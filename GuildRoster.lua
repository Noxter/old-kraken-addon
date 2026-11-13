local ADDON_NAME = ...

local Roster = {}
OldKraken.GuildRoster = Roster

local ROW_HEIGHT = 22
local VISIBLE_ROWS = 16
local rosterFrame
local rowFrames = {}
local rosterData = {}

local function SafeText(value, fallback)
    if value == nil or value == "" then
        return fallback or "-"
    end
    return tostring(value)
end

local function CreateRosterWindow()
    if rosterFrame then
        return rosterFrame
    end

    local frame = CreateFrame("Frame", "OldKrakenRosterFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(720, 470)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:Hide()

    if frame.TitleText then
        frame.TitleText:SetText("Old Kraken — Guild Roster")
    end

    local refreshButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refreshButton:SetSize(100, 24)
    refreshButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -38, -30)
    refreshButton:SetText("Оновити")
    refreshButton:SetScript("OnClick", function()
        Roster:RequestUpdate()
    end)

    local summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    summary:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -38)
    summary:SetJustifyH("LEFT")
    frame.summaryText = summary

    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -67)
    header:SetText("ІМ'Я                         РАНГ                 РІВ.    КЛАС             ЛОКАЦІЯ                         СТАТУС")

    local scroll = CreateFrame("ScrollFrame", "OldKrakenRosterScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -88)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 14)
    scroll:EnableMouseWheel(true)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(660, 1)
    scroll:SetScrollChild(content)

    scroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maximum = math.max(0, content:GetHeight() - self:GetHeight())
        local nextValue = math.max(0, math.min(maximum, current - delta * ROW_HEIGHT * 3))
        self:SetVerticalScroll(nextValue)
    end)

    frame.scrollFrame = scroll
    frame.contentFrame = content
    rosterFrame = frame

    return frame
end

local function CreateRow(index, parent)
    local row = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row:SetJustifyH("LEFT")
    row:SetWordWrap(false)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -((index - 1) * ROW_HEIGHT))
    row:SetWidth(650)
    rowFrames[index] = row
    return row
end

local function RenderRoster()
    local frame = CreateRosterWindow()
    local content = frame.contentFrame
    local total = #rosterData
    local online = 0

    for _, member in ipairs(rosterData) do
        if member.isOnline then
            online = online + 1
        end
    end

    frame.summaryText:SetText(string.format("Учасників: %d | Онлайн: %d", total, online))
    content:SetHeight(math.max(1, total * ROW_HEIGHT))

    for index, member in ipairs(rosterData) do
        local row = rowFrames[index] or CreateRow(index, content)
        local name = SafeText(member.name)
        local rank = SafeText(member.rank)
        local level = SafeText(member.level)
        local class = SafeText(member.class)
        local zone = SafeText(member.zone)
        local status = member.isOnline and "Онлайн" or "Офлайн"

        row:SetText(string.format("%-22s %-20s %3s   %-15s %-28s %s",
            name, rank, level, class, zone, status))
        row:Show()
    end

    for index = total + 1, #rowFrames do
        rowFrames[index]:Hide()
    end
end

function Roster:Load()
    local total, online = GetNumGuildMembers()
    total = tonumber(total) or 0
    online = tonumber(online) or 0

    rosterData = {}

    for index = 1, total do
        local name, rankName, rankIndex, level, className, zone,
            publicNote, officerNote, isOnline, status, classFileName = GetGuildRosterInfo(index)

        if name then
            rosterData[#rosterData + 1] = {
                name = name,
                rank = rankName,
                rankIndex = rankIndex,
                level = level,
                class = className or classFileName,
                zone = zone,
                isOnline = isOnline == true,
            }
        end
    end

    RenderRoster()
    return total, online
end

function Roster:RequestUpdate()
    if not IsInGuild or not IsInGuild() then
        print("|cff2ec4b6Old Kraken|r: персонаж не перебуває в гільдії.")
        return
    end

    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    else
        print("|cff2ec4b6Old Kraken|r: API оновлення ростера недоступний.")
    end
end

function Roster:Show()
    local frame = CreateRosterWindow()
    frame:Show()
    self:Load()
    self:RequestUpdate()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
eventFrame:SetScript("OnEvent", function()
    if rosterFrame and rosterFrame:IsShown() then
        Roster:Load()
    end
end)

SLASH_OLDKRAKEN1 = "/okr"
SLASH_OLDKRAKEN2 = "/oldkraken"
SlashCmdList["OLDKRAKEN"] = function(message)
    local command = string.lower(message or "")
    if command == "refresh" then
        Roster:RequestUpdate()
    else
        Roster:Show()
    end
end
