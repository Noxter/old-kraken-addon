from pathlib import Path

from lupa.lua51 import LuaRuntime


root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
OldKraken = {
    DB = {events = {}, settings = {}},
    _listeners = {},
    UIStyle = {Window=function() end, Button=function() end, Dropdown=function() end, Input=function() end},
    Communication = {},
    GroupFinder = {_pack=function() return '' end, _unpackFields=function() return nil end},
}
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
assert(firstFrame.alertButton.text == 'Сповіщення: увімк.', 'alert setting was not rendered')
assert(firstFrame.pageLabel.text == '1 / 1', 'page label was not rendered')
assert(firstFrame.empty:IsShown(), 'empty state was not rendered')
assert(firstFrame.details.text == 'Оберіть подію зі списку.', 'empty selection details were not rendered')
assert(not firstFrame.previousPage:IsShown() and not firstFrame.nextPage:IsShown(), 'single-page arrows should be hidden')
assert(firstFrame.pageLabel.point[4] == 191 and firstFrame.pageLabel.width == 64, 'single-page indicator is not centered')

for i=1,9 do
    assert(OldKraken.GuildEvents:Create('Подія '..i,'',GetServerTime()+3600,'guild',10))
end
assert(firstFrame.pageLabel.text == '1 / 2', 'multi-page count was not rendered')
assert(firstFrame.previousPage:IsShown() and firstFrame.nextPage:IsShown(), 'multi-page arrows should be visible')
assert(firstFrame.previousPage.point[4] == 138 and firstFrame.nextPage.point[4] == 263, 'multi-page controls are not centered')
firstFrame.nextPage.scripts.OnClick()
assert(firstFrame.pageLabel.text == '2 / 2', 'next page button did not advance')
''')
