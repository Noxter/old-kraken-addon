from pathlib import Path

from lupa.lua51 import LuaRuntime


root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
OldKraken = {
    name = 'OldKraken',
    DB = {events = {}, settings = {}},
    _listeners = {},
    UIStyle = {
        Colors = {
            brandGold = {0.88, 0.69, 0.32, 1},
            mutedText = {0.63, 0.67, 0.73},
            success = {0.41, 0.86, 0.55, 1},
            neutral = {0.63, 0.67, 0.73, 1},
            sel = {0.20, 0.28, 0.62, 0.55},
            selEdge = {0.55, 0.66, 1, 1},
        },
        Window=function() end, Button=function() end, Dropdown=function() end, Input=function() end, Panel=function() end, Font=function() end,
        PanelFrame=function(parent) return CreateFrame('Frame', nil, parent) end,
        StepIndicator=function(parent, number, title)
            local s = CreateFrame('Frame', nil, parent)
            s.number = s:CreateFontString(); s.number:SetText(tostring(number))
            s.title = s:CreateFontString(); s.title:SetText(title or '')
            function s:SetTitle(v) self.title:SetText(v or '') end
            return s
        end,
        Chip=function(parent, text, options)
            local c = CreateFrame('Button', nil, parent)
            c.label = c:CreateFontString(); c.label:SetText(text or '')
            c.active = options and options.active and true or false
            function c:SetLabel(v) self.label:SetText(v or '') end
            function c:SetActive(a) self.active = a and true or false end
            return c
        end,
        SegmentedTabs=function(parent, items, onSelect, options)
            local box = CreateFrame('Frame', nil, parent)
            box.tabs = {}
            for _, item in ipairs(items) do
                local tab = CreateFrame('Button', nil, box)
                tab.label = tab:CreateFontString(); tab.label:SetText(item.label)
                tab:SetScript('OnClick', function() if onSelect then onSelect(item.key) end end)
                box.tabs[item.key] = tab
            end
            function box:SetActive(key)
                self.activeKey = key
                for k, t in pairs(self.tabs) do t.selected = (k == key) end
            end
            box:SetActive(options and options.active or (items[1] and items[1].key))
            return box
        end,
        ApplySelection=function(card, selected) card.isSelected = selected and true or false end,
    },
    Communication = {},
    GroupFinder = {_pack=function() return '' end, _unpackFields=function() return nil end, CanPerformRole=function() return true end, GetGameRoles=function() return nil end},
}
StaticPopupDialogs={}
function StaticPopup_Show(_,_,_,callback)
    popup={callback=callback,HookScript=function() end,GetFrameStrata=function() return 'DIALOG' end,SetFrameStrata=function() end}
    return popup
end
function OldKraken:On(name, callback)
    self._listeners[name] = self._listeners[name] or {}
    table.insert(self._listeners[name], callback)
end
function OldKraken:Fire(name, ...)
    for _, callback in ipairs(self._listeners[name] or {}) do callback(...) end
end
function OldKraken.Communication:RegisterHandler() end
function OldKraken.Communication:SendProtocol() return true end
function UnitName() return 'Tester', 'Realm' end
function GetGuildInfo() return 'Guild' end
function GetRealmName() return 'Test Realm' end
function GetServerTime() return 2000000000 end
function GetTime() return 10 end
function date() return '01.01.2033 00:00' end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_JustifyText() end
function UIDropDownMenu_Initialize() end
function UIDropDownMenu_SetText() end
function UIDropDownMenu_CreateInfo() return {} end
function print() end

local methods = {}
function methods:RegisterEvent() end
function methods:SetScript(name, callback) self.scripts[name] = callback end
function methods:HookScript(name, callback)
    self.hooks[name] = self.hooks[name] or {}
    table.insert(self.hooks[name], callback)
end
function methods:ClearAllPoints() self.points = {}; self.point = nil end
function methods:SetPoint(...) self.points = self.points or {}; table.insert(self.points, {...}); self.point = {...} end
function methods:SetWidth(value) self.width = value end
function methods:SetJustifyH(value) self.justifyH = value end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:GetFrameLevel() return 1 end
function methods:SetMovable() end
function methods:EnableMouse() end
function methods:RegisterForDrag() end
function methods:SetClampedToScreen() end
function methods:SetText(value) self.text = value end
function methods:GetText() return self.text or '' end
function methods:SetShown(value)
    if value then self:Show() else self:Hide() end
end
function methods:Show()
    if self.shown then return end
    self.shown = true
    if self.scripts.OnShow then self.scripts.OnShow(self) end
    for _, callback in ipairs(self.hooks.OnShow or {}) do callback(self) end
