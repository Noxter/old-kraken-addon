local T = OldKraken.Translate or function(text) return text end
-- Minimap shortcut; uses LibDataBroker-1.1 + LibDBIcon-1.0 when available, with a standalone button fallback.
local LDB_NAME = 'OldKraken'
local button
local libDBIcon
local initialized = false
local communitiesButton
local matchingGroups = 0
local roles = {'tank', 'healer', 'dps'}

local function attachGroupIndicator(targetButton)
    if not targetButton or rawget(targetButton, 'groupIndicator') or type(targetButton.CreateTexture) ~= 'function' then return end
    local indicator = targetButton:CreateTexture(nil, 'OVERLAY', nil, 2)
    indicator:SetTexture('Interface\\AddOns\\OldKraken\\Media\\StatusOnline.tga')
    indicator:SetSize(12, 12)
    indicator:SetPoint('BOTTOMRIGHT', targetButton, 'BOTTOMRIGHT', -1, 1)
    indicator:Hide()
    targetButton.groupIndicator = indicator
end

local function ensureLibDBIconButton()
    if not libDBIcon or type(libDBIcon.GetMinimapButton) ~= 'function' then return end
    if not button then button = libDBIcon:GetMinimapButton(LDB_NAME) end
    if button then
        attachGroupIndicator(button)
        local indicator = rawget(button, 'groupIndicator')
        if indicator then
            if matchingGroups > 0 then indicator:Show() else indicator:Hide() end
        end
    end
end

local function updateMinimapVisibility()
    local settings = OldKraken.DB and OldKraken.DB.settings
    local show = type(settings) ~= 'table' or settings.showMinimapButton ~= false
    if libDBIcon then
        if type(settings) == 'table' and type(settings.minimap) == 'table' then
            settings.minimap.hide = not show
        end
        if show then
            if type(libDBIcon.Show) == 'function' then libDBIcon:Show(LDB_NAME) end
            ensureLibDBIconButton()
        else
            if type(libDBIcon.Hide) == 'function' then libDBIcon:Hide(LDB_NAME) end
        end
        return
    end
    if not button then return end
    if show then button:Show() else button:Hide() end
end

local function updateGroupIndicator()
    if not initialized then return end
    local t0 = OldKraken and OldKraken.perfEnabled and type(debugprofilestop) == 'function' and debugprofilestop() or nil
    local finder = OldKraken.GroupFinder
    local level = type(UnitLevel) == 'function' and tonumber(UnitLevel('player'))
    local count = 0
    if finder and finder.active and finder.identity and level and level > 0
        and type(finder.groups) == 'table' and type(finder.CanPerformRole) == 'function'
        and type(finder.RoleAvailable) == 'function' then
        local available = {}
        for _, role in ipairs(roles) do available[role] = finder:CanPerformRole(finder.identity, role) end
        for key, group in pairs(finder.groups) do
            local hiddenOffline = type(finder.IsGroupHiddenByOfflineOwner) == 'function' and finder:IsGroupHiddenByOfflineOwner(key, group)
            if not hiddenOffline and not group.closed and not group.hidden and group.owner ~= finder.identity
                and type(group.members) == 'table' and type(group.maxSize) == 'number'
                and #group.members < group.maxSize and type(group.minLevel) == 'number'
                and type(group.maxLevel) == 'number' and level >= group.minLevel and level <= group.maxLevel then
                local member = false
                for _, name in ipairs(group.members) do if name == finder.identity then member = true; break end end
                if not member then
                    for _, role in ipairs(roles) do
                        if available[role] and finder:RoleAvailable(group, role) then count = count + 1; break end
                    end
                end
            end
        end
    end
    matchingGroups = count
    ensureLibDBIconButton()
    local indicator = button and rawget(button, 'groupIndicator')
    if indicator then
        if count > 0 then indicator:Show() else indicator:Hide() end
    end
    if t0 and OldKraken.PerfRecord then OldKraken:PerfRecord('minimap.ind', debugprofilestop() - t0) end
end

