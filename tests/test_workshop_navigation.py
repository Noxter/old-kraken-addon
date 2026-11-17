"""Regression tests for Workshop navigation, recipe-picker lifecycle and order drafts.

The shared Lua client fixture lives in test_workshop_orders.py so both suites exercise
the same WoW API stubs and embedded/standalone layouts.
"""
from test_workshop_orders import client, tick


def test_navigation_stack_is_idempotent_and_bounded():
    lua = client("Nav", embedded=True)
    tick(lua)
    lua.execute("""
        OldKraken.Workshop:Show('orders')
        local w=OldKraken.Workshop
        assert(w.currentView=='orders')
        assert(#w.navigationStack==0)

        assert(w:Navigate('recipes')==true)
        assert(w.currentView=='recipes' and #w.navigationStack==1)
        assert(w:Navigate('recipes')==false)
        assert(#w.navigationStack==1, 'same-view navigation pushed a duplicate entry')

        assert(w:Navigate('orders')==true)
        assert(w.currentView=='orders' and #w.navigationStack==2)
        w:Back()
        assert(w.currentView=='recipes' and #w.navigationStack==1)
        w:Back()
        assert(w.currentView=='orders' and #w.navigationStack==0)
        w:Back()
        assert(#w.navigationStack==0, 'Back underflowed an empty stack')

        for i=1,30 do
            w:Navigate(i%2==0 and 'recipes' or 'orders')
        end
        assert(#w.navigationStack==20, 'navigation history exceeded its documented cap')
    """)


def test_recipe_picker_cancel_returns_to_order_form_without_losing_draft():
    lua = client("Picker", embedded=True)
    tick(lua)
    lua.execute("""
        OldKraken.WorkshopOrders:Show()
        local w=OldKraken.Workshop
        assert(w.currentView=='orders')
        assert(OldKraken.WorkshopOrders:OpenCreateForm())
        assert(w.currentView=='orderCreate')

        local workshop=OldKraken.UIHub.pages.workshop.frame
        local orderPanel=workshop.ordersView
        local form=orderPanel.createForm
        form.item:SetText('Elixir of Test')
        form.quantity:SetText('3')
        form.note:SetText('Keep these values')
        selectOption(OldKrakenOrderProfession,171)
        selectOption(orderPanel.deadlineMenu,21600)

        local saved=OldKraken.DB.workshop.guilds['Realm\\001Guild'].orderDrafts['Picker Mon']
        assert(saved and saved.item=='Elixir of Test' and saved.quantity=='3')
        assert(saved.note=='Keep these values')
        assert(saved.profession==171 and saved.deadline==21600)

        local callbackCalled=false
        OldKraken.WorkshopRecipes:Choose(function() callbackCalled=true end)
        assert(w.currentView=='recipes', 'recipe picker did not navigate to recipes')
        assert(OldKraken.WorkshopRecipes:IsPicking(), 'picker callback was not registered')
        assert(OldKraken.WorkshopRecipes:GetTab()=='recipes')

        w:Back()
        assert(w.currentView=='orderCreate', 'Back did not return to the order form')
        assert(not OldKraken.WorkshopRecipes:IsPicking(), 'picker remained active after cancellation')
        assert(not callbackCalled, 'cancel unexpectedly selected a recipe')
        assert(form:IsShown(), 'order form was not restored')
        assert(form.item:GetText()=='Elixir of Test')
        assert(form.quantity:GetText()=='3')
        assert(form.note:GetText()=='Keep these values')
        assert(OldKraken.DB.workshop.guilds['Realm\\001Guild'].orderDrafts['Picker Mon'].item=='Elixir of Test')
    """)


def test_order_draft_restores_after_reload_and_is_scoped_to_character_and_guild():
    lua = client("DraftOwner")
    tick(lua)
    lua.execute("""
        OldKraken.WorkshopOrders:Show()
        local f=OldKrakenWorkshopOrdersFrame
        f.item:SetText('Drafted item')
        f.quantity:SetText('4')
        f.note:SetText('Persist me')
        selectOption(OldKrakenOrderProfession,171)
        selectOption(f.materialsMenu,'mixed')
        selectOption(f.deadlineMenu,604800)
        local scope=OldKraken.DB.workshop.guilds['Realm\\001Guild']
        local d=scope.orderDrafts['DraftOwner Mon']
        assert(d and d.item=='Drafted item' and d.quantity=='4')
        assert(d.note=='Persist me' and d.profession==171)
        assert(d.materials=='mixed' and d.deadline==604800)
    """)

    # Simulate a normal /reload: SavedVariables survive and addon modules are reloaded.
    lua.execute("""
        savedDB=OldKraken.DB
        savedDraft=savedDB.workshop.guilds['Realm\\001Guild'].orderDrafts['DraftOwner Mon']
    """)
    from test_workshop_orders import restart
    restart(lua)
    lua.execute("""
        OldKraken.WorkshopOrders:Show()
        local f=OldKrakenWorkshopOrdersFrame
        assert(f.item:GetText()=='Drafted item')
        assert(f.quantity:GetText()=='4')
        assert(f.note:GetText()=='Persist me')
        assert(OldKraken.DB.workshop.guilds['Realm\\001Guild'].orderDrafts['DraftOwner Mon'].materials=='mixed')

        -- A different character in the same guild must not inherit this draft.
        player='AnotherCharacter'
        OldKraken.WorkshopOrders:Show()
        assert(OldKrakenWorkshopOrdersFrame.item:GetText()=='')
        assert(OldKraken.DB.workshop.guilds['Realm\\001Guild'].orderDrafts['DraftOwner Mon'].item=='Drafted item')

        -- The original character's draft remains available when switching back.
        player='DraftOwner'
        OldKraken.WorkshopOrders:Show()
        assert(OldKrakenWorkshopOrdersFrame.item:GetText()=='Drafted item')

        -- The same character in another guild has an independent draft scope.
        function GetGuildInfo() return 'Other Guild' end
        OldKraken.WorkshopOrders:Show()
        assert(OldKrakenWorkshopOrdersFrame.item:GetText()=='')
        function GetGuildInfo() return 'Guild' end
        OldKraken.WorkshopOrders:Show()
        assert(OldKrakenWorkshopOrdersFrame.item:GetText()=='Drafted item')
    """)


def test_successful_publish_clears_only_the_current_character_draft():
    lua = client("Publisher")
    tick(lua)
    lua.execute("""
        OldKraken.WorkshopOrders:Show()
        local f=OldKrakenWorkshopOrdersFrame
        f.item:SetText('Ready to publish')
        selectOption(OldKrakenOrderProfession,171)
        local scope=OldKraken.DB.workshop.guilds['Realm\\001Guild']
        scope.orderDrafts['Other Mon']={item='Keep other character draft'}
        assert(scope.orderDrafts['Publisher Mon'].item=='Ready to publish')
        click('Опублікувати')
        assert(scope.orderDrafts['Publisher Mon']==nil, 'successful publish left a stale draft')
        assert(scope.orderDrafts['Other Mon'].item=='Keep other character draft',
            'publishing one character order cleared another character draft')
    """)


if __name__ == '__main__':
    test_navigation_stack_is_idempotent_and_bounded()
    test_recipe_picker_cancel_returns_to_order_form_without_losing_draft()
    test_order_draft_restores_after_reload_and_is_scoped_to_character_and_guild()
    test_successful_publish_clears_only_the_current_character_draft()
    print('Workshop navigation and draft regression checks passed')
