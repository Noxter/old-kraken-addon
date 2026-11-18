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
function methods:GetAlpha()
    if self.alpha == nil then
        return 1
    end
    return self.alpha
end
function methods:SetFrameStrata(value) self.strata = value end
function methods:GetFrameStrata() return self.strata or 'MEDIUM' end
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
function methods:HookScript(name, callback)
    self.hookCounts = self.hookCounts or {}
    self.hookCounts[name] = (self.hookCounts[name] or 0) + 1
    local prev = self.scripts[name]
    self.scripts[name] = function(...)
        if prev then prev(...) end
        callback(...)
    end
end
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
hookSecureCounts = {}
function hooksecurefunc(tblOrName, nameOrFn, fn)
    if type(tblOrName) == 'string' then
        hookSecureCounts[tblOrName] = (hookSecureCounts[tblOrName] or 0) + 1
        local orig = _G[tblOrName]
        _G[tblOrName] = function(...) local r = orig(...); nameOrFn(...); return r end
    elseif type(tblOrName) == 'table' then
        local orig = tblOrName[nameOrFn]
        tblOrName[nameOrFn] = function(...) local r = orig and orig(...); fn(...); return r end
    end
end
function UIDropDownMenu_AddButton() end
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

-- Explicit GetAlpha mock assertions (unset -> 1, 0.85, 0.6, 0).
local alphaProbe = CreateFrame()
assert(alphaProbe:GetAlpha() == 1)
alphaProbe:SetAlpha(0.85); assert(alphaProbe:GetAlpha() == 0.85)
alphaProbe:SetAlpha(0.6); assert(alphaProbe:GetAlpha() == 0.6)
alphaProbe:SetAlpha(0); assert(alphaProbe:GetAlpha() == 0)

-- DropDownList2 lifecycle & third-party isolation tests (Scenarios A-F).
local list1 = CreateFrame('Frame', 'DropDownList1')
list1:SetFrameStrata('DIALOG')
_G.DropDownList1Backdrop = CreateFrame(); _G.DropDownList1Backdrop:SetAlpha(1)
_G.DropDownList1MenuBackdrop = CreateFrame(); _G.DropDownList1MenuBackdrop:SetAlpha(1)

local list2 = CreateFrame('Frame', 'DropDownList2')
list2:SetFrameStrata('MEDIUM')
list2.numButtons = 1
local bd2 = CreateFrame(); bd2:SetAlpha(0.85)
local mbd2 = CreateFrame(); mbd2:SetAlpha(0.6)
_G.DropDownList2Backdrop = bd2
_G.DropDownList2MenuBackdrop = mbd2
local list2BtnText = CreateFrame()
_G.DropDownList2Button1NormalText = list2BtnText

local okDd = CreateFrame('Frame', 'OldKrakenTestSubmenuDropdown')
local okToggle = CreateFrame()
_G.OldKrakenTestSubmenuDropdownText = CreateFrame()
_G.OldKrakenTestSubmenuDropdownLeft = CreateFrame()
_G.OldKrakenTestSubmenuDropdownButton = okToggle
style.Dropdown(okDd, {rounded = true})
style.Dropdown(okDd, {rounded = true})
assert(okDd.oldKrakenStyled == true)
assert(style.dropdownAddButtonHooked == true)
assert(hookSecureCounts.UIDropDownMenu_AddButton == 1, 'UIDropDownMenu_AddButton hook must be registered exactly once across multiple Dropdown() calls')
assert(list2.hookCounts and list2.hookCounts.OnShow == 1 and list2.hookCounts.OnHide == 1)

local foreignDd = CreateFrame('Frame', 'ThirdPartyAddonDropdown')

-- Scenario C (before any Old Kraken open): third-party dropdown opens DropDownList2 -> untouched.
UIDROPDOWNMENU_OPEN_MENU = foreignDd
list2:Show()
list2.scripts.OnShow(list2)
assert(list2:GetFrameStrata() == 'MEDIUM', 'foreign dropdown must not elevate DropDownList2 strata')
assert(bd2:GetAlpha() == 0.85 and mbd2:GetAlpha() == 0.6, 'foreign dropdown must keep original backdrop alphas')
assert(not list2.oldKrakenSkinTextures, 'foreign dropdown must not create Old Kraken textures')
UIDropDownMenu_AddButton({}, 2)
assert(list2BtnText.font == nil, 'UIDropDownMenu_AddButton hook must not alter foreign dropdown fonts')
list2:Hide()
list2.scripts.OnHide(list2)

