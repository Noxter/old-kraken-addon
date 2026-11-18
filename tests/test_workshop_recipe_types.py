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
        assert(dd.text == 'Броня')
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
        OldKraken.WorkshopRecipes:Choose(function() end, 171)
        assert(not dd:IsShown(), 'standalone selectRecipe must hide type filter to avoid overlap')
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


if __name__ == '__main__':
    test_recipe_type_filter()
    test_standalone_type_filter()
    test_global_getiteminfo_fallback()
    test_type_cache_invalidates_on_item_change()
    print('Workshop recipe type filter checks passed')
