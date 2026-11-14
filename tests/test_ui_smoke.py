from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
OldKraken = {}; UIParent = {}; StaticPopupDialogs = {}
function StaticPopup_Show() end
function OldKraken:On(name, fn) self.listener = fn end
function print(...) end
function GetServerTime() return 12345 end
function GetTime() return 1 end
local methods = {}
function methods:SetText(v) self.text = v end
function methods:GetText() return self.text or '' end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown end
function methods:SetScript(name, fn) self.scripts[name] = fn end
function methods:CreateFontString() return CreateFrame() end
local meta = {__index=function(_, k) if k == 'TitleText' then return nil end; return methods[k] or function() end end}
function CreateFrame() return setmetatable({scripts={}}, meta) end
''')
for name in ['GroupFinder.lua', 'GroupFinderUI.lua']:
    lua.execute((root / name).read_text(encoding='utf-8'))
lua.execute('''
local f = OldKraken.GroupFinder
f:Initialize('Tester', function() return true end)
f.active = true
assert(f:Create('Test', 'quest', 'Description', 5))
f:Show()
assert(OldKraken.listener)
OldKraken.listener()
''')
print('UI smoke checks passed')
