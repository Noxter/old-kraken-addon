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

local function updateButtons()
    for key, button in pairs(Hub.buttons) do
        local selected = key == Hub.currentPage
        button.activeBar:SetShown(selected)
        local labelColor = selected and colors.brandGold or colors.text
        local shortcutColor = selected and colors.brandGold or colors.mutedText
        button.label:SetTextColor(labelColor[1], labelColor[2], labelColor[3])
        button.shortcut:SetTextColor(shortcutColor[1], shortcutColor[2], shortcutColor[3])
    end
end

local function createPageButton(page)
    local button = CreateFrame('Button', nil, Hub.frame, 'UIPanelButtonTemplate')
    OldKraken.UIStyle.Button(button)
    button:SetSize(164, 39)
    button:SetPoint('TOPLEFT', Hub.frame, 'TOPLEFT', 14, -NAV_TOP - (page.index - 1) * NAV_STEP)
    button:SetScript('OnClick', function() Hub:ShowPage(page.key) end)

    button.activeBar = button:CreateTexture(nil, 'ARTWORK')
    button.activeBar:SetPoint('TOPLEFT', button, 'TOPLEFT', 1, -6)
    button.activeBar:SetSize(3, 27)
    button.activeBar:SetColorTexture(unpack(colors.brandGold))

    button.shortcut = button:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    button.shortcut:SetPoint('LEFT', button, 'LEFT', 12, 0)
    button.shortcut:SetWidth(24)
    button.shortcut:SetText(page.shortcut)

    button.label = button:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
    button.label:SetPoint('LEFT', button, 'LEFT', 38, 0)
    button.label:SetJustifyH('LEFT')
    button.label:SetText(page.title)

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
    if frame.TitleText then frame.TitleText:SetText('Old Kraken') end
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
    brand:SetPoint('TOPLEFT', frame, 'TOPLEFT', 64, -(HEADER_HEIGHT + 20))
    brand:SetText('OLD KRAKEN')
    brand:SetTextColor(colors.brandGold[1], colors.brandGold[2], colors.brandGold[3])

    local subtitle = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    subtitle:SetPoint('TOPLEFT', brand, 'BOTTOMLEFT', 0, -3)
    subtitle:SetText('ГІЛЬДІЙНИЙ ЦЕНТР')
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
    Hub.frame = frame
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
    if self.frame.TitleText then self.frame.TitleText:SetText('Old Kraken') end
    self.contentTitle:SetText(page.title)
    for _, item in ipairs(self.pageOrder) do
        if item.frame then item.frame:SetShown(item == page) end
    end
    updateButtons()
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
