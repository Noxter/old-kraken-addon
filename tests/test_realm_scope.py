from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def make_lua(files, realm='Evermoon', guild='Guild', player='Alice', secret_realm=False, with_db=True):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals()._realm = realm
    lua.globals()._guild = guild
    lua.globals()._player = player
    lua.globals()._secret_realm = secret_realm
    lua.execute('''
        now = 1700000000
        clock = 100
        timers = {}
        frames = {}
        cleared = 0
        handlers = {}
        OldKraken = {
            version = '0.5.5-alpha.1',
            events = {},
            UIStyle = {
                Colors = { brandGold = {0.88, 0.69, 0.32, 1} },
                Button = function() end,
                Window = function() end,
                Dropdown = function() end,
                Input = function() end,
            },
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
            ClearProtocolState = function() cleared = cleared + 1 end,
        }
        function print(...) end
        function UnitName() return _player, 'Tester' end
        function GetGuildInfo() return _guild end
        function GetRealmName() return _realm end
        function issecretvalue(v) return _secret_realm and v == _realm end
        function GetServerTime() return now end
        function GetTime() return clock end
        function IsInGroup() return false end
        function IsInRaid() return false end
        function GetNumGroupMembers() return 0 end
        UIParent = {}
        UISpecialFrames = {}
        StaticPopupDialogs = {}
        local methods = {}
        function methods:SetScript(k, fn) self.scripts[k] = fn end
        function methods:RegisterEvent(ev) self.events[ev] = true end
        function methods:Show() self.shown = true end
        function methods:Hide() self.shown = false end
        function methods:IsShown() return self.shown end
        function methods:CreateFontString() return CreateFrame() end
        function methods:CreateTexture() return CreateFrame() end
        function methods:GetFontString() return CreateFrame() end
        local meta = { __index = function(_, k) return methods[k] or function() end end }
        function CreateFrame(_, name, parent)
            local f = setmetatable({ scripts = {}, events = {}, parent = parent }, meta)
            if name then _G[name] = f end
            frames[#frames + 1] = f
            return f
        end
        C_Timer = {
            After = function(_, fn) fn() end,
            NewTicker = function(_, fn) timers[#timers + 1] = fn; return {} end,
        }
        OldKrakenDB = {}
    ''')
    for name in files:
        lua.execute((ROOT / name).read_text(encoding='utf-8'))
    if with_db:
        lua.execute('OldKraken.Database.Initialize()')
    else:
        lua.execute('OldKraken.DB = { groupFinder = {}, events = { guildCalendarV1 = {} } }')
    return lua


def trigger_login(lua):
    lua.execute('''
        for _, f in ipairs(frames) do
            if f.events['PLAYER_LOGIN'] and f.scripts['OnEvent'] then
                f.scripts['OnEvent'](f, 'PLAYER_LOGIN')
            end
        end
    ''')


def tick_all(lua):
    lua.execute('''
        for _, fn in ipairs(timers) do
            fn()
        end
    ''')


GF_FILES = ('Database.lua', 'Locale.lua', 'GroupFinder.lua', 'GroupFinderIntegration.lua')
GF_FALLBACK_FILES = ('Locale.lua', 'GroupFinder.lua', 'GroupFinderIntegration.lua')
GE_FILES = ('Database.lua', 'Locale.lua', 'ActivityCatalog.lua', 'GroupFinder.lua', 'GuildEvents.lua')
GE_FALLBACK_FILES = ('Locale.lua', 'ActivityCatalog.lua', 'GroupFinder.lua', 'GuildEvents.lua')

BAD_REALMS = [
    ('', False),
    (None, False),
    (123, False),
    ('Bad\001Realm', False),
    ('R' * 129, False),
    ('SecretRealm', True),
]


# --- GroupFinderIntegration tests ---

for with_db in (True, False):
    files = GF_FILES if with_db else GF_FALLBACK_FILES
    for bad_realm, is_secret in BAD_REALMS:
        lua = make_lua(files, realm=bad_realm, secret_realm=is_secret, with_db=with_db)
        trigger_login(lua)
        lua.execute('''
            assert(not OldKraken.GroupFinder.active, 'GroupFinder must stay inactive on invalid realm')
            assert(next(OldKraken.DB.groupFinder) == nil, 'invalid realm must not create groupFinder scope')
        ''')

