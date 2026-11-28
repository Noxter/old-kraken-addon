OldKraken = OldKraken or {}
local T = OldKraken.Translate or function(text) return text end

local WhatsNew = {}
OldKraken.WhatsNew = WhatsNew

local CARDS = {
    {
        title = 'Нові перемикачі',
        desc = 'У вкладці «Налаштування» всі опції переведено на компактні перемикачі у дві колонки.',
        icon = 'Interface\\Icons\\INV_Misc_Gear_01',
        tab = 'settings',
    },
    {
        title = 'Автозакриття групи',
        desc = 'Ваше оголошення в Пошуку групи автоматично закриється, щойно ви зайдете в підземелля.',
        icon = 'Interface\\Icons\\INV_Shield_06',
    },
    {
        title = 'Швидша Майстерня',
        desc = 'Список майстрів професій і рецептів тепер відкривається помітно швидше, без підвисань.',
        icon = 'Interface\\Icons\\Trade_BlackSmithing',
        tab = 'workshop',
    },
    {
        title = 'Кнопка в ігровому меню',
        desc = 'Додано кнопку Old Kraken у меню Esc над «AddOns» і збільшено герб у вікні гільдії.',
        icon = 'Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend',
        tab = 'settings',
    },
    {
        title = 'Чистіший чат',
        desc = 'Фонова синхронізація рецептів більше не засмічує чат повідомленнями про гравців в офлайні.',
        icon = 'Interface\\Icons\\INV_Letter_15',
    },
    {
        title = 'Події та сповіщення',
        desc = 'Анонси подій і записів у чат із клікабельними лінками та гнучкими сповіщеннями.',
        icon = 'Interface\\Icons\\INV_Misc_PocketWatch_01',
    },
}

local frame = nil
local titleText = nil
local sessionChecked = false

function WhatsNew:GetCards()
    return CARDS
end

function WhatsNew:MarkSeen()
    local db = OldKraken.DB
    local ver = OldKraken.version
    if type(db) ~= 'table' or type(db.settings) ~= 'table' or type(ver) ~= 'string' or ver == '' then
        return false
    end
    db.settings.whatsNewSeenVersion = ver
    return true
end

function WhatsNew:ShouldAutoShow()
    if type(InCombatLockdown) == 'function' and InCombatLockdown() then return false end
    local db = OldKraken.DB
    local ver = OldKraken.version
    if type(db) ~= 'table' or type(db.settings) ~= 'table' or type(ver) ~= 'string' or ver == '' then
        return false
    end
    return db.settings.whatsNewSeenVersion ~= ver
end

local function openTab(tabKey)
    WhatsNew:MarkSeen()
    if frame and type(frame.Hide) == 'function' then frame:Hide() end
    if tabKey and OldKraken.UIHub and type(OldKraken.UIHub.ShowPage) == 'function' then
        OldKraken.UIHub:ShowPage(tabKey)
    end
end

