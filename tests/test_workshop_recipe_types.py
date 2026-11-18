from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_workshop_orders import client, tick


def test_recipe_type_filter():
    lua = client('TypeTester', embedded=True)
    tick(lua)
    lua.execute('''
        local loaded = false
        local items = {
            [5001] = {'Healing Potion', 'Consumable', 'Potion', '', 0, 1, 0},
            [5002] = {'Mongoose Elixir', 'Consumable', 'Elixir', '', 0, 2, 0},
            [5003] = {'Breastplate', 'Armor', 'Plate', 'INVTYPE_CHEST', 4, 4, 0},
            [5004] = {'Arcanite Reaper', 'Weapon', 'Axe', 'INVTYPE_2HWEAPON', 2, 1, 0},
            [5005] = {'Runecloth Bag', 'Container', 'Bag', 'INVTYPE_BAG', 1, 0, 0},
            [5007] = {'BoP Ring', 'Armor', 'Miscellaneous', 'INVTYPE_FINGER', 4, 0, 1},
            [5008] = {'Elemental Ore', 'Tradeskill', 'Other', '', 7, 0, 0},
            [5009] = {'Aegis Shield', 'Armor', 'Shields', 'INVTYPE_SHIELD', 4, 6, 0},
            [5010] = {'Mage Tome', 'Armor', 'Miscellaneous', 'INVTYPE_HOLDABLE', 4, 0, 0},
            [5011] = {'Ruby Necklace', 'Armor', 'Miscellaneous', 'INVTYPE_NECK', 4, 0, 0},
        }
        -- Forever 1.60.1 exposes C_Item.GetItemInfo without global GetItemInfo.
        GetItemInfo = nil
        C_Item = C_Item or {}
        C_Item.GetItemInfo = function(id)
            if id == 5006 then
                if not loaded then return nil end
                return 'Late Helm', nil, 2, 1, 1, 'Armor', 'Mail', 1, 'INVTYPE_HEAD', 134400, 0, 4, 3, 0
            end
            local d = items[id]
            if not d then return nil end
            return d[1], nil, 1, 1, 1, d[2], d[3], 1, d[4], 134400, 0, d[5], d[6], d[7]
        end

        local scope = OldKraken.DB.workshop.guilds['Realm\\001Guild']
        local alch = {}
        for i = 1, 12 do
            alch[8000 + i] = {recipe = 8000 + i, item = 5001, profession = 171, seen = GetServerTime(), name = 'Potion ' .. i, product = 'Potion ' .. i}
        end
        alch[8020] = {recipe = 8020, item = 5002, profession = 171, seen = GetServerTime(), name = 'Elixir A', product = 'Elixir A'}
        alch[8021] = {recipe = 8021, item = 5008, profession = 171, seen = GetServerTime(), name = 'Elemental Ore', product = 'Elemental Ore'}
        scope.recipes['Crafter Mon'] = alch

        local smith = {
            [8101] = {recipe = 8101, item = 5003, profession = 164, seen = GetServerTime(), name = 'Chest A', product = 'Chest A'},
            [8102] = {recipe = 8102, item = 5004, profession = 164, seen = GetServerTime(), name = 'Axe A', product = 'Axe A'},
            [8103] = {recipe = 8103, item = 5006, profession = 164, seen = GetServerTime(), name = 'Late Helm', product = 'Late Helm'},
            [8104] = {recipe = 8104, item = 5007, profession = 164, seen = GetServerTime(), name = 'BoP Ring', product = 'BoP Ring'},
            [8105] = {recipe = 8105, item = 5009, profession = 164, seen = GetServerTime(), name = 'Aegis Shield', product = 'Aegis Shield'},
            [8106] = {recipe = 8106, item = 5010, profession = 164, seen = GetServerTime(), name = 'Mage Tome', product = 'Mage Tome'},
        }
        scope.recipes['Smith Mon'] = smith
        scope.recipes['OtherSmith Mon'] = {
            [8101] = {recipe = 8101, item = 5003, profession = 164, seen = GetServerTime(), name = 'Chest A', product = 'Chest A'},
            [8107] = {recipe = 8107, item = 5011, profession = 164, seen = GetServerTime(), name = 'Ruby Necklace', product = 'Ruby Necklace'},
        }
        scope.recipes['Enchanter Mon'] = {
            [8201] = {recipe = 8201, item = 0, profession = 333, seen = GetServerTime(), name = 'Enchant Chest', product = ''},
        }

        local function drainTimers()
            while #timers > 0 do
                local pending = timers; timers = {}
                for _, t in ipairs(pending) do t() end
            end
        end

        _G.OldKrakenRecipeTypeFilterButton = CreateFrame('Button')
        OldKraken.Workshop:Show()
        OldKraken.WorkshopRecipes:ShowProfession(171)
        drainTimers()

        local recipesView = OldKraken.UIHub.pages.workshop.frame.recipesView
        local dd = OldKrakenRecipeTypeFilter
        assert(dd and dd:IsShown(), 'type filter dropdown must be visible in embedded recipes view')
        assert(recipesView.page.text == '1 / 2', '14 alchemy recipes must paginate with PAGE_SIZE = 10')

        -- Move to page 2, then filter to elixir: must reset to page 1.
        recipesView.nextPage.scripts.OnClick(recipesView.nextPage)
        assert(recipesView.page.text == '2 / 2')

        local function dropdownOptions()
            choices = {}
            dd.dropdown(dd, 1)
            return choices
        end

        local alchOpts = dropdownOptions()
        local alchKeys = {}
        for _, o in ipairs(alchOpts) do alchKeys[o.value] = true end
        assert(alchKeys.all and alchKeys.potion and alchKeys.elixir and alchKeys.reagent and not alchKeys.flask and not alchKeys.armor,
            'only present alchemy categories (including Tradeskill reagent) should appear in dropdown')

        -- Text search must NOT alter available dropdown categories.
        recipesView.query:SetText('Elixir')
        recipesView.query.scripts.OnTextChanged(recipesView.query)
        local afterSearchOpts = dropdownOptions()
        assert(#afterSearchOpts == #alchOpts, 'type dropdown categories must stay stable during text search')

        -- Simultaneous text search + type filter.
        for _, o in ipairs(alchOpts) do if o.value == 'elixir' then o.func() end end
        assert(recipesView.page.text == '1 / 1', 'selecting a category must reset pagination to page 1')
        assert(recipesView.count.text:find('Знайдено: 1 ', 1, true))
        recipesView.query:SetText('')
        recipesView.query.scripts.OnTextChanged(recipesView.query)
        assert(recipesView.count.text:find('Знайдено: 1 ', 1, true), 'elixir filter must stay active after clearing search')

        -- Switching profession must reset type filter to all.
        OldKraken.WorkshopRecipes:ShowProfession(164)
        drainTimers()
        assert(dd.text == 'Усі типи', 'switching profession must reset type filter')

        -- BoP ring (5007) must be excluded; uncached 5006 temporarily lands in other (along with holdable 5010).
        local smithOptsBefore = dropdownOptions()
        local beforeSet = {}
        for _, o in ipairs(smithOptsBefore) do beforeSet[o.value] = true end
        assert(beforeSet.armor and beforeSet.weapon and beforeSet.other, 'uncached item should temporarily appear in other')
        assert(beforeSet.trinket, 'non-BoP neck 5011 should appear under trinket/accessories')

        -- Test ITEM_DATA_LOAD_RESULT (in addition to GET_ITEM_INFO_RECEIVED) for 5006.
        loaded = true
        for _, f in ipairs(frames) do
            if f.scripts and f.scripts.OnEvent and f.events and f.events.ITEM_DATA_LOAD_RESULT then
                f.scripts.OnEvent(f, 'ITEM_DATA_LOAD_RESULT', 5006, true)
            end
        end
        drainTimers()

        -- Filter to armor: must include Chest A, Aegis Shield, Late Helm (loaded), and NOT BoP Ring.
        for _, o in ipairs(dropdownOptions()) do if o.value == 'armor' then o.func() end end
        assert(recipesView.count.text:find('Знайдено: 3 ', 1, true), 'armor should contain Chest A, Shield, and Late Helm')

        -- Switching between two masters who both have armor must reset selectedType to all.
        OldKraken.WorkshopRecipes:ShowMemberProfession('Smith Mon', 164)
        drainTimers()
        for _, o in ipairs(dropdownOptions()) do if o.value == 'armor' then o.func() end end
        assert(dd.text == '|cffe0b052Тип: Броня|r')
        OldKraken.WorkshopRecipes:ShowMemberProfession('OtherSmith Mon', 164)
        drainTimers()
        assert(dd.text == 'Усі типи', 'switching viewOwner must reset selectedType even when both have armor')

        -- Embedded "All Recipes" tab works with type filter.
        OldKraken.WorkshopRecipes:SelectTab('recipes')
        drainTimers()
        assert(dd:IsShown() and dd.text == 'Усі типи')

        -- Enchanting (item == 0) safely falls back to other without breaking All Types.
        OldKraken.WorkshopRecipes:ShowProfession(333)
        drainTimers()
        assert(recipesView.count.text:find('Знайдено: 1 ', 1, true))

        -- Embedded selectRecipe keeps type filter visible to the right of profession picker.
        local placedX
        local origSetPoint = dd.SetPoint
        dd.SetPoint = function(self, _, _, _, x, ...) placedX = x; return origSetPoint(self, _, _, _, x, ...) end
        OldKraken.WorkshopRecipes:Choose(function() end, 171)
        drainTimers()
        assert(dd:IsShown() and placedX == 612, 'embedded selectRecipe should place type filter at x=612')
    ''')


