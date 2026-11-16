local ADDON_NAME = ...

OldKraken = OldKraken or {}
OldKraken.name = ADDON_NAME
OldKraken.version = "0.4.0-alpha.3"
OldKraken._listeners = OldKraken._listeners or {}

-- Shared dark theme for the addon's native controls.
OldKraken.UIStyle = {}
OldKraken.UIStyle.Colors = {
    window = {0.025, 0.035, 0.055, 0.98},
    header = {0.075, 0.085, 0.11, 1},
    panel = {0.055, 0.07, 0.095, 0.96},
    panelEdge = {0.33, 0.26, 0.14, 0.68},
    button = {0.08, 0.095, 0.125, 1},
    buttonEdge = {0.20, 0.23, 0.29, 0.85},
    primaryButton = {0.30, 0.37, 0.83, 1},
    primaryButtonEdge = {0.48, 0.54, 0.98, 1},
    brandGold = {0.88, 0.69, 0.32, 1},
    actionBlue = {0.31, 0.43, 0.95, 0.24},
    text = {0.93, 0.94, 0.96},
    mutedText = {0.63, 0.67, 0.73},
    dropdownTint = {0.68, 0.59, 0.42},
    -- Redesign palette: selection, zebra rows and status colours.
    sel = {0.20, 0.28, 0.62, 0.55},
    selEdge = {0.55, 0.66, 1, 1},
    zebra = {1, 1, 1, 0.035},
    divider = {0.20, 0.23, 0.29, 0.85},
    white = {1, 1, 1, 1},
    success = {0.41, 0.86, 0.55, 1},
    warning = {1, 0.76, 0.42, 1},
    danger = {1, 0.48, 0.43, 1},
    info = {0.40, 0.70, 1, 1},
    neutral = {0.63, 0.67, 0.73, 1},
    roleTank = {0.40, 0.70, 1, 1},
    roleHealer = {0.41, 0.86, 0.55, 1},
    roleDps = {1, 0.48, 0.43, 1},
    roleFlex = {1, 0.82, 0.42, 1},
    roleEmpty = {0.16, 0.18, 0.22, 1},
}

function OldKraken.UIStyle.EmblemPath()
    return 'Interface\\AddOns\\' .. OldKraken.name .. '\\Media\\OldKrakenKraken.tga'
end

local function addOutline(frame, color)
    local top = frame:CreateTexture(nil, 'BORDER')
    top:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
    top:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, 0)
    top:SetHeight(1)
    top:SetColorTexture(unpack(color))

    local bottom = frame:CreateTexture(nil, 'BORDER')
    bottom:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 0, 0)
    bottom:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', 0, 0)
    bottom:SetHeight(1)
    bottom:SetColorTexture(unpack(color))

    local left = frame:CreateTexture(nil, 'BORDER')
    left:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
    left:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 0, 0)
    left:SetWidth(1)
    left:SetColorTexture(unpack(color))

    local right = frame:CreateTexture(nil, 'BORDER')
    right:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, 0)
    right:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', 0, 0)
    right:SetWidth(1)
    right:SetColorTexture(unpack(color))
end

local function addPanelOutline(frame, x, y, width, height, color)
    local function edge(point, offsetX, offsetY, edgeWidth, edgeHeight)
        local texture = frame:CreateTexture(nil, 'BORDER')
        texture:SetPoint(point, frame, 'TOPLEFT', offsetX, offsetY)
        texture:SetSize(edgeWidth, edgeHeight)
        texture:SetColorTexture(unpack(color))
    end
    edge('TOPLEFT', x, y, width, 1)
    edge('BOTTOMLEFT', x, y - height + 1, width, 1)
    edge('TOPLEFT', x, y, 1, height)
    edge('TOPRIGHT', x + width - 1, y, 1, height)
end