end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown == true end
function methods:CreateFontString() return CreateFrame() end
function methods:GetStringHeight() return 14 end
function methods:CreateTexture() return CreateFrame() end
local meta = {__index=function(_, key)
    if key == 'TitleText' or key == 'CloseButton' then return nil end
    return methods[key] or function() end
end}
createdFrames = {}
function CreateFrame(_, name, parent)
    local frame = setmetatable({scripts = {}, hooks = {}, points = {}, parent = parent, shown = false}, meta)
    createdFrames[#createdFrames + 1] = frame
    if name then _G[name] = frame end
    return frame
end

OldKraken.UIHub = {pages = {}}
function OldKraken.UIHub:RegisterPage(key, _, _, create)
    self.pages[key] = create
end
function OldKraken.UIHub:ShowPage(key)
    local create = self.pages[key]
    OldKrakenEventsFrame = create(CreateFrame('Frame'))
    OldKrakenEventsFrame:Show()
end
''')
lua.execute((root / 'ActivityCatalog.lua').read_text(encoding='utf-8'))
lua.execute((root / 'GuildEvents.lua').read_text(encoding='utf-8'))
lua.execute('''
for _, frame in ipairs(createdFrames) do
    if frame.scripts.OnEvent then frame.scripts.OnEvent(frame, 'PLAYER_LOGIN') end
end
OldKraken.UIHub:ShowPage('events')
local firstFrame = OldKrakenEventsFrame
assert(firstFrame:IsShown(), 'events page is hidden')
assert(firstFrame.width == 900 and firstFrame.height == 607, 'events page does not match the Hub page grid')
assert(firstFrame.detailsContent.width == 400, 'event details column did not expand to the Hub grid')
assert(firstFrame.alertButton.text == 'Сповіщення: увімк.', 'alert setting was not rendered')
assert(firstFrame.pageLabel.text == '1 / 1', 'page label was not rendered')
assert(firstFrame.empty:IsShown(), 'empty state was not rendered')
assert(firstFrame.details.text == 'Оберіть подію зі списку.', 'empty selection details were not rendered')
assert(not firstFrame.previousPage:IsShown() and not firstFrame.nextPage:IsShown(), 'single-page arrows should be hidden')
assert(firstFrame.pageLabel.point[4] == 196 and firstFrame.pageLabel.width == 64, 'single-page indicator is not centered')

for i=1,9 do
    assert(OldKraken.GuildEvents:Create('Подія '..i,'',GetServerTime()+3600,'guild',10))
end
assert(firstFrame.pageLabel.text == '1 / 2', 'multi-page count was not rendered')
assert(firstFrame.previousPage:IsShown() and firstFrame.nextPage:IsShown(), 'multi-page arrows should be visible')
assert(firstFrame.previousPage.point[4] == 143 and firstFrame.nextPage.point[4] == 268, 'multi-page controls are not centered')
firstFrame.nextPage.scripts.OnClick()
assert(firstFrame.pageLabel.text == '2 / 2', 'next page button did not advance')
local before=#firstFrame.visible
local delete=firstFrame.eventRows[1].delete
assert(delete:IsShown(), 'owner delete button is hidden')
delete.scripts.OnClick(delete)
assert(#firstFrame.visible==before, 'delete happened without confirmation')
popup.callback()
assert(#firstFrame.visible==before-1, 'confirmed deletion did not remove event')

-- Verify the 3-step creation wizard, horizontal kind chips, location cards, stepper and summary bar.
firstFrame.createTab.scripts.OnClick()
assert(firstFrame.creationMode and firstFrame.step1:IsShown() and firstFrame.step2:IsShown() and firstFrame.step3:IsShown())
assert(firstFrame.kindChips.raid.active and not firstFrame.kindChips.pvp.active)
assert(firstFrame.activityCards:IsShown() and firstFrame.activityCards.cards[1].height == 64 and firstFrame.activityCards.cards[1].art.width == 44)
-- Selecting a location auto-fills the title unless the user typed a custom title.
firstFrame.activityCards.cards[1].scripts.OnClick(firstFrame.activityCards.cards[1])
local autoTitle = firstFrame.title:GetText()
assert(autoTitle ~= '' and firstFrame.activityCards.cards[1].isSelected and not firstFrame.noLocationButton.active)
firstFrame.noLocationButton.scripts.OnClick()
assert(firstFrame.noLocationButton.active and firstFrame.title:GetText() == 'Рейд')
firstFrame.title:SetText('Власна назва рейду')
firstFrame.activityCards.cards[1].scripts.OnClick(firstFrame.activityCards.cards[1])
assert(firstFrame.title:GetText() == 'Власна назва рейду', 'auto-fill must not overwrite manual title')
-- Event kind chips preserve internal identifiers including pvp.
firstFrame.kindChips.pvp.scripts.OnClick()
assert(firstFrame.kindChips.pvp.active and not firstFrame.activityCards:IsShown())
firstFrame.kindChips.raid.scripts.OnClick()
-- Stepper clamps between 2 and 40 and updates the live summary line.
firstFrame.size:SetText('3')
firstFrame.sizeMinus.scripts.OnClick()
assert(firstFrame.size:GetText() == '2')
firstFrame.sizeMinus.scripts.OnClick()
assert(firstFrame.size:GetText() == '2')
firstFrame.size:SetText('39')
firstFrame.sizePlus.scripts.OnClick()
assert(firstFrame.size:GetText() == '40')
firstFrame.sizePlus.scripts.OnClick()
assert(firstFrame.size:GetText() == '40')
assert(firstFrame.summaryLine:GetText():find('Власна назва рейду', 1, true) and firstFrame.summaryLine:GetText():find('40 місць', 1, true))
-- Cancel button exits creation mode back to the events list.
firstFrame.cancelCreate.scripts.OnClick()
assert(not firstFrame.creationMode and not firstFrame.summaryBar:IsShown())
-- Regression: largeRoleIcon must only resize the leading :16:16: dimensions, not healer's :64:16:16:32: texcoords.
firstFrame.previousPage.scripts.OnClick()
firstFrame.eventRows[1].scripts.OnClick(firstFrame.eventRows[1])
local selectedKey = firstFrame.visible and firstFrame.visible[1] and firstFrame.visible[1].key
assert(selectedKey and OldKraken.GuildEvents:Signup(selectedKey, 'healer'))
assert(firstFrame.signupRows[1] and firstFrame.signupRows[1].roleStatus.text:find(':26:26:0:0:64:16:16:32:0:16|t', 1, true),
    'healer role icon texcoords corrupted: ' .. tostring(firstFrame.signupRows[1] and firstFrame.signupRows[1].roleStatus.text))
''')
