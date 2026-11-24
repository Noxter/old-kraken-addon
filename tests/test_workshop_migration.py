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


# 1. Invalid realms (nil, number, secret, control char, >128 chars) must never create "\001Guild"
for bad_realm, is_secret in [(None, False), (123, False), ('Bad\001Realm', False), ('R' * 129, False), ('SecretRealm', True)]:
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
                    ['Alice Tester\\001ord1'] = { owner = 'Alice Tester', id = 'ord1', rev = 2, created = now, deadline = now+100, profession = 171, item = 'Flask', itemID = 0, recipeID = 0, quantity = 5, reward = 10, rewardSilver = 0, materials = 'customer', note = 'legacy', status = 'open', candidates = {}, acks = {} },
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
    assert(canon.migrationPendingTallies[id][id .. '\\001diffw'].worker == 'Dan Tester' and canon.migrationPendingTallies[id][id .. '\\001diffw'].items == 3)
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

# 7. Direct confirmed=true call without a pending marker must not migrate
lua = make_client(realm='Evermoon', guild='Kraken', player='Alice')
lua.execute('''
    OldKraken.DB.workshop.guilds = {
        ['\\001Kraken'] = { orderSequences = { ['Alice Tester'] = 42 } },
    }
    local ok, status = OldKraken.Database:MigrateWorkshopScope('Evermoon', 'Kraken', true)
    assert(ok == false and status == 'unconfirmed', 'confirmed=true without pending marker must be refused, got ' .. tostring(status))
    local canon = OldKraken.DB.workshop.guilds['Evermoon\\001Kraken']
    assert(canon == nil or canon.orderSequences == nil, 'refused call must not touch canonical scope')
    local meta = OldKraken.DB.workshop.legacyMigrations['\\001Kraken']
    assert(meta.status['Evermoon\\001Kraken'] == nil and meta.inProgress['Evermoon\\001Kraken'] == nil)
    -- the proper two-step path still works
    assert(select(2, OldKraken.Database:MigrateWorkshopScope('Evermoon', 'Kraken', false)) == 'pending')
    local ok2, status2 = OldKraken.Database:MigrateWorkshopScope('Evermoon', 'Kraken', true)
    assert(ok2 == true and status2 == 'completed')
    assert(OldKraken.DB.workshop.guilds['Evermoon\\001Kraken'].orderSequences['Alice Tester'] == 42)
    assert(meta.pendingConfirmation['Evermoon\\001Kraken'] == nil, 'pending marker is cleared only on completion')
''')

# 8. Missing canonical order but present legacy order: tally limits use the legacy quantity
lua = make_client(realm='Evermoon', guild='Kraken', player='Alice')
lua.execute('''
    local id = 'Alice Tester'
    local k = 'Carol Tester\\001ord7'
    OldKraken.DB.workshop.guilds = {
        ['\\001Kraken'] = {
            orderObserved = { [k] = { owner = 'Carol Tester', id = 'ord7', rev = 1, ownerRev = 1, created = now, deadline = now+100, profession = 171, item = 'Flask', materials = 'customer', note = '', reward = 0, quantity = 3, status = 'assigned', worker = id, candidates = {}, acks = {} } },
            orderDeliveryTallies = { [id] = { [k] = { worker = id, assignment = 1, materials = {}, items = 5, money = 0 } } },
        },
    }
    OldKraken.Database:MigrateWorkshopScope('Evermoon', 'Kraken', false)
    assert(OldKraken.Database:MigrateWorkshopScope('Evermoon', 'Kraken', true))
    local canon = OldKraken.DB.workshop.guilds['Evermoon\\001Kraken']
    assert(canon.orderObserved[k].quantity == 3, 'legacy observed order must be migrated')
    assert(canon.orderDeliveryTallies[id][k] == nil, 'items=5 exceeds legacy order quantity 3 and must not become active')
    assert(canon.migrationConflicts['orderDeliveryTallies\\001' .. id .. '\\001' .. k].legacy.items == 5)
    assert(OldKraken.DB.workshop.guilds['\\001Kraken'].orderDeliveryTallies[id][k].items == 5, 'legacy tally stays intact')
''')