local function onMinimapClick(_, mouseButton)
    local target = mouseButton == 'RightButton' and OldKraken.GroupFinder or OldKraken.GuildRoster
    if target and type(target.Toggle) == 'function' then target:Toggle() end
end

local function populateTooltip(tooltip)
    if not tooltip then return end
    local gold = OldKraken.UIStyle.Colors.brandGold
    tooltip:SetText(OldKraken.GetGuildDisplayName and OldKraken.GetGuildDisplayName() or 'Old Kraken', gold[1], gold[2], gold[3])
    if matchingGroups > 0 then tooltip:AddLine(T('Підходящих груп за рівнем і роллю: ') .. matchingGroups, 0.41, 0.86, 0.55) end
    tooltip:AddLine(T('Ліва кнопка: відкрити / закрити Old Kraken'), 1, 1, 1)
    tooltip:AddLine(T('Права кнопка: відкрити / закрити групи'), 1, 1, 1)
    tooltip:AddLine(T('Перетягніть, щоб перемістити'), 0.75, 0.75, 0.75)
end

local function place(angle)
    local radians = math.rad(angle)
    local x, y = math.cos(radians), math.sin(radians)
    if type(GetMinimapShape) == 'function' and GetMinimapShape() == 'SQUARE' then
        local edge = math.max(math.abs(x), math.abs(y))
        if edge > 0 then x, y = x / edge, y / edge end
    end
    button:ClearAllPoints()
    button:SetPoint('CENTER', Minimap, 'CENTER', x * (Minimap:GetWidth() / 2 + 5), y * (Minimap:GetHeight() / 2 + 5))
end

local function updatePosition(self)
    local x, y = Minimap:GetCenter()
    if not x or not y then return end
    local cursorX, cursorY = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    if not scale or scale <= 0 then return end
    local angle = math.deg(math.atan2(cursorY / scale - y, cursorX / scale - x)) % 360
    OldKraken.DB.settings.minimapAngle = angle
    if type(OldKraken.DB.settings.minimap) == 'table' then
        OldKraken.DB.settings.minimap.minimapPos = angle
    end
    place(angle)
end

local function registerLibDBIcon(db)
    local libStub = LibStub
    if type(libStub) ~= 'table' and type(libStub) ~= 'function' then return false end
    local okBroker, broker = pcall(libStub, 'LibDataBroker-1.1', true)
    local okIcon, libIcon = pcall(libStub, 'LibDBIcon-1.0', true)
    if not (okBroker and broker and okIcon and libIcon) then return false end
    if type(broker.NewDataObject) ~= 'function' or type(libIcon.Register) ~= 'function' then return false end

    if type(db.settings.minimap) ~= 'table' then db.settings.minimap = {} end
    if db.settings.minimap.minimapPos == nil and type(db.settings.minimapAngle) == 'number' then
        db.settings.minimap.minimapPos = db.settings.minimapAngle
    end
    db.settings.minimap.hide = db.settings.showMinimapButton == false

    local okObj, launcher = pcall(broker.NewDataObject, broker, LDB_NAME, {
        type = 'launcher',
        text = 'Old Kraken',
        icon = OldKraken.UIStyle.EmblemPath(),
        OnClick = onMinimapClick,
        OnTooltipShow = populateTooltip,
    })
    if not okObj or not launcher then return false end
    local okReg = pcall(libIcon.Register, libIcon, LDB_NAME, launcher, db.settings.minimap)
    if not okReg then return false end
    libDBIcon = libIcon
    ensureLibDBIconButton()
    return true
end

