local ADDON_NAME = ...

OldKraken = OldKraken or {}
OldKraken.name = ADDON_NAME
OldKraken.version = "0.5.3-alpha.1"
OldKraken._listeners = OldKraken._listeners or {}
local T = OldKraken.Translate or function(text) return text end

-- Shared dark theme for the addon's native controls.
OldKraken.UIStyle = {}
OldKraken.UIStyle.Colors = {
    window = {0.025, 0.035, 0.055, 1},
    header = {0.075, 0.085, 0.11, 1},
    panel = {0.055, 0.07, 0.095, 0.96},
    panelEdge = {0.33, 0.26, 0.14, 0.68},
    button = {0.08, 0.095, 0.125, 1},
    buttonEdge = {0.20, 0.23, 0.29, 0.85},
    primaryButton = {0.20, 0.31, 0.56, 1},
    primaryButtonEdge = {0.33, 0.47, 0.76, 1},
    dangerButton = {0.38, 0.12, 0.13, 1},
    dangerButtonEdge = {0.82, 0.32, 0.30, 1},
    brandGold = {0.88, 0.69, 0.32, 1},
    actionBlue = {0.24, 0.38, 0.75, 0.24},
    scrollTrack = {0.035, 0.045, 0.068, 0.9},
    scrollThumb = {0.34, 0.41, 0.56, 0.95},
    text = {0.93, 0.94, 0.96},
    mutedText = {0.63, 0.67, 0.73},
    dropdownTint = {0.68, 0.59, 0.42},
    -- Redesign palette: selection, zebra rows and status colours.
    sel = {0.102, 0.141, 0.302, 1},
    selEdge = {0.478, 0.541, 0.980, 1},
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
    top.isOldKrakenEdge = true
    top:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
    top:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, 0)
    top:SetHeight(1)
    top:SetColorTexture(unpack(color))

    local bottom = frame:CreateTexture(nil, 'BORDER')
    bottom.isOldKrakenEdge = true
    bottom:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 0, 0)
    bottom:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', 0, 0)
    bottom:SetHeight(1)
    bottom:SetColorTexture(unpack(color))

    local left = frame:CreateTexture(nil, 'BORDER')
    left.isOldKrakenEdge = true
    left:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
    left:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 0, 0)
    left:SetWidth(1)
    left:SetColorTexture(unpack(color))

    local right = frame:CreateTexture(nil, 'BORDER')
    right.isOldKrakenEdge = true
    right:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, 0)
    right:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', 0, 0)
    right:SetWidth(1)
    right:SetColorTexture(unpack(color))

    return {top, bottom, left, right}
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