def test_standalone_type_filter():
    lua = client('StandaloneTypes', embedded=False)
    tick(lua)
    lua.execute('''
        GetItemInfo = nil
        C_Item = C_Item or {}
        C_Item.GetItemInfo = function(id)
            if id == 5001 then return 'Healing Potion', nil, 1, 1, 1, 'Consumable', 'Potion', 1, '', 134400, 0, 0, 1, 0 end
        end
        local scope = OldKraken.DB.workshop.guilds['Realm\\001Guild']
        scope.recipes['Crafter Mon'] = {
            [8001] = {recipe = 8001, item = 5001, profession = 171, seen = GetServerTime(), name = 'Potion 1', product = 'Potion 1'},
        }
        OldKraken.WorkshopRecipes:Show()
        while #timers > 0 do
            local pending = timers; timers = {}
            for _, t in ipairs(pending) do t() end
        end
        local dd = OldKrakenRecipeTypeFilter
        assert(dd and dd:IsShown(), 'standalone recipes window must show type filter')
        choices = {}
        dd.dropdown(dd, 1)
        assert(choices[1].minWidth == 160, 'standalone dropdown must set minWidth=160')
        for _, o in ipairs(choices) do if o.value == 'potion' then o.func() end end
        assert(dd.text == '|cffe0b052Тип: Зілля|r', 'standalone active filter must use gold label')
        OldKraken.WorkshopRecipes:Choose(function() end, 171)
        assert(not dd:IsShown(), 'standalone selectRecipe must hide type filter to avoid overlap')
    ''')


