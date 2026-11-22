local T = OldKraken.Translate or function(text) return text end
-- Group Finder window and user actions.
local Finder = OldKraken.GroupFinder
local function memberSpecText(name)
    local comm = OldKraken.Communication
    local spec = name and comm and comm.GetRosterSpec and comm:GetRosterSpec(name)
    if spec and not (type(issecretvalue) == 'function' and issecretvalue(spec.name)) and type(spec.name) == 'string' and spec.name ~= '' then
        return OldKraken.LocalizeSpecName and OldKraken.LocalizeSpecName(spec.name) or spec.name
    end
end
local window, selected, requestsWindow
local refresh
local groupAlert
local refreshAlertRoster
local lastAlertSoundAt = -math.huge
local ALERT_DURATION, ALERT_FADE_DURATION, ALERT_SOUND_INTERVAL = 9, 1, 60
local tab = 'all'
local offset = 0
local requestOffset = 0
local editingDescriptionKey
local REQUESTS_PER_PAGE, CARDS_PER_PAGE = 5, 3
local category, role = 'dungeon', 'dps'
local filterCategory, filterRole, filterFree = 'all', '', false
local dungeon, filterDungeon = '', ''
local catalog = OldKraken.ActivityCatalog
local function UpdateReannounceButton(control)
    local group = selected and Finder.groups[selected]
    local remaining = group and Finder.GetReannounceRemaining and Finder:GetReannounceRemaining(group.id)
    if remaining and remaining > 0 then
        control:SetText(string.format(T('Анонс через %02d:%02d'), math.floor(remaining / 60), remaining % 60))
        control:SetEnabled(false)
    else
        control:SetText(T('Оновити набір'))
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
local function displayGroupTitle(group)
    if type(group) ~= 'table' then return '' end
    local title = type(group.title) == 'string' and group.title or ''
    if catalog and type(catalog.IsCanonicalTitle) == 'function' and catalog.IsCanonicalTitle(group.dungeon, title) then
        return dungeonLabels[group.dungeon] or title
    end
    return title
end
local function displayEventTitle(event)
    if OldKraken.GuildEvents and type(OldKraken.GuildEvents.DisplayTitle) == 'function' then
        return OldKraken.GuildEvents:DisplayTitle(event)
    end
    return type(event) == 'table' and type(event.title) == 'string' and event.title or ''
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

local roleIconIndex = {tank=0, healer=1, dps=2, flex=3}
local function setRoleIcon(texture, role)
    local index = roleIconIndex[role] or 3
    texture:SetTexture('Interface\\AddOns\\' .. OldKraken.name .. '\\Media\\RoleIcons.tga')
    texture:SetTexCoord(index / 4, (index + 1) / 4, 0, 1)
end
local ROLE_ICON_DARK = {0.04, 0.055, 0.08}
local SLOT_NEUTRAL = {0.35, 0.39, 0.46, 1}
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
    closed={text='ЗАКРИТО', color={0.70, 0.72, 0.76}},
    retry={text='ПОДАЙТЕ ЗНОВУ', color={1, 0.65, 0.25}},
}

local OFFLINE_APPLICATION_TTL = 300
local people, guildRosterLoaded, ownerOfflineSince, offlinePruneTimerPending = {}, false, {}, false
local refreshPeople
-- The model receives the owner in the identity form ("Name Surname"), while the
-- guild roster is keyed by another representation ("Name-Realm"), so a direct
-- lookup misses and the owner looks offline. Compare normalised parts instead.
-- No realm on either side is not a match: two characters may share a name on
-- different realms, and a false match could prune a live application.
local function ownerKey(name)
    if type(name) ~= 'string' then return nil end
    local character, realm = name:match('^([^-%s]+)[%-%s](.+)$')
    if not character or character == '' or not realm or realm == '' then return nil end
    return character .. '\1' .. realm:gsub('%-', ' ')
end
local indexedPeople, peopleIndex
local function ownerRecords()
    if indexedPeople == people then return peopleIndex end
    indexedPeople, peopleIndex = people, {}
    for name, rec in pairs(people) do
        local key = ownerKey(name)
        if key then peopleIndex[key] = rec end
    end
    return peopleIndex
end
local function ownerRecord(owner)
    if type(owner) ~= 'string' or owner == '' then return nil end
    local rec = people[owner]
    if rec then return rec end
    local key = ownerKey(owner)
    if not key then return nil end
    return ownerRecords()[key]
end
-- Three states, not two: only a confirmed offline record may expire an
-- application. A missing record is unknown, so the application is kept.
local function isOwnerOnline(owner)
    if not guildRosterLoaded or not owner or owner == Finder.identity then return true end
    local rec = ownerRecord(owner)
    return rec ~= nil and rec.online == true
end
local function isOwnerOffline(owner)
    if not guildRosterLoaded or not owner or owner == Finder.identity then return false end
    local rec = ownerRecord(owner)
    return rec ~= nil and rec.online == false
end
local function isGroupHiddenByOfflineOwner(key, group)
    if not guildRosterLoaded or not group or group.closed or group.hidden or group.owner == Finder.identity then return false end
    if not isOwnerOffline(group.owner) then return false end
    local since = ownerOfflineSince[key]
    local now = type(GetTime) == 'function' and GetTime() or 0
    return type(since) == 'number' and now - since >= OFFLINE_APPLICATION_TTL
end
function Finder:IsGroupHiddenByOfflineOwner(key, group)
    return isGroupHiddenByOfflineOwner(key, group)
end
local function pruneOfflineApplications()
    if not guildRosterLoaded then
        for key in pairs(ownerOfflineSince) do ownerOfflineSince[key] = nil end
        return
    end
    local now = type(GetTime) == 'function' and GetTime() or 0
    local changed, nextDelay = false, nil
    for key, group in pairs(Finder.groups or {}) do
        if type(group) == 'table' and not group.closed and not group.hidden and group.owner ~= Finder.identity then
            if isOwnerOffline(group.owner) then
                ownerOfflineSince[key] = ownerOfflineSince[key] or now
                local remaining = OFFLINE_APPLICATION_TTL - (now - ownerOfflineSince[key])
                if remaining > 0 and (not nextDelay or remaining < nextDelay) then nextDelay = remaining end
            else ownerOfflineSince[key] = nil end
        end
    end
    for key in pairs(Finder.pending or {}) do
        local group = Finder.groups and Finder.groups[key]
        if type(group) ~= 'table' then group = nil end
        local owner = type(group) == 'table' and group.owner or nil
        if not owner and type(key) == 'string' then owner = key:match('^([^\001]+)\001.+$') end
        if owner and owner ~= Finder.identity then
            if isOwnerOnline(owner) then
                ownerOfflineSince[key] = nil
            elseif isOwnerOffline(owner) then
                ownerOfflineSince[key] = ownerOfflineSince[key] or now
                local remaining = OFFLINE_APPLICATION_TTL - (now - ownerOfflineSince[key])
                if remaining <= 0 then
                    Finder.pending[key] = nil
                    if Finder.pendingVersions then Finder.pendingVersions[key] = nil end
                    if Finder.pendingRoles then Finder.pendingRoles[key] = nil end
                    if not group or group.closed or group.hidden then ownerOfflineSince[key] = nil end
                    changed = true
                elseif not nextDelay or remaining < nextDelay then
                    nextDelay = remaining
                end
            else
                -- Owner state is unknown, which is not the same as offline: keep
                -- the application and forget any half-counted offline window.
                ownerOfflineSince[key] = nil
            end
        else
            ownerOfflineSince[key] = nil
        end
    end
    for key in pairs(ownerOfflineSince) do
        local group = Finder.groups and Finder.groups[key]
        local openRemote = type(group) == 'table' and not group.closed and not group.hidden and group.owner ~= Finder.identity and isOwnerOffline(group.owner)
        if not openRemote and not (Finder.pending and Finder.pending[key]) then ownerOfflineSince[key] = nil end
    end
    if nextDelay and not offlinePruneTimerPending and C_Timer and type(C_Timer.After) == 'function' then
        offlinePruneTimerPending = true
        C_Timer.After(math.max(1, nextDelay), function()
            offlinePruneTimerPending = false
            refreshPeople()
            pruneOfflineApplications()
            if refresh then refresh() end
            if type(OldKraken.Fire) == 'function' then OldKraken:Fire('GROUP_FINDER_OFFLINE_CHANGED') end
        end)
    end
    if changed then Finder:Changed() end
end
refreshPeople = function()
    local nextPeople, rosterCount = {}, 0
    local nextPeopleIndex = {}
    if type(GetNumGuildMembers) == 'function' and type(GetGuildRosterInfo) == 'function' then
        local ok, count = pcall(GetNumGuildMembers)
        if ok and type(count) == 'number' then
            rosterCount = count
            for i = 1, count do
                pcall(function()
                    local name, _, _, level, _, _, _, _, isOnline, _, class = GetGuildRosterInfo(i)
                    if type(issecretvalue) == 'function' and (issecretvalue(name) or issecretvalue(level) or issecretvalue(class)) then return end
                    if type(name) == 'string' and name ~= '' then
                        local rec = {level=tonumber(level), class=class}
                        if not (type(issecretvalue) == 'function' and issecretvalue(isOnline)) and type(isOnline) == 'boolean' then
                            rec.online = isOnline
                        end
                        nextPeople[name] = rec
                        local key = ownerKey(name)
                        if key then nextPeopleIndex[key] = rec end
                    end
                end)
            end
        end
    end
    guildRosterLoaded = rosterCount > 0
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
                local key = ownerKey(name)
                local prev = nextPeople[name] or (key and nextPeopleIndex[key])
                local isConnected
                if type(UnitIsConnected) == 'function' then
                    local ok, connected = pcall(UnitIsConnected, unit)
                    if ok and not (type(issecretvalue) == 'function' and issecretvalue(connected)) and type(connected) == 'boolean' then
                        isConnected = connected
                    end
                end
                local online = prev and prev.online
                if isConnected == true then online = true
                elseif isConnected == false and online ~= true then online = false end
                local rec = prev or {}
                rec.class = class or rec.class
                rec.level = tonumber(level) or rec.level
                rec.online = online
                nextPeople[name] = rec
                if key then nextPeopleIndex[key] = rec end
            end)
        end
    end
    people = nextPeople
end

local function playerLabel(name)
    local info = ownerRecord(name)
    local classColor = info and type(info.class) == 'string' and RAID_CLASS_COLORS and RAID_CLASS_COLORS[info.class]
    local colored = name
    if classColor and classColor.r and classColor.g and classColor.b then
        colored = string.format('|cff%02x%02x%02x%s|r', math.floor(classColor.r * 255), math.floor(classColor.g * 255), math.floor(classColor.b * 255), name)
    end
    if info and info.level and info.level > 0 then colored = colored .. ' (' .. info.level .. ')' end
    return colored
end

local function roleLabel(value)
    return '|c' .. (roleColors[value] or roleColors['']) .. (roleLabels[value] or T('Невідома')) .. '|r'
end
local function roleChoiceLabel(value)
    local icon = (catalog and catalog.roleIcons and catalog.roleIcons[value]) or ''
    return (icon ~= '' and (icon .. ' ') or '') .. roleLabel(value)
end
local coloredRoleLabels = {}
for _, value in ipairs(roles) do coloredRoleLabels[value] = roleLabel(value) end

StaticPopupDialogs.OLDKRAKEN_REMOVE_MEMBER = {
    text = 'Видалити %s з групи? Якщо гравець у паті, аддон спробує виключити його з паті.',
    button1 = 'Видалити', button2 = 'Скасувати', timeout = 0,
    whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnAccept = function(_, callback) if type(callback) == 'function' then callback() end end,
}

local function button(parent, label, x, y, width, callback, height, variant, options)
    local b = CreateFrame('Button', nil, parent, 'UIPanelButtonTemplate')
    OldKraken.UIStyle.Button(b, variant, options)
    b:SetSize(width, height or 23); b:SetPoint('TOPLEFT', parent, 'TOPLEFT', x, y); b:SetText(label)
    b:SetScript('OnClick', callback)
    return b
end

local dropdownCount = 0
local function dropdown(parent, x, y, width, options, selectedValue, onSelect, styleOptions)
    dropdownCount = dropdownCount + 1
    local frame = CreateFrame('Frame', 'OldKrakenFinderSelect' .. dropdownCount, parent, 'UIDropDownMenuTemplate')
    OldKraken.UIStyle.Dropdown(frame, styleOptions or {rounded = true})
    frame:SetPoint('TOPLEFT', parent, 'TOPLEFT', x - 16, y + 3)
    frame:SetWidth(width + 32)
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
    local frameName = type(frame.GetName) == 'function' and frame:GetName()
    local label = frameName and _G[frameName .. 'Text']
    if label and OldKraken.UIStyle.Font then
        OldKraken.UIStyle.Font(label, 13)
        if label.SetShadowColor then label:SetShadowColor(0, 0, 0, 0.9) end
        if label.SetShadowOffset then label:SetShadowOffset(1, -1) end
    end
    local initial = type(options) == 'function' and options() or options
    for _, option in ipairs(initial) do
        if option.value == selectedValue() then UIDropDownMenu_SetText(frame, option.label); break end
    end
    return frame
end