# 9. Tally validity matrix: invalid/invalid, valid canonical + invalid legacy, invalid canonical + valid legacy
lua = make_client(realm='Evermoon', guild='Kraken', player='Alice')
lua.execute('''
    local id = 'Alice Tester'
    local both, keepCanon, takeLegacy = id .. '\\001both', id .. '\\001keep', id .. '\\001take'
    OldKraken.DB.workshop.guilds = {
        ['\\001Kraken'] = { orderDeliveryTallies = { [id] = {
            [both] = { worker = 'Bob Tester', assignment = 1, materials = { [5] = -1 }, items = 1, money = 0 },
            [keepCanon] = { worker = 'Bob Tester', assignment = 1, materials = {}, items = 1, money = -7 },
            [takeLegacy] = { worker = 'Bob Tester', assignment = 2, materials = { [7] = 3 }, items = 2, money = 10 },
        } } },
        ['Evermoon\\001Kraken'] = { orderDeliveryTallies = { [id] = {
            [both] = { worker = 'Bob Tester', assignment = 'x', materials = {}, items = 1, money = 0 },
            [keepCanon] = { worker = 'Bob Tester', assignment = 1, materials = { [9] = 2 }, items = 1, money = 50 },
            [takeLegacy] = { worker = 'Bob Tester', assignment = 2, materials = {}, items = 2, money = 2000000000 },
        } } },
    }
    OldKraken.Database:MigrateWorkshopScope('Evermoon', 'Kraken', false)
    assert(OldKraken.Database:MigrateWorkshopScope('Evermoon', 'Kraken', true))
    local canon = OldKraken.DB.workshop.guilds['Evermoon\\001Kraken']
    local active = canon.orderDeliveryTallies[id]
    local pending = canon.migrationPendingTallies[id]
    local conflicts = canon.migrationConflicts
    assert(active[both] == nil, 'invalid/invalid must leave no active tally')
    assert(conflicts['orderDeliveryTallies\\001' .. id .. '\\001' .. both].canonical.assignment == 'x', 'invalid canonical preserved for diagnostics')
    assert(conflicts['orderDeliveryTallies\\001' .. id .. '\\001' .. both].legacy.materials[5] == -1, 'invalid legacy preserved for diagnostics')
    assert(active[keepCanon] == nil and pending[keepCanon].money == 50 and pending[keepCanon].materials[9] == 2, 'valid canonical must be preserved while its order is missing')
    assert(active[takeLegacy] == nil and pending[takeLegacy].money == 10 and pending[takeLegacy].materials[7] == 3, 'valid legacy must be preserved while its order is missing')
    assert(conflicts['orderDeliveryTallies\\001' .. id .. '\\001' .. takeLegacy].canonical.money == 2000000000, 'replaced invalid canonical must be preserved')
''')

