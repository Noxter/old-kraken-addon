"""Tests for Workshop order item localization and unified standalone recipe picker."""
from pathlib import Path
from test_workshop_orders import client, flush, tick

ROOT = Path(__file__).resolve().parents[1]


def test_order_item_localization():
    alice = client("Alice")
    bob = client("Bob")
    tick(alice)
    tick(bob)

    # Bob has recipe 118 (itemID 118) and is on an enUS client where item 118 is initially uncached.
    bob.execute(
        """
        local loaded = false
        local requests = 0
        C_Item = {
            GetItemNameByID = function(id)
                if id == 118 and loaded then return 'Minor Healing Potion' end
            end,
            GetItemIconByID = function() return 134400 end,
            RequestLoadItemDataByID = function(id)
                if id == 118 then requests = requests + 1 end
            end,
        }
        function GetItemInfo(id)
            if id == 118 and loaded then return 'Minor Healing Potion' end
        end
        _setLoaded = function(v) loaded = v end
        _getRequests = function() return requests end
        """
    )

    # Alice (ruRU sender) creates an order with Russian raw item text and valid itemID=118.
    alice.execute(
        """
        local scope = OldKraken.DB.workshop.guilds['Realm\\001Guild']
        scope.recipes['Bob Mon'] = scope.recipes['Bob Mon'] or {}
        scope.recipes['Bob Mon'][2001] = {recipe=2001, item=118, profession=171, seen=now, name='Зелье лечения', product='Зелье лечения'}
        OldKraken.WorkshopOrders:Show()
        local f = OldKrakenWorkshopOrdersFrame
        -- Clicking the recipe button in standalone opens the recipe catalog.
        f.orderForm.item.scripts.OnClick(f.orderForm.item)
        assert(OldKraken.WorkshopRecipes:IsPicking())
        -- Selecting a recipe fills name, itemID, recipeID, and profession.
        local pick = OldKraken.WorkshopRecipes
        -- Simulate picking Bob's recipe via the callback stored on Recipes.
        local rows = OldKrakenWorkshopRecipesFrame
        """
    )

    # Directly test received ruRU order on enUS receiver (Bob) before and after item data loads.
    bob.execute(
        """
        local scope = OldKraken.DB.workshop.guilds['Realm\\001Guild']
        -- Inject an order as received from Alice with Russian raw o.item and valid itemID=118.
        local codec = OldKraken.GroupFinder
        local payload = codec._pack({'Alice Mon', 'ord-1', 1, now, now + 86400, 171, 'Зелье лечения', 1, 0, 'customer', 'Коментар користувача', 'open', '', 0, 0, 118, 2001, 0, 0, 0})
        handlers.WORDER('Alice Mon', 'GUILD', payload)
        local o = scope.orderObserved['Alice Mon\\001ord-1']
        assert(o and o.item == 'Зелье лечения' and o.itemID == 118 and o.recipeID == 2001)
        assert(o.note == 'Коментар користувача')

        -- 1. Before item data loads: Russian raw text must NOT be shown; placeholder is shown instead.
        assert(_getRequests() >= 1)
        local lastNotice = notices[#notices]
        assert(lastNotice and not lastNotice[2]:find('Зелье', 1, true), 'Notice leaked Russian text: ' .. tostring(lastNotice[2]))
        assert(lastNotice[2]:find('Завантаження назви', 1, true))

        OldKraken.WorkshopOrders:Show('Alice Mon\\001ord-1')
        local f = OldKrakenWorkshopOrdersFrame
        local cardTitle = f.orderRows[1].title.text
        assert(not cardTitle:find('Зелье', 1, true), 'Card title leaked Russian text: ' .. tostring(cardTitle))
        assert(cardTitle:find('Завантаження назви', 1, true))
        assert(not f.details.text:find('Зелье', 1, true), 'Details leaked Russian text')
        assert(f.details.text:find('Коментар користувача', 1, true), 'User note must remain intact')

        -- Tooltip before load
        f.orderRows[1].scripts.OnEnter(f.orderRows[1])
        assert(not tooltipTitle:find('Зелье', 1, true))

        -- 2. After ITEM_DATA_LOAD_RESULT: all UI surfaces update to English 'Minor Healing Potion'.
        _setLoaded(true)
        for _, frame in ipairs(frames) do
            if frame.events and frame.events.ITEM_DATA_LOAD_RESULT then
                frame.scripts.OnEvent(frame, 'ITEM_DATA_LOAD_RESULT', 118, true)
            end
        end
        tick()
        assert(f.orderRows[1].title.text == 'Minor Healing Potion')
        assert(f.details.text:find('Minor Healing Potion', 1, true))
        assert(not f.details.text:find('Зелье', 1, true))
        f.orderRows[1].scripts.OnEnter(f.orderRows[1])
        assert(tooltipTitle == 'Minor Healing Potion')

        -- 3. Search finds order by localized display name.
        local searchBox
        for _, fr in ipairs(frames) do
            if fr.kind == 'EditBox' and fr.parent == f and fr ~= f.orderForm.quantity and fr ~= f.orderForm.note then
                searchBox = fr
            end
        end
        assert(searchBox, 'Search EditBox not found')
        searchBox:SetText('Minor Healing')
        searchBox.scripts.OnTextChanged(searchBox)
        assert(f.orderRows[1]:IsShown() and f.orderRows[1].title.text == 'Minor Healing Potion')
        searchBox:SetText('')
        searchBox.scripts.OnTextChanged(searchBox)

        -- 4. Raw o.item in SavedVariables and encoded payload remain unchanged.
        assert(o.item == 'Зелье лечения')
        assert(scope.orderRelays['Alice Mon\\001ord-1']:find('Зелье лечения', 1, true))

        -- 5. Old/manual order with itemID == 0 keeps textual fallback.
        local oldPayload = codec._pack({'Alice Mon', 'ord-old', 1, now, now + 86400, 171, 'Legacy Manual Item', 1, 0, 'customer', 'Old note', 'open', '', 0, 0, 0, 0, 0, 0, 0})
        handlers.WORDER('Alice Mon', 'GUILD', oldPayload)
        OldKraken.WorkshopOrders:Show('Alice Mon\\001ord-old')
        assert(f.details.text:find('Legacy Manual Item', 1, true))

        -- 6. Popup confirmation uses localized display name.
        local p = codec._pack({'Alice Mon', 'ord-1', 2, now, now + 86400, 171, 'Зелье лечения', 1, 0, 'customer', 'Коментар користувача', 'assigned', 'Bob Mon', 0, 0, 118, 2001, 0, 2, 0})
        handlers.WORDER('Alice Mon', 'GUILD', p)
        assert(notices[#notices][3]:find('Minor Healing Potion', 1, true))
        assert(not notices[#notices][3]:find('Зелье', 1, true))
        -- Test StaticPopup_Show on owner cancel action with localized item name.
        scope.orderOwners['Bob Mon'] = scope.orderOwners['Bob Mon'] or {}
        scope.orderOwners['Bob Mon']['Bob Mon\\001ord-pop'] = {owner='Bob Mon', id='ord-pop', rev=1, created=now+1, deadline=now+86400, profession=171, item='Зелье лечения', itemID=118, recipeID=2001, quantity=1, reward=0, rewardSilver=0, materials='customer', note='', status='open', candidates={}, acks={}}
        OldKraken.WorkshopOrders:Show('Bob Mon\\001ord-pop')
        f.orderRows[1].cancel.scripts.OnClick(f.orderRows[1].cancel)
        assert(popup and popup.arg1 == 'Minor Healing Potion')
        """
    )