def test_armor_slots_and_submenu():
    lua = client('ArmorSlotsSubmenu', embedded=True)
    tick(lua)
    lua.execute('''
        local lateLoaded = false
        local items = {
            [6001] = {'Head Item', 'Armor', 'Plate', 'INVTYPE_HEAD', 4, 4, 0},
            [6002] = {'Shoulder Item', 'Armor', 'Plate', 'INVTYPE_SHOULDER', 4, 4, 0},
            [6003] = {'Back Item', 'Armor', 'Cloth', 'INVTYPE_CLOAK', 4, 1, 0},
            [6004] = {'Chest Item', 'Armor', 'Plate', 'INVTYPE_CHEST', 4, 4, 0},
            [6005] = {'Robe Item', 'Armor', 'Cloth', 'INVTYPE_ROBE', 4, 1, 0},
            [6006] = {'Shirt Item', 'Armor', 'Miscellaneous', 'INVTYPE_BODY', 4, 0, 0},
            [6007] = {'Wrist Item', 'Armor', 'Plate', 'INVTYPE_WRIST', 4, 4, 0},
            [6008] = {'Hands Item', 'Armor', 'Plate', 'INVTYPE_HAND', 4, 4, 0},
            [6009] = {'Waist Item', 'Armor', 'Plate', 'INVTYPE_WAIST', 4, 4, 0},
            [6010] = {'Legs Item', 'Armor', 'Plate', 'INVTYPE_LEGS', 4, 4, 0},
            [6011] = {'Feet Item', 'Armor', 'Plate', 'INVTYPE_FEET', 4, 4, 0},
            [6012] = {'Shield Item', 'Armor', 'Shields', 'INVTYPE_SHIELD', 4, 6, 0},
            [6013] = {'NoLoc Armor', 'Armor', 'Cloth', '', 4, 1, 0},
        }
        GetItemInfo = nil
        C_Item = C_Item or {}
        C_Item.GetItemInfo = function(id)
            if id == 6014 then
                if not lateLoaded then return nil end
                return 'Late Pants', nil, 2, 1, 1, 'Armor', 'Mail', 1, 'INVTYPE_LEGS', 134400, 0, 4, 3, 0
            end
            local d = items[id]
            if not d then return nil end
            return d[1], nil, 1, 1, 1, d[2], d[3], 1, d[4], 134400, 0, d[5], d[6], d[7]
        end

        local scope = OldKraken.DB.workshop.guilds['Realm\\001Guild']
        local smith = {}
        for idx = 1, 13 do
            smith[9000 + idx] = {recipe = 9000 + idx, item = 6000 + idx, profession = 164, seen = GetServerTime(), name = 'Item ' .. idx, product = 'Item ' .. idx}
        end
        scope.recipes['MasterA Mon'] = smith
        scope.recipes['MasterB Mon'] = {
            [9001] = {recipe = 9001, item = 6001, profession = 164, seen = GetServerTime(), name = 'Head Only', product = 'Head Only'},
        }
        scope.recipes['TailorC Mon'] = {
            [9101] = {recipe = 9101, item = 6014, profession = 197, seen = GetServerTime(), name = 'Late Pants', product = 'Late Pants'},
        }

        local function drainTimers()
            while #timers > 0 do
                local pending = timers; timers = {}
                for _, t in ipairs(pending) do t() end
            end
        end

        _G.OldKrakenRecipeTypeFilterButton = CreateFrame('Button')
        OldKraken.Workshop:Show()
        OldKraken.WorkshopRecipes:ShowProfession(164)
        drainTimers()

        local recipesView = OldKraken.UIHub.pages.workshop.frame.recipesView
        local dd = OldKrakenRecipeTypeFilter
        assert(dd.text == 'Усі типи', 'default filter label must be Усі типи')

        -- Level 1 must contain only base categories, no armor:* subcategories, and armor must have hasArrow + menuList.
        choices = {}
        dd.dropdown(dd, 1)
        local armorItem
        for _, o in ipairs(choices) do
            assert(not o.value:find(':', 1, true), 'level 1 must not contain armor:* subcategories: ' .. tostring(o.value))
            assert(o.minWidth == 170, 'embedded level 1 must set minWidth=170')
            if o.value == 'armor' then armorItem = o end
        end
        assert(armorItem and armorItem.hasArrow and armorItem.menuList == 'armor', 'armor must open level 2 submenu')

        -- Level 2 must start with 'Уся броня' and list all 11 armor slots in fixed order (CHEST + ROBE grouped under armor:chest).
        choices = {}
        dd.dropdown(dd, 2, 'armor')
        local expectedSlots = {
            'armor', 'armor:head', 'armor:shoulder', 'armor:back', 'armor:chest', 'armor:shirt',
            'armor:wrist', 'armor:hands', 'armor:waist', 'armor:legs', 'armor:feet', 'armor:shield',
        }
        assert(#choices == #expectedSlots, 'level 2 must contain Уся броня + 11 slots, got ' .. #choices)
        for i, v in ipairs(expectedSlots) do
            assert(choices[i].value == v and choices[i].level == 2, 'slot order mismatch at ' .. i)
        end
        assert(choices[1].text == 'Уся броня')

        -- Selecting 'Уся броня' matches all 13 items (12 equipLoc slots + 1 subtype-only armor without equipLoc).
        dropdownClosed = 0
        choices[1].func()
        assert(dropdownClosed >= 1, 'selecting Уся броня must close dropdown menus')
        assert(dd.text == '|cffe0b052Тип: Броня|r')
        assert(recipesView.count.text:find('Знайдено: 13 ', 1, true), 'armor must include all 11 slots + subtype-only armor')

        -- Selecting armor:chest matches both INVTYPE_CHEST and INVTYPE_ROBE (2 items).
        choices = {}
        dd.dropdown(dd, 2, 'armor')
        for _, o in ipairs(choices) do if o.value == 'armor:chest' then o.func() end end
        assert(dd.text == '|cffe0b052Тип: Груди|r')
        assert(recipesView.count.text:find('Знайдено: 2 ', 1, true), 'CHEST and ROBE must both classify as armor:chest')

        -- Selecting armor:legs matches only 1 item, closes menus, and marks checked on reopen.
        dropdownClosed = 0
        choices = {}
        dd.dropdown(dd, 2, 'armor')
        for _, o in ipairs(choices) do if o.value == 'armor:legs' then o.func() end end
        assert(dropdownClosed >= 1, 'selecting level 2 slot must call CloseDropDownMenus')
        assert(dd.text == '|cffe0b052Тип: Штани|r')
        assert(recipesView.count.text:find('Знайдено: 1 ', 1, true), 'armor:legs must match only pants')

        choices = {}
        dd.dropdown(dd, 1)
        for _, o in ipairs(choices) do
            if o.value == 'armor' then assert(o.checked, 'level 1 Броня must be checked when an armor slot is active') else assert(not o.checked) end
        end

        choices = {}
        dd.dropdown(dd, 2, 'armor')
        for _, o in ipairs(choices) do
            if o.value == 'armor:legs' then assert(o.checked) else assert(not o.checked) end
        end

        -- Right-clicking the dropdown button resets active filter back to all in one click.
        local typeBtn = _G.OldKrakenRecipeTypeFilterButton
        assert(typeBtn and typeBtn.scripts and typeBtn.scripts.OnClick)
        typeBtn.scripts.OnClick(typeBtn, 'RightButton')
        assert(dd.text == 'Усі типи', 'right-click must reset type filter to Усі типи')
        assert(recipesView.count.text:find('Знайдено: 13 ', 1, true), 'right-click reset must restore full recipe count')

        -- Switching to MasterB Mon (who only has armor:head) must show only 'Уся броня' + 'Голова' in level 2 and reset filter.
        OldKraken.WorkshopRecipes:ShowMemberProfession('MasterB Mon', 164)
        drainTimers()
        assert(dd.text == 'Усі типи', 'switching master must reset filter')
        choices = {}
        dd.dropdown(dd, 2, 'armor')
        assert(#choices == 2 and choices[1].value == 'armor' and choices[2].value == 'armor:head',
            'level 2 must omit absent slots for MasterB Mon')

        -- Switching profession resets filter; late item load updates armor:legs availability in Tailoring.
        OldKraken.WorkshopRecipes:ShowProfession(197)
        drainTimers()
        assert(dd.text == 'Усі типи', 'switching profession must reset filter')
        lateLoaded = true
        for _, f in ipairs(frames) do
            if f.scripts and f.scripts.OnEvent and f.events and f.events.ITEM_DATA_LOAD_RESULT then
                f.scripts.OnEvent(f, 'ITEM_DATA_LOAD_RESULT', 6014, true)
            end
        end
        drainTimers()
        choices = {}
        dd.dropdown(dd, 2, 'armor')
        assert(#choices == 2 and choices[2].value == 'armor:legs', 'late item data load must populate armor:legs in submenu')
    ''')


