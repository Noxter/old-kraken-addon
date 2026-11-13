local ADDON_NAME = ...

OldKraken = OldKraken or {}
OldKraken.name = ADDON_NAME
OldKraken.version = "0.4.0-alpha.2-syncfix"
OldKraken._listeners = OldKraken._listeners or {}

-- Shared styling keeps the native controls and their interaction behavior.
OldKraken.UIStyle = {}
function OldKraken.UIStyle.Window(frame)
    local accent = frame:CreateTexture(nil, 'ARTWORK')
    accent:SetColorTexture(0.18, 0.77, 0.71, 0.95)
    accent:SetPoint('TOPLEFT', frame, 'TOPLEFT', 12, -27)
    accent:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -12, -27)
    accent:SetHeight(2)
    if frame.TitleText then frame.TitleText:SetTextColor(0.45, 0.91, 0.86) end
end

function OldKraken.UIStyle.Button(button)
    local normal, pushed, highlight = button:GetNormalTexture(), button:GetPushedTexture(), button:GetHighlightTexture()
    if normal then normal:SetVertexColor(0.56, 0.79, 0.77) end
    if pushed then pushed:SetVertexColor(0.38, 0.69, 0.66) end
    if highlight then highlight:SetVertexColor(0.35, 0.95, 0.85, 0.7) end
end

function OldKraken.UIStyle.Panel(frame, x, y, width, height)
    local panel = frame:CreateTexture(nil, 'BACKGROUND', nil, 1)
    panel:SetPoint('TOPLEFT', frame, 'TOPLEFT', x, y)
    panel:SetSize(width, height)
    panel:SetColorTexture(0.035, 0.10, 0.11, 0.55)
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
