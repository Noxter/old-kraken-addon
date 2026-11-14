local Hub = {pages = {}, pageOrder = {}, buttons = {}, currentPage = nil}
OldKraken.UIHub = Hub
local colors = OldKraken.UIStyle.Colors

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
    button:SetSize(164, 48)
    button:SetPoint('TOPLEFT', Hub.frame, 'TOPLEFT', 20, -112 - (page.index - 1) * 58)
    button:SetScript('OnClick', function() Hub:ShowPage(page.key) end)

    button.activeBar = button:CreateTexture(nil, 'ARTWORK')
    button.activeBar:SetPoint('TOPLEFT', button, 'TOPLEFT', 1, -8)
    button.activeBar:SetSize(3, 32)
    button.activeBar:SetColorTexture(unpack(colors.brandGold))

    button.shortcut = button:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
    button.shortcut:SetPoint('LEFT', button, 'LEFT', 14, 0)
    button.shortcut:SetWidth(28)
    button.shortcut:SetText(page.shortcut)

    button.label = button:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
    button.label:SetPoint('LEFT', button, 'LEFT', 48, 0)
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
    frame:SetSize(1140, 660)
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

    OldKraken.UIStyle.Panel(frame, 12, -42, 180, 600)
    Hub.brandMark = CreateFrame('Frame', nil, frame)
    Hub.brandMark:SetSize(52, 52)
    Hub.brandMark:SetPoint('TOPLEFT', frame, 'TOPLEFT', 16, -48)
    Hub.brandMark.texture = Hub.brandMark:CreateTexture(nil, 'ARTWORK')
    Hub.brandMark.texture:SetAllPoints(Hub.brandMark)
    Hub.brandMark.texture:SetTexture(OldKraken.UIStyle.EmblemPath())

    local brand = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
    brand:SetPoint('TOPLEFT', frame, 'TOPLEFT', 76, -59)
    brand:SetText('OLD KRAKEN')
    brand:SetTextColor(colors.brandGold[1], colors.brandGold[2], colors.brandGold[3])

    local subtitle = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    subtitle:SetPoint('TOPLEFT', brand, 'BOTTOMLEFT', 0, -4)
    subtitle:SetText('ГІЛЬДІЙНИЙ ЦЕНТР')
    subtitle:SetTextColor(colors.mutedText[1], colors.mutedText[2], colors.mutedText[3])

    Hub.content = CreateFrame('Frame', nil, frame)
    Hub.content:SetSize(920, 600)
    Hub.content:SetPoint('TOPLEFT', frame, 'TOPLEFT', 205, -42)
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
        page.frame:SetPoint('CENTER', self.content, 'CENTER')
    end

    self.currentPage = key
    if self.frame.TitleText then self.frame.TitleText:SetText('Old Kraken — ' .. page.title) end
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
