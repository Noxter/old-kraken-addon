local ADDON_NAME = ...

local Roster = {}
OldKraken.GuildRoster = Roster

local ROW_HEIGHT = 22
local CONTENT_WIDTH = 840
local rosterFrame
local rowFrames = {}
local rosterData = {}
local filteredData = {}
local pendingLoad, pendingRender, refreshElapsed = false, false, 0
local drawing = false

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
local addonFilter = 'all'

local function HasAddon(name)
    local comm = OldKraken.Communication
    return comm and comm.HasRosterAddon and comm:HasRosterAddon(name)
end

local copyFrame, memberMenu
local function CopyName(name)
    if not copyFrame then
        copyFrame = CreateFrame('Frame', 'OldKrakenCopyNameFrame', UIParent, 'BasicFrameTemplateWithInset')
        copyFrame:SetSize(330, 100); copyFrame:SetPoint('CENTER'); copyFrame:SetFrameStrata('DIALOG')
        table.insert(UISpecialFrames, 'OldKrakenCopyNameFrame')
        if copyFrame.TitleText then copyFrame.TitleText:SetText("Скопіювати ім'я — Ctrl+C") end
        local edit = CreateFrame('EditBox', nil, copyFrame, 'InputBoxTemplate')
        edit:SetSize(280, 26); edit:SetPoint('CENTER'); edit:SetAutoFocus(false)
        edit:SetScript('OnEscapePressed', function() copyFrame:Hide() end)
        edit:SetScript('OnEnterPressed', function() copyFrame:Hide() end)
        copyFrame.edit = edit
    end
    copyFrame:Show(); copyFrame.edit:SetText(name); copyFrame.edit:SetFocus(); copyFrame.edit:HighlightText()
end

local function ShowMemberMenu(row)
    local member = row.member
    if not member then return end
    if GameTooltip then GameTooltip:Hide() end
    if not memberMenu then memberMenu = CreateFrame('Frame', 'OldKrakenRosterMemberMenu', UIParent, 'UIDropDownMenuTemplate') end
    UIDropDownMenu_Initialize(memberMenu, function(_, level)
        local title = UIDropDownMenu_CreateInfo()
        title.text = member.name; title.isTitle = true; title.notCheckable = true
        UIDropDownMenu_AddButton(title, level)
        local function Action(text, callback, disabled)
            local info = UIDropDownMenu_CreateInfo()
            info.text = text; info.notCheckable = true; info.disabled = disabled
            info.func = function() CloseDropDownMenus(); callback() end
            UIDropDownMenu_AddButton(info, level)
        end
        Action('Запросити в групу', function() OldKraken:InvitePlayer(member.name) end, not member.isOnline)
        Action('Шепнути', function() ChatFrame_SendTell(member.name) end, not member.isOnline)
        Action("Скопіювати ім'я", function() CopyName(member.name) end)
    end, 'MENU')
    ToggleDropDownMenu(1, nil, memberMenu, 'cursor', 0, 0)
end

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

    if addonFilter ~= 'all' then
        local installed = HasAddon(member.name)
        if addonFilter == 'yes' and not installed then return false end
        if addonFilter == 'unknown' and installed then return false end
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

    local filter = CreateFrame('Frame', 'OldKrakenRosterAddonFilter', frame, 'UIDropDownMenuTemplate')
    OldKraken.UIStyle.Dropdown(filter); filter:SetPoint('TOPLEFT', frame, 'TOPLEFT', 570, -36)
    UIDropDownMenu_SetWidth(filter, 160)
    UIDropDownMenu_Initialize(filter, function(_, level)
        for _, entry in ipairs({{'all','Аддон: усі'}, {'yes','Є аддон'}, {'unknown','Немає аддона'}}) do
            local value, label = entry[1], entry[2]
            local info = UIDropDownMenu_CreateInfo()
            info.text = label; info.checked = addonFilter == value
            info.func = function() addonFilter = value; UIDropDownMenu_SetText(filter, label); Roster:Render() end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(filter, 'Аддон: усі'); frame.addonFilter = filter

    local summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    summary:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -72)
    summary:SetJustifyH("LEFT")
    frame.summaryText = summary

    CreateColumnHeader(frame, "ІМ'Я", "name", 18, 170)
    CreateColumnHeader(frame, "РАНГ", "rank", 192, 105)
    CreateColumnHeader(frame, "РІВ.", "level", 301, 45)
    CreateColumnHeader(frame, "КЛАС", "class", 350, 90)
    CreateColumnHeader(frame, "ЛОКАЦІЯ", "zone", 444, 140)
    CreateColumnHeader(frame, "ПРОФЕСІЇ", nil, 588, 80)
    frame.addonHeader = CreateColumnHeader(frame, "АДДОН", nil, 672, 174)


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

    local previousScroll = scroll:GetScript('OnVerticalScroll')
    scroll:SetScript('OnVerticalScroll', function(self, offset)
        if previousScroll then previousScroll(self, offset) end
        if not drawing then Roster:RenderVisible() end
    end)
    local previousResize = scroll:GetScript('OnSizeChanged')
    scroll:SetScript('OnSizeChanged', function(self, width, height)
        if previousResize then previousResize(self, width, height) end
        if not drawing then Roster:RenderVisible() end
    end)
    frame:SetScript('OnShow', function() Roster:ScheduleRefresh(true) end)
    frame.scrollFrame = scroll
    frame.contentFrame = content
    rosterFrame = frame

    UpdateFilterButtonLabels()
    return frame
