local ADDON_NAME = ...

OldKraken = OldKraken or {}
OldKraken.name = ADDON_NAME
OldKraken.version = "0.3.0"

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")

frame:SetScript("OnEvent", function(self, event, loadedAddon)
    if loadedAddon ~= ADDON_NAME then
        return
    end

    OldKrakenDB = OldKrakenDB or {}
    OldKrakenDB.version = OldKraken.version
    OldKrakenDB.settings = OldKrakenDB.settings or {}
    OldKrakenDB.settings.roster = OldKrakenDB.settings.roster or {}
    OldKrakenDB.roster = OldKrakenDB.roster or {}
    OldKrakenDB.events = OldKrakenDB.events or {}

    print("|cff2ec4b6Old Kraken|r: аддон завантажено.")
    self:UnregisterEvent("ADDON_LOADED")
end)