local function createOwnButton(db)
    if not Minimap then return end
    local angle = tonumber(type(db.settings.minimap) == 'table' and db.settings.minimap.minimapPos or nil) or tonumber(db.settings.minimapAngle)
    if not angle or angle ~= angle or angle < 0 or angle >= 360 then angle = 225 end
    button = CreateFrame('Button', 'OldKrakenMinimapButton', Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata('MEDIUM')
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
    button:RegisterForDrag('LeftButton')
    button:EnableMouse(true)
    local background = button:CreateTexture(nil, 'BACKGROUND')
    background:SetTexture('Interface\\Minimap\\UI-Minimap-Background')
    background:SetPoint('CENTER', button, 'CENTER', 0, 1)
    background:SetSize(22, 22)
    background:SetVertexColor(unpack(OldKraken.UIStyle.Colors.window))
    button.background = background
    local icon = button:CreateTexture(nil, 'ARTWORK')
    icon:SetPoint('CENTER', button, 'CENTER', 0, 1)
    icon:SetSize(18, 18)
    icon:SetTexture(OldKraken.UIStyle.EmblemPath())
    button.icon = icon
    local border = button:CreateTexture(nil, 'OVERLAY')
    border:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')
    border:SetSize(52, 52)
    border:SetPoint('TOPLEFT', button, 'TOPLEFT', 0, 0)
    button.border = border
    attachGroupIndicator(button)
    button:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')
    button:SetScript('OnClick', onMinimapClick)
    button:SetScript('OnEnter', function(self)
        GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
        populateTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    button:SetScript('OnLeave', function() GameTooltip:Hide() end)
    button:SetScript('OnDragStart', function(self) self:SetScript('OnUpdate', updatePosition) end)
    button:SetScript('OnDragStop', function(self) self:SetScript('OnUpdate', nil) end)
    place(angle)
end

OldKraken:On('INITIALIZED', function(db)
    if initialized or type(db) ~= 'table' or type(db.settings) ~= 'table' then return end
    if not registerLibDBIcon(db) then
        if not Minimap then return end
        createOwnButton(db)
    end
    initialized = true
    updateMinimapVisibility()
    updateGroupIndicator()
    if C_Timer and type(C_Timer.NewTicker) == 'function' then C_Timer.NewTicker(10, updateGroupIndicator) end
end)

local function attachCommunitiesButton()
    if communitiesButton or not CommunitiesFrame then return end
    communitiesButton = CreateFrame('Button', 'OldKrakenCommunitiesButton', CommunitiesFrame)
    local lastTab = (type(CommunitiesFrame.GuildBenefitsTab) == 'table' and type(CommunitiesFrame.GuildBenefitsTab.IsShown) == 'function'
        and CommunitiesFrame.GuildBenefitsTab:IsShown() and CommunitiesFrame.GuildBenefitsTab)
        or (type(CommunitiesFrame.GuildInfoTab) == 'table' and type(CommunitiesFrame.GuildInfoTab.GetPoint) == 'function' and CommunitiesFrame.GuildInfoTab)
    local tabW = lastTab and type(lastTab.GetWidth) == 'function' and tonumber(lastTab:GetWidth()) or 0
    local tabH = lastTab and type(lastTab.GetHeight) == 'function' and tonumber(lastTab:GetHeight()) or 0
    local btnW = (tabW and tabW >= 32) and tabW or 40
    local btnH = (tabH and tabH >= 32) and tabH or 40
    communitiesButton:SetSize(btnW, btnH)
    if type(CommunitiesFrame.GetFrameStrata) == 'function' then
        communitiesButton:SetFrameStrata(CommunitiesFrame:GetFrameStrata() or 'MEDIUM')
    end
    local level = (type(CommunitiesFrame.GuildInfoTab) == 'table' and type(CommunitiesFrame.GuildInfoTab.GetFrameLevel) == 'function' and CommunitiesFrame.GuildInfoTab:GetFrameLevel())
        or (type(CommunitiesFrame.GetFrameLevel) == 'function' and CommunitiesFrame:GetFrameLevel()) or 1
    communitiesButton:SetFrameLevel(level + 5)
    if lastTab == CommunitiesFrame.GuildBenefitsTab and lastTab then
        communitiesButton:SetPoint('TOP', lastTab, 'BOTTOM', 0, -16)
    elseif lastTab then
        communitiesButton:SetPoint('TOP', lastTab, 'BOTTOM', 0, -64)
    else
        communitiesButton:SetPoint('TOPLEFT', CommunitiesFrame, 'TOPRIGHT', 2, -258)
    end
    communitiesButton:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
    communitiesButton:EnableMouse(true)
    local bg = communitiesButton:CreateTexture(nil, 'BACKGROUND')
    bg:SetAllPoints()
    local panelColor = OldKraken.UIStyle.Colors.panel or OldKraken.UIStyle.Colors.window
    bg:SetColorTexture(panelColor[1], panelColor[2], panelColor[3], 0.96)
    local edgeColor = OldKraken.UIStyle.Colors.panelEdge or OldKraken.UIStyle.Colors.brandGold
    for _, side in ipairs({
        {'TOPLEFT', 'TOPRIGHT', 1, true},
        {'BOTTOMLEFT', 'BOTTOMRIGHT', 1, true},
        {'TOPLEFT', 'BOTTOMLEFT', 1, false},
        {'TOPRIGHT', 'BOTTOMRIGHT', 1, false},
    }) do
        local line = communitiesButton:CreateTexture(nil, 'BORDER')
        line:SetPoint(side[1], communitiesButton, side[1], 0, 0)
        line:SetPoint(side[2], communitiesButton, side[2], 0, 0)
        if side[4] then line:SetHeight(side[3]) else line:SetWidth(side[3]) end
        line:SetColorTexture(edgeColor[1], edgeColor[2], edgeColor[3], edgeColor[4] or 1)
    end
    local icon = communitiesButton:CreateTexture(nil, 'ARTWORK')
    icon:SetPoint('CENTER')
    icon:SetSize(math.floor(btnW * 0.8), math.floor(btnH * 0.8))
    icon:SetTexture(OldKraken.UIStyle.EmblemPath())
    communitiesButton:SetHighlightTexture('Interface\\Buttons\\ButtonHilight-Square', 'ADD')
    communitiesButton:SetScript('OnClick', function(_, mouseButton)
        local target = mouseButton == 'RightButton' and OldKraken.GroupFinder or OldKraken.GuildRoster
        if target and type(target.Toggle) == 'function' then target:Toggle() end
    end)
    communitiesButton:SetScript('OnEnter', function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
        local gold = OldKraken.UIStyle.Colors.brandGold
        GameTooltip:SetText(OldKraken.GetGuildDisplayName and OldKraken.GetGuildDisplayName() or 'Old Kraken', gold[1], gold[2], gold[3])
        GameTooltip:AddLine(T('Ліва кнопка: відкрити / закрити Old Kraken'), 1, 1, 1)
        GameTooltip:AddLine(T('Права кнопка: відкрити / закрити групи'), 1, 1, 1)
        GameTooltip:Show()
    end)
    communitiesButton:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
end

local function isCommunitiesLoaded()
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if type(isLoaded) ~= 'function' then return CommunitiesFrame ~= nil end
    local ok, loaded = pcall(isLoaded, 'Blizzard_Communities')
    return ok and loaded == true
end

if isCommunitiesLoaded() and CommunitiesFrame then
    attachCommunitiesButton()
else
    local communitiesLoader = CreateFrame('Frame')
    pcall(communitiesLoader.RegisterEvent, communitiesLoader, 'ADDON_LOADED')
    communitiesLoader:SetScript('OnEvent', function(self, _, addonName)
        if addonName == 'Blizzard_Communities' and CommunitiesFrame then
            attachCommunitiesButton()
            self:UnregisterEvent('ADDON_LOADED')
        end
    end)
end

OldKraken:On('MINIMAP_BUTTON_SETTING', updateMinimapVisibility)
OldKraken:On('GROUP_FINDER_CHANGED', updateGroupIndicator)
OldKraken:On('GROUP_FINDER_OFFLINE_CHANGED', updateGroupIndicator)
local indicatorEvents = CreateFrame('Frame')
for _, event in ipairs({'PLAYER_ENTERING_WORLD', 'PLAYER_LEVEL_UP', 'GUILD_ROSTER_UPDATE',
    'GROUP_ROSTER_UPDATE', 'PLAYER_ROLES_ASSIGNED', 'ROLE_CHANGED_INFORM',
    'PLAYER_SPECIALIZATION_CHANGED', 'ACTIVE_TALENT_GROUP_CHANGED'}) do
    pcall(indicatorEvents.RegisterEvent, indicatorEvents, event)
end
indicatorEvents:SetScript('OnEvent', updateGroupIndicator)
