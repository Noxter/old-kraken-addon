-- Group Finder window and user actions.
local Finder = OldKraken.GroupFinder
local window, selected
local tab = 'all'
local offset, editing = 0, nil
local category, role = 'dungeon', ''
local filterCategory, filterRole, filterFree = 'all', '', false
local categories = {'dungeon', 'quest', 'world', 'raid', 'pvp', 'other'}
local categoryLabels = {dungeon='Підземелля', quest='Квести', world='Відкритий світ', raid='Рейд', pvp='PvP', other='Інше'}
local roles = {'', 'tank', 'healer', 'dps', 'flex'}
local roleLabels = {['']='Без ролі', tank='Танк', healer='Лікар', dps='DPS', flex='Гнучка'}
local pendingLabels = {pending='Очікує', accept='Прийнято', reject='Відхилено', closed='Закрито', retry='Подайте заявку знову'}

local function cycle(values, value)
    for i, item in ipairs(values) do if item == value then return values[i % #values + 1] end end
    return values[1]
end

local function button(parent, label, x, y, width, callback)
    local b = CreateFrame('Button', nil, parent, 'UIPanelButtonTemplate')
    b:SetSize(width, 23); b:SetPoint('TOPLEFT', parent, 'TOPLEFT', x, y); b:SetText(label)
    b:SetScript('OnClick', callback)
    return b
end

local function input(parent, label, x, y, width, initial)
    local text = parent:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    text:SetPoint('TOPLEFT', parent, 'TOPLEFT', x, y); text:SetText(label)
    local box = CreateFrame('EditBox', nil, parent, 'InputBoxTemplate')
    box:SetSize(width, 22); box:SetPoint('TOPLEFT', parent, 'TOPLEFT', x + 4, y - 18)
    box:SetAutoFocus(false); box:SetText(initial or '')
    box.label = text
    box:SetScript('OnEscapePressed', function(self) self:ClearFocus() end)
    return box
end

local function refresh()
    if not window or not window:IsShown() then return end
    local lines = {}
    for key, group in pairs(Finder.groups or {}) do
        local level = tonumber(window.levelFilter:GetText())
        local matches = (filterCategory == 'all' or group.category == filterCategory)
            and (filterRole == '' or group.role == filterRole)
            and (not filterFree or #group.members < group.maxSize)
            and (not level or (level >= group.minLevel and level <= group.maxLevel))
        if (tab == 'all' and not group.closed and matches) or (tab == 'mine' and group.owner == Finder.identity)
            or (tab == 'applications' and Finder.pending[key]) then
            lines[#lines + 1] = {key=key, group=group}
        end
    end
    table.sort(lines, function(a,b) return a.group.title < b.group.title end)
    window.visible = lines
    for i, b in ipairs(window.rows) do
        local entry = lines[i + offset]
        if entry then
            local g = entry.group
            local status = Finder.pending[entry.key]
            b:SetText(string.format('%s | %s | %s | %d/%d%s', g.title, categoryLabels[g.category], g.owner, #g.members, g.maxSize,
                status and (' | ' .. (pendingLabels[status] or status)) or ''))
            b:Show()
        else b:Hide() end
    end
    local g = selected and Finder.groups[selected]
    if g then
        local applicants = {}
        for name, applicantRole in pairs(Finder.requests[g.id] or {}) do
            applicants[#applicants + 1] = name .. ' (' .. (roleLabels[applicantRole] or applicantRole) .. ')'
        end
        local applicationStatus = Finder.pending[selected]
        window.details:SetText(string.format('%s — %s\nАвтор: %s | Рівень: %d–%d | Роль: %s\n%s\nСклад: %s\nСтатус: %s%s',
            g.title, categoryLabels[g.category], g.owner, g.minLevel, g.maxLevel, roleLabels[g.role],
            g.description .. '\nЗаявки: ' .. table.concat(applicants, ', '), table.concat(g.members, ', '), g.closed and 'Закрито' or 'Відкрито',
            applicationStatus and (' | Заявка: ' .. (pendingLabels[applicationStatus] or applicationStatus)) or ''))
    else window.details:SetText('Виберіть оголошення у списку.') end
    for _, box in ipairs(window.createFields) do
        if tab == 'create' then box:Show(); box.label:Show() else box:Hide(); box.label:Hide() end
    end
    if tab == 'create' then window.createButton:Show(); window.categoryButton:Show() else window.createButton:Hide(); window.categoryButton:Hide() end
end

local function createWindow()
    local f = CreateFrame('Frame', 'OldKrakenGroupFinderFrame', UIParent, 'BasicFrameTemplateWithInset')
    f:SetSize(900, 590); f:SetPoint('CENTER'); f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag('LeftButton'); f:SetScript('OnDragStart', f.StartMoving); f:SetScript('OnDragStop', f.StopMovingOrSizing)
    f:SetClampedToScreen(true); f:Hide()
    if f.TitleText then f.TitleText:SetText('Old Kraken — Пошук груп') end
    for i, item in ipairs({{'Усі групи','all'}, {'Створити','create'}, {'Мої заявки','applications'}, {'Мої оголошення','mine'}}) do
        button(f, item[1], 18 + (i-1)*160, -32, 150, function() tab=item[2]; selected=nil; editing=nil; offset=0; refresh() end)
    end
    f.rows = {}
    for i=1,10 do
        local index = i
        f.rows[i] = button(f, '', 18, -65-(i-1)*25, 520, function()
            local entry = f.visible and f.visible[index + offset]
            if entry then selected=entry.key; refresh() end
        end)
    end
    button(f, '‹', 18, -318, 50, function() offset=math.max(0, offset-10); refresh() end)
    button(f, '›', 75, -318, 50, function() if f.visible and offset+10 < #f.visible then offset=offset+10 end; refresh() end)
    f.details = f:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    f.details:SetPoint('TOPLEFT', f, 'TOPLEFT', 550, -70); f.details:SetWidth(320); f.details:SetJustifyH('LEFT')
    f.levelFilter = input(f, 'Фільтр рівня', 20, -465, 80, '')
    f.levelFilter:SetScript('OnTextChanged', refresh)
    button(f, 'Категорія: усі', 120, -485, 155, function(self)
        if filterCategory == 'all' then filterCategory=categories[1]
        else
            local nextCategory=cycle(categories, filterCategory)
            filterCategory=nextCategory==categories[1] and 'all' or nextCategory
        end
        self:SetText(filterCategory=='all' and 'Категорія: усі' or categoryLabels[filterCategory]); refresh()
    end)
    button(f, 'Роль: усі', 285, -485, 125, function(self)
        filterRole=cycle(roles, filterRole)
        self:SetText(filterRole=='' and 'Роль: усі' or roleLabels[filterRole]); refresh()
    end)
    button(f, 'Вільні: усі', 420, -485, 115, function(self)
        filterFree=not filterFree; self:SetText(filterFree and 'Є місця' or 'Вільні: усі'); refresh()
    end)
    f.titleBox = input(f, 'Назва', 20, -330, 240, '')
    f.descriptionBox = input(f, 'Опис', 275, -330, 250, '')
    f.maxBox = input(f, 'Місць', 20, -385, 65, '5')
    f.minBox = input(f, 'Мін. рівень', 105, -385, 80, '1')
    f.maxLevelBox = input(f, 'Макс. рівень', 205, -385, 80, '60')
    f.createFields = {f.titleBox, f.descriptionBox, f.maxBox, f.minBox, f.maxLevelBox}
    f.categoryButton = button(f, categoryLabels[category], 305, -408, 140, function(self)
        category = cycle(categories, category); self:SetText(categoryLabels[category])
    end)
    button(f, 'Роль: без ролі', 550, -330, 150, function(self)
        role=cycle(roles, role); self:SetText('Роль: '..roleLabels[role])
    end)
    f.createButton = button(f, 'Створити', 460, -408, 120, function()
        local ok
        if editing then
            ok = Finder:Edit(editing, f.titleBox:GetText(), f.descriptionBox:GetText(), f.maxBox:GetText(), f.minBox:GetText(), f.maxLevelBox:GetText(), role, category)
        else
            ok = Finder:Create(f.titleBox:GetText(), category, f.descriptionBox:GetText(), f.maxBox:GetText(), f.minBox:GetText(), f.maxLevelBox:GetText(), role)
        end
        if ok then Finder:Changed(); editing=nil; tab='mine'; refresh() else print('Old Kraken: перевірте поля та стан зв’язку.') end
    end)
    button(f, 'Подати заявку', 550, -385, 140, function()
        local g=selected and Finder.groups[selected]
        if g and Finder:Apply(g.owner, g.id, role) then Finder:Changed(); refresh() end
    end)
    button(f, 'Відкликати', 700, -385, 140, function()
        local g=selected and Finder.groups[selected]
        if g and Finder:Withdraw(g.owner, g.id) then Finder:Changed(); refresh() end
    end)
    button(f, 'Закрити набір', 550, -415, 140, function()
        local g=selected and Finder.groups[selected]
        if g and g.owner==Finder.identity and Finder:Cancel(g.id) then Finder:Changed(); refresh() end
    end)
    button(f, 'Редагувати', 700, -415, 140, function()
        local g=selected and Finder.groups[selected]
        if not g or g.owner~=Finder.identity or g.closed then return end
        editing=g.id; tab='create'; role=g.role; category=g.category
        f.titleBox:SetText(g.title); f.descriptionBox:SetText(g.description)
        f.maxBox:SetText(tostring(g.maxSize)); f.minBox:SetText(tostring(g.minLevel)); f.maxLevelBox:SetText(tostring(g.maxLevel))
        f.categoryButton:SetText(categoryLabels[category]); refresh()
    end)
    f.applicantBox = input(f, 'Ім’я заявника / учасника', 550, -445, 200, '')
    button(f, 'Прийняти', 550, -500, 95, function()
        local g=selected and Finder.groups[selected]
        if g and g.owner==Finder.identity and Finder:Decide(g.id, f.applicantBox:GetText(), true) then Finder:Changed(); refresh() end
    end)
    button(f, 'Відхилити', 650, -500, 95, function()
        local g=selected and Finder.groups[selected]
        if g and g.owner==Finder.identity and Finder:Decide(g.id, f.applicantBox:GetText(), false) then Finder:Changed(); refresh() end
    end)
    button(f, 'Видалити', 750, -500, 95, function()
        local g=selected and Finder.groups[selected]
        if g and g.owner==Finder.identity and Finder:RemoveMember(g.id, f.applicantBox:GetText()) then Finder:Changed(); refresh() end
    end)
    return f
end

function Finder:Show()
    if not self.active then print('Old Kraken: пошук груп не ініціалізовано.') return end
    if not window then window=createWindow() end
    window:Show(); refresh()
end
OldKraken:On('GROUP_FINDER_CHANGED', refresh)
