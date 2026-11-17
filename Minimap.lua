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
    background:SetVertexColor(unpack(OldKraken.UIStyle.Colors.window))
    local icon = button:CreateTexture(nil, 'ARTWORK')
    icon:SetPoint('CENTER', button, 'CENTER', 0, 0)
    icon:SetSize(28, 28)
    icon:SetTexture(OldKraken.UIStyle.EmblemPath())
    local border = button:CreateTexture(nil, 'OVERLAY')
    border:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')
    border:SetSize(54, 54); border:SetPoint('TOPLEFT', button, 'TOPLEFT', 0, 0)
    button:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')
    button:SetScript('OnClick', function(_, mouseButton)
        local target = mouseButton == 'RightButton' and OldKraken.GroupFinder or OldKraken.GuildRoster
        if target and type(target.Toggle) == 'function' then target:Toggle() end
    end)
    button:SetScript('OnEnter', function(self)
        GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
        local gold = OldKraken.UIStyle.Colors.brandGold
        GameTooltip:SetText('Old Kraken', gold[1], gold[2], gold[3])
        GameTooltip:AddLine('Ліва кнопка: відкрити / закрити Old Kraken', 1, 1, 1)
        GameTooltip:AddLine('Права кнопка: відкрити / закрити групи', 1, 1, 1)
        GameTooltip:AddLine('Перетягніть, щоб перемістити', 0.75, 0.75, 0.75)
        GameTooltip:Show()
    end)
    button:SetScript('OnLeave', function() GameTooltip:Hide() end)
    button:SetScript('OnDragStart', function(self) self:SetScript('OnUpdate', updatePosition) end)
    button:SetScript('OnDragStop', function(self) self:SetScript('OnUpdate', nil) end)
    place(angle)
end)