local function availableRolesForContext(targetCategory)
    local out = {}
    local source = targetCategory == 'dungeon' and {'tank', 'healer', 'dps'} or roles
    for _, value in ipairs(source) do
        if Finder:CanPerformRole(Finder.identity, value) then out[#out + 1] = value end
    end
    return out
end

local function styleRoleSegment(b, active)
    local colors = OldKraken.UIStyle and OldKraken.UIStyle.Colors
    if not colors or type(b.fillParts) ~= 'table' then return end
    local fill = active and colors.primaryButton or colors.button
    local edge = active and colors.primaryButtonEdge or colors.buttonEdge
    if fill then for _, t in ipairs(b.fillParts) do t:SetVertexColor(fill[1], fill[2], fill[3], fill[4] or 1); t.color = fill end end
    if edge then for _, t in ipairs(b.ringParts or {}) do t:SetVertexColor(edge[1], edge[2], edge[3], edge[4] or 1); t.color = edge end end
end

local function createRoleSelector(parent, x, y, width)
    local selector = CreateFrame('Frame', nil, parent)
    selector:SetSize(width, 28)
    selector:SetPoint('TOPLEFT', parent, 'TOPLEFT', x, y)
    selector.buttons = {}
    selector.allowedRoles = {}
    selector.mode = 'none'
    selector.selectedRole = ''
    for i = 1, 4 do
        local b = CreateFrame('Button', nil, selector, 'UIPanelButtonTemplate')
        OldKraken.UIStyle.Button(b, nil, {rounded = true})
        b:SetSize(69, 28)
        b:SetScript('OnClick', function(self)
            if not self.role or not Finder:CanPerformRole(Finder.identity, self.role) then return end
            role = self.role
            selector:Update(selector.currentCategory)
        end)
        b:Hide()
        selector.buttons[i] = b
    end
    local badge = CreateFrame('Frame', nil, selector)
    OldKraken.UIStyle.Panel(badge, 0, 0, width, 28)
    badge:SetSize(width, 28)
    badge:SetPoint('TOPLEFT', selector, 'TOPLEFT', 0, 0)
    badge.text = badge:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(badge.text, 13) end
    badge.text:SetPoint('LEFT', badge, 'LEFT', 10, 0)
    badge.text:SetJustifyH('LEFT')
    badge:Hide()
    selector.badge = badge
    function selector:Update(targetCategory)
        self.currentCategory = targetCategory
        local allowed = availableRolesForContext(targetCategory)
        self.allowedRoles = allowed
        local valid = false
        for _, value in ipairs(allowed) do if value == role then valid = true; break end end
        if not valid or not Finder:CanPerformRole(Finder.identity, role) then
            local preferred = Finder:PreferredRole()
            local prefValid = false
            for _, value in ipairs(allowed) do if value == preferred then prefValid = true; break end end
            role = prefValid and preferred or (allowed[1] or '')
        end
        self.selectedRole = role
        if #allowed >= 2 then
            self.mode = 'buttons'
            self.badge:Hide()
            local gap = 6
            local btnW = math.floor((width - gap * (#allowed - 1)) / #allowed)
            for i = 1, 4 do
                local b = self.buttons[i]
                local r = allowed[i]
                if r then
                    b.role = r
                    b:SetSize(btnW, 28)
                    b:ClearAllPoints()
                    b:SetPoint('TOPLEFT', self, 'TOPLEFT', (i - 1) * (btnW + gap), 0)
                    b:SetText(roleChoiceLabel(r))
                    styleRoleSegment(b, r == role)
                    b:Show()
                else
                    b.role = nil
                    b:Hide()
                end
            end
        elseif #allowed == 1 then
            self.mode = 'badge'
            for i = 1, 4 do self.buttons[i].role = nil; self.buttons[i]:Hide() end
            self.badge.text:SetText(roleChoiceLabel(allowed[1]))
            self.badge:Show()
        else
            self.mode = 'none'
            for i = 1, 4 do self.buttons[i].role = nil; self.buttons[i]:Hide() end
            self.badge.text:SetText(T('|cff9aa5b1Немає доступної ролі|r'))
            self.badge:Show()
        end
    end
    return selector
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
                    id=id, name=name, role=applicantRole, title=displayGroupTitle(group),
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
    requestsWindow.count:SetText(T('Вхідні заявки (') .. #entries .. ')')
    for i, row in ipairs(requestsWindow.rows) do
        local entry = entries[requestOffset + i]
        row.entry = entry
        if entry then
            row.name:SetText(playerLabel(entry.name))
            row.roleStatus:SetText(roleLabel(entry.role or '') .. T(' |cff9ba9bc·|r |cffffc36bОчікує|r'))
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
    if not Finder.active then print(T('Old Kraken: пошук груп не ініціалізовано.')); return end
    if not window or not window:IsShown() then Finder:Show() end
    if not window or not window:IsShown() then return end
    if tab == 'create' then tab='mine'; selected=nil end
    refreshPeople()
    if not requestsWindow then
        local f = CreateFrame('Frame', 'OldKrakenRequestsFrame', window)
        f:Hide()
        local colors = OldKraken.UIStyle.Colors or {}
        f:SetSize(298, 384)
        if type(window.detailPanel) == 'table' then
            f:SetPoint('TOPLEFT', window.detailPanel, 'TOPLEFT', 16, -16)
            if type(f.SetFrameLevel) == 'function' then
                f:SetFrameLevel(((type(window.detailPanel.GetFrameLevel) == 'function' and window.detailPanel:GetFrameLevel()) or 1) + 5)
            end
        else
            f:SetPoint('TOPLEFT', window, 'TOPLEFT', 587, -119)
        end
        f:EnableMouse(true)
        f.count = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
        f.count:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, 0)
        if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(f.count, 14, true) end
        if colors.brandGold then f.count:SetTextColor(colors.brandGold[1], colors.brandGold[2], colors.brandGold[3]) end
        f.empty = f:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        f.empty:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, -32); f.empty:SetWidth(290); f.empty:SetJustifyH('LEFT'); f.empty:SetText(T('Нових заявок немає. Поверніться до деталей оголошення.'))
        if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(f.empty, 13) end
        if colors.mutedText then f.empty:SetTextColor(colors.mutedText[1], colors.mutedText[2], colors.mutedText[3]) end
        f.rows = {}
        for i=1, REQUESTS_PER_PAGE do
            local row = {}
            local y = -32 - (i - 1) * 64
            row.name = f:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
            row.name:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, y); row.name:SetSize(136, 18)
            row.name:SetJustifyH('LEFT'); row.name:SetWordWrap(false)
            if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(row.name, 13, true) end
            row.roleStatus = f:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
            row.roleStatus:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, y - 19); row.roleStatus:SetSize(136, 16)
            row.roleStatus:SetJustifyH('LEFT'); row.roleStatus:SetWordWrap(false)
            if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(row.roleStatus, 12) end
            row.group = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
            row.group:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, y - 36); row.group:SetSize(136, 15)
            row.group:SetJustifyH('LEFT'); row.group:SetWordWrap(false)
            if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(row.group, 11) end
            row.hover = CreateFrame('Frame', nil, f)
            row.hover:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, y); row.hover:SetSize(136, 52); row.hover:EnableMouse(true)
            row.hover:SetScript('OnEnter', function(self)
                if not row.entry then return end
                GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
                GameTooltip:SetText(playerLabel(row.entry.name) .. ' · ' .. roleLabel(row.entry.role))
                GameTooltip:AddLine(T('|cffffc36bОчікує|r'), 1, 1, 1)
                GameTooltip:AddLine(row.entry.title, 1, 1, 1, true)
                GameTooltip:AddLine(T('|cff68d98cНатисніть, щоб шепнути|r'), 1, 1, 1)
                GameTooltip:Show()
            end)
            row.hover:SetScript('OnLeave', function() GameTooltip:Hide() end)
            row.hover:SetScript('OnMouseUp', function(_, btn)
                if btn == 'LeftButton' and row.entry and row.entry.name and type(ChatFrame_SendTell) == 'function' then
                    ChatFrame_SendTell(row.entry.name)
                end
            end)
            local function decide(accept)
                local entry = row.entry
                if not entry then return end
                local group = Finder.groups[Finder.identity .. '\001' .. entry.id]
                if not group or group.closed or not Finder.requests[entry.id] or Finder.requests[entry.id][entry.name] == nil then refreshRequests(); return end
                if Finder:Decide(entry.id, entry.name, accept) then
                    Finder:Changed()
                    if accept then invitePlayer(entry.name) end
                    refreshRequests()
                else print(T('Old Kraken: не вдалося обробити заявку. Перевірте наявність місць і зв’язок.')) end
            end
            row.accept = button(f, T('Прийняти'), 142, y - 12, 74, function() decide(true) end, 26, 'primary', {rounded = true})
            row.reject = button(f, T('Відхилити'), 222, y - 12, 76, function() decide(false) end, 26, 'danger', {rounded = true})
            for _, btn in ipairs({row.accept, row.reject}) do
                local lbl = type(btn.GetFontString) == 'function' and btn:GetFontString()
                if type(lbl) == 'table' and OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(lbl, 12) end
            end
            row.accept:SetScript('OnEnter', function(self) if GameTooltip then GameTooltip:SetOwner(self, 'ANCHOR_RIGHT'); GameTooltip:SetText(row.entry and not Finder:CanPerformRole(row.entry.name,row.entry.role) and T('Клас учасника не може виконувати цю роль або ще невідомий.') or T('Прийняти заявку')); GameTooltip:Show() end end)
            row.reject:SetScript('OnEnter', function(self) if GameTooltip then GameTooltip:SetOwner(self, 'ANCHOR_RIGHT'); GameTooltip:SetText(T('Відхилити заявку')); GameTooltip:Show() end end)
            row.accept:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
            row.reject:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
            f.rows[i] = row
        end
        f.previousPage = button(f, '‹', 76, -352, 44, function() requestOffset=math.max(0, requestOffset-REQUESTS_PER_PAGE); refreshRequests() end, 26, nil, {rounded = true})
        f.nextPage = button(f, '›', 178, -352, 44, function() if requestOffset + REQUESTS_PER_PAGE < #(f.entries or {}) then requestOffset=requestOffset+REQUESTS_PER_PAGE end; refreshRequests() end, 26, nil, {rounded = true})
        f.page = f:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        f.page:SetPoint('CENTER', f.previousPage, 'RIGHT', 29, 0); f.page:SetJustifyH('CENTER')
        requestsWindow = f
    end
    requestsWindow:Show(); refreshRequests(); if refresh then refresh() end
end

local CARD_HEIGHT, CARD_STEP, VISIBLE_CARDS = 84, 92, 5
local STATUS_GREEN = {0.349, 0.902, 0.502, 1}

local function roleSlotColor(roleKey, occupied)
    local colors = OldKraken.UIStyle.Colors or {}
    if not occupied then return colors.button or {0.08, 0.095, 0.125, 1} end
    if roleKey == 'tank' then return colors.roleTank or {0.40, 0.70, 1, 1}
    elseif roleKey == 'healer' then return colors.roleHealer or {0.41, 0.86, 0.55, 1}
    elseif roleKey == 'dps' then return colors.roleDps or {1, 0.48, 0.43, 1}
    else return colors.roleFlex or {1, 0.82, 0.42, 1} end
end

local function ensureGroupCard(f, index)
    if f.rows[index] then return f.rows[index] end
    local card
    card = CreateFrame('Button', nil, f.listContent)
    OldKraken.UIStyle.Button(card)
    card:SetSize(554, CARD_HEIGHT)
    card:SetPoint('TOPLEFT', f.listContent, 'TOPLEFT', 0, -(index - 1) * CARD_STEP)
    card:SetScript('OnClick', function(self)
        local entry = (self and self.entry) or (card and card.entry) or (f.visible and f.visible[index])
        if entry then
            if requestsWindow then requestsWindow:Hide() end
            if selected ~= entry.key then requestOffset = 0; f.detailsScroll:SetVerticalScroll(0) end
            selected = entry.key
            refresh()
        end
    end)
    card.art = card:CreateTexture(nil, 'ARTWORK')
    card.art:SetPoint('TOPLEFT', card, 'TOPLEFT', 11, -10); card.art:SetSize(64, 64)
    card.title = card:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
    card.title:SetPoint('TOPLEFT', card, 'TOPLEFT', 87, -14); card.title:SetPoint('RIGHT', card, 'RIGHT', -138, 0)
    card.title:SetJustifyH('LEFT'); card.title:SetWordWrap(false)
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(card.title, 14, true) end
    local gold = OldKraken.UIStyle.Colors and OldKraken.UIStyle.Colors.brandGold
    if gold then card.title:SetTextColor(gold[1], gold[2], gold[3]) end
    card.meta = card:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
    card.meta:SetPoint('TOPLEFT', card, 'TOPLEFT', 87, -35); card.meta:SetPoint('RIGHT', card, 'RIGHT', -138, 0)
    card.meta:SetJustifyH('LEFT'); card.meta:SetWordWrap(false)
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(card.meta, 13) end
    card.members = card:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    card.members:SetPoint('TOPLEFT', card, 'TOPLEFT', 87, -55); card.members:SetPoint('RIGHT', card, 'RIGHT', -138, 0)
    card.members:SetJustifyH('LEFT'); card.members:SetWordWrap(false)
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(card.members, 12) end
    local muted = OldKraken.UIStyle.Colors and OldKraken.UIStyle.Colors.mutedText
    if muted then card.members:SetTextColor(muted[1], muted[2], muted[3]) end
    card:SetScript('OnEnter', function(self)
        if GameTooltip and self.tooltipTitle then
            GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
            GameTooltip:SetText(self.tooltipTitle)
            if self.tooltipBody and self.tooltipBody ~= '' then GameTooltip:AddLine(self.tooltipBody, 1, 1, 1, true) end
            GameTooltip:Show()
        end
    end)
    card:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)

    if OldKraken.UIStyle.PillBadge then
        card.statusPill = OldKraken.UIStyle.PillBadge(card, T('Відкрито'), 'success', {width = 80, height = 19, fontSize = 11, bold = true, rounded = true, customColors = {success = STATUS_GREEN}})
        card.statusPill:SetPoint('BOTTOMRIGHT', card, 'BOTTOMRIGHT', -11, 14)
        card.statusBackground = card.statusPill.fill
        card.status = card.statusPill.label
        card.status:SetWidth(76)
        card.status:SetJustifyH('CENTER')
    else
        card.statusBackground = card:CreateTexture(nil, 'ARTWORK')
        card.statusBackground:SetPoint('BOTTOMRIGHT', card, 'BOTTOMRIGHT', -11, 14)
        card.statusBackground:SetSize(68, 19); card.statusBackground:SetColorTexture(0.035, 0.04, 0.05, 0.92)
        card.status = card:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
        card.status:SetPoint('CENTER', card.statusBackground, 'CENTER'); card.status:SetWidth(64)
        card.status:SetJustifyH('CENTER'); card.status:SetWordWrap(false)
    end
    card.slots = {}
    local slotBorderColor = OldKraken.UIStyle.Colors and OldKraken.UIStyle.Colors.buttonEdge or {0.20, 0.23, 0.29, 0.85}
    for slotIndex = 1, 5 do
        local slot = CreateFrame('Button', nil, card)
        slot:SetSize(20, 20); slot:SetPoint('TOPRIGHT', card, 'TOPRIGHT', -11 - (5 - slotIndex) * 24, -18)
        local mediaBase = 'Interface\\AddOns\\' .. OldKraken.name .. '\\Media\\'
        slot.fill = slot:CreateTexture(nil, 'BACKGROUND')
        slot.fill:SetAllPoints(slot)
        slot.fill:SetTexture(mediaBase .. 'PillFill.tga')
        slot.fill:SetVertexColor(unpack(roleSlotColor(nil, false)))
        slot.border = slot:CreateTexture(nil, 'BORDER')
        slot.border:SetAllPoints(slot)
        slot.border:SetTexture(mediaBase .. 'PillRing.tga')
        slot.border:SetVertexColor(slotBorderColor[1], slotBorderColor[2], slotBorderColor[3], 1)
        slot.ring = slot:CreateTexture(nil, 'ARTWORK')
        slot.ring:SetPoint('CENTER'); slot.ring:SetSize(14, 14)
        slot.ring:SetColorTexture(0, 0, 0, 0)
        slot.ring:Hide()
        slot.icon = slot:CreateTexture(nil, 'OVERLAY')
        slot.icon:SetPoint('CENTER'); slot.icon:SetSize(12, 12)
        slot.text = slot:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall'); slot.text:SetPoint('CENTER'); slot.text:SetTextColor(1, 1, 1)
        slot:SetScript('OnEnter', function(self)
            GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
            if self.member then
                GameTooltip:SetText(playerLabel(self.member))
                local specText = memberSpecText(self.member)
                if specText then GameTooltip:AddLine(T('Спеціалізація: ') .. specText, 1, 1, 1) end
                GameTooltip:AddLine(T('Роль: ') .. roleLabel(self.memberRole), 1, 1, 1)
                local group = self.groupKey and Finder.groups[self.groupKey]
                if group and self.member ~= group.owner then
                    GameTooltip:AddLine(not group.partyObserved and T('Стан невідомий') or (group.partyObserved[self.member] and T('У паті') or T('Резерв')), 1, 1, 1)
                end
            else
                GameTooltip:SetText(T('Вільне місце') .. (self.requiredRole and (': ' .. roleLabel(self.requiredRole)) or ''))
                local group = self.groupKey and Finder.groups[self.groupKey]
                if group and group.owner == Finder.identity then
                    GameTooltip:AddLine(T('Це ваше оголошення'), 1, 1, 1, true)
                elseif Finder.pending[self.groupKey] == 'pending' then
                    GameTooltip:AddLine(T('Заявка вже очікує відповіді'), 1, 1, 1, true)
                else
                    GameTooltip:AddLine(self.requiredRole and T('Натисніть, щоб подати заявку на цю роль') or T('Натисніть, щоб вибрати роль і подати заявку'), 1, 1, 1, true)
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
                else print(T('Old Kraken: місце вже зайняте або заявку не вдалося надіслати.')) end
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
    f.rows[index] = card
    local remove = CreateFrame('Button', nil, card)
    OldKraken.UIStyle.Button(remove)
    remove:SetSize(26, 26)
    remove:SetPoint('BOTTOMRIGHT', card, 'BOTTOMRIGHT', -94, 10)
    remove:SetHitRectInsets(-2, -2, -2, -2)
    remove.glyph = remove:CreateTexture(nil, 'ARTWORK')
    remove.glyph:SetTexture('Interface\\AddOns\\' .. OldKraken.name .. '\\Media\\IconTrash.tga')
    remove.glyph:SetSize(16, 16)
    remove.glyph:SetPoint('CENTER', remove, 'CENTER', 0, 0)
    remove.glyph:SetVertexColor(0.9, 0.32, 0.3, 1)
    remove:SetScript('OnClick', function()
        local entry = card.entry or (f.visible and f.visible[index])
        local group = entry and Finder.groups[entry.key]
        if group and tab == 'applications' and Finder.pending[entry.key] then
            if Finder:DismissApplication(group.owner, group.id) then
                if selected == entry.key then selected = nil end
                Finder:Changed(); refresh()
            else print(T('Old Kraken: не вдалося відкликати заявку. Перевірте зв’язок.')) end
            return
        end
        if not group or group.owner ~= Finder.identity then return end
        if Finder:Delete(group.id) then
            if selected == entry.key then selected = nil end
            Finder:Changed()
            refresh()
        else
            print(T('Old Kraken: не вдалося видалити групу. Перевірте зв’язок.'))
        end
    end)
    remove:SetScript('OnEnter', function(self)
        if GameTooltip then
            local entry = card.entry or (f.visible and f.visible[index])
            local status = entry and tab == 'applications' and Finder.pending[entry.key]
            local label = status == 'pending' and T('Відкликати заявку')
                or (status and T('Прибрати заявку зі списку') or T('Видалити групу'))
            GameTooltip:SetOwner(self, 'ANCHOR_RIGHT'); GameTooltip:SetText(label); GameTooltip:Show()
        end
    end)
    remove:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
    remove:Hide()
    f.deleteButtons[index] = remove
    return card
end

refresh=function()
    if not window or not window:IsShown() then return end
    local compactMine = tab == 'mine' or tab == 'applications'
    local contentTop = compactMine and -103 or -179
    window.listScroll:ClearAllPoints()
    window.listScroll:SetPoint('TOPLEFT', window, 'TOPLEFT', 0, contentTop)
    window.listScroll:SetHeight(compactMine and 476 or 400)
    window.detailPanel:ClearAllPoints()
    window.detailPanel:SetPoint('TOPLEFT', window, 'TOPLEFT', 570, contentTop)
    window.detailPanel:SetHeight(compactMine and 504 or 428)
    window.detailsScroll:ClearAllPoints()
    window.detailsScroll:SetPoint('TOPLEFT', window, 'TOPLEFT', 587, contentTop - 17)
    window.detailsScroll:SetHeight(compactMine and 362 or 286)
    local roleCategory = tab == 'create' and category or (selected and Finder.groups[selected] and Finder.groups[selected].category or category)
    if window.roleButton and window.roleButton.Update then window.roleButton:Update(roleCategory) end
    local alertsOn = Finder:GroupAlertsEnabled()
    window.alertButton:SetText(alertsOn and T('Сповіщення: увімк.') or T('Сповіщення: вимк.'))
    if window.alertDot then
        local c = alertsOn and STATUS_GREEN or (OldKraken.UIStyle.Colors and OldKraken.UIStyle.Colors.neutral) or {0.63, 0.67, 0.73, 1}
        window.alertDot:SetColorTexture(c[1], c[2], c[3], 1)
    end
    local minText = window.minLevelFilter and window.minLevelFilter:GetText() or ''
    local maxText = window.maxLevelFilter and window.maxLevelFilter:GetText() or ''
    local minLevel = tonumber(minText)
    local maxLevel = tonumber(maxText)
    if minLevel and maxLevel and minLevel > maxLevel then minLevel, maxLevel = maxLevel, minLevel end
    if window.minLevelHint then window.minLevelHint:SetShown(minText == '') end
    if window.maxLevelHint then window.maxLevelHint:SetShown(maxText == '') end
    local searchText = window.searchFilter:GetText() or ''
    if window.searchHint then window.searchHint:SetShown(searchText == '') end
    refreshPeople()
    pruneOfflineApplications()
    if tab == 'all' and selected and isGroupHiddenByOfflineOwner(selected, Finder.groups and Finder.groups[selected]) then
        selected = nil
        requestOffset = 0
    end
    local query = string.lower(searchText)
    local lines = {}
    local totalOpenGroups = 0
    for key, group in pairs(Finder.groups or {}) do
        local hiddenOffline = isGroupHiddenByOfflineOwner(key, group)
        if not group.closed and not hiddenOffline then totalOpenGroups = totalOpenGroups + 1 end
        local levelMatches = true
        if minLevel and maxLevel then
            levelMatches = group.maxLevel >= minLevel and group.minLevel <= maxLevel
        elseif minLevel then
            levelMatches = group.maxLevel >= minLevel
        elseif maxLevel then
            levelMatches = group.minLevel <= maxLevel
        end
        local matches = (filterCategory == 'all' or group.category == filterCategory)
            and (filterDungeon == '' or group.dungeon == filterDungeon)
            and (filterRole == '' or (#group.members < group.maxSize and Finder:RoleAvailable(group, filterRole)))
            and (not filterFree or #group.members < group.maxSize)
            and levelMatches
            and (query == '' or string.find(string.lower(displayGroupTitle(group) .. ' ' .. group.owner .. ' ' .. group.description .. ' ' .. (dungeonLabels[group.dungeon] or '')), query, 1, true))
        if (tab == 'all' and not group.closed and not hiddenOffline and #group.members < group.maxSize and matches) or (tab == 'mine' and group.owner == Finder.identity and not group.hidden)
            or (tab == 'applications' and Finder.pending[key]) then
            lines[#lines + 1] = {key=key, group=group}
        end
    end
    table.sort(lines, function(a,b) return displayGroupTitle(a.group) < displayGroupTitle(b.group) end)
    window.visible = lines
    local pendingApplications = 0
    for key in pairs(Finder.pending or {}) do
        local group = Finder.groups and Finder.groups[key]
        -- Count every application except the ones whose owner is confirmed
        -- offline; an unknown owner is not a reason to hide the application.
        if group and not isOwnerOffline(group.owner) then pendingApplications = pendingApplications + 1 end
    end
    if window.tabBar and window.tabBar.SetBadge then
        window.tabBar:SetBadge('applications', pendingApplications)
        window.tabBar:SetActive(tab)
    end
    local empty = #lines == 0 and tab ~= 'create'
    local hasFilters = filterCategory ~= 'all' or filterRole ~= '' or filterFree or filterDungeon ~= ''
        or searchText ~= '' or minText ~= '' or maxText ~= ''
    if tab == 'applications' then
        window.emptyList:SetText(T('Ви ще не подали жодної заявки.'))
    elseif tab == 'mine' then
        window.emptyList:SetText(T('У вас ще немає оголошень.'))
    elseif hasFilters and totalOpenGroups > 0 then
        window.emptyList:SetText(T('За обраними фільтрами груп не знайдено.\nСкиньте фільтри або створіть власне оголошення.'))
    else
        window.emptyList:SetText(T('Доступних груп поки немає.\nСтворіть перше оголошення для гільдії.'))
    end
    window.emptyList:SetShown(empty)
    window.emptyAction:SetText(tab == 'applications' and T('Знайти групу') or (tab == 'all' and hasFilters and T('Скинути фільтри') or T('Створити оголошення')))
    window.emptyAction:SetShown(empty)
    for _, item in ipairs(window.tabs) do
        item.button.activeMark:SetShown(item.key == tab)
        if not window.tabBar then
            if item.key == tab then item.button:LockHighlight() else item.button:UnlockHighlight() end
        end
    end
    window.listScroll:SetShown(tab ~= 'create')
    local listScrollBar = _G.OldKrakenGroupListScrollScrollBar
    if type(listScrollBar) == 'table' and listScrollBar.SetShown then listScrollBar:SetShown(tab ~= 'create' and #lines > 4) end
    window.listSummary:SetShown(tab ~= 'create' and (#lines > 0 or tab == 'all'))
    local n = #lines
    local mod100, mod10 = n % 100, n % 10
    local word
    if OldKraken.GetLanguage and OldKraken.GetLanguage() == 'enUS' then
        word = n == 1 and 'group' or 'groups'
    elseif mod100 >= 11 and mod100 <= 14 then
        word = 'груп'
    else
        word = (mod10 == 1 and 'групу') or (mod10 >= 2 and mod10 <= 4 and 'групи') or 'груп'
    end
    window.listSummary:SetText(string.format(T('Показано %d %s · список оновлюється автоматично'), n, word))
    local listViewport = tonumber((window.listScroll:GetHeight())) or 400
    if listViewport <= 0 then listViewport = 400 end
    local fullListHeight = math.max(1, #lines * CARD_STEP - 8)
    window.listContent:SetHeight(fullListHeight)
    local rawListScroll = tonumber((window.listScroll:GetVerticalScroll())) or 0
    local clampedListScroll = math.max(0, math.min(rawListScroll, math.max(0, fullListHeight - listViewport)))
    if clampedListScroll ~= rawListScroll then window.listScroll:SetVerticalScroll(clampedListScroll) end
    local firstCardIndex = math.floor(clampedListScroll / CARD_STEP) + 1
    local cardWidth = #lines > 4 and 530 or 554
    window.listScroll:SetWidth(cardWidth)
    window.listContent:SetWidth(cardWidth)
    for i = 1, #window.rows do
        local dataIndex = firstCardIndex + i - 1
        local entry = lines[dataIndex]
        local b = window.rows[i]
        b.entry = entry
        if entry then
            b:SetWidth(cardWidth)
            b:ClearAllPoints()
            b:SetPoint('TOPLEFT', window.listContent, 'TOPLEFT', 0, -((dataIndex - 1) * CARD_STEP))
            local g = entry.group
            local status = Finder.pending[entry.key]
            local kind = (g.dungeon and g.dungeon ~= '' and dungeonLabels[g.dungeon]) or categoryLabels[g.category] or g.category
            catalog.SetArtwork(b.art, g.dungeon)
            local title = displayGroupTitle(g)
            b.title:SetText(title == kind and title or (title .. '  ·  ' .. kind))
            local present, reserved = {}, 0
            if g.partyObserved then
                for memberIndex = 2, #g.members do
                    local name = g.members[memberIndex]
                    if g.partyObserved[name] then present[#present + 1] = name else reserved = reserved + 1 end
                end
            end
            b.meta:SetText(string.format(T('%s  ·  рівні %d–%d  ·  місць %d/%d%s'), playerLabel(g.owner), g.minLevel, g.maxLevel, #g.members, g.maxSize, reserved > 0 and (T(' · резерв ') .. reserved) or ''))
            local badge = tab == 'applications' and applicationBadges[status]
            if badge then
                local offline = isOwnerOffline(g.owner)
                if b.statusPill and b.statusPill.SetKind then
                    local pillKind = offline and 'neutral' or (status == 'reject' and 'danger' or (status == 'closed' and 'neutral' or 'warning'))
                    b.statusPill:SetKind(pillKind)
                end
                b.status:SetText(offline and T('ОФЛАЙН') or badge.text)
                if offline then b.status:SetTextColor(0.68, 0.72, 0.78) else b.status:SetTextColor(unpack(badge.color)) end
                b.status:Show(); b.statusBackground:Show()
                if b.statusPill then b.statusPill:Show() end
            else
                local ownerOffline = not g.closed and g.owner ~= Finder.identity and isOwnerOffline(g.owner)
                local openKind = g.closed and 'neutral' or ((ownerOffline or #g.members >= g.maxSize) and 'warning' or 'success')
                local openLabel = g.closed and T('Закрито') or (ownerOffline and T('Офлайн') or (#g.members >= g.maxSize and T('Заповнено') or T('Відкрито')))
                if b.statusPill and b.statusPill.SetKind then
                    b.statusPill:SetKind(openKind)
                    b.statusPill:SetLabel(openLabel)
                    b.statusPill:Show()
                else
                    b.status:SetText(openLabel); b.status:Show(); b.statusBackground:Show()
                end
            end
            local partyLine
            if g.partyObserved and #present > 0 then
                local preview = {playerLabel(g.owner)}
                for memberIndex = 1, math.min(#present, 2) do preview[#preview + 1] = playerLabel(present[memberIndex]) end
                partyLine = T('У паті: ') .. table.concat(preview, ', ') .. (#present > 2 and ('  +' .. (#present - 2)) or '')
            else
                partyLine = g.partyObserved and T('Автор поки без паті') or T('Склад паті не підтверджено')
            end
            b.members:SetText(g.description ~= '' and g.description or partyLine)
            b.tooltipTitle = displayGroupTitle(g)
            b.tooltipBody = g.description ~= '' and (g.description .. '\n' .. partyLine) or partyLine
            local fixedSlots = g.category == 'dungeon' and g.maxSize == 5 and Finder:DungeonSlots(g) or nil
            for slotIndex, slot in ipairs(b.slots) do
                if slotIndex <= math.min(5, g.maxSize) then
                    local fixed = fixedSlots and fixedSlots[slotIndex]
                    local member = fixed and fixed.member or (not fixed and g.members[slotIndex])
                    if not fixed and slotIndex == 5 and g.maxSize > 5 and #g.members < g.maxSize then member = nil end
                    local memberRole = fixed and fixed.memberRole or (member and (member == g.owner and g.role or (g.memberRoles and g.memberRoles[member]) or '')) or ''
                    slot.groupKey, slot.member, slot.memberRole, slot.requiredRole = entry.key, member, memberRole, fixed and fixed.role or nil
                    local mutedEdge = (OldKraken.UIStyle.Colors and OldKraken.UIStyle.Colors.buttonEdge) or {0.20, 0.23, 0.29, 0.85}
                    local fillColor, edgeColor = roleSlotColor(nil, false), mutedEdge
                    if member then
                        fillColor = roleIconIndex[memberRole] and roleSlotColor(memberRole, true) or SLOT_NEUTRAL
                        edgeColor = fillColor
                    end
                    if slot.fill then slot.fill:SetVertexColor(fillColor[1], fillColor[2], fillColor[3], 1) end
                    if slot.border then slot.border:SetVertexColor(edgeColor[1], edgeColor[2], edgeColor[3], 1) end
                    slot.ring:Hide()
                    if member then
                        local isReserved = member ~= g.owner and g.partyObserved and not g.partyObserved[member]
                        slot.text:Hide()
                        if roleIconIndex[memberRole] then
                            setRoleIcon(slot.icon, memberRole); slot.icon:SetVertexColor(ROLE_ICON_DARK[1], ROLE_ICON_DARK[2], ROLE_ICON_DARK[3], 1)
                            slot.icon:SetAlpha(isReserved and 0.45 or 1); slot.icon:Show()
                        else
                            slot.icon:Hide(); slot.text:SetText('?'); slot.text:Show()
                        end
                    else
                        slot.text:Hide()
                        local req = fixed and fixed.role
                        if req and roleIconIndex[req] then
                            setRoleIcon(slot.icon, req); slot.icon:SetVertexColor(0.63, 0.67, 0.73, 1); slot.icon:SetAlpha(0.45); slot.icon:Show()
                        else
                            slot.icon:Hide()
                        end
                    end
                    slot:Show()
                else slot:Hide() end
            end
            if OldKraken.UIStyle.ApplySelection then
                OldKraken.UIStyle.ApplySelection(b, selected == entry.key)
                b:UnlockHighlight()
            elseif selected == entry.key then
                b:LockHighlight()
            else
                b:UnlockHighlight()
            end
            b:Show()
            if tab == 'applications' or (g.owner == Finder.identity and not g.hidden) then window.deleteButtons[i]:Show() else window.deleteButtons[i]:Hide() end
        elseif b then
            b:UnlockHighlight()
            b:Hide()
            if window.deleteButtons[i] then window.deleteButtons[i]:Hide() end
        end
    end
    if tab == 'create' and requestsWindow then requestsWindow:Hide() end
    local showingRequests = requestsWindow and requestsWindow:IsShown() and tab ~= 'create'
    window.detailPanel:SetShown(tab ~= 'create')
    window.detailsScroll:SetShown(tab ~= 'create' and not showingRequests)
    local detailsScrollBar = _G.OldKrakenGroupDetailsScrollScrollBar
    local g
    if tab ~= 'create' and selected and type(Finder.groups) == 'table' then
        g = Finder.groups[selected]
        if type(g) ~= 'table' then g = nil end
    end
    if type(detailsScrollBar) == 'table' and detailsScrollBar.SetShown then
        detailsScrollBar:SetShown(g ~= nil and type(g.members) == 'table' and #g.members > 3)
    end
    local canManage = tab ~= 'create' and g and g.owner == Finder.identity and not g.closed
    local canEditDescription = tab ~= 'create' and g and g.owner == Finder.identity and not g.hidden
    if not canEditDescription or selected ~= editingDescriptionKey then editingDescriptionKey = nil end
    local editing = canEditDescription and editingDescriptionKey == selected and not showingRequests
    local hasDescription = g ~= nil and (g.description or '') ~= ''
    local showDesc = g ~= nil and not editing and (hasDescription or canEditDescription)
    if g then
        local applicationStatus = Finder.pending[selected]
        local activity = (g.dungeon and g.dungeon ~= '' and dungeonLabels[g.dungeon]) or categoryLabels[g.category]
        local activityLine = activity and activity ~= displayGroupTitle(g) and ('\n|cff9ba9bc' .. activity .. '|r') or ''
        local status = g.closed and T('|cffb5b5b5Закрито|r') or T('|cff59e680Відкрито|r')
        local application = applicationStatus and (T('\n|cff9ba9bcЗаявка:|r |c') .. (pendingColors[applicationStatus] or 'ffb5b5b5') .. (pendingLabels[applicationStatus] or applicationStatus) .. '|r') or ''
        local description = g.description ~= '' and (T('\n\n|cff9ba9bcОпис:|r ') .. g.description) or ''
        window.details:SetText(string.format(T('|cffffd35a%s|r%s\n\n|cff9ba9bcАвтор:|r   |cff9bcaff%s|r\n|cff9ba9bcРівні:|r   |cff9bcaff%d–%d|r\n|cff9ba9bcРоль:|r    %s\n|cff9ba9bcСтатус:|r  %s%s%s\n\n|cffffd35aСклад групи:|r'),
            displayGroupTitle(g), activityLine, playerLabel(g.owner), g.minLevel, g.maxLevel, roleLabel(g.role), status, application, description))
        window.details:SetAlpha(0)
        window.detailsHeading:SetText(displayGroupTitle(g))
        window.detailsHeading:Show()
        local appNote = (applicationStatus and not (g.closed and applicationStatus == 'closed'))
            and (' · |c' .. (pendingColors[applicationStatus] or 'ffb5b5b5') .. (pendingLabels[applicationStatus] or applicationStatus) .. '|r') or ''
        local kvValues = {
            playerLabel(g.owner),
            string.format('%d–%d', g.minLevel, g.maxLevel),
            roleLabel(g.role),
            status .. appNote,
            hasDescription and g.description or '—',
        }
        for idx, kv in ipairs(window.detailsKV or {}) do
            if idx == 5 then
                kv.key:SetShown(showDesc or editing)
                kv.val:SetWidth(canEditDescription and 122 or 198)
                kv.val:SetText(kvValues[5])
                kv.val:SetShown(showDesc)
            else
                kv.key:Show()
                kv.val:SetText(kvValues[idx] or '—')
                kv.val:Show()
            end
        end
        if window.detailsDivider then window.detailsDivider:Show() end
        if window.detailsRosterHeader then window.detailsRosterHeader:Show() end
    else
        window.details:SetText(T('Виберіть оголошення у списку.'))
        window.details:SetAlpha(1)
        if window.detailsHeading then window.detailsHeading:Hide() end
        for _, kv in ipairs(window.detailsKV or {}) do kv.key:Hide(); kv.val:Hide() end
        if window.detailsDivider then window.detailsDivider:Hide() end
        if window.detailsRosterHeader then window.detailsRosterHeader:Hide() end
    end
    if type(window.editDescButton) == 'table' then
        window.editDescButton:SetShown(canEditDescription and not editing and not showingRequests)
        window.editDescBox:SetShown(editing)
        window.saveDescButton:SetShown(editing)
        window.cancelDescButton:SetShown(editing)
    end
    local extraDesc = 0
    if g and not editing then
        local descVal = window.detailsKV and window.detailsKV[5] and window.detailsKV[5].val
        if not showDesc then
            extraDesc = -26
        elseif type(descVal) == 'table' and type(descVal.GetStringHeight) == 'function' then
            local descHeight = tonumber(descVal:GetStringHeight()) or 16
            if descHeight > 16 then extraDesc = descHeight - 16 end
        end
    end
    if window.detailsDivider then
        window.detailsDivider:ClearAllPoints()
        window.detailsDivider:SetPoint('TOPLEFT', window.detailsContent, 'TOPLEFT', 0, editing and -194 or (-166 - extraDesc))
    end
    if window.detailsRosterHeader then
        window.detailsRosterHeader:ClearAllPoints()
        window.detailsRosterHeader:SetPoint('TOPLEFT', window.detailsContent, 'TOPLEFT', 0, editing and -208 or (-180 - extraDesc))
    end
    local members = g and g.members or {}
    local top = g and (editing and 240 or (212 + extraDesc)) or (window.details:GetStringHeight() + 8)
    local viewport=tonumber((window.detailsScroll:GetHeight())) or 210
    if viewport<=0 then viewport=210 end
    local oldScroll=tonumber((window.detailsScroll:GetVerticalScroll())) or 0
    local scrollTop=math.max(0,math.min(oldScroll,math.max(0,math.max(210,top+#members*36+4)-viewport)))
    if scrollTop~=oldScroll then window.detailsScroll:SetVerticalScroll(scrollTop) end
    local first=math.max(1,math.floor((scrollTop-top)/36)+1)
    local visibleCount=math.max(0,math.min(math.ceil(viewport/36)+1,#members-first+1))
    for i = 1, math.max(visibleCount, #window.memberRows) do
        local dataIndex=first+i-1
        local row = window.memberRows[i]
        if i <= visibleCount then
            if not row then
                row = {}
                row.name = window.detailsContent:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
                row.name:SetHeight(20); row.name:SetJustifyH('LEFT'); row.name:SetWordWrap(false)
                if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(row.name, 13) end
                row.state = window.detailsContent:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
                row.state:SetHeight(20); row.state:SetJustifyH('RIGHT'); row.state:SetWordWrap(false)
                if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(row.state, 12) end
                row.hover = CreateFrame('Frame', nil, window.detailsContent)
                row.hover:SetSize(276, 24); row.hover:EnableMouse(true)
                row.hover:SetScript('OnEnter', function(self)
                    if GameTooltip then GameTooltip:SetOwner(self, 'ANCHOR_RIGHT'); GameTooltip:SetText(self.memberLabel); GameTooltip:Show() end
                end)
                row.hover:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
                row.invite = CreateFrame('Button', nil, window.detailsContent, 'UIPanelButtonTemplate')
                OldKraken.UIStyle.Button(row.invite, 'primary', {rounded = true})
                row.invite:SetSize(76, 22); row.invite:SetText(T('Запросити'))
                row.invite:SetScript('OnClick', function(self)
                    local current = selected and Finder.groups[selected]
                    local name = self.memberName
                    if not current or current.owner ~= Finder.identity or current.closed or not current.partyObserved or current.partyObserved[name] then return end
                    for j = 2, #current.members do
                        if current.members[j] == name then invitePlayer(name); return end
                    end
                end)
                row.remove = CreateFrame('Button', nil, window.detailsContent, 'UIPanelButtonTemplate')
                OldKraken.UIStyle.Button(row.remove, nil, {rounded = true})
                row.remove:SetSize(24, 22); row.remove:SetText('×')
                row.remove:SetScript('OnEnter', function(self)
                    if GameTooltip then GameTooltip:SetOwner(self, 'ANCHOR_RIGHT'); GameTooltip:SetText(T('Видалити з оголошення або виключити з паті')); GameTooltip:Show() end
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
                        print(T('|cffff5555Old Kraken|r: Склад паті ще не визначено. Спробуйте пізніше.'))
                    elseif current.partyObserved[name] then
                        if type(UnitIsGroupLeader) == 'function' and not UnitIsGroupLeader('player') then
                            print(T('|cffff5555Old Kraken|r: Для виключення гравця потрібні права лідера групи.'))
                        elseif not C_PartyInfo or type(C_PartyInfo.UninviteUnit) ~= 'function' then
                            print(T('|cffff5555Old Kraken|r: API виключення недоступний. Видаліть гравця з паті вручну.'))
                        else
                            local ok, result = pcall(C_PartyInfo.UninviteUnit, name)
                            if ok and result ~= false then
                                print(T('|cff2ec4b6Old Kraken|r: Спроба виключити ') .. name .. T(' з паті. Перевірте повідомлення гри.'))
                            else
                                print(T('|cffff5555Old Kraken|r: Не вдалося виключити ') .. name .. T(' з паті.'))
                            end
                        end
                    elseif Finder:RemoveMember(current.id, name) then
                        Finder:Changed(); refresh()
                    else
                        print(T('|cffff5555Old Kraken|r: Не вдалося видалити резерв. Перевірте зв’язок.'))
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
            local memberRole=dataIndex==1 and g.role or (g.memberRoles and g.memberRoles[name])
            local coloredRole=roleLabel(memberRole or '')
            local coloredState='|c' .. memberStateColors[state] .. T(state) .. '|r'

            local rowY = -top - (dataIndex - 1) * 36
            local isAuthor = dataIndex == 1
            local canInvite = canManage and not isAuthor and g.partyObserved and not g.partyObserved[name]
            local canRemove = canManage and not isAuthor

            if canRemove then
                row.remove:ClearAllPoints()
                row.remove:SetPoint('RIGHT', window.detailsContent, 'TOPLEFT', 276, rowY)
                row.remove.memberName = name
                row.remove:Show()
            else
                row.remove:Hide()
            end

            if canInvite then
                row.invite:ClearAllPoints()
                row.invite:SetPoint('RIGHT', row.remove, 'LEFT', -4, 0)
                row.invite.memberName = name
                row.invite:Show()
            else
                row.invite:Hide()
            end

            if canInvite then
                row.state:Hide()
            else
                row.state:ClearAllPoints()
                if canRemove then
                    row.state:SetPoint('RIGHT', row.remove, 'LEFT', -6, 0)
                else
                    row.state:SetPoint('RIGHT', window.detailsContent, 'TOPLEFT', 276, rowY)
                end
                row.state:SetText(coloredRole .. ' |cff9ba9bc·|r ' .. coloredState)
                row.state:Show()
            end

            row.name:ClearAllPoints()
            row.name:SetPoint('LEFT', window.detailsContent, 'TOPLEFT', 0, rowY)
            if canInvite then
                row.name:SetPoint('RIGHT', row.invite, 'LEFT', -6, 0)
            elseif row.state:IsShown() then
                row.name:SetPoint('RIGHT', row.state, 'LEFT', -6, 0)
            else
                row.name:SetPoint('RIGHT', window.detailsContent, 'TOPLEFT', 276, rowY)
            end
            row.name:SetText((catalog.roleIcons[memberRole] or '') .. ' ' .. playerLabel(name))
            row.name:Show()

            row.hover:ClearAllPoints()
            row.hover:SetPoint('LEFT', window.detailsContent, 'TOPLEFT', 0, rowY)
            row.hover:SetSize(canInvite and 180 or (canRemove and 240 or 276), 24)
            local specText = memberSpecText(name)
            row.hover.memberLabel = name .. T('\nРоль: ') .. coloredRole .. T('\nСтатус: ') .. coloredState .. (specText and (T('\nСпеціалізація: ') .. specText) or '')
            row.hover:Show()
        elseif row then
            row.name:Hide(); row.state:Hide(); row.hover:Hide(); row.invite:Hide(); row.remove:Hide()
        end
    end
    window.detailsContent:SetHeight(math.max(250, top + #members * 36 + 4))
    local isOther = tab ~= 'create' and g and g.owner ~= Finder.identity and not g.closed
    local pending = selected and Finder.pending[selected]
    local alreadyMember = false
    if g then for _, name in ipairs(g.members) do if name == Finder.identity then alreadyMember = true; break end end end
    local canApply = isOther and not showingRequests and not alreadyMember and pending ~= 'pending'
    local showAppAction = not showingRequests and tab == 'applications' and g and g.owner ~= Finder.identity and pending ~= nil
    window.applyButton:ClearAllPoints()
    if canApply and showAppAction then
        window.applyButton:SetSize(144, 40)
        window.applyButton:SetPoint('TOPLEFT', window, 'TOPLEFT', 587, -550)
    else
        window.applyButton:SetSize(296, 40)
        window.applyButton:SetPoint('TOPLEFT', window, 'TOPLEFT', 587, -550)
    end
    window.applyButton:SetShown(canApply and true or false)
    window.applicationActionButton:ClearAllPoints()
    if canApply and showAppAction then
        window.applicationActionButton:SetSize(144, 40)
        window.applicationActionButton:SetPoint('TOPLEFT', window, 'TOPLEFT', 739, -550)
    else
        window.applicationActionButton:SetSize(296, 40)
        window.applicationActionButton:SetPoint('TOPLEFT', window, 'TOPLEFT', 587, -550)
    end
    window.applicationActionButton:SetText(pending == 'pending' and T('Відкликати') or T('Прибрати заявку'))
    window.applicationActionButton:SetShown(showAppAction)
    local canReopen = tab ~= 'create' and g and g.owner == Finder.identity and g.closed and not g.hidden and not showingRequests
    window.cancelButton:SetShown(canManage and not showingRequests)
    window.bumpButton:SetShown(canManage and not showingRequests)
    if window.reopenButton then window.reopenButton:SetShown(canReopen and true or false) end
    UpdateReannounceButton(window.bumpButton)
    window.roleLabel:ClearAllPoints(); window.roleLabel:SetPoint('TOPLEFT', window, 'TOPLEFT', 587, -484)
    window.roleButton:ClearAllPoints(); window.roleButton:SetPoint('TOPLEFT', window, 'TOPLEFT', 587, -502)
    window.roleButton:SetShown(canApply and true or false)
    window.roleLabel:SetShown(canApply and true or false)
    if window.applyButton.SetEnabled then window.applyButton:SetEnabled(not canApply or (role ~= '' and Finder:CanPerformRole(Finder.identity, role))) end
    local requestCount, haveOwned = 0, false
    for _, group in pairs(Finder.groups or {}) do
        if group.owner == Finder.identity and not group.closed and not group.hidden then haveOwned = true; break end
    end
    for id, applicants in pairs(Finder.requests or {}) do
        local own = Finder.groups[Finder.identity .. '\001' .. id]
        if own and not own.closed and not own.hidden then for _ in pairs(applicants) do requestCount = requestCount + 1 end end
    end
    local hasNewRequests = not showingRequests and requestCount > 0
    window.requestsButton:SetText(showingRequests and T('До деталей') or (hasNewRequests and (T('|cff69dc8c•|r  Вхідні заявки: ') .. requestCount) or (T('Заявки: ') .. requestCount)))
    local colors = OldKraken.UIStyle.Colors
    if colors and type(window.requestsButton.fillParts) == 'table' then
        local fill = hasNewRequests and colors.primaryButton or colors.button
        local edge = hasNewRequests and colors.primaryButtonEdge or colors.buttonEdge
        for _, t in ipairs(window.requestsButton.fillParts) do t:SetVertexColor(fill[1], fill[2], fill[3], fill[4] or 1); t.color = fill end
        for _, t in ipairs(window.requestsButton.ringParts or {}) do t:SetVertexColor(edge[1], edge[2], edge[3], edge[4] or 1); t.color = edge end
    end
    local showRequestsBtn = tab ~= 'create' and tab ~= 'applications' and (showingRequests or canManage or (not g and haveOwned))
    window.requestsButton:SetShown(showRequestsBtn and true or false)
    for _, control in ipairs(window.filterControls) do control:SetShown(tab == 'all') end
    if window.searchHint then window.searchHint:SetShown(tab == 'all' and searchText == '') end
    if window.minLevelHint then window.minLevelHint:SetShown(tab == 'all' and minText == '') end
    if window.maxLevelHint then window.maxLevelHint:SetShown(tab == 'all' and maxText == '') end
    if window.freeFilter then window.freeFilter:Hide() end
    window.creationFooter:SetShown(tab=='create')
    window.LayoutCreation()
    local showCards=tab=='create' and (category=='dungeon' or category=='raid')
    window.activityPicker:SetShown(showCards)
    if showCards then window.UpdateActivityCards() end
    local advanced=tab=='create' and window.advancedCreation
    window.creationOptions:SetShown(advanced)
    for _,box in ipairs({window.titleBox,window.minBox,window.maxLevelBox}) do
        box:SetShown(advanced); box.label:SetShown(advanced)
    end
    local showMaxBox = advanced and category ~= 'dungeon'
    window.maxBox:SetShown(showMaxBox); window.maxBox.label:SetShown(showMaxBox)
    window.titleBox:SetWidth(category == 'dungeon' and 320 or 240)
    window.descriptionBox:SetShown(tab=='create'); window.descriptionBox.label:Hide()
    if window.commentHint then window.commentHint:SetShown(tab=='create' and (window.descriptionBox:GetText() or '')=='') end
    window.categoryButton:SetShown(advanced); window.categoryLabel:SetShown(advanced)
    window.dungeonLabel:Hide()
    window.maxBox.label:SetText(T('Місць'))
    window.createButton:SetShown(tab=='create')
    window.createButton:SetText(T('Зібрати групу'))
    local colors = OldKraken.UIStyle.Colors or {}
    for _,control in ipairs(window.creationRoles) do
        local allowed = Finder:CanPerformRole(Finder.identity,control.role)
        local isRoleActive = control.role == role
        control:SetEnabled(allowed)
        control:SetShown(tab=='create' and (category~='dungeon' or control.role~='flex'))
        if control.active then control.active:SetShown(isRoleActive) end
        local fillCol = isRoleActive and (colors.sel or {0.102, 0.141, 0.302, 1}) or (colors.button or {0.08, 0.095, 0.125, 1})
        local edgeCol = isRoleActive and (colors.selEdge or {0.478, 0.541, 0.980, 1}) or (colors.buttonEdge or {0.20, 0.23, 0.29, 0.85})
        if type(control.fillParts) == 'table' then
            for _, t in ipairs(control.fillParts) do t:SetVertexColor(fillCol[1], fillCol[2], fillCol[3], fillCol[4] or 1) end
            if type(control.ringParts) == 'table' then
                for _, t in ipairs(control.ringParts) do t:SetVertexColor(edgeCol[1], edgeCol[2], edgeCol[3], edgeCol[4] or 1) end
            end
        elseif type(control.fill) == 'table' and type(control.fill.SetColorTexture) == 'function' then
            control.fill:SetColorTexture(fillCol[1], fillCol[2], fillCol[3], fillCol[4] or 1)
        end
        local label = control.GetFontString and control:GetFontString()
        if label then
            local tc = isRoleActive and (colors.white or {1, 1, 1}) or (colors.text or {0.93, 0.94, 0.96})
            label:SetTextColor(tc[1], tc[2], tc[3])
            label:SetAlpha(allowed and 1 or 0.4)
        end
    end
    window.creationOptionsButton:SetText(window.advancedCreation and T('Параметри -') or T('Параметри +'))
    local selectedActivity=dungeon~='' and dungeonLabels[dungeon] or nil
    window.dungeonSelection:SetText(selectedActivity or ((category=='dungeon' or category=='raid') and T('Оберіть картку вище') or categoryLabels[category]))
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
    f:SetSize(900, 607); f:SetPoint('CENTER', parent or UIParent, 'CENTER'); f:SetMovable(not parent); f:EnableMouse(true)
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
    if OldKraken.BindGuildTitle then OldKraken.BindGuildTitle(f, T('Пошук груп')) end

    -- Segmented tabs block (at y = -47)
    local tabItems = {
        {key='all', label=T('Усі групи'), width=96},
        {key='create', label=T('Створити'), width=96},
        {key='applications', label=T('Мої заявки'), width=138},
        {key='mine', label=T('Мої оголошення'), width=148},
    }
    local function switchTab(nextTab)
        if requestsWindow then requestsWindow:Hide() end
        if type(CloseDropDownMenus)=='function' then CloseDropDownMenus() end
        tab = nextTab; selected = nil; offset = 0; requestOffset = 0; refresh()
    end
    f.tabs = {}
    if OldKraken.UIStyle.SegmentedTabs then
        f.tabBar = OldKraken.UIStyle.SegmentedTabs(f, tabItems, switchTab, {active = tab, height = 40, edgeKey = 'buttonEdge', rounded = true})
        f.tabBar:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, -47)
        for _, item in ipairs(tabItems) do
            local b = f.tabBar.tabs[item.key]
            b.activeMark = b:CreateTexture(nil, 'OVERLAY')
            b.activeMark:SetPoint('BOTTOMLEFT', b, 'BOTTOMLEFT', 8, 2)
            b.activeMark:SetSize(item.width - 16, 2)
            b.activeMark:SetColorTexture(unpack(OldKraken.UIStyle.Colors.brandGold))
            b.activeMark:SetAlpha(0)
            b.activeMark:Hide()
            f.tabs[#f.tabs + 1] = {key = item.key, button = b}
        end
    else
        for i, item in ipairs(tabItems) do
            local b = button(f, item.label, (i - 1) * 116, -47, item.width, function() switchTab(item.key) end, 30)
            b.activeMark = b:CreateTexture(nil, 'OVERLAY')
            b.activeMark:SetPoint('BOTTOMLEFT', b, 'BOTTOMLEFT', 8, 2)
            b.activeMark:SetSize(item.width - 16, 2)
            b.activeMark:SetColorTexture(unpack(OldKraken.UIStyle.Colors.brandGold))
            b.activeMark:SetAlpha(0)
            b.activeMark:Hide()
            f.tabs[#f.tabs + 1] = {key = item.key, button = b}
        end
    end

    -- Header notification chip (right side of the shared header row)
    f.alertButton = button(f, T('Сповіщення: увімк.'), 732, 0, 168, function()
        if Finder:SetGroupAlertsEnabled(not Finder:GroupAlertsEnabled()) then refresh()
        else print(T('Old Kraken: не вдалося зберегти налаштування сповіщень.')) end
    end, 31)
    local alertLabel = f.alertButton:GetFontString()
    if alertLabel then
        if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(alertLabel, 12) end
        local mutedText = OldKraken.UIStyle.Colors and OldKraken.UIStyle.Colors.mutedText
        if mutedText then alertLabel:SetTextColor(mutedText[1], mutedText[2], mutedText[3]) end
        alertLabel:ClearAllPoints()
        alertLabel:SetPoint('LEFT', f.alertButton, 'LEFT', 24, 0)
        alertLabel:SetPoint('RIGHT', f.alertButton, 'RIGHT', -8, 0)
        alertLabel:SetWordWrap(false)
    end
    f.alertDot = f.alertButton:CreateTexture(nil, 'OVERLAY')
    f.alertDot:SetSize(8, 8)
    f.alertDot:SetPoint('LEFT', f.alertButton, 'LEFT', 10, 0)
    f.alertDot:SetColorTexture(STATUS_GREEN[1], STATUS_GREEN[2], STATUS_GREEN[3], 1)

    f.rows, f.deleteButtons = {}, {}
    f.slotMenu = CreateFrame('Frame', 'OldKrakenSlotRoleMenu', f, 'UIDropDownMenuTemplate')
    UIDropDownMenu_Initialize(f.slotMenu, function(_, level)
        for _, candidate in ipairs(roles) do
            local choice = candidate
            local info = UIDropDownMenu_CreateInfo()
            info.text = T('Подати заявку: ') .. roleLabel(choice)
            info.disabled = not Finder:CanPerformRole(Finder.identity,choice)
            info.notCheckable = true
            info.func = function()
                local key = f.slotMenu.groupKey
                local group = key and Finder.groups[key]
                if not group or group.owner == Finder.identity or group.closed or #group.members >= group.maxSize
                    or Finder.pending[key] == 'pending' then return end
                for _, name in ipairs(group.members) do if name == Finder.identity then return end end
                if Finder:Apply(group.owner, group.id, choice) then Finder:Changed(); refresh()
                else print(T('Old Kraken: не вдалося подати заявку. Перевірте зв’язок.')) end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end, 'MENU')

    -- Scrollable group list (left column: 554 x 400) + footer caption
    f.listScroll = CreateFrame('ScrollFrame', 'OldKrakenGroupListScroll', f, 'UIPanelScrollFrameTemplate')
    if OldKraken.UIStyle.ScrollBar then OldKraken.UIStyle.ScrollBar(f.listScroll) end
    f.listScroll:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, -179)
    f.listScroll:SetSize(534, 400)
    f.listScroll:EnableMouseWheel(true)
    f.listContent = CreateFrame('Frame', nil, f.listScroll)
    f.listContent:SetSize(534, 1)
    f.listScroll:SetScrollChild(f.listContent)
    f.listScroll:SetScript('OnMouseWheel', function(self, delta)
        if OldKraken.UIHub and OldKraken.UIHub.HandleScaleWheel and OldKraken.UIHub:HandleScaleWheel(delta) then return end
        local current = tonumber((self:GetVerticalScroll())) or 0
        local maxScroll = math.max(0, (tonumber((f.listContent:GetHeight())) or 0) - (tonumber((self:GetHeight())) or 400))
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, current - delta * CARD_STEP)))
        refresh()
    end)
    local previousListScroll = f.listScroll:GetScript('OnVerticalScroll')
    f.listScroll:SetScript('OnVerticalScroll', function(self, value)
        if previousListScroll then previousListScroll(self, value) end
        refresh()
    end)

    f.listSummary = f:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    f.listSummary:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, -588)
    f.listSummary:SetJustifyH('LEFT')
    local muted = OldKraken.UIStyle.Colors and OldKraken.UIStyle.Colors.mutedText
    if muted then f.listSummary:SetTextColor(muted[1], muted[2], muted[3]) end

    local function resetAllFilters()
        filterCategory, filterRole, filterFree, filterDungeon = 'all', '', false, ''
        f.searchFilter:SetText('')
        f.minLevelFilter:SetText('')
        f.maxLevelFilter:SetText('')
        UIDropDownMenu_SetText(f.categoryFilter, T('Категорія: усі'))
        UIDropDownMenu_SetText(f.roleFilter, T('Роль: усі'))
        UIDropDownMenu_SetText(f.freeFilter, T('Усі групи'))
        UIDropDownMenu_SetText(f.dungeonFilter, dungeonLabels[''] or T('Підземелля: усі'))
        offset = 0
        refresh()
    end

    f.emptyList = f:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
    f.emptyList:SetPoint('TOP', f.listScroll, 'TOP', 0, -135)
    f.emptyList:SetWidth(460); f.emptyList:SetJustifyH('CENTER')
    if type(f.emptyList.SetSpacing) == 'function' then f.emptyList:SetSpacing(5) end
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(f.emptyList, 14) end
    f.emptyList:SetText(T('Доступних груп поки немає.\nСтворіть перше оголошення для гільдії.'))
    f.emptyAction = button(f, T('Створити оголошення'), 182, -365, 190, function()
        local hasFilters = filterCategory ~= 'all' or filterRole ~= '' or filterFree or filterDungeon ~= ''
            or (f.searchFilter:GetText() or '') ~= '' or (f.minLevelFilter:GetText() or '') ~= '' or (f.maxLevelFilter:GetText() or '') ~= ''
        if tab == 'all' and hasFilters then
            resetAllFilters()
            return
        elseif tab == 'applications' then tab = 'all'
        else tab = 'create' end
        selected = nil; offset = 0; refresh()
    end, 38, 'primary')
    f.emptyAction:ClearAllPoints()
    f.emptyAction:SetPoint('TOP', f.emptyList, 'BOTTOM', 0, -16)

    for i = 1, 6 do ensureGroupCard(f, i) end

    -- Right column: details panel (330 x 428 at 570, -179)
    if OldKraken.UIStyle.PanelFrame then
        f.detailPanel = OldKraken.UIStyle.PanelFrame(f, 'buttonEdge')
    else
        f.detailPanel = CreateFrame('Frame', nil, f)
        OldKraken.UIStyle.Panel(f.detailPanel, 0, 0, 330, 428)
    end
    f.detailPanel:SetSize(330, 428)
    f.detailPanel:SetPoint('TOPLEFT', f, 'TOPLEFT', 570, -179)

    f.detailsScroll = CreateFrame('ScrollFrame', 'OldKrakenGroupDetailsScroll', f, 'UIPanelScrollFrameTemplate')
    if OldKraken.UIStyle.ScrollBar then OldKraken.UIStyle.ScrollBar(f.detailsScroll) end
    if type(f.detailsScroll.SetFrameLevel) == 'function' then
        f.detailsScroll:SetFrameLevel(((type(f.detailPanel.GetFrameLevel) == 'function' and f.detailPanel:GetFrameLevel()) or 1) + 5)
    end
    f.detailsScroll:SetPoint('TOPLEFT', f, 'TOPLEFT', 587, -196); f.detailsScroll:SetSize(276, 276)
    if f.detailsScroll.SetClipsChildren then pcall(f.detailsScroll.SetClipsChildren, f.detailsScroll, true) end
    local previousDetailsScroll=f.detailsScroll:GetScript('OnVerticalScroll')
    local detailsScrollPending=false
    f.detailsScroll:SetScript('OnVerticalScroll',function(self,value)
        if previousDetailsScroll then previousDetailsScroll(self,value) end
        if detailsScrollPending then return end
        local function update() detailsScrollPending=false; refresh() end
        if C_Timer and C_Timer.After then detailsScrollPending=true; C_Timer.After(0,update) else update() end
    end)
    f.detailsContent = CreateFrame('Frame', nil, f.detailsScroll)
    f.detailsContent:SetSize(276, 86); f.detailsScroll:SetScrollChild(f.detailsContent)
    f.details = f.detailsContent:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
    f.details:SetPoint('TOPLEFT'); f.details:SetWidth(276); f.details:SetJustifyH('LEFT'); f.details:SetJustifyV('TOP')
    f.detailsHeading = f.detailsContent:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
    f.detailsHeading:SetPoint('TOPLEFT', f.detailsContent, 'TOPLEFT', 0, 0)
    f.detailsHeading:SetWidth(276); f.detailsHeading:SetJustifyH('LEFT'); f.detailsHeading:SetWordWrap(false)
    local goldColor = OldKraken.UIStyle.Colors and OldKraken.UIStyle.Colors.brandGold
    if goldColor then f.detailsHeading:SetTextColor(goldColor[1], goldColor[2], goldColor[3]) end
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(f.detailsHeading, 16, true) end
    f.detailsHeading:Hide()
    f.detailsKV = {}
    for idx, labelText in ipairs({T('Автор'), T('Рівні'), T('Роль'), T('Статус'), T('Опис')}) do
        local rowY = -30 - (idx - 1) * 26
        local k = f.detailsContent:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        k:SetPoint('TOPLEFT', f.detailsContent, 'TOPLEFT', 0, rowY)
        k:SetWidth(70); k:SetJustifyH('LEFT')
        if muted then k:SetTextColor(muted[1], muted[2], muted[3]) end
        if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(k, 12) end
        k:SetText(labelText); k:Hide()
        local v = f.detailsContent:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
        v:SetPoint('TOPLEFT', f.detailsContent, 'TOPLEFT', 78, rowY)
        v:SetWidth(198); v:SetJustifyH('LEFT'); v:SetWordWrap(idx == 5)
        if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(v, 13) end
        v:Hide()
        f.detailsKV[idx] = {key = k, val = v}
    end
    f.editDescButton = button(f.detailsContent, T('Змінити'), 206, -132, 70, function()
        local g = selected and Finder.groups[selected]
        if not g or g.owner ~= Finder.identity or g.hidden then return end
        editingDescriptionKey = selected
        f.editDescBox:SetText(g.description or '')
        refresh()
        if type(f.editDescBox.SetFocus) == 'function' then f.editDescBox:SetFocus() end
    end, 20, nil, {rounded = true})
    local editLbl = type(f.editDescButton.GetFontString) == 'function' and f.editDescButton:GetFontString()
    if type(editLbl) == 'table' and OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(editLbl, 11) end
    f.editDescButton:Hide()

    f.editDescBox = CreateFrame('EditBox', nil, f.detailsContent, 'InputBoxTemplate')
    OldKraken.UIStyle.Input(f.editDescBox)
    f.editDescBox:SetSize(276, 26); f.editDescBox:SetPoint('TOPLEFT', f.detailsContent, 'TOPLEFT', 0, -156)
    f.editDescBox:SetAutoFocus(false)
    local function saveEditedDescription()
        local g = selected and Finder.groups[selected]
        if not g or g.owner ~= Finder.identity or g.hidden then editingDescriptionKey = nil; refresh(); return end
        local text = (f.editDescBox:GetText() or ''):match('^%s*(.-)%s*$')
        local ok, reason = Finder:UpdateDescription(g.id, text)
        if ok then
            editingDescriptionKey = nil
            Finder:Changed()
            refresh()
        elseif reason == 'revision' then
            print(T('Old Kraken: досягнуто межі ревізії групи; створіть новий набір.'))
        else
            print(T('Old Kraken: не вдалося оновити опис. Перевірте довжину тексту та зв’язок.'))
        end
    end
    f.editDescBox:SetScript('OnEnterPressed', saveEditedDescription)
    f.editDescBox:SetScript('OnEscapePressed', function(self) self:ClearFocus(); editingDescriptionKey = nil; refresh() end)
    f.editDescBox:Hide()

    f.saveDescButton = button(f.detailsContent, T('Ок'), 208, -130, 38, saveEditedDescription, 22, 'primary', {rounded = true})
    f.saveDescButton:Hide()
    f.cancelDescButton = button(f.detailsContent, '×', 250, -130, 26, function() editingDescriptionKey = nil; refresh() end, 22, nil, {rounded = true})
    f.cancelDescButton:Hide()
    f.detailsDivider = f.detailsContent:CreateTexture(nil, 'ARTWORK')
    f.detailsDivider:SetPoint('TOPLEFT', f.detailsContent, 'TOPLEFT', 0, -166)
    f.detailsDivider:SetSize(276, 1)
    local divColor = OldKraken.UIStyle.Colors and OldKraken.UIStyle.Colors.divider or {0.20, 0.23, 0.29, 0.85}
    f.detailsDivider:SetColorTexture(unpack(divColor))
    f.detailsDivider:Hide()
    f.detailsRosterHeader = f.detailsContent:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
    f.detailsRosterHeader:SetPoint('TOPLEFT', f.detailsContent, 'TOPLEFT', 0, -180)
    f.detailsRosterHeader:SetWidth(276); f.detailsRosterHeader:SetJustifyH('LEFT')
    if goldColor then f.detailsRosterHeader:SetTextColor(goldColor[1], goldColor[2], goldColor[3]) end
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(f.detailsRosterHeader, 13, true) end
    f.detailsRosterHeader:SetText(T('Склад групи')); f.detailsRosterHeader:Hide()
    f.memberRows = {}
    f.requestsButton = button(f, T('Заявки'), 587, -514, 296, function()
        if requestsWindow and requestsWindow:IsShown() then requestsWindow:Hide(); refresh() else showRequests() end
    end, 30, nil, {rounded = true})
    if type(f.requestsButton.SetFrameLevel) == 'function' then
        f.requestsButton:SetFrameLevel(((type(f.detailPanel.GetFrameLevel) == 'function' and f.detailPanel:GetFrameLevel()) or 1) + 5)
    end

    -- Filters bar (one row in a 900 x 60 bordered panel above the list)
    if OldKraken.UIStyle.PanelFrame then
        f.filterPanel = OldKraken.UIStyle.PanelFrame(f, 'buttonEdge')
    else
        f.filterPanel = CreateFrame('Frame', nil, f)
        OldKraken.UIStyle.Panel(f.filterPanel, 0, 0, 900, 60)
    end
    f.filterPanel:SetSize(900, 60)
    f.filterPanel:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, -103)

    f.searchFilter = CreateFrame('EditBox', nil, f, 'InputBoxTemplate')
    OldKraken.UIStyle.Input(f.searchFilter)
    f.searchFilter:SetSize(170, 34); f.searchFilter:SetPoint('TOPLEFT', f, 'TOPLEFT', 13, -116)
    f.searchFilter:SetAutoFocus(false); f.searchFilter:SetTextInsets(8, 8, 0, 0); f.searchFilter:SetText('')
    f.searchFilter.label = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    f.searchFilter.label:Hide()
    f.searchHint = f.searchFilter:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    f.searchHint:SetPoint('LEFT', f.searchFilter, 'LEFT', 10, 0)
    f.searchHint:SetText(T('Пошук групи'))
    if muted then f.searchHint:SetTextColor(muted[1], muted[2], muted[3]) end
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(f.searchHint, 13) end
    f.searchFilter:SetScript('OnEscapePressed', function(self) self:ClearFocus() end)
    f.searchFilter:SetScript('OnTextChanged', function(self)
        if f.searchHint then
            local text = (self and self.GetText and self:GetText()) or (f.searchFilter.GetText and f.searchFilter:GetText()) or ''
            f.searchHint:SetShown(text == '')
        end
        offset=0; refresh()
    end)

    f.dungeonFilter = dropdown(f, 193, -117, 170, activityOptions,
        function() return filterDungeon end, function(value) filterDungeon=value; offset=0; refresh() end)
    UIDropDownMenu_SetText(f.dungeonFilter, T('Підземелля: усі'))
    f.dungeonFilterLabel = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    f.dungeonFilterLabel:Hide()

    f.categoryFilter = dropdown(f, 373, -117, 156, choices(categories, categoryLabels, {value='all', label=T('Категорія: усі')}),
        function() return filterCategory end, function(value) filterCategory=value; offset=0; refresh() end)
    f.roleFilter = dropdown(f, 539, -117, 110, choices({'tank','healer','dps'}, coloredRoleLabels, {value='', label=T('Роль: усі')}),
        function() return filterRole end, function(value) filterRole=value; offset=0; refresh() end)
    f.freeFilter = dropdown(f, 539, -117, 110, {{value=false, label=T('Усі групи')}, {value=true, label=T('Є місця')}},
        function() return filterFree end, function(value) filterFree=value; offset=0; refresh() end)
    f.freeFilter:Hide()

    f.levelRangeLabel = f.filterPanel:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    f.levelRangeLabel:SetPoint('TOPLEFT', f, 'TOPLEFT', 659, -127)
    f.levelRangeLabel:SetText(T('Рівень'))
    if muted then f.levelRangeLabel:SetTextColor(muted[1], muted[2], muted[3]) end
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(f.levelRangeLabel, 12) end

    f.minLevelFilter = CreateFrame('EditBox', nil, f, 'InputBoxTemplate')
    OldKraken.UIStyle.Input(f.minLevelFilter)
    f.minLevelFilter:SetSize(44, 34); f.minLevelFilter:SetPoint('TOPLEFT', f, 'TOPLEFT', 704, -116)
    f.minLevelFilter:SetAutoFocus(false); f.minLevelFilter:SetTextInsets(6, 6, 0, 0); f.minLevelFilter:SetText('')
    f.minLevelFilter.label = f.levelRangeLabel
    f.minLevelHint = f.minLevelFilter:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    f.minLevelHint:SetPoint('CENTER', f.minLevelFilter, 'CENTER', 0, 0); f.minLevelHint:SetText(T('від'))
    if muted then f.minLevelHint:SetTextColor(muted[1], muted[2], muted[3]) end
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(f.minLevelHint, 13) end
    f.minLevelFilter:SetScript('OnEscapePressed', function(self) self:ClearFocus() end)
    f.minLevelFilter:SetScript('OnTextChanged', function(self)
        if f.minLevelHint then
            local text = (self and self.GetText and self:GetText()) or (f.minLevelFilter.GetText and f.minLevelFilter:GetText()) or ''
            f.minLevelHint:SetShown(text == '')
        end
        offset=0; refresh()
    end)

    f.levelDash = f.filterPanel:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    f.levelDash:SetPoint('TOPLEFT', f, 'TOPLEFT', 754, -127); f.levelDash:SetText('–')
    if muted then f.levelDash:SetTextColor(muted[1], muted[2], muted[3]) end
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(f.levelDash, 13) end

    f.maxLevelFilter = CreateFrame('EditBox', nil, f, 'InputBoxTemplate')
    OldKraken.UIStyle.Input(f.maxLevelFilter)
    f.maxLevelFilter:SetSize(44, 34); f.maxLevelFilter:SetPoint('TOPLEFT', f, 'TOPLEFT', 767, -116)
    f.maxLevelFilter:SetAutoFocus(false); f.maxLevelFilter:SetTextInsets(6, 6, 0, 0); f.maxLevelFilter:SetText('')
    f.maxLevelHint = f.maxLevelFilter:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    f.maxLevelHint:SetPoint('CENTER', f.maxLevelFilter, 'CENTER', 0, 0); f.maxLevelHint:SetText(T('до'))
    if muted then f.maxLevelHint:SetTextColor(muted[1], muted[2], muted[3]) end
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(f.maxLevelHint, 13) end
    f.maxLevelFilter:SetScript('OnEscapePressed', function(self) self:ClearFocus() end)
    f.maxLevelFilter:SetScript('OnTextChanged', function(self)
        if f.maxLevelHint then
            local text = (self and self.GetText and self:GetText()) or (f.maxLevelFilter.GetText and f.maxLevelFilter:GetText()) or ''
            f.maxLevelHint:SetShown(text == '')
        end
        offset=0; refresh()
    end)
    -- Backward-compatible alias for single-input callers
    f.levelFilter = f.minLevelFilter

    f.resetFilterButton = button(f, T('Скинути'), 824, -119, 63, resetAllFilters, 28)
    local resetText = f.resetFilterButton:GetFontString()
    local gold = OldKraken.UIStyle.Colors and OldKraken.UIStyle.Colors.brandGold
    if resetText and gold then resetText:SetTextColor(gold[1], gold[2], gold[3]) end

    f.filterControls = {
        f.filterPanel, f.searchFilter, f.dungeonFilter,
        f.levelRangeLabel, f.minLevelFilter, f.levelDash, f.maxLevelFilter,
        f.categoryFilter, f.roleFilter, f.resetFilterButton,
    }
    f.titleBox = input(f, T('Назва'), 20, -330, 240, '')
    f.descriptionBox = input(f, T('Опис'), 275, -330, 250, '')
    f.maxBox = input(f, T('Місць'), 20, -385, 65, '5')
    f.maxBox:SetScript('OnEnter', function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, 'ANCHOR_TOP')
            GameTooltip:SetText(T('Загальний розмір групи разом із вами (1–200).'))
            GameTooltip:Show()
        end
    end)
    f.maxBox:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
    f.minBox = input(f, T('Мін. рівень'), 105, -385, 80, '1')
    f.maxLevelBox = input(f, T('Макс. рівень'), 205, -385, 80, '60')
    f.createFields = {f.titleBox, f.descriptionBox, f.maxBox, f.minBox, f.maxLevelBox}
    local autoDungeonTitle
    f.categoryButton = dropdown(f, 305, -408, 140, choices(categories, categoryLabels),
        function() return category end, function(value)
            local previousCategory=category
            category=value
            if category ~= previousCategory then
                if autoDungeonTitle and f.titleBox:GetText() == autoDungeonTitle then f.titleBox:SetText('') end
                autoDungeonTitle=nil
                dungeon=''; f.dungeonSelection:SetText(T('Без конкретного підземелля'))
            end
            if category == 'dungeon' then
                f.maxBox:SetText('5')
                if role == 'flex' or role == '' then role='dps' end
            end
            refresh()
        end)
    f.categoryLabel = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    f.categoryLabel:SetPoint('TOPLEFT', f, 'TOPLEFT', 305, -389); f.categoryLabel:SetText(T('Категорія'))
    f.roleButton = createRoleSelector(f, 587, -502, 296)
    f.roleButton:Update(category)
    f.roleLabel = f.roleButton:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(f.roleLabel, 13, true) end
    local roleLabelMuted = OldKraken.UIStyle.Colors and OldKraken.UIStyle.Colors.mutedText
    if roleLabelMuted then f.roleLabel:SetTextColor(roleLabelMuted[1], roleLabelMuted[2], roleLabelMuted[3]) end
    f.roleLabel:SetPoint('TOPLEFT', f, 'TOPLEFT', 587, -484); f.roleLabel:SetText(T('Ваша роль у групі:'))
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
            if recommended.size then f.maxBox:SetText(tostring(recommended.size)) end
        end
        f.dungeonSelection:SetText(value~='' and dungeonLabels[value] or T('Без конкретного підземелля'))
        f.UpdateActivityCards()
        refresh()
    end
    -- An inline, clipped three-column grid. No popup or additional click is needed.
    local picker=CreateFrame('Frame',nil,f)
    picker:SetSize(840,442); picker:SetPoint('TOPLEFT',f,'TOPLEFT',18,-100)
    picker:EnableMouse(true); picker:EnableMouseWheel(true)
    local colors = OldKraken.UIStyle.Colors or {}
    local bgColor = colors.panel or {0.055, 0.07, 0.095, 0.96}
    local background=picker:CreateTexture(nil,'BACKGROUND')
    background:SetAllPoints(picker); background:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], 1)
    picker.heading=picker:CreateFontString(nil,'OVERLAY','GameFontNormal')
    picker.heading:SetPoint('TOPLEFT',picker,'TOPLEFT',10,-8)
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(picker.heading, 14, true) end
    local hint=picker:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    hint:SetPoint('LEFT',picker.heading,'RIGHT',14,0)
    hint:SetText(T('Підсвічено під ваш рівень · прокрутка коліщатком'))
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(hint, 12) end
    if colors.mutedText then hint:SetTextColor(colors.mutedText[1], colors.mutedText[2], colors.mutedText[3]) end
    picker.clear=button(picker,T('Без конкретного підземелля'),605,-4,225,function() selectActivity('') end)
    local clip=CreateFrame('Frame',nil,picker)
    clip:SetPoint('TOPLEFT',picker,'TOPLEFT',6,-36); clip:SetSize(808,396)
    if clip.SetClipsChildren then pcall(clip.SetClipsChildren,clip,true) end
    local content=CreateFrame('Frame',nil,clip)
    content:SetPoint('TOPLEFT',clip,'TOPLEFT',0,0); content:SetSize(808,1)
    picker.clip=clip; picker.content=content; picker.cards={}; picker.offset=0; picker.viewportHeight=396; picker.fullHeight=1
    function picker:ScrollTo(value)
        local maximum=math.max(0,(self.fullHeight or 0)-(self.viewportHeight or 407))
        self.offset=math.max(0,math.min(maximum,value or 0))
        content:ClearAllPoints(); content:SetPoint('TOPLEFT',clip,'TOPLEFT',0,self.offset)
    end
    local function scrollActivities(_,delta)
        if OldKraken.UIHub and OldKraken.UIHub.HandleScaleWheel and OldKraken.UIHub:HandleScaleWheel(delta) then return end
        picker:ScrollTo(picker.offset-delta*70)
    end
    picker:SetScript('OnMouseWheel',scrollActivities)
    clip:EnableMouseWheel(true); clip:SetScript('OnMouseWheel',scrollActivities)
    f.activityPicker=picker
    picker:Hide()
    f.dungeonSelection=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    f.dungeonSelection:SetPoint('TOPLEFT',f,'TOPLEFT',460,-408)
    f.dungeonSelection:SetSize(350,30); f.dungeonSelection:SetJustifyH('LEFT')
    f.dungeonSelection:SetText(T('Без конкретного підземелля'))
    f.UpdateActivityCards=function()
        picker.heading:SetText(category=='raid' and T('Оберіть рейд') or T('Куди йдемо?'))
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
                            GameTooltip:AddLine(T('Рекомендовані рівні: ')..self.entry.min..'–'..self.entry.max,1,1,1,true)
                            if self.levelNote then GameTooltip:AddLine(self.levelNote,self.levelColor[1],self.levelColor[2],self.levelColor[3],true) end
                            GameTooltip:Show()
                        end
                    end)
                    card:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
                    picker.cards[count]=card
                end
                local fits=level==0 or (entry.min and entry.max and level>=entry.min-2 and level<=entry.max+2)
                local tooLow=level>0 and entry.min and level<entry.min-2
                local tooHigh=level>0 and entry.max and level>entry.max+2
                if fits and not firstFit then firstFit=count end
                if entry.value==dungeon then selectedIndex=count end
                card.entry=entry; card.fitsLevel=fits and true or false
                if tooLow then
                    card.levelNote=T('Ваш рівень нижчий за рекомендований'); card.levelColor={1,0.48,0.43}
                elseif tooHigh then
                    card.levelNote=T('Ваш рівень вищий за рекомендований'); card.levelColor={0.61,0.66,0.74}
                else
                    card.levelNote=nil; card.levelColor=nil
                end
                catalog.SetArtwork(card.art,entry.value); card.art:SetDesaturated(not fits); card.art:SetAlpha(fits and 1 or 0.65)
                card.selected=entry.value==dungeon
                card.title:SetText(entry.label)
                if card.selected then
                    card.title:SetTextColor(1,1,1)
                    card.fill:SetColorTexture(0.15,0.21,0.44,1)
                else
                    card.title:SetTextColor(fits and 1 or 0.8,fits and 0.91 or 0.8,fits and 0.65 or 0.8)
                    card.fill:SetColorTexture(fits and 0.14 or 0.06,fits and 0.11 or 0.065,0.06,1)
                end
                local levelBadge = fits and T('  |cff69dc8cпід ваш рівень|r') or (tooLow and T('  |cffff7a6eнизький рівень|r') or (tooHigh and T('  |cff9ba9bcвище рівня|r') or ''))
                card.levels:SetText(entry.min..'–'..entry.max..levelBadge)
                local r,g,b=0.23,0.25,0.28
                local thickness=1
                if card.selected then r,g,b=0.45,0.60,1.0; thickness=2
                elseif fits then r,g,b=0.55,0.42,0.16 end
                for idx,edge in ipairs(card.edges) do
                    edge:SetColorTexture(r,g,b,1)
                    if idx<=2 then edge:SetHeight(thickness) else edge:SetWidth(thickness) end
                end
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
        if OldKraken.UIStyle and OldKraken.UIStyle.ApplySelection then
            OldKraken.UIStyle.ApplySelection(picker.clear, dungeon == '')
        end
    end
    f.dungeonLabel = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    f.dungeonLabel:SetPoint('TOPLEFT', f, 'TOPLEFT', 460, -389); f.dungeonLabel:SetText(T('Підземелля'))
    local function truncateUtf8Bytes(text, limit)
        if type(text) ~= 'string' or #text <= limit then return text or '' end
        if limit <= 0 then return '' end
        local cut = limit
        local nextByte = text:byte(cut + 1)
        if nextByte and nextByte >= 128 and nextByte < 192 then
            while cut > 0 do
                local b = text:byte(cut)
                cut = cut - 1
                if not b or b < 128 or b >= 192 then break end
            end
        end
        return text:sub(1, cut)
    end
    local function announceGroupInGuildChat(activityName, currentCount, maxPlayers, minLv, maxLv, descText, group)
        if type(IsInGuild) ~= 'function' or not IsInGuild() then return end
        local sendChat = (type(SendChatMessage) == 'function' and SendChatMessage)
            or (C_ChatInfo and type(C_ChatInfo.SendChatMessage) == 'function' and C_ChatInfo.SendChatMessage)
        if not sendChat then
            print(T('|cffff5555Old Kraken|r: API відправки в гільд-чат недоступне.'))
            return
        end
        local maxSize = maxPlayers or 5
        local count = currentCount or 1
        local metaParts = {}
        if minLv and maxLv and minLv > 0 and maxLv > 0 then
            metaParts[#metaParts + 1] = minLv == maxLv and ('lvl ' .. minLv) or ('lvl ' .. minLv .. '–' .. maxLv)
        end
        if type(group) == 'table' and group.category == 'dungeon' and maxSize == 5 and type(Finder.DungeonSlots) == 'function' then
            local slots = Finder:DungeonSlots(group)
            local extra = math.max(0, count - (type(group.members) == 'table' and #group.members or 1))
            local counts = {tank = 0, healer = 0, dps = 0}
            for i = #slots, 1, -1 do
                local slot = slots[i]
                if not slot.member then
                    if extra > 0 then
                        extra = extra - 1
                    elseif counts[slot.role] ~= nil then
                        counts[slot.role] = counts[slot.role] + 1
                    end
                end
            end
            local roleParts = {}
            for _, r in ipairs({'tank', 'healer', 'dps'}) do
                local n = counts[r]
                if n > 0 then
                    local label = roleLabels[r] or r
                    roleParts[#roleParts + 1] = n > 1 and (n .. ' ' .. label) or label
                end
            end
            if #roleParts > 0 then
                metaParts[#metaParts + 1] = T('потрібні: ') .. table.concat(roleParts, ', ')
            end
        else
            local freeSlots = math.max(0, maxSize - count)
            if freeSlots > 0 then
                metaParts[#metaParts + 1] = string.format(T('вільно: %d'), freeSlots)
            end
        end
        local cleanActivity = tostring(activityName or ''):gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')
        local prefix = '{rt8} LFG ' .. cleanActivity .. (#metaParts > 0 and (' · ' .. table.concat(metaParts, ' · ')) or '')
        local suffix = T(' »»» Old Kraken · Групи') .. ' {rt8}'
        local note = ((descText or ''):gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')):match('^%s*(.-)%s*$')
        local maxBytes = 255
        if #prefix + #suffix > maxBytes then
            local ellipsis = '…'
            prefix = truncateUtf8Bytes(prefix, math.max(0, maxBytes - #suffix - #ellipsis)) .. ellipsis
        end
        local notePart = ''
        if note ~= '' then
            local sep = ' · '
            local budget = maxBytes - #prefix - #suffix - #sep
            if budget > 4 then
                if #note > budget then
                    local ellipsis = '…'
                    note = truncateUtf8Bytes(note, budget - #ellipsis) .. ellipsis
                end
                notePart = sep .. note
            end
        end
        local msg = prefix .. notePart .. suffix
        local sent, err = pcall(sendChat, msg, 'GUILD')
        if not sent then print(T('|cffff5555Old Kraken|r: не вдалося надіслати анонс у гільд-чат: ') .. tostring(err)) end
    end
    local function createErrorMessage(err, titleText, maxText, minText, maxLevelText)
        if err == 'role' then return T('Old Kraken: оберіть вашу роль у групі.') end
        if err == 'class_role' then return T('Old Kraken: обрана роль недоступна для вашого класу.') end
        if err == 'dungeon_size' then return T('Old Kraken: для підземелля кількість місць має дорівнювати 5.') end
        if err == 'roles' then return T('Old Kraken: для підземелля потрібна роль танка, лікаря або DPS.') end
        if err == 'capacity' then return T('Old Kraken: досягнуто ліміт активних оголошень.') end
        if err == 'queue' then return T('Old Kraken: не вдалося надіслати оголошення. Перевірте, чи ви в гільдії та стан зв’язку (/okr comm status).') end
        if err == 'invalid' then
            if titleText == '' or #titleText > 100 then
                return T('Old Kraken: введіть назву групи (1–100 символів) або оберіть підземелля.')
            end
            local maxNum = tonumber(maxText)
            if not maxNum or maxNum % 1 ~= 0 or maxNum < 1 or maxNum > 200 then
                return T('Old Kraken: кількість місць має бути цілим числом від 1 до 200.')
            end
            local minLv, maxLv = tonumber(minText), tonumber(maxLevelText)
            if not minLv or not maxLv or minLv % 1 ~= 0 or maxLv % 1 ~= 0 or minLv < 1 or maxLv > 255 or minLv > maxLv then
                return T('Old Kraken: перевірте діапазон рівнів (мін. <= макс., від 1 до 255).')
            end
            return T('Old Kraken: перевірте коректність заповнених полів.')
        end
        return T('Old Kraken: перевірте поля, доступність ролі та стан зв’язку. Для підземелля потрібна роль танка, лікаря або DPS.')
    end
    f.announceGuildEnabled = true
    f.createButton = button(f, T('Створити'), 550, -455, 150, function()
        local titleText = (f.titleBox:GetText() or ''):match('^%s*(.-)%s*$')
        local maxPlayers = category == 'dungeon' and '5' or f.maxBox:GetText()
        local ok, err = Finder:Create(f.titleBox:GetText(), category, f.descriptionBox:GetText(), maxPlayers, f.minBox:GetText(), f.maxLevelBox:GetText(), role, dungeon)
        if ok then
            if type(Finder.SyncPartyNow) == 'function' then Finder:SyncPartyNow() end
            if f.announceGuildEnabled then
                local createdGroup = Finder.identity and err and Finder.groups and Finder.groups[Finder.identity .. '\001' .. err]
                local currentCount = (type(createdGroup) == 'table' and type(createdGroup.members) == 'table' and #createdGroup.members) or 1
                if type(IsInGroup) == 'function' and IsInGroup() and type(GetNumGroupMembers) == 'function' then
                    local okCount, partyCount = pcall(GetNumGroupMembers)
                    if okCount and type(partyCount) == 'number' and partyCount > currentCount then
                        currentCount = math.min(tonumber(maxPlayers) or partyCount, partyCount)
                    end
                end
                local activityName = titleText ~= '' and titleText or ((dungeon ~= '' and dungeonLabels[dungeon]) or categoryLabels[category] or T('Група'))
                announceGroupInGuildChat(activityName, currentCount, tonumber(maxPlayers) or 5, tonumber(f.minBox:GetText()), tonumber(f.maxLevelBox:GetText()), f.descriptionBox:GetText(), createdGroup)
            end
            Finder:Changed(); tab='mine'; refresh()
        else print(createErrorMessage(err, titleText, maxPlayers, f.minBox:GetText(), f.maxLevelBox:GetText())) end
    end, nil, 'primary')
    f.advancedCreation=false
    local colors = OldKraken.UIStyle.Colors or {}
    local panelBg = colors.panel or {0.055, 0.07, 0.095, 0.96}
    local footer=CreateFrame('Frame',nil,f)
    footer:SetSize(844,46); footer:SetPoint('TOPLEFT',f,'TOPLEFT',18,-552)
    local footerFill=footer:CreateTexture(nil,'BACKGROUND'); footerFill:SetAllPoints(footer); footerFill:SetColorTexture(panelBg[1], panelBg[2], panelBg[3], 1)
    f.creationFooter=footer
    f.creationArt=footer:CreateTexture(nil,'ARTWORK'); f.creationArt:SetSize(36,28); f.creationArt:SetPoint('TOPLEFT',footer,'TOPLEFT',3,-8)
    f.dungeonSelection:SetParent(footer); f.dungeonSelection:ClearAllPoints()
    f.dungeonSelection:SetPoint('TOPLEFT',footer,'TOPLEFT',43,-7); f.dungeonSelection:SetSize(145,32)
    f.creationRoles={}
    local roleChipWidths = {tank = 52, healer = 56, dps = 48, flex = 64}
    local roleChipTitles = {tank = T('Танк'), healer = T('Лікар'), dps = 'DPS', flex = T('Гнучка')}
    local chipX = 194
    for i,value in ipairs({'tank','healer','dps'}) do
        local chosen=value
        local chipW = roleChipWidths[value] or 54
        local control=button(footer,roleChipTitles[value] or value,chipX,-8,chipW,function() role=chosen; refresh() end,28,nil,{rounded=true})
        control.role=value
        local label = control:GetFontString()
        if label and OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(label, 12) end
        control.active=control:CreateTexture(nil,'OVERLAY')
        control.active:SetPoint('BOTTOMLEFT',control,'BOTTOMLEFT',6,1); control.active:SetSize(chipW-12,2); control.active:SetColorTexture(unpack(roleSlotColor(value,true)))
        control:SetScript('OnEnter',function(self) if GameTooltip then GameTooltip:SetOwner(self,'ANCHOR_TOP'); GameTooltip:SetText(roleLabel(chosen)); GameTooltip:Show() end end)
        control:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
        f.creationRoles[i]=control
        chipX = chipX + chipW + 4
    end
    f.descriptionBox:SetParent(footer); f.descriptionBox:ClearAllPoints()
    f.descriptionBox:SetPoint('TOPLEFT',footer,'TOPLEFT',364,-8); f.descriptionBox:SetSize(124,28)
    f.commentHint=footer:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    f.commentHint:SetPoint('LEFT',f.descriptionBox,'LEFT',8,0); f.commentHint:SetText(T('Коментар'))
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(f.commentHint, 12) end
    if muted then f.commentHint:SetTextColor(muted[1], muted[2], muted[3]) end
    f.descriptionBox:SetScript('OnTextChanged',function(self) f.commentHint:SetShown(self:GetText()=='') end)
    if OldKraken.UIStyle.Chip then
        f.announceGuild = OldKraken.UIStyle.Chip(footer, T('У чат'), {dot = 'success', active = true, width = 78, height = 28, rounded = true})
        f.announceGuild:SetPoint('TOPLEFT', footer, 'TOPLEFT', 494, -8)
        f.announceGuild:SetScript('OnClick', function(self)
            f.announceGuildEnabled = not f.announceGuildEnabled
            self:SetActive(f.announceGuildEnabled)
            if self.SetDotColor then self:SetDotColor(f.announceGuildEnabled and 'success' or 'neutral') end
        end)
        f.announceGuild:SetScript('OnEnter', function(self) if GameTooltip then GameTooltip:SetOwner(self, 'ANCHOR_TOP'); GameTooltip:SetText(T('Повідомити в гільд-чат про нову групу')); GameTooltip:Show() end end)
        f.announceGuild:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
    end
    f.creationOptionsButton=button(footer,T('Параметри +'),578,-8,104,function() f.advancedCreation=not f.advancedCreation; refresh() end,28,nil,{rounded=true})
    f.creationOptionsButton:SetScript('OnEnter',function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self,'ANCHOR_TOP')
            GameTooltip:SetText(T('Параметри групи'))
            GameTooltip:AddLine(T('Назва, категорія (рейд, PvP, квести), кількість місць та рівні.'),1,1,1,true)
            GameTooltip:Show()
        end
    end)
    f.creationOptionsButton:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
    f.createButton:SetParent(footer); f.createButton:ClearAllPoints()
    f.createButton:SetPoint('TOPLEFT',footer,'TOPLEFT',688,-8); f.createButton:SetSize(150,28)
    local options=CreateFrame('Frame',nil,f)
    options:SetSize(840,82); options:SetPoint('TOPLEFT',f,'TOPLEFT',18,-466)
    local optionsFill=options:CreateTexture(nil,'BACKGROUND'); optionsFill:SetAllPoints(options); optionsFill:SetColorTexture(panelBg[1], panelBg[2], panelBg[3], 1)
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
    f.applyButton = button(f, T('Подати заявку'), 587, -550, 296, function()
        local g=selected and Finder.groups[selected]
        if tab == 'all' and selected and isGroupHiddenByOfflineOwner(selected, g) then
            selected = nil
            refresh()
            return
        end
        if role == '' or not Finder:CanPerformRole(Finder.identity, role) then
            print(T('Old Kraken: оберіть доступну роль для подачі заявки.'))
            return
        end
        if g and Finder:Apply(g.owner, g.id, role) then Finder:Changed(); refresh()
        elseif g then print(T('Old Kraken: місце для цієї ролі зайняте або заявку не вдалося надіслати.')) end
    end, 40, 'primary')
    f.applicationActionButton = button(f, T('Відкликати'), 739, -550, 144, function()
        local g=selected and Finder.groups[selected]
        if not g or g.owner == Finder.identity or not Finder.pending[selected] then return end
        if Finder:DismissApplication(g.owner, g.id) then
            Finder:Changed(); selected=nil; refresh()
        else print(T('Old Kraken: не вдалося обробити заявку. Перевірте зв’язок.')) end
    end, 40)
    f.cancelButton = button(f, T('Закрити набір'), 587, -554, 144, function()
        local g=selected and Finder.groups[selected]
        if g and g.owner==Finder.identity and Finder:Cancel(g.id) then Finder:Changed(); refresh() end
    end, 36)
    f.bumpButton = button(f, T('Оновити набір'), 739, -554, 144, function()
        local group = selected and Finder.groups[selected]
        if not group or group.owner ~= Finder.identity or group.closed then return end
        local ok, reason, seconds = Finder:Reannounce(group.id)
        if ok then
            local activityName = (group.title and group.title ~= '' and displayGroupTitle(group)) or (group.dungeon and group.dungeon ~= '' and dungeonLabels[group.dungeon]) or categoryLabels[group.category] or T('Група')
            announceGroupInGuildChat(activityName, type(group.members) == 'table' and #group.members or 1, group.maxSize, group.minLevel, group.maxLevel, group.description, group)
            print(T('Old Kraken: повторне оголошення додано до черги гільдії.'))
        elseif reason == 'cooldown' then print(T('Old Kraken: повторити оголошення можна через ') .. seconds .. T(' с.'))
        else print(T('Old Kraken: не вдалося надіслати оголошення. Перевірте зв’язок.')) end
        UpdateReannounceButton(f.bumpButton)
    end, 36)
    f.reopenButton = button(f, T('Відкрити набір знову'), 587, -550, 296, function()
        local group = selected and Finder.groups[selected]
        if not group or group.owner ~= Finder.identity or not group.closed or group.hidden then return end
        local ok, reason = Finder:Reopen(group.id)
        if ok then Finder:Changed(); refresh()
        elseif reason == 'payload' then print(T('Old Kraken: оголошення завелике для повторного відкриття. Скоротіть опис або створіть новий набір.'))
        elseif reason == 'revision' then print(T('Old Kraken: досягнуто межі ревізії групи; створіть новий набір.'))
        else print(T('Old Kraken: не вдалося відкрити набір знову. Перевірте зв’язок.')) end
    end, 40, 'primary', {rounded = true})
    f.bumpButton:SetScript('OnUpdate', function(self, elapsed)
        self.countdownElapsed = (self.countdownElapsed or 0) + elapsed
        if self.countdownElapsed < 0.25 then return end
        self.countdownElapsed = 0
        UpdateReannounceButton(self)
    end)
    for _, item in ipairs({{f.cancelButton, T('Закрити набір: оголошення зникне з відкритих груп.')}, {f.bumpButton, T('Повторно сповістити гільдію про набір. Інтервал — 5 хвилин.')}}) do
        local control, help = item[1], item[2]
        control:SetScript('OnEnter', function(self) if GameTooltip then GameTooltip:SetOwner(self, 'ANCHOR_RIGHT'); GameTooltip:SetText(help); GameTooltip:Show() end end)
        control:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
    end
    return f
end

function Finder:Show()
    if not self.active then print(T('Old Kraken: пошук груп не ініціалізовано.')) return end
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
local offlineTrackingRefreshPending=false
local function scheduleRefresh()
    if scheduleRefreshPending then return end
    if not ((window and window:IsShown()) or (requestsWindow and requestsWindow:IsShown())) then return end
    local function flush()
        scheduleRefreshPending=false
        if (window and window:IsShown()) or (requestsWindow and requestsWindow:IsShown()) then if peopleDirty then refreshPeople(); peopleDirty=false end; refresh(); refreshRequests() end
    end
    if C_Timer and C_Timer.After then scheduleRefreshPending=true; C_Timer.After(0.15,flush) else flush() end
end
OldKraken:On('GROUP_FINDER_CHANGED', function(group)
    if refreshAlertRoster then refreshAlertRoster() end
    -- Start tracking newly received listings even when the window is closed.
    if group and group.owner ~= Finder.identity and not (window and window:IsShown()) and not offlineTrackingRefreshPending then
        local function updateOfflineTracking()
            offlineTrackingRefreshPending = false
            refreshPeople()
            pruneOfflineApplications()
        end
        if C_Timer and type(C_Timer.After) == 'function' then
            offlineTrackingRefreshPending = true
            C_Timer.After(0, updateOfflineTracking)
        else updateOfflineTracking() end
    end
    scheduleRefresh()
end)
local peopleEvents = CreateFrame('Frame')
peopleEvents:RegisterEvent('GUILD_ROSTER_UPDATE')
peopleEvents:RegisterEvent('GROUP_ROSTER_UPDATE')
peopleEvents:SetScript('OnEvent', function()
    peopleDirty = true
    -- Keep the offline window continuous even while the group page is hidden.
    if next(Finder.groups or {}) or next(Finder.pending or {}) then
        refreshPeople()
        pruneOfflineApplications()
    end
    scheduleRefresh()
end)
OldKraken:On('GROUP_FINDER_ALERT_SETTING', function()
    if Finder.SyncAlertVisibility then Finder:SyncAlertVisibility('group') end
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
            control:SetSize(92,91); control:SetPoint('TOPLEFT',groupAlert,'TOPLEFT',116+(i-1)*98,-61)
            control.ring=control:CreateTexture(nil,'BACKGROUND'); control.ring:SetSize(46,46); control.ring:SetPoint('TOP',control,'TOP',0,0)
            control.ring:SetTexture('Interface\\AddOns\\OldKraken\\Media\\RoleSlot.tga')
            control.icon=control:CreateTexture(nil,'ARTWORK'); control.icon:SetSize(36,36); control.icon:SetPoint('CENTER',control.ring,'CENTER',0,0)
            control.label=control:CreateFontString(nil,'OVERLAY','GameFontHighlight')
            if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(control.label, 13, false) end
            control.label:SetShadowColor(0,0,0,1); control.label:SetShadowOffset(1,-1)
            control.label:SetPoint('TOPLEFT',control,'TOPLEFT',0,-48); control.label:SetSize(92,21); control.label:SetJustifyH('CENTER'); control.label:SetWordWrap(false)
            control.vacancy=control:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
            if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(control.vacancy, 11, false) end
            control.vacancy:SetPoint('TOPLEFT',control,'TOPLEFT',0,-70); control.vacancy:SetSize(92,18)
            control.vacancy:SetJustifyH('CENTER'); control.vacancy:SetText(T('|cffbfc3caВільне місце|r'))
            control:RegisterForClicks('LeftButtonUp','RightButtonUp')
            control:SetScript('OnClick',function(self,mouseButton)
                if GameTooltip then GameTooltip:Hide() end
                if mouseButton=='LeftButton' and self and self.occupied then
                    if refreshAlertRoster then refreshAlertRoster() end
                    return
                end
                if mouseButton=='LeftButton' and self and not self.occupied then
                    local key=groupAlert.groupKey
                    local current=key and Finder.groups[key]
                    if not current or current.closed then
                        groupAlert:Hide()
                        print(T('Old Kraken: набір уже недоступний.')); return
                    end
                    if current.category=='dungeon' and current.maxSize==5 then
                        local live=Finder:DungeonSlots(current)[self.slotIndex]
                        if not live or live.member or live.role~=self.role then
                            paintAlertRoster(current)
                            if refreshAlertRoster then refreshAlertRoster() end
                            print(T('Old Kraken: це місце вже зайняте.')); return
                        end
                    elseif #current.members>=current.maxSize then
                        if refreshAlertRoster then refreshAlertRoster() end
                        print(T('Old Kraken: групу вже зібрано.')); return
                    end
                    if Finder.pending[key]=='pending' then
                        print(T('Old Kraken: заявку вже подано; очікуйте рішення автора.')); return
                    end
                    if Finder:Apply(current.owner,current.id,self.role) then
                        Finder:Changed()
                        groupAlert:Hide()
                    else
                        print(T('Old Kraken: роль уже зайнята або заявку не вдалося надіслати.'))
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
                control.memberName=member; control.role=displayedRole; control.occupied=member~=nil; control.slotIndex=i
                control:SetEnabled(member==nil and Finder:CanPerformRole(Finder.identity,displayedRole))
                control.icon:SetTexture(coords and 'Interface\\LFGFrame\\UI-LFG-ICON-ROLES' or 'Interface\\Icons\\INV_Misc_QuestionMark')
                if coords then control.icon:SetTexCoord(unpack(coords)) else control.icon:SetTexCoord(0,1,0,1) end
                control.icon:SetDesaturated(not member); control.icon:SetAlpha(member and 1 or 0.4)
                local state=not member and T('Вільне місце') or (member==group.owner and T('Автор збору') or (group.partyObserved and (group.partyObserved[member] and T('У групі') or T('Резерв')) or T('Стан групи невідомий')))
                if not member then control.ring:SetVertexColor(0.4,0.44,0.5)
                elseif group.partyObserved and member~=group.owner and not group.partyObserved[member] then control.ring:SetVertexColor(1,0.72,0.25)
                else control.ring:SetVertexColor(0.3,1,0.55) end
                control.label:SetText(member and ('|cffffd36b'..member..'|r') or roleLabel(slot.role))
                control.vacancy:SetShown(not member)
                control.label:SetTextColor(member and 1 or 0.85,member and 1 or 0.88,member and 1 or 0.93)
                control.tooltipText=(member or T('Вільне місце'))..'\n'..roleLabel(displayedRole)..' · '..state
                local specText = member and memberSpecText(member)
                if specText then control.tooltipText=control.tooltipText..T('\nСпеціалізація: ')..specText end
                if not member then control.tooltipText=control.tooltipText..(Finder:CanPerformRole(Finder.identity,displayedRole) and T('\nЛівий клік — подати заявку на цю роль.') or T('\nЦя роль недоступна вашому класу.')) end
            end
        end
    end
end

local function alertCompositionText(group)
    local extra=#group.members>5 and (T(' · ще учасників: ')..(#group.members-5)) or ''
    return T('|cffffd36bУ складі: ')..#group.members..T(' із ')..group.maxSize..T('|r  ·  |cff69dc8cВільних місць: ')..math.max(0,group.maxSize-#group.members)..'|r'..extra
end
refreshAlertRoster=function()
    if not groupAlert or not groupAlert:IsShown() or groupAlert.kind~='group' or not groupAlert.groupKey then return end
    local group=Finder.groups[groupAlert.groupKey]
    if not group or group.closed or group.hidden then groupAlert:Hide(); return end
    if group.revision and groupAlert.rosterGroup==group and groupAlert.rosterRevision==group.revision then return end
    paintAlertRoster(group)
    groupAlert.alertSubtitle:SetText(alertCompositionText(group))
    groupAlert.rosterGroup,groupAlert.rosterRevision=group,group.revision
end

local deferredRequests = {}
local deferredRequestSequence = 0

local function groupAlertsEnabled()
    if type(Finder.GroupAlertsEnabled) == 'function' then return Finder:GroupAlertsEnabled() end
    local settings = OldKraken.DB and OldKraken.DB.settings
    return type(settings) ~= 'table' or settings.groupFinderNotifications ~= false
end
local function eventAlertsEnabled()
    if OldKraken.GuildEvents and type(OldKraken.GuildEvents.AlertsEnabled) == 'function' then
        return OldKraken.GuildEvents:AlertsEnabled()
    end
    local settings = OldKraken.DB and OldKraken.DB.settings
    return type(settings) ~= 'table' or settings.guildEventNotifications ~= false
end
local function workshopAlertsEnabled()
    local settings = OldKraken.DB and OldKraken.DB.settings
    return type(settings) ~= 'table' or settings.workshopOrderAlerts ~= false
end
function Finder:SyncAlertVisibility(category)
    local groupEnabled, eventEnabled, workshopEnabled = groupAlertsEnabled(), eventAlertsEnabled(), workshopAlertsEnabled()
    if (not category or category == 'group') and not groupEnabled then deferredRequests = {} end
    if not groupAlert then return end
    local kind = groupAlert.kind
    if ((not category or category == 'group') and (kind == 'group' or kind == 'request' or kind == 'decision') and not groupEnabled)
        or ((not category or category == 'event') and (kind == 'event' or kind == 'event_signup') and not eventEnabled)
        or ((not category or category == 'workshop') and kind == 'workshop' and not workshopEnabled) then groupAlert:Hide() end
end
function Finder:ResetAlertPositions()
    local settings = OldKraken.DB and OldKraken.DB.settings
    if type(settings) == 'table' then settings.alertPositions = {} end
    if groupAlert then
        groupAlert:ClearAllPoints()
        groupAlert:SetPoint('TOP', UIParent, 'TOP', 0, -160)
    end
    return true
end

local function smartNotificationsEnabled()
    local settings = OldKraken.DB and OldKraken.DB.settings
    return type(settings) ~= 'table' or settings.smartNotifications ~= false
end

local function isValidRequestAlertTarget(groupKey)
    if not groupKey then return false end
    local group = Finder.groups[groupKey]
    if not group or group.closed or group.owner ~= Finder.identity then return false end
    local reqs = group.id and Finder.requests[group.id]
    if type(reqs) ~= 'table' then return false end
    for _, role in pairs(reqs) do
        if role ~= nil then return true end
    end
    return false
end

local function isPlayerInCombat()
    if type(InCombatLockdown) ~= 'function' then return false end
    local ok, inCombat = pcall(InCombatLockdown)
    return ok and inCombat == true
end

local function isInGroupPvEInstance()
    if type(IsInInstance) ~= 'function' then return false end
    local ok, inInstance, instanceType = pcall(IsInInstance)
    if not ok or inInstance ~= true then return false end
    return instanceType == 'party' or instanceType == 'raid'
end

local function shouldShowAlertBanner(kind, isPreview)
    if not smartNotificationsEnabled() then return true end
    if isPlayerInCombat() then return false end
    if isPreview then return true end
    if kind ~= 'request' and isInGroupPvEInstance() then return false end
    return true
end

local function logAlert(title, subtitle, kind)
    local isEvent = kind == 'event' or kind == 'event_signup'
    local isWorkshop = kind == 'workshop'
    print('|cff2ec4b6Old Kraken|r: ' .. title .. (subtitle ~= '' and (' · ' .. subtitle) or '') .. (isEvent and '. /okr events' or (isWorkshop and '. /okr orders' or '. /okr group')))
end

local function playAlertSound()
    local now = type(GetTime) == 'function' and GetTime()
    if type(PlaySound) == 'function' and SOUNDKIT and SOUNDKIT.READY_CHECK
        and type(now) == 'number' and now - lastAlertSoundAt >= ALERT_SOUND_INTERVAL then
        lastAlertSoundAt = now
        pcall(PlaySound, SOUNDKIT.READY_CHECK)
    end
end

local function showAlert(title, subtitle, kind, key, dungeonId, rosterGroup, isPreview)
    local isEvent = kind == 'event' or kind == 'event_signup'
    local isWorkshop = kind == 'workshop'
    if not shouldShowAlertBanner(kind, isPreview) then
        if kind ~= 'group' and kind ~= 'request' then
            logAlert(title, subtitle, kind)
        end
        return
    end
    if not groupAlert then
        groupAlert = CreateFrame('Button', nil, UIParent, 'UIPanelButtonTemplate')
        groupAlert.roleSlots = {}
        OldKraken.UIStyle.Button(groupAlert)
        groupAlert:SetSize(560, 100)
        groupAlert.alertChrome=groupAlert:CreateTexture(nil,'BACKGROUND',nil,1)
        groupAlert.alertChrome:SetAllPoints(groupAlert)
        groupAlert.alertChrome:SetColorTexture(0.045,0.045,0.05,1)
        for _,side in ipairs({'TOP','BOTTOM','LEFT','RIGHT'}) do
            local edge=groupAlert:CreateTexture(nil,'OVERLAY')
            if side=='TOP' or side=='BOTTOM' then
                edge:SetPoint(side..'LEFT',groupAlert,side..'LEFT',0,0); edge:SetPoint(side..'RIGHT',groupAlert,side..'RIGHT',0,0); edge:SetHeight(2)
            else
                edge:SetPoint('TOP'..side,groupAlert,'TOP'..side,0,0); edge:SetPoint('BOTTOM'..side,groupAlert,'BOTTOM'..side,0,0); edge:SetWidth(2)
            end
            edge:SetColorTexture(0.42,0.43,0.46,1)
        end
        groupAlert.alertAccent = groupAlert:CreateTexture(nil, 'ARTWORK')
        groupAlert.alertAccent:SetPoint('TOPLEFT', groupAlert, 'TOPLEFT', 2, -2)
        groupAlert.alertAccent:SetPoint('TOPRIGHT', groupAlert, 'TOPRIGHT', -2, -2)
        groupAlert.alertAccent:SetHeight(2)
        groupAlert.alertAccent:SetColorTexture(0.85, 0.5, 0.18, 0.9)
        groupAlert.alertArt = groupAlert:CreateTexture(nil, 'ARTWORK')
        groupAlert.alertArt:SetSize(60, 60)
        groupAlert.alertArt:SetPoint('LEFT', groupAlert, 'LEFT', 8, 0)
        groupAlert.alertCaption = groupAlert:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
        if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(groupAlert.alertCaption, 11, true) end
        groupAlert.alertCaption:SetTextColor(1, 0.78, 0.35)
        groupAlert.alertCaption:SetHeight(14)
        groupAlert.alertTitle = groupAlert:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
        if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(groupAlert.alertTitle, 16, true) end
        groupAlert.alertTitle:SetTextColor(0.94, 0.95, 0.96)
        groupAlert.alertTitle:SetHeight(22)
        groupAlert.alertTitle:SetWordWrap(false)
        groupAlert.alertSubtitle = groupAlert:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
        if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(groupAlert.alertSubtitle, 13, false) end
        groupAlert.alertSubtitle:SetTextColor(0.9, 0.93, 0.97)
        groupAlert.alertSubtitle:SetShadowColor(0,0,0,1)
        groupAlert.alertSubtitle:SetShadowOffset(1,-1)
        groupAlert.alertHint = groupAlert:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
        if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(groupAlert.alertHint, 12, false) end
        groupAlert.alertHint:SetTextColor(0.75,0.83,0.93)
        groupAlert.alertHint:SetJustifyH('LEFT')
        groupAlert.alertHint:SetWordWrap(false)
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
            if alertKind == 'request' then
                local validTarget = isValidRequestAlertTarget(target)
                tab, selected, offset, requestOffset = 'mine', validTarget and target or nil, 0, 0
                if requestsWindow then requestsWindow:Hide() end
                Finder:Show()
                if validTarget then showRequests() end
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
    groupAlert:SetSize(graphical and 620 or 560,graphical and 204 or 112)
    groupAlert.alertAccent:SetShown(not graphical)
    groupAlert.alertArt:SetSize(graphical and 90 or 60,graphical and 118 or 60)
    groupAlert.alertChrome:SetShown(graphical)
    local highlight=groupAlert:GetHighlightTexture(); if highlight then highlight:SetAlpha(graphical and 0 or 1) end
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
    local textLeft = graphical and 116 or (hasGroupArt and 82 or 18)
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
    groupAlert.alertFooter:SetHeight(graphical and 32 or 58)
    groupAlert.alertHint:ClearAllPoints()
    groupAlert.alertHint:SetPoint('BOTTOMLEFT',groupAlert,'BOTTOMLEFT',textLeft,12)
    groupAlert.alertHint:SetPoint('RIGHT',groupAlert,'RIGHT',-12,0)
    groupAlert.alertHint:SetHeight(16)
    groupAlert.alertHint:SetText('|cff8ccfff'..(alertActions[kind] or T('Клік — відкрити'))..T('|r  |cffb0baca· перетягніть, щоб перемістити|r'))
    groupAlert.alertSubtitle:SetPoint('BOTTOMRIGHT',groupAlert,'BOTTOMRIGHT',-12,12)
    if graphical then
        paintAlertRoster(rosterGroup)
        groupAlert.alertSubtitle:ClearAllPoints()
        groupAlert.alertSubtitle:SetPoint('TOPLEFT',groupAlert,'TOPLEFT',116,-169)
        groupAlert.alertSubtitle:SetPoint('BOTTOMRIGHT',groupAlert,'BOTTOMRIGHT',-12,12)
        groupAlert.alertSubtitle:SetText(alertCompositionText(rosterGroup))
        groupAlert.rosterGroup,groupAlert.rosterRevision=rosterGroup,rosterGroup.revision
        groupAlert.alertHint:SetText(''); groupAlert.alertHint:Hide()
    else
    groupAlert.alertHint:Show()
    groupAlert.alertSubtitle:SetText(subtitle)
    end
    groupAlert.remaining = ALERT_DURATION
    groupAlert:SetAlpha(1)
    groupAlert:Show()
    playAlertSound()
end

function Finder:PreviewAlert(kind)
    if kind == 'group' then
        showAlert(T('Гравець збирає: Назва групи'), T('Склад 2/5 · Вільно місць: 3'), 'group',nil,'rfc',{category='dungeon',maxSize=5,owner=T('Танк'),role='tank',members={T('Танк'),T('Лікар')},memberRoles={[T('Лікар')]='healer'}}, true)
    elseif kind == 'request' then
        showAlert(T('Нова заявка від гравця'), T('Танк · Назва групи'), 'request', nil, nil, nil, true)
    elseif kind == 'event' then
        showAlert(T('Назва події'), T('Організатор · сьогодні о 20:00'), 'event', nil, nil, nil, true)
    elseif kind == 'workshop' then
        showAlert(T('Замовлення'), T('Приклад сповіщення Майстерні'), 'workshop', nil, nil, nil, true)
    end
end

OldKraken:On('WORKSHOP_ORDER_NOTICE', function(title,subtitle,k)
    if not workshopAlertsEnabled() then return end
    showAlert(title,subtitle,'workshop',k)
end)

OldKraken:On('GUILD_EVENTS_NEW', function(key, event)
    if not eventAlertsEnabled() then return end
    local subtitle = event.owner .. ' · ' .. date('%d.%m.%Y %H:%M', event.when)
    showAlert(T('Нова подія: ') .. displayEventTitle(event), subtitle, 'event', key)
end)
OldKraken:On('GUILD_EVENTS_NEW_SIGNUP', function(key, event, name, role)
    if not eventAlertsEnabled() then return end
    refreshPeople()
    local signupRole=role=='flex' and T('Учасник') or roleLabel(role)
    showAlert(T('Новий запис: ') .. playerLabel(name), signupRole .. ' · ' .. displayEventTitle(event), 'event_signup', key)
end)
OldKraken:On('GUILD_EVENTS_CANCELLED', function(key, event)
    if not eventAlertsEnabled() then return end
    showAlert(T('Подію скасовано'), displayEventTitle(event) .. T(' · Автор: ') .. event.owner, 'event_signup', key)
end)
OldKraken:On('GUILD_EVENTS_ALERT_SETTING', function()
    Finder:SyncAlertVisibility('event')
end)
OldKraken:On('WORKSHOP_ALERT_SETTING', function() Finder:SyncAlertVisibility('workshop') end)

OldKraken:On('GROUP_FINDER_NEW', function(group)
    if not groupAlertsEnabled() then return end
    if group.minLevel and group.maxLevel then
        local level = type(UnitLevel) == 'function' and tonumber(UnitLevel('player'))
        if not level or level < group.minLevel or level > group.maxLevel then return end
    end
    refreshPeople()
    local free = math.max(0, group.maxSize - #group.members)
    local actual = group.partyObserved and 1 or (#group.members <= 1 and #group.members or nil)
    for i, name in ipairs(group.members) do
        if actual and i > 1 and group.partyObserved[name] then actual = actual + 1 end
    end
    local presence = actual and (T('у групі ') .. actual .. T(', резерв ') .. (#group.members - actual)) or T('стан групи невідомий')
    local summary = T('Склад ') .. #group.members .. '/' .. group.maxSize .. ' · ' .. presence
    local needed = T('Вільно місць: ') .. free .. T(' · склад гнучкий')
    if group.category == 'dungeon' and group.maxSize == 5 then
        local missing = {tank=0, healer=0, dps=0}
        for _, slot in ipairs(Finder:DungeonSlots(group)) do if not slot.member then missing[slot.role] = missing[slot.role] + 1 end end
        needed = T('Вільні ролі: ') .. roleLabel('tank') .. ' ' .. missing.tank .. ', ' .. roleLabel('healer') .. ' ' .. missing.healer .. ', ' .. roleLabel('dps') .. ' ' .. missing.dps
    end
    local groupKey = group.owner .. '\001' .. group.id
    showAlert(playerLabel(group.owner) .. T(' збирає: ') .. displayGroupTitle(group), summary .. ' · ' .. needed, 'group', groupKey, group.dungeon, group)
end)

local function flushDeferredRequests()
    local pending = deferredRequests
    deferredRequests = {}
    if not groupAlertsEnabled() then return end
    if not smartNotificationsEnabled() or isPlayerInCombat() then return end
    local uniqueApplicants = {}
    local count = 0
    local bestGroupKey = nil
    local bestSeq = -1
    for groupKey, applicants in pairs(pending) do
        local group = Finder.groups[groupKey]
        local reqs = group and group.id and Finder.requests[group.id]
        if group and not group.closed and group.owner == Finder.identity and type(reqs) == 'table' then
            local groupBestSeq = -1
            for applicantName, seq in pairs(applicants) do
                if reqs[applicantName] ~= nil then
                    if not uniqueApplicants[applicantName] then
                        uniqueApplicants[applicantName] = true
                        count = count + 1
                    end
                    if type(seq) == 'number' and seq > groupBestSeq then
                        groupBestSeq = seq
                    end
                end
            end
            if groupBestSeq > bestSeq then
                bestSeq = groupBestSeq
                bestGroupKey = groupKey
            end
        end
    end
    if count > 0 and bestGroupKey then
        showAlert(T('Нові заявки: ') .. count, T('Очікують підтвердження'), 'request', bestGroupKey)
    end
end

local alertCombatEvents = CreateFrame('Frame')
alertCombatEvents:RegisterEvent('PLAYER_REGEN_ENABLED')
alertCombatEvents:SetScript('OnEvent', function(_, event)
    if event == 'PLAYER_REGEN_ENABLED' then flushDeferredRequests() end
end)

OldKraken:On('GROUP_FINDER_NEW_REQUEST', function(group, name, role)
    refreshPeople()
    local groupKey = group.owner .. '\001' .. group.id
    if groupAlertsEnabled() and smartNotificationsEnabled() and isPlayerInCombat() and group.owner == Finder.identity and type(name) == 'string' and name ~= '' then
        deferredRequests[groupKey] = deferredRequests[groupKey] or {}
        deferredRequestSequence = deferredRequestSequence + 1
        deferredRequests[groupKey][name] = deferredRequestSequence
    end
    if groupAlertsEnabled() then
        showAlert(T('Нова заявка від ') .. playerLabel(name), roleLabel(role) .. '  |cff9ba9bc·|r  |cffffd36b' .. displayGroupTitle(group) .. '|r',
            'request', groupKey)
    end
    refreshRequests()
end)

OldKraken:On('GROUP_FINDER_APPLICATION_STATUS', function(group, status)
    if not group or status ~= 'reject' then return end
    if not groupAlertsEnabled() then return end
    refreshPeople()
    showAlert(T('Заявку відхилив ') .. playerLabel(group.owner), displayGroupTitle(group), 'decision', group.owner .. '\001' .. group.id)
end)

if OldKraken.LocalizeTable then
    OldKraken.LocalizeTable(categoryLabels)
    OldKraken.LocalizeTable(roleLabels)
    OldKraken.LocalizeTable(pendingLabels)
    OldKraken.LocalizeTable(applicationBadges, 'text')
    OldKraken.LocalizeTable(alertCaptions)
    OldKraken.LocalizeTable(alertActions)
    OldKraken.LocalizeTable(StaticPopupDialogs.OLDKRAKEN_REMOVE_MEMBER)
    OldKraken.LocalizeTable(dungeonLabels)
    OldKraken:On('INITIALIZED', function()
        for _, value in ipairs(roles) do coloredRoleLabels[value] = roleLabel(value) end
    end)
end
