from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
OldKraken = {listeners = {}}; UIParent = {}; StaticPopupDialogs = {}; UISpecialFrames = {}
OldKraken.UIStyle = {
    Window = function() end,
    Button = function() end,
    Dropdown = function() end,
    Panel = function() end,
}
function StaticPopup_Show() end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_JustifyText() end
function UIDropDownMenu_Initialize() end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton() end
function UIDropDownMenu_SetText() end
function OldKraken:On(name, fn) self.listeners[name] = fn end
function print(...) end
function GetServerTime() return 12345 end
function GetTime() return 1 end
local methods = {}
function methods:SetText(v) self.text = v end
function methods:GetText() return self.text or '' end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown end
function methods:GetStringHeight() return 0 end
function methods:SetScript(name, fn) self.scripts[name] = fn end
function methods:CreateFontString() return CreateFrame() end
function methods:CreateTexture() return CreateFrame() end
local meta = {__index=function(_, k) if k == 'TitleText' then return nil end; return methods[k] or function() end end}
function CreateFrame() return setmetatable({scripts={}}, meta) end
''')
for name in ['GroupFinder.lua', 'GroupFinderUI.lua']:
    lua.execute((root / name).read_text(encoding='utf-8'))
lua.execute('''
local f = OldKraken.GroupFinder
f:Initialize('Tester', function() return true end)
function f:GroupAlertsEnabled() return true end
function f:SetGroupAlertsEnabled() return true end
f.active = true
assert(f:Create('Test', 'quest', 'Description', 5, 1, 60, 'dps'))
f:Show()
assert(OldKraken.listeners.GROUP_FINDER_CHANGED)
OldKraken.listeners.GROUP_FINDER_CHANGED()
''')
print('UI smoke checks passed')
