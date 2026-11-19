local T = OldKraken.Translate or function(text) return text end
local Hub = {pages = {}, pageOrder = {}, buttons = {}, currentPage = nil}
OldKraken.UIHub = Hub
local colors = OldKraken.UIStyle.Colors

-- Window geometry (design grid): 1140x680, 30 px header, 190 px sidebar.
-- Content area: 948x648, 24 px horizontal padding, 20 px top padding, 16 px block spacing.
local WINDOW_WIDTH, WINDOW_HEIGHT, HEADER_HEIGHT, SIDEBAR_WIDTH = 1140, 680, 30, 190
local PAD_X, PAD_TOP, SPACING = 24, 20, 16
local TITLE_HEIGHT = 31
local CONTENT_WIDTH = WINDOW_WIDTH - 2 - SIDEBAR_WIDTH
local CONTENT_HEIGHT = WINDOW_HEIGHT - HEADER_HEIGHT - 2
local PAGE_WIDTH = CONTENT_WIDTH - PAD_X * 2
local PAGE_HEIGHT = CONTENT_HEIGHT - PAD_TOP * 2
local NAV_TOP, NAV_STEP = 115, 45
Hub.geometry = {
    pageWidth = PAGE_WIDTH, pageHeight = PAGE_HEIGHT, pageTop = PAD_TOP,
    titleRowTop = PAD_TOP, titleHeight = TITLE_HEIGHT, spacing = SPACING,
}

local NAV_ACTIVE_BG = {0.102, 0.141, 0.302, 1}
local NAV_ACTIVE_EDGE = {0.478, 0.541, 0.980, 1}
local NAV_INACTIVE_BG = {0.08, 0.095, 0.125, 1}
local NAV_INACTIVE_EDGE = {0.20, 0.23, 0.29, 0.85}

local function updateButtons()
    local activeLabel = colors.white or {1, 1, 1}
    local inactiveLabel = colors.mutedText or {0.63, 0.67, 0.73}
    for key, button in pairs(Hub.buttons) do
        local selected = key == Hub.currentPage
        button.activeBar:Hide()
        local fillColor = selected and (colors.sel or NAV_ACTIVE_BG) or (colors.button or NAV_INACTIVE_BG)
        local edgeColor = selected and (colors.selEdge or NAV_ACTIVE_EDGE) or (colors.buttonEdge or NAV_INACTIVE_EDGE)
        if button.activeFillParts then
            for _, t in ipairs(button.activeFillParts) do
                t:SetVertexColor(fillColor[1], fillColor[2], fillColor[3], fillColor[4] or 1)
                t.color = fillColor
                t:SetShown(selected)
            end
            for _, t in ipairs(button.activeRingParts) do
                t:SetVertexColor(edgeColor[1], edgeColor[2], edgeColor[3], edgeColor[4] or 1)
                t.color = edgeColor
                t:SetShown(selected)
            end
        elseif button.activeFill then
            button.activeFill:SetColorTexture(fillColor[1], fillColor[2], fillColor[3], fillColor[4] or 1)
            button.activeFill:SetShown(selected)
            for _, edge in ipairs(button.activeEdges or {}) do
                edge:SetColorTexture(edgeColor[1], edgeColor[2], edgeColor[3], edgeColor[4] or 1)
                edge:SetShown(selected)
            end
        end
        local labelColor = selected and activeLabel or inactiveLabel
        local shortcutColor = selected and colors.brandGold or inactiveLabel
        button.label:SetTextColor(labelColor[1], labelColor[2], labelColor[3])
        button.shortcut:SetTextColor(shortcutColor[1], shortcutColor[2], shortcutColor[3])
    end
end

