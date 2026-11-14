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
    local menu = CreateFrame('Frame', 'OldKrakenMinimapMenu', UIParent)
    menu:SetSize(205, 64); menu:SetFrameStrata('FULLSCREEN_DIALOG'); menu:EnableMouse(true); menu:Hide()
    local menuBackground = menu:CreateTexture(nil, 'BACKGROUND')
    menuBackground:SetAllPoints(); menuBackground:SetColorTexture(0.055, 0.06, 0.07, 0.98)
    local function menuButton(label, y, command)
        local item = CreateFrame('Button', nil, menu, 'UIPanelButtonTemplate')
        item:SetPoint('TOPLEFT', menu, 'TOPLEFT', 6, y); item:SetSize(193, 24)
        item:SetText(label); OldKraken.UIStyle.Button(item)
        item:SetScript('OnClick', function()
            menu:Hide()
            if SlashCmdList and type(SlashCmdList.OLDKRAKEN) == 'function' then
                SlashCmdList.OLDKRAKEN(command)
            end
        end)
    end
    menuButton('Відкрити (/okr)', -6, '')
    menuButton('Пошук групи (/okr group)', -34, 'group')
    menu:SetScript('OnUpdate', function(self)
        if (IsMouseButtonDown('LeftButton') or IsMouseButtonDown('RightButton'))
            and not MouseIsOver(self) and not MouseIsOver(button) then self:Hide() end
    end)
    button:SetScript('OnClick', function(_, mouseButton)
        if mouseButton == 'RightButton' then
            if menu:IsShown() then menu:Hide(); return end
            GameTooltip:Hide()
            menu:ClearAllPoints()
            local x = button:GetCenter()
            if x and x < UIParent:GetWidth() / 2 then
                menu:SetPoint('TOPLEFT', button, 'TOPRIGHT', 6, 0)
            else
                menu:SetPoint('TOPRIGHT', button, 'TOPLEFT', -6, 0)
            end
            menu:Show()
        else
            menu:Hide()
            if SlashCmdList and type(SlashCmdList.OLDKRAKEN) == 'function' then SlashCmdList.OLDKRAKEN('') end
        end
    end)
    button:SetScript('OnEnter', function(self)
        GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
        GameTooltip:SetText('Old Kraken', 0.3, 0.72, 1)
        GameTooltip:AddLine('Ліва кнопка: /okr', 1, 1, 1)
        GameTooltip:AddLine('Права кнопка: меню', 1, 1, 1)
        GameTooltip:AddLine('Перетягніть, щоб перемістити', 0.75, 0.75, 0.75)
        GameTooltip:Show()
    end)
    button:SetScript('OnLeave', function() GameTooltip:Hide() end)
    button:SetScript('OnDragStart', function(self) self:SetScript('OnUpdate', updatePosition) end)
    button:SetScript('OnDragStop', function(self) self:SetScript('OnUpdate', nil) end)
    place(angle)
end)
