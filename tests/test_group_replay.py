from pathlib import Path
from lupa.lua51 import LuaRuntime


root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute("""
OldKraken = {}
function GetTime() return 10 end
function GetServerTime() return 1700000000 end
""")
lua.execute((root / "GroupFinder.lua").read_text(encoding="utf-8"))
lua.execute(r"""
local model = OldKraken.GroupFinder
local sent = {}
model:Initialize('Owner Realm', function(kind, payload)
    sent[#sent + 1] = {kind=kind, payload=payload}
    return true
end)
assert(model:Create('Replay test', 'quest', '', 5, 1, 60, 'dps'))
local group
for _, value in pairs(model.groups) do group = value end
local id = group.id
local apply = model._pack({'Owner Realm', id, 'healer', 'apply', '1700000000001'})

-- The real CHAT_MSG_ADDON sender is the applicant identity. No applicant
-- identity is trusted from the payload.
assert(model:ReceiveJoin('Applicant Realm', apply))
assert(model.requests[id]['Applicant Realm'] == 'healer')
assert(model.requestVersions[id .. '\001' .. 'Applicant Realm'] == 1700000000001)

-- Simulate a restart: owner group and request-version high-water marks are
-- restored from SavedVariables, while transport-level duplicate cache is gone.
local savedGroup = model:EncodeGroup(group)
local savedVersions = {}
for key, value in pairs(model.requestVersions) do savedVersions[key] = value end
local restarted = setmetatable({}, {__index=model})
restarted:Initialize('Owner Realm', function() return true end)
restarted.requestVersions = savedVersions
assert(restarted:ReceiveGroup('Owner Realm', savedGroup))
assert(not restarted:ReceiveJoin('Applicant Realm', apply))

-- Removing the display/application record must not remove the version fence.
restarted.requests[id] = nil
assert(not restarted:ReceiveJoin('Applicant Realm', apply))

-- A different sender cannot submit an application as the previous applicant;
-- the actual sender becomes the key used for the request.
local forged = model._pack({'Owner Realm', id, 'tank', 'apply', '1700000000002'})
assert(restarted:ReceiveJoin('Mallory Realm', forged))
assert(restarted.requests[id]['Mallory Realm'] == 'tank')
assert(restarted.requests[id]['Applicant Realm'] == nil)

-- A spoofed group snapshot is rejected even when its payload claims the owner.
local remote = setmetatable({}, {__index=model})
remote:Initialize('Observer Realm', function() return true end)
assert(not remote:ReceiveGroup('Mallory Realm', savedGroup))
assert(remote:ReceiveGroup('Owner Realm', savedGroup))

-- Once the listing is closed, its tombstone becomes the replay barrier;
-- the per-applicant high-water marks can then be pruned safely.
assert(restarted:Cancel(id))
assert(restarted:Prune())
assert(restarted.requestVersions[id .. '\001' .. 'Applicant Realm'] == nil)
assert(not restarted:ReceiveJoin('Applicant Realm', apply))

""")
print("Group Finder replay and sender checks passed")
