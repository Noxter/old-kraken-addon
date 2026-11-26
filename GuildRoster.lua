local T = OldKraken.Translate or function(text) return text end
local function chatInfo(msg)
    if OldKraken.Print then OldKraken:Print(msg) else print('|cff2ec4b6Old Kraken|r: ' .. tostring(msg or ''):gsub('^|c%x%x%x%x%x%x%x%xOld Kraken|r:%s*', ''):gsub('^Old Kraken:%s*', '')) end
end
local function chatError(msg)
    if OldKraken.PrintError then OldKraken:PrintError(msg) else print('|cffff5555Old Kraken|r: ' .. tostring(msg or ''):gsub('^|c%x%x%x%x%x%x%x%xOld Kraken|r:%s*', ''):gsub('^Old Kraken:%s*', '')) end
end
local ADDON_NAME = ...

local Roster = {}
OldKraken.GuildRoster = Roster

local ROW_HEIGHT = 40
local CONTENT_WIDTH = 874
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

local CLASS_NAMES = {
    DRUID = "Druid",
    HUNTER = "Hunter",
    MAGE = "Mage",
    PALADIN = "Paladin",
    PRIEST = "Priest",
    ROGUE = "Rogue",
    SHAMAN = "Shaman",
    WARLOCK = "Warlock",
    WARRIOR = "Warrior",
}

local STATUS_LABELS = {
    all = "усі",
    online = "онлайн",
    offline = "офлайн",
}

local ADDON_LABELS = {
    all = "Аддон: усі",
    yes = "Аддон: є",
    unknown = "Аддон: не виявлено",
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
local selectedProfileName, savedScrollOffset = nil, 0
local OpenMemberProfile, CloseMemberProfile, RenderMemberProfile

local function isSelfMember(memberName)
    if type(memberName) ~= 'string' or memberName == '' or type(UnitName) ~= 'function' then
        return false
    end
    local first, second = UnitName('player')
    if type(first) ~= 'string' or first == '' then return false end
    local full = (type(second) == 'string' and second ~= '') and (first .. ' ' .. second) or first
    if memberName == full then return true end
    local realm = type(GetRealmName) == 'function' and GetRealmName() or nil
    if type(realm) == 'string' and realm ~= '' then
        if memberName == (first .. '-' .. realm) or memberName == (full .. '-' .. realm) then
            return true
        end
    end
    return memberName == first and not memberName:find('-', 1, true)
end

local function isWorkshopAvailable()
    local ws = OldKraken.Workshop
    if not ws or type(ws.GetMemberProfessions) ~= 'function' or not OldKraken.DB then
        return false
    end
    if type(ws.IsActive) == 'function' then
        return ws:IsActive() == true
    end
    if type(IsInGuild) == 'function' and IsInGuild() == false then
        return false
    end
    return true
end
local function CopyName(name)
    if not copyFrame then
        copyFrame = CreateFrame('Frame', 'OldKrakenCopyNameFrame', UIParent, 'BasicFrameTemplateWithInset')
        copyFrame:SetSize(400, 138); copyFrame:SetPoint('CENTER')
        OldKraken.UIStyle.Window(copyFrame)
        copyFrame:SetFrameStrata('FULLSCREEN_DIALOG'); copyFrame:SetFrameLevel(100)
        copyFrame:EnableMouse(true)
        table.insert(UISpecialFrames, 'OldKrakenCopyNameFrame')
        if copyFrame.TitleText then copyFrame.TitleText:SetText(T("Скопіювати ім'я — Ctrl+C")) end
        local edit = CreateFrame('EditBox', nil, copyFrame, 'InputBoxTemplate')
        OldKraken.UIStyle.Input(edit)
        edit:SetSize(350, 28); edit:SetPoint('TOPLEFT',copyFrame,'TOPLEFT',24,-67); edit:SetAutoFocus(false)
        edit:SetTextInsets(6,6,0,0)
        local hint=copyFrame:CreateFontString(nil,'OVERLAY','GameFontHighlight')
        hint:SetPoint('TOPLEFT',copyFrame,'TOPLEFT',20,-38)
        hint:SetText(T('Ім’я виділено: Ctrl+C — скопіювати, Esc — закрити'))
        edit:SetScript('OnEscapePressed', function() copyFrame:Hide() end)
        edit:SetScript('OnEnterPressed', function() copyFrame:Hide() end)
        edit:SetScript('OnEditFocusGained',function(self) self:HighlightText() end)
        edit:SetScript('OnMouseUp',function(self) self:SetFocus(); self:HighlightText() end)
        copyFrame:SetScript('OnHide',function() edit:ClearFocus() end)
        copyFrame.edit = edit
    end
    copyFrame:SetFrameStrata('FULLSCREEN_DIALOG')
    copyFrame:Show(); copyFrame.edit:SetText(name); copyFrame.edit:SetFocus(); copyFrame.edit:HighlightText()
    -- Dropdown cleanup may change focus after its action callback returns.
    if C_Timer and C_Timer.After then
        C_Timer.After(0,function()
            if copyFrame:IsShown() and copyFrame.edit:GetText()==name then
                copyFrame.edit:SetFocus(); copyFrame.edit:HighlightText()
            end
        end)
    end
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
        Action(T('Відкрити профіль'), function() if OpenMemberProfile then OpenMemberProfile(member) end end)
        Action(T('Запросити в групу'), function() OldKraken:InvitePlayer(member.name) end, not member.isOnline)
        Action(T('Шепнути'), function() ChatFrame_SendTell(member.name) end, not member.isOnline)
        Action(T("Скопіювати ім'я"), function() CopyName(member.name) end)
    end, 'MENU')
    ToggleDropDownMenu(1, nil, memberMenu, 'cursor', 0, 0)
    local list = _G and _G.DropDownList1
    if type(list) == 'table' and list:IsShown() then
        local num = list.numButtons or 0
        if num > 0 then
            local width = math.max(185, (list:GetWidth() or 150) + 26)
            list:SetWidth(width)
            for i = 1, num do
                local btn = _G['DropDownList1Button' .. i]
                if type(btn) == 'table' then
                    btn:SetHeight(i == 1 and 22 or 24)
                    btn:SetWidth(width - 20)
                    btn:ClearAllPoints()
                    btn:SetPoint('TOPLEFT', list, 'TOPLEFT', 10, -14 - (i == 1 and 0 or (22 + 4 + (i - 2) * 24)))
                    local nt = _G['DropDownList1Button' .. i .. 'NormalText']
                    if type(nt) == 'table' and OldKraken.UIStyle and OldKraken.UIStyle.Font then
                        OldKraken.UIStyle.Font(nt, 13, i == 1)
                    end
                end
            end
            list:SetHeight(14 + 22 + 4 + math.max(0, num - 1) * 24 + 14)
        end
    end
end

local ROSTER_DEFAULTS = { status = "all", sort = "level", ascending = true, class = "ALL", search = "" }

local function GetSettings()
    if not OldKraken.DB then
        return nil
    end

    if type(OldKraken.DB.settings) ~= "table" then
        OldKraken.DB.settings = {}
    end
    if type(OldKraken.DB.settings.roster) ~= "table" then
        OldKraken.DB.settings.roster = {}
    end
    local target = OldKraken.DB.settings.roster
    for key, value in pairs(ROSTER_DEFAULTS) do
        if target[key] == nil then
            target[key] = value
        end
    end
    if target.class == "" then
        target.class = "ALL"
    end
    if target.sort == "" then
        target.sort = "level"
    end
    settings = target
    return settings
end

local function SafeText(value, fallback)
    if value == nil or value == "" then
        return fallback or "-"
    end
    return tostring(value)
end