local function slicePill(parent, layer, sublayer, capWidth, insets)
    local base = 'Interface\\AddOns\\' .. (OldKraken and OldKraken.name or 'OldKraken') .. '\\Media\\'
    capWidth = capWidth or 6
    insets = insets or {}
    local topOffset = insets.top or 0
    local bottomOffset = insets.bottom or 0
    local leftOffset = insets.left or 0
    local rightOffset = insets.right or 0
    local function slice(file, l, sl)
        local parts = {}
        for i, range in ipairs({{0, 0.25}, {0.25, 0.75}, {0.75, 1}}) do
            local t = parent:CreateTexture(nil, l, nil, sl)
            t:SetTexture(base .. file)
            t:SetTexCoord(range[1], range[2], 0, 1)
            t:SetPoint('TOP', parent, 'TOP', 0, topOffset)
            t:SetPoint('BOTTOM', parent, 'BOTTOM', 0, bottomOffset)
            if i == 1 then
                t:SetPoint('LEFT', parent, 'LEFT', leftOffset, 0)
                t:SetWidth(capWidth)
            elseif i == 3 then
                t:SetPoint('RIGHT', parent, 'RIGHT', rightOffset, 0)
                t:SetWidth(capWidth)
            else
                t:SetPoint('LEFT', parts[1], 'RIGHT', 0, 0)
                t:SetPoint('RIGHT', parent, 'RIGHT', rightOffset - capWidth, 0)
            end
            parts[i] = t
        end
        return parts
    end
    return slice('PillFill.tga', layer or 'BACKGROUND', sublayer), slice('PillRing.tga', 'BORDER', sublayer and (sublayer + 1) or nil)
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
    if frame.TitleText then
        frame.TitleText:SetTextColor(unpack(colors.text))
        if type(frame.TitleText.ClearAllPoints) == 'function' then
            frame.TitleText:ClearAllPoints()
            frame.TitleText:SetPoint('CENTER', header, 'CENTER', 0, 0)
        end
        OldKraken.UIStyle.Font(frame.TitleText, 14, true)
    end

    local close = frame.CloseButton or (type(frame.GetName) == 'function' and frame:GetName() and _G[frame:GetName() .. 'CloseButton'])
    if close and type(close) == 'table' and type(close.SetSize) == 'function' then
        close:SetSize(22, 22)
        close:ClearAllPoints()
        close:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -6, -4)
        for _, method in ipairs({'GetNormalTexture', 'GetPushedTexture', 'GetDisabledTexture', 'GetHighlightTexture'}) do
            local tex = type(close[method]) == 'function' and close[method](close)
            if tex and type(tex) == 'table' then
                if type(tex.SetTexture) == 'function' then tex:SetTexture(nil) end
                if type(tex.Hide) == 'function' then tex:Hide() end
                if type(tex.SetAlpha) == 'function' then tex:SetAlpha(0) end
            end
        end
        if not close.oldKrakenStyled then
            local fill = close:CreateTexture(nil, 'BACKGROUND')
            fill:SetAllPoints(close)
            fill:SetColorTexture(unpack(colors.button))
            close.fill = fill
            addOutline(close, colors.buttonEdge)

            local crossParts = {}
            local function setCrossColor(r, g, b, a)
                for _, part in ipairs(crossParts) do
                    part:SetColorTexture(r, g, b, a or 1)
                end
            end
            for d = -4, 4 do
                local p1 = close:CreateTexture(nil, 'OVERLAY')
                p1:SetSize(2, 2)
                p1:SetPoint('CENTER', close, 'CENTER', d, d)
                crossParts[#crossParts + 1] = p1
                if d ~= 0 then
                    local p2 = close:CreateTexture(nil, 'OVERLAY')
                    p2:SetSize(2, 2)
                    p2:SetPoint('CENTER', close, 'CENTER', d, -d)
                    crossParts[#crossParts + 1] = p2
                end
            end
            close.crossParts = crossParts
            setCrossColor(colors.mutedText[1], colors.mutedText[2], colors.mutedText[3], 1)

            close:SetScript('OnEnter', function()
                fill:SetColorTexture(colors.danger[1], colors.danger[2], colors.danger[3], 0.45)
                setCrossColor(1, 1, 1, 1)
            end)
            close:SetScript('OnLeave', function()
                fill:SetColorTexture(unpack(colors.button))
                setCrossColor(colors.mutedText[1], colors.mutedText[2], colors.mutedText[3], 1)
            end)
            close.oldKrakenStyled = true
        end
    end
end

function OldKraken.UIStyle.Button(button, variant, options)
    options = options or {}
    if button.NineSlice then button.NineSlice:Hide() end
    for _, part in ipairs({'Left', 'Middle', 'Right'}) do
        if button[part] then button[part]:Hide() end
    end
    button.fitTextWidthPadding = nil
    button.fitTextCanWidthDecrease = false
    if not button.oldKrakenFixedWidthHook then
        button.oldKrakenFixedWidthHook = true
        local origSetSize = button.SetSize
        local origSetWidth = button.SetWidth
        local origSetText = button.SetText
        if type(origSetSize) == 'function' then
            function button:SetSize(w, h)
                self.oldKrakenWidth = w
                self.oldKrakenHeight = h
                return origSetSize(self, w, h)
            end
        end
        if type(origSetWidth) == 'function' then
            function button:SetWidth(w)
                self.oldKrakenWidth = w
                return origSetWidth(self, w)
            end
        end
        if type(origSetText) == 'function' then
            function button:SetText(text)
                local result = origSetText(self, text)
                if self.oldKrakenWidth and type(origSetWidth) == 'function' then
                    origSetWidth(self, self.oldKrakenWidth)
                end
                if self.oldKrakenHeight and type(self.SetHeight) == 'function' then
                    self:SetHeight(self.oldKrakenHeight)
                end
                return result
            end
        end
    end
    local normal, pushed = button:GetNormalTexture(), button:GetPushedTexture()
    if normal then normal:SetAlpha(0) end
    if pushed then pushed:SetAlpha(0) end
    local colors = OldKraken.UIStyle.Colors
    local primary = variant == 'primary'
    local danger = variant == 'danger'
    local fillColor = primary and colors.primaryButton or (danger and colors.dangerButton or colors.button)
    local edgeColor = primary and colors.primaryButtonEdge or (danger and colors.dangerButtonEdge or colors.buttonEdge)
    if options.rounded then
        local fillParts, ringParts = slicePill(button, 'BACKGROUND', nil, options.capWidth or 6)
        button.fillParts, button.ringParts = fillParts, ringParts
        button.fill = fillParts[2]
        button.borderEdges = ringParts
        for _, t in ipairs(fillParts) do
            t:SetVertexColor(unpack(fillColor))
            t.color = fillColor
        end
        for _, t in ipairs(ringParts) do
            t:SetVertexColor(unpack(edgeColor))
            t.color = edgeColor
        end
    else
        local fill = button:CreateTexture(nil, 'BACKGROUND')
        fill:SetAllPoints(button)
        fill:SetColorTexture(unpack(fillColor))
        button.fill = fill
        button.borderEdges = addOutline(button, edgeColor)
    end
    local label = button:GetFontString()
    if label then
        label:SetTextColor(colors.text[1], colors.text[2], colors.text[3])
        OldKraken.UIStyle.Font(label, 13)
    end
    local highlight = button:CreateTexture(nil, 'HIGHLIGHT')
    highlight:SetAllPoints(button)
    if options.rounded then
            local base = 'Interface\\AddOns\\' .. (OldKraken and OldKraken.name or 'OldKraken') .. '\\Media\\'
        highlight:SetTexture(base .. 'PillFill.tga')
        highlight:SetVertexColor(colors.actionBlue[1], colors.actionBlue[2], colors.actionBlue[3], 0.15)
        highlight.color = colors.actionBlue
    else
        highlight:SetColorTexture(unpack(colors.actionBlue))
    end
    button:SetHighlightTexture(highlight)
end

function OldKraken.UIStyle.Input(editBox, options)
    options = options or {}
    local name = editBox:GetName()
    if name then
        for _, part in ipairs({'Left', 'Middle', 'Right'}) do
            local texture = _G[name .. part]
            if texture and texture.Hide then texture:Hide() end
        end
    end
    for _, part in ipairs({'Left', 'Middle', 'Right'}) do
        local region = editBox[part]
        if type(region) == 'table' and type(region.Hide) == 'function' then region:Hide() end
    end
    if editBox.GetRegions then
        for _, region in ipairs({editBox:GetRegions()}) do
            if region:IsObjectType('Texture') and not region.isOldKraken and not region.isOldKrakenEdge then
                region:Hide()
            end
        end
    end
    local colors = OldKraken.UIStyle.Colors
    if options.rounded then
        local fillParts, ringParts = slicePill(editBox, 'BACKGROUND', -8, options.capWidth or 6)
        editBox.oldKrakenFillParts = fillParts
        editBox.oldKrakenRingParts = ringParts
        for _, t in ipairs(fillParts) do
            t.isOldKraken = true
            t:SetVertexColor(unpack(colors.button))
            t.color = colors.button
        end
        for _, t in ipairs(ringParts) do
            t.isOldKrakenEdge = true
            t:SetVertexColor(unpack(colors.buttonEdge))
            t.color = colors.buttonEdge
        end
    else
        local background = editBox:CreateTexture(nil, 'BACKGROUND', nil, -8)
        background.isOldKraken = true
        background:SetAllPoints(editBox)
        background:SetColorTexture(unpack(colors.button))
        addOutline(editBox, colors.buttonEdge)
    end
    editBox:SetTextColor(colors.text[1], colors.text[2], colors.text[3])
    if type(editBox.SetFont) == 'function' then
        OldKraken.UIStyle.Font(editBox, 13)
    end
    if type(editBox.SetTextInsets) == 'function' then
        editBox:SetTextInsets(10, 10, 0, 0)
    end
end

local dropdownHooksInstalled = false

local function layoutDropdownText(dropdownFrame)
    if not dropdownFrame or not dropdownFrame.oldKrakenFill then return end
    local name = type(dropdownFrame.GetName) == 'function' and dropdownFrame:GetName()
    local label = name and _G[name .. 'Text']
    if not label then return end
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(label, 13) end
    if label.SetShadowColor then label:SetShadowColor(0, 0, 0, 0.9) end
    if label.SetShadowOffset then label:SetShadowOffset(1, -1) end
    if type(label.SetWidth) == 'function' then label:SetWidth(0) end
    if type(label.ClearAllPoints) == 'function' then
        label:ClearAllPoints()
        label:SetPoint('LEFT', dropdownFrame.oldKrakenFill, 'LEFT', 10, 0)
        label:SetPoint('RIGHT', dropdownFrame.oldKrakenFill, 'RIGHT', -22, 0)
    end
    if type(label.SetJustifyH) == 'function' then label:SetJustifyH('LEFT') end
    if type(label.SetWordWrap) == 'function' then label:SetWordWrap(false) end
end

local function isOldKrakenMenuFrame(menu)
    if type(menu) == 'string' then menu = _G[menu] end
    return type(menu) == 'table' and menu.oldKrakenStyled == true
end

local function isOldKrakenDropdownOpen()
    return isOldKrakenMenuFrame(UIDROPDOWNMENU_OPEN_MENU)
end

local function isOldKrakenButtonTarget()
    if UIDROPDOWNMENU_OPEN_MENU ~= nil then
        return isOldKrakenMenuFrame(UIDROPDOWNMENU_OPEN_MENU)
    end
    return isOldKrakenMenuFrame(UIDROPDOWNMENU_INIT_MENU)
end

local function restoreDropDownList(list)
    if not list or type(list) ~= 'table' then return end
    if list.oldKrakenStrata and type(list.SetFrameStrata) == 'function' then
        list:SetFrameStrata(list.oldKrakenStrata)
        list.oldKrakenStrata = nil
    end
    if list.oldKrakenSavedAlphas then
        local listName = type(list.GetName) == 'function' and list:GetName()
        for _, suffix in ipairs({'Backdrop', 'MenuBackdrop'}) do
            local saved = list.oldKrakenSavedAlphas[suffix]
            if saved ~= nil then
                local backdrop = list[suffix] or (listName and _G[listName .. suffix])
                if backdrop and type(backdrop) == 'table' and type(backdrop.SetAlpha) == 'function' then
                    backdrop:SetAlpha(saved)
                end
            end
        end
        list.oldKrakenSavedAlphas = nil
    end
    if list.oldKrakenSkinTextures then
        for _, tex in ipairs(list.oldKrakenSkinTextures) do
            if tex and tex.Hide then tex:Hide() end
        end
    end
end

local function attachDropDownListHooks(list)
    if not list or type(list) ~= 'table' or type(list.HookScript) ~= 'function' then return end
    if not list.oldKrakenShowHook then
        list:HookScript('OnShow', function(self)
            local pred = self.oldKrakenStylePredicate
            if pred and not pred() then
                restoreDropDownList(self)
                return
            end
            if pred then
                if not self.oldKrakenStrata and type(self.GetFrameStrata) == 'function' then
                    self.oldKrakenStrata = self:GetFrameStrata()
                end
                if type(self.SetFrameStrata) == 'function' then self:SetFrameStrata('FULLSCREEN_DIALOG') end
            end
            OldKraken.UIStyle.StyleDropDownList(self, pred)
        end)
        list.oldKrakenShowHook = true
    end
    if not list.oldKrakenRestoreHook then
        list:HookScript('OnHide', function(self)
            restoreDropDownList(self)
        end)
        list.oldKrakenRestoreHook = true
    end
end

function OldKraken.UIStyle.StyleDropDownList(list, predicate)
    if not list or type(list) ~= 'table' then return end
    if predicate ~= nil then list.oldKrakenStylePredicate = predicate end
    local activePred = list.oldKrakenStylePredicate
    if activePred and not activePred() then
        restoreDropDownList(list)
        return
    end
    local colors = OldKraken.UIStyle.Colors
    local listName = type(list.GetName) == 'function' and list:GetName()
    list.oldKrakenSavedAlphas = list.oldKrakenSavedAlphas or {}
    for _, suffix in ipairs({'Backdrop', 'MenuBackdrop'}) do
        local backdrop = list[suffix] or (listName and _G[listName .. suffix])
        if backdrop and type(backdrop) == 'table' and type(backdrop.SetAlpha) == 'function' then
            if list.oldKrakenSavedAlphas[suffix] == nil and type(backdrop.GetAlpha) == 'function' then
                list.oldKrakenSavedAlphas[suffix] = backdrop:GetAlpha()
            end
            backdrop:SetAlpha(0)
        end
    end
    if not list.oldKrakenSkinTextures then
        local fill = list:CreateTexture(nil, 'BACKGROUND', nil, -7)
        fill:SetPoint('TOPLEFT', list, 'TOPLEFT', 6, -6)
        fill:SetPoint('BOTTOMRIGHT', list, 'BOTTOMRIGHT', -6, 6)
        fill:SetColorTexture(colors.panel[1], colors.panel[2], colors.panel[3], 0.98)
        local top = list:CreateTexture(nil, 'BORDER', nil, -6)
        top:SetPoint('TOPLEFT', fill, 'TOPLEFT', 0, 0)
        top:SetPoint('TOPRIGHT', fill, 'TOPRIGHT', 0, 0)
        top:SetHeight(1)
        top:SetColorTexture(unpack(colors.buttonEdge))
        local bottom = list:CreateTexture(nil, 'BORDER', nil, -6)
        bottom:SetPoint('BOTTOMLEFT', fill, 'BOTTOMLEFT', 0, 0)
        bottom:SetPoint('BOTTOMRIGHT', fill, 'BOTTOMRIGHT', 0, 0)
        bottom:SetHeight(1)
        bottom:SetColorTexture(unpack(colors.buttonEdge))
        local left = list:CreateTexture(nil, 'BORDER', nil, -6)
        left:SetPoint('TOPLEFT', fill, 'TOPLEFT', 0, 0)
        left:SetPoint('BOTTOMLEFT', fill, 'BOTTOMLEFT', 0, 0)
        left:SetWidth(1)
        left:SetColorTexture(unpack(colors.buttonEdge))
        local right = list:CreateTexture(nil, 'BORDER', nil, -6)
        right:SetPoint('TOPRIGHT', fill, 'TOPRIGHT', 0, 0)
        right:SetPoint('BOTTOMRIGHT', fill, 'BOTTOMRIGHT', 0, 0)
        right:SetWidth(1)
        right:SetColorTexture(unpack(colors.buttonEdge))
        list.oldKrakenSkinTextures = {fill, top, bottom, left, right}
    end
    for _, tex in ipairs(list.oldKrakenSkinTextures) do
        if tex and tex.Show then tex:Show() end
    end
    if not activePred then
        local maxButtons = UIDROPDOWNMENU_MAXBUTTONS or 32
        for i = 1, maxButtons do
            local btnName = listName and (listName .. 'Button' .. i)
            local normalText = btnName and _G[btnName .. 'NormalText']
            if normalText and OldKraken.UIStyle.Font then
                OldKraken.UIStyle.Font(normalText, 13)
                if normalText.SetShadowColor then normalText:SetShadowColor(0, 0, 0, 0.9) end
                if normalText.SetShadowOffset then normalText:SetShadowOffset(1, -1) end
            end
        end
    end
    attachDropDownListHooks(list)
end

local function ensureDropdownButtonHook()
    if OldKraken.UIStyle.dropdownAddButtonHooked then return end
    if type(hooksecurefunc) ~= 'function' or type(UIDropDownMenu_AddButton) ~= 'function' then return end
    OldKraken.UIStyle.dropdownAddButtonHooked = true
    hooksecurefunc('UIDropDownMenu_AddButton', function(info, level)
        if not isOldKrakenButtonTarget() then return end
        level = level or 1
        local listFrame = _G['DropDownList' .. level]
        if listFrame then
            local count = listFrame.numButtons or 0
            local normalText = _G['DropDownList' .. level .. 'Button' .. count .. 'NormalText']
            if normalText and OldKraken.UIStyle.Font then
                OldKraken.UIStyle.Font(normalText, 13)
                if normalText.SetShadowColor then normalText:SetShadowColor(0, 0, 0, 0.9) end
                if normalText.SetShadowOffset then normalText:SetShadowOffset(1, -1) end
            end
        end
    end)
end

function OldKraken.UIStyle.Dropdown(frame, options)
    options = options or {}
    local colors = OldKraken.UIStyle.Colors
    local name = frame:GetName()
    if not name then return end
    frame.oldKrakenStyled = true
    if type(frame.SetHeight) == 'function' then frame:SetHeight(36) end
    for _, part in ipairs({'Left', 'Middle', 'Right'}) do
        local texture = _G[name .. part]
        if texture then
            if texture.SetVertexColor then texture:SetVertexColor(unpack(colors.dropdownTint)) end
            if texture.SetAlpha then texture:SetAlpha(0) end
            if texture.Hide then texture:Hide() end
        end
    end
    if not frame.oldKrakenFill then
        if options.rounded then
            local fill = frame:CreateTexture(nil, 'BACKGROUND', nil, -8)
            fill:SetPoint('TOPLEFT', frame, 'TOPLEFT', 16, -2)
            fill:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -16, 0)
            fill:SetColorTexture(0, 0, 0, 0)
            frame.oldKrakenFill = fill

            local fillParts, ringParts = slicePill(frame, 'BACKGROUND', -7, options.capWidth or 6, {left = 16, right = -16, top = -2, bottom = 0})
            frame.oldKrakenFillParts = fillParts
            frame.oldKrakenRingParts = ringParts
            for _, t in ipairs(fillParts) do
                t:SetVertexColor(unpack(colors.button))
                t.color = colors.button
            end
            for _, t in ipairs(ringParts) do
                t.isOldKrakenEdge = true
                t:SetVertexColor(unpack(colors.buttonEdge))
                t.color = colors.buttonEdge
            end
            frame.oldKrakenEdges = ringParts
            frame.oldKrakenBox = frame
        else
            local fill = frame:CreateTexture(nil, 'BACKGROUND', nil, -7)
            fill:SetPoint('TOPLEFT', frame, 'TOPLEFT', 16, -2)
            fill:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -16, 0)
            fill:SetColorTexture(unpack(colors.button))
            frame.oldKrakenFill = fill

            local edges = {}
            for i, side in ipairs({'TOP', 'BOTTOM', 'LEFT', 'RIGHT'}) do
                local edge = frame:CreateTexture(nil, 'BORDER', nil, -6)
                edge.isOldKrakenEdge = true
                if side == 'TOP' or side == 'BOTTOM' then
                    edge:SetPoint(side .. 'LEFT', fill, side .. 'LEFT', 0, 0)
                    edge:SetPoint(side .. 'RIGHT', fill, side .. 'RIGHT', 0, 0)
                    edge:SetHeight(1)
                else
                    edge:SetPoint('TOP' .. side, fill, 'TOP' .. side, 0, 0)
                    edge:SetPoint('BOTTOM' .. side, fill, 'BOTTOM' .. side, 0, 0)
                    edge:SetWidth(1)
                end
                edge:SetColorTexture(unpack(colors.buttonEdge))
                edges[i] = edge
            end
            frame.oldKrakenEdges = edges
            frame.oldKrakenBox = frame
        end
    end
    ensureDropdownButtonHook()
    if not dropdownHooksInstalled and type(hooksecurefunc) == 'function' then
        dropdownHooksInstalled = true
        if type(UIDropDownMenu_SetWidth) == 'function' then
            hooksecurefunc('UIDropDownMenu_SetWidth', function(dropdownFrame) layoutDropdownText(dropdownFrame) end)
        end
        if type(UIDropDownMenu_JustifyText) == 'function' then
            hooksecurefunc('UIDropDownMenu_JustifyText', function(dropdownFrame) layoutDropdownText(dropdownFrame) end)
        end
        if type(UIDropDownMenu_SetText) == 'function' then
            hooksecurefunc('UIDropDownMenu_SetText', function(dropdownFrame) layoutDropdownText(dropdownFrame) end)
        end
        if type(UIDropDownMenu_Initialize) == 'function' then
            hooksecurefunc('UIDropDownMenu_Initialize', function(dropdownFrame) layoutDropdownText(dropdownFrame) end)
        end
    end
    local label = _G[name .. 'Text']
    if label then
        if label.SetDrawLayer then label:SetDrawLayer('OVERLAY', 7) end
        if label.SetTextColor then
            label:SetTextColor(colors.text[1], colors.text[2], colors.text[3])
        end
        if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(label, 13) end
        if label.SetShadowColor then label:SetShadowColor(0, 0, 0, 0.9) end
        if label.SetShadowOffset then label:SetShadowOffset(1, -1) end
        if not label.oldKrakenFontHook and type(hooksecurefunc) == 'function' then
            label.oldKrakenFontHook = true
            hooksecurefunc(label, 'SetFontObject', function(self)
                if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(self, 13) end
                if self.SetShadowColor then self:SetShadowColor(0, 0, 0, 0.9) end
                if self.SetShadowOffset then self:SetShadowOffset(1, -1) end
            end)
        end
        layoutDropdownText(frame)
        if label.Show then label:Show() end
    end
    local toggle = _G[name .. 'Button']
    if toggle then
        local arrow = type(toggle.GetNormalTexture) == 'function' and toggle:GetNormalTexture()
        if arrow and arrow.SetVertexColor then arrow:SetVertexColor(colors.brandGold[1], colors.brandGold[2], colors.brandGold[3]) end
        for _, method in ipairs({'GetNormalTexture', 'GetPushedTexture', 'GetDisabledTexture', 'GetHighlightTexture'}) do
            local tex = type(toggle[method]) == 'function' and toggle[method](toggle)
            if tex and type(tex) == 'table' and type(tex.SetAlpha) == 'function' then
                tex:SetAlpha(0)
            end
        end
        if toggle.ClearAllPoints and frame.oldKrakenFill then
            toggle:ClearAllPoints()
            toggle:SetPoint('TOPLEFT', frame.oldKrakenFill, 'TOPLEFT', 0, 0)
            toggle:SetPoint('BOTTOMRIGHT', frame.oldKrakenFill, 'BOTTOMRIGHT', 0, 0)
        end
        if not toggle.oldKrakenHighlight and type(toggle.CreateTexture) == 'function' and type(toggle.SetHighlightTexture) == 'function' then
            local hl = toggle:CreateTexture(nil, 'HIGHLIGHT')
            hl:SetAllPoints(toggle)
            hl:SetColorTexture(unpack(colors.actionBlue))
            toggle:SetHighlightTexture(hl)
            toggle.oldKrakenHighlight = hl
        end
    end
    if not frame.oldKrakenChevron and frame.oldKrakenFill then
        local chevron = {}
        local widths = {7, 5, 3, 1}
        local offsets = {2, 1, 0, -1}
        for idx = 1, 4 do
            local bar = frame:CreateTexture(nil, 'OVERLAY', nil, 7)
            bar:SetSize(widths[idx], 1)
            bar:SetPoint('CENTER', frame.oldKrakenFill, 'RIGHT', -13, offsets[idx])
            bar:SetColorTexture(unpack(colors.brandGold))
            chevron[idx] = bar
        end
        frame.oldKrakenChevron = chevron
    end
    local function ensureSecondaryDropDownHooks()
        local list2 = _G.DropDownList2
        if not list2 or type(list2) ~= 'table' or list2.oldKrakenShowHook then return end
        list2.oldKrakenStylePredicate = isOldKrakenDropdownOpen
        attachDropDownListHooks(list2)
    end
    ensureSecondaryDropDownHooks()
    if toggle and toggle.HookScript and not toggle.oldKrakenClickHook then
        toggle.oldKrakenClickHook = true
        toggle:HookScript('OnClick', function()
            ensureSecondaryDropDownHooks()
            local list = _G.DropDownList1
            if not list or not list:IsShown() then return end
            OldKraken.UIStyle.StyleDropDownList(list, isOldKrakenDropdownOpen)
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

function OldKraken.UIStyle.FontPath(weight)
    local base = 'Interface\\AddOns\\' .. (OldKraken and OldKraken.name or 'OldKraken') .. '\\Media\\Fonts\\'
    if weight == 'semibold' then return base .. 'NotoSans-SemiBold.ttf' end
    if weight == 'medium' then return base .. 'NotoSans-Medium.ttf' end
    return base .. 'NotoSans-Regular.ttf'
end

function OldKraken.UIStyle.Font(fontString, size, bold)
    local currentPath, currentSize
    if type(fontString.GetFont) == 'function' then
        currentPath, currentSize = fontString:GetFont()
    end
    local effectiveSize = size or currentSize or 13
    local weight = bold and (effectiveSize >= 15 and 'semibold' or 'medium') or 'regular'
    local path = OldKraken.UIStyle.FontPath(weight) or currentPath or STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF'
    if type(fontString.SetFont) == 'function' then
        fontString:SetFont(path, effectiveSize, bold and 'OUTLINE' or '')
    end
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
    if options.rounded then
        local capWidth = options.capWidth or (options.height and math.floor(options.height * 8 / 32 + 0.5)) or 6
        local fillParts, ringParts = slicePill(chip, 'BACKGROUND', nil, capWidth)
        chip.fillParts = fillParts
        chip.ringParts = ringParts
        chip.fill = fillParts[2]
        chip.borderEdges = ringParts
        local origShow = chip.Show
        local origHide = chip.Hide
        function chip:Show()
            if origShow then origShow(self) end
            for _, t in ipairs(self.fillParts or {}) do if t.Show then t:Show() end end
            for _, t in ipairs(self.ringParts or {}) do if t.Show then t:Show() end end
        end
        function chip:Hide()
            if origHide then origHide(self) end
            for _, t in ipairs(self.fillParts or {}) do if t.Hide then t:Hide() end end
            for _, t in ipairs(self.ringParts or {}) do if t.Hide then t:Hide() end end
        end
    else
        chip.fill = solid(chip, 'BACKGROUND', colors.button)
        chip.fill:SetAllPoints(chip)
        chip.borderEdges = createBorder(chip, colors.buttonEdge)
    end
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
    OldKraken.UIStyle.Font(chip.label, options.fontSize or 12, options.bold)
    if options.center then
        chip.label:SetPoint('CENTER', chip, 'CENTER', 0, 0)
    else
        chip.label:SetPoint('LEFT', chip, 'LEFT', left, 0)
        chip.label:SetPoint('RIGHT', chip, 'RIGHT', right, 0)
    end
    chip.label:SetJustifyH(options.center and 'CENTER' or 'LEFT')
    chip.label:SetWordWrap(false)
    function chip:SetLabel(value) self.label:SetText(value or '') end
    function chip:SetDotColor(key)
        if self.dot then self.dot:SetColorTexture(unpack(colors[key] or colors.neutral)) end
    end
    function chip:SetActive(active)
        self.active = active and true or false
        local fill = self.active and (options.selStyle and colors.sel or colors.primaryButton) or colors.button
        local edge = self.active and (options.selStyle and colors.selEdge or colors.primaryButtonEdge) or colors.buttonEdge
        if self.fillParts then
            for _, t in ipairs(self.fillParts) do
                t:SetVertexColor(fill[1], fill[2], fill[3], fill[4] or 1)
                t.color = fill
            end
            for _, t in ipairs(self.ringParts) do
                t:SetVertexColor(edge[1], edge[2], edge[3], edge[4] or 1)
                t.color = edge
            end
        else
            self.fill:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 1)
            setBorderColor(self.borderEdges, edge)
        end
        local text = self.active and (options.selStyle and colors.text or colors.white) or (options.selStyle and colors.mutedText or colors.text)
        self.label:SetTextColor(text[1], text[2], text[3])
        if options.selStyle then OldKraken.UIStyle.Font(self.label, options.fontSize or 13, self.active) end
    end
    chip.SetText = chip.SetLabel
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
    if options.rounded then
        local capWidth = (options.height or 19) * 8 / 32
        local fillParts, ringParts = slicePill(pill, 'BACKGROUND', nil, capWidth)
        pill.fillParts = fillParts
        pill.ringParts = ringParts
        pill.fill = fillParts[2]
        pill.borderEdges = {}
    else
        pill.fill = solid(pill, 'BACKGROUND', colors.neutral, 0.16)
        pill.fill:SetAllPoints(pill)
        pill.borderEdges = createBorder(pill, colors.neutral)
    end
    pill.label = pill:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    OldKraken.UIStyle.Font(pill.label, options.fontSize or 12, options.bold)
    pill.label:SetPoint('CENTER', pill, 'CENTER', 0, 0)
    pill.label:SetWordWrap(false)
    function pill:SetKind(value)
        local color = (options.customColors and options.customColors[value]) or colors[value] or colors.neutral
        self.kind = value or 'neutral'
        if self.fillParts then
            for _, t in ipairs(self.fillParts) do t:SetVertexColor(color[1], color[2], color[3], 0.16) end
            for _, t in ipairs(self.ringParts) do t:SetVertexColor(color[1], color[2], color[3], 1) end
        else
            self.fill:SetColorTexture(color[1], color[2], color[3], 0.16)
            setBorderColor(self.borderEdges, color, 1)
        end
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
    local origHide = pill.Hide
    function pill:Hide()
        self.fill:Hide()
        for _, t in ipairs(self.fillParts or {}) do t:Hide() end
        for _, t in ipairs(self.ringParts or {}) do t:Hide() end
        for _, edge in ipairs(self.borderEdges or {}) do edge:Hide() end
        self.label:Hide()
        if origHide then origHide(self) end
    end
    local origShow = pill.Show
    function pill:Show()
        if origShow then origShow(self) end
        self.fill:Show()
        for _, t in ipairs(self.fillParts or {}) do t:Show() end
        for _, t in ipairs(self.ringParts or {}) do t:Show() end
        for _, edge in ipairs(self.borderEdges or {}) do edge:Show() end
        self.label:Show()
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
    local edgeColor = colors[options.edgeKey or 'panelEdge']
    if options.rounded then
        local fillParts, ringParts = slicePill(box, 'BACKGROUND', nil, 6)
        box.fillParts, box.ringParts = fillParts, ringParts
        box.fill = fillParts[2]
        box.borderEdges = ringParts
        for _, t in ipairs(fillParts) do
            t:SetVertexColor(unpack(colors.panel))
            t.color = colors.panel
        end
        for _, t in ipairs(ringParts) do
            t:SetVertexColor(unpack(edgeColor))
            t.color = edgeColor
        end
    else
        box.fill = solid(box, 'BACKGROUND', colors.panel)
        box.fill:SetAllPoints(box)
        box.borderEdges = createBorder(box, edgeColor)
    end
    box.tabs, box.order = {}, {}
    local x = pad
    for _, item in ipairs(items) do
        local width = item.width or options.tabWidth or 120
        local tab = CreateFrame('Button', nil, box)
        tab:SetSize(width, height - pad * 2)
        tab:SetPoint('TOPLEFT', box, 'TOPLEFT', x, -pad)
        tab.key = item.key
        if options.rounded then
            local capWidth = options.capWidth or 5
            local fillParts, ringParts = slicePill(tab, 'BACKGROUND', nil, capWidth)
            tab.fillParts, tab.ringParts = fillParts, ringParts
            tab.fill = fillParts[2]
            tab.borderEdges = ringParts
            for _, t in ipairs(fillParts) do
                t:SetVertexColor(unpack(colors.panel))
                t.color = colors.panel
            end
            for _, t in ipairs(ringParts) do
                t:SetVertexColor(unpack(colors.selEdge))
                t.color = colors.selEdge
                t:Hide()
            end
        else
            tab.fill = solid(tab, 'BACKGROUND', colors.panel)
            tab.fill:SetAllPoints(tab)
            tab.borderEdges = createBorder(tab, colors.selEdge)
            for _, edge in ipairs(tab.borderEdges) do edge:Hide() end
        end
        local hover = tab:CreateTexture(nil, 'HIGHLIGHT')
        hover:SetAllPoints(tab)
        if options.rounded then
            local base = 'Interface\\AddOns\\' .. (OldKraken and OldKraken.name or 'OldKraken') .. '\\Media\\'
            hover:SetTexture(base .. 'PillFill.tga')
            hover:SetVertexColor(colors.actionBlue[1], colors.actionBlue[2], colors.actionBlue[3], 0.15)
            hover.color = colors.actionBlue
        else
            hover:SetColorTexture(unpack(colors.actionBlue))
        end
        tab:SetHighlightTexture(hover)
        tab.label = tab:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
        OldKraken.UIStyle.Font(tab.label, 13)
        tab.label:SetPoint('CENTER', tab, 'CENTER', 0, 0)
        if type(tab.label.SetJustifyH) == 'function' then tab.label:SetJustifyH('CENTER') end
        tab.label:SetText(item.label)
        tab.badge = CreateFrame('Frame', nil, tab)
        tab.badge:SetSize(18, 16)
        tab.badge:SetPoint('RIGHT', tab, 'RIGHT', -7, 0)
        local bFillParts, bRingParts = slicePill(tab.badge, 'BACKGROUND', nil, 4)
        tab.badge.fillParts, tab.badge.ringParts = bFillParts, bRingParts
        tab.badge.fill = bFillParts[2]
        tab.badge.borderEdges = bRingParts
        for _, t in ipairs(bFillParts) do
            t:SetVertexColor(colors.brandGold[1], colors.brandGold[2], colors.brandGold[3], 0.95)
            t.color = colors.brandGold
        end
        for _, t in ipairs(bRingParts) do
            t:SetVertexColor(0.55, 0.42, 0.18, 0.7)
            t.color = {0.55, 0.42, 0.18, 0.7}
        end
        tab.badge.text = tab.badge:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        OldKraken.UIStyle.Font(tab.badge.text, 11, false)
        tab.badge.text:SetPoint('CENTER', tab.badge, 'CENTER', 0, 0)
        tab.badge.text:SetTextColor(0.06, 0.07, 0.10, 1)
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
            local fill = active and (options.activeBg or colors.sel) or (options.inactiveBg or colors.panel)
            local edge = active and (options.activeEdge or colors.selEdge) or colors.buttonEdge
            if tab.fillParts then
                for _, t in ipairs(tab.fillParts) do
                    t:SetVertexColor(fill[1], fill[2], fill[3], fill[4] or 1)
                    t.color = fill
                end
                for _, t in ipairs(tab.ringParts) do
                    t:SetVertexColor(edge[1], edge[2], edge[3], active and (edge[4] or 0.8) or 0)
                    t.color = edge
                    t:SetShown(active)
                end
            else
                tab.fill:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 1)
                for _, edgeFrame in ipairs(tab.borderEdges or {}) do
                    edgeFrame:SetShown(active)
                    if edgeFrame.SetColorTexture then
                        edgeFrame:SetColorTexture(edge[1], edge[2], edge[3], edge[4] or 1)
                    end
                end
            end
            local text = active and colors.white or colors.mutedText
            tab.label:SetTextColor(text[1], text[2], text[3])
            OldKraken.UIStyle.Font(tab.label, 13, active)
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
        if value > 0 then
            local textW = tab.badge.text.GetStringWidth and tab.badge.text:GetStringWidth() or 8
            local badgeW = math.max(18, math.floor(textW + 8 + 0.5))
            tab.badge:SetWidth(badgeW)
            if type(tab.label.ClearAllPoints) == 'function' then
                tab.label:ClearAllPoints()
                local shift = math.floor((badgeW + 2) / 2 + 0.5)
                tab.label:SetPoint('CENTER', tab, 'CENTER', -shift, 0)
            end
        else
            if type(tab.label.ClearAllPoints) == 'function' then
                tab.label:ClearAllPoints()
                tab.label:SetPoint('CENTER', tab, 'CENTER', 0, 0)
            end
        end
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
        card.selFill = card:CreateTexture(nil, 'BACKGROUND', nil, 1)
        card.selFill:SetAllPoints(card)
        card.selEdges = createBorder(card, colors.buttonEdge)
        for _, edge in ipairs(card.selEdges) do
            if type(edge.SetDrawLayer) == 'function' then edge:SetDrawLayer('BORDER', 2) end
        end
    end
    local fill = selected and colors.sel or colors.panel
    local edge = selected and colors.selEdge or colors.buttonEdge
    card.selFill:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 1)
    setBorderColor(card.selEdges, edge)
    if card.fill and type(card.fill.SetColorTexture) == 'function' then
        card.fill:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 1)
    end
    if card.borderEdges then
        setBorderColor(card.borderEdges, edge)
    end
    card.isSelected = selected and true or false
