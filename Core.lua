local ADDON_NAME = ...

OldKraken = OldKraken or {}
OldKraken.name = ADDON_NAME
OldKraken.version = "0.1.0"

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")

frame:SetScript("OnEvent", function(self, event, loadedAddon)
    if loadedAddon ~= ADDON_NAME then
        return
    end

    OldKrakenDB = OldKrakenDB or {
        version = OldKraken.version,
        settings = {},
        roster = {},
        events = {},
    }

    print("|cff2ec4b6Old Kraken|r: аддон завантажено.")
    self:UnregisterEvent("ADDON_LOADED")
end)