local function ClassLabel(classToken, fallbackName)
    if classToken == "ALL" then
        return T("Усі класи")
    end

    if type(classToken) == "string" and CLASS_NAMES[classToken] then
        return CLASS_NAMES[classToken]
    end

    if fallbackName ~= nil and fallbackName ~= "" then
        return tostring(fallbackName)
    end

    if classToken ~= nil and classToken ~= "" then
        return tostring(classToken)
    end

    return T("Усі класи")
end

local function UpdateFilterButtonLabels()
    if not rosterFrame then
        return
    end

    UIDropDownMenu_SetText(rosterFrame.statusDropdown, T("Статус: ") .. (STATUS_LABELS[settings.status] or T("усі")))
    UIDropDownMenu_SetText(
        rosterFrame.classDropdown,
        settings.class == "ALL" and T("Клас: усі") or (T("Клас: ") .. ClassLabel(settings.class))
    )
    UIDropDownMenu_SetText(rosterFrame.addonFilter, ADDON_LABELS[addonFilter] or ADDON_LABELS.all)
    if rosterFrame.searchHint then
        rosterFrame.searchHint:SetShown((settings.search or "") == "")
    end
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
        if not a.isOnline then
            local aa, bb = a.lastOnline, b.lastOnline
            if (aa ~= nil) ~= (bb ~= nil) then return aa ~= nil end
            if aa and bb then
                for _, unit in ipairs({'years', 'months', 'days', 'hours'}) do
                    if aa[unit] ~= bb[unit] then
                        if settings.ascending then return aa[unit] < bb[unit] end
                        return aa[unit] > bb[unit]
                    end
                end
            end
        end
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
    local colors = OldKraken.UIStyle.Colors or {}
    local muted = colors.mutedText or {0.63, 0.67, 0.73}
    local gold = colors.brandGold or {0.88, 0.69, 0.32, 1}
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, 32)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -123)
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", button, "LEFT", 0, 0)
    text:SetJustifyH("LEFT")
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(text, 12, false) end
    text:SetTextColor(muted[1], muted[2], muted[3])
    text:SetText(label)
    button.label = text
    button.sortKey = key
    if key then
        local arrow = CreateFrame("Frame", nil, button)
        arrow:SetSize(8, 6)
        arrow:SetPoint("LEFT", text, "RIGHT", 5, 0)
        arrow.bars = {}
        for idx = 1, 3 do
            local bar = arrow:CreateTexture(nil, "OVERLAY")
            bar:SetColorTexture(gold[1], gold[2], gold[3], 1)
            arrow.bars[idx] = bar
        end
        arrow:Hide()
        button.sortArrow = arrow
        button:SetScript("OnClick", function()
            if settings.sort == key then
                settings.ascending = not settings.ascending
            else
                settings.sort = key
                settings.ascending = true
            end
            Roster:Render()
        end)
    else
        button:EnableMouse(false)
    end
    if type(parent.columnHeaders) ~= 'table' then parent.columnHeaders = {} end
    parent.columnHeaders[#parent.columnHeaders + 1] = button
    return button
end

local function UpdateSortHeaders()
    if not rosterFrame or not rosterFrame.columnHeaders then return end
    local colors = OldKraken.UIStyle.Colors or {}
    local muted = colors.mutedText or {0.63, 0.67, 0.73}
    local gold = colors.brandGold or {0.88, 0.69, 0.32, 1}
    for _, btn in ipairs(rosterFrame.columnHeaders) do
        local active = btn.sortKey and btn.sortKey == settings.sort
        if btn.label then
            local c = active and gold or muted
            btn.label:SetTextColor(c[1], c[2], c[3])
        end
        if type(btn.sortArrow) == 'table' then
            btn.sortArrow:SetShown(active)
            if active then
                local widths = settings.ascending and {1, 3, 5} or {5, 3, 1}
                local offsets = {2, 0, -2}
                for idx = 1, 3 do
                    local bar = btn.sortArrow.bars[idx]
                    bar:SetSize(widths[idx], 1)
                    bar:ClearAllPoints()
                    bar:SetPoint("CENTER", btn.sortArrow, "CENTER", 0, offsets[idx])
                end
            end
        end
    end
end

local function CreateStatChip(parent, x, width)
    if OldKraken.UIStyle.Chip then
        local chip = OldKraken.UIStyle.Chip(parent, "", {width = width, height = 30, center = true, rounded = true})
        chip:SetPoint("TOPLEFT", parent, "TOPLEFT", x, 0)
        chip:EnableMouse(false)
        return chip
    end
    local chip = CreateFrame("Frame", nil, parent)
    chip:SetSize(width, 30)
    chip:SetPoint("TOPLEFT", parent, "TOPLEFT", x, 0)
    chip.label = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chip.label:SetPoint("CENTER", chip, "CENTER", 0, 0)
    function chip:SetLabel(value) self.label:SetText(value or "") end
    return chip
end

local function CreateRosterWindow(parent)
    if rosterFrame then
        return rosterFrame
    end
    if not GetSettings() then
        settings = { status = "all", sort = "level", ascending = true, class = "ALL", search = "" }
    end

    local frame
    if parent then
        frame = CreateFrame("Frame", "OldKrakenRosterFrame", parent)
    else
        frame = CreateFrame("Frame", "OldKrakenRosterFrame", UIParent, "BasicFrameTemplateWithInset")
    end
    if not parent then table.insert(UISpecialFrames, "OldKrakenRosterFrame") end
    frame:SetSize(900, 607)
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
    -- Filter bar panel (height 60) and table panel (height 485)
    OldKraken.UIStyle.Panel(frame, 0, -46, 900, 60)
    OldKraken.UIStyle.Panel(frame, 0, -122, 900, 485)
    frame:Hide()

    if OldKraken.BindGuildTitle then OldKraken.BindGuildTitle(frame, T('Реєстр гільдії')) end

    frame.shownChip = CreateStatChip(frame, 0, 94)
    frame.shownChip:ClearAllPoints()
    frame.shownChip:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -2)

    frame.onlineChip = CreateStatChip(frame, 0, 90)
    frame.onlineChip:ClearAllPoints()
    frame.onlineChip:SetPoint("TOPRIGHT", frame.shownChip, "TOPLEFT", -8, 0)

    frame.totalChip = CreateStatChip(frame, 0, 111)
    frame.totalChip:ClearAllPoints()
    frame.totalChip:SetPoint("TOPRIGHT", frame.onlineChip, "TOPLEFT", -8, 0)

    local searchBox = CreateFrame("EditBox", "OldKrakenRosterSearchBox", frame, "InputBoxTemplate")
    OldKraken.UIStyle.Input(searchBox, {rounded = true})
    searchBox:SetSize(248, 34)
    searchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 13, -59)
    searchBox:SetAutoFocus(false)
    searchBox:SetTextInsets(10, 10, 0, 0)
    searchBox:SetText(settings.search or "")
    local searchHint = searchBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    searchHint:SetPoint("LEFT", searchBox, "LEFT", 12, 0)
    searchHint:SetText(T("Пошук гравця за ім’ям"))
    local muted = OldKraken.UIStyle.Colors and OldKraken.UIStyle.Colors.mutedText
    if muted then searchHint:SetTextColor(muted[1], muted[2], muted[3]) end
    searchHint:SetShown((settings.search or "") == "")
    frame.searchHint = searchHint
    searchBox:SetScript("OnTextChanged", function(self)
        settings.search = self:GetText() or ""
        if frame.searchHint then frame.searchHint:SetShown(settings.search == "") end
        Roster:Render()
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame.searchBox = searchBox

    local statusDropdown = CreateFrame("Frame", "OldKrakenRosterStatusDropdown", frame, "UIDropDownMenuTemplate")
    OldKraken.UIStyle.Dropdown(statusDropdown, {rounded = true})
    statusDropdown:SetPoint("TOPLEFT", frame, "TOPLEFT", 271 - 16, -57)
    UIDropDownMenu_SetWidth(statusDropdown, 142)
    UIDropDownMenu_JustifyText(statusDropdown, "LEFT")
    UIDropDownMenu_Initialize(statusDropdown, function(_, level)
        for _, value in ipairs({"all", "online", "offline"}) do
            local status = value
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.value = T("Статус: ") .. STATUS_LABELS[status], status
            info.checked = settings.status == status
            info.func = function() settings.status = status; Roster:Render() end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    frame.statusDropdown = statusDropdown

    local classDropdown = CreateFrame("Frame", "OldKrakenClassDropdown", frame, "UIDropDownMenuTemplate")
    OldKraken.UIStyle.Dropdown(classDropdown, {rounded = true})
    classDropdown:SetPoint("TOPLEFT", frame, "TOPLEFT", 459 - 16, -57)
    UIDropDownMenu_SetWidth(classDropdown, 132)
    UIDropDownMenu_JustifyText(classDropdown, "LEFT")
    UIDropDownMenu_Initialize(classDropdown, function(_, level)
        local info = UIDropDownMenu_CreateInfo()
        info.text = T("Клас: усі")
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
    OldKraken.UIStyle.Dropdown(filter, {rounded = true})
    filter:SetPoint('TOPLEFT', frame, 'TOPLEFT', 637 - 16, -57)
    UIDropDownMenu_SetWidth(filter, 152)
    UIDropDownMenu_JustifyText(filter, 'LEFT')
    UIDropDownMenu_Initialize(filter, function(_, level)
        for _, entry in ipairs({{'all', ADDON_LABELS.all}, {'yes', ADDON_LABELS.yes}, {'unknown', ADDON_LABELS.unknown}}) do
            local value, label = entry[1], entry[2]
            local info = UIDropDownMenu_CreateInfo()
            info.text = label; info.checked = addonFilter == value
            info.func = function() addonFilter = value; UIDropDownMenu_SetText(filter, label); Roster:Render() end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(filter, ADDON_LABELS.all); frame.addonFilter = filter

    local resetButton = CreateFrame("Button", "OldKrakenRosterResetButton", frame, "UIPanelButtonTemplate")
    OldKraken.UIStyle.Button(resetButton, nil, {rounded = true})
    resetButton:SetSize(74, 34)
    resetButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 813, -59)
    resetButton:SetText(T("Скинути"))
    local gold = OldKraken.UIStyle.Colors and OldKraken.UIStyle.Colors.brandGold
    local resetLabel = resetButton:GetFontString()
    if resetLabel and gold then resetLabel:SetTextColor(gold[1], gold[2], gold[3]) end
    resetButton:SetScript("OnClick", function()
        settings.search = ""
        settings.status = "all"
        settings.class = "ALL"
        addonFilter = "all"
        searchBox:SetText("")
        if frame.searchHint then frame.searchHint:Show() end
        Roster:Render()
    end)
    frame.resetButton = resetButton

    local summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -582)
    summary:SetJustifyH("LEFT")
    if OldKraken.UIStyle.Colors and OldKraken.UIStyle.Colors.mutedText then
        local m = OldKraken.UIStyle.Colors.mutedText
        summary:SetTextColor(m[1], m[2], m[3])
    end
    frame.summaryText = summary
    frame.footerText = summary

    CreateColumnHeader(frame, T("ІМ'Я"), "name", 40, 190)
    CreateColumnHeader(frame, T("РАНГ"), "rank", 240, 70)
    CreateColumnHeader(frame, T("РІВ."), "level", 320, 44)
    CreateColumnHeader(frame, T("КЛАС"), "class", 374, 80)
    CreateColumnHeader(frame, T("ЛОКАЦІЯ"), "zone", 464, 200)
    CreateColumnHeader(frame, T("ПРОФЕСІЇ"), nil, 674, 70)
    frame.addonHeader = CreateColumnHeader(frame, T("АДДОН"), nil, 754, 130)

    local headerDivider = frame:CreateTexture(nil, "ARTWORK")
    headerDivider:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -155)
    headerDivider:SetSize(898, 1)
    local divColor = OldKraken.UIStyle.Colors and OldKraken.UIStyle.Colors.divider or {0.20, 0.23, 0.29, 0.85}
    headerDivider:SetColorTexture(unpack(divColor))

    local footerDivider = frame:CreateTexture(nil, "ARTWORK")
    footerDivider:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -572)
    footerDivider:SetSize(898, 1)
    footerDivider:SetColorTexture(unpack(divColor))

    local scroll = CreateFrame("ScrollFrame", "OldKrakenRosterScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -155)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 42)
    scroll:EnableMouseWheel(true)
    if scroll.SetClipsChildren then pcall(scroll.SetClipsChildren, scroll, true) end
    if OldKraken.UIStyle.ScrollBar then OldKraken.UIStyle.ScrollBar(scroll, {inside = true}) end

    local emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyText:SetPoint("CENTER", scroll, "CENTER", 0, 14)
    emptyText:SetText(T("За обраними фільтрами гравців не знайдено."))
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(emptyText, 13) end
    if OldKraken.UIStyle.Colors and OldKraken.UIStyle.Colors.mutedText then
        local m = OldKraken.UIStyle.Colors.mutedText
        emptyText:SetTextColor(m[1], m[2], m[3])
    end
    emptyText:Hide()
    frame.emptyText = emptyText

    local emptyReset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    OldKraken.UIStyle.Button(emptyReset, nil, {rounded = true})
    emptyReset:SetSize(140, 32)
    emptyReset:SetPoint("TOP", emptyText, "BOTTOM", 0, -12)
    emptyReset:SetText(T("Скинути фільтри"))
    emptyReset:SetScript("OnClick", function()
        if resetButton and resetButton.GetScript then
            local onClick = resetButton:GetScript("OnClick")
            if onClick then onClick() end
        end
    end)
    emptyReset:Hide()
    frame.emptyReset = emptyReset

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_WIDTH, 1)
    scroll:SetScrollChild(content)

    scroll:SetScript("OnMouseWheel", function(self, delta)
        if OldKraken.UIHub and OldKraken.UIHub.HandleScaleWheel and OldKraken.UIHub:HandleScaleWheel(delta) then return end
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
    local function createProfilePanel(parent)
        local colors = OldKraken.UIStyle.Colors or {}
        local panel = CreateFrame('Frame', nil, parent)
        panel:SetPoint('TOPLEFT', parent, 'TOPLEFT', 0, -48)
        panel:SetPoint('BOTTOMRIGHT', parent, 'BOTTOMRIGHT', 0, 0)
        panel:SetFrameLevel((type(parent.GetFrameLevel) == 'function' and parent:GetFrameLevel() or 1) + 12)
        panel:EnableMouse(true)
        local bg = panel:CreateTexture(nil, 'BACKGROUND')
        bg:SetAllPoints(panel)
        local winCol = colors.window or {0.025, 0.035, 0.055, 1}
        bg:SetColorTexture(winCol[1], winCol[2], winCol[3], 1)

        local backBtn = CreateFrame('Button', nil, panel, 'UIPanelButtonTemplate')
        OldKraken.UIStyle.Button(backBtn, nil, {rounded = true})
        backBtn:SetSize(172, 30)
        backBtn:SetPoint('TOPLEFT', panel, 'TOPLEFT', 14, -10)
        backBtn:SetText(T('‹ Назад до ростера'))
        backBtn:SetScript('OnClick', function() if CloseMemberProfile then CloseMemberProfile() end end)
        panel.backButton = backBtn

        if OldKraken.UIStyle.Panel then
            OldKraken.UIStyle.Panel(panel, 14, -50, 872, 108)
            OldKraken.UIStyle.Panel(panel, 14, -172, 426, 138)
            OldKraken.UIStyle.Panel(panel, 460, -172, 426, 138)
            OldKraken.UIStyle.Panel(panel, 14, -324, 872, 74)
        end

        local nameText = panel:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
        nameText:SetPoint('TOPLEFT', panel, 'TOPLEFT', 32, -66)
        if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(nameText, 19, true) end
        panel.nameText = nameText

        local metaText = panel:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
        metaText:SetPoint('TOPLEFT', panel, 'TOPLEFT', 32, -96)
        if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(metaText, 13) end
        panel.metaText = metaText

        local statusDot = panel:CreateTexture(nil, 'OVERLAY')
        statusDot:SetSize(10, 10)
        statusDot:SetPoint('TOPLEFT', panel, 'TOPLEFT', 32, -126)
        panel.statusDot = statusDot

        local statusText = panel:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
        statusText:SetPoint('LEFT', statusDot, 'RIGHT', 8, 0)
        if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(statusText, 13) end
        panel.statusText = statusText

        local addonText = panel:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        addonText:SetPoint('TOPRIGHT', panel, 'TOPRIGHT', -32, -72)
        addonText:SetJustifyH('RIGHT')
        if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(addonText, 12) end
        panel.addonText = addonText

        local specTitle = panel:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
        specTitle:SetPoint('TOPLEFT', panel, 'TOPLEFT', 32, -188)
        specTitle:SetText(T('Спеціалізація'))
        if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(specTitle, 14, true) end
        if colors.brandGold then specTitle:SetTextColor(colors.brandGold[1], colors.brandGold[2], colors.brandGold[3]) end

        local specIcon = panel:CreateTexture(nil, 'OVERLAY')
        specIcon:SetSize(36, 36)
        specIcon:SetPoint('TOPLEFT', panel, 'TOPLEFT', 32, -222)
        panel.specIcon = specIcon

        local specName = panel:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
        specName:SetPoint('TOPLEFT', panel, 'TOPLEFT', 78, -222)
        specName:SetWidth(344)
        specName:SetJustifyH('LEFT')
        if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(specName, 14, true) end
        panel.specName = specName

        local specPoints = panel:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        specPoints:SetPoint('TOPLEFT', panel, 'TOPLEFT', 78, -244)
        if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(specPoints, 13) end
        if colors.mutedText then specPoints:SetTextColor(colors.mutedText[1], colors.mutedText[2], colors.mutedText[3]) end
        panel.specPoints = specPoints

        local profTitle = panel:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
        profTitle:SetPoint('TOPLEFT', panel, 'TOPLEFT', 478, -188)
        profTitle:SetText(T('Професії'))
        if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(profTitle, 14, true) end
        if colors.brandGold then profTitle:SetTextColor(colors.brandGold[1], colors.brandGold[2], colors.brandGold[3]) end

        local profEmpty = panel:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        profEmpty:SetPoint('TOPLEFT', panel, 'TOPLEFT', 478, -222)
        profEmpty:SetWidth(390)
        profEmpty:SetJustifyH('LEFT')
        if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(profEmpty, 13) end
        if colors.mutedText then profEmpty:SetTextColor(colors.mutedText[1], colors.mutedText[2], colors.mutedText[3]) end
        panel.profEmpty = profEmpty

        panel.profRows = {}
        local rowHoverCol = colors.actionBlue or {0.24, 0.38, 0.75, 0.24}
        for i = 1, 2 do
            local prow = CreateFrame('Button', nil, panel)
            prow:SetSize(390, 32)
            prow:SetPoint('TOPLEFT', panel, 'TOPLEFT', 478, -218 - (i - 1) * 38)
            local phighlight = prow:CreateTexture(nil, 'HIGHLIGHT')
            phighlight:SetAllPoints(prow)
            phighlight:SetColorTexture(rowHoverCol[1], rowHoverCol[2], rowHoverCol[3], 0.16)
            prow:SetHighlightTexture(phighlight)
            prow.icon = prow:CreateTexture(nil, 'ARTWORK')
            prow.icon:SetSize(24, 24)
            prow.icon:SetPoint('LEFT', prow, 'LEFT', 2, 0)
            prow.text = prow:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
            prow.text:SetPoint('LEFT', prow.icon, 'RIGHT', 10, 0)
            prow.text:SetWidth(190)
            prow.text:SetJustifyH('LEFT')
            if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(prow.text, 13) end
            prow.value = prow:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
            prow.value:SetPoint('RIGHT', prow, 'RIGHT', -4, 0)
            prow.value:SetWidth(160)
            prow.value:SetJustifyH('RIGHT')
            if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(prow.value, 13) end
            if colors.mutedText then prow.value:SetTextColor(colors.mutedText[1], colors.mutedText[2], colors.mutedText[3]) end
            prow:SetScript('OnClick', function(self)
                if self.memberName and self.professionID and OldKraken.WorkshopRecipes then
                    local targetMember = panel.member
                    OldKraken.WorkshopRecipes:ShowMemberProfession(self.memberName, self.professionID, function()
                        Roster:Show()
                        if targetMember and OpenMemberProfile then OpenMemberProfile(targetMember) end
                    end)
                end
            end)
            prow:Hide()
            panel.profRows[i] = prow
        end

        local function makeActionBtn(label, x, width, variant, onClick)
            local b = CreateFrame('Button', nil, panel, 'UIPanelButtonTemplate')
            OldKraken.UIStyle.Button(b, variant, {rounded = true})
            b:SetSize(width, 34)
            b:SetPoint('TOPLEFT', panel, 'TOPLEFT', x, -344)
            b:SetText(label)
            b:SetScript('OnClick', onClick)
            return b
        end
        panel.whisperButton = makeActionBtn(T('Шепнути'), 32, 130, nil, function()
            if panel.member and panel.member.isOnline and not isSelfMember(panel.member.name) and type(ChatFrame_SendTell) == 'function' then
                ChatFrame_SendTell(panel.member.name)
            end
        end)
        panel.inviteButton = makeActionBtn(T('Запросити в групу'), 172, 168, nil, function()
            if panel.member and panel.member.isOnline and not isSelfMember(panel.member.name) and OldKraken.InvitePlayer then
                OldKraken:InvitePlayer(panel.member.name)
            end
        end)
        panel.recipesButton = makeActionBtn(T('Переглянути рецепти'), 350, 180, 'primary', function()
            if panel.member and panel.firstCraftProfessionID and OldKraken.WorkshopRecipes then
                local targetMember = panel.member
                OldKraken.WorkshopRecipes:ShowMemberProfession(panel.member.name, panel.firstCraftProfessionID, function()
                    Roster:Show()
                    if targetMember and OpenMemberProfile then OpenMemberProfile(targetMember) end
                end)
            end
        end)
        panel.orderButton = makeActionBtn(T('Створити замовлення'), 540, 180, nil, function()
            if OldKraken.WorkshopOrders then
                local targetMember = panel.member
                local preferredProf = panel.firstCraftProfessionID
                OldKraken.WorkshopOrders:Show()
                if type(OldKraken.WorkshopOrders.OpenCreateForm) == 'function' then
                    OldKraken.WorkshopOrders:OpenCreateForm(preferredProf, function()
                        Roster:Show()
                        if targetMember and OpenMemberProfile then OpenMemberProfile(targetMember) end
                    end)
                end
            end
        end)
        panel.copyButton = makeActionBtn(T("Скопіювати ім'я"), 730, 140, nil, function()
            if panel.member then CopyName(panel.member.name) end
        end)

        panel:Hide()
        return panel
    end

    frame.profilePanel = createProfilePanel(frame)
    frame:SetScript('OnShow', function() Roster:ScheduleRefresh(true) end)
    frame.scrollFrame = scroll
    frame.contentFrame = content
    rosterFrame = frame

    UpdateFilterButtonLabels()
    return frame
end

local function setButtonEnabled(btn, enabled)
    if not btn then return end
    if enabled then
        if type(btn.Enable) == 'function' then btn:Enable() end
        if type(btn.SetAlpha) == 'function' then btn:SetAlpha(1) end
    else
        if type(btn.Disable) == 'function' then btn:Disable() end
        if type(btn.SetAlpha) == 'function' then btn:SetAlpha(0.45) end
    end
end

local function formatOfflineDuration(duration)
    if not duration then return nil end
    local parts = {}
    for _, unit in ipairs({{'years', 'р'}, {'months', 'міс'}, {'days', 'д'}, {'hours', 'год'}}) do
        local value = duration[unit[1]]
        if value > 0 then
            parts[#parts + 1] = tostring(value) .. ' ' .. T(unit[2])
            if #parts == 2 then break end
        end
    end
    return #parts > 0 and table.concat(parts, ' ') or T('< 1 год')
end

RenderMemberProfile = function(member)
    if not rosterFrame or not rosterFrame.profilePanel or not member then return end
    local panel = rosterFrame.profilePanel
    panel.member = member
    local colors = OldKraken.UIStyle.Colors or {}
    local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.classFile]
    panel.nameText:SetText(member.name or '')
    if classColor then
        panel.nameText:SetTextColor(classColor.r, classColor.g, classColor.b)
    elseif colors.text then
        panel.nameText:SetTextColor(colors.text[1], colors.text[2], colors.text[3])
    end

    local levelPart = string.format(T('Рівень %d'), tonumber(member.level) or 0)
    local classPart = CLASS_NAMES[member.classFile] or member.class or member.classFile or ''
    local rankPart = (type(member.rank) == 'string' and member.rank ~= '') and member.rank or '—'
    panel.metaText:SetText(levelPart .. ' · ' .. classPart .. ' · ' .. rankPart)

    if member.isOnline then
        panel.statusDot:SetTexture('Interface\\AddOns\\OldKraken\\Media\\StatusOnline.tga')
        local zonePart = (type(member.zone) == 'string' and member.zone ~= '') and (' · ' .. member.zone) or ''
        panel.statusText:SetText('|cff69dc8c' .. T('В мережі') .. '|r' .. zonePart)
    else
        panel.statusDot:SetTexture('Interface\\AddOns\\OldKraken\\Media\\StatusOffline.tga')
        local ago = formatOfflineDuration(member.lastOnline)
        panel.statusText:SetText('|cff9aa5b1' .. T('Офлайн') .. (ago and (' · ' .. ago) or '') .. '|r')
    end

    local comm = OldKraken.Communication
    local version = comm and comm.GetRosterVersion and comm:GetRosterVersion(member.name)
    if version then
        panel.addonText:SetText(T('Аддон: ') .. version)
    elseif HasAddon(member.name) then
        panel.addonText:SetText(T('Аддон: ') .. T('активний'))
    else
        panel.addonText:SetText(T('Аддон: ') .. T('Не виявлено'))
    end

    local selfMember = isSelfMember(member.name)
    local spec = comm and comm.GetRosterSpec and comm:GetRosterSpec(member.name)
    if type(spec) == 'table' and spec.icon and type(spec.name) == 'string' and spec.name ~= '' then
        local specLabel = OldKraken.LocalizeSpecName and OldKraken.LocalizeSpecName(spec.name) or spec.name
        panel.specIcon:SetTexture(spec.icon)
        panel.specIcon:Show()
        if type(panel.specName.ClearAllPoints) == 'function' then
            panel.specName:ClearAllPoints()
            panel.specName:SetPoint('TOPLEFT', panel, 'TOPLEFT', 78, -222)
        end
        if type(panel.specPoints.ClearAllPoints) == 'function' then
            panel.specPoints:ClearAllPoints()
            panel.specPoints:SetPoint('TOPLEFT', panel, 'TOPLEFT', 78, -244)
        end
        panel.specName:SetText(specLabel)
        panel.specPoints:SetText(type(spec.points) == 'string' and spec.points ~= '' and (T('Розподіл очок: ') .. spec.points) or '')
    else
        panel.specIcon:SetTexture(nil)
        panel.specIcon:Hide()
        if type(panel.specName.ClearAllPoints) == 'function' then
            panel.specName:ClearAllPoints()
            panel.specName:SetPoint('TOPLEFT', panel, 'TOPLEFT', 32, -222)
        end
        if type(panel.specPoints.ClearAllPoints) == 'function' then
            panel.specPoints:ClearAllPoints()
            panel.specPoints:SetPoint('TOPLEFT', panel, 'TOPLEFT', 32, -244)
        end
        panel.specName:SetText(T('Дані спеціалізації відсутні.'))
        panel.specPoints:SetText(selfMember and T('Відкрийте таланти (N), щоб оновити спек.') or T('Гравець ще не оновив таланти з аддоном.'))
    end

    local firstCraftID = nil
    local workshopReady = isWorkshopAvailable()
    local professions = workshopReady and OldKraken.Workshop:GetMemberProfessions(member.name) or {}
    for _, prow in ipairs(panel.profRows) do prow:Hide() end
    if not workshopReady then
        panel.profEmpty:SetText(T('Дані про професії недоступні.'))
        panel.profEmpty:Show()
    elseif #professions == 0 then
        panel.profEmpty:SetText(T('Професії ще не зафіксовані.'))
        panel.profEmpty:Show()
    else
        panel.profEmpty:Hide()
        for i = 1, math.min(2, #professions) do
            local p = professions[i]
            local prow = panel.profRows[i]
            local pname, picon = OldKraken.Workshop:ProfessionInfo(p.id)
            if not firstCraftID then firstCraftID = p.id end
            prow.memberName = member.name
            prow.professionID = p.id
            prow.icon:SetTexture(picon or 134400)
            local detail = p.native and T('Із ігрового ростера') or (p.rank and (tostring(p.rank) .. '/' .. tostring(p.maximum or '?')) or '')
            prow.text:SetText(pname)
            if prow.value then prow.value:SetText(detail) end
            prow:Show()
        end
    end
    panel.firstCraftProfessionID = firstCraftID

    setButtonEnabled(panel.whisperButton, member.isOnline and not selfMember)
    setButtonEnabled(panel.inviteButton, member.isOnline and not selfMember)
    setButtonEnabled(panel.recipesButton, firstCraftID ~= nil and OldKraken.WorkshopRecipes ~= nil)
    setButtonEnabled(panel.orderButton, not selfMember and OldKraken.WorkshopOrders ~= nil)
    setButtonEnabled(panel.copyButton, true)
    if type(panel.whisperButton.SetShown) == 'function' then panel.whisperButton:SetShown(not selfMember) end
    if type(panel.inviteButton.SetShown) == 'function' then panel.inviteButton:SetShown(not selfMember) end
    if type(panel.orderButton.SetShown) == 'function' then panel.orderButton:SetShown(not selfMember) end
    if type(panel.recipesButton.ClearAllPoints) == 'function' then
        panel.recipesButton:ClearAllPoints()
        panel.recipesButton:SetPoint('TOPLEFT', panel, 'TOPLEFT', selfMember and 32 or 350, -344)
    end
    if type(panel.copyButton.ClearAllPoints) == 'function' then
        panel.copyButton:ClearAllPoints()
        panel.copyButton:SetPoint('TOPLEFT', panel, 'TOPLEFT', selfMember and 222 or 730, -344)
    end
end

OpenMemberProfile = function(member)
    if not member or not rosterFrame or not rosterFrame.profilePanel then return end
    if not selectedProfileName and rosterFrame.scrollFrame and type(rosterFrame.scrollFrame.GetVerticalScroll) == 'function' then
        savedScrollOffset = tonumber((rosterFrame.scrollFrame:GetVerticalScroll())) or 0
    end
    selectedProfileName = member.name
    if rosterFrame.scrollFrame then rosterFrame.scrollFrame:Hide() end
    if rosterFrame.emptyText then rosterFrame.emptyText:Hide() end
    if rosterFrame.emptyReset then rosterFrame.emptyReset:Hide() end
    if rosterFrame.totalChip and type(rosterFrame.totalChip.Hide) == 'function' then rosterFrame.totalChip:Hide() end
    if rosterFrame.onlineChip and type(rosterFrame.onlineChip.Hide) == 'function' then rosterFrame.onlineChip:Hide() end
    if rosterFrame.shownChip and type(rosterFrame.shownChip.Hide) == 'function' then rosterFrame.shownChip:Hide() end
    RenderMemberProfile(member)
    rosterFrame.profilePanel:Show()
end

CloseMemberProfile = function()
    selectedProfileName = nil
    if not rosterFrame then return end
    if rosterFrame.profilePanel then rosterFrame.profilePanel:Hide() end
    if rosterFrame.totalChip and type(rosterFrame.totalChip.Show) == 'function' then rosterFrame.totalChip:Show() end
    if rosterFrame.onlineChip and type(rosterFrame.onlineChip.Show) == 'function' then rosterFrame.onlineChip:Show() end
    if rosterFrame.shownChip and type(rosterFrame.shownChip.Show) == 'function' then rosterFrame.shownChip:Show() end
    if rosterFrame.scrollFrame then
        rosterFrame.scrollFrame:Show()
        if type(rosterFrame.scrollFrame.SetVerticalScroll) == 'function' then
            rosterFrame.scrollFrame:SetVerticalScroll(savedScrollOffset or 0)
        end
    end
    Roster:Render()
end

local function HandleRowClick(row, mouseButton)
    if not row or not row.member then return end
    if mouseButton == 'LeftButton' then
        if OpenMemberProfile then OpenMemberProfile(row.member) end
    else
        ShowMemberMenu(row)
    end
end

local function CreateRow(index, parent)
    local row = CreateFrame("Button", nil, parent)
    row:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
    row:SetScript('OnClick', HandleRowClick)
    row:SetSize(CONTENT_WIDTH, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
    local zebra = OldKraken.UIStyle.Colors and OldKraken.UIStyle.Colors.zebra or {1, 1, 1, 0.035}
    local stripe = row:CreateTexture(nil, "BACKGROUND")
    stripe:SetAllPoints(row)
    stripe:SetColorTexture(unpack(zebra))
    stripe:SetShown(index % 2 == 0)
    row.stripe = stripe
    local hoverColor = OldKraken.UIStyle.Colors and OldKraken.UIStyle.Colors.actionBlue or {0.24, 0.38, 0.75, 0.24}
    local rowHighlight = row:CreateTexture(nil, "HIGHLIGHT")
    rowHighlight:SetAllPoints(row)
    rowHighlight:SetColorTexture(hoverColor[1], hoverColor[2], hoverColor[3], 0.16)
    row:SetHighlightTexture(rowHighlight)

    local columns = {
        { x = 40, width = 190 },
        { x = 240, width = 70 },
        { x = 320, width = 44 },
        { x = 374, width = 80 },
        { x = 464, width = 200 },
        { x = 674, width = 70 },
        { x = 766, width = 104 },
    }

    row.cells = {}
    for cellIndex, column in ipairs(columns) do
        local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        cell:SetPoint("LEFT", row, "LEFT", column.x, 0)
        cell:SetWidth(column.width)
        cell:SetHeight(ROW_HEIGHT)
        cell:SetJustifyH("LEFT")
        cell:SetWordWrap(false)
        if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(cell, 13, column.bold) end
        row.cells[cellIndex] = cell
    end
    row.onlineDot = row:CreateTexture(nil, 'OVERLAY')
    row.specIcon = row:CreateTexture(nil, 'OVERLAY')
    row.specIcon:SetSize(14, 14); row.specIcon:SetPoint('LEFT', row, 'LEFT', 374, 0); row.specIcon:Hide()
    row.onlineDot:SetPoint('LEFT', row, 'LEFT', 14, 0)
    row.onlineDot:SetWidth(8)
    row.onlineDot:SetHeight(8)
    row.addonDot = row:CreateTexture(nil, 'OVERLAY')
    row.addonDot:SetSize(8, 8); row.addonDot:SetPoint('LEFT', row, 'LEFT', 754, 0)
    if OldKraken.UIStyle.PillBadge then
        row.versionBadge = OldKraken.UIStyle.PillBadge(row, '', 'neutral', {
            width = 90, height = 19, fontSize = 11, rounded = true,
            customColors = {success = {0.349, 0.902, 0.502, 1}}
        })
        row.versionBadge:SetPoint('LEFT', row, 'LEFT', 754, 0)
        row.versionBadge:Hide()
    end
    row.cellHovers = {}
    for _, cellIndex in ipairs({1, 2, 4, 5, 7}) do
        local hover = CreateFrame('Button', nil, row)
        hover:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
        hover:SetScript('OnClick', function(_, mouseButton) HandleRowClick(row, mouseButton) end)
        if cellIndex == 4 then hover:ClearAllPoints(); hover:SetPoint('LEFT', row, 'LEFT', 374, 0); hover:SetSize(80, ROW_HEIGHT)
        else hover:SetAllPoints(row.cells[cellIndex]) end
        hover:EnableMouse(true)
        hover:SetScript('OnEnter', function(self)
            if GameTooltip and self.fullText and self.fullText ~= '' then
                GameTooltip:SetOwner(self, 'ANCHOR_RIGHT'); GameTooltip:SetText(self.fullText); GameTooltip:Show()
            end
        end)
        hover:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
        row.cellHovers[cellIndex] = hover
    end

    row.professions = {}
    for i=1,2 do
        local icon=CreateFrame('Button',nil,row)
        icon:SetSize(20,20); icon:SetPoint('LEFT',row,'LEFT',674+(i-1)*24,0)
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
            if self.native then GameTooltip:AddLine(T('Професія з ігрового ростера; рівень і рецепти невідомі.'),1,1,1,true)
            elseif self.rank then
                GameTooltip:AddLine(T('Рівень: ')..tostring(self.rank)..'/'..tostring(self.maximum or '?'),1,1,1)
                if self.relayed then GameTooltip:AddLine(T('Отримано через гільдію'),1,1,1) end
                if type(self.updated)=='number' and type(GetServerTime)=='function' and GetServerTime()-self.updated>604800 then GameTooltip:AddLine(T('Дані застарілі'),1,0.7,0.25) end
            end
            if not isGathering(self.professionID) then
                GameTooltip:AddLine(T('Натисніть, щоб переглянути збережені рецепти.'),0.6,0.9,1,true)
            end
            GameTooltip:Show()
        end)
        icon:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
        icon:Hide(); row.professions[i]=icon
    end

    rowFrames[index] = row
    return row
end

local function ActiveFilterDescription()
    local parts = {}
    if (settings.search or "") ~= "" then
        parts[#parts + 1] = T("пошук: ") .. settings.search
    end
    if settings.status and settings.status ~= "all" then
        parts[#parts + 1] = STATUS_LABELS[settings.status] or settings.status
    end
    if settings.class and settings.class ~= "ALL" then
        parts[#parts + 1] = ClassLabel(settings.class)
    end
    if addonFilter == "yes" then
        parts[#parts + 1] = T("аддон: є")
    elseif addonFilter == "unknown" then
        parts[#parts + 1] = T("аддон: не виявлено")
    end
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, ", ")
end

local function UpdateSummary()
    local total = #rosterData
    local online = 0
    for _, member in ipairs(rosterData) do
        if member.isOnline then
            online = online + 1
        end
    end

    if rosterFrame.totalChip then
        rosterFrame.totalChip:SetLabel(string.format(T("Учасників %d"), total))
    end
    if rosterFrame.onlineChip then
        rosterFrame.onlineChip:SetLabel(string.format(T("Онлайн |cff69dc8c%d|r"), online))
    end
    if rosterFrame.shownChip then
        rosterFrame.shownChip:SetLabel(string.format(T("Показано %d"), #filteredData))
    end

    local activeFilter = ActiveFilterDescription()
    if activeFilter then
        rosterFrame.summaryText:SetText(string.format(
            T("Показано %d з %d · фільтр «%s» увімкнено"),
            #filteredData, total, activeFilter
        ))
    else
        rosterFrame.summaryText:SetText(string.format(
            T("Показано %d з %d"),
            #filteredData, total
        ))
    end
end

local function runRender(self)
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
    UpdateSortHeaders()

    if selectedProfileName then
        local found
        for _, member in ipairs(rosterData) do
            if member.name == selectedProfileName then
                found = member
                break
            end
        end
        if found then
            RenderMemberProfile(found)
            return
        end
        CloseMemberProfile()
        return
    end

    self:RenderVisible()
end

function Roster:Render()
    local t0 = OldKraken and OldKraken.perfEnabled and type(debugprofilestop) == 'function' and debugprofilestop() or nil
    runRender(self)
    if t0 and OldKraken.PerfRecord then OldKraken:PerfRecord('roster.render', debugprofilestop() - t0) end
end

function Roster:RenderVisible()
    if not rosterFrame or drawing then return end
    drawing = true
    local content = rosterFrame.contentFrame
    local scroll = rosterFrame.scrollFrame
    local viewport = tonumber((scroll:GetHeight())) or 440
    if viewport <= 0 then viewport = 440 end
    local fullHeight = #filteredData * ROW_HEIGHT
    content:SetHeight(math.max(1, fullHeight))
    local scrollBar = _G.OldKrakenRosterScrollFrameScrollBar
    if type(scrollBar) == 'table' and scrollBar.SetShown then
        scrollBar:SetShown(fullHeight > viewport)
    end
    if rosterFrame.emptyText then rosterFrame.emptyText:SetShown(#filteredData == 0) end
    if rosterFrame.emptyReset then rosterFrame.emptyReset:SetShown(#filteredData == 0) end
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
        if row.stripe then row.stripe:SetShown(dataIndex % 2 == 0) end
        row.member = member
        local cells = row.cells
        row.specIcon:SetTexture(nil); row.specIcon:Hide()
        local spec = comm and comm.GetRosterSpec and comm:GetRosterSpec(member.name)
        cells[4]:ClearAllPoints()
        if spec and spec.icon then
            row.specIcon:SetTexture(spec.icon); row.specIcon:Show()
            cells[4]:SetPoint('LEFT', row, 'LEFT', 392, 0); cells[4]:SetWidth(62)
        else
            cells[4]:SetPoint('LEFT', row, 'LEFT', 374, 0); cells[4]:SetWidth(80)
        end

        cells[7]:Show()
        row.cellHovers[7]:Show()

        if HasAddon(member.name) then
            cells[7]:SetTextColor(0.25, 1, 0.25)
        else
            local muted = OldKraken.UIStyle.Colors and OldKraken.UIStyle.Colors.mutedText or {0.63, 0.67, 0.73}
            cells[7]:SetTextColor(muted[1], muted[2], muted[3])
        end
        local version = comm and comm.GetRosterVersion and comm:GetRosterVersion(member.name)
        local comparison = version and comm.CompareVersions and comm:CompareVersions(version, localVersion)
        row.addonDot:SetTexture(HasAddon(member.name) and 'Interface\\AddOns\\OldKraken\\Media\\StatusOnline.tga' or 'Interface\\AddOns\\OldKraken\\Media\\StatusOffline.tga')
        local badgeKind = 'neutral'
        local versionStatus = T('Версію не передано; оновіть аддон учасника та натисніть «Оновити».')
        if comparison == -1 then
            cells[7]:SetTextColor(1, 0.55, 0.15); versionStatus = T('Застаріла: версія старіша за вашу.'); badgeKind = 'warning'
        elseif comparison == 1 then
            cells[7]:SetTextColor(0.3, 0.8, 1); versionStatus = T('Новіша за вашу версію.'); badgeKind = 'info'
        elseif comparison == 0 and version:match('%+g%x+$') and localVersion and localVersion:match('%+g%x+$') and version~=localVersion then
            cells[7]:SetTextColor(1, 0.76, 0.42); versionStatus = T('Однакова версія, але різні Git-збірки.'); badgeKind = 'warning'
        elseif comparison == 0 and localVersion and version~=localVersion and ((version:match('%+g%x+$') and not localVersion:match('%+g%x+$')) or (localVersion:match('%+g%x+$') and not version:match('%+g%x+$'))) then
            cells[7]:SetTextColor(0.7, 0.7, 0.7); versionStatus = T('Неможливо порівняти Git-збірки: в однієї немає ідентифікатора.'); badgeKind = 'neutral'
        elseif comparison == 0 then
            cells[7]:SetTextColor(0.25, 1, 0.25); versionStatus = T('Така сама версія, як у вас.'); badgeKind = 'success'
        elseif version then
            cells[7]:SetTextColor(0.7, 0.7, 0.7)
            versionStatus = T('Не вдалося порівняти номер версії.')
        end
        cells[7]:SetText(version or '—')
        if row.versionBadge then
            if version then
                row.addonDot:Hide()
                row.versionBadge:SetKind(badgeKind)
                row.versionBadge:Show()
                cells[7]:ClearAllPoints()
                cells[7]:SetPoint('CENTER', row.versionBadge, 'CENTER', 0, 0)
                cells[7]:SetWidth(84)
                cells[7]:SetJustifyH('CENTER')
                if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(cells[7], 11, false) end
            else
                row.addonDot:Hide()
                row.versionBadge:Hide()
                cells[7]:ClearAllPoints()
                cells[7]:SetPoint('LEFT', row, 'LEFT', 768, 0)
                cells[7]:SetWidth(84)
                cells[7]:SetJustifyH('LEFT')
                if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(cells[7], 13, false) end
            end
        end
        row.cellHovers[7].fullText = (version or T('Невідомо')) .. '\n' .. versionStatus
        cells[1]:SetText(SafeText(member.name))
        cells[2]:SetText(SafeText(member.rank))
        cells[3]:SetText(SafeText(member.level))
        local hasClass = (member.classFile ~= nil and member.classFile ~= "") or (member.class ~= nil and member.class ~= "")
        local classText = hasClass and ClassLabel(member.classFile, member.class) or "-"
        cells[4]:SetText(classText)
        local offlineText = not member.isOnline and formatOfflineDuration(member.lastOnline)
        local zoneText = SafeText(member.zone)
        local locationText = offlineText and (T('Офлайн') .. ' · ' .. offlineText) or zoneText
        cells[5]:SetText(locationText)
        row.onlineDot:SetTexture(member.isOnline and 'Interface\\AddOns\\OldKraken\\Media\\StatusOnline.tga' or 'Interface\\AddOns\\OldKraken\\Media\\StatusOffline.tga')
        row.cellHovers[1].fullText = SafeText(member.name)
        row.cellHovers[2].fullText = SafeText(member.rank)
        row.cellHovers[4].fullText = classText
        if spec and spec.name then row.cellHovers[4].fullText = row.cellHovers[4].fullText .. '\n' .. (OldKraken.LocalizeSpecName and OldKraken.LocalizeSpecName(spec.name) or spec.name) end
        row.cellHovers[5].fullText = offlineText and (T('Офлайн') .. ': ' .. offlineText .. (zoneText ~= '' and ('\n' .. zoneText) or '')) or zoneText

        local classColor = member.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.classFile]
        if classColor then
            cells[1]:SetTextColor(classColor.r, classColor.g, classColor.b)
            cells[4]:SetTextColor(classColor.r, classColor.g, classColor.b)
        else
            cells[1]:SetTextColor(1, 1, 1)
            cells[4]:SetTextColor(1, 1, 1)
        end

        row:Show()
        if row.versionBadge then
            if version then
                row.versionBadge:Show()
            else
                row.versionBadge:Hide()
            end
        end
        local professions=OldKraken.Workshop and OldKraken.Workshop:GetMemberProfessions(member.name) or {}
        if #professions==0 then
            local muted = OldKraken.UIStyle.Colors and OldKraken.UIStyle.Colors.mutedText
            cells[6]:SetText('—')
            if muted then cells[6]:SetTextColor(muted[1], muted[2], muted[3]) else cells[6]:SetTextColor(0.55, 0.55, 0.55) end
            cells[6]:Show()
        else
            cells[6]:Hide()
        end
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

local function Pack(...) return {n = select('#', ...), ...} end

function Roster:Load()
    local t0 = OldKraken and OldKraken.perfEnabled and type(debugprofilestop) == 'function' and debugprofilestop() or nil
    pendingLoad, pendingRender = false, false
    if OldKraken.Workshop then OldKraken.Workshop:RefreshNativeProfessions() end
    local total = GetNumGuildMembers()
    total = tonumber(total) or 0

    rosterData = {}

    for index = 1, total do
        local name, rankName, rankIndex, level, className, zone,
            publicNote, officerNote, isOnline, status, classFileName = GetGuildRosterInfo(index)

        if name then
            local lastOnline
            if not isOnline and type(GetGuildRosterLastOnline) == 'function' then
                local values = Pack(pcall(GetGuildRosterLastOnline, index))
                if values[1] then
                    local n = values.n - 1
                    local first = values[2]
                    if n == 1 and not (type(issecretvalue) == 'function' and issecretvalue(first)) and type(first) == 'number' and first == 0 then
                        values = {n = 5, true, 0, 0, 0, 0}
                        n = 4
                    end
                    local valid = n == 4
                    for i = 2, 5 do
                        local value = values[i]
                        if (type(issecretvalue) == 'function' and issecretvalue(value)) or type(value) ~= 'number' or value < 0 or math.floor(value) ~= value then valid = false; break end
                    end
                    if valid then lastOnline = {years = values[2], months = values[3], days = values[4], hours = values[5]} end
                end
            end
            rosterData[#rosterData + 1] = {
                name = name,
                rank = rankName,
                rankIndex = tonumber(rankIndex) or 0,
                level = tonumber(level) or 0,
                class = className or classFileName,
                classFile = classFileName,
                zone = zone,
                isOnline = isOnline == true,
                lastOnline = lastOnline,
            }
        end
    end

    self:Render()
    if t0 and OldKraken.PerfRecord then OldKraken:PerfRecord('roster.load', debugprofilestop() - t0) end
    return #rosterData
end

function Roster:RequestUpdate()
    if not IsInGuild or not IsInGuild() then
        chatInfo(T("|cff2ec4b6Old Kraken|r: персонаж не перебуває в гільдії."))
        return
    end

    if OldKraken.Communication.RequestRosterPresence then OldKraken.Communication:RequestRosterPresence() end
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    else
        chatError(T("|cff2ec4b6Old Kraken|r: API оновлення ростера недоступний."))
    end
end

function Roster:Show()
    if not GetSettings() then
        chatError(T("|cff2ec4b6Old Kraken|r: база даних ще не ініціалізована."))
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
if type(eventFrame.Hide) == 'function' then eventFrame:Hide() end
function Roster:ScheduleRefresh(reload)
    pendingLoad = pendingLoad or reload == true
    pendingRender = true
    if rosterFrame and rosterFrame:IsShown() and type(eventFrame.Show) == 'function' then eventFrame:Show() end
end
eventFrame:SetScript('OnUpdate', function(_, elapsed)
    if not pendingRender then
        refreshElapsed = 0
        if type(eventFrame.Hide) == 'function' then eventFrame:Hide() end
        return
    end
    refreshElapsed = refreshElapsed + elapsed
    if refreshElapsed < 0.15 then return end
    refreshElapsed = 0
    if not rosterFrame or not rosterFrame:IsShown() then
        if type(eventFrame.Hide) == 'function' then eventFrame:Hide() end
        return
    end
    local reload = pendingLoad
    pendingLoad, pendingRender = false, false
    if type(eventFrame.Hide) == 'function' then eventFrame:Hide() end
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

    if OldKraken.HandlePerfCommand and OldKraken:HandlePerfCommand(command) then
        return
    end

    if command == 'recipes' then
        if OldKraken.WorkshopRecipes then OldKraken.WorkshopRecipes:Show() end
        return
    elseif command == 'orders' then
        if OldKraken.WorkshopOrders then OldKraken.WorkshopOrders:Show() end
        return
    elseif command == 'workshop migrate' then
        if OldKraken.Database and type(OldKraken.Database.ConfirmWorkshopMigration) == 'function' then
            local ok, status = OldKraken.Database:ConfirmWorkshopMigration()
            if ok and status == 'completedWithOverflow' then
                chatInfo(T('Міграцію Майстерні завершено, але не всі конфлікти вмістилися у сховище конфліктів. Старі дані збережено без змін.'))
            elseif ok then
                chatInfo(T('Міграцію Майстерні завершено.'))
            elseif status == 'unavailable' then
                chatError(T('Майстерня ще завантажується. Спробуйте перенесення пізніше.'))
            else
                chatInfo(T('Немає очікуваної міграції Майстерні для поточного світу.'))
            end
            if ok and type(OldKraken.Database.WorkshopMigrationConflicts)=='function' then
                local count=OldKraken.Database.WorkshopMigrationConflicts()
                if count>0 then chatInfo(T('Збережено розбіжностей: ')..count..T('. Переглянути: /okr workshop conflicts')) end
            end
        end
        return
    elseif command == 'workshop conflicts' then
        if OldKraken.Database and type(OldKraken.Database.WorkshopMigrationConflicts)=='function' then
            local count,sections,overflow=OldKraken.Database.WorkshopMigrationConflicts()
            chatInfo(T('Невирішених розбіжностей Майстерні: ')..count)
            if sections.orderDrafts then
                chatInfo(T('Чернетка: /okr workshop draft legacy — стара; /okr workshop draft canonical — поточна до перенесення.'))
            end
            if sections.pendingDeliveryTallies then
                chatInfo(T('Облік передач очікує відповідного замовлення; невідповідні дані збережено окремо.'))
            end
            if count>(sections.orderDrafts or 0)+(sections.pendingDeliveryTallies or 0) or overflow then
                chatInfo(T('Інші розбіжності збережені в даних аддона; старий розділ не видалено.'))
            end
        end
        return
    elseif command == 'workshop draft legacy' or command == 'workshop draft canonical' then
        if OldKraken.Database and type(OldKraken.Database.ChooseWorkshopDraft)=='function' then
            local choice=command=='workshop draft legacy' and 'legacy' or 'canonical'
            if OldKraken.Database.ChooseWorkshopDraft(choice) then
                chatInfo(T('Обрану чернетку відновлено.'))
            else
                chatInfo(T('Для цього персонажа немає збереженої розбіжності чернеток.'))
            end
        end
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

if OldKraken.LocalizeTable then
    OldKraken.LocalizeTable(STATUS_LABELS)
    OldKraken.LocalizeTable(ADDON_LABELS)
    OldKraken.LocalizeTable(SORT_LABELS)
end