function OldKraken.UIStyle.Window(frame)
    frame:SetFrameStrata('FULLSCREEN')
    frame:SetToplevel(true)
    for _, key in ipairs({'NineSlice', 'Bg', 'Inset', 'TitleBg', 'TopTileStreaks'}) do
        local part = frame[key]
        if type(part) == 'table' and type(part.Hide) == 'function' then part:Hide() end
    end
    if type(frame.GetRegions) == 'function' then
        for _, region in ipairs({frame:GetRegions()}) do
            if region ~= frame.TitleText and type(region) == 'table' and type(region.Hide) == 'function' then
                region:Hide()
            end
        end
    end
    local colors = OldKraken.UIStyle.Colors
    local background = frame:CreateTexture(nil, 'BACKGROUND', nil, 0)
    background:SetAllPoints(frame)
    background:SetColorTexture(unpack(colors.window))
    local header = frame:CreateTexture(nil, 'BACKGROUND', nil, 1)
    header:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
    header:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, 0)
    header:SetHeight(30)
    header:SetColorTexture(unpack(colors.header))
    local accent = frame:CreateTexture(nil, 'ARTWORK')
    accent:SetColorTexture(unpack(colors.brandGold))
    accent:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, -30)
    accent:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, -30)
    accent:SetHeight(1)
    addOutline(frame, colors.panelEdge)
    if frame.TitleText then frame.TitleText:SetTextColor(unpack(colors.text)) end
end

function OldKraken.UIStyle.Button(button, variant)
    if button.NineSlice then button.NineSlice:Hide() end
    for _, part in ipairs({'Left', 'Middle', 'Right'}) do
        if button[part] then button[part]:Hide() end
    end
    local normal, pushed = button:GetNormalTexture(), button:GetPushedTexture()
    if normal then normal:SetAlpha(0) end
    if pushed then pushed:SetAlpha(0) end
    local colors = OldKraken.UIStyle.Colors
    local primary = variant == 'primary'
    local fill = button:CreateTexture(nil, 'BACKGROUND')
    fill:SetAllPoints(button)
    fill:SetColorTexture(unpack(primary and colors.primaryButton or colors.button))
    addOutline(button, primary and colors.primaryButtonEdge or colors.buttonEdge)
    local label = button:GetFontString()
    if label then label:SetTextColor(colors.text[1], colors.text[2], colors.text[3]) end
    local highlight = button:CreateTexture(nil, 'HIGHLIGHT')
    highlight:SetAllPoints(button)
    highlight:SetColorTexture(unpack(colors.actionBlue))
    button:SetHighlightTexture(highlight)
end

function OldKraken.UIStyle.Input(editBox)
    for _, part in ipairs({'Left', 'Middle', 'Right'}) do
        local region = editBox[part]
        if type(region) == 'table' and type(region.Hide) == 'function' then region:Hide() end
    end
    local colors = OldKraken.UIStyle.Colors
    local background = editBox:CreateTexture(nil, 'BACKGROUND', nil, -8)
    background:SetAllPoints(editBox)
    background:SetColorTexture(unpack(colors.button))
    addOutline(editBox, colors.buttonEdge)
    editBox:SetTextColor(colors.text[1], colors.text[2], colors.text[3])
end

