local ADDON_NAME = ...

OldKraken = OldKraken or {}
OldKraken.name = ADDON_NAME
OldKraken.version = "0.4.0-alpha.3"
OldKraken._listeners = OldKraken._listeners or {}

-- Shared dark theme for the addon's native controls.
OldKraken.UIStyle = {}
function OldKraken.UIStyle.Window(frame)
    frame:SetFrameStrata('FULLSCREEN')
    frame:SetToplevel(true)
    if frame.NineSlice then frame.NineSlice:Hide() end
    if frame.Bg then frame.Bg:Hide() end
    if frame.Inset then frame.Inset:Hide() end
    local background = frame:CreateTexture(nil, 'BACKGROUND', nil, -8)
    background:SetAllPoints(frame)
    background:SetColorTexture(0.055, 0.060, 0.070, 0.98)
    local header = frame:CreateTexture(nil, 'BACKGROUND', nil, -7)
    header:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
    header:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, 0)
    header:SetHeight(28)
    header:SetColorTexture(0.11, 0.12, 0.13, 1)
    local accent = frame:CreateTexture(nil, 'ARTWORK')
    accent:SetColorTexture(0.0, 0.57, 0.93, 0.95)
    accent:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, -27)
    accent:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, -27)
    accent:SetHeight(1)
    if frame.TitleText then frame.TitleText:SetTextColor(0.94, 0.95, 0.96) end
end

function OldKraken.UIStyle.Button(button)
    if button.NineSlice then button.NineSlice:Hide() end
    for _, part in ipairs({'Left', 'Middle', 'Right'}) do
        if button[part] then button[part]:Hide() end
    end
    local normal, pushed = button:GetNormalTexture(), button:GetPushedTexture()
    if normal then normal:SetAlpha(0) end
    if pushed then pushed:SetAlpha(0) end
    local fill = button:CreateTexture(nil, 'BACKGROUND')
    fill:SetAllPoints(button)
    fill:SetColorTexture(0.14, 0.15, 0.17, 1)
    local highlight = button:CreateTexture(nil, 'HIGHLIGHT')
    highlight:SetAllPoints(button)
    highlight:SetColorTexture(0.0, 0.57, 0.93, 0.32)
    button:SetHighlightTexture(highlight)
end

function OldKraken.UIStyle.Dropdown(frame)
    local name = frame:GetName()
    if not name then return end
    for _, part in ipairs({'Left', 'Middle', 'Right'}) do
        local texture = _G[name .. part]
        if texture and texture.SetVertexColor then texture:SetVertexColor(0.48, 0.53, 0.57) end
    end
end

function OldKraken.UIStyle.Panel(frame, x, y, width, height)
    local panel = frame:CreateTexture(nil, 'BACKGROUND', nil, 1)
    panel:SetPoint('TOPLEFT', frame, 'TOPLEFT', x, y)
    panel:SetSize(width, height)
    panel:SetColorTexture(0.12, 0.13, 0.14, 0.90)
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
