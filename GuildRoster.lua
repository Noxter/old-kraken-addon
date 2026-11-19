local T = OldKraken.Translate or function(text) return text end
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

local function ClassLabel(classToken)
    if not classToken or classToken == "" then
        return T("Усі класи")
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
    CreateColumnHeader(frame, T("ЛОКАЦІЯ"), "zone", 464, 160)
    CreateColumnHeader(frame, T("ПРОФЕСІЇ"), nil, 634, 110)
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
    frame:SetScript('OnShow', function() Roster:ScheduleRefresh(true) end)
    frame.scrollFrame = scroll
    frame.contentFrame = content
    rosterFrame = frame

    UpdateFilterButtonLabels()
    return frame
end

local function CreateRow(index, parent)
    local row = CreateFrame("Button", nil, parent)
    row:RegisterForClicks('RightButtonUp')
    row:SetScript('OnClick', ShowMemberMenu)
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
        { x = 464, width = 160 },
        { x = 634, width = 110 },
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
        hover:RegisterForClicks('RightButtonUp')
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

    local function isGathering(id)
        return OldKraken.Workshop and OldKraken.Workshop.IsGatheringProfession and OldKraken.Workshop:IsGatheringProfession(id)
    end
    row.professions = {}
    for i=1,5 do
        local icon=CreateFrame('Button',nil,row)
        icon:SetSize(18,18); icon:SetPoint('LEFT',row,'LEFT',634+(i-1)*22,0)
        icon.texture=icon:CreateTexture(nil,'ARTWORK'); icon.texture:SetAllPoints(icon)
        icon:SetScript('OnClick',function(self)
            if self.memberName and self.professionID and not isGathering(self.professionID) and OldKraken.WorkshopRecipes then
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
    UpdateSortHeaders()

    self:RenderVisible()
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
        if row.versionBadge then
            if version then
                row.versionBadge:Show()
            else
                row.versionBadge:Hide()
            end
        end
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
        print(T("|cff2ec4b6Old Kraken|r: персонаж не перебуває в гільдії."))
        return
    end

    if OldKraken.Communication.RequestRosterPresence then OldKraken.Communication:RequestRosterPresence() end
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    else
        print(T("|cff2ec4b6Old Kraken|r: API оновлення ростера недоступний."))
    end
end

function Roster:Show()
    if not GetSettings() then
        print(T("|cff2ec4b6Old Kraken|r: база даних ще не ініціалізована."))
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

if OldKraken.LocalizeTable then
    OldKraken.LocalizeTable(STATUS_LABELS)
    OldKraken.LocalizeTable(ADDON_LABELS)
    OldKraken.LocalizeTable(SORT_LABELS)
end
