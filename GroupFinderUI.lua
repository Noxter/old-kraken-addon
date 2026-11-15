-- Group Finder window and user actions.
local Finder = OldKraken.GroupFinder
local window, selected, requestsWindow
local refresh
local groupAlert
local lastAlertSoundAt = -math.huge
local ALERT_DURATION, ALERT_FADE_DURATION, ALERT_SOUND_INTERVAL = 9, 1, 60
local tab = 'all'
local offset = 0
local requestOffset = 0
local REQUESTS_PER_PAGE, CARDS_PER_PAGE = 2, 3
local category, role = 'dungeon', 'dps'
local filterCategory, filterRole, filterFree = 'all', '', false
local dungeon, filterDungeon = '', ''
local catalog = OldKraken.ActivityCatalog
local function UpdateReannounceButton(control)
    local group = selected and Finder.groups[selected]
    local remaining = group and Finder.GetReannounceRemaining and Finder:GetReannounceRemaining(group.id)
    if remaining and remaining > 0 then
        control:SetText(string.format('Анонс через %02d:%02d', math.floor(remaining / 60), remaining % 60))
        control:SetEnabled(false)
    else
        control:SetText('Оновити набір')
        control:SetEnabled(remaining == 0)
    end
end
local dungeonOptions = catalog.dungeon
local dungeonLabels, dungeonLevels = {}, {}
for _, options in ipairs({catalog.dungeon, catalog.raid}) do
    for _, entry in ipairs(options) do
        dungeonLabels[entry.value] = entry.label
        if entry.min and entry.max then dungeonLevels[entry.value] = entry end
    end
end
local activityOptions = {}
for _, options in ipairs({catalog.dungeon, catalog.raid}) do
    for i, entry in ipairs(options) do if #activityOptions == 0 or i > 1 then activityOptions[#activityOptions+1] = entry end end
end
local roleCoords = {
    tank={0,67/256,67/256,134/256}, healer={67/256,134/256,0,67/256},
    dps={67/256,134/256,67/256,134/256},
}
local roleAtlases = {
    tank='groupfinder-icon-role-large-tank', healer='groupfinder-icon-role-large-heal',
    dps='groupfinder-icon-role-large-dps',
}

local function setRoleIcon(texture, role)
    local atlas = roleAtlases[role]
    if atlas and type(texture.SetAtlas) == 'function' then
        local ok = pcall(texture.SetAtlas, texture, atlas, false)
        if ok then return end
    end
    texture:SetTexture('Interface\\LFGFrame\\UI-LFG-ICON-ROLES')
    texture:SetTexCoord(unpack(roleCoords[role]))
end
local categories = {'dungeon', 'quest', 'world', 'raid', 'pvp', 'other'}
local categoryLabels = {dungeon='Підземелля', quest='Квести', world='Відкритий світ', raid='Рейд', pvp='PvP', other='Інше'}
local roles = {'tank', 'healer', 'dps', 'flex'}
local roleLabels = {['']='Не визначено', tank='Танк', healer='Лікар', dps='DPS', flex='Гнучка'}
local roleColors = {tank='ff66b3ff', healer='ff69dc8c', dps='ffff7a6e', flex='ffffd06a', ['']='ffb5b5b5'}
local memberStateColors = {['автор']='ffffd35a', ['у групі']='ff69dc8c', ['резерв']='ffffc36b', ['невідомо']='ffb5b5b5'}
local pendingLabels = {pending='Очікує', reject='Відхилено', closed='Закрито', retry='Подайте заявку знову'}
local pendingColors = {pending='ffffc36b', reject='ffff7a6e', closed='ffb5b5b5', retry='ffffc36b'}
local applicationBadges = {
    pending={text='ОЧІКУЄ', color={1, 0.80, 0.25}},
    reject={text='ВІДХИЛЕНО', color={1, 0.35, 0.32}},
    closed={text='НАБІР ЗАКРИТО', color={0.70, 0.72, 0.76}},
    retry={text='ПОДАЙТЕ ЗНОВУ', color={1, 0.65, 0.25}},
}