end

local function hideScrollButtonTextures(target)
    if type(target) ~= 'table' then return end
    for _, method in ipairs({'GetNormalTexture', 'GetPushedTexture', 'GetDisabledTexture', 'GetHighlightTexture'}) do
        local tex = type(target[method]) == 'function' and target[method](target)
        if type(tex) == 'table' then
            if type(tex.SetTexture) == 'function' then tex:SetTexture(nil) end
            if type(tex.SetAlpha) == 'function' then tex:SetAlpha(0) end
            if type(tex.Hide) == 'function' then tex:Hide() end
        end
    end
end

function OldKraken.UIStyle.ScrollBar(scrollFrame, options)
    if type(scrollFrame) ~= 'table' then return end
    options = options or {}
    local name = type(scrollFrame.GetName) == 'function' and scrollFrame:GetName()
    local sb = scrollFrame.ScrollBar or (name and _G[name .. 'ScrollBar'])
    if type(sb) ~= 'table' then return end
    local colors = OldKraken.UIStyle.Colors
    local sbName = type(sb.GetName) == 'function' and sb:GetName()
    if type(sb.SetWidth) == 'function' then sb:SetWidth(8) end
    if options.inside and type(sb.ClearAllPoints) == 'function' then
        sb:ClearAllPoints()
        sb:SetPoint('TOPRIGHT', scrollFrame, 'TOPRIGHT', -4, -4)
        sb:SetPoint('BOTTOMRIGHT', scrollFrame, 'BOTTOMRIGHT', -4, 4)
    end
    if type(scrollFrame.GetFrameLevel) == 'function' and type(sb.SetFrameLevel) == 'function' then
        sb:SetFrameLevel(scrollFrame:GetFrameLevel() + 5)
    end
    if type(sb.GetRegions) == 'function' then
        for _, region in ipairs({sb:GetRegions()}) do
            if type(region) == 'table' and type(region.Hide) == 'function' and not region.oldKrakenScrollPart then
                region:Hide()
            end
        end
    end
    for _, suffix in ipairs({'ScrollUpButton', 'ScrollDownButton'}) do
        local btn = sb[suffix] or (sbName and _G[sbName .. suffix])
        if type(btn) == 'table' then
            hideScrollButtonTextures(btn)
            if type(btn.SetSize) == 'function' then btn:SetSize(8, 2) end
            if type(btn.SetAlpha) == 'function' then btn:SetAlpha(0) end
        end
    end
    if not sb.oldKrakenTrack and type(sb.CreateTexture) == 'function' then
        local track = sb:CreateTexture(nil, 'BACKGROUND')
        track.oldKrakenScrollPart = true
        track:SetAllPoints(sb)
        track:SetColorTexture(unpack(colors.scrollTrack))
        sb.oldKrakenTrack = track
    end
    local thumb = (type(sb.GetThumbTexture) == 'function' and sb:GetThumbTexture())
        or sb.ThumbTexture or (sbName and _G[sbName .. 'ThumbTexture'])
    if type(thumb) == 'table' then
        thumb.oldKrakenScrollPart = true
        if type(thumb.SetTexture) == 'function' then thumb:SetTexture(nil) end
        if type(thumb.SetColorTexture) == 'function' then thumb:SetColorTexture(unpack(colors.scrollThumb)) end
        if type(thumb.SetSize) == 'function' then
            thumb:SetSize(6, 36)
        elseif type(thumb.SetWidth) == 'function' then
            thumb:SetWidth(6)
        end
    end