# 10. Real interruption mid-merge, then resume: no double accumulation, originals kept
lua = make_client(realm='Evermoon', guild='Kraken', player='Alice')
lua.execute('''
    local id = 'Alice Tester'
    local k = id .. '\\001ord1'
    OldKraken.DB.workshop.guilds = {
        ['\\001Kraken'] = {
            orderSequences = { [id] = 900 },
            orderDeliveryTallies = { [id] = { [k] = { worker = 'Bob Tester', assignment = 1, materials = { [1] = 6 }, items = 1, money = 300 } } },
            orderDrafts = { [id] = setmetatable({}, { __index = function() error('simulated interruption') end }) },
        },
        ['Evermoon\\001Kraken'] = {
            orderSequences = { [id] = 500 },
            orderDeliveryTallies = { [id] = { [k] = { worker = 'Bob Tester', assignment = 1, materials = { [1] = 2 }, items = 4, money = 100 } } },
        },
    }
    OldKraken.Database:MigrateWorkshopScope('Evermoon', 'Kraken', false)
    local okRun = pcall(OldKraken.Database.MigrateWorkshopScope, OldKraken.Database, 'Evermoon', 'Kraken', true)
    assert(okRun == false, 'expected simulated interruption')
    local meta = OldKraken.DB.workshop.legacyMigrations['\\001Kraken']
    assert(meta.inProgress['Evermoon\\001Kraken'] == true and meta.status['Evermoon\\001Kraken'] == nil)
    assert(meta.pendingConfirmation['Evermoon\\001Kraken'] == true, 'pending marker survives an interrupted run')
    local canon = OldKraken.DB.workshop.guilds['Evermoon\\001Kraken']
    -- tallies were merged before the interruption (partial state)
    assert(canon.migrationPendingTallies[id][k].items == 4 and canon.migrationPendingTallies[id][k].money == 300)

    -- the bad section is repaired; an ordinary connect-style call resumes the confirmed run
    OldKraken.DB.workshop.guilds['\\001Kraken'].orderDrafts = { [id] = { item = 'Elixir', quantity = '2' } }
    local ok, status = OldKraken.Database:MigrateWorkshopScope('Evermoon', 'Kraken', false)
    assert(ok == true and status == 'completed', 'interrupted run must resume, got ' .. tostring(status))
    local t = canon.migrationPendingTallies[id][k]
    assert(t.items == 4 and t.money == 300 and t.materials[1] == 6, 'resume must not accumulate counters twice')
    assert(canon.orderSequences[id] == 900)
    assert(canon.orderDrafts[id].item == 'Elixir')
    local c = canon.migrationConflicts['orderDeliveryTallies\\001' .. id .. '\\001' .. k]
    assert(c.canonical.items == 4 and c.canonical.money == 100 and c.canonical.materials[1] == 2, 'pre-migration canonical original must survive resume')
    local n = 0; for _ in pairs(canon.migrationConflicts) do n = n + 1 end
    assert(n == 1, 'resume must not duplicate conflicts')
    assert(meta.inProgress['Evermoon\\001Kraken'] == nil and meta.pendingConfirmation['Evermoon\\001Kraken'] == nil)
    -- legacy scope untouched apart from the repaired test fixture
    assert(OldKraken.DB.workshop.guilds['\\001Kraken'].orderDeliveryTallies[id][k].money == 300)
''')

# 11. Overflow specifically during MergeDeliveryTallies when 200 conflicts are already recorded
lua = make_client(realm='Evermoon', guild='Kraken', player='Alice')
lua.execute('''
    local id = 'Alice Tester'
    local tk = id .. '\\001tallyOrd'
    local preConflicts = {}
    for i = 1, 200 do
        preConflicts['orderOwners\\001' .. id .. '\\001ord' .. i] = {
            section = 'orderOwners', key = id .. '\\001ord' .. i,
            canonical = { rev = 1 }, legacy = { rev = 1 }, detectedAt = 100, resolved = false,
        }
    end
    OldKraken.DB.workshop.guilds = {
        ['\\001Kraken'] = {
            orderDeliveryTallies = {
                [id] = {
                    [tk] = { worker = 'Bob Tester', assignment = 2, materials = { [1] = 5 }, items = 3, money = 999 },
                },
            },
        },
        ['Evermoon\\001Kraken'] = {
            migrationConflicts = preConflicts,
            orderDeliveryTallies = {
                [id] = {
                    [tk] = { worker = 'Bob Tester', assignment = 1, materials = { [1] = 2 }, items = 1, money = 100 },
                },
            },
        },
    }
    OldKraken.Database:MigrateWorkshopScope('Evermoon', 'Kraken', false)
    local ok, status = OldKraken.Database:ConfirmWorkshopMigration()
    assert(ok == true and status == 'completedWithOverflow', 'expected completedWithOverflow, got ' .. tostring(status))
    local canon = OldKraken.DB.workshop.guilds['Evermoon\\001Kraken']
    assert(canon.migrationConflictsOverflow == true)
    assert(canon.migrationPendingTallies[id][tk].assignment == 1 and canon.migrationPendingTallies[id][tk].money == 100,
        'canonical tally must remain unchanged when conflict cannot be recorded due to overflow')
    assert(OldKraken.DB.workshop.guilds['\\001Kraken'].orderDeliveryTallies[id][tk].money == 999,
        'legacy tally must remain intact on overflow')
''')

