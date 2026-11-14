local ADDON_NAME = ...

local Roster = {}
OldKraken.GuildRoster = Roster

local ROW_HEIGHT = 22
local CONTENT_WIDTH = 840
local rosterFrame
local rowFrames = {}
local rosterData = {}
local filteredData = {}

local CLASS_ORDER = {
    "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST",
    "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR",
}

local STATUS_LABELS = {
    all = "Усі",
    online = "Онлайн",
    offline = "Офлайн",
}

local SORT_LABELS = {
    name = "Ім'я",
    level = "Рівень",
    class = "Клас",
    rank = "Ранг",
    zone = "Локація",
}

local settings

local function GetSettings()
    if not OldKraken.DB then
        return nil
    end

    settings = OldKraken.DB.settings.roster
    return settings
end

local function SafeText(value, fallback)
    if value == nil or value == "" then
        return fallback or "-"
    end
    return tostring(value)
end

local function ClassLabel(classToken)
    if not classToken or classToken == "" then
        return "Усі класи"
    end

    for _, member in ipairs(rosterData) do
        if member.classFile == classToken and member.class then
            return member.class
        end
    end

    return classToken
end

local function UpdateFilterButtonLabels()
    if not rosterFrame then
        return
    end

    UIDropDownMenu_SetText(rosterFrame.statusDropdown, "Статус: " .. (STATUS_LABELS[settings.status] or "Усі"))
    UIDropDownMenu_SetText(
        rosterFrame.classDropdown,
        settings.class == "ALL" and "Усі класи" or ClassLabel(settings.class)
    )
end

local function MatchesFilters(member)
    local query = string.lower(settings.search or "")
    if query ~= "" and not string.find(string.lower(member.name or ""), query, 1, true) then
        return false
    end

    if settings.status == "online" and not member.isOnline then
        return false
    elseif settings.status == "offline" and member.isOnline then
        return false
    end

    if settings.class ~= "ALL" and member.classFile ~= settings.class then
        return false
    end

    return true
end

local function SortMembers(a, b)
    if a.isOnline ~= b.isOnline then
        return a.isOnline
    end

    local key = settings.sort
    local left, right

    if key == "name" then
        left = string.lower(a.name or "")
        right = string.lower(b.name or "")
    elseif key == "class" then
        left = a.class or a.classFile or ""
        right = b.class or b.classFile or ""
    elseif key == "rank" then
        left = tonumber(a.rankIndex) or 0
        right = tonumber(b.rankIndex) or 0
    elseif key == "zone" then
        left = string.lower(a.zone or "")
        right = string.lower(b.zone or "")
    else
        left = tonumber(a.level) or 0
        right = tonumber(b.level) or 0
    end

    if left == right then
        return string.lower(a.name or "") < string.lower(b.name or "")
    end

    if settings.ascending then
        return left < right
    end
    return left > right
end

local function CreateColumnHeader(parent, label, key, x, width)
    if not key then
        local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header:SetPoint("LEFT", parent, "TOPLEFT", x + 6, -116)
        header:SetWidth(width - 8)
        header:SetHeight(22)
        header:SetJustifyH("LEFT")
        header:SetText(label)
        return header
    end

    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    OldKraken.UIStyle.Button(button)
    button:SetSize(width, 22)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -105)
    button:SetText(label)
    button:SetScript("OnClick", function()
        if settings.sort == key then
            settings.ascending = not settings.ascending
        else
            settings.sort = key
            settings.ascending = true
        end
        Roster:Render()
    end)
    return button
end

