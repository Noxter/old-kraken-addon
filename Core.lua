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
}

function OldKraken.UIStyle.EmblemPath()
    return 'Interface\\AddOns\\' .. OldKraken.name .. '\\Media\\OldKrakenEmblem.tga'
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
    if frame.NineSlice then frame.NineSlice:Hide() end
    if frame.Bg then frame.Bg:Hide() end
    if frame.Inset then frame.Inset:Hide() end
    local colors = OldKraken.UIStyle.Colors
    local background = frame:CreateTexture(nil, 'BACKGROUND', nil, -8)
    background:SetAllPoints(frame)
    background:SetColorTexture(unpack(colors.window))
    local header = frame:CreateTexture(nil, 'BACKGROUND', nil, -7)
    header:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
    header:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, 0)
    header:SetHeight(28)
    header:SetColorTexture(unpack(colors.header))
    local accent = frame:CreateTexture(nil, 'ARTWORK')
    accent:SetColorTexture(unpack(colors.brandGold))
    accent:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, -27)
    accent:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, -27)
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
        if texture and texture.SetVertexColor then texture:SetVertexColor(unpack(colors.dropdownTint)) end
    end
    local label = _G[name .. 'Text']
    if label and label.SetTextColor then
        label:SetTextColor(colors.text[1], colors.text[2], colors.text[3])
    end
    local toggle = _G[name .. 'Button']
    if toggle then
        local arrow = type(toggle.GetNormalTexture) == 'function' and toggle:GetNormalTexture()
        if arrow and arrow.SetVertexColor then arrow:SetVertexColor(colors.brandGold[1], colors.brandGold[2], colors.brandGold[3]) end
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
