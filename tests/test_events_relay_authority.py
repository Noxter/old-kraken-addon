from pathlib import Path

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]


def make_runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r"""
OldKraken = {
    DB = {events = {}, settings = {}},
    _listeners = {},
    Communication = {handlers = {}},
    GroupFinder = {},
}
StaticPopupDialogs = {}
function OldKraken:On(name, callback)
    self._listeners[name] = self._listeners[name] or {}
    table.insert(self._listeners[name], callback)
end
function OldKraken:Fire(name, ...)
    for _, callback in ipairs(self._listeners[name] or {}) do callback(...) end
end
function OldKraken.Communication:RegisterHandler(kind, callback)
    self.handlers[kind] = callback
end
function OldKraken.Communication:SendProtocol() return true end
function OldKraken.GroupFinder._pack(fields)
    local out = {}
    for _, value in ipairs(fields) do
        value = tostring(value)
        out[#out + 1] = #value .. ':' .. value
    end
    return table.concat(out)
end
function OldKraken.GroupFinder._unpackFields(payload, maxFields)
    if type(payload) ~= 'string' or #payload > 2560 then return nil end
    local fields, pos = {}, 1
    while pos <= #payload do
        if #fields >= maxFields then return nil end
        local first, last, size = payload:find('(%d+):', pos)
        if first ~= pos or not last then return nil end
        size = tonumber(size)
        pos = last + 1
        if size > #payload - pos + 1 then return nil end
        fields[#fields + 1] = payload:sub(pos, pos + size - 1)
        pos = pos + size
    end
    return fields
end
function UnitName() return 'Tester', 'Realm' end
function GetGuildInfo() return 'Guild' end
function GetRealmName() return 'Test Realm' end
function GetServerTime() return 2000000000 end
function GetTime() return 10 end
function print() end
local frameMethods = {}
function frameMethods:RegisterEvent() end
function frameMethods:SetScript(name, callback) self.scripts[name] = callback end
local frameMeta = {__index=frameMethods}
createdFrames = {}
function CreateFrame()
    local frame = setmetatable({scripts={}}, frameMeta)
    createdFrames[#createdFrames + 1] = frame
    return frame
end
""")
    lua.execute((ROOT / "ActivityCatalog.lua").read_text(encoding="utf-8"))
    lua.execute((ROOT / "GuildEvents.lua").read_text(encoding="utf-8"))
    lua.execute(r"""
for _, frame in ipairs(createdFrames) do
    if frame.scripts.OnEvent then frame.scripts.OnEvent(frame, 'PLAYER_LOGIN') end
end
local function eventPayload(revision, cancelled, role, status)
    return OldKraken.GroupFinder._pack({
        '1999999900-123456-1', 'Owner Realm', revision, 2000003600,
        'raid', 10, cancelled and '1' or '0', 'Test event', '', 1,
        'Tester Realm', role or 'dps', '', status or 'A'
    })
end
makePayload = eventPayload
""")
    return lua


def storage_for(lua):
    return lua.eval("OldKraken.DB.events.guildCalendarV1['Test Realm\\001Guild\\001Tester Realm']")


def test_relay_does_not_overwrite_last_direct_snapshot():
    lua = make_runtime()
    lua.execute(r"""
local handlers = OldKraken.Communication.handlers
local direct = makePayload(1, false, 'dps', 'A')
handlers.CEVENT('Owner Realm', 'direct-1', direct)
local relay = makePayload(9, false, 'tank', 'P')
handlers.CVSTATE('Relay Realm', 'relay-9', relay)
""")
    store = storage_for(lua)
    assert store["observed"]["Owner Realm\0011999999900-123456-1"]["rev"] == 1
    assert store["observed"]["Owner Realm\0011999999900-123456-1"]["people"]["Tester Realm"] == "dps"
    assert store["relays"]["Owner Realm\0011999999900-123456-1"] is not None


def test_newer_direct_snapshot_supersedes_higher_untrusted_relay_revision():
    lua = make_runtime()
    lua.execute(r"""
local handlers = OldKraken.Communication.handlers
handlers.CEVENT('Owner Realm', 'direct-1', makePayload(1, false, 'dps', 'A'))
handlers.CVSTATE('Relay Realm', 'relay-9', makePayload(9, false, 'tank', 'P'))
handlers.CEVENT('Owner Realm', 'direct-2', makePayload(2, false, 'healer', 'A'))
""")
    store = storage_for(lua)
    key = "Owner Realm\0011999999900-123456-1"
    assert store["observed"][key]["rev"] == 2
    assert store["observed"][key]["people"]["Tester Realm"] == "healer"
    assert store["relays"][key] is None


def test_relayed_cancellation_never_emits_cancellation_notification():
    lua = make_runtime()
    lua.execute(r"""
cancelledAlerts = 0
OldKraken:On('GUILD_EVENTS_CANCELLED', function() cancelledAlerts = cancelledAlerts + 1 end)
local handlers = OldKraken.Communication.handlers
handlers.CEVENT('Owner Realm', 'direct-1', makePayload(1, false, 'dps', 'A'))
handlers.CVSTATE('Relay Realm', 'relay-cancel', makePayload(2, true, 'dps', 'A'))
""")
    assert lua.eval("cancelledAlerts") == 0
    assert lua.eval("OldKraken.GuildEvents:GetRelayDiagnostics().rejected_relay_cancelled") == 1


def test_relay_only_event_is_display_only_and_cannot_create_signup_intent():
    lua = make_runtime()
    lua.execute(r"""
local payload = makePayload(1, false, 'dps', 'A')
OldKraken.Communication.handlers.CVSTATE('Relay Realm', 'relay-1', payload)
local key = 'Owner Realm\0011999999900-123456-1'
signupResult = OldKraken.GuildEvents:Signup(key, 'healer')
""")
    store = storage_for(lua)
    assert lua.eval("signupResult") is False
    # A relay-only event never writes a direct snapshot, so the whole container may be
    # absent; the invariant to hold is that no observed entry exists for the key.
    observed = store["observed"]
    assert observed is None or observed["Owner Realm\0011999999900-123456-1"] is None
    assert store["relays"]["Owner Realm\0011999999900-123456-1"] is not None


def test_payload_owner_cannot_impersonate_direct_sender():
    lua = make_runtime()
    lua.execute(r"""
OldKraken.Communication.handlers.CEVENT('Relay Realm', 'forged-direct',
    makePayload(1, false, 'dps', 'A'))
""")
    store = storage_for(lua)
    assert store["observed"] is None or store["observed"]["Owner Realm\0011999999900-123456-1"] is None
    assert lua.eval("OldKraken.GuildEvents:GetRelayDiagnostics().invalid_payload") == 1


if __name__ == "__main__":
    test_relay_does_not_overwrite_last_direct_snapshot()
    test_newer_direct_snapshot_supersedes_higher_untrusted_relay_revision()
    test_relayed_cancellation_never_emits_cancellation_notification()
    test_relay_only_event_is_display_only_and_cannot_create_signup_intent()
    test_payload_owner_cannot_impersonate_direct_sender()
    print("Relay authority checks passed")