local function CreateRosterWindow(parent)
    if rosterFrame then
        return rosterFrame
    end

    local frame
    if parent then
        frame = CreateFrame("Frame", "OldKrakenRosterFrame", parent)
    else
        frame = CreateFrame("Frame", "OldKrakenRosterFrame", UIParent, "BasicFrameTemplateWithInset")
    end
    if not parent then table.insert(UISpecialFrames, "OldKrakenRosterFrame") end
    frame:SetSize(900, 590)
    frame:SetPoint("CENTER", parent or UIParent, "CENTER")
    frame:SetMovable(not parent)
    frame:EnableMouse(true)
    if not parent then
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    end
    frame:SetClampedToScreen(true)
    if not parent then OldKraken.UIStyle.Window(frame) end
    OldKraken.UIStyle.Panel(frame, 12, -132, 852, 440)
    frame:Hide()

    if frame.TitleText then
        frame.TitleText:SetText("Old Kraken — Guild Roster")
    end

    local refreshButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    OldKraken.UIStyle.Button(refreshButton)
    refreshButton:SetSize(92, 24)
    refreshButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -38, -30)
    refreshButton:SetText("Оновити")
    refreshButton:SetScript("OnClick", function()
        Roster:RequestUpdate()
    end)

    local searchBox = CreateFrame("EditBox", "OldKrakenRosterSearchBox", frame, "InputBoxTemplate")
    OldKraken.UIStyle.Input(searchBox)
    searchBox:SetSize(190, 24)
    searchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -38)
    searchBox:SetAutoFocus(false)
    searchBox:SetTextInsets(6, 6, 0, 0)
    searchBox:SetText(settings.search or "")
    searchBox:SetScript("OnTextChanged", function(self)
        settings.search = self:GetText() or ""
        Roster:Render()
    end)
    frame.searchBox = searchBox

    local statusDropdown = CreateFrame("Frame", "OldKrakenRosterStatusDropdown", frame, "UIDropDownMenuTemplate")
    OldKraken.UIStyle.Dropdown(statusDropdown)
    statusDropdown:SetPoint("LEFT", searchBox, "RIGHT", -6, -2)
    UIDropDownMenu_SetWidth(statusDropdown, 125)
    UIDropDownMenu_JustifyText(statusDropdown, "LEFT")
    UIDropDownMenu_Initialize(statusDropdown, function(_, level)
        for _, value in ipairs({"all", "online", "offline"}) do
            local status = value
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.value = STATUS_LABELS[status], status
            info.checked = settings.status == status
            info.func = function() settings.status = status; Roster:Render() end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    frame.statusDropdown = statusDropdown

    local classDropdown = CreateFrame("Frame", "OldKrakenClassDropdown", frame, "UIDropDownMenuTemplate")
    OldKraken.UIStyle.Dropdown(classDropdown)
    classDropdown:SetPoint("LEFT", statusDropdown, "RIGHT", -8, 0)
    UIDropDownMenu_SetWidth(classDropdown, 150)
    UIDropDownMenu_JustifyText(classDropdown, "LEFT")
    UIDropDownMenu_Initialize(classDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        info.text = "Усі класи"
        info.value = "ALL"
        info.checked = settings.class == "ALL"
        info.func = function()
            settings.class = "ALL"
            Roster:Render()
        end
        UIDropDownMenu_AddButton(info, level)

        for _, classToken in ipairs(CLASS_ORDER) do
            local token = classToken
            local classInfo = UIDropDownMenu_CreateInfo()
            classInfo.text = ClassLabel(token)
            classInfo.value = token
            classInfo.checked = settings.class == token
            classInfo.func = function()
                settings.class = token
                Roster:Render()
            end
            UIDropDownMenu_AddButton(classInfo, level)
        end
    end)
    frame.classDropdown = classDropdown

    local summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    summary:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -72)
    summary:SetJustifyH("LEFT")
    frame.summaryText = summary

    CreateColumnHeader(frame, "ІМ'Я", "name", 18, 180)
    CreateColumnHeader(frame, "РАНГ", "rank", 202, 130)
    CreateColumnHeader(frame, "РІВ.", "level", 336, 48)
    CreateColumnHeader(frame, "КЛАС", "class", 388, 100)
    CreateColumnHeader(frame, "ЛОКАЦІЯ", "zone", 492, 100)
    CreateColumnHeader(frame, "ПРОФЕСІЇ", nil, 594, 80)
    CreateColumnHeader(frame, "СТАТУС", nil, 676, 74)
    CreateColumnHeader(frame, "ДІЯ", nil, 754, 84)

    local scroll = CreateFrame("ScrollFrame", "OldKrakenRosterScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -132)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 14)
    scroll:EnableMouseWheel(true)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_WIDTH, 1)
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

    UpdateFilterButtonLabels()
    return frame
end