-- Scenario A: Old Kraken opens DropDownList2 -> styled with opaque panel, buttonEdge, FULLSCREEN_DIALOG.
UIDROPDOWNMENU_OPEN_MENU = okDd
list2:Show()
list2.scripts.OnShow(list2)
assert(list2:GetFrameStrata() == 'FULLSCREEN_DIALOG')
assert(bd2:GetAlpha() == 0 and mbd2:GetAlpha() == 0)
assert(list2.oldKrakenSkinTextures and #list2.oldKrakenSkinTextures == 5)
local fill = list2.oldKrakenSkinTextures[1]
assert(fill.color[1] == colors.panel[1] and fill.color[2] == colors.panel[2] and fill.color[3] == colors.panel[3] and fill.color[4] == 0.98)
assert(list2.oldKrakenSkinTextures[2].color[1] == colors.buttonEdge[1])
assert(fill:IsShown())
UIDropDownMenu_AddButton({}, 2)
assert(list2BtnText.font and list2BtnText.font[2] == 13, 'Old Kraken dropdown must style level 2 button font')

-- Scenario B: OnHide restores original FrameStrata, exact original alphas (0.85 / 0.6), and hides skin textures.
list2:Hide()
list2.scripts.OnHide(list2)
assert(list2:GetFrameStrata() == 'MEDIUM')
assert(bd2:GetAlpha() == 0.85 and mbd2:GetAlpha() == 0.6)
for _, tex in ipairs(list2.oldKrakenSkinTextures) do assert(not tex:IsShown()) end

-- Scenario D: After Old Kraken closes, third-party opens DropDownList2 -> must not inherit Old Kraken style.
UIDROPDOWNMENU_OPEN_MENU = foreignDd
list2:Show()
list2.scripts.OnShow(list2)
assert(list2:GetFrameStrata() == 'MEDIUM')
assert(bd2:GetAlpha() == 0.85 and mbd2:GetAlpha() == 0.6)
for _, tex in ipairs(list2.oldKrakenSkinTextures) do assert(not tex:IsShown()) end
list2:Hide()
list2.scripts.OnHide(list2)

-- Scenario E: Repeated Old Kraken open/close cycles do not duplicate hooks or textures.
for _ = 1, 3 do
    UIDROPDOWNMENU_OPEN_MENU = okDd
    okToggle.scripts.OnClick(okToggle)
    list2:Show()
    list2.scripts.OnShow(list2)
    assert(list2:GetFrameStrata() == 'FULLSCREEN_DIALOG')
    assert(#list2.textures == 5 and #list2.oldKrakenSkinTextures == 5)
    assert(list2.hookCounts.OnShow == 1 and list2.hookCounts.OnHide == 1)
    list2:Hide()
    list2.scripts.OnHide(list2)
    assert(list2:GetFrameStrata() == 'MEDIUM')
    assert(bd2:GetAlpha() == 0.85 and mbd2:GetAlpha() == 0.6)
    for _, tex in ipairs(list2.oldKrakenSkinTextures) do assert(not tex:IsShown()) end
end

-- Scenario F: Mid-flight owner change before OnShow -> restores non-styled state.
UIDROPDOWNMENU_OPEN_MENU = okDd
list2:Show()
list2.scripts.OnShow(list2)
assert(list2:GetFrameStrata() == 'FULLSCREEN_DIALOG')
UIDROPDOWNMENU_OPEN_MENU = foreignDd
list2.scripts.OnShow(list2)
assert(list2:GetFrameStrata() == 'MEDIUM')
assert(bd2:GetAlpha() == 0.85 and mbd2:GetAlpha() == 0.6)
for _, tex in ipairs(list2.oldKrakenSkinTextures) do assert(not tex:IsShown()) end

-- Scenario G: Exact restoration of alpha == 0 on OnHide.
bd2:SetAlpha(0)
UIDROPDOWNMENU_OPEN_MENU = okDd
list2:Show()
list2.scripts.OnShow(list2)
assert(bd2:GetAlpha() == 0 and mbd2:GetAlpha() == 0)
list2:Hide()
list2.scripts.OnHide(list2)
assert(bd2:GetAlpha() == 0 and mbd2:GetAlpha() == 0.6, 'alpha == 0 must be restored exactly as 0')
bd2:SetAlpha(0.85)

-- Scenario H: Stale UIDROPDOWNMENU_INIT_MENU vs UIDROPDOWNMENU_OPEN_MENU + string-named menu support.
UIDROPDOWNMENU_OPEN_MENU = nil
UIDROPDOWNMENU_INIT_MENU = okDd
list2:Show()
list2.scripts.OnShow(list2)
assert(list2:GetFrameStrata() == 'MEDIUM', 'DropDownList2:OnShow must ignore stale INIT_MENU when OPEN_MENU is nil')
assert(bd2:GetAlpha() == 0.85 and mbd2:GetAlpha() == 0.6)
for _, tex in ipairs(list2.oldKrakenSkinTextures) do assert(not tex:IsShown()) end

list2BtnText.font = nil
UIDROPDOWNMENU_OPEN_MENU = nil
UIDROPDOWNMENU_INIT_MENU = okDd
UIDropDownMenu_AddButton({}, 2)
assert(list2BtnText.font and list2BtnText.font[2] == 13, 'UIDropDownMenu_AddButton must style font via INIT_MENU when OPEN_MENU is nil')

list2BtnText.font = nil
UIDROPDOWNMENU_OPEN_MENU = foreignDd
UIDROPDOWNMENU_INIT_MENU = okDd
list2.scripts.OnShow(list2)
assert(list2:GetFrameStrata() == 'MEDIUM')
UIDropDownMenu_AddButton({}, 2)
assert(list2BtnText.font == nil, 'UIDropDownMenu_AddButton must prioritize foreign OPEN_MENU over stale INIT_MENU')

UIDROPDOWNMENU_OPEN_MENU = 'OldKrakenTestSubmenuDropdown'
UIDROPDOWNMENU_INIT_MENU = nil
list2.scripts.OnShow(list2)
assert(list2:GetFrameStrata() == 'FULLSCREEN_DIALOG', 'string-named Old Kraken OPEN_MENU must be recognized')
list2:Hide()
list2.scripts.OnHide(list2)
assert(list2:GetFrameStrata() == 'MEDIUM')
''')
