local ADDON_NAME = ...

OldKraken = OldKraken or {}
OldKraken.name = ADDON_NAME
OldKraken.version = "0.3.2"
OldKraken._listeners = OldKraken._listeners or {}

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
