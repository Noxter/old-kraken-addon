from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
    handlers = {}
    frames = {}
    timers = {}
    OldKraken = {
        DB = {
            events = { guildCalendarV1 = {} },
            groupFinder = {},
            settings = {},
        },
        events = {},
    }
    function OldKraken:On() end
    function OldKraken:Fire(name) self.events[name] = (self.events[name] or 0) + 1 end
    function OldKraken:Print() end
    function OldKraken:PrintError() end
    OldKraken.Communication = {
        queue = {},
        RegisterHandler = function(_, kind, fn) handlers[kind] = fn end,
        SendProtocol = function() return true end,
        RequestSync = function() return true end,
        ClearProtocolState = function() end,
    }
    function UnitName() return 'Alice', 'Tester' end
    function GetRealmName() return 'Evermoon' end
    function GetGuildInfo() return 'Kraken' end
    function GetServerTime() return 1700000000 end
    function GetTime() return 100 end
    function IsInGroup() return false end
    function IsInRaid() return false end
    function GetNumGroupMembers() return 0 end
    UIParent = {}
    UISpecialFrames = {}
    StaticPopupDialogs = {}
    local meta = { __index = function() return function() end end }
    function CreateFrame()
        local f = setmetatable({ scripts = {}, events = {} }, meta)
        function f:SetScript(k, fn) self.scripts[k] = fn end
        function f:RegisterEvent(ev) self.events[ev] = true end
        frames[#frames + 1] = f
        return f
    end
    C_Timer = {
        After = function(_, fn) fn() end,
        NewTicker = function(_, fn) timers[#timers + 1] = fn; return {} end,
    }
''')

for name in ('Locale.lua', 'ActivityCatalog.lua', 'GroupFinder.lua', 'GuildEvents.lua'):
    lua.execute((ROOT / name).read_text(encoding='utf-8'))

lua.execute('''
    local gf = OldKraken.GroupFinder
    gf:Initialize('Alice Tester', function() return true end)

    -- Simulate v0.5.4 ActivityCatalog (without new wing IDs) against incoming new wing IDs
    local catalog = OldKraken.ActivityCatalog
    local newWings = {
        'ubrs',
        'sm-graveyard', 'sm-library', 'sm-armory', 'sm-cathedral',
        'dm-east', 'dm-west', 'dm-north',
        'strat-live', 'strat-undead',
        'mara-purple', 'mara-orange', 'mara-princess',
    }
    local newSet = {}
    for _, id in ipairs(newWings) do newSet[id] = true end

    local v054Dungeon = {}
    for _, entry in ipairs(catalog.dungeon) do
        if not newSet[entry.value] then
            v054Dungeon[#v054Dungeon + 1] = entry
        end
    end

    -- Under v0.5.4 catalog, IsValidActivity('dungeon', wingId) is false for new wing IDs
    local function v054ValidActivity(kind, id)
        if id == '' then return true end
        for _, entry in ipairs(v054Dungeon) do
            if entry.value == id then return true end
        end
        return false
    end

    for _, wingId in ipairs(newWings) do
        assert(catalog.IsValidActivity('dungeon', wingId) == true, 'current catalog must accept ' .. wingId)
        assert(v054ValidActivity('dungeon', wingId) == false, 'v0.5.4 catalog must reject ' .. wingId)
    end

    -- GroupFinder preserves groups with unknown/future dungeon IDs (losing only label lookup)
    local sender = setmetatable({}, { __index = gf })
    sender:Initialize('Bob Tester', function() return true end)
    assert(sender:Create('UBRS Run', 'dungeon', 'LFM', 5, 58, 60, 'dps', 'ubrs'))
    local created
    for _, g in pairs(sender.groups) do created = g end
    assert(gf:ReceiveGroup('Bob Tester', sender:EncodeGroup(created)) == true)
    assert(gf.groups['Bob Tester\\001' .. created.id].dungeon == 'ubrs')
''')

print('Mixed-version activity checks passed')