local function ensureFrame()
    if frame then return frame end
    if type(CreateFrame) ~= 'function' or type(UIParent) ~= 'table' then return nil end
    local style = OldKraken.UIStyle
    if type(style) ~= 'table' or type(style.Window) ~= 'function' then return nil end

    local cols, cardW, cardH, gap = 3, 270, 152, 14
    local startX, startY = 21, -102
    local rows = math.max(1, math.ceil(#CARDS / cols))
    local winW = startX * 2 + cols * cardW + (cols - 1) * gap
    local winH = math.abs(startY) + rows * cardH + (rows - 1) * gap + 56

    frame = CreateFrame('Frame', 'OldKrakenWhatsNewFrame', UIParent)
    frame:SetSize(winW, winH)
    frame:SetPoint('CENTER')
    frame:EnableMouse(true)
    if type(frame.SetClampedToScreen) == 'function' then frame:SetClampedToScreen(true) end
    if type(frame.SetMovable) == 'function' then frame:SetMovable(true) end
    if type(frame.RegisterForDrag) == 'function' then frame:RegisterForDrag('LeftButton') end
    frame:SetScript('OnDragStart', function(self) if type(self.StartMoving) == 'function' then self:StartMoving() end end)
    frame:SetScript('OnDragStop', function(self) if type(self.StopMovingOrSizing) == 'function' then self:StopMovingOrSizing() end end)
    frame:SetScript('OnHide', function() WhatsNew:MarkSeen() end)
    if type(UISpecialFrames) == 'table' then tinsert(UISpecialFrames, 'OldKrakenWhatsNewFrame') end

    style.Window(frame)
    local colors = style.Colors or {}
    local gold = colors.brandGold or { 0.88, 0.69, 0.32 }
    local muted = colors.mutedText or { 0.68, 0.74, 0.82 }

    local applyFont = type(style.Font) == 'function' and style.Font or nil

    local headerTitle = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
    headerTitle:SetPoint('LEFT', frame, 'TOPLEFT', 14, -15)
    if applyFont then applyFont(headerTitle, 13, true) end
    headerTitle:SetText(T('Що нового'))
    headerTitle:SetTextColor(gold[1], gold[2], gold[3])

    local closeBtn = CreateFrame('Button', nil, frame, 'UIPanelButtonTemplate')
    closeBtn:SetSize(24, 22)
    closeBtn:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -6, -4)
    closeBtn:SetText('×')
    if type(style.Button) == 'function' then style.Button(closeBtn) end
    closeBtn:SetScript('OnClick', function() WhatsNew:MarkSeen(); frame:Hide() end)

    local emblem = frame:CreateTexture(nil, 'ARTWORK')
    emblem:SetSize(48, 48)
    emblem:SetPoint('TOPLEFT', frame, 'TOPLEFT', 21, -42)
    if type(style.EmblemPath) == 'function' then emblem:SetTexture(style.EmblemPath()) end

    titleText = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
    titleText:SetPoint('LEFT', emblem, 'RIGHT', 14, 9)
    if applyFont then applyFont(titleText, 18, true) end
    titleText:SetTextColor(1, 1, 1)

    local subText = frame:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    subText:SetPoint('TOPLEFT', titleText, 'BOTTOMLEFT', 0, -4)
    if applyFont then applyFont(subText, 12.5) end
    subText:SetText(T('Основні зміни та покращення цього оновлення'))
    subText:SetTextColor(muted[1], muted[2], muted[3])

    for idx, item in ipairs(CARDS) do
        local col = (idx - 1) % cols
        local row = math.floor((idx - 1) / cols)
        local x = startX + col * (cardW + gap)
        local y = startY - row * (cardH + gap)
        local card = style.PanelFrame(frame, 'panelEdge')
        card:SetSize(cardW, cardH)
        card:SetPoint('TOPLEFT', frame, 'TOPLEFT', x, y)

        local icon = card:CreateTexture(nil, 'ARTWORK')
        icon:SetSize(28, 28)
        icon:SetPoint('TOPLEFT', card, 'TOPLEFT', 14, -14)
        icon:SetTexture(item.icon or (type(style.EmblemPath) == 'function' and style.EmblemPath() or ''))

        local cardTitle = card:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
        cardTitle:SetPoint('LEFT', icon, 'RIGHT', 10, 0)
        cardTitle:SetPoint('RIGHT', card, 'RIGHT', -12, 0)
        if applyFont then applyFont(cardTitle, 14, true) end
        if type(cardTitle.SetJustifyH) == 'function' then cardTitle:SetJustifyH('LEFT') end
        cardTitle:SetText(T(item.title))
        cardTitle:SetTextColor(gold[1], gold[2], gold[3])

        local desc = card:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        desc:SetPoint('TOPLEFT', icon, 'BOTTOMLEFT', 0, -10)
        desc:SetPoint('BOTTOMRIGHT', card, 'BOTTOMRIGHT', -14, 40)
        if applyFont then applyFont(desc, 12.5) end
        if type(desc.SetJustifyH) == 'function' then desc:SetJustifyH('LEFT') end
        if type(desc.SetJustifyV) == 'function' then desc:SetJustifyV('TOP') end
        if type(desc.SetWordWrap) == 'function' then desc:SetWordWrap(true) end
        desc:SetText(T(item.desc))
        desc:SetTextColor(0.86, 0.90, 0.96)

        if item.tab then
            local openBtn = CreateFrame('Button', nil, card, 'UIPanelButtonTemplate')
            openBtn:SetSize(88, 22)
            openBtn:SetPoint('BOTTOMRIGHT', card, 'BOTTOMRIGHT', -10, 10)
            openBtn:SetText(T('Відкрити'))
            if type(style.Button) == 'function' then style.Button(openBtn) end
            local targetTab = item.tab
            openBtn:SetScript('OnClick', function() openTab(targetTab) end)
        end
    end

    local hint = frame:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    hint:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 20, 18)
    if applyFont then applyFont(hint, 11.5) end
    hint:SetText(T('Показати знову в чаті:') .. ' |cff2ec4b6/okr new|r')
    hint:SetTextColor(muted[1], muted[2], muted[3])

    local okBtn = CreateFrame('Button', nil, frame, 'UIPanelButtonTemplate')
    okBtn:SetSize(136, 30)
    okBtn:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -21, 14)
    okBtn:SetText(T('Зрозуміло'))
    if type(style.Button) == 'function' then style.Button(okBtn, 'primary') end
    okBtn:SetScript('OnClick', function() WhatsNew:MarkSeen(); frame:Hide() end)

    frame:Hide()
    return frame
end

function WhatsNew:Show(force)
    if not force and not self:ShouldAutoShow() then return false end
    local f = ensureFrame()
    if not f then return false end
    if titleText then
        local ver = type(OldKraken.version) == 'string' and OldKraken.version ~= '' and OldKraken.version or ''
        titleText:SetText(string.format(T('Оновлення Old Kraken %s'), ver))
    end
    f:Show()
    return true
end

local events = CreateFrame('Frame')

function WhatsNew:CheckAutoShow()
    if sessionChecked then return false end
    local db = OldKraken.DB
    local ver = OldKraken.version
    if type(db) == 'table' and type(db.settings) == 'table' and type(ver) == 'string' and ver ~= ''
        and db.settings.whatsNewSeenVersion == ver then
        sessionChecked = true
        if type(events.UnregisterAllEvents) == 'function' then pcall(events.UnregisterAllEvents, events) end
        return false
    end
    if type(InCombatLockdown) == 'function' and InCombatLockdown() then
        return false
    end
    if self:Show(false) then
        sessionChecked = true
        if type(events.UnregisterAllEvents) == 'function' then pcall(events.UnregisterAllEvents, events) end
        return true
    end
    return false
end

pcall(events.RegisterEvent, events, 'PLAYER_ENTERING_WORLD')
pcall(events.RegisterEvent, events, 'PLAYER_REGEN_ENABLED')
events:SetScript('OnEvent', function(_, event)
    if sessionChecked then return end
    if event == 'PLAYER_REGEN_ENABLED' then
        WhatsNew:CheckAutoShow()
        return
    end
    if type(C_Timer) == 'table' and type(C_Timer.After) == 'function' then
        C_Timer.After(1.5, function() WhatsNew:CheckAutoShow() end)
    else
        WhatsNew:CheckAutoShow()
    end
end)