# 12. Direct evidence wins over relayed timestamps; tombstones without a live
# owner table are still processed, even if the recipes section is absent.
lua = make_client(realm='Evermoon', guild='Kraken')
lua.execute('''
local old={
    recipes={Alice={[101]={seen=200,name='relayed'}},Bob={[102]={seen=100,name='direct'}}},
    recipeTombstones={Carol={[103]={seen=300,name='deleted'}}},
    recipeSources={Alice={[101]=true},Bob={[102]=false},Carol={[103]=false}},
}
local current={
    recipes={Alice={[101]={seen=100,name='direct'}},Bob={[102]={seen=200,name='relayed'}},Carol={[103]={seen=100,name='old'}}},
    recipeTombstones={},recipeSources={Alice={[101]=false},Bob={[102]=true},Carol={[103]=false}},
}
OldKraken.DB.workshop.guilds={['\\001Kraken']=old,['Evermoon\\001Kraken']=current}
assert(select(2,OldKraken.Database:MigrateWorkshopScope('Evermoon','Kraken',false))=='pending')
assert(OldKraken.Database:ConfirmWorkshopMigration())
assert(current.recipes.Alice[101].name=='direct' and current.recipeSources.Alice[101]==false)
assert(current.recipes.Bob[102].name=='direct' and current.recipeSources.Bob[102]==false)
assert(current.recipes.Carol[103]==nil and current.recipeTombstones.Carol[103].name=='deleted')
assert(old.recipes.Alice[101].name=='relayed' and old.recipeTombstones.Carol[103].name=='deleted')
''')
lua = make_client(realm='Evermoon', guild='Kraken')
lua.execute('''
local old={recipeTombstones={Carol={[103]={seen=300,name='deleted'}}},recipeSources={Carol={[103]=false}}}
OldKraken.DB.workshop.guilds={['\\001Kraken']=old}
OldKraken.Database:MigrateWorkshopScope('Evermoon','Kraken',false)
assert(OldKraken.Database:ConfirmWorkshopMigration())
local current=OldKraken.DB.workshop.guilds['Evermoon\\001Kraken']
assert(current.recipeTombstones.Carol[103].name=='deleted')
''')

# 13. Invalid saved orders never enter live caches; retain them for inspection,
# notify once about the pending transfer, and keep all Workshop timers running.
lua = make_client(realm='Evermoon', guild='Kraken')
lua.execute('''
OldKraken.UIStyle = nil
messages={}; function OldKraken:Print(message) messages[#messages+1]=message end
local id='Alice Tester'; local key=id..'\\001bad'
OldKraken.DB.workshop.guilds={['\\001Kraken']={orderOwners={[id]={[key]={owner=id,id='bad'}}}}}
''')
trigger_connect(lua)
lua.execute('''
assert(#messages==1 and messages[1]:find('/okr workshop migrate',1,true))
assert(select(2,OldKraken.Database:MigrateWorkshopScope('Evermoon','Kraken',false))=='pending')
assert(#messages==1, 'pending migration notification must not spam')
local ok,status=OldKraken.Database:ConfirmWorkshopMigration(); assert(ok and status=='completed')
local current=OldKraken.DB.workshop.guilds['Evermoon\\001Kraken']
local key='Alice Tester\\001bad'
assert(current.orderOwners['Alice Tester'][key]==nil)
assert(current.migrationConflicts['orderOwners\\001Alice Tester\\001'..key].legacy.id=='bad')
local count,sections=OldKraken.Database.WorkshopMigrationConflicts()
assert(count==1 and sections.orderOwners==1)
for _,fn in ipairs(timers) do local good,err=pcall(fn); assert(good,tostring(err)) end
''')