function OldKraken.UIStyle.Dropdown(frame)
    local colors = OldKraken.UIStyle.Colors
    local name = frame:GetName()
    if not name then return end
    for _, part in ipairs({'Left', 'Middle', 'Right'}) do
        local texture = _G[name .. part]
        if texture and texture.SetVertexColor then
            texture:SetVertexColor(unpack(colors.dropdownTint))
            if texture.SetAlpha then texture:SetAlpha(0) end
        end
    end
    if not frame.oldKrakenBox then
        local box = CreateFrame('Frame', nil, frame)
        box:SetPoint('TOPLEFT', frame, 'TOPLEFT', 16, -2)
        box:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -16, 4)
        local fill = box:CreateTexture(nil, 'BACKGROUND')
        fill:SetAllPoints(box)
        fill:SetColorTexture(unpack(colors.button))
        addOutline(box, colors.buttonEdge)
        frame.oldKrakenBox = box
    end
    local label = _G[name .. 'Text']
    if label and label.SetTextColor then
        label:SetTextColor(colors.text[1], colors.text[2], colors.text[3])
        if label.ClearAllPoints and frame.oldKrakenBox then
            label:ClearAllPoints()
            label:SetPoint('LEFT', frame.oldKrakenBox, 'LEFT', 10, 0)
            label:SetPoint('RIGHT', frame.oldKrakenBox, 'RIGHT', -22, 0)
        end
    end
    local toggle = _G[name .. 'Button']
    if toggle then
        local arrow = type(toggle.GetNormalTexture) == 'function' and toggle:GetNormalTexture()
        if arrow and arrow.SetVertexColor then arrow:SetVertexColor(colors.brandGold[1], colors.brandGold[2], colors.brandGold[3]) end
        if toggle.ClearAllPoints and frame.oldKrakenBox then
            toggle:ClearAllPoints()
            toggle:SetPoint('RIGHT', frame.oldKrakenBox, 'RIGHT', -4, 0)
            toggle:SetSize(20, 20)
        end
    end
    if toggle and toggle.HookScript then
        toggle:HookScript('OnClick', function()
            local list = _G.DropDownList1
            if not list or not list:IsShown() then return end
            if not list.oldKrakenRestoreHook then
                list:HookScript('OnHide', function(self)
                    if self.oldKrakenStrata then
                        self:SetFrameStrata(self.oldKrakenStrata)
                        self.oldKrakenStrata = nil
                    end
                end)
                list.oldKrakenRestoreHook = true
            end
            if not list.oldKrakenStrata then list.oldKrakenStrata = list:GetFrameStrata() end
            list:SetFrameStrata('FULLSCREEN_DIALOG')
        end)
    end
end

function OldKraken.UIStyle.Panel(frame, x, y, width, height)
    local colors = OldKraken.UIStyle.Colors
    local panel = frame:CreateTexture(nil, 'BACKGROUND', nil, 1)
    panel:SetPoint('TOPLEFT', frame, 'TOPLEFT', x, y)
    panel:SetSize(width, height)
    panel:SetColorTexture(unpack(colors.panel))
    addPanelOutline(frame, x, y, width, height, colors.panelEdge)
end

-- ---------------------------------------------------------------------------
-- Redesign components (shared by Groups, Events and Roster pages).
-- All colours come from UIStyle.Colors; edges are plain 1 px rectangles.
-- ---------------------------------------------------------------------------
local UIStyle = OldKraken.UIStyle

local function solid(frame, layer, color, alpha)
    local texture = frame:CreateTexture(nil, layer or 'BACKGROUND')
    texture:SetColorTexture(color[1], color[2], color[3], alpha or color[4] or 1)
    return texture
end

-- Four 1 px edges whose colour can be changed later through SetBorderColor.
local function createBorder(frame, color)
    local edges = {}
    for i, side in ipairs({'TOP', 'BOTTOM', 'LEFT', 'RIGHT'}) do
        local edge = solid(frame, 'BORDER', color)
        if side == 'TOP' or side == 'BOTTOM' then
            edge:SetPoint(side .. 'LEFT', frame, side .. 'LEFT', 0, 0)
            edge:SetPoint(side .. 'RIGHT', frame, side .. 'RIGHT', 0, 0)
            edge:SetHeight(1)
        else
            edge:SetPoint('TOP' .. side, frame, 'TOP' .. side, 0, 0)
            edge:SetPoint('BOTTOM' .. side, frame, 'BOTTOM' .. side, 0, 0)
            edge:SetWidth(1)
        end
        edges[i] = edge
    end
    return edges
end

local function setBorderColor(edges, color, alpha)
    for _, edge in ipairs(edges) do
        edge:SetColorTexture(color[1], color[2], color[3], alpha or color[4] or 1)
    end
end

function OldKraken.UIStyle.Font(fontString, size, bold)
    local path = type(fontString.GetFont) == 'function' and fontString:GetFont() or nil
    if type(path) ~= 'string' or path == '' then path = STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF' end
    fontString:SetFont(path, size, bold and 'OUTLINE' or '')
    return fontString
