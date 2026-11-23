"""Tests for Dire Maul, Stratholme, and Maraudon wings expansion with legacy compatibility."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def build_env(lang="ukUA"):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(
        """
        OldKraken = {
            name = 'OldKraken',
            _listeners = {},
            Communication = {queue = {}},
            UIStyle = {
                Colors = {
                    window = {0, 0, 0, 1}, brandGold = {1, 1, 0, 1}, text = {1, 1, 1, 1},
                    mutedText = {0.6, 0.6, 0.6}, success = {0, 1, 0, 1}, neutral = {0.6, 0.6, 0.6, 1},
                    danger = {1, 0, 0, 1},
                },
                EmblemPath = function() return 'emblem' end,
            },
        }
        eventHandlers = {}
        function OldKraken.Communication:RegisterHandler(kind, fn) eventHandlers[kind] = fn end
        function OldKraken.Communication:SendProtocol() return true end
        function OldKraken.Communication:RegisterCommand() end
        function OldKraken:On(name, fn)
            self._listeners[name] = self._listeners[name] or {}
            table.insert(self._listeners[name], fn)
        end
        function OldKraken:Fire(name, ...)
            for _, fn in ipairs(self._listeners[name] or {}) do fn(...) end
        end
        now = 1700000000
        function GetTime() return 100 end
        function GetServerTime() return now end
        function UnitName() return 'Tester', 'Realm' end
        function GetRealmName() return 'Realm' end
        function GetGuildInfo() return 'Guild' end
        function IsInGuild() return true end
        function print() end
        createdFrames = {}
        function CreateFrame(_, name)
            local f = {
                scripts = {},
                RegisterEvent = function() end,
                SetScript = function(self, k, fn) self.scripts[k] = fn end,
                Show = function() end,
                Hide = function() end,
            }
            table.insert(createdFrames, f)
            return f
        end
        StaticPopupDialogs = {}
        UISpecialFrames = {}
        UIParent = {}
    """
    )
    for file in ("Locale.lua", "ActivityCatalog.lua", "GroupFinder.lua", "GuildEvents.lua"):
        lua.execute((ROOT / file).read_text(encoding="utf-8"))
    lua.execute(
        f"""
        local db = {{
            settings = {{language = '{lang}', groupFinderNotifications = false, guildEventNotifications = false}},
            events = {{guildCalendarV1 = {{['Realm\\001Guild\\001Tester Realm'] = {{owned={{}}, relays={{}}, sequence=0}}}}}},
        }}
        OldKraken.InitializeLocale(db)
        OldKraken.DB = db
        for _, frame in ipairs(createdFrames) do
            if frame.scripts and frame.scripts.OnEvent then
                frame.scripts.OnEvent(frame, 'PLAYER_LOGIN')
            end
        end
    """
    )
    return lua


def test_activity_catalog_expansion_and_legacy():
    lua = build_env("ukUA")
    lua.execute(
        r"""
        local cat = OldKraken.ActivityCatalog
        assert(cat and cat.dungeon, 'catalog.dungeon must exist')

        local dungeonMap = {}
        for _, entry in ipairs(cat.dungeon) do
            assert(not dungeonMap[entry.value], 'duplicate dungeon value: ' .. tostring(entry.value))
            dungeonMap[entry.value] = entry
        end

        -- Legacy entries must NOT be present in active catalog.dungeon
        assert(not dungeonMap['dm'], 'legacy dm must not be in catalog.dungeon')
        assert(not dungeonMap['strat'], 'legacy strat must not be in catalog.dungeon')
        assert(not dungeonMap['maraudon'], 'legacy maraudon must not be in catalog.dungeon')
        assert(not dungeonMap['sm'], 'legacy sm must not be in catalog.dungeon')

        -- Dire Maul wings
        local dmEast = dungeonMap['dm-east']
        assert(dmEast and dmEast.min == 55 and dmEast.max == 58, 'dm-east range 55-58')
        local dmWest = dungeonMap['dm-west']
        assert(dmWest and dmWest.min == 57 and dmWest.max == 60, 'dm-west range 57-60')
        local dmNorth = dungeonMap['dm-north']
        assert(dmNorth and dmNorth.min == 57 and dmNorth.max == 60, 'dm-north range 57-60')

        -- Stratholme wings
        local stratLive = dungeonMap['strat-live']
        assert(stratLive and stratLive.min == 58 and stratLive.max == 60, 'strat-live range 58-60')
        local stratUD = dungeonMap['strat-undead']
        assert(stratUD and stratUD.min == 58 and stratUD.max == 60, 'strat-undead range 58-60')

        -- Maraudon parts / princess run
        local maraPurp = dungeonMap['mara-purple']
        assert(maraPurp and maraPurp.min == 45 and maraPurp.max == 50, 'mara-purple range 45-50')
        local maraOrg = dungeonMap['mara-orange']
        assert(maraOrg and maraOrg.min == 45 and maraOrg.max == 50, 'mara-orange range 45-50')
        local maraPrin = dungeonMap['mara-princess']
        assert(maraPrin and maraPrin.min == 48 and maraPrin.max == 53, 'mara-princess range 48-53')

        -- Legacy table verification
        assert(cat.legacy and cat.legacy.dungeon, 'catalog.legacy.dungeon must exist')
        local legacyMap = {}
        for _, entry in ipairs(cat.legacy.dungeon) do legacyMap[entry.value] = entry end
        assert(legacyMap['dm'] and legacyMap['dm'].min == 55 and legacyMap['dm'].max == 60, 'legacy dm in legacy table')
        assert(legacyMap['strat'] and legacyMap['strat'].min == 58 and legacyMap['strat'].max == 60, 'legacy strat in legacy table')
        assert(legacyMap['maraudon'] and legacyMap['maraudon'].min == 46 and legacyMap['maraudon'].max == 55, 'legacy maraudon in legacy table')
        assert(legacyMap['sm'] and legacyMap['sm'].min == 30 and legacyMap['sm'].max == 46, 'legacy sm in legacy table')

        -- Artwork mapping: DM=131835, Strat=131871, Mara=131850
        local mockTexture = {
            texture = nil,
            SetTexture = function(self, tex) self.texture = tex end,
            SetTexCoord = function() end,
        }
        for _, id in ipairs({'dm', 'dm-east', 'dm-west', 'dm-north'}) do
            cat.SetArtwork(mockTexture, id)
            assert(mockTexture.texture == 131835, 'texture for ' .. id .. ' must be 131835')
        end
        for _, id in ipairs({'strat', 'strat-live', 'strat-undead'}) do
            cat.SetArtwork(mockTexture, id)
            assert(mockTexture.texture == 131871, 'texture for ' .. id .. ' must be 131871')
        end
        for _, id in ipairs({'maraudon', 'mara-purple', 'mara-orange', 'mara-princess'}) do
            cat.SetArtwork(mockTexture, id)
            assert(mockTexture.texture == 131850, 'texture for ' .. id .. ' must be 131850')
        end

        -- IsValidActivity verification
        for _, id in ipairs({'dm-east', 'dm-west', 'dm-north', 'strat-live', 'strat-undead', 'mara-purple', 'mara-orange', 'mara-princess'}) do
            assert(cat.IsValidActivity('dungeon', id), id .. ' must be valid activity')
        end
        for _, id in ipairs({'dm', 'strat', 'maraudon', 'sm'}) do
            assert(cat.IsValidActivity('dungeon', id), 'legacy ' .. id .. ' must be valid activity')
        end
        assert(not cat.IsValidActivity('dungeon', 'dm-unknown'), 'dm-unknown must be invalid')
        assert(not cat.IsValidActivity('dungeon', 'strat-unknown'), 'strat-unknown must be invalid')
        assert(not cat.IsValidActivity('dungeon', 'mara-unknown'), 'mara-unknown must be invalid')
    """
    )


def test_localization_expansion():
    # Ukrainian
    lua_uk = build_env("ukUA")
    lua_uk.execute(
        r"""
        local cat = OldKraken.ActivityCatalog
        local map = {}
        for _, entry in ipairs(cat.dungeon) do map[entry.value] = entry.label end
        for _, entry in ipairs(cat.legacy.dungeon) do map[entry.value] = entry.label end

        assert(map['dm-east'] == 'Забуте Місто: Схід (DM East)')
        assert(map['dm-west'] == 'Забуте Місто: Захід (DM West)')
        assert(map['dm-north'] == 'Забуте Місто: Північ (DM North)')
        assert(map['dm'] == 'Забуте Місто (DM)')

        assert(map['strat-live'] == 'Стратхольм: Жива частина (Strat Live)')
        assert(map['strat-undead'] == 'Стратхольм: Нежить (Strat UD)')
        assert(map['strat'] == 'Стратхольм (Strat)')

        assert(map['mara-purple'] == 'Мародон: Фіолетовий (Mara Purp)')
        assert(map['mara-orange'] == 'Мародон: Помаранчевий (Mara Org)')
        assert(map['mara-princess'] == 'Мародон: Забіг на Принцесу (Mara Prin)')
        assert(map['maraudon'] == 'Мародон (Mara)')
    """
    )

    # English
    lua_en = build_env("enUS")
    lua_en.execute(
        r"""
        local cat = OldKraken.ActivityCatalog
        local map = {}
        for _, entry in ipairs(cat.dungeon) do map[entry.value] = entry.label end
        for _, entry in ipairs(cat.legacy.dungeon) do map[entry.value] = entry.label end

        assert(map['dm-east'] == 'Dire Maul: East (DM East)')
        assert(map['dm-west'] == 'Dire Maul: West (DM West)')
        assert(map['dm-north'] == 'Dire Maul: North (DM North)')
        assert(map['dm'] == 'Dire Maul (DM)')

        assert(map['strat-live'] == 'Stratholme: Live (Strat Live)')
        assert(map['strat-undead'] == 'Stratholme: Undead (Strat UD)')
        assert(map['strat'] == 'Stratholme (Strat)')

        assert(map['mara-purple'] == 'Maraudon: Purple (Mara Purp)')
        assert(map['mara-orange'] == 'Maraudon: Orange (Mara Org)')
        assert(map['mara-princess'] == 'Maraudon: Princess Run (Mara Prin)')
        assert(map['maraudon'] == 'Maraudon (Mara)')
    """
    )


def test_group_finder_expansion():
    lua = build_env("ukUA")
    lua.execute(
        r"""
        local f = OldKraken.GroupFinder
        f:Initialize('Tester Realm', function() return true end)
        f.active = true
        function f:CanPerformRole() return true end

        local wings = {
            'dm-east', 'dm-west', 'dm-north',
            'strat-live', 'strat-undead',
            'mara-purple', 'mara-orange', 'mara-princess'
        }
        for _, wing in ipairs(wings) do
            local ok, id = f:Create('Test Group', 'dungeon', '', 5, 55, 60, 'tank', wing)
            assert(ok, 'create with ' .. wing .. ' must succeed')
            local g = f.groups['Tester Realm\001' .. id]
            assert(g and g.dungeon == wing)

            local payload = f:EncodeGroup(g)
            local other = setmetatable({}, {__index = f})
            other:Initialize('Other Realm', function() return true end)
            local okOther = other:ReceiveGroup('Tester Realm', payload)
            assert(okOther, 'ReceiveGroup with ' .. wing .. ' must succeed')
            assert(other.groups['Tester Realm\001' .. id].dungeon == wing)
        end

        -- Legacy IDs
        for _, leg in ipairs({'dm', 'strat', 'maraudon'}) do
            local ok, id = f:Create('Legacy Group', 'dungeon', '', 5, 50, 60, 'tank', leg)
            assert(ok, 'create with legacy ' .. leg .. ' must succeed')
            local g = f.groups['Tester Realm\001' .. id]
            local payload = f:EncodeGroup(g)
            local other = setmetatable({}, {__index = f})
            other:Initialize('Other Realm', function() return true end)
            assert(other:ReceiveGroup('Tester Realm', payload))
            assert(other.groups['Tester Realm\001' .. id].dungeon == leg)
        end
    """
    )


def test_guild_events_creation_and_network_receive():
    lua = build_env("ukUA")
    lua.execute(
        r"""
        local events = OldKraken.GuildEvents
        local codec = OldKraken.GroupFinder
        local handler = eventHandlers['CVNEW']
        assert(handler, 'CVNEW handler must be registered')
        local storageKey = 'Realm\001Guild\001Tester Realm'

        local newActivities = {
            'dm-east', 'dm-west', 'dm-north',
            'strat-live', 'strat-undead',
            'mara-purple', 'mara-orange', 'mara-princess'
        }
        for i, act in ipairs(newActivities) do
            local ok = events:Create('Event ' .. act, '', now + 3600, 'dungeon', 5, act)
            assert(ok, 'event create with ' .. act .. ' must succeed')

            -- Network receive
            local msgId = '1700000000-10' .. tostring(i)
            local payload = codec._pack({
                msgId, 'OtherPlayer', '1', tostring(now + 3600), 'dungeon', '5', '0',
                'Run ' .. act, '', '1', 'OtherPlayer', 'tank', act, 'A'
            })
            handler('OtherPlayer', msgId, payload)
            local observed = OldKraken.DB.events.guildCalendarV1[storageKey].observed
            assert(observed and observed['OtherPlayer\001' .. msgId], 'event ' .. act .. ' must be received')
            assert(observed['OtherPlayer\001' .. msgId].activity == act)
        end

        -- Legacy events
        for i, leg in ipairs({'dm', 'strat', 'maraudon'}) do
            local ok = events:Create('Legacy ' .. leg, '', now + 3600, 'dungeon', 5, leg)
            assert(ok, 'create with legacy ' .. leg .. ' must succeed')

            local msgId = '1700000000-20' .. tostring(i)
            local payload = codec._pack({
                msgId, 'OtherPlayer', '1', tostring(now + 3600), 'dungeon', '5', '0',
                'Legacy ' .. leg, '', '1', 'OtherPlayer', 'tank', leg, 'A'
            })
            handler('OtherPlayer', msgId, payload)
            local observed = OldKraken.DB.events.guildCalendarV1[storageKey].observed
            assert(observed and observed['OtherPlayer\001' .. msgId], 'legacy ' .. leg .. ' must be received')
            assert(observed['OtherPlayer\001' .. msgId].activity == leg)
        end

        -- Unknown activity rejected
        local badId = '1700000000-999'
        local payloadBad = codec._pack({
            badId, 'OtherPlayer', '1', tostring(now + 3600), 'dungeon', '5', '0',
            'Bad Run', '', '1', 'OtherPlayer', 'tank', 'dm-bogus', 'A'
        })
        handler('OtherPlayer', badId, payloadBad)
        local observed = OldKraken.DB.events.guildCalendarV1[storageKey].observed
        assert(observed['OtherPlayer\001' .. badId] == nil, 'bogus activity must be rejected')
    """
    )


def test_ui_title_resolution_expansion():
    for lang, testCases in (
        ("ukUA", {
            ('dm-east', 'Забуте Місто: Схід (DM East)'),
            ('dm-west', 'Забуте Місто: Захід (DM West)'),
            ('dm-north', 'Забуте Місто: Північ (DM North)'),
            ('dm', 'Забуте Місто (DM)'),
            ('strat-live', 'Стратхольм: Жива частина (Strat Live)'),
            ('strat-undead', 'Стратхольм: Нежить (Strat UD)'),
            ('strat', 'Стратхольм (Strat)'),
            ('mara-purple', 'Мародон: Фіолетовий (Mara Purp)'),
            ('mara-orange', 'Мародон: Помаранчевий (Mara Org)'),
            ('mara-princess', 'Мародон: Забіг на Принцесу (Mara Prin)'),
            ('maraudon', 'Мародон (Mara)'),
        }),
        ("enUS", {
            ('dm-east', 'Dire Maul: East (DM East)'),
            ('dm-west', 'Dire Maul: West (DM West)'),
            ('dm-north', 'Dire Maul: North (DM North)'),
            ('dm', 'Dire Maul (DM)'),
            ('strat-live', 'Stratholme: Live (Strat Live)'),
            ('strat-undead', 'Stratholme: Undead (Strat UD)'),
            ('strat', 'Stratholme (Strat)'),
            ('mara-purple', 'Maraudon: Purple (Mara Purp)'),
            ('mara-orange', 'Maraudon: Orange (Mara Org)'),
            ('mara-princess', 'Maraudon: Princess Run (Mara Prin)'),
            ('maraudon', 'Maraudon (Mara)'),
        }),
    ):
        lua = build_env(lang)
        lua.execute(
            """
            for name, fr in pairs(frames or {}) do end
            UIDropDownMenu_SetWidth = function() end
            UIDropDownMenu_JustifyText = function() end
            UIDropDownMenu_Initialize = function() end
            UIDropDownMenu_SetText = function() end
            UIDropDownMenu_CreateInfo = function() return {} end
            PlaySound = function() end
        """
        )
        lua.execute((ROOT / "GroupFinderUI.lua").read_text(encoding="utf-8"))
        lua.execute(
            """
            local finder = OldKraken.GroupFinder
            local events = OldKraken.GuildEvents

            -- Verify dungeonOptions does NOT offer any legacy entries in UI selector
            local legacyKeys = {dm = true, strat = true, maraudon = true, sm = true}
            for _, opt in ipairs(OldKraken.ActivityCatalog.dungeon) do
                assert(not legacyKeys[opt.value], 'catalog.dungeon must not contain legacy entry: ' .. tostring(opt.value))
            end
        """
        )

        for act, expectedLabel in testCases:
            lua.execute(
                f"""
                local finder = OldKraken.GroupFinder
                local events = OldKraken.GuildEvents

                local groupTitle = finder:DisplayTitle({{title = '{expectedLabel}', dungeon = '{act}'}})
                assert(groupTitle == '{expectedLabel}', 'groupTitle mismatch for {act} in {lang}: ' .. tostring(groupTitle))

                local eventTitle = events:DisplayTitle({{title = '{expectedLabel}', activity = '{act}'}})
                assert(eventTitle == '{expectedLabel}', 'eventTitle mismatch for {act} in {lang}: ' .. tostring(eventTitle))
            """
            )


def test_saved_variables_restore_legacy_events():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(
        """
        OldKraken = {
            name = 'OldKraken',
            _listeners = {},
            Communication = {queue = {}},
            UIStyle = {
                Colors = {
                    window = {0, 0, 0, 1}, brandGold = {1, 1, 0, 1}, text = {1, 1, 1, 1},
                    mutedText = {0.6, 0.6, 0.6}, success = {0, 1, 0, 1}, neutral = {0.6, 0.6, 0.6, 1},
                    danger = {1, 0, 0, 1},
                },
                EmblemPath = function() return 'emblem' end,
            },
        }
        eventHandlers = {}
        function OldKraken.Communication:RegisterHandler(kind, fn) eventHandlers[kind] = fn end
        function OldKraken.Communication:SendProtocol() return true end
        function OldKraken.Communication:RegisterCommand() end
        function OldKraken:On(name, fn)
            self._listeners[name] = self._listeners[name] or {}
            table.insert(self._listeners[name], fn)
        end
        function OldKraken:Fire(name, ...)
            for _, fn in ipairs(self._listeners[name] or {}) do fn(...) end
        end
        now = 1700000000
        function GetTime() return 100 end
        function GetServerTime() return now end
        function UnitName() return 'Tester', 'Realm' end
        function GetRealmName() return 'Realm' end
        function GetGuildInfo() return 'Guild' end
        function IsInGuild() return true end
        function print() end
        createdFrames = {}
        function CreateFrame(_, name)
            local f = {
                scripts = {},
                RegisterEvent = function() end,
                SetScript = function(self, k, fn) self.scripts[k] = fn end,
                Show = function() end,
                Hide = function() end,
            }
            table.insert(createdFrames, f)
            return f
        end
        StaticPopupDialogs = {}
        UISpecialFrames = {}
        UIParent = {}
    """
    )
    for file in ("Locale.lua", "ActivityCatalog.lua", "GroupFinder.lua", "GuildEvents.lua"):
        lua.execute((ROOT / file).read_text(encoding="utf-8"))

    lua.execute(
        r"""
        local storageKey = 'Realm\001Guild\001Tester Realm'
        local dmId = '1700000000-111111-1'
        local stratId = '1700000000-222222-2'
        local maraId = '1700000000-333333-3'

        local preOwned = {
            ['Tester Realm\001' .. dmId] = {
                id = dmId, owner = 'Tester Realm', rev = 1, when = now + 3600,
                kind = 'dungeon', size = 5, cancelled = false, title = 'Old DM Event',
                description = 'Legacy DM', people = {['Tester Realm'] = 'tank'},
                statuses = {['Tester Realm'] = 'accepted'}, versions = {}, activity = 'dm'
            },
            ['Tester Realm\001' .. stratId] = {
                id = stratId, owner = 'Tester Realm', rev = 1, when = now + 7200,
                kind = 'dungeon', size = 5, cancelled = false, title = 'Old Strat Event',
                description = 'Legacy Strat', people = {['Tester Realm'] = 'tank'},
                statuses = {['Tester Realm'] = 'accepted'}, versions = {}, activity = 'strat'
            },
        }

        local preObserved = {
            ['OtherLeader\001' .. maraId] = {
                id = maraId, owner = 'OtherLeader', rev = 1, when = now + 5000,
                kind = 'dungeon', size = 5, cancelled = false, title = 'Old Mara Event',
                description = 'Legacy Mara', people = {['OtherLeader'] = 'dps'},
                statuses = {['OtherLeader'] = 'accepted'}, versions = {}, activity = 'maraudon'
            },
        }

        local db = {
            settings = {language = 'ukUA', groupFinderNotifications = false, guildEventNotifications = false},
            events = {guildCalendarV1 = {[storageKey] = {
                owned = preOwned, observed = preObserved, relays = {}, sequence = 2
            }}},
        }
        OldKraken.InitializeLocale(db)
        OldKraken.DB = db

        -- Fire PLAYER_LOGIN to trigger connect()
        for _, frame in ipairs(createdFrames) do
            if frame.scripts and frame.scripts.OnEvent then
                frame.scripts.OnEvent(frame, 'PLAYER_LOGIN')
            end
        end

        local events = OldKraken.GuildEvents

        -- Verify that legacy events were successfully decoded and restored
        local titleDM = events:DisplayTitle({title = 'Old DM Event', activity = 'dm'})
        assert(titleDM == 'Old DM Event', 'legacy DM event display title')

        -- Trigger save() by creating a new event
        local okNew = events:Create('New Wing Event', '', now + 10000, 'dungeon', 5, 'dm-east')
        assert(okNew, 'creating new event must succeed and trigger save')

        -- Verify SavedVariables storage still preserves the legacy events
        local storage = OldKraken.DB.events.guildCalendarV1[storageKey]
        assert(storage.owned['Tester Realm\001' .. dmId], 'legacy DM event must be preserved in storage.owned after save')
        assert(storage.owned['Tester Realm\001' .. dmId].activity == 'dm', 'legacy DM activity must stay dm')

        assert(storage.owned['Tester Realm\001' .. stratId], 'legacy Strat event must be preserved in storage.owned after save')
        assert(storage.owned['Tester Realm\001' .. stratId].activity == 'strat', 'legacy Strat activity must stay strat')

        assert(storage.observed['OtherLeader\001' .. maraId], 'legacy Mara event must be preserved in storage.observed after save')
        assert(storage.observed['OtherLeader\001' .. maraId].activity == 'maraudon', 'legacy Mara activity must stay maraudon')
    """
    )


if __name__ == "__main__":
    test_activity_catalog_expansion_and_legacy()
    test_localization_expansion()
    test_group_finder_expansion()
    test_guild_events_creation_and_network_receive()
    test_saved_variables_restore_legacy_events()
    test_ui_title_resolution_expansion()
    print("Dungeon wings expansion (DM, Strat, Mara) tests passed")