# 14. Never consume a confirmation when order validation is unavailable.
lua = make_client(realm='Evermoon', guild='Kraken')
lua.execute('''
local id='Alice Tester'; local k=id..'\\001a'
OldKraken.DB.workshop.guilds={['\\001Kraken']={orderOwners={[id]={[k]={owner=id,id='a'}}}}}
local normalize=OldKraken.WorkshopOrders.NormalizeMigrationOrder
OldKraken.WorkshopOrders.NormalizeMigrationOrder=nil
OldKraken.Database:MigrateWorkshopScope('Evermoon','Kraken',false)
local ok,status=OldKraken.Database:ConfirmWorkshopMigration()
assert(not ok and status=='unavailable')
assert(not OldKraken.DB.workshop.guilds['Evermoon\\001Kraken'])
OldKraken.WorkshopOrders.NormalizeMigrationOrder=normalize
local resumed,resumeStatus=OldKraken.Database:MigrateWorkshopScope('Evermoon','Kraken',false)
assert(resumed and resumeStatus=='completed', 'approved migration must resume automatically when validation becomes available')
''')

# 15. A tally may precede its order; periodic cleanup must not discard it.
lua = make_client(realm='Evermoon', guild='Kraken')
lua.execute('''
local id='Alice Tester'; local k='Bob Tester\\001order1'
OldKraken.DB.workshop.guilds={['\\001Kraken']={orderDeliveryTallies={[id]={[k]={
    worker=id,assignment=1,materials={[123]=3},items=1,money=0}}}}}
''')
trigger_connect(lua)
lua.execute('''
assert(OldKraken.Database:ConfirmWorkshopMigration())
local scope=OldKraken.DB.workshop.guilds['Evermoon\\001Kraken']
local id='Alice Tester'; local k='Bob Tester\\001order1'
assert(scope.migrationPendingTallies[id][k].materials[123]==3 and not scope.orderDeliveryTallies[id][k])
for _,fn in ipairs(timers) do local ok,err=pcall(fn); assert(ok,tostring(err)) end
assert(scope.migrationPendingTallies[id][k].materials[123]==3, 'unmatched migrated tally must survive cleanup')
scope.orderObserved[k]={owner='Bob Tester',id='order1',created=now,deadline=now+100,quantity=0,status='assigned',worker=id,assignment=1,itemID=0,reward=0}
for _,fn in ipairs(timers) do local ok,err=pcall(fn); assert(ok,tostring(err)) end
assert(scope.migrationPendingTallies[id][k] and not scope.orderDeliveryTallies[id][k], 'invalid tally must stay isolated')
scope.orderObserved[k].quantity=5
scope.orderObserved[k].worker='Different Tester'
for _,fn in ipairs(timers) do local ok,err=pcall(fn); assert(ok,tostring(err)) end
assert(scope.migrationPendingTallies[id][k] and not scope.orderDeliveryTallies[id][k], 'different worker must stay isolated')
scope.orderObserved[k].worker=id
for _,fn in ipairs(timers) do local ok,err=pcall(fn); assert(ok,tostring(err)) end
assert(not scope.migrationPendingTallies[id][k] and scope.orderDeliveryTallies[id][k])
scope.orderObserved[k]=nil
for _,fn in ipairs(timers) do local ok,err=pcall(fn); assert(ok,tostring(err)) end
assert(scope.orderDeliveryTallies[id][k]==nil, 'ordinary cleanup resumes after the order was found')
''')

