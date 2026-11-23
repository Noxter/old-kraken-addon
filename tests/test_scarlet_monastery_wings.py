"""Tests for Scarlet Monastery wings split and legacy 'sm' compatibility in ActivityCatalog."""
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


def test_activity_catalog_wings_and_legacy():
    lua = build_env("ukUA")
    lua.execute(
        r"""
        local cat = OldKraken.ActivityCatalog
        assert(cat and cat.dungeon, 'catalog.dungeon must exist')

        local foundWings = {}
        local foundLegacyInDungeon = false
        for _, entry in ipairs(cat.dungeon) do
            if entry.value == 'sm' then foundLegacyInDungeon = true end
            if entry.value:find('^sm%-') then
                assert(not foundWings[entry.value], 'duplicate wing id: ' .. entry.value)
                foundWings[entry.value] = entry
            end
        end

        assert(not foundLegacyInDungeon, 'legacy "sm" must not be offered in catalog.dungeon')
        assert(foundWings['sm-graveyard'], 'sm-graveyard must be in catalog.dungeon')
        assert(foundWings['sm-library'], 'sm-library must be in catalog.dungeon')
        assert(foundWings['sm-armory'], 'sm-armory must be in catalog.dungeon')
        assert(foundWings['sm-cathedral'], 'sm-cathedral must be in catalog.dungeon')

        -- Levels verification
        local gy = foundWings['sm-graveyard']
        assert(gy.min == 30 and gy.max == 35, 'sm-graveyard levels 30-35')
        local lib = foundWings['sm-library']
        assert(lib.min == 33 and lib.max == 38, 'sm-library levels 33-38')
        local arm = foundWings['sm-armory']
        assert(arm.min == 36 and arm.max == 42, 'sm-armory levels 36-42')
        local cath = foundWings['sm-cathedral']
        assert(cath.min == 38 and cath.max == 46, 'sm-cathedral levels 38-46')

        -- Legacy support verification
        assert(cat.legacy and cat.legacy.dungeon, 'catalog.legacy.dungeon must exist')
        local legacyEntry
        for _, entry in ipairs(cat.legacy.dungeon) do
            if entry.value == 'sm' then legacyEntry = entry; break end
        end
        assert(legacyEntry and legacyEntry.min == 30 and legacyEntry.max == 46, 'legacy sm must exist with 30-46')

        -- Artwork verification: all 4 wings and legacy sm share texture 131852
        local mockTexture = {
            texture = nil,
            SetTexture = function(self, tex) self.texture = tex end,
            SetTexCoord = function() end,
        }
        cat.SetArtwork(mockTexture, 'sm')
        assert(mockTexture.texture == 131852, 'legacy sm texture')
        cat.SetArtwork(mockTexture, 'sm-graveyard')
        assert(mockTexture.texture == 131852, 'sm-graveyard texture')
        cat.SetArtwork(mockTexture, 'sm-library')
        assert(mockTexture.texture == 131852, 'sm-library texture')
        cat.SetArtwork(mockTexture, 'sm-armory')
        assert(mockTexture.texture == 131852, 'sm-armory texture')
        cat.SetArtwork(mockTexture, 'sm-cathedral')
        assert(mockTexture.texture == 131852, 'sm-cathedral texture')

        -- IsValidActivity check
        assert(cat.IsValidActivity('dungeon', 'sm-graveyard'), 'sm-graveyard is valid')
        assert(cat.IsValidActivity('dungeon', 'sm-library'), 'sm-library is valid')
        assert(cat.IsValidActivity('dungeon', 'sm-armory'), 'sm-armory is valid')
        assert(cat.IsValidActivity('dungeon', 'sm-cathedral'), 'sm-cathedral is valid')
        assert(cat.IsValidActivity('dungeon', 'sm'), 'legacy sm is valid')
        assert(not cat.IsValidActivity('dungeon', 'sm-unknown'), 'unknown is invalid')
        assert(cat.IsValidActivity('dungeon', ''), 'empty is valid')
    """
    )


