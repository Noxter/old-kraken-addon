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
function methods:SetTexture(value) self.texture = value end
function methods:SetTexCoord(...) self.texCoord = {...} end
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
function methods:CreateFontString()
    local text = setmetatable({scripts = {}}, {__index = methods})
    return text
end
function methods:SetFont(...) self.font = {...} end
function methods:SetJustifyH(value) self.justifyH = value end
function methods:SetWordWrap(value) self.wordWrap = value end
function methods:SetText(value) self.text = value end
function methods:GetStringWidth() return 40 end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetShown(value) self.shown = value == true end
function methods:IsShown() return self.shown == true end
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

local chip = style.Chip(CreateFrame(), 'Сповіщення: увімк.', {dot = 'success', width = 156, height = 31})
assert(chip.label.text == 'Сповіщення: увімк.' and chip.dot)
chip:SetActive(true)
assert(chip.active and chip.fill.color[1] == colors.primaryButton[1])
local selChip = style.Chip(CreateFrame(), 'Рейд', {selStyle = true, active = true})
assert(selChip.fill.color[1] == colors.sel[1] and selChip.borderEdges[1].color[1] == colors.selEdge[1])
selChip:SetActive(false)
assert(selChip.fill.color[1] == colors.button[1] and selChip.borderEdges[1].color[1] == colors.buttonEdge[1])

local pill = style.PillBadge(CreateFrame(), 'Відкрито', 'success', {
    width = 68, height = 19, fontSize = 11, bold = true, customColors = {success = {0.349, 0.902, 0.502, 1}},
})
assert(pill.label.text == 'Відкрито' and pill.kind == 'success')
assert(pill.width == 68 and pill.label.font[2] == 11 and pill.label.textColor[1] == 0.349)

local round = style.PillBadge(CreateFrame(), 'Закрито', 'neutral', {width = 68, height = 19, rounded = true})
assert(#round.fillParts == 3 and #round.ringParts == 3 and round.fill == round.fillParts[2])
round:Hide(); round:Show()

local roundChip = style.Chip(CreateFrame(), 'Учасників 557', {width = 111, height = 30, rounded = true})
assert(#roundChip.fillParts == 3 and #roundChip.ringParts == 3 and roundChip.fill == roundChip.fillParts[2])
roundChip:Hide(); roundChip:Show()

local roundBtn = CreateFrame()
roundBtn.fontString = CreateFrame()
style.Button(roundBtn, nil, {rounded = true})
assert(#roundBtn.fillParts == 3 and #roundBtn.ringParts == 3 and roundBtn.fill == roundBtn.fillParts[2])

local roundInp = CreateFrame()
style.Input(roundInp, {rounded = true})
assert(#roundInp.oldKrakenFillParts == 3 and #roundInp.oldKrakenRingParts == 3)

local roundDd = CreateFrame('Frame', 'OldKrakenStyleRoundDropdown')
_G.OldKrakenStyleRoundDropdownText = CreateFrame()
_G.OldKrakenStyleRoundDropdownLeft = CreateFrame()
_G.OldKrakenStyleRoundDropdownButton = CreateFrame()
style.Dropdown(roundDd, {rounded = true})
assert(#roundDd.oldKrakenFillParts == 3 and #roundDd.oldKrakenRingParts == 3)

local selectedTab
local tabs = style.SegmentedTabs(CreateFrame(), {
    {key = 'all', label = 'Усі групи', width = 87},
    {key = 'applications', label = 'Мої заявки', width = 125},
}, function(key) selectedTab = key end, {active = 'all', edgeKey = 'buttonEdge'})
assert(tabs.activeKey == 'all' and tabs.tabs.all.selected and not tabs.tabs.applications.selected)
assert(tabs.borderEdges[1].color[1] == colors.buttonEdge[1])
assert(tabs.tabs.all.borderEdges[1]:IsShown() and not tabs.tabs.applications.borderEdges[1]:IsShown())
assert(tabs.tabs.all.label.font[3] == 'OUTLINE' and tabs.tabs.applications.label.font[3] == '')
tabs:SetBadge('applications', 2)
assert(tabs.tabs.applications.badge:IsShown() and tabs.tabs.applications.badge.text.text == '2')
tabs.tabs.applications.scripts.OnClick()
assert(selectedTab == 'applications')

local step = style.StepIndicator(CreateFrame(), 1, 'Тип події')
assert(step.number.text == '1' and step.title.text == 'Тип події')

assert(colors.sel[1] == 0.102 and colors.selEdge[1] == 0.478)
local card = CreateFrame()
style.ApplySelection(card, true)
assert(card.isSelected and card.selFill.color[1] == 0.102 and card.selEdges[1].color[1] == 0.478)
style.ApplySelection(card, false)
assert(not card.isSelected and card.selFill.color[1] == colors.panel[1])
''')