local people = {}
local function refreshPeople()
    local nextPeople = {}
    if type(GetNumGuildMembers) == 'function' and type(GetGuildRosterInfo) == 'function' then
        local ok, count = pcall(GetNumGuildMembers)
        if ok and type(count) == 'number' then
            for i = 1, count do
                pcall(function()
                    local name, _, _, level, _, _, _, _, _, _, class = GetGuildRosterInfo(i)
                    if type(issecretvalue) == 'function' and (issecretvalue(name) or issecretvalue(level) or issecretvalue(class)) then return end
                    if type(name) == 'string' and name ~= '' then nextPeople[name] = {level=tonumber(level), class=class} end
                end)
            end
        end
    end
    if type(UnitName) == 'function' and type(UnitClass) == 'function' and type(UnitLevel) == 'function' then
        local units = {'player'}
        local raid = false
        if type(IsInRaid) == 'function' then
            local ok, value = pcall(IsInRaid)
            if ok and not (type(issecretvalue) == 'function' and issecretvalue(value)) then raid = value and true or false end
        end
        for i = 1, raid and 40 or 4 do units[#units + 1] = (raid and 'raid' or 'party') .. i end
        for _, unit in ipairs(units) do
            pcall(function()
                local name, surname = UnitName(unit)
                local _, class = UnitClass(unit)
                local level = UnitLevel(unit)
                if type(issecretvalue) == 'function' and (issecretvalue(name) or issecretvalue(surname) or issecretvalue(class) or issecretvalue(level)) then return end
                if type(name) ~= 'string' or name == '' then return end
                if type(surname) == 'string' and surname ~= '' then name = name .. ' ' .. surname end
                nextPeople[name] = {class=class, level=tonumber(level)}
            end)
        end
    end
    people = nextPeople
end

local function playerLabel(name)
    local info = people[name]
    local classColor = info and type(info.class) == 'string' and RAID_CLASS_COLORS and RAID_CLASS_COLORS[info.class]
    local colored = name
    if classColor and classColor.r and classColor.g and classColor.b then
        colored = string.format('|cff%02x%02x%02x%s|r', math.floor(classColor.r * 255), math.floor(classColor.g * 255), math.floor(classColor.b * 255), name)
    end
    if info and info.level and info.level > 0 then colored = colored .. ' (' .. info.level .. ')' end
    return colored
end

local function roleLabel(value)
    return '|c' .. (roleColors[value] or roleColors['']) .. (roleLabels[value] or 'Невідома') .. '|r'
end
local coloredRoleLabels = {}
for _, value in ipairs(roles) do coloredRoleLabels[value] = roleLabel(value) end

StaticPopupDialogs.OLDKRAKEN_REMOVE_MEMBER = {
    text = 'Видалити %s з групи? Якщо гравець у паті, аддон спробує виключити його з паті.',
    button1 = 'Видалити', button2 = 'Скасувати', timeout = 0,
    whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnAccept = function(_, callback) if type(callback) == 'function' then callback() end end,
}

local function button(parent, label, x, y, width, callback, height, variant)
    local b = CreateFrame('Button', nil, parent, 'UIPanelButtonTemplate')
    OldKraken.UIStyle.Button(b, variant)
    b:SetSize(width, height or 23); b:SetPoint('TOPLEFT', parent, 'TOPLEFT', x, y); b:SetText(label)
    b:SetScript('OnClick', callback)
    return b
end

local dropdownCount = 0
local function dropdown(parent, x, y, width, options, selectedValue, onSelect)
    dropdownCount = dropdownCount + 1
    local frame = CreateFrame('Frame', 'OldKrakenFinderSelect' .. dropdownCount, parent, 'UIDropDownMenuTemplate')
    OldKraken.UIStyle.Dropdown(frame)
    frame:SetPoint('TOPLEFT', parent, 'TOPLEFT', x - 16, y + 3)
    UIDropDownMenu_SetWidth(frame, width - 34)
    UIDropDownMenu_JustifyText(frame, 'LEFT')
    UIDropDownMenu_Initialize(frame, function(_, level)
        local available = type(options) == 'function' and options() or options
        for _, option in ipairs(available) do
            local item = option
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.value = item.label, item.value
            info.checked = selectedValue() == item.value
            info.func = function() onSelect(item.value); UIDropDownMenu_SetText(frame, item.label) end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    local initial = type(options) == 'function' and options() or options
    for _, option in ipairs(initial) do
        if option.value == selectedValue() then UIDropDownMenu_SetText(frame, option.label); break end
    end
    return frame
end

local function choices(values, labels, first)
    local out = {}
    if first then out[#out + 1] = first end
    for _, value in ipairs(values) do out[#out + 1] = {value=value, label=labels[value]} end
    return out
end

local function input(parent, label, x, y, width, initial)
    local text = parent:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    text:SetPoint('TOPLEFT', parent, 'TOPLEFT', x, y); text:SetText(label)
    local box = CreateFrame('EditBox', nil, parent, 'InputBoxTemplate')
    OldKraken.UIStyle.Input(box)
    box:SetSize(width, 22); box:SetPoint('TOPLEFT', parent, 'TOPLEFT', x + 4, y - 18)
    box:SetAutoFocus(false); box:SetText(initial or '')
    box.label = text
    box:SetScript('OnEscapePressed', function(self) self:ClearFocus() end)
    return box
end

local function invitePlayer(name)
    return OldKraken:InvitePlayer(name)
end

local function refreshRequests()
    if not requestsWindow or not requestsWindow:IsShown() then return end
    local entries = {}
    for id, requests in pairs(Finder.requests or {}) do
        local group = Finder.groups[Finder.identity .. '\001' .. id]
        if group and not group.closed and not group.hidden then
            for name, applicantRole in pairs(requests) do
                local requestKey = id .. '\001' .. name
                entries[#entries + 1] = {
                    id=id, name=name, role=applicantRole, title=group.title,
                    selected=selected == Finder.identity .. '\001' .. id,
                    time=Finder.requestVersions[requestKey] or 0,
                }
            end
        end
    end
    table.sort(entries, function(a, b)
        if a.selected ~= b.selected then return a.selected end
        if a.time ~= b.time then return a.time > b.time end
        if a.title ~= b.title then return a.title < b.title end
        return a.name < b.name
    end)
    if requestOffset >= #entries then requestOffset = math.max(0, math.floor((#entries - 1) / REQUESTS_PER_PAGE) * REQUESTS_PER_PAGE) end
    requestsWindow.entries = entries
    requestsWindow.empty:SetShown(#entries == 0)
    requestsWindow.count:SetText('Заявок: ' .. #entries)
    for i, row in ipairs(requestsWindow.rows) do
        local entry = entries[requestOffset + i]
        row.entry = entry
        if entry then
            row.name:SetText(playerLabel(entry.name))
            row.roleStatus:SetText(roleLabel(entry.role or '') .. ' |cff9ba9bc·|r |cffffc36bОчікує|r')
            row.accept:SetEnabled(Finder:CanPerformRole(entry.name,entry.role))
            row.group:SetText(entry.title)
            row.name:Show(); row.roleStatus:Show(); row.group:Show(); row.hover:Show(); row.accept:Show(); row.reject:Show()
        else
            row.name:Hide(); row.roleStatus:Hide(); row.group:Hide(); row.hover:Hide(); row.accept:Hide(); row.reject:Hide()
        end
    end
    local showPagination = #entries > REQUESTS_PER_PAGE
    requestsWindow.page:SetText(showPagination and ((math.floor(requestOffset / REQUESTS_PER_PAGE) + 1) .. ' / ' .. math.ceil(#entries / REQUESTS_PER_PAGE)) or '')
    requestsWindow.page:SetShown(showPagination); requestsWindow.previousPage:SetShown(showPagination); requestsWindow.nextPage:SetShown(showPagination)
end

local function showRequests()
    if not Finder.active then print('Old Kraken: пошук груп не ініціалізовано.'); return end
    if not window or not window:IsShown() then Finder:Show() end
    if not window or not window:IsShown() then return end
    if tab == 'create' then tab='mine'; selected=nil end
    refreshPeople()
    if not requestsWindow then
        local f = CreateFrame('Frame', 'OldKrakenRequestsFrame', window)
        f:Hide()
        f:SetSize(300, 175); f:SetPoint('TOPLEFT', window, 'TOPLEFT', 550, -70)
        f:EnableMouse(true)
        f.count = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
        f.count:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, 0)
        f.empty = f:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        f.empty:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, -28); f.empty:SetWidth(285); f.empty:SetJustifyH('LEFT'); f.empty:SetText('Нових заявок немає. Поверніться до деталей оголошення.')
        f.rows = {}
        for i=1, REQUESTS_PER_PAGE do
            local row = {}
            local y = -22 - (i - 1) * 55
            row.name = f:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
            row.name:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, y); row.name:SetSize(150, 18)
            row.name:SetJustifyH('LEFT'); row.name:SetWordWrap(false)
            row.roleStatus = f:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
            row.roleStatus:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, y - 18); row.roleStatus:SetSize(150, 16)
            row.roleStatus:SetJustifyH('LEFT'); row.roleStatus:SetWordWrap(false)
            row.group = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
            row.group:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, y - 34); row.group:SetSize(150, 15)
            row.group:SetJustifyH('LEFT'); row.group:SetWordWrap(false)
            row.hover = CreateFrame('Frame', nil, f)
            row.hover:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, y); row.hover:SetSize(150, 49); row.hover:EnableMouse(true)
            row.hover:SetScript('OnEnter', function(self)
                if not row.entry then return end
                GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
                GameTooltip:SetText(playerLabel(row.entry.name) .. ' · ' .. roleLabel(row.entry.role))
                GameTooltip:AddLine('|cffffc36bОчікує|r', 1, 1, 1)
                GameTooltip:AddLine(row.entry.title, 1, 1, 1, true); GameTooltip:Show()
            end)
            row.hover:SetScript('OnLeave', function() GameTooltip:Hide() end)
            local function decide(accept)
                local entry = row.entry
                if not entry then return end
                local group = Finder.groups[Finder.identity .. '\001' .. entry.id]
                if not group or group.closed or not Finder.requests[entry.id] or Finder.requests[entry.id][entry.name] == nil then refreshRequests(); return end
                if Finder:Decide(entry.id, entry.name, accept) then
                    Finder:Changed()
                    if accept then invitePlayer(entry.name) end
                    refreshRequests()
                else print('Old Kraken: не вдалося обробити заявку. Перевірте наявність місць і зв’язок.') end
            end
            row.accept = button(f, 'Прийняти', 150, y - 10, 70, function() decide(true) end, nil, 'primary')
            row.reject = button(f, 'Відхилити', 225, y - 10, 70, function() decide(false) end)
            row.accept:SetScript('OnEnter', function(self) if GameTooltip then GameTooltip:SetOwner(self, 'ANCHOR_RIGHT'); GameTooltip:SetText(row.entry and not Finder:CanPerformRole(row.entry.name,row.entry.role) and 'Клас учасника не може виконувати цю роль або ще невідомий.' or 'Прийняти заявку'); GameTooltip:Show() end end)
            row.reject:SetScript('OnEnter', function(self) if GameTooltip then GameTooltip:SetOwner(self, 'ANCHOR_RIGHT'); GameTooltip:SetText('Відхилити заявку'); GameTooltip:Show() end end)
            row.accept:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
            row.reject:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
            f.rows[i] = row
        end
        f.previousPage = button(f, '‹', 0, -145, 45, function() requestOffset=math.max(0, requestOffset-REQUESTS_PER_PAGE); refreshRequests() end)
        f.nextPage = button(f, '›', 97, -145, 45, function() if requestOffset + REQUESTS_PER_PAGE < #(f.entries or {}) then requestOffset=requestOffset+REQUESTS_PER_PAGE end; refreshRequests() end)
        f.page = f:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        f.page:SetPoint('TOPLEFT', f, 'TOPLEFT', 52, -149)
        requestsWindow = f
    end
    requestsWindow:Show(); refreshRequests(); if refresh then refresh() end
end

refresh=function()
    if not window or not window:IsShown() then return end
    if not Finder:CanPerformRole(Finder.identity,role) then role=Finder:PreferredRole(); UIDropDownMenu_SetText(window.roleButton,roleLabel(role)) end
    window.alertButton:SetText(Finder:GroupAlertsEnabled() and 'Сповіщення: увімк.' or 'Сповіщення: вимк.')
    local lines = {}
    for key, group in pairs(Finder.groups or {}) do
        local level = tonumber(window.levelFilter:GetText())
        local query = string.lower(window.searchFilter:GetText() or '')
        local matches = (filterCategory == 'all' or group.category == filterCategory)
            and (filterDungeon == '' or group.dungeon == filterDungeon)
            and (filterRole == '' or (#group.members < group.maxSize and Finder:RoleAvailable(group, filterRole)))
            and (not filterFree or #group.members < group.maxSize)
            and (not level or (level >= group.minLevel and level <= group.maxLevel))
            and (query == '' or string.find(string.lower(group.title .. ' ' .. group.owner .. ' ' .. group.description .. ' ' .. (dungeonLabels[group.dungeon] or '')), query, 1, true))
        if (tab == 'all' and not group.closed and matches) or (tab == 'mine' and group.owner == Finder.identity and not group.hidden)
            or (tab == 'applications' and Finder.pending[key]) then
            lines[#lines + 1] = {key=key, group=group}
        end
    end
    table.sort(lines, function(a,b) return a.group.title < b.group.title end)
    if offset >= #lines then offset = math.max(0, math.floor((#lines - 1) / CARDS_PER_PAGE) * CARDS_PER_PAGE) end
    window.visible = lines
    local empty = #lines == 0 and tab ~= 'create'
    window.emptyList:SetText(tab == 'applications' and 'Ви ще не подали жодної заявки.' or (tab == 'mine' and 'У вас ще немає оголошень.' or 'Груп не знайдено. Змініть фільтри або створіть оголошення.'))
    window.emptyList:SetShown(empty)
    local hasFilters = filterCategory ~= 'all' or filterRole ~= '' or filterFree or filterDungeon ~= '' or (window.searchFilter:GetText() or '') ~= '' or (window.levelFilter:GetText() or '') ~= ''
    window.emptyAction:SetText(tab == 'applications' and 'Знайти групу' or (tab == 'all' and hasFilters and 'Очистити фільтри' or 'Створити оголошення'))
    window.emptyAction:SetShown(empty)
    for _, item in ipairs(window.tabs) do
        item.button.activeMark:SetShown(item.key == tab)
        if item.key == tab then item.button:LockHighlight() else item.button:UnlockHighlight() end
    end
    local pageCount = math.ceil(#lines / CARDS_PER_PAGE)
    local showPagination = tab ~= 'create' and pageCount > 1
    window.listPage:SetText(showPagination and ((math.floor(offset / CARDS_PER_PAGE) + 1) .. ' / ' .. pageCount) or '')
    window.listPage:SetShown(showPagination)
    window.previousPageButton:SetShown(showPagination)
    window.nextPageButton:SetShown(showPagination)
    for i, b in ipairs(window.rows) do
        local entry = lines[i + offset]
        if entry then
            local g = entry.group
            local status = Finder.pending[entry.key]
            local kind = (g.dungeon and g.dungeon ~= '' and dungeonLabels[g.dungeon]) or categoryLabels[g.category] or g.category
            catalog.SetArtwork(b.art, g.dungeon)
            b.title:SetText(g.title == kind and g.title or (g.title .. '  ·  ' .. kind))
            local present, reserved = {}, 0
            if g.partyObserved then
                for memberIndex = 2, #g.members do
                    local name = g.members[memberIndex]
                    if g.partyObserved[name] then present[#present + 1] = name else reserved = reserved + 1 end
                end
            end
            b.meta:SetText(string.format('%s  ·  %d–%d  ·  місць %d/%d%s', playerLabel(g.owner), g.minLevel, g.maxLevel, #g.members, g.maxSize, reserved > 0 and (' · резерв ' .. reserved) or ''))
            local badge = tab == 'applications' and applicationBadges[status]
            if badge then
                b.status:SetText(badge.text); b.status:SetTextColor(unpack(badge.color)); b.status:Show(); b.statusBackground:Show()
            else b.status:Hide(); b.statusBackground:Hide() end
            local preview = {}
            if g.partyObserved and #present > 0 then
                preview[1] = playerLabel(g.owner)
                for memberIndex = 1, math.min(#present, 2) do preview[#preview + 1] = playerLabel(present[memberIndex]) end
                b.members:SetText('У паті: ' .. table.concat(preview, ', ') .. (#present > 2 and ('  +' .. (#present - 2)) or ''))
            else
                b.members:SetText(g.partyObserved and 'Автор поки без паті' or 'Склад паті не підтверджено')
            end
            local fixedSlots = g.category == 'dungeon' and g.maxSize == 5 and Finder:DungeonSlots(g) or nil
            for slotIndex, slot in ipairs(b.slots) do
                if slotIndex <= math.min(5, g.maxSize) then
                    -- In larger groups the last circle remains an entry point
                    -- for any free place; the detailed roster retains all names.
                    local fixed = fixedSlots and fixedSlots[slotIndex]
                    local member = fixed and fixed.member or (not fixed and g.members[slotIndex])
                    if not fixed and slotIndex == 5 and g.maxSize > 5 and #g.members < g.maxSize then member = nil end
                    local memberRole = fixed and fixed.memberRole or (member and (member == g.owner and g.role or (g.memberRoles and g.memberRoles[member]) or '')) or ''
                    slot.groupKey, slot.member, slot.memberRole, slot.requiredRole = entry.key, member, memberRole, fixed and fixed.role or nil
                    if member then
                        local isReserved = member ~= g.owner and g.partyObserved and not g.partyObserved[member]
                        if roleCoords[memberRole] then
                            slot.ring:Hide(); setRoleIcon(slot.icon, memberRole); slot.icon:SetAlpha(isReserved and 0.45 or 1); slot.icon:Show(); slot.text:Hide()
                        elseif memberRole == 'flex' then
                            slot.ring:Hide(); slot.icon:Hide(); slot.text:SetText('F'); slot.text:Show()
                        else
                            slot.ring:Show(); slot.icon:Hide(); slot.text:SetText('?'); slot.text:Show()
                        end
                    else
                        slot.ring:Show(); slot.icon:Hide(); slot.text:Hide()
                    end
                    slot:Show()
                else slot:Hide() end
            end
            if selected == entry.key then b:LockHighlight() else b:UnlockHighlight() end
            b:Show()
            if (tab == 'applications' and status) or (g.owner == Finder.identity and not g.hidden) then window.deleteButtons[i]:Show() else window.deleteButtons[i]:Hide() end
        else
            b:UnlockHighlight()
            b:Hide()
            window.deleteButtons[i]:Hide()
        end
    end
    if tab == 'create' and requestsWindow then requestsWindow:Hide() end
    local showingRequests = requestsWindow and requestsWindow:IsShown() and tab ~= 'create'
    window.detailsScroll:SetShown(tab ~= 'create' and not showingRequests)
    local g = tab ~= 'create' and selected and Finder.groups[selected]
    if g then
        local applicationStatus = Finder.pending[selected]
        local activity = (g.dungeon and g.dungeon ~= '' and dungeonLabels[g.dungeon]) or categoryLabels[g.category]
        local activityLine = activity and activity ~= g.title and ('\n|cff9ba9bc' .. activity .. '|r') or ''
        local status = g.closed and '|cffb5b5b5Закрито|r' or '|cff69dc8cВідкрито|r'
        local application = applicationStatus and ('\n|cff9ba9bcЗаявка:|r |c' .. (pendingColors[applicationStatus] or 'ffb5b5b5') .. (pendingLabels[applicationStatus] or applicationStatus) .. '|r') or ''
        local description = g.description ~= '' and ('\n\n|cff9ba9bcОпис:|r ' .. g.description) or ''
        window.details:SetText(string.format('|cffffd35a%s|r%s\n\n|cff9ba9bcАвтор:|r |cff9bcaff%s|r\n|cff9ba9bcРівень:|r |cff9bcaff%d–%d|r\n|cff9ba9bcРоль:|r %s\n|cff9ba9bcСтатус:|r %s%s%s\n\n|cffffd35aСклад:|r',
            g.title, activityLine, playerLabel(g.owner), g.minLevel, g.maxLevel, roleLabel(g.role), status, application, description))
    else window.details:SetText('Виберіть оголошення у списку.') end
    local canManage = tab ~= 'create' and g and g.owner == Finder.identity and not g.closed
    local members = g and g.members or {}
    local top = window.details:GetStringHeight() + 5
    local viewport=tonumber((window.detailsScroll:GetHeight())) or 210
    if viewport<=0 then viewport=210 end
    local oldScroll=tonumber((window.detailsScroll:GetVerticalScroll())) or 0
    local scrollTop=math.max(0,math.min(oldScroll,math.max(0,math.max(210,top+#members*40+4)-viewport)))
    if scrollTop~=oldScroll then window.detailsScroll:SetVerticalScroll(scrollTop) end
    local first=math.max(1,math.floor((scrollTop-top)/40)+1)
    local visibleCount=math.max(0,math.min(math.ceil(viewport/40)+1,#members-first+1))
    for i = 1, math.max(visibleCount, #window.memberRows) do
        local dataIndex=first+i-1
        local row = window.memberRows[i]
        if i <= visibleCount then
            if not row then
                row = {}
                row.name = window.detailsContent:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
                row.name:SetWidth(155); row.name:SetHeight(20); row.name:SetJustifyH('LEFT'); row.name:SetWordWrap(false)
                row.state = window.detailsContent:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
                row.state:SetWidth(285); row.state:SetHeight(16); row.state:SetJustifyH('LEFT'); row.state:SetWordWrap(false)
                row.hover = CreateFrame('Frame', nil, window.detailsContent)
                row.hover:SetSize(155, 22); row.hover:EnableMouse(true)
                row.hover:SetScript('OnEnter', function(self)
                    if GameTooltip then GameTooltip:SetOwner(self, 'ANCHOR_RIGHT'); GameTooltip:SetText(self.memberLabel); GameTooltip:Show() end
                end)
                row.hover:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
                row.invite = CreateFrame('Button', nil, window.detailsContent, 'UIPanelButtonTemplate')
                OldKraken.UIStyle.Button(row.invite, 'primary')
                row.invite:SetSize(100, 22); row.invite:SetText('Запросити')
                row.invite:SetScript('OnClick', function(self)
                    local current = selected and Finder.groups[selected]
                    local name = self.memberName
                    if not current or current.owner ~= Finder.identity or current.closed or not current.partyObserved or current.partyObserved[name] then return end
                    for j = 2, #current.members do
                        if current.members[j] == name then invitePlayer(name); return end
                    end
                end)
                row.remove = CreateFrame('Button', nil, window.detailsContent, 'UIPanelButtonTemplate')
                OldKraken.UIStyle.Button(row.remove)
                row.remove:SetSize(30, 22); row.remove:SetText('×')
                row.remove:SetScript('OnEnter', function(self)
                    if GameTooltip then GameTooltip:SetOwner(self, 'ANCHOR_RIGHT'); GameTooltip:SetText('Видалити з оголошення або виключити з паті'); GameTooltip:Show() end
                end)
                row.remove:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
                row.remove:SetScript('OnClick', function(self)
                    local name = self.memberName
                    local key = selected
                    local function remove()
                    local current = key and Finder.groups[key]
                    if not current or current.owner ~= Finder.identity or current.closed then return end
                    local present = false
                    for j = 2, #current.members do if current.members[j] == name then present = true; break end end
                    if not present then return end
                    if not current.partyObserved then
                        print('|cffff5555Old Kraken|r: Склад паті ще не визначено. Спробуйте пізніше.')
                    elseif current.partyObserved[name] then
                        if type(UnitIsGroupLeader) == 'function' and not UnitIsGroupLeader('player') then
                            print('|cffff5555Old Kraken|r: Для виключення гравця потрібні права лідера групи.')
                        elseif not C_PartyInfo or type(C_PartyInfo.UninviteUnit) ~= 'function' then
                            print('|cffff5555Old Kraken|r: API виключення недоступний. Видаліть гравця з паті вручну.')
                        else
                            local ok, result = pcall(C_PartyInfo.UninviteUnit, name)
                            if ok and result ~= false then
                                print('|cff2ec4b6Old Kraken|r: Спроба виключити ' .. name .. ' з паті. Перевірте повідомлення гри.')
                            else
                                print('|cffff5555Old Kraken|r: Не вдалося виключити ' .. name .. ' з паті.')
                            end
                        end
                    elseif Finder:RemoveMember(current.id, name) then
                        Finder:Changed(); refresh()
                    else
                        print('|cffff5555Old Kraken|r: Не вдалося видалити резерв. Перевірте зв’язок.')
                    end
                    end
                    local popup = StaticPopup_Show('OLDKRAKEN_REMOVE_MEMBER', name, nil, remove)
                    if popup then
                        popup.oldKrakenStrata = popup:GetFrameStrata()
                        if not popup.oldKrakenRestoreHook then
                            popup:HookScript('OnHide', function(self)
                                if self.oldKrakenStrata then
                                    self:SetFrameStrata(self.oldKrakenStrata)
                                    self.oldKrakenStrata = nil
                                end
                            end)
                            popup.oldKrakenRestoreHook = true
                        end
                        popup:SetFrameStrata('FULLSCREEN_DIALOG')
                    end
                end)
                window.memberRows[i] = row
            end
            local name = members[dataIndex]
            local state = dataIndex == 1 and 'автор' or
                (not g.partyObserved and 'невідомо' or (g.partyObserved[name] and 'у групі' or 'резерв'))
            row.name:ClearAllPoints(); row.name:SetPoint('TOPLEFT', window.detailsContent, 'TOPLEFT', 0, -top - (dataIndex - 1) * 40)
            local memberRole=dataIndex==1 and g.role or (g.memberRoles and g.memberRoles[name])
            local coloredRole=roleLabel(memberRole or '')
            local coloredState='|c' .. memberStateColors[state] .. state .. '|r'
            row.name:SetText((catalog.roleIcons[memberRole] or '') .. ' ' .. playerLabel(name)); row.name:Show()
            row.state:ClearAllPoints(); row.state:SetPoint('TOPLEFT', row.name, 'BOTTOMLEFT', 0, 0); row.state:SetText(coloredRole .. ' |cff9ba9bc·|r ' .. coloredState); row.state:Show()
            row.hover:ClearAllPoints(); row.hover:SetPoint('TOPLEFT', row.name, 'TOPLEFT'); row.hover.memberLabel = name .. '\nРоль: ' .. coloredRole .. '\nСтатус: ' .. coloredState; row.hover:Show()
            row.invite:ClearAllPoints(); row.invite:SetPoint('TOPLEFT', window.detailsContent, 'TOPLEFT', 160, -top - (dataIndex - 1) * 40)
            row.invite.memberName = name
            if canManage and dataIndex > 1 and g.partyObserved and not g.partyObserved[name] then row.invite:Show() else row.invite:Hide() end
            row.remove:ClearAllPoints(); row.remove:SetPoint('TOPLEFT', window.detailsContent, 'TOPLEFT', 265, -top - (dataIndex - 1) * 40)
            row.remove.memberName = name
            if canManage and dataIndex > 1 then row.remove:Show() else row.remove:Hide() end
        elseif row then
            row.name:Hide(); row.state:Hide(); row.hover:Hide(); row.invite:Hide(); row.remove:Hide()
        end
    end
    window.detailsContent:SetHeight(math.max(210, top + #members * 40 + 4))
    local isOther = tab ~= 'create' and g and g.owner ~= Finder.identity and not g.closed
    local pending = selected and Finder.pending[selected]
    local alreadyMember = false
    if g then for _, name in ipairs(g.members) do if name == Finder.identity then alreadyMember = true; break end end end
    local canApply = isOther and not showingRequests and not alreadyMember and pending ~= 'pending'
    window.applyButton:SetShown(canApply)
    window.applicationActionButton:SetText(pending == 'pending' and 'Відкликати' or 'Прибрати заявку')
    window.applicationActionButton:SetShown(not showingRequests and tab == 'applications' and g and g.owner ~= Finder.identity and pending ~= nil)
    window.cancelButton:SetShown(canManage and not showingRequests)
    window.bumpButton:SetShown(canManage and not showingRequests)
    UpdateReannounceButton(window.bumpButton)
    local roleLabelY = -313
    window.roleLabel:ClearAllPoints(); window.roleLabel:SetPoint('TOPLEFT', window, 'TOPLEFT', 550, roleLabelY)
    window.roleButton:ClearAllPoints(); window.roleButton:SetPoint('TOPLEFT', window, 'TOPLEFT', 534, roleLabelY - 14)
    window.roleButton:SetShown(canApply and true or false)
    window.roleLabel:SetShown(canApply and true or false)
    local requestCount, haveOwned = 0, false
    for _, group in pairs(Finder.groups or {}) do
        if group.owner == Finder.identity and not group.closed and not group.hidden then haveOwned = true; break end
    end
    for id, applicants in pairs(Finder.requests or {}) do
        local own = Finder.groups[Finder.identity .. '\001' .. id]
        if own and not own.closed and not own.hidden then for _ in pairs(applicants) do requestCount = requestCount + 1 end end
    end
    window.requestsButton:SetText(showingRequests and '← До деталей' or ('Заявки: ' .. requestCount))
    window.requestsButton:SetShown(tab ~= 'create' and (haveOwned or showingRequests))
    for _, control in ipairs(window.filterControls) do control:SetShown(tab == 'all') end
    window.creationFooter:SetShown(tab=='create')
    window.LayoutCreation()
    local showCards=tab=='create' and (category=='dungeon' or category=='raid')
    window.activityPicker:SetShown(showCards)
    if showCards then window.UpdateActivityCards() end
    local advanced=tab=='create' and window.advancedCreation
    window.creationOptions:SetShown(advanced)
    for _,box in ipairs({window.titleBox,window.maxBox,window.minBox,window.maxLevelBox}) do
        box:SetShown(advanced); box.label:SetShown(advanced)
    end
    window.descriptionBox:SetShown(tab=='create'); window.descriptionBox.label:Hide()
    window.categoryButton:SetShown(advanced); window.categoryLabel:SetShown(advanced)
    window.dungeonLabel:Hide()
    window.maxBox.label:SetText(category=='dungeon' and 'Місць (5)' or 'Місць')
    window.createButton:SetShown(tab=='create')
    window.createButton:SetText('Зібрати групу')
    for _,control in ipairs(window.creationRoles) do
        control:SetEnabled(Finder:CanPerformRole(Finder.identity,control.role))
        control:SetShown(tab=='create' and (category~='dungeon' or control.role~='flex'))
        control.active:SetShown(control.role==role)
    end
    window.creationOptionsButton:SetText(window.advancedCreation and 'Менше' or 'Деталі')
    local selectedActivity=dungeon~='' and dungeonLabels[dungeon] or nil
    window.dungeonSelection:SetText(selectedActivity or ((category=='dungeon' or category=='raid') and 'Оберіть картку вище' or categoryLabels[category]))
    catalog.SetArtwork(window.creationArt,dungeon)

end

local function createWindow(parent)
    local f
    if parent then
        f = CreateFrame('Frame', 'OldKrakenGroupFinderFrame', parent)
    else
        f = CreateFrame('Frame', 'OldKrakenGroupFinderFrame', UIParent, 'BasicFrameTemplateWithInset')
    end
    if not parent then table.insert(UISpecialFrames, 'OldKrakenGroupFinderFrame') end
    f.embedded = parent ~= nil
    f:SetSize(900, 590); f:SetPoint('CENTER', parent or UIParent, 'CENTER'); f:SetMovable(not parent); f:EnableMouse(true)
    if not parent then
        f:RegisterForDrag('LeftButton'); f:SetScript('OnDragStart', f.StartMoving)
    end
    if not parent then
        f:SetScript('OnDragStop', function(self)
            self:StopMovingOrSizing()
        end)
    end
    f:SetClampedToScreen(true); f:Hide()
    if not parent then OldKraken.UIStyle.Window(f) end
    f:HookScript('OnHide', function() if requestsWindow then requestsWindow:Hide() end end)
    OldKraken.UIStyle.Panel(f, 12, -60, 526, 255)
    OldKraken.UIStyle.Panel(f, 542, -60, 335, 255)
    if f.TitleText then f.TitleText:SetText('Old Kraken — Пошук груп') end
    f.tabs = {}
    for i, item in ipairs({{'Усі групи','all'}, {'Створити','create'}, {'Мої заявки','applications'}, {'Мої оголошення','mine'}}) do
        local b = button(f, item[1], 18 + (i-1)*160, -32, 150, function()
            if requestsWindow then requestsWindow:Hide() end
            if type(CloseDropDownMenus)=='function' then CloseDropDownMenus() end
            tab=item[2]; selected=nil; offset=0; requestOffset=0; refresh()
        end)
        b.activeMark = b:CreateTexture(nil, 'OVERLAY')
        b.activeMark:SetPoint('BOTTOMLEFT', b, 'BOTTOMLEFT', 8, 2)
        b.activeMark:SetSize(134, 2)
        b.activeMark:SetColorTexture(unpack(OldKraken.UIStyle.Colors.brandGold))
        b.activeMark:Hide()
        f.tabs[#f.tabs + 1] = {key=item[2], button=b}
    end
    f.alertButton = button(f, 'Сповіщення', 700, -32, 175, function()
        if Finder:SetGroupAlertsEnabled(not Finder:GroupAlertsEnabled()) then refresh()
        else print('Old Kraken: не вдалося зберегти налаштування сповіщень.') end
    end)
    f.rows, f.deleteButtons = {}, {}
    f.slotMenu = CreateFrame('Frame', 'OldKrakenSlotRoleMenu', f, 'UIDropDownMenuTemplate')
    UIDropDownMenu_Initialize(f.slotMenu, function(_, level)
        for _, candidate in ipairs(roles) do
            local choice = candidate
            local info = UIDropDownMenu_CreateInfo()
            info.text = 'Подати заявку: ' .. roleLabel(choice)
            info.disabled = not Finder:CanPerformRole(Finder.identity,choice)
            info.notCheckable = true
            info.func = function()
                local key = f.slotMenu.groupKey
                local group = key and Finder.groups[key]
                if not group or group.owner == Finder.identity or group.closed or #group.members >= group.maxSize
                    or Finder.pending[key] == 'pending' then return end
                for _, name in ipairs(group.members) do if name == Finder.identity then return end end
                if Finder:Apply(group.owner, group.id, choice) then Finder:Changed(); refresh()
                else print('Old Kraken: не вдалося подати заявку. Перевірте зв’язок.') end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end, 'MENU')
    f.emptyList = f:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
    f.emptyList:SetPoint('TOPLEFT', f, 'TOPLEFT', 25, -75); f.emptyList:SetWidth(480); f.emptyList:SetJustifyH('LEFT'); f.emptyList:SetText('Груп не знайдено. Змініть фільтри або створіть оголошення.')
    f.emptyAction = button(f, 'Створити оголошення', 25, -115, 190, function()
        local hasFilters = filterCategory ~= 'all' or filterRole ~= '' or filterFree or filterDungeon ~= '' or (f.searchFilter:GetText() or '') ~= '' or (f.levelFilter:GetText() or '') ~= ''
        if tab == 'all' and hasFilters then
            filterCategory, filterRole, filterFree, filterDungeon = 'all', '', false, ''
            f.searchFilter:SetText(''); f.levelFilter:SetText('')
            UIDropDownMenu_SetText(f.categoryFilter, 'Усі категорії'); UIDropDownMenu_SetText(f.roleFilter, 'Усі ролі')
            UIDropDownMenu_SetText(f.freeFilter, 'Усі групи'); UIDropDownMenu_SetText(f.dungeonFilter, dungeonLabels[''] or 'Усі / не вибрано')
        elseif tab == 'applications' then tab='all'
        else tab='create' end
        selected=nil; offset=0; refresh()
    end)
    for i=1,CARDS_PER_PAGE do
        local index = i
        local card = button(f, '', 18, -65-(i-1)*82, 490, function()
            local entry = f.visible and f.visible[index + offset]
            if entry then if requestsWindow then requestsWindow:Hide() end; if selected ~= entry.key then requestOffset=0; f.detailsScroll:SetVerticalScroll(0) end; selected=entry.key; refresh() end
        end)
        card:SetHeight(78)
        card.art = card:CreateTexture(nil, 'ARTWORK')
        card.art:SetPoint('TOPLEFT', card, 'TOPLEFT', 1, -4); card.art:SetSize(70, 70)
        card.title = card:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
        card.title:SetPoint('TOPLEFT', card, 'TOPLEFT', 78, -8); card.title:SetPoint('RIGHT', card, 'RIGHT', -155, 0)
        card.title:SetJustifyH('LEFT'); card.title:SetWordWrap(false)
        card.meta = card:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
        card.meta:SetPoint('TOPLEFT', card, 'TOPLEFT', 78, -31); card.meta:SetPoint('RIGHT', card, 'RIGHT', -155, 0)
        card.meta:SetJustifyH('LEFT'); card.meta:SetWordWrap(false)
        card.members = card:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
        card.members:SetPoint('TOPLEFT', card, 'TOPLEFT', 78, -54); card.members:SetPoint('RIGHT', card, 'RIGHT', -155, 0)
        card.members:SetJustifyH('LEFT'); card.members:SetWordWrap(false)
        card.statusBackground = card:CreateTexture(nil, 'ARTWORK')
        card.statusBackground:SetPoint('BOTTOMRIGHT', card, 'BOTTOMRIGHT', -8, 7)
        card.statusBackground:SetSize(138, 23); card.statusBackground:SetColorTexture(0.035, 0.04, 0.05, 0.92)
        card.status = card:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
        card.status:SetPoint('CENTER', card.statusBackground, 'CENTER'); card.status:SetWidth(132)
        card.status:SetJustifyH('CENTER'); card.status:SetWordWrap(false)
        card.slots = {}
        for slotIndex = 1, 5 do
            local slot = CreateFrame('Button', nil, card)
            slot:SetSize(25, 25); slot:SetPoint('TOPRIGHT', card, 'TOPRIGHT', -8 - (5-slotIndex)*28, -7)
            slot.ring = slot:CreateTexture(nil, 'ARTWORK')
            slot.ring:SetPoint('CENTER'); slot.ring:SetSize(15, 15)
            local ok = type(slot.ring.SetAtlas) == 'function' and pcall(slot.ring.SetAtlas, slot.ring, 'groupfinder-icon-emptyslot', false)
            if not ok then
                slot.ring:SetTexture('Interface\\CHARACTERFRAME\\TempPortraitAlphaMask')
                slot.ring:SetVertexColor(0.18, 0.18, 0.18, 0.9)
            end
            slot.icon = slot:CreateTexture(nil, 'OVERLAY')
            slot.icon:SetPoint('CENTER'); slot.icon:SetSize(22, 22)
            slot.text = slot:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall'); slot.text:SetPoint('CENTER'); slot.text:SetTextColor(1, 1, 1)
            slot:SetScript('OnEnter', function(self)
                GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
                if self.member then
                    GameTooltip:SetText(playerLabel(self.member))
                    GameTooltip:AddLine('Роль: ' .. roleLabel(self.memberRole), 1, 1, 1)
                    local group = self.groupKey and Finder.groups[self.groupKey]
                    if group and self.member ~= group.owner then
                        GameTooltip:AddLine(not group.partyObserved and 'Стан невідомий' or (group.partyObserved[self.member] and 'У паті' or 'Резерв'), 1, 1, 1)
                    end
                else
                    GameTooltip:SetText('Вільне місце' .. (self.requiredRole and (': ' .. roleLabel(self.requiredRole)) or ''))
                    local group = self.groupKey and Finder.groups[self.groupKey]
                    if group and group.owner == Finder.identity then
                        GameTooltip:AddLine('Це ваше оголошення', 1, 1, 1, true)
                    elseif Finder.pending[self.groupKey] == 'pending' then
                        GameTooltip:AddLine('Заявка вже очікує відповіді', 1, 1, 1, true)
                    else
                        GameTooltip:AddLine(self.requiredRole and 'Натисніть, щоб подати заявку на цю роль' or 'Натисніть, щоб вибрати роль і подати заявку', 1, 1, 1, true)
                    end
                end
                GameTooltip:Show()
            end)
            slot:SetScript('OnLeave', function() GameTooltip:Hide() end)
            slot:SetScript('OnClick', function(self)
                local group = self.groupKey and Finder.groups[self.groupKey]
                if not group or self.member or group.closed or group.owner == Finder.identity
                    or #group.members >= group.maxSize or Finder.pending[self.groupKey] == 'pending' then return end
                for _, name in ipairs(group.members) do if name == Finder.identity then return end end
                if self.requiredRole then
                    if Finder:Apply(group.owner, group.id, self.requiredRole) then Finder:Changed(); refresh()
                    else print('Old Kraken: місце вже зайняте або заявку не вдалося надіслати.') end
                    return
                end
                f.slotMenu.groupKey = self.groupKey
                ToggleDropDownMenu(1, nil, f.slotMenu, self, 0, 0)
                local list = _G.DropDownList1
                if list and list:IsShown() then
                    if not list.oldKrakenRestoreHook then
                        list:HookScript('OnHide', function(frame)
                            if frame.oldKrakenStrata then frame:SetFrameStrata(frame.oldKrakenStrata); frame.oldKrakenStrata = nil end
                        end)
                        list.oldKrakenRestoreHook = true
                    end
                    if not list.oldKrakenStrata then list.oldKrakenStrata = list:GetFrameStrata() end
                    list:SetFrameStrata('FULLSCREEN_DIALOG')
                end
            end)
            card.slots[slotIndex] = slot
        end
        f.rows[i] = card
        local remove = CreateFrame('Button', nil, f)
        remove:SetSize(24, 23)
        remove:SetPoint('TOPLEFT', f, 'TOPLEFT', 514, -65-(i-1)*82)
        -- Draw a small trash can using native textures, including on Forever clients
        -- that do not provide the newer delete-icon atlas.
        local function piece(x, y, width, height)
            local texture = remove:CreateTexture(nil, 'ARTWORK')
            texture:SetColorTexture(0.9, 0.32, 0.3, 1)
            texture:SetSize(width, height)
            texture:SetPoint('TOPLEFT', remove, 'TOPLEFT', x, -y)
        end
        piece(6, 6, 12, 2); piece(9, 4, 6, 2)
        piece(7, 9, 2, 9); piece(15, 9, 2, 9); piece(7, 17, 10, 2)
        remove:SetScript('OnClick', function()
            local entry = f.visible and f.visible[index + offset]
            local group = entry and Finder.groups[entry.key]
            if group and tab == 'applications' and Finder.pending[entry.key] then
                if Finder:DismissApplication(group.owner, group.id) then
                    if selected == entry.key then selected = nil end
                    Finder:Changed(); refresh()
                else print('Old Kraken: не вдалося відкликати заявку. Перевірте зв’язок.') end
                return
            end
            if not group or group.owner ~= Finder.identity then return end
            if Finder:Delete(group.id) then
                if selected == entry.key then selected = nil end
                Finder:Changed()
                refresh()
            else
                print('Old Kraken: не вдалося видалити групу. Перевірте зв’язок.')
            end
        end)
        remove:SetScript('OnEnter', function(self)
            if GameTooltip then
                local entry = f.visible and f.visible[index + offset]
                local status = entry and tab == 'applications' and Finder.pending[entry.key]
                local label = status == 'pending' and 'Відкликати заявку'
                    or (status and 'Прибрати заявку зі списку' or 'Видалити групу')
                GameTooltip:SetOwner(self, 'ANCHOR_RIGHT'); GameTooltip:SetText(label); GameTooltip:Show()
            end
        end)
        remove:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
        remove:Hide()
        f.deleteButtons[i] = remove
    end
    f.previousPageButton = button(f, '‹', 18, -313, 80, function() offset=math.max(0, offset-CARDS_PER_PAGE); refresh() end, 36)
    f.nextPageButton = button(f, '›', 116, -313, 80, function() if f.visible and offset+CARDS_PER_PAGE < #f.visible then offset=offset+CARDS_PER_PAGE end; refresh() end, 36)
    f.listPage = f:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    f.listPage:SetPoint('TOPLEFT', f, 'TOPLEFT', 96, -323)
    f.listPage:SetWidth(44); f.listPage:SetJustifyH('CENTER')
    f.detailsScroll = CreateFrame('ScrollFrame', nil, f, 'UIPanelScrollFrameTemplate')
    f.detailsScroll:SetPoint('TOPLEFT', f, 'TOPLEFT', 550, -70); f.detailsScroll:SetSize(300, 175)
    local previousDetailsScroll=f.detailsScroll:GetScript('OnVerticalScroll')
    local detailsScrollPending=false
    f.detailsScroll:SetScript('OnVerticalScroll',function(self,value)
        if previousDetailsScroll then previousDetailsScroll(self,value) end
        if detailsScrollPending then return end
        local function update() detailsScrollPending=false; refresh() end
        if C_Timer and C_Timer.After then detailsScrollPending=true; C_Timer.After(0,update) else update() end
    end)
    f.detailsContent = CreateFrame('Frame', nil, f.detailsScroll)
    f.detailsContent:SetSize(300, 86); f.detailsScroll:SetScrollChild(f.detailsContent)
    f.details = f.detailsContent:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
    f.details:SetPoint('TOPLEFT'); f.details:SetWidth(300); f.details:SetJustifyH('LEFT'); f.details:SetJustifyV('TOP')
    f.memberRows = {}
    f.requestsButton = button(f, 'Заявки', 550, -288, 150, function()
        if requestsWindow and requestsWindow:IsShown() then requestsWindow:Hide(); refresh() else showRequests() end
    end)
    f.searchFilter = input(f, 'Пошук за назвою або автором', 20, -350, 260, '')
    f.searchFilter:SetScript('OnTextChanged', function() offset=0; refresh() end)
    f.dungeonFilter = dropdown(f, 285, -368, 250, activityOptions,
        function() return filterDungeon end, function(value) filterDungeon=value; offset=0; refresh() end)
    f.dungeonFilterLabel = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    f.dungeonFilterLabel:SetPoint('TOPLEFT', f, 'TOPLEFT', 285, -350); f.dungeonFilterLabel:SetText('Підземелля / рейд')
    f.levelFilter = input(f, 'Фільтр рівня', 20, -465, 80, '')
    f.levelFilter:SetScript('OnTextChanged', refresh)
    f.categoryFilter = dropdown(f, 110, -485, 155, choices(categories, categoryLabels, {value='all', label='Усі категорії'}),
        function() return filterCategory end, function(value) filterCategory=value; offset=0; refresh() end)
    f.roleFilter = dropdown(f, 270, -485, 125, choices({'tank','healer','dps','flex'}, coloredRoleLabels, {value='', label='Усі ролі'}),
        function() return filterRole end, function(value) filterRole=value; offset=0; refresh() end)
    f.freeFilter = dropdown(f, 400, -485, 135, {{value=false, label='Усі групи'}, {value=true, label='Є місця'}},
        function() return filterFree end, function(value) filterFree=value; offset=0; refresh() end)
    f.filterControls = {
        f.searchFilter, f.searchFilter.label, f.dungeonFilter, f.dungeonFilterLabel,
        f.levelFilter, f.levelFilter.label, f.categoryFilter, f.roleFilter, f.freeFilter,
    }
    f.titleBox = input(f, 'Назва', 20, -330, 240, '')
    f.descriptionBox = input(f, 'Опис', 275, -330, 250, '')
    f.maxBox = input(f, 'Місць', 20, -385, 65, '5')
    f.minBox = input(f, 'Мін. рівень', 105, -385, 80, '1')
    f.maxLevelBox = input(f, 'Макс. рівень', 205, -385, 80, '60')
    f.createFields = {f.titleBox, f.descriptionBox, f.maxBox, f.minBox, f.maxLevelBox}
    local autoDungeonTitle
    f.categoryButton = dropdown(f, 305, -408, 140, choices(categories, categoryLabels),
        function() return category end, function(value)
            local previousCategory=category
            category=value
            if category ~= previousCategory then
                if autoDungeonTitle and f.titleBox:GetText() == autoDungeonTitle then f.titleBox:SetText('') end
                autoDungeonTitle=nil
                dungeon=''; f.dungeonSelection:SetText('Без конкретного підземелля')
            end
            if category == 'dungeon' then
                f.maxBox:SetText('5')
                if role == 'flex' or role == '' then role='dps'; UIDropDownMenu_SetText(f.roleButton, roleLabel(role)) end
            end
            refresh()
        end)
    f.categoryLabel = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    f.categoryLabel:SetPoint('TOPLEFT', f, 'TOPLEFT', 305, -389); f.categoryLabel:SetText('Категорія')
    f.roleButton = dropdown(f, 550, -330, 150, function()
        local allowed={}
        for _,value in ipairs(category == 'dungeon' and {'tank','healer','dps'} or roles) do
            if Finder:CanPerformRole(Finder.identity,value) then allowed[#allowed+1]=value end
        end
        return choices(allowed, coloredRoleLabels)
    end,
        function() return role end, function(value) role=value end)
    f.roleLabel = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    f.roleLabel:SetPoint('TOPLEFT', f, 'TOPLEFT', 550, -313); f.roleLabel:SetText('Роль')
    local function selectActivity(value)
        local title = f.titleBox:GetText()
        local replaceTitle = title == '' or (autoDungeonTitle and title == autoDungeonTitle)
        dungeon=value
        if replaceTitle then
            autoDungeonTitle = value ~= '' and dungeonLabels[value] or nil
            f.titleBox:SetText(autoDungeonTitle or '')
        else autoDungeonTitle=nil end
        local recommended = dungeonLevels[value]
        if recommended then
            f.minBox:SetText(tostring(recommended.min)); f.maxLevelBox:SetText(tostring(recommended.max))
        end
        f.dungeonSelection:SetText(value~='' and dungeonLabels[value] or 'Без конкретного підземелля')
        f.UpdateActivityCards()
        refresh()
    end
    -- An inline, clipped three-column grid. No popup or additional click is needed.
    local picker=CreateFrame('Frame',nil,f)
    picker:SetSize(840,450); picker:SetPoint('TOPLEFT',f,'TOPLEFT',18,-64)
    picker:EnableMouse(true); picker:EnableMouseWheel(true)
    local background=picker:CreateTexture(nil,'BACKGROUND')
    background:SetAllPoints(picker); background:SetColorTexture(0.035,0.04,0.05,1)
    picker.heading=picker:CreateFontString(nil,'OVERLAY','GameFontNormal')
    picker.heading:SetPoint('TOPLEFT',picker,'TOPLEFT',10,-9)
    local hint=picker:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    hint:SetPoint('TOPLEFT',picker,'TOPLEFT',160,-11)
    hint:SetText('Підсвічено під ваш рівень · прокрутка коліщатком')
    picker.clear=button(picker,'Без конкретного підземелля',605,-5,225,function() selectActivity('') end)
    local clip=CreateFrame('Frame',nil,picker)
    clip:SetPoint('TOPLEFT',picker,'TOPLEFT',6,-36); clip:SetSize(808,407)
    if clip.SetClipsChildren then pcall(clip.SetClipsChildren,clip,true) end
    local content=CreateFrame('Frame',nil,clip)
    content:SetPoint('TOPLEFT',clip,'TOPLEFT',0,0); content:SetSize(808,1)
    picker.clip=clip; picker.content=content; picker.cards={}; picker.offset=0; picker.viewportHeight=407; picker.fullHeight=1
    function picker:ScrollTo(value)
        local maximum=math.max(0,(self.fullHeight or 0)-(self.viewportHeight or 407))
        self.offset=math.max(0,math.min(maximum,value or 0))
        content:ClearAllPoints(); content:SetPoint('TOPLEFT',clip,'TOPLEFT',0,self.offset)
    end
    local function scrollActivities(_,delta) picker:ScrollTo(picker.offset-delta*70) end
    picker:SetScript('OnMouseWheel',scrollActivities)
    clip:EnableMouseWheel(true); clip:SetScript('OnMouseWheel',scrollActivities)
    f.activityPicker=picker
    picker:Hide()
    f.dungeonSelection=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    f.dungeonSelection:SetPoint('TOPLEFT',f,'TOPLEFT',460,-408)
    f.dungeonSelection:SetSize(350,30); f.dungeonSelection:SetJustifyH('LEFT')
    f.dungeonSelection:SetText('Без конкретного підземелля')
    f.UpdateActivityCards=function()
        picker.heading:SetText(category=='raid' and 'Оберіть рейд' or 'Куди йдемо?')
        local level=type(UnitLevel)=='function' and tonumber((UnitLevel('player'))) or 0
        level=level or 0
        local count=0
        local firstFit,selectedIndex
        for _,entry in ipairs(catalog[category] or catalog.dungeon) do
            if entry.value~='' then
                count=count+1
                local card=picker.cards[count]
                if not card then
                    card=CreateFrame('Button',nil,picker.content)
                    card:SetSize(258,64)
                    card:SetPoint('TOPLEFT',picker.content,'TOPLEFT',((count-1)%3)*270,-math.floor((count-1)/3)*70)
                    card.fill=card:CreateTexture(nil,'BACKGROUND'); card.fill:SetAllPoints(card)
                    card.edges={}
                    for _,side in ipairs({'TOP','BOTTOM','LEFT','RIGHT'}) do
                        local edge=card:CreateTexture(nil,'OVERLAY')
                        if side=='TOP' or side=='BOTTOM' then
                            edge:SetPoint(side..'LEFT',card,side..'LEFT',0,0); edge:SetPoint(side..'RIGHT',card,side..'RIGHT',0,0); edge:SetHeight(1)
                        else
                            edge:SetPoint('TOP'..side,card,'TOP'..side,0,0); edge:SetPoint('BOTTOM'..side,card,'BOTTOM'..side,0,0); edge:SetWidth(1)
                        end
                        card.edges[#card.edges+1]=edge
                    end
                    card.art=card:CreateTexture(nil,'ARTWORK'); card.art:SetPoint('TOPLEFT',card,'TOPLEFT',1,-1); card.art:SetSize(62,62)
                    card.title=card:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
                    card.title:SetPoint('TOPLEFT',card,'TOPLEFT',71,-8); card.title:SetSize(177,28); card.title:SetJustifyH('LEFT')
                    card.levels=card:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
                    card.levels:SetPoint('BOTTOMLEFT',card,'BOTTOMLEFT',71,7); card.levels:SetSize(177,16); card.levels:SetJustifyH('LEFT')
                    local hover=card:CreateTexture(nil,'HIGHLIGHT'); hover:SetAllPoints(card); hover:SetColorTexture(1,0.8,0.3,0.12)
                    card:SetHighlightTexture(hover)
                    card:EnableMouseWheel(true); card:SetScript('OnMouseWheel',scrollActivities)
                    card:SetScript('OnClick',function(self) if self.entry then selectActivity(self.entry.value) end end)
                    card:SetScript('OnEnter',function(self)
                        if GameTooltip and self.entry then
                            GameTooltip:SetOwner(self,'ANCHOR_RIGHT'); GameTooltip:SetText(self.entry.label)
                            GameTooltip:AddLine('Рекомендовані рівні: '..self.entry.min..'–'..self.entry.max,1,1,1,true)
                            GameTooltip:Show()
                        end
                    end)
                    card:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
                    picker.cards[count]=card
                end
                local fits=level==0 or (entry.min and entry.max and level>=entry.min-2 and level<=entry.max+2)
                if fits and not firstFit then firstFit=count end
                if entry.value==dungeon then selectedIndex=count end
                card.entry=entry; card.fitsLevel=fits and true or false
                catalog.SetArtwork(card.art,entry.value); card.art:SetDesaturated(not fits); card.art:SetAlpha(fits and 1 or 0.65)
                card.title:SetText(entry.label)
                card.title:SetTextColor(fits and 1 or 0.8,fits and 0.91 or 0.8,fits and 0.65 or 0.8)
                card.levels:SetText(entry.min..'–'..entry.max..(fits and '  |cff69dc8cпід ваш рівень|r' or ''))
                card.fill:SetColorTexture(fits and 0.16 or 0.06,fits and 0.12 or 0.065,0.06,1)
                card.selected=entry.value==dungeon
                local r,g,b=0.23,0.25,0.28
                if card.selected then r,g,b=1,0.75,0.2
                elseif fits then r,g,b=0.65,0.49,0.18 end
                for _,edge in ipairs(card.edges) do edge:SetColorTexture(r,g,b,1) end
                card:Show()
            end
        end
        for i=count+1,#picker.cards do picker.cards[i].entry=nil; picker.cards[i]:Hide() end
        picker.fullHeight=math.max(1,math.ceil(count/3)*70)
        picker.content:SetHeight(picker.fullHeight)
        if picker.category~=category then
            local target=selectedIndex or firstFit
            picker.offset=target and math.max(0,math.floor((target-1)/3)*70-70) or 0
            picker.category=category
        end
        picker:ScrollTo(picker.offset)
    end
    f.dungeonLabel = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    f.dungeonLabel:SetPoint('TOPLEFT', f, 'TOPLEFT', 460, -389); f.dungeonLabel:SetText('Підземелля')
    f.createButton = button(f, 'Створити', 550, -455, 150, function()
        local ok = Finder:Create(f.titleBox:GetText(), category, f.descriptionBox:GetText(), f.maxBox:GetText(), f.minBox:GetText(), f.maxLevelBox:GetText(), role, dungeon)
        if ok then Finder:Changed(); tab='mine'; refresh()
        else print('Old Kraken: перевірте поля, доступність ролі та стан зв’язку. Для підземелля потрібна роль танка, лікаря або DPS.') end
    end, nil, 'primary')
    f.advancedCreation=false
    local footer=CreateFrame('Frame',nil,f)
    footer:SetSize(844,46); footer:SetPoint('TOPLEFT',f,'TOPLEFT',18,-527)
    local footerFill=footer:CreateTexture(nil,'BACKGROUND'); footerFill:SetAllPoints(footer); footerFill:SetColorTexture(0.055,0.06,0.075,1)
    f.creationFooter=footer
    f.creationArt=footer:CreateTexture(nil,'ARTWORK'); f.creationArt:SetSize(36,28); f.creationArt:SetPoint('TOPLEFT',footer,'TOPLEFT',3,-8)
    f.dungeonSelection:SetParent(footer); f.dungeonSelection:ClearAllPoints()
    f.dungeonSelection:SetPoint('TOPLEFT',footer,'TOPLEFT',45,-7); f.dungeonSelection:SetSize(177,32)
    f.creationRoles={}
    for i,value in ipairs({'tank','healer','dps','flex'}) do
        local chosen=value
        local control=button(footer,catalog.roleIcons[value] or 'Гн.',230+(i-1)*34,-8,30,function() role=chosen; refresh() end,28)
        control.role=value
        control.active=control:CreateTexture(nil,'OVERLAY')
        control.active:SetPoint('BOTTOMLEFT',control,'BOTTOMLEFT',1,1); control.active:SetSize(28,2); control.active:SetColorTexture(1,0.78,0.25,1)
        control:SetScript('OnEnter',function(self) if GameTooltip then GameTooltip:SetOwner(self,'ANCHOR_TOP'); GameTooltip:SetText(roleLabel(chosen)); GameTooltip:Show() end end)
        control:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
        f.creationRoles[i]=control
    end
    f.descriptionBox:SetParent(footer); f.descriptionBox:ClearAllPoints()
    f.descriptionBox:SetPoint('TOPLEFT',footer,'TOPLEFT',373,-8); f.descriptionBox:SetSize(207,28)
    f.commentHint=footer:CreateFontString(nil,'OVERLAY','GameFontDisableSmall')
    f.commentHint:SetPoint('LEFT',f.descriptionBox,'LEFT',6,0); f.commentHint:SetText('Коментар')
    f.descriptionBox:SetScript('OnTextChanged',function(self) f.commentHint:SetShown(self:GetText()=='') end)
    f.creationOptionsButton=button(footer,'Деталі',590,-8,88,function() f.advancedCreation=not f.advancedCreation; refresh() end,28)
    f.createButton:SetParent(footer); f.createButton:ClearAllPoints()
    f.createButton:SetPoint('TOPLEFT',footer,'TOPLEFT',688,-8); f.createButton:SetSize(150,28)
    local options=CreateFrame('Frame',nil,f)
    options:SetSize(840,82); options:SetPoint('TOPLEFT',f,'TOPLEFT',18,-440)
    local optionsFill=options:CreateTexture(nil,'BACKGROUND'); optionsFill:SetAllPoints(options); optionsFill:SetColorTexture(0.055,0.06,0.075,1)
    f.creationOptions=options
    local fields={{f.titleBox,12,240},{f.maxBox,267,65},{f.minBox,348,75},{f.maxLevelBox,438,75}}
    for _,layout in ipairs(fields) do
        local box=layout[1]; box:SetParent(options); box:ClearAllPoints()
        box:SetPoint('TOPLEFT',options,'TOPLEFT',layout[2],-29); box:SetSize(layout[3],24)
        box.label:SetParent(options); box.label:ClearAllPoints(); box.label:SetPoint('BOTTOMLEFT',box,'TOPLEFT',0,3)
    end
    f.categoryButton:SetParent(options); f.categoryButton:ClearAllPoints(); f.categoryButton:SetPoint('TOPLEFT',options,'TOPLEFT',535,-26)
    f.categoryLabel:SetParent(options); f.categoryLabel:ClearAllPoints(); f.categoryLabel:SetPoint('TOPLEFT',options,'TOPLEFT',550,-12)
    f.LayoutCreation=function()
        local height=f.advancedCreation and 370 or 450
        picker:SetHeight(height); picker.viewportHeight=height-43
        clip:SetHeight(picker.viewportHeight); picker:ScrollTo(picker.offset)
    end
    options:Hide(); footer:Hide()
    f.applyButton = button(f, 'Подати заявку', 550, -385, 140, function()
        local g=selected and Finder.groups[selected]
        if g and Finder:Apply(g.owner, g.id, role) then Finder:Changed(); refresh()
        elseif g then print('Old Kraken: місце для цієї ролі зайняте або заявку не вдалося надіслати.') end
    end, nil, 'primary')
    f.applicationActionButton = button(f, 'Відкликати', 700, -385, 140, function()
        local g=selected and Finder.groups[selected]
        if not g or g.owner == Finder.identity or not Finder.pending[selected] then return end
        if Finder:DismissApplication(g.owner, g.id) then
            Finder:Changed(); selected=nil; refresh()
        else print('Old Kraken: не вдалося обробити заявку. Перевірте зв’язок.') end
    end)
    f.cancelButton = button(f, 'Закрити набір', 550, -253, 140, function()
        local g=selected and Finder.groups[selected]
        if g and g.owner==Finder.identity and Finder:Cancel(g.id) then Finder:Changed(); refresh() end
    end)
    f.bumpButton = button(f, 'Оновити набір', 700, -253, 150, function()
        local group = selected and Finder.groups[selected]
        if not group or group.owner ~= Finder.identity or group.closed then return end
        local ok, reason, seconds = Finder:Reannounce(group.id)
        if ok then print('Old Kraken: повторне оголошення додано до черги гільдії.')
        elseif reason == 'cooldown' then print('Old Kraken: повторити оголошення можна через ' .. seconds .. ' с.')
        else print('Old Kraken: не вдалося надіслати оголошення. Перевірте зв’язок.') end
        UpdateReannounceButton(f.bumpButton)
    end)
    f.bumpButton:SetScript('OnUpdate', function(self, elapsed)
        self.countdownElapsed = (self.countdownElapsed or 0) + elapsed
        if self.countdownElapsed < 0.25 then return end
        self.countdownElapsed = 0
        UpdateReannounceButton(self)
    end)
    for _, item in ipairs({{f.cancelButton, 'Закрити набір: оголошення зникне з відкритих груп.'}, {f.bumpButton, 'Повторно сповістити гільдію про набір. Інтервал — 5 хвилин.'}}) do
        local control, help = item[1], item[2]
        control:SetScript('OnEnter', function(self) if GameTooltip then GameTooltip:SetOwner(self, 'ANCHOR_RIGHT'); GameTooltip:SetText(help); GameTooltip:Show() end end)
        control:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
    end
    return f
end

function Finder:Show()
    if not self.active then print('Old Kraken: пошук груп не ініціалізовано.') return end
    refreshPeople()
    if OldKraken.UIHub then
        OldKraken.UIHub:ShowPage('groups')
    else
        if not window then window=createWindow() end
        window:Show()
    end
    refresh()
end

function Finder:Toggle()
    if OldKraken.UIHub and OldKraken.UIHub.frame and OldKraken.UIHub.frame:IsShown()
        and OldKraken.UIHub.currentPage == 'groups' then
        OldKraken.UIHub.frame:Hide()
    elseif window and window:IsShown() and not OldKraken.UIHub then
        window:Hide()
    else
        self:Show()
    end
end
if OldKraken.UIHub then
    OldKraken.UIHub:RegisterPage('groups', 'Групи', '02', function(parent)
        if not window then window=createWindow(parent) end
        return window
    end)
end
local peopleDirty=false
local scheduleRefreshPending=false
local function scheduleRefresh()
    if scheduleRefreshPending then return end
    if not ((window and window:IsShown()) or (requestsWindow and requestsWindow:IsShown())) then return end
    local function flush()
        scheduleRefreshPending=false
        if (window and window:IsShown()) or (requestsWindow and requestsWindow:IsShown()) then if peopleDirty then refreshPeople(); peopleDirty=false end; refresh(); refreshRequests() end
    end
    if C_Timer and C_Timer.After then scheduleRefreshPending=true; C_Timer.After(0.15,flush) else flush() end
end
OldKraken:On('GROUP_FINDER_CHANGED', scheduleRefresh)
local peopleEvents = CreateFrame('Frame')
peopleEvents:RegisterEvent('GUILD_ROSTER_UPDATE')
peopleEvents:RegisterEvent('GROUP_ROSTER_UPDATE')
peopleEvents:SetScript('OnEvent', function() peopleDirty=true; scheduleRefresh() end)
OldKraken:On('GROUP_FINDER_ALERT_SETTING', function()
    if groupAlert and groupAlert.kind == 'group' and not Finder:GroupAlertsEnabled() then groupAlert:Hide() end
    refresh()
end)

local alertCaptions = {
    group='НОВЕ ОГОЛОШЕННЯ', request='НОВА ЗАЯВКА', decision='СТАН ЗАЯВКИ',
    event='ПОДІЯ ГІЛЬДІЇ', event_signup='ЗАПИС НА ПОДІЮ', workshop='МАЙСТЕРНЯ',
}
local alertActions = {
    group='Клік — відкрити групу', request='Клік — мої оголошення',
    decision='Клік — переглянути заявку', event='Клік — відкрити подію',
    event_signup='Клік — відкрити подію', workshop='Клік — відкрити замовлення',
}

local function paintAlertRoster(group)
    groupAlert.roleSlots=groupAlert.roleSlots or {}
    local slots={}
    if group.category=='dungeon' and group.maxSize==5 then slots=Finder:DungeonSlots(group)
    else
        for i=1,math.min(5,group.maxSize) do
            local member=group.members[i]
            slots[i]={member=member,role='flex',memberRole=member and (i==1 and group.role or (group.memberRoles and group.memberRoles[member]) or '')}
        end
    end
    local atlas={tank={0,67/256,67/256,134/256},healer={67/256,134/256,0,67/256},dps={67/256,134/256,67/256,134/256}}
    for i=1,5 do
        local slot=slots[i]
        local control=groupAlert.roleSlots[i]
        if slot and not control then
            control=CreateFrame('Button',nil,groupAlert)
            control:SetSize(86,49); control:SetPoint('TOPLEFT',groupAlert,'TOPLEFT',82+(i-1)*91,-53)
            control.ring=control:CreateTexture(nil,'BACKGROUND'); control.ring:SetSize(30,30); control.ring:SetPoint('TOP',control,'TOP',0,0)
            control.ring:SetTexture('Interface\\AddOns\\OldKraken\\Media\\RoleSlot.tga')
            control.icon=control:CreateTexture(nil,'ARTWORK'); control.icon:SetSize(22,22); control.icon:SetPoint('CENTER',control.ring,'CENTER',0,0)
            control.label=control:CreateFontString(nil,'OVERLAY','GameFontHighlight')
            local fontPath,fontSize=control.label:GetFont()
            if fontPath then control.label:SetFont(fontPath,math.max(13,tonumber(fontSize) or 13),'OUTLINE') end
            control.label:SetShadowColor(0,0,0,1); control.label:SetShadowOffset(1,-1)
            control.label:SetPoint('TOPLEFT',control,'TOPLEFT',0,-32); control.label:SetSize(86,19); control.label:SetJustifyH('CENTER'); control.label:SetWordWrap(false)
            control:RegisterForClicks('LeftButtonUp','RightButtonUp')
            control:SetScript('OnClick',function(self,mouseButton)
                if GameTooltip then GameTooltip:Hide() end
                if mouseButton=='LeftButton' and self and not self.occupied then
                    local key=groupAlert.groupKey
                    local current=key and Finder.groups[key]
                    if not current or current.closed then
                        print('Old Kraken: набір уже недоступний.'); return
                    end
                    if Finder.pending[key]=='pending' then
                        print('Old Kraken: заявку вже подано; очікуйте рішення автора.'); return
                    end
                    if Finder:Apply(current.owner,current.id,self.role) then
                        Finder:Changed()
                        groupAlert:Hide()
                    else
                        print('Old Kraken: роль уже зайнята або заявку не вдалося надіслати.')
                    end
                    return
                end
                local click=groupAlert:GetScript('OnClick'); if click then click(groupAlert,mouseButton) end
            end)
            control:RegisterForDrag('LeftButton')
            control:SetScript('OnDragStart',function() local fn=groupAlert:GetScript('OnDragStart'); if fn then fn(groupAlert) end end)
            control:SetScript('OnDragStop',function() local fn=groupAlert:GetScript('OnDragStop'); if fn then fn(groupAlert) end end)
            control:SetScript('OnEnter',function(self)
                if GameTooltip then GameTooltip:SetOwner(self,'ANCHOR_TOP'); GameTooltip:SetText(self.tooltipText); GameTooltip:Show() end
            end)
            control:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
            groupAlert.roleSlots[i]=control
        end
        if control then
            control:SetShown(slot~=nil)
            if slot then
                local member=slot.member
                local displayedRole=member and (slot.memberRole or '') or slot.role
                local coords=atlas[displayedRole]
                control.memberName=member; control.role=displayedRole; control.occupied=member~=nil
                control:SetEnabled(member~=nil or Finder:CanPerformRole(Finder.identity,displayedRole))
                control.icon:SetTexture(coords and 'Interface\\LFGFrame\\UI-LFG-ICON-ROLES' or 'Interface\\Icons\\INV_Misc_QuestionMark')
                if coords then control.icon:SetTexCoord(unpack(coords)) else control.icon:SetTexCoord(0,1,0,1) end
                control.icon:SetDesaturated(not member); control.icon:SetAlpha(member and 1 or 0.4)
                local state=not member and 'Вільне місце' or (member==group.owner and 'Автор збору' or (group.partyObserved and (group.partyObserved[member] and 'У групі' or 'Резерв') or 'Стан групи невідомий'))
                if not member then control.ring:SetVertexColor(0.4,0.44,0.5)
                elseif group.partyObserved and member~=group.owner and not group.partyObserved[member] then control.ring:SetVertexColor(1,0.72,0.25)
                else control.ring:SetVertexColor(0.3,1,0.55) end
                control.label:SetText(member or roleLabel(slot.role))
                control.label:SetTextColor(member and 1 or 0.85,member and 1 or 0.88,member and 1 or 0.93)
                control.tooltipText=(member or 'Вільне місце')..'\n'..roleLabel(displayedRole)..' · '..state
                if not member then control.tooltipText=control.tooltipText..(Finder:CanPerformRole(Finder.identity,displayedRole) and '\nЛівий клік — подати заявку на цю роль.' or '\nЦя роль недоступна вашому класу.') end
            end
        end
    end
end

local function showAlert(title, subtitle, kind, key, dungeonId, rosterGroup)
    local isEvent = kind == 'event' or kind == 'event_signup'
    local isWorkshop = kind == 'workshop'
    print('|cff2ec4b6Old Kraken|r: ' .. title .. (subtitle ~= '' and (' · ' .. subtitle) or '') .. (isEvent and '. /okr events' or (isWorkshop and '. /okr orders' or '. /okr group')))
    if not groupAlert then
        groupAlert = CreateFrame('Button', nil, UIParent, 'UIPanelButtonTemplate')
        groupAlert.roleSlots = {}
        OldKraken.UIStyle.Button(groupAlert)
        groupAlert:SetSize(560, 100)
        groupAlert.alertAccent = groupAlert:CreateTexture(nil, 'ARTWORK')
        groupAlert.alertAccent:SetPoint('TOPLEFT', groupAlert, 'TOPLEFT', 2, -2)
        groupAlert.alertAccent:SetPoint('TOPRIGHT', groupAlert, 'TOPRIGHT', -2, -2)
        groupAlert.alertAccent:SetHeight(2)
        groupAlert.alertAccent:SetColorTexture(0.85, 0.5, 0.18, 0.9)
        groupAlert.alertArt = groupAlert:CreateTexture(nil, 'ARTWORK')
        groupAlert.alertArt:SetSize(60, 60)
        groupAlert.alertArt:SetPoint('LEFT', groupAlert, 'LEFT', 8, 0)
        groupAlert.alertCaption = groupAlert:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
        groupAlert.alertCaption:SetTextColor(1, 0.78, 0.35)
        groupAlert.alertCaption:SetHeight(14)
        groupAlert.alertTitle = groupAlert:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
        groupAlert.alertTitle:SetTextColor(0.94, 0.95, 0.96)
        groupAlert.alertTitle:SetHeight(22)
        groupAlert.alertTitle:SetWordWrap(false)
        groupAlert.alertSubtitle = groupAlert:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
        groupAlert.alertSubtitle:SetTextColor(0.9, 0.93, 0.97)
        groupAlert.alertSubtitle:SetShadowColor(0,0,0,1)
        groupAlert.alertSubtitle:SetShadowOffset(1,-1)
        local subtitleFont,subtitleSize=groupAlert.alertSubtitle:GetFont()
        if subtitleFont then groupAlert.alertSubtitle:SetFont(subtitleFont,math.max(13,tonumber(subtitleSize) or 13),'OUTLINE') end
        groupAlert.alertHint = groupAlert:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
        groupAlert.alertHint:SetTextColor(0.75,0.83,0.93)
        groupAlert.alertHint:SetJustifyH('LEFT')
        groupAlert.alertHint:SetWordWrap(false)
        local hintFont,hintSize=groupAlert.alertHint:GetFont()
        if hintFont then groupAlert.alertHint:SetFont(hintFont,math.max(12,tonumber(hintSize) or 12),'OUTLINE') end
        groupAlert.alertHint:SetShadowColor(0,0,0,1); groupAlert.alertHint:SetShadowOffset(1,-1)
        groupAlert.alertFooter=groupAlert:CreateTexture(nil,'BACKGROUND')
        groupAlert.alertFooter:SetColorTexture(0.025,0.045,0.075,0.9)
        groupAlert.alertSubtitle:SetWordWrap(true)
        groupAlert.alertCaption:SetPoint('TOPLEFT', groupAlert, 'TOPLEFT', 82, -10)
        groupAlert.alertTitle:SetPoint('TOPLEFT', groupAlert, 'TOPLEFT', 82, -28)
        groupAlert.alertTitle:SetPoint('RIGHT', groupAlert, 'RIGHT', -12, 0)
        groupAlert.alertSubtitle:SetPoint('TOPLEFT', groupAlert, 'TOPLEFT', 82, -51)
        groupAlert.alertSubtitle:SetPoint('BOTTOMRIGHT', groupAlert, 'BOTTOMRIGHT', -12, 8)
        groupAlert.alertCaption:SetJustifyH('LEFT')
        groupAlert.alertTitle:SetJustifyH('LEFT')
        groupAlert.alertSubtitle:SetJustifyH('LEFT')
        groupAlert.alertSubtitle:SetJustifyV('TOP')
        groupAlert:SetPoint('TOP', UIParent, 'TOP', 0, -160)
        groupAlert:SetFrameStrata('FULLSCREEN_DIALOG')
        groupAlert:SetFrameLevel(50)
        groupAlert:SetMovable(true)
        groupAlert:SetClampedToScreen(true)
        groupAlert:RegisterForDrag('LeftButton')
        groupAlert:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
        groupAlert:SetScript('OnDragStart', function(self)
            self.dragging = true
            self:StartMoving()
        end)
        groupAlert:SetScript('OnDragStop', function(self)
            self:StopMovingOrSizing()
            self.dragging = false
            self.remaining = ALERT_DURATION
            self:SetAlpha(1)
            local x, y = self:GetCenter()
            local px, py = UIParent:GetCenter()
            local settings = OldKraken.DB and OldKraken.DB.settings
            if x and y and px and py and type(settings) == 'table' then
                if type(settings.alertPositions) ~= 'table' then settings.alertPositions = {} end
                settings.alertPositions[self.positionKind] = {x=x-px, y=y-py}
            end
        end)
        groupAlert:SetScript('OnClick', function(self, button)
            local target = self.groupKey
            local alertKind = self.kind
            self:Hide()
            if button == 'RightButton' then return end
            if alertKind == 'workshop' then
                if OldKraken.WorkshopOrders then OldKraken.WorkshopOrders:Show(target) end
                return
            end
            if alertKind == 'event' or alertKind == 'event_signup' then
                if OldKraken.GuildEvents then OldKraken.GuildEvents:ShowEvent(target) end
                return
            end
            if target and Finder.groups[target] then
                local targetTab = alertKind == 'decision' and 'applications'
                    or (alertKind == 'group' and 'all' or 'mine')
                tab, selected, offset, requestOffset = targetTab, target, 0, 0
            elseif alertKind == 'group' then
                tab, selected, offset, requestOffset = 'all', nil, 0, 0
            end
            if requestsWindow then requestsWindow:Hide() end
            Finder:Show()
            if alertKind == 'request' then showRequests() end
        end)
        groupAlert:SetScript('OnUpdate', function(self, elapsed)
            if self.dragging or self:IsMouseOver() then
                self.remaining=ALERT_DURATION
                self:SetAlpha(1)
                return
            end
            self.remaining = (self.remaining or 0) - elapsed
            if self.remaining <= ALERT_FADE_DURATION then
                self:SetAlpha(math.max(0, self.remaining / ALERT_FADE_DURATION))
            end
            if self.remaining <= 0 then self:Hide() end
        end)
    end
    for _,control in ipairs(groupAlert.roleSlots or {}) do control:Hide() end
    local graphical=kind=='group' and rosterGroup~=nil
    groupAlert:SetSize(560,graphical and 166 or 112)
    groupAlert.kind, groupAlert.groupKey = kind, key
    local hasGroupArt = kind == 'group'
    groupAlert.alertArt:SetShown(hasGroupArt)
    if hasGroupArt then catalog.SetArtwork(groupAlert.alertArt, dungeonId) end
    groupAlert.positionKind = isWorkshop and 'workshop' or (isEvent and 'event' or (kind == 'group' and 'group' or 'request'))
    local settings = OldKraken.DB and OldKraken.DB.settings
    local positions = type(settings) == 'table' and settings.alertPositions
    local pos = type(positions) == 'table' and positions[groupAlert.positionKind]
    groupAlert:ClearAllPoints()
    if type(pos) == 'table' and type(pos.x) == 'number' and type(pos.y) == 'number'
        and pos.x == pos.x and pos.y == pos.y and math.abs(pos.x) < 10000 and math.abs(pos.y) < 10000 then
        groupAlert:SetPoint('CENTER', UIParent, 'CENTER', pos.x, pos.y)
    else
        groupAlert:SetPoint('TOP', UIParent, 'TOP', 0, -160)
    end
    local textLeft = hasGroupArt and 82 or 18
    groupAlert.alertCaption:ClearAllPoints()
    groupAlert.alertTitle:ClearAllPoints()
    groupAlert.alertSubtitle:ClearAllPoints()
    groupAlert.alertCaption:SetPoint('TOPLEFT', groupAlert, 'TOPLEFT', textLeft, -10)
    groupAlert.alertTitle:SetPoint('TOPLEFT', groupAlert, 'TOPLEFT', textLeft, -28)
    groupAlert.alertTitle:SetPoint('RIGHT', groupAlert, 'RIGHT', -12, 0)
    groupAlert.alertSubtitle:SetPoint('TOPLEFT', groupAlert, 'TOPLEFT', textLeft, -51)
    groupAlert.alertSubtitle:SetPoint('BOTTOMRIGHT', groupAlert, 'BOTTOMRIGHT', -12, 8)
    groupAlert.alertCaption:SetText(alertCaptions[kind] or 'OLD KRAKEN')
    groupAlert.alertTitle:SetText(title)
    groupAlert.alertFooter:ClearAllPoints()
    groupAlert.alertFooter:SetPoint('BOTTOMLEFT',groupAlert,'BOTTOMLEFT',textLeft-7,7)
    groupAlert.alertFooter:SetPoint('BOTTOMRIGHT',groupAlert,'BOTTOMRIGHT',-7,7)
    groupAlert.alertFooter:SetHeight(graphical and 54 or 58)
    groupAlert.alertHint:ClearAllPoints()
    groupAlert.alertHint:SetPoint('BOTTOMLEFT',groupAlert,'BOTTOMLEFT',textLeft,12)
    groupAlert.alertHint:SetPoint('RIGHT',groupAlert,'RIGHT',-12,0)
    groupAlert.alertHint:SetHeight(16)
    groupAlert.alertHint:SetText('|cff8ccfff'..(alertActions[kind] or 'Клік — відкрити')..'|r  |cffb0baca· перетягніть, щоб перемістити|r')
    groupAlert.alertSubtitle:SetPoint('BOTTOMRIGHT',groupAlert,'BOTTOMRIGHT',-12,34)
    if graphical then
        paintAlertRoster(rosterGroup)
        groupAlert.alertSubtitle:ClearAllPoints()
        groupAlert.alertSubtitle:SetPoint('TOPLEFT',groupAlert,'TOPLEFT',82,-108)
        groupAlert.alertSubtitle:SetPoint('BOTTOMRIGHT',groupAlert,'BOTTOMRIGHT',-12,34)
        local extra=#rosterGroup.members>5 and (' · ще учасників: '..(#rosterGroup.members-5)) or ''
        groupAlert.alertSubtitle:SetText('|cffffd36bУ складі: '..#rosterGroup.members..' із '..rosterGroup.maxSize..'|r  ·  |cff69dc8cВільних місць: '..math.max(0,rosterGroup.maxSize-#rosterGroup.members)..'|r'..extra)
        groupAlert.alertHint:SetText('|cff8ccfffВільна роль — подати заявку|r  ·  |cffe0e6efКлік по банеру — група|r')
    else
    groupAlert.alertSubtitle:SetText(subtitle)
    end
    groupAlert.remaining = ALERT_DURATION
    groupAlert:SetAlpha(1)
    groupAlert:Show()
    local now = type(GetTime) == 'function' and GetTime()
    if type(PlaySound) == 'function' and SOUNDKIT and SOUNDKIT.READY_CHECK
        and type(now) == 'number' and now - lastAlertSoundAt >= ALERT_SOUND_INTERVAL then
        lastAlertSoundAt = now
        pcall(PlaySound, SOUNDKIT.READY_CHECK)
    end
end

function Finder:PreviewAlert(kind)
    if kind == 'group' then
        showAlert('Гравець збирає: Назва групи', 'Склад 2/5 · Вільно місць: 3', 'group',nil,'rfc',{category='dungeon',maxSize=5,owner='Танк',role='tank',members={'Танк','Лікар'},memberRoles={['Лікар']='healer'}})
    elseif kind == 'request' then
        showAlert('Нова заявка від гравця', 'Танк · Назва групи', 'request')
    elseif kind == 'event' then
        showAlert('Назва події', 'Організатор · сьогодні о 20:00', 'event')
    elseif kind == 'workshop' then
        showAlert('Замовлення', 'Приклад сповіщення Майстерні', 'workshop')
    end
end

OldKraken:On('WORKSHOP_ORDER_NOTICE', function(title,subtitle,k)
    showAlert(title,subtitle,'workshop',k)
end)

OldKraken:On('GUILD_EVENTS_NEW', function(key, event)
    if not OldKraken.GuildEvents or not OldKraken.GuildEvents:AlertsEnabled() then return end
    local subtitle = event.owner .. ' · ' .. date('%d.%m.%Y %H:%M', event.when)
    showAlert('Нова подія: ' .. event.title, subtitle, 'event', key)
end)
OldKraken:On('GUILD_EVENTS_NEW_SIGNUP', function(key, event, name, role)
    refreshPeople()
    local signupRole=role=='flex' and 'Учасник' or roleLabel(role)
    showAlert('Новий запис: ' .. playerLabel(name), signupRole .. ' · ' .. event.title, 'event_signup', key)
end)
OldKraken:On('GUILD_EVENTS_CANCELLED', function(key, event)
    showAlert('Подію скасовано', event.title .. ' · Автор: ' .. event.owner, 'event_signup', key)
end)
OldKraken:On('GUILD_EVENTS_ALERT_SETTING', function()
    if groupAlert and groupAlert.kind=='event' and not OldKraken.GuildEvents:AlertsEnabled() then groupAlert:Hide() end
end)

OldKraken:On('GROUP_FINDER_NEW', function(group)
    if not Finder:GroupAlertsEnabled() then return end
    refreshPeople()
    local free = math.max(0, group.maxSize - #group.members)
    local actual = group.partyObserved and 1 or nil
    for i, name in ipairs(group.members) do
        if actual and i > 1 and group.partyObserved[name] then actual = actual + 1 end
    end
    local presence = actual and ('у групі ' .. actual .. ', резерв ' .. (#group.members - actual)) or 'стан групи невідомий'
    local summary = 'Склад ' .. #group.members .. '/' .. group.maxSize .. ' · ' .. presence
    local needed = 'Вільно місць: ' .. free .. ' · склад гнучкий'
    if group.category == 'dungeon' and group.maxSize == 5 then
        local missing = {tank=0, healer=0, dps=0}
        for _, slot in ipairs(Finder:DungeonSlots(group)) do if not slot.member then missing[slot.role] = missing[slot.role] + 1 end end
        needed = 'Вільні ролі: ' .. roleLabel('tank') .. ' ' .. missing.tank .. ', ' .. roleLabel('healer') .. ' ' .. missing.healer .. ', ' .. roleLabel('dps') .. ' ' .. missing.dps
    end
    local groupKey = group.owner .. '\001' .. group.id
    showAlert(playerLabel(group.owner) .. ' збирає: ' .. group.title, summary .. ' · ' .. needed, 'group', groupKey, group.dungeon, group)
end)

OldKraken:On('GROUP_FINDER_NEW_REQUEST', function(group, name, role)
    refreshPeople()
    showAlert('Нова заявка від ' .. playerLabel(name), roleLabel(role) .. '  |cff9ba9bc·|r  |cffffd36b' .. group.title .. '|r',
        'request', group.owner .. '\001' .. group.id)
    refreshRequests()
end)

OldKraken:On('GROUP_FINDER_APPLICATION_STATUS', function(group, status)
    if not group or status ~= 'reject' then return end
    refreshPeople()
    showAlert('Заявку відхилив ' .. playerLabel(group.owner), group.title, 'decision', group.owner .. '\001' .. group.id)
end)
