from pathlib import Path

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
OldKraken = { listeners = {}, name = 'OldKraken' }
UIParent = {}
UISpecialFrames = {}
SlashCmdList = {}

local methods = {}
function methods:SetAllPoints(...) self.allPoints = {...} end
function methods:ClearAllPoints() self.points = {} end
function methods:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = {...} end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetHeight(value) self.height = value end
function methods:SetWidth(value) self.width = value end
function methods:SetColorTexture(...) self.color = {...} end
function methods:SetAlpha(value) self.alpha = value end
function methods:GetAlpha() return self.alpha == nil and 1 or self.alpha end
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
    return setmetatable({scripts = {}}, {__index = methods})
end
function methods:SetFont(...) self.font = {...} end
function methods:SetJustifyH(value) self.justifyH = value end
function methods:SetWordWrap(value) self.wordWrap = value end
function methods:SetText(value) self.text = value end
function methods:GetText() return self.text end
function methods:GetStringWidth() return 40 end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetShown(value) self.shown = value == true end
function methods:IsShown() return self.shown == true end

local meta = {__index = function(_, key) return methods[key] end}
function CreateFrame(frameType, name, parent)
    local frame = setmetatable({scripts = {}, name = name, parent = parent, shown = true}, meta)
    if frameType == 'Button' then
        frame.fontString = frame:CreateFontString()
    end
    if name then _G[name] = frame end
    return frame
end
function hooksecurefunc() end
function UIDropDownMenu_AddButton() end
function OldKraken:On() end
''')
lua.execute((ROOT / 'Core.lua').read_text(encoding='utf-8'))

lua.execute(r'''
local style = OldKraken.UIStyle
local colors = style.Colors
local parent = CreateFrame('Frame', nil, UIParent)

local function sameColor(a, b)
    return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and (a[4] or 1) == (b[4] or 1)
end

-- 1. Creation & initial OFF state
local toggle = style.Toggle(parent, 'Пошук груп', 18, -354, 256)
assert(toggle.isOldKrakenToggle == true)
assert(toggle.checked == false)
assert(toggle.width == 256 and toggle.height == 34)
assert(toggle.label.text == 'Пошук груп')
assert(toggle.fontString.alpha == 0 and toggle.fontString.shown == false)
assert(toggle:GetText() == 'Пошук груп: вимк.')
assert(toggle.knob.texture == 'Interface\\AddOns\\OldKraken\\Media\\PillFill.tga')
assert(toggle.knob.points[1][1] == 'LEFT')
assert(sameColor(toggle.knob.vertexColor, colors.mutedText))
for _, t in ipairs(toggle.trackFill) do assert(sameColor(t.vertexColor, colors.scrollTrack)) end
for _, t in ipairs(toggle.trackRing) do assert(sameColor(t.vertexColor, colors.buttonEdge)) end

-- 2. Programmatic SetChecked(true) and idempotent SetChecked(true) must not fire OnClick
local clicks = 0
toggle:SetScript('OnClick', function() clicks = clicks + 1 end)

toggle:SetChecked(true)
assert(clicks == 0)
assert(toggle.checked == true)
assert(toggle:GetText() == 'Пошук груп: увімк.')
assert(#toggle.knob.points == 1 and toggle.knob.points[1][1] == 'RIGHT')
assert(sameColor(toggle.knob.vertexColor, colors.text))
for _, t in ipairs(toggle.trackFill) do assert(sameColor(t.vertexColor, colors.primaryButton)) end
for _, t in ipairs(toggle.trackRing) do assert(sameColor(t.vertexColor, colors.selEdge)) end

toggle:SetChecked(true)
assert(clicks == 0 and toggle.checked == true and toggle:GetText() == 'Пошук груп: увімк.')

-- 3. SetChecked(false) restores OFF visual and text state
toggle:SetChecked(false)
assert(clicks == 0 and toggle.checked == false)
assert(toggle:GetText() == 'Пошук груп: вимк.')
assert(#toggle.knob.points == 1 and toggle.knob.points[1][1] == 'LEFT')
assert(sameColor(toggle.knob.vertexColor, colors.mutedText))
for _, t in ipairs(toggle.trackFill) do assert(sameColor(t.vertexColor, colors.scrollTrack)) end
for _, t in ipairs(toggle.trackRing) do assert(sameColor(t.vertexColor, colors.buttonEdge)) end

-- 4. SetText / GetText preservation and OnClick callback invocation
toggle:SetText('Custom: текст')
assert(toggle:GetText() == 'Custom: текст')
assert(toggle.width == 256 and toggle.height == 34)
toggle.scripts.OnClick(toggle)
assert(clicks == 1)

-- 5. Translation support via OldKraken.Translate
OldKraken.Translate = function(s)
    if s == 'увімк.' then return 'On' end
    if s == 'вимк.' then return 'Off' end
    return s
end
toggle:SetChecked(true)
assert(toggle:GetText() == 'Пошук груп: On')
toggle:SetChecked(false)
assert(toggle:GetText() == 'Пошук груп: Off')

print('UIStyle.Toggle checks passed')
''')