# 10. Empty GetRealmName() on WoW Forever resolves to explicit 'Forever' scope:
#     all 4 Workshop modules connect to 'Forever\\001Kraken', legacy '\\001Kraken' is preserved
#     until explicit confirmation, and explicit confirmation migrates into 'Forever\\001Kraken'.
lua_forever = make_client(realm='', guild='Kraken', player='Alice')
lua_forever.execute('''
    OldKraken.DB.workshop.guilds = {
        ['\\001Kraken'] = {
            records = { ['Alice Tester'] = { professions = { [171] = { rank = 300, max = 300 } }, updated = 100 } },
            recipes = { ['Alice Tester'] = { [171] = { [2329] = 1 } } },
        },
        ['Evermoon\\001Kraken'] = {
            records = { ['Bob Tester'] = { professions = { [164] = { rank = 250, max = 300 } }, updated = 90 } },
        },
    }
''')
trigger_connect(lua_forever)
lua_forever.execute('''
    local guilds = OldKraken.DB.workshop.guilds
    assert(OldKraken.Database:IsValidRealm('') == false, 'IsValidRealm("") must stay false')
    assert(OldKraken.Database:GetRealmScope() == 'Forever', 'GetRealmScope() must return Forever')
    local fScope = guilds['Forever\\001Kraken']
    assert(type(fScope) == 'table', 'Forever workshop scope must exist')
    assert(type(fScope.records) == 'table' and type(fScope.recipes) == 'table' and type(fScope.orderOwners) == 'table',
        'All Workshop modules must connect under Forever\\001Kraken')
    assert(fScope.records['Alice Tester'] == nil, 'legacy data must not auto-migrate before confirmation')
    assert(fScope.records['Bob Tester'] == nil, 'Evermoon data must stay isolated from Forever')
    assert(guilds['\\001Kraken'].records['Alice Tester'] ~= nil, 'legacy scope must remain intact')
    assert(guilds['Evermoon\\001Kraken'].records['Bob Tester'] ~= nil, 'Evermoon scope must remain intact')

    local ok, reason = OldKraken.Database:ConfirmWorkshopMigration()
    assert(ok and reason == 'completed', 'explicit migration into Forever\\001Kraken must succeed')
    assert(fScope.records['Alice Tester'] ~= nil and fScope.recipes['Alice Tester'][171][2329] == 1,
        'confirmed migration must copy legacy data into Forever\\001Kraken')
    assert(guilds['\\001Kraken'].records['Alice Tester'] ~= nil, 'legacy source must be preserved')
''')

# Consent recorded by older versions for the ambiguous Forever key is not trusted.
lua = make_client(realm='Forever', guild='Kraken')
lua.execute("""
    OldKraken.DB.workshop.guilds={['\\001Kraken']={orderDrafts={['Alice Tester']={item='Legacy'}}}}
    OldKraken.DB.workshop.legacyMigrations={['\\001Kraken']={
        confirmedDestination='Forever\\001Kraken',inProgress={['Forever\\001Kraken']=true}}}
""")
trigger_connect(lua)
lua.execute("""
    local dlg=OldKrakenWorkshopMigrationFrame
    assert(dlg and dlg:IsShown() and dlg.migrationData.realm=='Forever', 'old ambiguous approval must not be reused')
    local current=OldKraken.DB.workshop.guilds['Forever\\001Kraken']
    assert(not current.orderDrafts['Alice Tester'])
    dlg.acceptButton.scripts.OnClick()
    assert(current.orderDrafts['Alice Tester'].item=='Legacy')
    assert(OldKraken.DB.workshop.legacyMigrations['\\001Kraken'].verifiedDestinations['Forever\\001Kraken'])
""")

# Independent order versions preserve the replaced canonical copy for owners and observers.
lua = make_client(realm='Evermoon', guild='Kraken')
lua.execute("""
    local id='Alice Tester'; local key=id..'\\001ord1'
    local function order(rev,note)
        return {owner=id,id='ord1',rev=rev,ownerRev=rev,created=now,deadline=now+100,
            profession=171,item='Flask',itemID=0,recipeID=0,quantity=5,reward=10,rewardSilver=0,
            materials='customer',note=note,status='open',candidates={},acks={}}
    end
    OldKraken.DB.workshop.guilds={
        ['\\001Kraken']={orderOwners={[id]={[key]=order(2,'legacy')}},orderObserved={[key]=order(2,'legacy observed')}},
        ['Evermoon\\001Kraken']={orderOwners={[id]={[key]=order(1,'canonical')}},orderObserved={[key]=order(1,'canonical observed')}},
    }
    OldKraken.Database:MigrateWorkshopScope('Evermoon','Kraken',false)
    assert(OldKraken.Database:ConfirmWorkshopMigration())
    local g=OldKraken.DB.workshop.guilds; local current=g['Evermoon\\001Kraken']
    assert(current.orderOwners[id][key].note=='legacy')
    assert(current.orderObserved[key].note=='legacy observed')
    local ownerConflict=current.migrationConflicts['orderOwners\\001'..id..'\\001'..key]
    local observedConflict=current.migrationConflicts['orderObserved\\001'..key]
    assert(ownerConflict.canonical.note=='canonical' and ownerConflict.legacy.note=='legacy')
    assert(observedConflict.canonical.note=='canonical observed' and observedConflict.legacy.note=='legacy observed')
    assert(g['\\001Kraken'].orderOwners[id][key].note=='legacy')
    assert(OldKraken.Database.WorkshopMigrationConflicts()==2)
    assert(OldKraken.Database:MigrateWorkshopScope('Evermoon','Kraken',false))
    assert(ownerConflict.canonical.note=='canonical' and observedConflict.canonical.note=='canonical observed')
""")