end

function OldKraken.UIStyle.Label(parent, text, size, colorKey)
    local colors = OldKraken.UIStyle.Colors
    local label = parent:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    OldKraken.UIStyle.Font(label, size or 12)
    local color = colors[colorKey or 'mutedText']
    label:SetTextColor(color[1], color[2], color[3])
    label:SetJustifyH('LEFT')
    if text then label:SetText(text) end
    return label
end

function OldKraken.UIStyle.Divider(parent)
    local colors = OldKraken.UIStyle.Colors
    local line = solid(parent, 'ARTWORK', colors.divider)
    line:SetHeight(1)
    return line
end

-- Bordered panel frame (returned) with the standard panel fill.
function OldKraken.UIStyle.PanelFrame(parent, edgeKey)
    local colors = OldKraken.UIStyle.Colors
    local frame = CreateFrame('Frame', nil, parent)
    frame.fill = solid(frame, 'BACKGROUND', colors.panel)
    frame.fill:SetAllPoints(frame)
    frame.borderEdges = createBorder(frame, colors[edgeKey or 'panelEdge'])
    return frame
end

-- Compact interactive chip: optional status dot, label, active state.
-- options: width, height, dot (colour key), active
function OldKraken.UIStyle.Chip(parent, text, options)
    local colors = OldKraken.UIStyle.Colors
    options = options or {}
    local chip = CreateFrame('Button', nil, parent)
    chip:SetSize(options.width or 120, options.height or 28)
    chip.fill = solid(chip, 'BACKGROUND', colors.button)
    chip.fill:SetAllPoints(chip)
    chip.borderEdges = createBorder(chip, colors.buttonEdge)
    local hover = chip:CreateTexture(nil, 'HIGHLIGHT')
    hover:SetAllPoints(chip)
    hover:SetColorTexture(unpack(colors.actionBlue))
    chip:SetHighlightTexture(hover)
    local left = options.center and 6 or 10
    local right = options.center and -6 or -10
    if options.dot then
        chip.dot = solid(chip, 'OVERLAY', colors[options.dot])
        chip.dot:SetSize(8, 8)
        chip.dot:SetPoint('LEFT', chip, 'LEFT', 10, 0)
        left = 24
    end
    chip.label = chip:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    OldKraken.UIStyle.Font(chip.label, 12)
    chip.label:SetPoint('LEFT', chip, 'LEFT', left, 0)
    chip.label:SetPoint('RIGHT', chip, 'RIGHT', right, 0)
    chip.label:SetJustifyH(options.center and 'CENTER' or 'LEFT')
    chip.label:SetWordWrap(false)
    function chip:SetLabel(value) self.label:SetText(value or '') end
    function chip:SetDotColor(key)
        if self.dot then self.dot:SetColorTexture(unpack(colors[key] or colors.neutral)) end
    end
    function chip:SetActive(active)
        self.active = active and true or false
        local fill = self.active and colors.primaryButton or colors.button
        local edge = self.active and colors.primaryButtonEdge or colors.buttonEdge
        self.fill:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 1)
        setBorderColor(self.borderEdges, edge)
        local text = self.active and colors.white or colors.text
        self.label:SetTextColor(text[1], text[2], text[3])
    end
    chip:SetLabel(text)
    chip:SetActive(options.active)
    return chip
end