local function createPageButton(page)
    local button = CreateFrame('Button', nil, Hub.frame, 'UIPanelButtonTemplate')
    OldKraken.UIStyle.Button(button, nil, {rounded = true})
    button:SetSize(164, 39)
    button:SetPoint('TOPLEFT', Hub.frame, 'TOPLEFT', 14, -NAV_TOP - (page.index - 1) * NAV_STEP)
    button:SetScript('OnClick', function() Hub:ShowPage(page.key) end)

    local base = 'Interface\\AddOns\\' .. (OldKraken and OldKraken.name or 'OldKraken') .. '\\Media\\'
    local function slice(file, layer, sublayer)
        local parts = {}
        for i, range in ipairs({{0, 0.25}, {0.25, 0.75}, {0.75, 1}}) do
            local t = button:CreateTexture(nil, layer, nil, sublayer)
            t:SetTexture(base .. file)
            t:SetTexCoord(range[1], range[2], 0, 1)
            t:SetPoint('TOP', button, 'TOP', 0, 0)
            t:SetPoint('BOTTOM', button, 'BOTTOM', 0, 0)
            if i == 1 then t:SetPoint('LEFT', button, 'LEFT', 0, 0); t:SetWidth(6)
            elseif i == 3 then t:SetPoint('RIGHT', button, 'RIGHT', 0, 0); t:SetWidth(6)
            else t:SetPoint('LEFT', parts[1], 'RIGHT', 0, 0); t:SetPoint('RIGHT', button, 'RIGHT', -6, 0) end
            t:Hide()
            parts[i] = t
        end
        return parts
    end

    button.activeFillParts = slice('PillFill.tga', 'BACKGROUND', 1)
    button.activeRingParts = slice('PillRing.tga', 'BORDER', 1)
    button.activeFill = button.activeFillParts[2]
    button.activeEdges = button.activeRingParts
    button.activeBorder = button.activeEdges[1]

    button.activeBar = button:CreateTexture(nil, 'ARTWORK')
    button.activeBar:SetPoint('TOPLEFT', button, 'TOPLEFT', 1, -6)
    button.activeBar:SetSize(3, 27)
    button.activeBar:SetColorTexture(unpack(colors.brandGold))
    button.activeBar:Hide()

    button.shortcut = button:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(button.shortcut, 13) end
    button.shortcut:SetPoint('LEFT', button, 'LEFT', 12, 0)
    button.shortcut:SetWidth(24)
    button.shortcut:SetText(page.shortcut)

    button.label = button:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(button.label, 14) end
    button.label:SetPoint('LEFT', button, 'LEFT', 38, 0)
    button.label:SetJustifyH('LEFT')
    button.label:SetText(T(page.title))

    Hub.buttons[page.key] = button
    updateButtons()
end