def test_global_getiteminfo_fallback():
    lua = client('GlobalFallbackTypes', embedded=True)
    tick(lua)
    lua.execute('''
        C_Item = {}
        GetItemInfo = function(id)
            if id == 5002 then return 'Mongoose Elixir', nil, 1, 1, 1, 'Consumable', 'Elixir', 1, '', 134400, 0, 0, 2, 0 end
            if id == 5003 then return 'Breastplate', nil, 1, 1, 1, 'Armor', 'Plate', 1, 'INVTYPE_CHEST', 134400, 0, 4, 4, 0 end
        end
        local scope = OldKraken.DB.workshop.guilds['Realm\\001Guild']
        scope.recipes['Fallback Mon'] = {
            [8020] = {recipe = 8020, item = 5002, profession = 171, seen = GetServerTime(), name = 'Elixir A', product = 'Elixir A'},
            [8101] = {recipe = 8101, item = 5003, profession = 171, seen = GetServerTime(), name = 'Chest A', product = 'Chest A'},
        }
        _G.OldKrakenRecipeTypeFilterButton = CreateFrame('Button')
        OldKraken.Workshop:Show()
        OldKraken.WorkshopRecipes:ShowProfession(171)
        while #timers > 0 do
            local pending = timers; timers = {}
            for _, t in ipairs(pending) do t() end
        end
        local recipesView = OldKraken.UIHub.pages.workshop.frame.recipesView
        local dd = OldKrakenRecipeTypeFilter
        choices = {}
        dd.dropdown(dd, 1)
        local keys = {}
        for _, o in ipairs(choices) do keys[o.value] = true end
        assert(keys.elixir and keys.armor, 'global GetItemInfo fallback must classify items when C_Item.GetItemInfo is absent')
        for _, o in ipairs(choices) do if o.value == 'elixir' then o.func() end end
        assert(recipesView.count.text:find('Знайдено: 1 ', 1, true), 'filtering via global GetItemInfo fallback must match 1 elixir')
    ''')