# If the conflict archive is full, never replace a canonical order without its backup.
lua = make_client(realm='Evermoon', guild='Kraken')
lua.execute("""
    local id='Alice Tester'; local key=id..'\\001ord1'; local conflicts={}
    for i=1,200 do conflicts['existing'..i]={section='existing',key=tostring(i)} end
    local function order(rev,note)
        return {owner=id,id='ord1',rev=rev,ownerRev=rev,created=now,deadline=now+100,
            profession=171,item='Flask',itemID=0,recipeID=0,quantity=5,reward=10,rewardSilver=0,
            materials='customer',note=note,status='open',candidates={},acks={}}
    end
    OldKraken.DB.workshop.guilds={
        ['\\001Kraken']={orderOwners={[id]={[key]=order(2,'legacy')}},orderObserved={[key]=order(2,'legacy observed')}},
        ['Evermoon\\001Kraken']={migrationConflicts=conflicts,orderOwners={[id]={[key]=order(1,'canonical')}},orderObserved={[key]=order(1,'canonical observed')}},
    }
    OldKraken.Database:MigrateWorkshopScope('Evermoon','Kraken',false)
    local ok,status=OldKraken.Database:ConfirmWorkshopMigration()
    assert(ok and status=='completedWithOverflow')
    local g=OldKraken.DB.workshop.guilds; local current=g['Evermoon\\001Kraken']
    assert(current.orderOwners[id][key].note=='canonical' and current.orderObserved[key].note=='canonical observed')
    assert(g['\\001Kraken'].orderOwners[id][key].note=='legacy' and g['\\001Kraken'].orderObserved[key].note=='legacy observed')
""")

# A realm-less scope prompts once; acceptance transfers without a slash command.
lua = make_client(realm='Evermoon', guild='Kraken')
lua.execute('''
messages={}; function OldKraken:Print(msg) messages[#messages+1]=msg end
popupCount=0
function StaticPopup_Show() popupCount=popupCount+1; return {} end
OldKraken.DB.workshop.guilds={['\\001Kraken']={orderDrafts={['Alice Tester']={item='Flask',quantity='5'}}}}
''')
trigger_connect(lua)
lua.execute('''
local dlg=OldKrakenWorkshopMigrationFrame
assert(popupCount==0 and dlg and dlg:IsShown() and dlg.migrationData.guild=='Kraken' and dlg.migrationData.realm=='Evermoon')
assert(not OldKraken.DB.workshop.guilds['Evermoon\\001Kraken'].orderDrafts['Alice Tester'])
dlg.laterButton.scripts.OnClick()
assert(not dlg:IsShown())
''')
trigger_connect(lua)
lua.execute('''
local dlg=OldKrakenWorkshopMigrationFrame
assert(not dlg:IsShown(), 'one prompt per scope until the user decides')
dlg.acceptButton.scripts.OnClick()
local g=OldKraken.DB.workshop.guilds
assert(g['Evermoon\\001Kraken'].orderDrafts['Alice Tester'].item=='Flask')
assert(g['\\001Kraken'].orderDrafts['Alice Tester'].item=='Flask')
assert(OldKraken.DB.workshop.legacyMigrations['\\001Kraken'].confirmedDestination=='Evermoon\\001Kraken')
''')
lua.globals()._realm = 'Frostmourne'
trigger_connect(lua)
lua.execute('''
local dlg=OldKrakenWorkshopMigrationFrame
assert(dlg:IsShown() and dlg.migrationData.realm=='Frostmourne')
assert(not OldKraken.DB.workshop.guilds['Frostmourne\\001Kraken'].orderDrafts['Alice Tester'])
''')