def test_localization_wings():
    # Test Ukrainian
    lua_uk = build_env("ukUA")
    lua_uk.execute(
        r"""
        local cat = OldKraken.ActivityCatalog
        local gy, lib, arm, cath
        for _, entry in ipairs(cat.dungeon) do
            if entry.value == 'sm-graveyard' then gy = entry.label end
            if entry.value == 'sm-library' then lib = entry.label end
            if entry.value == 'sm-armory' then arm = entry.label end
            if entry.value == 'sm-cathedral' then cath = entry.label end
        end
        assert(gy == 'Червоний монастир: Цвинтар (SM Gy)', 'UK gy label: ' .. tostring(gy))
        assert(lib == 'Червоний монастир: Бібліотека (SM Lib)', 'UK lib label: ' .. tostring(lib))
        assert(arm == 'Червоний монастир: Зброярня (SM Arm)', 'UK arm label: ' .. tostring(arm))
        assert(cath == 'Червоний монастир: Собор (SM Cath)', 'UK cath label: ' .. tostring(cath))
        assert(cat.legacy.dungeon[1].label == 'Червоний монастир (SM)', 'UK legacy label')
    """
    )

    # Test English
    lua_en = build_env("enUS")
    lua_en.execute(
        r"""
        local cat = OldKraken.ActivityCatalog
        local gy, lib, arm, cath
        for _, entry in ipairs(cat.dungeon) do
            if entry.value == 'sm-graveyard' then gy = entry.label end
            if entry.value == 'sm-library' then lib = entry.label end
            if entry.value == 'sm-armory' then arm = entry.label end
            if entry.value == 'sm-cathedral' then cath = entry.label end
        end
        assert(gy == 'Scarlet Monastery: Graveyard (SM Gy)', 'EN gy label: ' .. tostring(gy))
        assert(lib == 'Scarlet Monastery: Library (SM Lib)', 'EN lib label: ' .. tostring(lib))
        assert(arm == 'Scarlet Monastery: Armory (SM Arm)', 'EN arm label: ' .. tostring(arm))
        assert(cath == 'Scarlet Monastery: Cathedral (SM Cath)', 'EN cath label: ' .. tostring(cath))
        assert(cat.legacy.dungeon[1].label == 'Scarlet Monastery (SM)', 'EN legacy label')
    """
    )


def test_group_finder_wings_and_legacy():
    lua = build_env("ukUA")
    lua.execute(
        r"""
        local f = OldKraken.GroupFinder
        f:Initialize('Tester Realm', function() return true end)
        f.active = true
        function f:CanPerformRole() return true end

        -- Create with each wing
        for _, wing in ipairs({'sm-graveyard', 'sm-library', 'sm-armory', 'sm-cathedral'}) do
            local ok, id = f:Create('Test', 'dungeon', '', 5, 30, 40, 'tank', wing)
            assert(ok, 'create with ' .. wing .. ' must succeed')
            local g = f.groups['Tester Realm\001' .. id]
            assert(g and g.dungeon == wing, 'saved group must have dungeon ' .. wing)

            -- Encoding / receiving preserves wing id
            local payload = f:EncodeGroup(g)
            local other = setmetatable({}, {__index = f})
            other:Initialize('Other Realm', function() return true end)
            local okOther = other:ReceiveGroup('Tester Realm', payload)
            assert(okOther, 'ReceiveGroup with ' .. wing .. ' must succeed')
            local rxGroup = other.groups['Tester Realm\001' .. id]
            assert(rxGroup and rxGroup.dungeon == wing, 'received group must have dungeon ' .. wing)
        end

        -- Legacy 'sm' group compatibility
        local okLegacy, legacyId = f:Create('Legacy SM', 'dungeon', '', 5, 30, 46, 'tank', 'sm')
        assert(okLegacy, 'create with legacy sm must succeed for backwards compat')
        local legGroup = f.groups['Tester Realm\001' .. legacyId]
        assert(legGroup and legGroup.dungeon == 'sm')
        local legPayload = f:EncodeGroup(legGroup)
        local otherLeg = setmetatable({}, {__index = f})
        otherLeg:Initialize('Other Realm', function() return true end)
        local okLegRx = otherLeg:ReceiveGroup('Tester Realm', legPayload)
        assert(okLegRx, 'ReceiveGroup with legacy sm must succeed')
        local rxLegGroup = otherLeg.groups['Tester Realm\001' .. legacyId]
        assert(rxLegGroup and rxLegGroup.dungeon == 'sm')
    """
    )


def test_guild_events_wings_and_legacy():
    lua = build_env("ukUA")
    lua.execute(
        r"""
        local events = OldKraken.GuildEvents

        -- Create event for each of the 4 wings
        for _, wing in ipairs({'sm-graveyard', 'sm-library', 'sm-armory', 'sm-cathedral'}) do
            local ok = events:Create('Event ' .. wing, '', now + 3600, 'dungeon', 5, wing)
            assert(ok, 'event create with ' .. wing .. ' must succeed')
        end

        -- Legacy 'sm' event compatibility
        local okLegacy = events:Create('Legacy Event', '', now + 3600, 'dungeon', 5, 'sm')
        assert(okLegacy, 'legacy sm event create must succeed')

        -- Invalid activity rejected
        local okBad = events:Create('Bad Event', '', now + 3600, 'dungeon', 5, 'sm-nonexistent')
        assert(not okBad, 'unknown activity must be rejected')

        -- Test canonical title display for wings and legacy
        local titleGy = events:DisplayTitle({title='Червоний монастир: Цвинтар (SM Gy)', activity='sm-graveyard'})
        assert(titleGy == 'Червоний монастир: Цвинтар (SM Gy)', 'canonical title gy: ' .. tostring(titleGy))
        local titleLegacy = events:DisplayTitle({title='Червоний монастир (SM)', activity='sm'})
        assert(titleLegacy == 'Червоний монастир (SM)', 'canonical title legacy: ' .. tostring(titleLegacy))
    """
    )


