local T = OldKraken.Translate or function(text) return text end
-- Minimap shortcut; its angle is stored in the addon's existing settings.
local button
local communitiesButton
local matchingGroups = 0
local roles = {'tank', 'healer', 'dps'}

local function updateMinimapVisibility()
    if not button then return end
    local settings = OldKraken.DB and OldKraken.DB.settings
    if type(settings) == 'table' and settings.showMinimapButton == false then
        button:Hide()
    else
        button:Show()
    end
end

local function updateGroupIndicator()
    if not button then return end
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
    if count > 0 then button.groupIndicator:Show() else button.groupIndicator:Hide() end
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
    place(angle)
end

OldKraken:On('INITIALIZED', function(db)
    if button or not Minimap or type(db.settings) ~= 'table' then return end
    local angle = tonumber(db.settings.minimapAngle)
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
    background:SetPoint('CENTER'); background:SetSize(24, 24)
    background:SetVertexColor(unpack(OldKraken.UIStyle.Colors.window))
    button.background = background
    local icon = button:CreateTexture(nil, 'ARTWORK')
    icon:SetPoint('CENTER', button, 'CENTER', 0, 0)
    icon:SetSize(28, 28)
    icon:SetTexture(OldKraken.UIStyle.EmblemPath())
    button.icon = icon
    local border = button:CreateTexture(nil, 'OVERLAY')
    border:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')
    border:SetSize(54, 54); border:SetPoint('TOPLEFT', button, 'TOPLEFT', 0, 0)
    button.border = border
    local indicator = button:CreateTexture(nil, 'OVERLAY', nil, 2)
    indicator:SetTexture('Interface\\AddOns\\OldKraken\\Media\\StatusOnline.tga')
    indicator:SetSize(12, 12); indicator:SetPoint('BOTTOMRIGHT', button, 'BOTTOMRIGHT', -1, 1)
    indicator:Hide()
    button.groupIndicator = indicator
    button:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')
    button:SetScript('OnClick', function(_, mouseButton)
        local target = mouseButton == 'RightButton' and OldKraken.GroupFinder or OldKraken.GuildRoster
        if target and type(target.Toggle) == 'function' then target:Toggle() end
    end)
    button:SetScript('OnEnter', function(self)
        GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
        local gold = OldKraken.UIStyle.Colors.brandGold
        GameTooltip:SetText(OldKraken.GetGuildDisplayName and OldKraken.GetGuildDisplayName() or 'Old Kraken', gold[1], gold[2], gold[3])
        if matchingGroups > 0 then GameTooltip:AddLine(T('Підходящих груп за рівнем і роллю: ') .. matchingGroups, 0.41, 0.86, 0.55) end
        GameTooltip:AddLine(T('Ліва кнопка: відкрити / закрити Old Kraken'), 1, 1, 1)
        GameTooltip:AddLine(T('Права кнопка: відкрити / закрити групи'), 1, 1, 1)
        GameTooltip:AddLine(T('Перетягніть, щоб перемістити'), 0.75, 0.75, 0.75)
        GameTooltip:Show()
    end)
    button:SetScript('OnLeave', function() GameTooltip:Hide() end)
    button:SetScript('OnDragStart', function(self) self:SetScript('OnUpdate', updatePosition) end)
    button:SetScript('OnDragStop', function(self) self:SetScript('OnUpdate', nil) end)
    place(angle)
    updateMinimapVisibility()
    updateGroupIndicator()
    if C_Timer and type(C_Timer.NewTicker) == 'function' then C_Timer.NewTicker(10, updateGroupIndicator) end
end)

local function attachCommunitiesButton()
    if communitiesButton or not CommunitiesFrame then return end
    communitiesButton = CreateFrame('Button', 'OldKrakenCommunitiesButton', CommunitiesFrame)
    communitiesButton:SetSize(32, 32)
    if type(CommunitiesFrame.GuildInfoTab) == 'table' and type(CommunitiesFrame.GuildInfoTab.GetPoint) == 'function' then
        communitiesButton:SetPoint('TOP', CommunitiesFrame.GuildInfoTab, 'BOTTOM', 0, -16)
    else
        communitiesButton:SetPoint('TOPLEFT', CommunitiesFrame, 'TOPRIGHT', 2, -210)
    end
    communitiesButton:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
    communitiesButton:EnableMouse(true)
    local bg = communitiesButton:CreateTexture(nil, 'BACKGROUND')
    bg:SetAllPoints()
    bg:SetColorTexture(unpack(OldKraken.UIStyle.Colors.window))
    local icon = communitiesButton:CreateTexture(nil, 'ARTWORK')
    icon:SetPoint('CENTER')
    icon:SetSize(26, 26)
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
