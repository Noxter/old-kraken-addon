from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
FILES = (
    'Database.lua',
    'Locale.lua',
    'GroupFinder.lua',
    'Workshop.lua',
    'WorkshopRecipes.lua',
    'WorkshopSync.lua',
    'WorkshopOrders.lua',
)
SOURCES = [(ROOT / name).read_text(encoding='utf-8') for name in FILES]


def make_client(realm='Realm', guild='Guild', player='Alice', secret_realm=False):
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
        notices = {}
        handlers = {}
        OldKraken = {
            version = '0.5.5-alpha.1',
            UIStyle = {
                Colors = { brandGold = {0.88, 0.69, 0.32, 1} },
                Button = function() end,
                Window = function() end,
                Dropdown = function() end,
                Input = function() end,
            },
        }
        function OldKraken:On() end
        function OldKraken:Fire(...) notices[#notices + 1] = {...} end
        function OldKraken:RegisterComm() end
        OldKraken.Communication = {
            queue = {},
            RegisterHandler = function(_, kind, fn) handlers[kind] = fn end,
            SendProtocol = function() return true end,
        }
        function print(...) end
        function UnitName() return _player, 'Tester' end
        function GetGuildInfo() return _guild end
        function GetRealmName() return _realm end
        function issecretvalue(v) return _secret_realm and v == _realm end
        function GetServerTime() return now end
        function GetTime() return clock end
        function date() return 'date' end
        function GetProfessions() return nil end
        function GetProfessionInfo() return nil end
        function IsLoggedIn() return true end
        function UnitExists() return true end
        UIParent = {}
        UISpecialFrames = {}
        StaticPopupDialogs = {}
        function UIDropDownMenu_SetWidth() end
        function UIDropDownMenu_SetText() end
        function UIDropDownMenu_Initialize() end
        function UIDropDownMenu_CreateInfo() return {} end
        function UIDropDownMenu_AddButton() end
        function CloseDropDownMenus() end
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
    for src in SOURCES:
        lua.execute(src)
    lua.execute('OldKraken.Database.Initialize()')
    return lua


def trigger_connect(lua):
    lua.execute('''
        for _, f in ipairs(frames) do
            if f.events['PLAYER_GUILD_UPDATE'] and f.scripts['OnEvent'] then
                f.scripts['OnEvent'](f, 'PLAYER_GUILD_UPDATE')
            end
        end
    ''')


# 1. Invalid realms (empty, nil, number, secret, control char, >128 chars) must never create "\001Guild"
for bad_realm, is_secret in [('', False), (None, False), (123, False), ('Bad\001Realm', False), ('R' * 129, False), ('SecretRealm', True)]:
    lua = make_client(realm=bad_realm, secret_realm=is_secret)
    trigger_connect(lua)
    lua.execute('''
        assert(OldKraken.DB.workshop.guilds == nil or next(OldKraken.DB.workshop.guilds) == nil,
            'invalid realm created workshop guild scope')
    ''')

# 2. Valid realm connects all 4 modules to the exact same canonical scope
lua = make_client(realm='Evermoon', guild='Kraken')
trigger_connect(lua)
lua.execute('''
    local guilds = OldKraken.DB.workshop.guilds
    assert(guilds['\\001Kraken'] == nil, 'unexpected legacy scope')
    local scope = guilds['Evermoon\\001Kraken']
    assert(type(scope) == 'table', 'missing canonical scope')
    assert(type(scope.records) == 'table', 'Workshop did not connect')
    assert(type(scope.recipes) == 'table', 'WorkshopRecipes did not connect')
    assert(type(scope.recipeDirectSnapshots) == 'table', 'WorkshopSync did not connect')
    assert(type(scope.orderOwners) == 'table', 'WorkshopOrders did not connect')
    assert(next(scope.orderActionRelays) == nil and next(scope.orderPaymentRelays) == nil)
''')

# 3. Legacy scope without confirmation must NOT auto-migrate or modify legacy data
lua = make_client(realm='Evermoon', guild='Kraken', player='Alice')
lua.execute('''
    OldKraken.DB.workshop.guilds = {
        ['\\001Kraken'] = {
            orderDrafts = {
                ['Alice Tester'] = { item = 'Flask', quantity = '5', note = 'urgent', profession = 171, materials = 'customer', deadline = 86400 },
            },
            orderOwners = {
                ['Alice Tester'] = {
                    ['Alice Tester\\001ord1'] = { owner = 'Alice Tester', id = 'ord1', rev = 2, created = 100, deadline = 200, profession = 171, item = 'Flask', itemID = 0, recipeID = 0, quantity = 5, reward = 10, rewardSilver = 0, materials = 'customer', note = 'legacy', status = 'open', candidates = {}, acks = {} },
                },
            },
        },
    }
''')
trigger_connect(lua)
lua.execute('''
    local guilds = OldKraken.DB.workshop.guilds
    assert(guilds['\\001Kraken'].orderDrafts['Alice Tester'].item == 'Flask', 'legacy data modified')
    local canon = guilds['Evermoon\\001Kraken']
    assert(canon.orderDrafts['Alice Tester'] == nil, 'draft auto-migrated without confirmation')
    assert(canon.orderOwners['Alice Tester']['Alice Tester\\001ord1'] == nil, 'order auto-migrated without confirmation')
    local meta = OldKraken.DB.workshop.legacyMigrations['\\001Kraken']
    assert(meta.pendingConfirmation['Evermoon\\001Kraken'] == true, 'missing addressable pendingConfirmation')
''')

# 4. Explicit confirmation migrates for RealmA while keeping legacy scope intact for RealmB
lua.execute('''
    local ok, status = OldKraken.Database:ConfirmWorkshopMigration()
    assert(ok == true and status == 'completed', 'expected completed migration')
    local guilds = OldKraken.DB.workshop.guilds
    assert(guilds['Evermoon\\001Kraken'].orderDrafts['Alice Tester'].item == 'Flask')
    assert(guilds['Evermoon\\001Kraken'].orderOwners['Alice Tester']['Alice Tester\\001ord1'].rev == 2)
    assert(guilds['\\001Kraken'] ~= nil and guilds['\\001Kraken'].orderDrafts['Alice Tester'].item == 'Flask', 'legacy scope must remain intact')
    local ok2, status2 = OldKraken.Database:MigrateWorkshopScope('Evermoon', 'Kraken', true)
    assert(ok2 == true and status2 == 'completed')
''')
lua.globals()._realm = 'Frostmourne'
trigger_connect(lua)
lua.execute('''
    local meta = OldKraken.DB.workshop.legacyMigrations['\\001Kraken']
    assert(meta.pendingConfirmation['Frostmourne\\001Kraken'] == true, 'second realm must get its own pendingConfirmation')
    local ok, status = OldKraken.Database:ConfirmWorkshopMigration()
    assert(ok == true and status == 'completed')
    assert(OldKraken.DB.workshop.guilds['Frostmourne\\001Kraken'].orderDrafts['Alice Tester'].item == 'Flask')
''')

# 5. Conflicts with equal versions (orderOwners, orderDrafts, orderDeliveryTallies, recipeSnapshotViews) + interrupted recovery
lua = make_client(realm='Evermoon', guild='Kraken', player='Alice')
lua.execute('''
    local id = 'Alice Tester'
    local okKey = id .. '\\001ord1'
    OldKraken.DB.workshop.guilds = {
        ['\\001Kraken'] = {
            orderOwners = {
                [id] = {
                    [okKey] = { owner = id, id = 'ord1', rev = 3, created = 100, deadline = 200, profession = 171, item = 'Flask', itemID = 0, recipeID = 0, quantity = 5, reward = 10, rewardSilver = 0, materials = 'customer', note = 'legacy-completed', status = 'completed', candidates = {'A', 'B'}, acks = {} },
                },
            },
            orderDrafts = {
                [id] = { item = 'Legacy Elixir', quantity = '2', reward = '0', rewardSilver = '0', note = 'legacy note', profession = 171, materials = 'customer', deadline = 86400 },
            },
            orderDeliveryTallies = {
                [id] = {
                    [okKey] = { worker = 'Bob Tester', assignment = 1, materials = { [1001] = 4 }, items = 2, money = 500 },
                    [id .. '\\001bad'] = { worker = 'Bob Tester', assignment = 1, materials = { [1001] = -5 }, items = 999, money = 100 },
                    [id .. '\\001diffw'] = { worker = 'Carl Tester', assignment = 2, materials = {}, items = 1, money = 0 },
                },
            },
            recipeSnapshotViews = {
                ['Bob Tester'] = { rev = 10, directRev = 10, relayed = false },
            },
        },
        ['Evermoon\\001Kraken'] = {
            orderOwners = {
                [id] = {
                    [okKey] = { owner = id, id = 'ord1', rev = 3, created = 100, deadline = 200, profession = 171, item = 'Flask', itemID = 0, recipeID = 0, quantity = 5, reward = 10, rewardSilver = 0, materials = 'customer', note = 'canon-open', status = 'open', candidates = {}, acks = {} },
                },
            },
            orderDrafts = {
                [id] = { item = 'Canon Potion', quantity = '1', reward = '0', rewardSilver = '0', note = '', profession = 171, materials = 'customer', deadline = 86400 },
            },
            orderDeliveryTallies = {
                [id] = {
                    [okKey] = { worker = 'Bob Tester', assignment = 1, materials = { [1001] = 2, [1002] = 3 }, items = 4, money = 200 },
                    [id .. '\\001diffw'] = { worker = 'Dan Tester', assignment = 2, materials = {}, items = 3, money = 0 },
                },
            },
            recipeSnapshotViews = {
                ['Bob Tester'] = { rev = 10, directRev = 5, relayed = true },
            },
        },
    }
    OldKraken.DB.workshop.legacyMigrations = {
        ['\\001Kraken'] = {
            inProgress = { ['Evermoon\\001Kraken'] = true },
            status = {},
            pendingConfirmation = { ['Evermoon\\001Kraken'] = true },
        },
    }
    local ok, status = OldKraken.Database:ConfirmWorkshopMigration()
    assert(ok == true and status == 'completed')
    local canon = OldKraken.DB.workshop.guilds['Evermoon\\001Kraken']
    -- orderOwners conflict: canonical remains active despite legacy being 'completed' with more candidates
    assert(canon.orderOwners[id][okKey].status == 'open')
    assert(canon.migrationConflicts['orderOwners\\001' .. id .. '\\001' .. okKey] ~= nil)
    -- orderDrafts conflict: canonical remains active, both saved
    assert(canon.orderDrafts[id].item == 'Canon Potion')
    assert(canon.migrationConflicts['orderDrafts\\001' .. id].legacy.item == 'Legacy Elixir')
    -- tallies: same worker+assignment uses component-wise max without summing; invalid tally excluded; diff worker keeps canonical
    local t = canon.orderDeliveryTallies[id][okKey]
    assert(t.items == 4 and t.money == 500 and t.materials[1001] == 4 and t.materials[1002] == 3)
    assert(canon.orderDeliveryTallies[id][id .. '\\001bad'] == nil, 'invalid tally must not enter active scope')
    assert(canon.orderDeliveryTallies[id][id .. '\\001diffw'].worker == 'Dan Tester' and canon.orderDeliveryTallies[id][id .. '\\001diffw'].items == 3)
    -- recipeSnapshotViews invariant: direct view wins when rev is equal
    local v = canon.recipeSnapshotViews['Bob Tester']
    assert(v.rev == 10 and v.directRev == 10 and v.relayed == false)
    -- inProgress cleared
    assert(OldKraken.DB.workshop.legacyMigrations['\\001Kraken'].inProgress['Evermoon\\001Kraken'] == nil)
''')

# 6. Overflow at MAX_MIGRATION_CONFLICTS = 200 -> completedWithOverflow & source intact
lua = make_client(realm='Evermoon', guild='Kraken', player='Alice')
lua.execute('''
    local id = 'Alice Tester'
    local srcOwners, tgtOwners = {}, {}
    for i = 1, 205 do
        local k = id .. '\\001ord' .. i
        srcOwners[k] = { owner = id, id = 'ord' .. i, rev = 1, item = 'S' .. i, quantity = 1, reward = 0, status = 'open', candidates = {}, acks = {} }
        tgtOwners[k] = { owner = id, id = 'ord' .. i, rev = 1, item = 'T' .. i, quantity = 1, reward = 0, status = 'open', candidates = {}, acks = {} }
    end
    OldKraken.DB.workshop.guilds = {
        ['\\001Kraken'] = { orderOwners = { [id] = srcOwners } },
        ['Evermoon\\001Kraken'] = { orderOwners = { [id] = tgtOwners } },
    }
    OldKraken.Database:MigrateWorkshopScope('Evermoon', 'Kraken', false)
    local ok, status = OldKraken.Database:ConfirmWorkshopMigration()
    assert(ok == true and status == 'completedWithOverflow', 'expected completedWithOverflow, got ' .. tostring(status))
    local canon = OldKraken.DB.workshop.guilds['Evermoon\\001Kraken']
    assert(canon.migrationConflictsOverflow == true)
    local count = 0
    for _ in pairs(canon.migrationConflicts) do count = count + 1 end
    assert(count == 200, 'conflict count must cap at 200')
    assert(OldKraken.DB.workshop.guilds['\\001Kraken'] ~= nil, 'source must remain intact on overflow')
    local okAgain, statusAgain = OldKraken.Database:MigrateWorkshopScope('Evermoon', 'Kraken', false)
    assert(okAgain == true and statusAgain == 'completedWithOverflow')
''')

print('Workshop migration checks passed')
