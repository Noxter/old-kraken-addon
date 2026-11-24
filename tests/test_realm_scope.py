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

# --- Forever explicit scope ('Forever' when GetRealmName() == '') ---

# IsValidRealm('') remains strictly false, while GetRealmScope() returns 'Forever' for ''
lua_forever_gf = make_lua(GF_FILES, realm='', guild='Kraken', player='Alice')
trigger_login(lua_forever_gf)
lua_forever_gf.execute('''
    assert(OldKraken.Database:IsValidRealm('') == false, 'IsValidRealm("") must remain false')
    assert(OldKraken.Database:IsValidRealm(nil) == false, 'IsValidRealm(nil) must remain false')
    assert(OldKraken.Database:GetRealmScope() == 'Forever', 'GetRealmScope() must return Forever for empty GetRealmName()')
    assert(OldKraken.GroupFinder.active, 'GroupFinder must activate under Forever scope')
    local fKey = 'Forever\\001Kraken\\001Alice'
    assert(type(OldKraken.DB.groupFinder[fKey]) == 'table', 'Forever groupFinder scope must exist')
    assert(OldKraken.DB.groupFinder['\\001Kraken\\001Alice'] == nil, 'legacy empty-realm key must not be created')
    local ok, gid = OldKraken.GroupFinder:Create('Forever Group', 'dungeon', '', 5, 1, 60, 'dps')
    assert(ok and gid, 'GroupFinder:Create must succeed under Forever scope')
''')
# Switching to another realm ('Evermoon') with same guild & player isolates SavedVariables completely
lua_forever_gf.globals()._realm = 'Evermoon'
trigger_login(lua_forever_gf)
lua_forever_gf.execute('''
    local eKey = 'Evermoon\\001Kraken\\001Alice'
    assert(type(OldKraken.DB.groupFinder[eKey]) == 'table', 'Evermoon groupFinder scope must exist')
    assert(#(OldKraken.DB.groupFinder[eKey].records or {}) == 0, 'Forever records must not leak into Evermoon scope')
    assert(#(OldKraken.DB.groupFinder['Forever\\001Kraken\\001Alice'].records or {}) == 1, 'Forever records must stay intact')
''')

# GuildEvents under Forever scope + isolation from Evermoon with same guild & player
lua_forever_ge = make_lua(GE_FILES, realm='', guild='Kraken', player='Alice')
trigger_login(lua_forever_ge)
lua_forever_ge.execute('''
    local fKey = 'Forever\\001Kraken\\001Alice Tester'
    assert(type(OldKraken.DB.events.guildCalendarV1[fKey]) == 'table', 'Forever events scope must exist')
    assert(OldKraken.DB.events.guildCalendarV1['\\001Kraken\\001Alice Tester'] == nil, 'legacy empty-realm events key must not be created')
    assert(OldKraken.GuildEvents:Create('Forever Event', 'desc', now + 3600, 'raid', 10, ''), 'GuildEvents:Create must succeed under Forever scope')
''')
lua_forever_ge.globals()._realm = 'Evermoon'
trigger_login(lua_forever_ge)
lua_forever_ge.execute('''
    local fKey = 'Forever\\001Kraken\\001Alice Tester'
    local eKey = 'Evermoon\\001Kraken\\001Alice Tester'
    assert(type(OldKraken.DB.events.guildCalendarV1[eKey]) == 'table', 'Evermoon events scope must exist')
    assert(OldKraken.DB.events.guildCalendarV1[eKey].owned == nil, 'Forever event must not leak into Evermoon scope')
    assert(next(OldKraken.DB.events.guildCalendarV1[fKey].owned) ~= nil, 'Forever event must stay intact')
''')

# Alternative API priority & validation in Database.GetRealmScope()
lua_alt = make_lua(('Database.lua',), realm='', guild='Kraken', player='Alice')
lua_alt.execute('''
    local db = OldKraken.Database

    -- Valid GetNormalizedRealmName() takes precedence over GetCVar and 'Forever'
    GetNormalizedRealmName = function() return 'NormRealm' end
    GetCVar = function(k) return k == 'realmName' and 'CVarRealm' or nil end
    assert(db:GetRealmScope() == 'NormRealm', 'GetNormalizedRealmName should precede GetCVar')

    -- Empty or invalid GetNormalizedRealmName() falls through to valid GetCVar('realmName')
    GetNormalizedRealmName = function() return '' end
    assert(db:GetRealmScope() == 'CVarRealm', 'Valid GetCVar("realmName") should be used when normalized is empty')
    GetNormalizedRealmName = function() return 'Bad\\001Norm' end
    assert(db:GetRealmScope() == 'CVarRealm', 'Invalid GetNormalizedRealmName should fall through to GetCVar')

    -- Empty or invalid GetCVar('realmName') falls back to 'Forever'
    GetCVar = function(k) return k == 'realmName' and '' or nil end
    assert(db:GetRealmScope() == 'Forever', 'Empty GetCVar should fall back to Forever')
    GetCVar = function(k) return k == 'realmName' and 'Bad\\001CVar' or nil end
    assert(db:GetRealmScope() == 'Forever', 'Invalid GetCVar should fall back to Forever')

    -- Valid GetRealmName() always takes precedence over both alternatives
    _realm = 'PrimaryRealm'
    GetNormalizedRealmName = function() return 'NormRealm' end
    GetCVar = function() return 'CVarRealm' end
    assert(db:GetRealmScope() == 'PrimaryRealm', 'Valid GetRealmName should precede alternatives')
''')

print('test_realm_scope.py: ALL PASSED')
