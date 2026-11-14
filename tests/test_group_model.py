from pathlib import Path
from lupa.lua51 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('OldKraken = {}; now = 10; function GetTime() return now end; function GetServerTime() return 1234567890 end')
lua.execute((Path(__file__).resolve().parents[1] / 'GroupFinder.lua').read_text(encoding='utf-8'))
lua.execute('''
local model = OldKraken.GroupFinder
local sent = {}
model:Initialize('Alice-Realm', function(kind, payload) sent[#sent+1] = {kind,payload}; return true end)
assert(model:Create('Печера', 'dungeon', 'Рівень 20+', 5, 1, 60, 'tank'))
local group
for _, g in pairs(model.groups) do group = g end
assert(group and group.owner == 'Alice-Realm')
local snapshot = model:EncodeGroup(group)
local clone = {}
setmetatable(clone, {__index = model})
clone:Initialize('Bob-Realm', function() return true end)
assert(not clone:ReceiveGroup('Mallory-Realm', snapshot))
assert(clone:ReceiveGroup('Alice-Realm', snapshot))
assert(not clone:ReceiveGroup('Alice-Realm', snapshot))
now = 100
assert(not clone:ReceiveGroup('Alice-Realm', snapshot))
assert(clone.groups['Alice-Realm' .. '\\001' .. group.id].seenAt == 100)
clone.pending['Alice-Realm' .. '\\001' .. group.id] = 'pending'
assert(model:ReceiveJoin('Bob-Realm', model._pack({'Alice-Realm', group.id, 'healer', 'apply', '1234567890001'})))
assert(model:ReceiveJoin('Eve-Realm', model._pack({'Alice-Realm', group.id, '', 'withdraw', '1234567890002'})))
assert(not model:ReceiveJoin('Eve-Realm', model._pack({'Alice-Realm', group.id, '', 'apply', '1234567890001'})))
assert(model:Decide(group.id, 'Bob-Realm', true))
assert(#group.members == 2 and group.revision == 2)
assert(clone:ReceiveGroup('Alice-Realm', model:EncodeGroup(group)))
assert(clone.pending['Alice-Realm' .. '\\001' .. group.id] == nil)
assert(not clone:ReceiveGroup('Mallory-Realm', model:EncodeGroup(group)))
assert(not model:ReceiveJoin('Mallory-Realm', 'garbage'))
local blocked, attempts = true, 0
model.send = function(kind, payload)
    if kind == 'SYNC' then attempts = attempts + 1; return not blocked end
    return true
end
model:OnQuery()
assert(not model:SyncStep() and attempts == 1)
blocked = false
assert(model:SyncStep() and attempts == 2)
assert(model:SyncStep() and attempts == 2)
assert(model:Cancel(group.id))
assert(clone:ReceiveGroup('Alice-Realm', model:EncodeGroup(group)))
assert(clone.groups['Alice-Realm' .. '\\001' .. group.id].closed)
assert(not clone:ReceiveGroup('Alice-Realm', snapshot))
now = 4000
clone:Prune()
assert(clone.groups['Alice-Realm' .. '\\001' .. group.id] == nil)
''')
print('Group model checks passed')