end

function OldKraken:InvitePlayer(name)
    if type(name) ~= 'string' or name == '' then return false end
    if not C_PartyInfo or type(C_PartyInfo.InviteUnit) ~= 'function' then
        print(T('|cffff5555Old Kraken|r: API запрошення недоступний. Запросіть ') .. name .. T(' вручну.'))
        return false
    end
    local ok, result = pcall(C_PartyInfo.InviteUnit, name)
    if ok and result ~= false then
        print(T('|cff2ec4b6Old Kraken|r: Спроба запросити ') .. name .. T(' у паті. Перевірте повідомлення гри.'))
        return true
    end
    print(T('|cffff5555Old Kraken|r: Не вдалося запросити ') .. name .. T('. Запросіть гравця вручну.'))
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

function OldKraken.GetGuildDisplayName()
    local name = GetGuildInfo and GetGuildInfo('player')
    if type(issecretvalue) == 'function' and issecretvalue(name) then return 'Old Kraken' end
    if type(name) == 'string' and name ~= '' then return name end
    return 'Old Kraken'
end

local guildTitles = setmetatable({}, {__mode = 'k'})

local function updateGuildTitle(window, title, name)
    if window.TitleText then
        window.TitleText:SetText(title.suffix and (name .. ' — ' .. title.suffix) or name)
    end
    if title.sidebar then title.sidebar:SetText(name) end
end

function OldKraken.BindGuildTitle(window, suffix, sidebar)
    local title = {suffix = suffix, sidebar = sidebar}
    guildTitles[window] = title
    updateGuildTitle(window, title, OldKraken.GetGuildDisplayName())
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_GUILD_UPDATE")

frame:SetScript("OnEvent", function(self, event, loadedAddon)
    if event ~= "ADDON_LOADED" then
        local name = OldKraken.GetGuildDisplayName()
        for window, title in pairs(guildTitles) do updateGuildTitle(window, title, name) end
        return
    end
    if loadedAddon ~= ADDON_NAME then
        return
    end

    if not OldKraken.Database or not OldKraken.Database.Initialize then
        print(T("|cffff5555Old Kraken|r: помилка ініціалізації бази даних."))
        self:UnregisterEvent("ADDON_LOADED")
        return
    end

    OldKraken.Database.Initialize()
    if OldKraken.InitializeLocale then OldKraken.InitializeLocale(OldKraken.DB) end
    OldKraken:Fire("INITIALIZED", OldKraken.DB)

    print(T("|cff2ec4b6Old Kraken|r: аддон завантажено."))
    self:UnregisterEvent("ADDON_LOADED")
end)
