-- Minimap shortcut; its angle is stored in the addon's existing settings.
local button

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
    background:SetVertexColor(0.05, 0.10, 0.15, 1)
    local icon = button:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
    icon:SetPoint('CENTER', button, 'CENTER', 0, 0)
    icon:SetTextColor(0.30, 0.72, 1)
    icon:SetText('K')
    local border = button:CreateTexture(nil, 'OVERLAY')
    border:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')
    border:SetSize(54, 54); border:SetPoint('TOPLEFT', button, 'TOPLEFT', 0, 0)
    button:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')
    local menu = CreateFrame('Frame', 'OldKrakenMinimapMenu', button, 'UIDropDownMenuTemplate')
    UIDropDownMenu_Initialize(menu, function(_, level)
        local function entry(text, callback, checked)
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.func, info.checked = text, callback, checked
            info.notCheckable = checked == nil
            UIDropDownMenu_AddButton(info, level)
        end
        entry('Відкрити /okr', function() if OldKraken.GuildRoster then OldKraken.GuildRoster:Show() end end)
        entry('Пошук груп', function() if OldKraken.GroupFinder then OldKraken.GroupFinder:Show() end end)
        entry('Лівий клік: /okr', function() db.settings.minimapAction = 'roster' end, db.settings.minimapAction ~= 'groups')
        entry('Лівий клік: пошук груп', function() db.settings.minimapAction = 'groups' end, db.settings.minimapAction == 'groups')
    end, 'MENU')
    button:SetScript('OnClick', function(_, mouseButton)
        if mouseButton == 'RightButton' then
            ToggleDropDownMenu(1, nil, menu, 'cursor', 0, 0)
        elseif db.settings.minimapAction == 'groups' then
            if OldKraken.GroupFinder then OldKraken.GroupFinder:Show() end
        elseif OldKraken.GuildRoster then
            OldKraken.GuildRoster:Show()
        end
    end)
    button:SetScript('OnEnter', function(self)
        GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
        GameTooltip:SetText('Old Kraken', 0.3, 0.72, 1)
        GameTooltip:AddLine(db.settings.minimapAction == 'groups' and 'Ліва кнопка: пошук груп' or 'Ліва кнопка: /okr', 1, 1, 1)
        GameTooltip:AddLine('Права кнопка: меню та налаштування', 1, 1, 1)
        GameTooltip:AddLine('Перетягніть, щоб перемістити', 0.75, 0.75, 0.75)
        GameTooltip:Show()
    end)
    button:SetScript('OnLeave', function() GameTooltip:Hide() end)
    button:SetScript('OnDragStart', function(self) self:SetScript('OnUpdate', updatePosition) end)
    button:SetScript('OnDragStop', function(self) self:SetScript('OnUpdate', nil) end)
    place(angle)
end)