def test_type_cache_invalidates_on_item_change():
    lua = client('TypeCacheItemMutation', embedded=True)
    tick(lua)
    lua.execute('''
        local calls = {}
        GetItemInfo = nil
        C_Item = C_Item or {}
        C_Item.GetItemInfo = function(id)
            calls[id] = (calls[id] or 0) + 1
            if id == 5001 then return 'Healing Potion', nil, 1, 1, 1, 'Consumable', 'Potion', 1, '', 134400, 0, 0, 1, 0 end
            if id == 5003 then return 'Breastplate', nil, 1, 1, 1, 'Armor', 'Plate', 1, 'INVTYPE_CHEST', 134400, 0, 4, 4, 0 end
        end
        local scope = OldKraken.DB.workshop.guilds['Realm\\001Guild']
        local rec = {recipe = 8501, item = 5001, profession = 171, seen = GetServerTime(), name = 'Dynamic Recipe', product = 'Dynamic Recipe'}
        scope.recipes['Cache Mon'] = { [8501] = rec }

        local function drainTimers()
            while #timers > 0 do
                local pending = timers; timers = {}
                for _, t in ipairs(pending) do t() end
            end
        end

        _G.OldKrakenRecipeTypeFilterButton = CreateFrame('Button')
        OldKraken.Workshop:Show()
        OldKraken.WorkshopRecipes:ShowProfession(171)
        drainTimers()

        local recipesView = OldKraken.UIHub.pages.workshop.frame.recipesView
        local dd = OldKrakenRecipeTypeFilter
        choices = {}
        dd.dropdown(dd, 1)
        local beforeKeys = {}
        for _, o in ipairs(choices) do beforeKeys[o.value] = true end
        assert(beforeKeys.potion and not beforeKeys.armor, 'initial item 5001 must classify as potion')

        -- Mutate r.item on the same profession + recipe, switch context away and back to force re-classification.
        OldKraken.WorkshopRecipes:ShowProfession(164)
        drainTimers()
        rec.item = 5003
        OldKraken.WorkshopRecipes:ShowProfession(171)
        drainTimers()

        choices = {}
        dd.dropdown(dd, 1)
        local afterKeys = {}
        for _, o in ipairs(choices) do afterKeys[o.value] = true end
        assert(afterKeys.armor and not afterKeys.potion, 'typeCache must not reuse stale category when r.item changes for same profession+recipe')
        assert(calls[5003] and calls[5003] >= 1, 'classifyRecipe must query new item 5003 on cache miss')
        for _, o in ipairs(choices) do if o.value == 'armor' then o.func() end end
        assert(recipesView.count.text:find('Знайдено: 1 ', 1, true), 'updated r.item must filter under new armor category')
    ''')