function Hub:RegisterPage(key, title, shortcut, create)
    assert(type(key) == 'string' and key ~= '', 'UI page key must be a non-empty string')
    assert(type(title) == 'string' and title ~= '', 'UI page title must be a non-empty string')
    assert(type(create) == 'function', 'UI page factory must be a function')
    assert(not self.pages[key], 'UI page already registered: ' .. key)

    local page = {key = key, title = title, shortcut = shortcut or '', create = create, index = #self.pageOrder + 1}
    self.pages[key] = page
    self.pageOrder[#self.pageOrder + 1] = page
    if self.frame then createPageButton(page) end
end

local SCALE_PRESETS = {0.85, 1.0, 1.15, 1.25, 1.4}

local function savedScale()
    local s = OldKraken.DB and OldKraken.DB.settings
    local val = type(s) == 'table' and tonumber(s.uiScale)
    if val and val >= 0.75 and val <= 1.5 then return val end
    return 1.0
end

local function applyScale(value)
    local scale = tonumber(value)
    if not scale or scale < 0.75 or scale > 1.5 then scale = 1.0 end
    if OldKraken.DB and type(OldKraken.DB.settings) == 'table' then
        OldKraken.DB.settings.uiScale = scale
    end
    if Hub.frame and type(Hub.frame.SetScale) == 'function' then
        Hub.frame:SetScale(scale)
    end
    if Hub.scaleButton then
        Hub.scaleButton:SetText(math.floor(scale * 100 + 0.5) .. '%')
    end
end

function Hub:HandleScaleWheel(delta)
    if type(IsControlKeyDown) ~= 'function' or not IsControlKeyDown() then return false end
    if not delta or delta == 0 then return false end
    local current = savedScale()
    local closest, bestDist = 1, math.abs(current - SCALE_PRESETS[1])
    for i = 2, #SCALE_PRESETS do
        local dist = math.abs(current - SCALE_PRESETS[i])
        if dist < bestDist then closest, bestDist = i, dist end
    end
    local target = delta > 0 and math.min(#SCALE_PRESETS, closest + 1) or math.max(1, closest - 1)
    applyScale(SCALE_PRESETS[target])
    return true
end

local function createWindow()
    local frame = CreateFrame('Frame', 'OldKrakenHubFrame', UIParent, 'BasicFrameTemplateWithInset')
    frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    frame:SetPoint('CENTER')
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag('LeftButton')
    frame:SetScript('OnDragStart', frame.StartMoving)
    frame:SetScript('OnDragStop', frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    OldKraken.UIStyle.Window(frame)
    local scaleBtn = CreateFrame('Button', nil, frame, 'UIPanelButtonTemplate')
    OldKraken.UIStyle.Button(scaleBtn, nil, {rounded = true})
    scaleBtn:SetSize(48, 22)
    scaleBtn:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -34, -4)
    local scaleLbl = type(scaleBtn.GetFontString) == 'function' and scaleBtn:GetFontString()
    if type(scaleLbl) == 'table' and OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(scaleLbl, 11) end
    scaleBtn:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
    scaleBtn:SetScript('OnClick', function(_, mouseButton)
        if mouseButton == 'RightButton' then
            applyScale(1.0)
            return
        end
        local current = savedScale()
        local nextScale = SCALE_PRESETS[1]
        for i, preset in ipairs(SCALE_PRESETS) do
            if math.abs(current - preset) < 0.03 then
                nextScale = SCALE_PRESETS[(i % #SCALE_PRESETS) + 1]
                break
            elseif preset > current then
                nextScale = preset
                break
            end
        end
        applyScale(nextScale)
    end)
    scaleBtn:SetScript('OnEnter', function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, 'ANCHOR_BOTTOM')
            GameTooltip:SetText(T('Масштаб вікна: ') .. math.floor(savedScale() * 100 + 0.5) .. '%')
            GameTooltip:AddLine(T('Лівий клік — змінити (85%–140%)'), 1, 1, 1, true)
            GameTooltip:AddLine(T('Правий клік — скинути на 100%'), 0.75, 0.82, 0.9, true)
            GameTooltip:AddLine(T('Ctrl + скрол — змінити масштаб'), 0.75, 0.82, 0.9, true)
            GameTooltip:Show()
        end
    end)
    scaleBtn:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
    Hub.scaleButton = scaleBtn

    frame:EnableMouseWheel(true)
    frame:SetScript('OnMouseWheel', function(_, delta) Hub:HandleScaleWheel(delta) end)
    table.insert(UISpecialFrames, 'OldKrakenHubFrame')
    frame:HookScript('OnHide', function()
        for _, page in ipairs(Hub.pageOrder) do
            if page.frame then page.frame:Hide() end
        end
    end)

    OldKraken.UIStyle.Panel(frame, 1, -(HEADER_HEIGHT + 1), SIDEBAR_WIDTH - 1, WINDOW_HEIGHT - HEADER_HEIGHT - 2)
    Hub.brandMark = CreateFrame('Frame', nil, frame)
    Hub.brandMark:SetSize(40, 40)
    Hub.brandMark:SetPoint('TOPLEFT', frame, 'TOPLEFT', 14, -(HEADER_HEIGHT + 17))
    Hub.brandMark.texture = Hub.brandMark:CreateTexture(nil, 'ARTWORK')
    Hub.brandMark.texture:SetAllPoints(Hub.brandMark)
    Hub.brandMark.texture:SetTexture(OldKraken.UIStyle.EmblemPath())

    local brand = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(brand, 15, true) end
    brand:SetPoint('TOPLEFT', frame, 'TOPLEFT', 64, -(HEADER_HEIGHT + 20))
    brand:SetWidth(112)
    brand:SetJustifyH('LEFT')
    brand:SetWordWrap(false)
    if OldKraken.BindGuildTitle then
        OldKraken.BindGuildTitle(frame, nil, brand)
    else
        brand:SetText('Old Kraken')
    end
    brand:SetTextColor(colors.brandGold[1], colors.brandGold[2], colors.brandGold[3])

    local subtitle = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(subtitle, 11) end
    subtitle:SetPoint('TOPLEFT', brand, 'BOTTOMLEFT', 0, -3)
    subtitle:SetText(T('ГІЛЬДІЙНИЙ ЦЕНТР'))
    subtitle:SetTextColor(colors.mutedText[1], colors.mutedText[2], colors.mutedText[3])

    Hub.content = CreateFrame('Frame', nil, frame)
    Hub.content:SetSize(CONTENT_WIDTH, CONTENT_HEIGHT)
    Hub.content:SetPoint('TOPLEFT', frame, 'TOPLEFT', 1 + SIDEBAR_WIDTH, -(HEADER_HEIGHT + 1))
    Hub.contentTitle = Hub.content:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
    Hub.contentTitle:SetPoint('TOPLEFT', Hub.content, 'TOPLEFT', PAD_X, -(PAD_TOP + 2))
    Hub.contentTitle:SetTextColor(colors.brandGold[1], colors.brandGold[2], colors.brandGold[3])
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(Hub.contentTitle, 22) end
    Hub.contentRule = Hub.content:CreateTexture(nil, 'ARTWORK')
    Hub.contentRule:SetPoint('TOPLEFT', Hub.content, 'TOPLEFT', PAD_X, -(PAD_TOP + TITLE_HEIGHT + 1))
    Hub.contentRule:SetSize(PAGE_WIDTH, 1)
    Hub.contentRule:SetColorTexture(unpack(colors.panelEdge))
    Hub.contentRule:Hide()
    Hub.frame = frame
    applyScale(savedScale())
    for _, page in ipairs(Hub.pageOrder) do createPageButton(page) end
    return frame
end

function Hub:ShowPage(key)
    local page = self.pages[key]
    assert(page, 'Unknown UI page: ' .. tostring(key))

    if not self.frame then createWindow() end
    if not page.frame then
        page.frame = page.create(self.content)
        assert(page.frame, 'UI page factory returned no frame: ' .. key)
        page.frame:ClearAllPoints()
        page.frame:SetPoint('TOPLEFT', self.content, 'TOPLEFT', PAD_X, -PAD_TOP)
    end

    self.currentPage = key
    self.contentTitle:SetText(T(page.title))
    for _, item in ipairs(self.pageOrder) do
        if item.frame then item.frame:SetShown(item == page) end
    end
    updateButtons()
    applyScale(savedScale())
    self.frame:Show()
    page.frame:Show()
    return page.frame
end

function Hub:Toggle(key)
    key = key or self.pageOrder[1] and self.pageOrder[1].key
    assert(key, 'No UI pages are registered')
    if self.frame and self.frame:IsShown() and self.currentPage == key then
        self.frame:Hide()
    else
        self:ShowPage(key)
    end
end

local function createSettings(parent)
    local page = CreateFrame('Frame', nil, parent)
    page:SetSize(PAGE_WIDTH, PAGE_HEIGHT)

    local label = page:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
    label:SetPoint('TOPLEFT', page, 'TOPLEFT', 0, -55)
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(label, 15, true) end
    label:SetText(T('Мова інтерфейсу'))

    local function button(text, x, y, width)
        local control = CreateFrame('Button', nil, page, 'UIPanelButtonTemplate')
        OldKraken.UIStyle.Button(control, nil, {rounded = true})
        control:SetSize(width, 34)
        control:SetPoint('TOPLEFT', page, 'TOPLEFT', x, y)
        control:SetText(text)
        return control
    end

    local ukrainian = button('Українська', 0, -82, 136)
    local english = button('English', 146, -82, 136)
    local apply = button(T('Застосувати й перезавантажити'), 0, -155, 280)
    local hint = page:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    hint:SetPoint('TOPLEFT', page, 'TOPLEFT', 0, -129)
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(hint, 13) end
    hint:SetText(T('Зміна мови перезавантажить інтерфейс WoW.'))

    local alertsLabel = page:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
    alertsLabel:SetPoint('TOPLEFT', page, 'TOPLEFT', 0, -215)
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(alertsLabel, 15, true) end
    alertsLabel:SetText(T('Сповіщення'))

    local smartButton = button(T('Розумні сповіщення: увімк.'), 0, -242, 280)
    local smartHint = page:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    smartHint:SetPoint('TOPLEFT', page, 'TOPLEFT', 0, -284)
    smartHint:SetWidth(520)
    smartHint:SetJustifyH('LEFT')
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(smartHint, 13) end
    smartHint:SetText(T('Автоматично приглушувати фонові банери в данжах і рейдах та відкладати заявки під час бою.'))

    local function refreshSmartButton()
        local settings = OldKraken.DB and OldKraken.DB.settings
        local enabled = type(settings) ~= 'table' or settings.smartNotifications ~= false
        smartButton:SetText(enabled and T('Розумні сповіщення: увімк.') or T('Розумні сповіщення: вимк.'))
    end
    smartButton:SetScript('OnClick', function()
        local settings = OldKraken.DB and OldKraken.DB.settings
        if type(settings) ~= 'table' then return end
        settings.smartNotifications = settings.smartNotifications == false
        refreshSmartButton()
    end)

    local active = OldKraken.GetLanguage()
    local selected = active
    local function selectLanguage(language)
        selected = language
        ukrainian:SetEnabled(language ~= 'ukUA')
        english:SetEnabled(language ~= 'enUS')
        apply:SetEnabled(language ~= active and type(ReloadUI) == 'function')
    end
    ukrainian:SetScript('OnClick', function() selectLanguage('ukUA') end)
    english:SetScript('OnClick', function() selectLanguage('enUS') end)
    apply:SetScript('OnClick', function()
        local settings = OldKraken.DB and OldKraken.DB.settings
        if type(settings) ~= 'table' or selected == active or type(ReloadUI) ~= 'function' then return end
        settings.language = selected
        ReloadUI()
    end)
    page:SetScript('OnShow', function() selectLanguage(active); refreshSmartButton() end)
    selectLanguage(active)
    refreshSmartButton()
    return page
end

if OldKraken.GetLanguage then
    OldKraken:On('INITIALIZED', function()
        Hub:RegisterPage('settings', 'Налаштування', '05', createSettings)
    end)
end