end

local function CreateRow(index, parent)
    local row = CreateFrame("Button", nil, parent)
    row:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
    row:SetScript('OnClick', ShowMemberMenu)
    row:SetSize(CONTENT_WIDTH, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
    if index % 2 == 0 then
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints(row)
        stripe:SetColorTexture(1, 1, 1, 0.035)
    end

    local columns = {
        { x = 22, width = 154 },
        { x = 180, width = 105 },
        { x = 289, width = 45 },
        { x = 338, width = 90 },
        { x = 432, width = 140 },
        { x = 660, width = 70 },
        { x = 674, width = 160 },

    }

    row.cells = {}
    for cellIndex, column in ipairs(columns) do
        local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        cell:SetPoint("LEFT", row, "LEFT", column.x, 0)
        cell:SetWidth(column.width)
        cell:SetHeight(ROW_HEIGHT)
        cell:SetJustifyH("LEFT")
        cell:SetWordWrap(false)
        row.cells[cellIndex] = cell
    end
    row.onlineDot = row:CreateTexture(nil, 'OVERLAY')
    row.onlineDot:SetPoint('LEFT', row, 'LEFT', 6, 0)
    row.onlineDot:SetWidth(8)
    row.onlineDot:SetHeight(8)
    row.addonDot = row:CreateTexture(nil, 'OVERLAY')
    row.addonDot:SetSize(8, 8); row.addonDot:SetPoint('LEFT', row, 'LEFT', 660, 0)
    row.cellHovers = {}
    for _, cellIndex in ipairs({1, 2, 4, 5, 7}) do
        local hover = CreateFrame('Button', nil, row)
        hover:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
        hover:SetScript('OnClick', function() ShowMemberMenu(row) end)
        hover:SetAllPoints(row.cells[cellIndex]); hover:EnableMouse(true)
        hover:SetScript('OnEnter', function(self)
            if GameTooltip and self.fullText and self.fullText ~= '' then
                GameTooltip:SetOwner(self, 'ANCHOR_RIGHT'); GameTooltip:SetText(self.fullText); GameTooltip:Show()
            end
        end)
        hover:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
        row.cellHovers[cellIndex] = hover
    end

    row.professions = {}
    for i=1,5 do
        local icon=CreateFrame('Button',nil,row)
        icon:SetSize(15,15); icon:SetPoint('LEFT',row,'LEFT',576+(i-1)*16,0)
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
            elseif self.rank then
                GameTooltip:AddLine('Рівень: '..tostring(self.rank)..'/'..tostring(self.maximum or '?'),1,1,1)
                if self.relayed then GameTooltip:AddLine('Отримано через гільдію',1,1,1) end
                if type(self.updated)=='number' and type(GetServerTime)=='function' and GetServerTime()-self.updated>604800 then GameTooltip:AddLine('Дані застарілі',1,0.7,0.25) end
            end
            GameTooltip:AddLine('Натисніть, щоб переглянути збережені рецепти.',0.6,0.9,1,true); GameTooltip:Show()
        end)
        icon:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
        icon:Hide(); row.professions[i]=icon
    end

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

    self:RenderVisible()
end

