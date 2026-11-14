from pathlib import Path

from lupa.lua51 import LuaRuntime


root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
OldKraken = {listeners = {}}
UIParent = {}
UISpecialFrames = {}
SlashCmdList = {}

local methods = {}
function methods:SetAllPoints(...) self.allPoints = {...} end
function methods:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = {...} end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetHeight(value) self.height = value end
function methods:SetWidth(value) self.width = value end
function methods:SetColorTexture(...) self.color = {...} end
function methods:SetAlpha(value) self.alpha = value end
function methods:SetFrameStrata(value) self.strata = value end
function methods:SetToplevel(value) self.toplevel = value end
function methods:SetTextColor(...) self.textColor = {...} end
function methods:SetVertexColor(...) self.vertexColor = {...} end
function methods:GetNormalTexture() return self.normalTexture end
function methods:GetPushedTexture() return nil end
function methods:GetFontString() return self.fontString end
function methods:GetName() return self.name end
function methods:SetHighlightTexture(texture) self.highlightTexture = texture end
function methods:RegisterEvent() end
function methods:SetScript(name, callback) self.scripts[name] = callback end
function methods:CreateTexture()
    local texture = setmetatable({scripts = {}}, {__index = methods})
    self.textures = self.textures or {}
    self.textures[#self.textures + 1] = texture
    return texture
end
local meta = {__index=function(_, key) return methods[key] end}
function CreateFrame(_, name)
    local frame = setmetatable({scripts = {}, name = name}, meta)
    if name then _G[name] = frame end
    return frame
end
function OldKraken:On() end
''')
lua.execute((root / "Core.lua").read_text(encoding="utf-8"))
assert (root / "Media" / "OldKrakenKraken.tga").is_file()
lua.execute("OldKraken.name = 'OldKraken'; assert(OldKraken.UIStyle.EmblemPath():find('OldKrakenKraken.tga', 1, true))")
lua.execute('''
local style, colors = OldKraken.UIStyle, OldKraken.UIStyle.Colors
assert(colors.brandGold[1] > colors.brandGold[2])
assert(colors.actionBlue[3] > colors.actionBlue[1])

local window = CreateFrame()
style.Window(window)
assert(window.strata == 'FULLSCREEN' and window.toplevel)
assert(window.textures[1].color[1] == colors.window[1])
assert(window.textures[2].color[1] == colors.header[1])
assert(window.textures[3].color[1] == colors.brandGold[1])
assert(#window.textures == 7)

local button = CreateFrame()
button.fontString = CreateFrame()
style.Button(button)
assert(button.textures[1].color[1] == colors.button[1])
assert(button.highlightTexture.color[3] == colors.actionBlue[3])
assert(button.fontString.textColor[1] == colors.text[1])
assert(#button.textures == 6)

local primaryButton = CreateFrame()
primaryButton.fontString = CreateFrame()
style.Button(primaryButton, 'primary')
assert(primaryButton.textures[1].color[1] == colors.primaryButton[1])

local input = CreateFrame()
style.Input(input)
assert(input.textColor[1] == colors.text[1])
assert(input.textures[1].color[1] == colors.button[1])
assert(#input.textures == 5)

local dropdown = CreateFrame('Frame', 'OldKrakenStyleDropdown')
local dropdownLabel = CreateFrame()
local dropdownLeft = CreateFrame()
local dropdownToggle = CreateFrame()
local dropdownArrow = CreateFrame()
dropdownToggle.normalTexture = dropdownArrow
_G.OldKrakenStyleDropdownText = dropdownLabel
_G.OldKrakenStyleDropdownLeft = dropdownLeft
_G.OldKrakenStyleDropdownButton = dropdownToggle
style.Dropdown(dropdown)
assert(dropdownLabel.textColor[1] == colors.text[1])
assert(dropdownLeft.vertexColor[1] == colors.dropdownTint[1])
assert(dropdownArrow.vertexColor[1] == colors.brandGold[1])

local panel = CreateFrame()
style.Panel(panel, 12, -42, 180, 600)
assert(panel.textures[1].color[1] == colors.panel[1])
assert(#panel.textures == 5)
''')