lua = make_lua(GF_FILES, realm='Evermoon', guild='Guild', player='Alice')
trigger_login(lua)
lua.execute('''
    assert(OldKraken.GroupFinder.active, 'GroupFinder must activate on valid realm')
    local expected = 'Evermoon' .. '\\001' .. 'Guild' .. '\\001' .. 'Alice'
    assert(type(OldKraken.DB.groupFinder[expected]) == 'table', 'canonical groupFinder profile must exist')
    local ok = OldKraken.GroupFinder:Create('Test Group', 'dungeon', '', 5, 1, 60, 'dps')
    assert(ok, 'GroupFinder:Create must succeed on valid realm')
''')

for bad_realm, is_secret in BAD_REALMS:
    lua.globals()._realm = bad_realm
    lua.globals()._secret_realm = is_secret
    tick_all(lua)
    lua.execute('''
        assert(not OldKraken.GroupFinder.active, 'GroupFinder must deactivate when realm becomes invalid')
        for k in pairs(OldKraken.DB.groupFinder) do
            assert(k == 'Evermoon\\001Guild\\001Alice', 'unexpected groupFinder key: ' .. tostring(k))
        end
    ''')
    lua.globals()._realm = 'Evermoon'
    lua.globals()._secret_realm = False
    trigger_login(lua)
    lua.execute('''
        assert(OldKraken.GroupFinder.active, 'GroupFinder must reconnect when valid realm returns')
        for k in pairs(OldKraken.DB.groupFinder) do
            assert(k == 'Evermoon\\001Guild\\001Alice', 'unexpected groupFinder key after reconnect: ' .. tostring(k))
        end
    ''')


# --- GuildEvents tests ---

for with_db in (True, False):
    files = GE_FILES if with_db else GE_FALLBACK_FILES
    for bad_realm, is_secret in BAD_REALMS:
        lua = make_lua(files, realm=bad_realm, secret_realm=is_secret, with_db=with_db)
        trigger_login(lua)
        lua.execute('''
            local ok = OldKraken.GuildEvents:Create('Raid', 'Desc', now + 3600, 'raid', 10, '')
            assert(not ok, 'GuildEvents must stay inactive on invalid realm')
            local cal = OldKraken.DB.events.guildCalendarV1
            assert(cal == nil or next(cal) == nil, 'invalid realm must not create guildCalendarV1 scope')
        ''')

lua = make_lua(GE_FILES, realm='Evermoon', guild='Guild', player='Alice')
trigger_login(lua)
lua.execute('''
    local expected = 'Evermoon' .. '\\001' .. 'Guild' .. '\\001' .. 'Alice Tester'
    assert(type(OldKraken.DB.events.guildCalendarV1[expected]) == 'table', 'canonical guildCalendarV1 profile must exist')
    local ok = OldKraken.GuildEvents:Create('Raid Night', 'Desc', now + 3600, 'raid', 10, '')
    assert(ok, 'GuildEvents:Create must succeed on valid realm')
''')

for bad_realm, is_secret in BAD_REALMS:
    lua.globals()._realm = bad_realm
    lua.globals()._secret_realm = is_secret
    tick_all(lua)
    lua.execute('''
        local ok = OldKraken.GuildEvents:Create('Blocked', 'Desc', now + 3600, 'raid', 10, '')
        assert(not ok, 'GuildEvents must deactivate when realm becomes invalid')
        for k in pairs(OldKraken.DB.events.guildCalendarV1) do
            assert(k == 'Evermoon\\001Guild\\001Alice Tester', 'unexpected guildCalendarV1 key: ' .. tostring(k))
        end
    ''')
    lua.globals()._realm = 'Evermoon'
    lua.globals()._secret_realm = False
    tick_all(lua)
    lua.execute('''
        local ok = OldKraken.GuildEvents:Create('Raid Night 2', 'Desc', now + 7200, 'raid', 10, '')
        assert(ok, 'GuildEvents must reconnect via ticker when valid realm returns')
        for k in pairs(OldKraken.DB.events.guildCalendarV1) do
            assert(k == 'Evermoon\\001Guild\\001Alice Tester', 'unexpected guildCalendarV1 key after reconnect: ' .. tostring(k))
        end
    ''')

print('test_realm_scope.py: ALL PASSED')