local function CreateRow(index, parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(CONTENT_WIDTH, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
    if index % 2 == 0 then
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints(row)
        stripe:SetColorTexture(1, 1, 1, 0.035)
    end

    local columns = {
        { x = 6, width = 180 },
        { x = 190, width = 130 },
        { x = 324, width = 48 },
        { x = 376, width = 100 },
        { x = 480, width = 100 },
        { x = 664, width = 74 },
    }

    row.cells = {}
    for cellIndex, column in ipairs(columns) do
        local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cell:SetPoint("LEFT", row, "LEFT", column.x, 0)
        cell:SetWidth(column.width)
        cell:SetHeight(ROW_HEIGHT)
        cell:SetJustifyH("LEFT")
        cell:SetWordWrap(false)
        row.cells[cellIndex] = cell
    end

    row.professions = {}
    for i=1,5 do
        local icon=CreateFrame('Button',nil,row)
        icon:SetSize(15,15); icon:SetPoint('LEFT',row,'LEFT',584+(i-1)*16,0)
        icon.texture=icon:CreateTexture(nil,'ARTWORK'); icon.texture:SetAllPoints(icon)
        icon:SetScript('OnClick',function(self)
            if self.memberName and self.professionID and OldKraken.WorkshopRecipes then
                OldKraken.WorkshopRecipes:ShowMemberProfession(self.memberName,self.professionID)
            end
        end)
        icon:SetScript('OnEnter',function(self)
            if not GameTooltip or not self.professionID or not OldKraken.Workshop then return end
            local name=OldKraken.Workshop:ProfessionInfo(self.professionID)
            GameTooltip:SetOwner(self,'ANCHOR_RIGHT'); GameTooltip:SetText(name)
            if self.native then GameTooltip:AddLine('Професія з ігрового ростера; рівень і рецепти невідомі.',1,1,1,true)
            elseif self.rank then GameTooltip:AddLine('Рівень: '..tostring(self.rank)..'/'..tostring(self.maximum or '?'),1,1,1) end
            GameTooltip:AddLine('Натисніть, щоб переглянути збережені рецепти.',0.6,0.9,1,true); GameTooltip:Show()
        end)
        icon:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
        icon:Hide(); row.professions[i]=icon
    end

    local inviteButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    OldKraken.UIStyle.Button(inviteButton, "primary")
    inviteButton:SetSize(76, 18)
    inviteButton:SetPoint("LEFT", row, "LEFT", 746, 0)
    inviteButton:SetText("Інвайт")
    inviteButton:SetScript("OnClick", function(self)
        if self.memberName and self.online then
            OldKraken:InvitePlayer(self.memberName)
        end
    end)
    inviteButton:SetScript("OnEnter", function(self)
        if GameTooltip and self.memberName then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.online and ("Запросити " .. self.memberName .. " у групу") or "Гравець офлайн")
            GameTooltip:Show()
        end
    end)
    inviteButton:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    row.inviteButton = inviteButton

    local offlineStatus = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    offlineStatus:SetPoint("CENTER", inviteButton, "CENTER")
    offlineStatus:SetWidth(76)
    offlineStatus:SetJustifyH("CENTER")
    offlineStatus:SetText("Офлайн")
    offlineStatus:SetTextColor(0.63, 0.67, 0.73)
    offlineStatus:Hide()
    row.offlineStatus = offlineStatus

    rowFrames[index] = row
    return row
end

local function UpdateSummary()
    local total = #rosterData
    local online = 0
    for _, member in ipairs(rosterData) do
        if member.isOnline then
            online = online + 1
        end
    end

    local visibleOnline = 0
    for _, member in ipairs(filteredData) do
        if member.isOnline then
            visibleOnline = visibleOnline + 1
        end
    end

    rosterFrame.summaryText:SetText(string.format(
        "Учасників: %d | Онлайн: %d | Показано: %d (онлайн: %d)",
        total, online, #filteredData, visibleOnline
    ))
end

function Roster:Render()
    if not GetSettings() then
        return
    end

    if not rosterFrame then
        CreateRosterWindow()
    end

    filteredData = {}
    for _, member in ipairs(rosterData) do
        if MatchesFilters(member) then
            filteredData[#filteredData + 1] = member
        end
    end
    table.sort(filteredData, SortMembers)

    UpdateSummary()
    UpdateFilterButtonLabels()

    local content = rosterFrame.contentFrame
    content:SetHeight(math.max(1, #filteredData * ROW_HEIGHT))

    for index, member in ipairs(filteredData) do
        local row = rowFrames[index] or CreateRow(index, content)
        local cells = row.cells

        cells[1]:SetText(SafeText(member.name))
        cells[2]:SetText(SafeText(member.rank))
        cells[3]:SetText(SafeText(member.level))
        cells[4]:SetText(SafeText(member.class))
        cells[5]:SetText(SafeText(member.zone))
        cells[6]:SetText(member.isOnline and "Онлайн" or "Офлайн")

        local classColor = member.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.classFile]
        if classColor then
            cells[1]:SetTextColor(classColor.r, classColor.g, classColor.b)
            cells[4]:SetTextColor(classColor.r, classColor.g, classColor.b)
        else
            cells[1]:SetTextColor(1, 1, 1)
            cells[4]:SetTextColor(1, 1, 1)
        end

        if member.isOnline then
            cells[6]:SetTextColor(0.25, 1, 0.25)
        else
            cells[6]:SetTextColor(0.55, 0.55, 0.55)
        end

        row:Show()
        row.inviteButton.memberName = member.name
        row.inviteButton.online = member.isOnline
        row.inviteButton:SetEnabled(member.isOnline)
        row.inviteButton:SetShown(member.isOnline)
        row.offlineStatus:SetShown(not member.isOnline)
        local professions=OldKraken.Workshop and OldKraken.Workshop:GetMemberProfessions(member.name) or {}
        for i,icon in ipairs(row.professions) do
            local profession=professions[i]
            if profession then
                local _,texture=OldKraken.Workshop:ProfessionInfo(profession.id)
                icon.professionID,icon.memberName,icon.native,icon.rank,icon.maximum=profession.id,member.name,profession.native,profession.rank,profession.maximum
                icon.texture:SetTexture(texture); icon.texture:SetAlpha(profession.native and 0.55 or 1); icon:Show()
            else icon.professionID=nil; icon:Hide() end
        end
    end

    for index = #filteredData + 1, #rowFrames do
        rowFrames[index]:Hide()
    end
end

function Roster:Load()
    if OldKraken.Workshop then OldKraken.Workshop:RefreshNativeProfessions() end
    local total = GetNumGuildMembers()
    total = tonumber(total) or 0

    rosterData = {}

    for index = 1, total do
        local name, rankName, rankIndex, level, className, zone,
            publicNote, officerNote, isOnline, status, classFileName = GetGuildRosterInfo(index)

        if name then
            rosterData[#rosterData + 1] = {
                name = name,
                rank = rankName,
                rankIndex = tonumber(rankIndex) or 0,
                level = tonumber(level) or 0,
                class = className or classFileName,
                classFile = classFileName,
                zone = zone,
                isOnline = isOnline == true,
            }
        end
    end

    self:Render()
    return #rosterData
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
    if not GetSettings() then
        print("|cff2ec4b6Old Kraken|r: база даних ще не ініціалізована.")
        return
    end

    if OldKraken.UIHub then
        OldKraken.UIHub:ShowPage("roster")
    else
        local frame = CreateRosterWindow()
        frame:Show()
    end
    self:Load()
    self:RequestUpdate()
end

function Roster:Toggle()
    if OldKraken.UIHub and OldKraken.UIHub.frame and OldKraken.UIHub.frame:IsShown()
        and OldKraken.UIHub.currentPage == "roster" then
        OldKraken.UIHub.frame:Hide()
    elseif rosterFrame and rosterFrame:IsShown() and not OldKraken.UIHub then
        rosterFrame:Hide()
    else
        self:Show()
    end
end

if OldKraken.UIHub then
    OldKraken.UIHub:RegisterPage("roster", "Ростер", "01", function(parent)
        return CreateRosterWindow(parent)
    end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
eventFrame:SetScript("OnEvent", function()
    if rosterFrame and rosterFrame:IsShown() then
        Roster:Load()
    end
end)
if type(OldKraken.On)=='function' then
    OldKraken:On('WORKSHOP_PROFESSIONS_CHANGED',function()
        if rosterFrame and rosterFrame:IsShown() then Roster:Render() end
    end)
end

SLASH_OLDKRAKEN1 = "/okr"
SLASH_OLDKRAKEN2 = "/oldkraken"
SlashCmdList["OLDKRAKEN"] = function(message)
    local command = string.lower(message or "")

    if OldKraken.Communication and OldKraken.Communication:HandleCommand(command) then
        return
    end

    if OldKraken.GroupFinderAPI and OldKraken.GroupFinderAPI:HandleCommand(command) then
        return
    end

    if command == 'recipes' then
        if OldKraken.WorkshopRecipes then OldKraken.WorkshopRecipes:Show() end
        return
    elseif command == 'orders' then
        if OldKraken.WorkshopOrders then OldKraken.WorkshopOrders:Show() end
        return
    elseif command == 'workshop' or command == 'craft' then
        if OldKraken.Workshop then OldKraken.Workshop:Show() end
        return
    elseif command == 'events' or command == 'calendar' then
        if OldKraken.GuildEvents then OldKraken.GuildEvents:Show() end
        return
    elseif command == 'alerts group' or command == 'alerts request' or command == 'alerts event' or command == 'alerts workshop' then
        if OldKraken.GroupFinder and OldKraken.GroupFinder.PreviewAlert then
            OldKraken.GroupFinder:PreviewAlert(command == 'alerts group' and 'group' or (command == 'alerts event' and 'event' or (command == 'alerts workshop' and 'workshop' or 'request')))
        end
        return
    elseif command == 'group status' then
        if OldKraken.GroupFinder then OldKraken.GroupFinder:PrintSyncStatus() end
        return
    elseif command == 'group sync' then
        if OldKraken.GroupFinder then OldKraken.GroupFinder:RequestSyncNow() end
        return
    elseif command == 'group' or command == 'groups' then
        if OldKraken.GroupFinder then OldKraken.GroupFinder:Show() end
        return
    end

    if command == "refresh" then
        Roster:RequestUpdate()
    else
        Roster:Show()
    end
end