def test_standalone_recipe_picker_and_validation():
    alice = client("Alice")
    tick(alice)

    alice.execute(
        """
        local scope = OldKraken.DB.workshop.guilds['Realm\\001Guild']
        scope.recipes['Bob Mon'] = {
            [3001] = {recipe=3001, item=2454, profession=171, seen=now, name='Elixir of Lion', product='Elixir of Lion'}
        }
        OldKraken:Fire('INITIALIZED', OldKraken.DB)
        OldKraken.WorkshopOrders:Show()
        local f = OldKrakenWorkshopOrdersFrame

        -- Standalone form must use button, not EditBox, and block creation without chosen recipe.
        assert(f.orderForm.item.kind == 'Button' or type(f.orderForm.item.scripts.OnClick) == 'function')
        assert(f.orderForm.item:GetText() == 'Обрати рецепт')
        selectOption(OldKrakenOrderProfession, 171)
        click('Опублікувати')
        assert(next(scope.orderOwners['Alice Mon']) == nil, 'Order must not be created without a chosen recipe')

        -- Open recipe catalog from standalone form and pick Bob's recipe.
        f.orderForm.item.scripts.OnClick(f.orderForm.item)
        assert(OldKraken.WorkshopRecipes:IsPicking())
        local rf = OldKrakenWorkshopRecipesFrame
        -- Trigger recipe selection on the first visible recipe row.
        local picked = false
        for _, row in ipairs(frames) do
            if type(row.entry) == 'table' and type(row.entry.record) == 'table' and row.entry.record.recipe == 3001 and row.scripts.OnClick then
                row.scripts.OnClick(row)
                picked = true
                break
            end
        end
        assert(picked, 'Could not find Bob recipe row in picker')
        assert(f.orderForm.item:GetText() == 'Elixir of Lion')
        f.orderForm.note:SetText('Please craft ASAP')
        click('Опублікувати')

        local k, o = next(scope.orderOwners['Alice Mon'])
        assert(o, 'Order should be created after picking a recipe')
        assert(o.itemID == 2454 and o.recipeID == 3001 and o.profession == 171)
        assert(o.note == 'Please craft ASAP')
        """
    )


test_order_item_localization()
test_standalone_recipe_picker_and_validation()
print("Workshop order localization and standalone picker tests passed")