def test_stale_cache_during_context_switch():
    lua = client('StaleCacheGuard', embedded=True)
    tick(lua)
    lua.execute('''
        local origAfter = C_Timer.After
        C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
        local items = {
            [7001] = {'Head Item', 'Armor', 'Plate', 'INVTYPE_HEAD', 4, 4, 0},
            [7002] = {'Legs Item', 'Armor', 'Plate', 'INVTYPE_LEGS', 4, 4, 0},
            [7003] = {'Feet Item', 'Armor', 'Cloth', 'INVTYPE_FEET', 4, 1, 0},
            [7004] = {'Healing Potion', 'Consumable', 'Potion', '', 0, 1, 0},
        }
        GetItemInfo = nil
        C_Item = C_Item or {}
        C_Item.GetItemInfo = function(id)
            local d = items[id]
            if not d then return nil end
            return d[1], nil, 1, 1, 1, d[2], d[3], 1, d[4], 134400, 0, d[5], d[6], d[7]
        end

        local scope = OldKraken.DB.workshop.guilds['Realm\\001Guild']
        scope.recipes['Master1 Mon'] = {
            [9501] = {recipe = 9501, item = 7001, profession = 164, seen = GetServerTime(), name = 'Head', product = 'Head'},
            [9502] = {recipe = 9502, item = 7002, profession = 164, seen = GetServerTime(), name = 'Legs', product = 'Legs'},
        }
        scope.recipes['Master2 Mon'] = {
            [9503] = {recipe = 9503, item = 7003, profession = 164, seen = GetServerTime(), name = 'Feet', product = 'Feet'},
        }
        for i = 1, 205 do
            scope.recipes['Master2 Mon'][9600 + i] = {recipe = 9600 + i, item = 7003, profession = 164, seen = GetServerTime(), name = 'Feet ' .. i, product = 'Feet ' .. i}
        end
        scope.recipes['Alch Mon'] = {
            [9504] = {recipe = 9504, item = 7004, profession = 171, seen = GetServerTime(), name = 'Potion', product = 'Potion'},
        }
        for i = 1, 205 do
            scope.recipes['Alch Mon'][9900 + i] = {recipe = 9900 + i, item = 7004, profession = 171, seen = GetServerTime(), name = 'Potion ' .. i, product = 'Potion ' .. i}
        end

        local function drainTimers()
            while #timers > 0 do
                local pending = timers; timers = {}
                for _, t in ipairs(pending) do t() end
            end
        end

        -- Test A: Master switch before scan completes must not expose previous master's armor slots.
        _G.OldKrakenRecipeTypeFilterButton = CreateFrame('Button')
        OldKraken.Workshop:Show()
        OldKraken.WorkshopRecipes:ShowMemberProfession('Master1 Mon', 164)
        local dd = OldKrakenRecipeTypeFilter
        local recipesView = OldKraken.UIHub.pages.workshop.frame.recipesView
        drainTimers()
        choices = {}
        dd.dropdown(dd, 2, 'armor')
        assert(#choices == 3 and choices[2].value == 'armor:head' and choices[3].value == 'armor:legs')

        -- Switch to Master2 Mon WITHOUT draining timers yet.
        OldKraken.WorkshopRecipes:ShowMemberProfession('Master2 Mon', 164)
        choices = {}
        dd.dropdown(dd, 1)
        for _, o in ipairs(choices) do
            assert(o.value ~= 'armor', 'stale armor category must not appear while new master scan is pending')
            if o.text == 'Завантаження…' then assert(o.disabled and o.func == nil, 'loading placeholder must have no callback') end
        end
        choices = {}
        dd.dropdown(dd, 2, 'armor')
        assert(#choices == 1 and choices[1].disabled and choices[1].func == nil and choices[1].value == nil,
            'level 2 must not expose Master1 armor slots while Master2 scan is pending')

        drainTimers()
        choices = {}
        dd.dropdown(dd, 2, 'armor')
        assert(#choices == 2 and choices[1].value == 'armor' and choices[2].value == 'armor:feet',
            'after Master2 scan completes, only Master2 slots must appear')

        -- Test B & C: Profession switch + repeated dropdown opens before scan completes must not create duplicate jobs or leak old categories.
        local timerCount = 0
        local prevAfter = C_Timer.After
        C_Timer.After = function(delay, fn)
            timerCount = timerCount + 1
            return prevAfter(delay, fn)
        end

        OldKraken.WorkshopRecipes:ShowProfession(171)
        local afterSwitchTimers = timerCount
        choices = {}
        dd.dropdown(dd, 1)
        for _, o in ipairs(choices) do
            assert(o.value ~= 'armor', 'stale armor from Blacksmithing must not appear in Alchemy before scan completes')
            if o.text == 'Завантаження…' then assert(o.disabled and o.func == nil) end
        end
        -- Re-open dropdown while scan is still pending: must NOT schedule duplicate scan job.
        choices = {}
        dd.dropdown(dd, 1)
        assert(timerCount == afterSwitchTimers, 're-opening dropdown during active scan must not spawn duplicate scan jobs')
        for _, o in ipairs(choices) do
            assert(o.value ~= 'armor')
        end
        C_Timer.After = prevAfter

        -- Test D: After scan completes, new profession categories work and filter properly.
        drainTimers()
        choices = {}
        dd.dropdown(dd, 1)
        local hasPotion, hasArmor = false, false
        for _, o in ipairs(choices) do
            if o.value == 'potion' then hasPotion = true; o.func() end
            if o.value == 'armor' then hasArmor = true end
        end
        assert(hasPotion and not hasArmor, 'Alchemy must show potion and not armor after scan completes')
        assert(dd.text == '|cffe0b052Тип: Зілля|r')
        assert(recipesView.count.text:find('Знайдено: 206 ', 1, true))
        C_Timer.After = origAfter
    ''')


if __name__ == '__main__':
    test_recipe_type_filter()
    test_standalone_type_filter()
    test_global_getiteminfo_fallback()
    test_type_cache_invalidates_on_item_change()
    test_armor_slots_and_submenu()
    test_stale_cache_during_context_switch()
    print('Workshop recipe type filter checks passed')