# A stale dialog cannot transfer into another realm after a scope change.
lua = make_client(realm='Evermoon', guild='Kraken')
lua.execute('''
messages={}; function OldKraken:Print(msg) messages[#messages+1]=msg end
OldKraken.DB.workshop.guilds={['\\001Kraken']={orderDrafts={['Alice Tester']={item='Flask',quantity='5'}}}}
''')
trigger_connect(lua)
lua.globals()._realm = 'Frostmourne'
lua.execute('''
OldKrakenWorkshopMigrationFrame.acceptButton.scripts.OnClick()
assert(not OldKraken.DB.workshop.guilds['Evermoon\\001Kraken'].orderDrafts['Alice Tester'])
assert(not OldKraken.DB.workshop.guilds['Frostmourne\\001Kraken'])
assert(messages[#messages]:find('не перенесено',1,true))
''')

# A destination explicitly approved earlier resumes automatically.
lua = make_client(realm='Evermoon', guild='Kraken')
lua.execute('''
OldKraken.DB.workshop.guilds={['\\001Kraken']={orderDrafts={['Alice Tester']={item='Flask',quantity='5'}}}}
OldKraken.DB.workshop.legacyMigrations={['\\001Kraken']={confirmedDestination='Evermoon\\001Kraken'}}
''')
trigger_connect(lua)
lua.execute('''
assert(not OldKrakenWorkshopMigrationFrame)
assert(OldKraken.DB.workshop.guilds['Evermoon\\001Kraken'].orderDrafts['Alice Tester'].item=='Flask')
assert(OldKraken.DB.workshop.guilds['\\001Kraken'].orderDrafts['Alice Tester'].item=='Flask')
assert(OldKraken.DB.workshop.legacyMigrations['\\001Kraken'].status['Evermoon\\001Kraken']=='completed')
''')

# A temporarily unavailable fallback popup is retried without repeatedly printing notices.
lua = make_client(realm='Evermoon', guild='Kraken')
lua.execute('''
OldKraken.UIStyle = nil
messages={}; function OldKraken:Print(msg) messages[#messages+1]=msg end
popupCount=0; ready=false
function StaticPopup_Show(_,_,_,data)
    popupCount=popupCount+1; popupData=data
    if ready then return {} end
end
OldKraken.DB.workshop.guilds={['\\001Kraken']={orderDrafts={['Alice Tester']={item='Flask',quantity='5'}}}}
''')
trigger_connect(lua)
lua.execute('assert(popupCount==1 and #messages==1); clock=clock+6; ready=true')
trigger_connect(lua)
lua.execute('''
assert(popupCount==2 and #messages==1)
StaticPopupDialogs.OLDKRAKEN_WORKSHOP_MIGRATION.OnAccept(nil,popupData)
assert(OldKraken.DB.workshop.guilds['Evermoon\\001Kraken'].orderDrafts['Alice Tester'].item=='Flask')
''')

# Custom UIStyle migration dialog avoids StaticPopup_Show in live UI.
lua = make_client(realm='Evermoon', guild='Kraken')
lua.execute('''
    popupCount=0
    function StaticPopup_Show() popupCount=popupCount+1; return {} end
    OldKraken.UIStyle={
        Window=function() end,
        Font=function() end,
        Button=function() end,
    }
    OldKraken.DB.workshop.guilds={['\\001Kraken']={orderDrafts={['Alice Tester']={item='Flask',quantity='5'}}}}
''')
trigger_connect(lua)
lua.execute('''
    assert(popupCount==0, 'must not call StaticPopup_Show when UIStyle is present')
    local dlg=OldKrakenWorkshopMigrationFrame
    assert(dlg and dlg:IsShown(), 'custom migration dialog must be shown')
    dlg.acceptButton.scripts.OnClick()
    assert(not dlg:IsShown())
    assert(OldKraken.DB.workshop.guilds['Evermoon\\001Kraken'].orderDrafts['Alice Tester'].item=='Flask')
''')

print('Workshop migration checks passed')
