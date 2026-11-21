"""Tests for Workshop order item localization and unified standalone recipe picker."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def make_client(player_name):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals()._playerName = player_name
    lua.execute(
        """
        player = _playerName
        now = 1700000000
        elapsed = 100
        frames = {}
        notices = {}
        outgoing = {}
        handlers = {}
        tickers = {}
        dropdownTexts = {}
        popup = nil
        tooltipTitle = nil
        function GetTime() return elapsed end
        function GetServerTime() return now end
        function UnitName(u) if u == 'player' then return player, 'Mon' end end
        function GetRealmName() return 'Realm' end
        function GetGuildInfo() return 'Guild' end
        function IsInGuild() return true end
        function GetProfessions() return 1 end
        function GetProfessionInfo() return 'Alchemy', 136240, 300, 300, 0, 0, 171 end
        function print() end
        function date() return '01.01.2026 12:00' end
        function StaticPopup_Show(which, arg1, arg2, cb)
            popup = {which=which, arg1=arg1, arg2=arg2, callback=cb, HookScript=function() end, GetFrameStrata=function() return 'DIALOG' end, SetFrameStrata=function() end}
            return popup
        end
        StaticPopupDialogs = {}
        UISpecialFrames = {}
        UIParent = {}
        C_Timer = {
            After = function(_, fn) if fn then fn() end end,
            NewTicker = function(_, fn) tickers[#tickers + 1] = fn; return {Cancel=function() end} end,
        }
        GameTooltip = {
            SetOwner = function() end,
            SetText = function(_, t) tooltipTitle = t end,
            AddLine = function() end,
            Show = function() end,
            Hide = function() end,
        }
        local menuItems = {}
        function UIDropDownMenu_SetText(f, t) dropdownTexts[f] = t end
        function UIDropDownMenu_SetWidth() end
        function UIDropDownMenu_JustifyText() end
        function UIDropDownMenu_CreateInfo() return {} end
        function UIDropDownMenu_AddButton(info) menuItems[#menuItems + 1] = info end
        function UIDropDownMenu_Initialize(f, cb) f.initialize = cb end
        function selectOption(f, val)
            menuItems = {}
            f.initialize(f, 1)
            for _, item in ipairs(menuItems) do
                if item.value == val then item.func(); return end
            end
            error('Option not found: ' .. tostring(val))
        end
        function click(label)
            for i = #frames, 1, -1 do
                local fr = frames[i]
                if fr.text == label and fr.scripts.OnClick then fr.scripts.OnClick(fr); return end
            end
            error('Button not found: ' .. tostring(label))
        end
        local methods = {}
        function methods:GetParent() return self.parent end
        function methods:SetText(v) self.text = v end
        function methods:GetText() return self.text or '' end
        function methods:SetSize(w, h) self.width, self.height = w, h end
        function methods:SetWidth(w) self.width = w end
        function methods:SetHeight(h) self.height = h end
        function methods:SetPoint() end
        function methods:ClearAllPoints() end
        function methods:SetJustifyH() end
        function methods:SetJustifyV() end
        function methods:SetWordWrap() end
        function methods:SetTextColor() end
        function methods:SetTextInsets() end
        function methods:SetAutoFocus() end
        function methods:SetClampedToScreen() end
        function methods:EnableMouse() end
        function methods:SetTexture() end
        function methods:SetAlpha() end
        function methods:LockHighlight() end
        function methods:UnlockHighlight() end
        function methods:Enable() self.enabled = true end
        function methods:Disable() self.enabled = false end
        function methods:SetEnabled(v) self.enabled = v end
        function methods:Show() self.shown = true end
        function methods:Hide() self.shown = false end
        function methods:SetShown(v) self.shown = v and true or false end
        function methods:IsShown() return self.shown == true end
        function methods:Raise() end
        function methods:GetVerticalScroll() return 0 end
        function methods:SetVerticalScroll() end
        function methods:GetHeight() return 400 end
        function methods:GetStringHeight() return 40 end
        function methods:SetScrollChild() end
        function methods:RegisterEvent(e) self.events[e] = true end
        function methods:SetScript(n, fn) self.scripts[n] = fn end
        function methods:HookScript(n, fn)
            local old = self.scripts[n]
            self.scripts[n] = function(...) if old then old(...) end; fn(...) end
        end
        function methods:CreateFontString() local fs = CreateFrame('FontString'); self._fs = fs; return fs end
        function methods:GetFontString() return self._fs end
        function methods:CreateTexture() return CreateFrame('Texture') end
        local mt = {__index = function(_, k) return methods[k] or function() end end}
        function CreateFrame(kind, name, parent, template)
            local fr = setmetatable({kind=kind, name=name, parent=parent, template=template, scripts={}, events={}, shown=true}, mt)
            if name then _G[name] = fr end
            frames[#frames + 1] = fr
            return fr
        end
        OldKraken = {
            name = 'OldKraken',
            DB = {settings={language='ukUA', workshopOrderAlerts=true}, workshop={guilds={}, recipeCatalog={}}},
            _listeners = {},
            On = function(self, ev, fn)
                self._listeners[ev] = self._listeners[ev] or {}
                table.insert(self._listeners[ev], fn)
            end,
            Fire = function(self, ev, ...)
                if ev == 'WORKSHOP_ORDER_NOTICE' then table.insert(notices, {ev, ...}) end
                for _, fn in ipairs(self._listeners[ev] or {}) do fn(...) end
            end,
            Communication = {
                queue = {},
                RegisterHandler = function(_, k, fn) handlers[k] = fn end,
                SendProtocol = function(_, k, p) table.insert(outgoing, {k, p}); return true end,
                HasRosterAddon = function() return true end,
            },
            UIStyle = {
                Colors = {brandGold={1,1,1}, mutedText={0.6,0.6,0.6}, success={0,1,0}, warning={1,1,0}, info={0,0,1}, neutral={0.5,0.5,0.5}, danger={1,0,0}},
                Window=function() end, Button=function() end, Dropdown=function() end, Input=function() end, Font=function() end,
            },
        }
        """
    )
    for fname in ("Locale.lua", "GroupFinder.lua", "Workshop.lua", "WorkshopRecipes.lua", "WorkshopOrders.lua"):
        lua.execute((ROOT / fname).read_text(encoding="utf-8"))
    lua.execute(
        """
        OldKraken.InitializeLocale(OldKraken.DB)
        OldKraken:Fire('INITIALIZED', OldKraken.DB)
        for _, fr in ipairs(frames) do
            if fr.events.PLAYER_LOGIN and fr.scripts.OnEvent then fr.scripts.OnEvent(fr, 'PLAYER_LOGIN') end
        end
        for _, t in ipairs(tickers) do t() end
        """
    )
    return lua


def test_order_item_localization():
    bob = make_client("Bob")
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

        local scope = OldKraken.DB.workshop.guilds['Realm\\001Guild']
        local codec = OldKraken.GroupFinder
        local payload = codec._pack({'Alice Mon', 'ord-1', 1, now, now + 86400, 171, 'Зелье лечения', 1, 0, 'customer', 'Коментар користувача', 'open', '', 0, 0, 118, 2001, 0, 0, 0})
        handlers.WORDER('Alice Mon', 'GUILD', payload)
        local o = scope.orderObserved['Alice Mon\\001ord-1']
        assert(o and o.item == 'Зелье лечения' and o.itemID == 118 and o.recipeID == 2001)
        assert(o.note == 'Коментар користувача')

        -- 1. Before item data loads: Russian raw text must NOT be shown; placeholder is shown instead.
        assert(requests >= 1)
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
        f.orderRows[1].scripts.OnEnter(f.orderRows[1])
        assert(not tooltipTitle:find('Зелье', 1, true))

        -- 2. After ITEM_DATA_LOAD_RESULT: all UI surfaces update to English 'Minor Healing Potion'.
        loaded = true
        for _, frame in ipairs(frames) do
            if frame.events and frame.events.ITEM_DATA_LOAD_RESULT then
                frame.scripts.OnEvent(frame, 'ITEM_DATA_LOAD_RESULT', 118, true)
            end
        end
        for _, t in ipairs(tickers) do t() end
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

        -- 6. Status change notice and StaticPopup_Show use localized display name.
        local p = codec._pack({'Alice Mon', 'ord-1', 2, now, now + 86400, 171, 'Зелье лечения', 1, 0, 'customer', 'Коментар користувача', 'assigned', 'Bob Mon', 0, 0, 118, 2001, 0, 2, 0})
        handlers.WORDER('Alice Mon', 'GUILD', p)
        assert(notices[#notices][3]:find('Minor Healing Potion', 1, true))
        assert(not notices[#notices][3]:find('Зелье', 1, true))
        scope.orderOwners['Bob Mon'] = scope.orderOwners['Bob Mon'] or {}
        scope.orderOwners['Bob Mon']['Bob Mon\\001ord-pop'] = {owner='Bob Mon', id='ord-pop', rev=1, created=now+1, deadline=now+86400, profession=171, item='Зелье лечения', itemID=118, recipeID=2001, quantity=1, reward=0, rewardSilver=0, materials='customer', note='', status='open', candidates={}, acks={}}
        OldKraken.WorkshopOrders:Show('Bob Mon\\001ord-pop')
        f.orderRows[1].cancel.scripts.OnClick(f.orderRows[1].cancel)
        assert(popup and popup.arg1 == 'Minor Healing Potion')
        """
    )


def test_standalone_recipe_picker_and_validation():
    alice = make_client("Alice")
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
        assert(f.orderForm.item.kind == 'Button')
        assert(f.orderForm.item:GetText() == 'Обрати рецепт')
        selectOption(OldKrakenOrderProfession, 171)
        click('Опублікувати')
        assert(next(scope.orderOwners['Alice Mon']) == nil, 'Order must not be created without a chosen recipe')

        -- Open recipe catalog from standalone form and pick Bob's recipe.
        f.orderForm.item.scripts.OnClick(f.orderForm.item)
        assert(OldKraken.WorkshopRecipes:IsPicking())
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

        local _, o = next(scope.orderOwners['Alice Mon'])
        assert(o, 'Order should be created after picking a recipe')
        assert(o.itemID == 2454 and o.recipeID == 3001 and o.profession == 171)
        assert(o.note == 'Please craft ASAP')
        """
    )


test_order_item_localization()
test_standalone_recipe_picker_and_validation()
print("Workshop order localization and standalone picker tests passed")