-- Status pill: translucent fill and 1 px edge in the status colour.
-- kind: success | warning | danger | info | neutral
function OldKraken.UIStyle.PillBadge(parent, text, kind, options)
    local colors = OldKraken.UIStyle.Colors
    options = options or {}
    local pill = CreateFrame('Frame', nil, parent)
    pill:SetHeight(options.height or 19)
    pill.fill = solid(pill, 'BACKGROUND', colors.neutral, 0.16)
    pill.fill:SetAllPoints(pill)
    pill.borderEdges = createBorder(pill, colors.neutral)
    pill.label = pill:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    OldKraken.UIStyle.Font(pill.label, 12)
    pill.label:SetPoint('CENTER', pill, 'CENTER', 0, 0)
    pill.label:SetWordWrap(false)
    function pill:SetKind(value)
        local color = colors[value] or colors.neutral
        self.kind = value or 'neutral'
        self.fill:SetColorTexture(color[1], color[2], color[3], 0.16)
        setBorderColor(self.borderEdges, color, 1)
        self.label:SetTextColor(color[1], color[2], color[3])
    end
    function pill:SetLabel(value)
        self.label:SetText(value or '')
        local width = options.width
        if not width then
            local measured = type(self.label.GetStringWidth) == 'function' and tonumber(self.label:GetStringWidth()) or nil
            width = (measured or 48) + 18
        end
        self:SetWidth(width)
    end
    pill:SetKind(kind)
    pill:SetLabel(text)
    return pill
end

-- Segmented tab block shared by every page.
-- items = {{key=, label=}, ...}; onSelect(key) is called on click.
-- Returns the container; container.tabs[key] are the buttons.
function OldKraken.UIStyle.SegmentedTabs(parent, items, onSelect, options)
    local colors = OldKraken.UIStyle.Colors
    options = options or {}
    local height, pad, gap = options.height or 40, 5, 4
    local box = CreateFrame('Frame', nil, parent)
    box.fill = solid(box, 'BACKGROUND', colors.panel)
    box.fill:SetAllPoints(box)
    box.borderEdges = createBorder(box, colors.panelEdge)
    box.tabs, box.order = {}, {}
    local x = pad
    for _, item in ipairs(items) do
        local width = item.width or options.tabWidth or 120
        local tab = CreateFrame('Button', nil, box)
        tab:SetSize(width, height - pad * 2)
        tab:SetPoint('TOPLEFT', box, 'TOPLEFT', x, -pad)
        tab.key = item.key
        tab.fill = solid(tab, 'BACKGROUND', colors.panel)
        tab.fill:SetAllPoints(tab)
        local hover = tab:CreateTexture(nil, 'HIGHLIGHT')
        hover:SetAllPoints(tab)
        hover:SetColorTexture(unpack(colors.actionBlue))
        tab:SetHighlightTexture(hover)
        tab.label = tab:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
        OldKraken.UIStyle.Font(tab.label, 13)
        tab.label:SetPoint('LEFT', tab, 'LEFT', 14, 0)
        tab.label:SetText(item.label)
        tab.badge = CreateFrame('Frame', nil, tab)
        tab.badge:SetSize(19, 15)
        tab.badge:SetPoint('RIGHT', tab, 'RIGHT', -8, 0)
        tab.badge.fill = solid(tab.badge, 'BACKGROUND', colors.brandGold)
        tab.badge.fill:SetAllPoints(tab.badge)
        tab.badge.text = tab.badge:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        OldKraken.UIStyle.Font(tab.badge.text, 12, true)
        tab.badge.text:SetPoint('CENTER', tab.badge, 'CENTER', 0, 0)
        tab.badge.text:SetTextColor(colors.window[1], colors.window[2], colors.window[3])
        tab.badge:Hide()
        tab:SetScript('OnClick', function() if onSelect then onSelect(item.key) end end)
        box.tabs[item.key] = tab
        box.order[#box.order + 1] = item.key
        x = x + width + gap
    end
    box:SetSize(options.width or (x - gap + pad), height)
    function box:SetActive(key)
        self.activeKey = key
        for tabKey, tab in pairs(self.tabs) do
            local active = tabKey == key
            local fill = active and colors.primaryButton or colors.panel
            tab.fill:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 1)
            local text = active and colors.white or colors.mutedText
            tab.label:SetTextColor(text[1], text[2], text[3])
            tab.selected = active
        end
    end
    function box:SetBadge(key, count)
        local tab = self.tabs[key]
        if not tab then return end
        local value = tonumber(count) or 0
        tab.badge.count = value
        tab.badge.text:SetText(tostring(value))
        tab.badge:SetShown(value > 0)
    end
    box:SetActive(options.active or (items[1] and items[1].key))
    return box