function Roster:RenderVisible()
    if not rosterFrame or drawing then return end
    drawing = true
    local content = rosterFrame.contentFrame
    local scroll = rosterFrame.scrollFrame
    local viewport = tonumber((scroll:GetHeight())) or 440
    if viewport <= 0 then viewport = 440 end
    content:SetHeight(math.max(1, #filteredData * ROW_HEIGHT))
    local offset = math.max(0, math.min(tonumber((scroll:GetVerticalScroll())) or 0, math.max(0, #filteredData * ROW_HEIGHT - viewport)))
    if offset ~= (tonumber((scroll:GetVerticalScroll())) or 0) then scroll:SetVerticalScroll(offset) end
    local first = math.floor(offset / ROW_HEIGHT) + 1
    local count = math.max(0, math.min(math.ceil(viewport / ROW_HEIGHT) + 1, #filteredData - first + 1))
    local comm = OldKraken.Communication
    local localVersion = comm and comm.GetLocalVersion and comm:GetLocalVersion()
    for index = 1, count do
        local dataIndex = first + index - 1
        local member = filteredData[dataIndex]
        local row = rowFrames[index] or CreateRow(index, content)
        row:ClearAllPoints()
        row:SetPoint('TOPLEFT', content, 'TOPLEFT', 0, -((dataIndex - 1) * ROW_HEIGHT))
        row.member = member
        local cells = row.cells

        cells[7]:Show()

        row.cellHovers[7]:Show()

        if HasAddon(member.name) then cells[7]:SetTextColor(0.25, 1, 0.25) else cells[7]:SetTextColor(0.7, 0.7, 0.7) end
        local version = comm and comm.GetRosterVersion and comm:GetRosterVersion(member.name)
        local comparison = version and comm.CompareVersions and comm:CompareVersions(version, localVersion)
        row.addonDot:SetTexture(HasAddon(member.name) and 'Interface\\AddOns\\OldKraken\\Media\\StatusOnline.tga' or 'Interface\\AddOns\\OldKraken\\Media\\StatusOffline.tga')
        cells[7]:SetText('(' .. (version or '?') .. ')')
        local versionStatus = 'Версію не передано; оновіть аддон учасника та натисніть «Оновити».'
        if comparison == -1 then
            cells[7]:SetTextColor(1, 0.55, 0.15); versionStatus = 'Застаріла: версія старіша за вашу.'
        elseif comparison == 1 then
            cells[7]:SetTextColor(0.3, 0.8, 1); versionStatus = 'Новіша за вашу версію.'
        elseif comparison == 0 then
            cells[7]:SetTextColor(0.25, 1, 0.25); versionStatus = 'Така сама версія, як у вас.'
        else
            cells[7]:SetTextColor(0.7, 0.7, 0.7)
            if version then versionStatus = 'Не вдалося порівняти номер версії.' end
        end
        row.cellHovers[7].fullText = (version or 'Невідомо') .. '\n' .. versionStatus
        cells[1]:SetText(SafeText(member.name))
        cells[2]:SetText(SafeText(member.rank))
        cells[3]:SetText(SafeText(member.level))
        cells[4]:SetText(SafeText(member.class))
        cells[5]:SetText(SafeText(member.zone))
        cells[6]:Hide()
        row.onlineDot:SetTexture(member.isOnline and 'Interface\\AddOns\\OldKraken\\Media\\StatusOnline.tga' or 'Interface\\AddOns\\OldKraken\\Media\\StatusOffline.tga')
        row.cellHovers[1].fullText = SafeText(member.name)
        row.cellHovers[2].fullText = SafeText(member.rank)
        row.cellHovers[4].fullText = SafeText(member.class)
        row.cellHovers[5].fullText = SafeText(member.zone)

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
        local professions=OldKraken.Workshop and OldKraken.Workshop:GetMemberProfessions(member.name) or {}
        for i,icon in ipairs(row.professions) do
            local profession=professions[i]
            if profession then
                local _,texture=OldKraken.Workshop:ProfessionInfo(profession.id)
                icon.professionID,icon.memberName,icon.native,icon.rank,icon.maximum,icon.updated,icon.relayed=profession.id,member.name,profession.native,profession.rank,profession.maximum,profession.timestamp,profession.relayed
                icon.texture:SetTexture(texture); icon.texture:SetAlpha(profession.native and 0.55 or 1); icon:Show()
            else icon.professionID=nil; icon:Hide() end
        end
    end

    for index = count + 1, #rowFrames do
        rowFrames[index].member = nil
        rowFrames[index]:Hide()
    end
    drawing = false
end

function Roster:Load()
    pendingLoad, pendingRender = false, false
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

    if OldKraken.Communication.RequestRosterPresence then OldKraken.Communication:RequestRosterPresence() end
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
function Roster:ScheduleRefresh(reload)
    pendingLoad = pendingLoad or reload == true
    pendingRender = true
end
eventFrame:SetScript('OnUpdate', function(_, elapsed)
    if not pendingRender then refreshElapsed = 0; return end
    refreshElapsed = refreshElapsed + elapsed
    if refreshElapsed < 0.15 then return end
    refreshElapsed = 0
    if not rosterFrame or not rosterFrame:IsShown() then return end
    local reload = pendingLoad
    pendingLoad, pendingRender = false, false
    if reload then Roster:Load() else Roster:Render() end
end)
eventFrame:SetScript('OnEvent', function() Roster:ScheduleRefresh(true) end)
if type(OldKraken.On)=='function' then
    OldKraken:On('ROSTER_ADDON_CHANGED',function() Roster:ScheduleRefresh(false) end)
    OldKraken:On('WORKSHOP_PROFESSIONS_CHANGED',function() Roster:ScheduleRefresh(false) end)
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