def test_guild_events_receive_network_event():
    lua = build_env("ukUA")
    lua.execute(
        r"""
        local codec = OldKraken.GroupFinder
        local handler = eventHandlers['CVNEW']
        assert(handler, 'CVNEW handler must be registered')
        local storageKey = 'Realm\001Guild\001Tester Realm'

        -- 1. Valid event with sm-graveyard
        local payloadGy = codec._pack({
            '1700000000-1', 'OtherPlayer', '1', tostring(now + 3600), 'dungeon', '5', '0',
            'Graveyard Run', '', '1', 'OtherPlayer', 'tank', 'sm-graveyard', 'A'
        })
        handler('OtherPlayer', '1700000000-1', payloadGy)
        local observed1 = OldKraken.DB.events.guildCalendarV1[storageKey].observed
        local savedGy = observed1 and observed1['OtherPlayer\0011700000000-1']
        assert(savedGy and savedGy.activity == 'sm-graveyard', 'sm-graveyard event must be received and stored')

        -- 2. Valid event with legacy sm
        local payloadLegacy = codec._pack({
            '1700000000-2', 'OtherPlayer', '1', tostring(now + 3600), 'dungeon', '5', '0',
            'Legacy SM Run', '', '1', 'OtherPlayer', 'tank', 'sm', 'A'
        })
        handler('OtherPlayer', '1700000000-2', payloadLegacy)
        local observed2 = OldKraken.DB.events.guildCalendarV1[storageKey].observed
        local savedLegacy = observed2 and observed2['OtherPlayer\0011700000000-2']
        assert(savedLegacy and savedLegacy.activity == 'sm', 'legacy sm event must be received and stored')

        -- 3. Invalid activity rejected
        local payloadBad = codec._pack({
            '1700000000-3', 'OtherPlayer', '1', tostring(now + 3600), 'dungeon', '5', '0',
            'Bad Run', '', '1', 'OtherPlayer', 'tank', 'sm-unknown', 'A'
        })
        handler('OtherPlayer', '1700000000-3', payloadBad)
        local observed3 = OldKraken.DB.events.guildCalendarV1[storageKey].observed
        local savedBad = observed3 and observed3['OtherPlayer\0011700000000-3']
        assert(savedBad == nil, 'unknown activity event must be rejected by decode')
    """
    )


def test_ui_activity_options_and_title_resolution():
    for lang, expectedGy, expectedLegacy in (
        ("ukUA", "Червоний монастир: Цвинтар (SM Gy)", "Червоний монастир (SM)"),
        ("enUS", "Scarlet Monastery: Graveyard (SM Gy)", "Scarlet Monastery (SM)"),
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
            f"""
            local cat = OldKraken.ActivityCatalog
            local finder = OldKraken.GroupFinder

            -- Test canonical group title resolution for wings and legacy
            local gyTitle = finder:DisplayTitle({{title = '{expectedGy}', dungeon = 'sm-graveyard'}})
            assert(gyTitle == '{expectedGy}', 'displayGroupTitle for wing in {lang}: ' .. tostring(gyTitle))

            local legTitle = finder:DisplayTitle({{title = '{expectedLegacy}', dungeon = 'sm'}})
            assert(legTitle == '{expectedLegacy}', 'displayGroupTitle for legacy sm in {lang}: ' .. tostring(legTitle))

            -- Verify catalog.dungeon does NOT offer legacy 'sm' but contains all 4 wings
            local hasLegacyInDungeon = false
            local wingCount = 0
            for _, entry in ipairs(cat.dungeon) do
                if entry.value == 'sm' then hasLegacyInDungeon = true end
                if entry.value:find('^sm%-') then wingCount = wingCount + 1 end
            end
            assert(not hasLegacyInDungeon, 'catalog.dungeon must not contain legacy sm')
            assert(wingCount == 4, 'catalog.dungeon must contain all 4 wings')
        """
        )


if __name__ == "__main__":
    test_activity_catalog_wings_and_legacy()
    test_localization_wings()
    test_group_finder_wings_and_legacy()
    test_guild_events_wings_and_legacy()
    test_guild_events_receive_network_event()
    test_ui_activity_options_and_title_resolution()
    print("Scarlet Monastery wings and legacy compatibility checks passed")