end

-- Numbered step header: gold-edged square with a digit and a 15 px title.
function OldKraken.UIStyle.StepIndicator(parent, number, title)
    local colors = OldKraken.UIStyle.Colors
    local step = CreateFrame('Frame', nil, parent)
    step:SetHeight(26)
    step.badge = CreateFrame('Frame', nil, step)
    step.badge:SetSize(24, 24)
    step.badge:SetPoint('LEFT', step, 'LEFT', 0, 0)
    step.badge.fill = solid(step.badge, 'BACKGROUND', colors.brandGold, 0.14)
    step.badge.fill:SetAllPoints(step.badge)
    step.badge.borderEdges = createBorder(step.badge, colors.brandGold)
    step.number = step.badge:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    OldKraken.UIStyle.Font(step.number, 12, true)
    step.number:SetPoint('CENTER', step.badge, 'CENTER', 0, 0)
    step.number:SetTextColor(colors.brandGold[1], colors.brandGold[2], colors.brandGold[3])
    step.number:SetText(tostring(number))
    step.title = step:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
    OldKraken.UIStyle.Font(step.title, 15, true)
    step.title:SetPoint('LEFT', step.badge, 'RIGHT', 10, 0)
    step.title:SetTextColor(colors.text[1], colors.text[2], colors.text[3])
    step.title:SetText(title or '')
    function step:SetTitle(value) self.title:SetText(value or '') end
    return step
end

-- Selected / normal state for cards and rows (blue fill + light blue edge).
function OldKraken.UIStyle.ApplySelection(card, selected)
    local colors = OldKraken.UIStyle.Colors
    if not card.selFill then
        card.selFill = solid(card, 'BACKGROUND', colors.sel)
        card.selFill:SetAllPoints(card)
        card.selEdges = createBorder(card, colors.buttonEdge)
    end
    local fill = selected and colors.sel or colors.panel
    local edge = selected and colors.selEdge or colors.buttonEdge
    card.selFill:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 1)
    setBorderColor(card.selEdges, edge)
    card.isSelected = selected and true or false
end

function OldKraken:InvitePlayer(name)
    if type(name) ~= 'string' or name == '' then return false end
    if not C_PartyInfo or type(C_PartyInfo.InviteUnit) ~= 'function' then
        print('|cffff5555Old Kraken|r: API запрошення недоступний. Запросіть ' .. name .. ' вручну.')
        return false
    end
    local ok, result = pcall(C_PartyInfo.InviteUnit, name)
    if ok and result ~= false then
        print('|cff2ec4b6Old Kraken|r: Спроба запросити ' .. name .. ' у паті. Перевірте повідомлення гри.')
        return true
    end
    print('|cffff5555Old Kraken|r: Не вдалося запросити ' .. name .. '. Запросіть гравця вручну.')
    return false
end

function OldKraken:On(eventName, callback)
    if type(eventName) ~= "string" or type(callback) ~= "function" then
        return
    end

    self._listeners[eventName] = self._listeners[eventName] or {}
    table.insert(self._listeners[eventName], callback)
end

function OldKraken:Fire(eventName, ...)
    local listeners = self._listeners[eventName]
    if not listeners then
        return
    end

    for _, callback in ipairs(listeners) do
        callback(...)
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")

frame:SetScript("OnEvent", function(self, event, loadedAddon)
    if loadedAddon ~= ADDON_NAME then
        return
    end

    if not OldKraken.Database or not OldKraken.Database.Initialize then
        print("|cffff5555Old Kraken|r: помилка ініціалізації бази даних.")
        self:UnregisterEvent("ADDON_LOADED")
        return
    end

    OldKraken.Database.Initialize()
    OldKraken:Fire("INITIALIZED", OldKraken.DB)

    print("|cff2ec4b6Old Kraken|r: аддон завантажено.")
    self:UnregisterEvent("ADDON_LOADED")
end)
