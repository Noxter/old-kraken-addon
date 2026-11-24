from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
OldKraken = {name = 'OldKraken', listeners = {}}; UIParent = {GetWidth=function() return 0 end}; StaticPopupDialogs = {}; UISpecialFrames = {}
function UnitLevel() return 20 end
OldKraken.UIStyle = {
    Colors = {
        window = {0.025, 0.035, 0.055, 0.98},
        panel = {0.055, 0.07, 0.095, 0.96},
        brandGold = {0.88, 0.69, 0.32, 1},
        panelEdge = {0.33, 0.26, 0.14, 0.68},
        primaryButton = {0.20, 0.31, 0.56, 1},
        primaryButtonEdge = {0.33, 0.47, 0.76, 1},
        button = {0.08, 0.095, 0.125, 1},
        buttonEdge = {0.20, 0.23, 0.29, 0.85},
        actionBlue = {0.24, 0.38, 0.75, 0.24},
        text = {0.93, 0.94, 0.96},
        mutedText = {0.63, 0.67, 0.73},
        sel = {0.102, 0.141, 0.302, 1},
        selEdge = {0.478, 0.541, 0.980, 1},
        zebra = {1, 1, 1, 0.035},
        divider = {0.20, 0.23, 0.29, 0.85},
        white = {1, 1, 1, 1},
        success = {0.41, 0.86, 0.55, 1},
        warning = {1, 0.76, 0.42, 1},
        danger = {1, 0.48, 0.43, 1},
        info = {0.40, 0.70, 1, 1},
        neutral = {0.63, 0.67, 0.73, 1},
        roleTank = {0.40, 0.70, 1, 1},
        roleHealer = {0.41, 0.86, 0.55, 1},
        roleDps = {1, 0.48, 0.43, 1},
        roleFlex = {1, 0.82, 0.42, 1},
        roleEmpty = {0.16, 0.18, 0.22, 1},
    },
    EmblemPath = function() return 'OldKrakenEmblem.tga' end,
    Window = function() end,
    Button = function() end,
    Input = function() end,
    Dropdown = function() end,
    Panel = function(frame, x, y, width, height)
        assert(frame and type(x) == 'number' and type(y) == 'number' and type(width) == 'number' and type(height) == 'number',
            'UIStyle.Panel requires numeric x, y, width, height')
    end,
    Font = function(fs) return fs end,
    Label = function(parent, text) local fs = parent:CreateFontString(); fs:SetText(text or ''); return fs end,
    Divider = function(parent) return parent:CreateTexture() end,
    PanelFrame = function(parent) return CreateFrame('Frame', nil, parent) end,
    Chip = function(parent, text)
        local c = CreateFrame('Button', nil, parent)
        c.label = c:CreateFontString(); c.dot = c:CreateTexture()
        function c:SetLabel(v) self.label:SetText(v or '') end
        function c:SetDotColor() end
        function c:SetActive(a) self.active = a and true or false end
        c:SetLabel(text); return c
    end,
    PillBadge = function(parent, text, kind)
        local p = CreateFrame('Frame', nil, parent)
        p.fill = p:CreateTexture(); p.label = p:CreateFontString()
        function p:SetKind(k) self.kind = k end
        function p:SetLabel(v) self.label:SetText(v or '') end
        p:SetKind(kind); p:SetLabel(text); return p
    end,
    SegmentedTabs = function(parent, items, onSelect, options)
        local box = CreateFrame('Frame', nil, parent)
        box.tabs = {}
        for _, item in ipairs(items) do
            local tab = CreateFrame('Button', nil, box)
            tab.label = tab:CreateFontString(); tab.label:SetText(item.label)
            tab.badge = CreateFrame('Frame', nil, tab); tab.badge.text = tab.badge:CreateFontString()
            tab:SetScript('OnClick', function() if onSelect then onSelect(item.key) end end)
            box.tabs[item.key] = tab
        end
        function box:SetActive(key)
            self.activeKey = key
            for k, t in pairs(self.tabs) do t.selected = (k == key) end
        end
        function box:SetBadge(key, count)
            local t = self.tabs[key]
            if t then t.badge.count = count; t.badge:SetShown((tonumber(count) or 0) > 0) end
        end
        box:SetActive(options and options.active or (items[1] and items[1].key))
        return box
    end,
    StepIndicator = function(parent, number, title)
        local s = CreateFrame('Frame', nil, parent)
        s.number = s:CreateFontString(); s.number:SetText(tostring(number))
        s.title = s:CreateFontString(); s.title:SetText(title or '')
        function s:SetTitle(v) self.title:SetText(v or '') end
        return s
    end,
    ApplySelection = function(card, selected) card.isSelected = selected and true or false end,
}
function StaticPopup_Show() end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_JustifyText() end
function UIDropDownMenu_Initialize(frame, initialize) frame.dropdownInit = initialize end
function UIDropDownMenu_CreateInfo() return {} end
dropdownItems = {}
function UIDropDownMenu_AddButton(info) dropdownItems[#dropdownItems+1] = info end
function UIDropDownMenu_SetText() end
function selectDropdown(frame, value)
    dropdownItems = {}
    frame.dropdownInit(frame, 1)
    for _, item in ipairs(dropdownItems) do
        if item.value == value then item.func(); return end
    end
    error('Dropdown option not found: ' .. tostring(value))
end
function OldKraken:On(name, fn) self.listeners[name] = fn end
function OldKraken:InvitePlayer() end
function print(...) end
function GetServerTime() return 12345 end
function GetTime() return 1 end
function date() return '14.11 20:00' end
SOUNDKIT = {READY_CHECK = 123}
alertSoundCalls = 0
function PlaySound() alertSoundCalls = alertSoundCalls + 1 end
local methods = {}
function methods:SetText(v) self.text = v end
function methods:GetText() return self.text or '' end
function methods:SetSize(w, h) self.width = w; self.height = h end
function methods:SetHeight(h) self.height = h end
function methods:SetTexture(texture) self.texture = texture end
function methods:SetTexCoord(...) self.texCoord = {...} end
function methods:SetAlpha(value) self.alpha = value end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetShown(value) self.shown = value end
function methods:IsShown() return self.shown end
function methods:LockHighlight() self.highlightLocked = true end
function methods:UnlockHighlight() self.highlightLocked = false end
function methods:GetStringHeight() return 0 end
function methods:SetScript(name, fn) self.scripts[name] = fn end
function methods:RegisterEvent(name) self.events = rawget(self, 'events') or {}; self.events[name] = true end
function methods:CreateFontString() return CreateFrame() end
function methods:CreateTexture() return CreateFrame() end
function methods:GetFontString()
    local fontString = rawget(self, 'fontString')
    if not fontString then fontString = CreateFrame(); rawset(self, 'fontString', fontString) end
    return fontString
end
local meta = {__index=function(_, k)
    if k == 'TitleText' or k == 'CloseButton' or k == 'template' or k == 'activityPicker' then return nil end
    return methods[k] or function() end
end}
createdFrames = {}
function CreateFrame(_, name, parent, template)
    local frame = setmetatable({scripts={}, parent=parent, template=template}, meta)
    if name then _G[name] = frame end
    createdFrames[#createdFrames + 1] = frame
    return frame
end
''')
for name in ['UIHub.lua', 'ActivityCatalog.lua', 'GroupFinder.lua', 'GroupFinderUI.lua']:
    lua.execute((root / name).read_text(encoding='utf-8'))
lua.execute('''
local f = OldKraken.GroupFinder
f:Initialize('Tester', function() return true end)
function f:GroupAlertsEnabled() return true end
function f:SetGroupAlertsEnabled() return true end
function f:Changed() end
f.active = true

local function addGroup(title, category, dungeon, role, maxSize, minLevel, maxLevel)
    local ok, id = f:Create(title, category, 'Description', maxSize, minLevel, maxLevel, role, dungeon)
    assert(ok)
    return f.groups[f.identity .. '\\001' .. id]
end
local tankGroup = addGroup('Tank needs healer', 'dungeon', 'rfc', 'tank', 5, 20, 30)
local healerGroup = addGroup('Healer has no open slot', 'dungeon', 'rfc', 'healer', 5, 20, 30)
healerGroup.members = {'Tester', 'Tankmate', 'DPSone', 'DPStwo'}
healerGroup.memberRoles = {Tankmate='tank', DPSone='dps', DPStwo='dps'}
local fullDungeon = addGroup('Full dungeon', 'dungeon', 'rfc', 'tank', 5, 20, 30)
fullDungeon.members = {'Tester', 'Healer', 'DPSone', 'DPStwo', 'DPSThree'}
fullDungeon.memberRoles = {Healer='healer', DPSone='dps', DPStwo='dps', DPSThree='dps'}
local wcGroup = addGroup('Other dungeon', 'dungeon', 'wc', 'tank', 5, 20, 30)
addGroup('Higher level dungeon', 'dungeon', 'rfc', 'tank', 5, 40, 50)
addGroup('Full quest', 'quest', '', 'dps', 1, 20, 30)
f:Show()
assert(OldKraken.listeners.GROUP_FINDER_CHANGED)
OldKraken.listeners.GROUP_FINDER_CHANGED()

local ui = OldKrakenGroupFinderFrame
assert(ui.parent == OldKraken.UIHub.content and ui.embedded and ui.template == nil)
assert(OldKraken.UIHub.currentPage == 'groups')
local function hasTitle(title)
    for _, entry in ipairs(ui.visible) do if entry.group.title == title then return true end end
    return false
end
local function selectTab(key)
    for _, item in ipairs(ui.tabs) do
        if item.key == key then item.button.scripts.OnClick() return end
    end
    error('Tab not found: ' .. key)
end
local function filtersShown(expected)
    for _, control in ipairs(ui.filterControls) do assert(control:IsShown() == expected) end
end

filtersShown(true)
assert(ui.listScroll:IsShown() and ui.listSummary:IsShown())
assert(ui.listSummary.text:find('Показано 4 групи', 1, true))
assert(not hasTitle('Full dungeon') and not hasTitle('Full quest'))
assert(#ui.rows == 6 and ui.rows[4]:IsShown() and not ui.rows[5]:IsShown())
assert(ui.tabs[1].button.activeMark:IsShown())
assert(not ui.tabs[2].button.activeMark:IsShown())
assert(ui.rows[1].art.width == 64 and ui.rows[1].art.height == 64)
assert(ui.rows[1].art.texCoord[2] - ui.rows[1].art.texCoord[1]
    == ui.rows[1].art.texCoord[4] - ui.rows[1].art.texCoord[3])
assert(ui.alertButton.width == 168 and ui.alertButton.height == 31)
assert(ui.searchFilter.width == 170)
assert(ui.minLevelFilter.width == 44 and ui.maxLevelFilter.width == 44)
assert(ui.resetFilterButton.width == 63 and ui.resetFilterButton.height == 28)
ui.rows[1].scripts.OnClick()
assert(ui.rows[1].isSelected and not ui.rows[1].highlightLocked)
assert(ui.detailsHeading.text == ui.visible[1].group.title)
selectTab('mine'); filtersShown(false)
assert(ui.tabs[4].button.activeMark:IsShown() and not ui.tabs[1].button.activeMark:IsShown())
selectTab('applications'); filtersShown(false)
selectTab('create'); filtersShown(false)
assert(not ui.listScroll:IsShown() and not ui.listSummary:IsShown())
selectTab('all'); filtersShown(true)
assert(ui.listScroll:IsShown() and ui.listSummary:IsShown())

selectDropdown(ui.roleFilter, 'healer')
assert(hasTitle('Tank needs healer'))
assert(not hasTitle('Healer has no open slot'))
assert(not hasTitle('Full dungeon'))
assert(not hasTitle('Full quest'))

selectDropdown(ui.roleFilter, '')
selectDropdown(ui.categoryFilter, 'dungeon')
assert(#ui.visible == 4)
selectDropdown(ui.dungeonFilter, 'rfc')
assert(#ui.visible == 3)
selectDropdown(ui.freeFilter, true)
assert(#ui.visible == 3 and not hasTitle('Full dungeon'))
ui.minLevelFilter:SetText('20')
ui.minLevelFilter.scripts.OnTextChanged()
ui.maxLevelFilter:SetText('30')
ui.maxLevelFilter.scripts.OnTextChanged()
assert(#ui.visible == 2 and not hasTitle('Higher level dungeon'))
-- Inverted range (from > to) is handled gracefully by swapping bounds.
ui.minLevelFilter:SetText('30')
ui.minLevelFilter.scripts.OnTextChanged()
ui.maxLevelFilter:SetText('20')
ui.maxLevelFilter.scripts.OnTextChanged()
assert(#ui.visible == 2)
ui.searchFilter:SetText('Tank needs healer')
ui.searchFilter.scripts.OnTextChanged()
assert(#ui.visible == 1 and hasTitle('Tank needs healer'))
assert(ui.listSummary.text:find('Показано 1 груп', 1, true))
-- Reset button clears all filters and restores all 4 non-full open groups.
ui.resetFilterButton.scripts.OnClick()
assert(#ui.visible == 4 and ui.searchFilter:GetText() == '' and ui.minLevelFilter:GetText() == '' and ui.maxLevelFilter:GetText() == '')

selectTab('create')
local function selectActivityCard(value)
    local picker=assert(ui.activityPicker)
    assert(picker:IsShown())
    for _,card in ipairs(picker.cards) do
        if card.entry and card.entry.value==value then card.scripts.OnClick(card); assert(picker:IsShown()); return end
    end
    error('Activity card not found: '..value)
end
ui.titleBox:SetText('')
ui.descriptionBox:SetText('Fresh listing')
ui.maxBox:SetText('5')
ui.minBox:SetText('20')
ui.maxLevelBox:SetText('30')
selectActivityCard('rfc')
local firstDungeonTitle = ui.titleBox:GetText()
selectActivityCard('wc')
assert(firstDungeonTitle == 'Вогненна прірва (RFC)')
assert(ui.titleBox:GetText() == 'Печери Стогонів (WC)')
ui.titleBox:SetText('Created from form')
selectActivityCard('rfc')
assert(ui.titleBox:GetText() == 'Created from form')
ui.createButton.scripts.OnClick()
local created
for _, group in pairs(f.groups) do if group.title == 'Created from form' then created = group end end
assert(created and created.dungeon == 'rfc' and created.description == 'Fresh listing')

local application = {
    id='accepted-group', owner='Remote Player', revision=1, closed=false, hidden=false,
    title='Accepted listing', category='quest', description='Accepted request',
    maxSize=5, minLevel=1, maxLevel=60, role='tank',
    members={'Remote Player'}, memberRoles={['Remote Player']='tank'},
}
local applicationKey = application.owner .. '\\001' .. application.id
f.groups[applicationKey] = application
f.pending[applicationKey] = 'reject'
selectTab('applications')
assert(#ui.visible == 1 and ui.visible[1].key == applicationKey)
ui.rows[1].scripts.OnClick()
assert(ui.rows[1].status.text == 'ВІДХИЛЕНО')
assert(ui.applicationActionButton:IsShown() and ui.applicationActionButton.text == 'Прибрати заявку')
assert(ui.applyButton:IsShown())
ui.applicationActionButton.scripts.OnClick()
assert(f.pending[applicationKey] == nil and #ui.visible == 0)

f.pending[applicationKey] = 'pending'
f.pendingVersions[applicationKey], f.pendingRoles[applicationKey] = 123, 'healer'
selectTab('applications')
ui.rows[1].scripts.OnClick()
assert(ui.applicationActionButton:IsShown() and ui.applicationActionButton.text == 'Відкликати')
ui.applicationActionButton.scripts.OnClick()
assert(f.pending[applicationKey] == nil and #ui.visible == 0)

local olderGroup = addGroup('A request', 'quest', '', 'dps', 5, 1, 60)
local newerGroup = addGroup('Z request', 'quest', '', 'dps', 5, 1, 60)
assert(f:ReceiveJoin('Old Applicant', f._pack({f.identity, olderGroup.id, 'dps', 'apply', '100'})))
assert(f:ReceiveJoin('New Applicant', f._pack({f.identity, newerGroup.id, 'dps', 'apply', '200'})))
ui.requestsButton.scripts.OnClick()
local requestWindow = OldKrakenRequestsFrame
assert(requestWindow.entries[1].name == 'New Applicant')
assert(requestWindow.entries[2].name == 'Old Applicant')
local whisperedTarget
function ChatFrame_SendTell(target) whisperedTarget = target end
requestWindow.rows[1].hover.scripts.OnMouseUp(requestWindow.rows[1].hover, 'LeftButton')
assert(whisperedTarget == 'New Applicant', 'left-click on applicant did not whisper')

local sentGuildChat
function IsInGuild() return true end
function SendChatMessage(msg, channel) if channel == 'GUILD' then sentGuildChat = msg end end
ui.tabBar.tabs.create.scripts.OnClick()
selectActivityCard('rfc')
ui.titleBox:SetText('Рейд на Оніксію')
ui.descriptionBox:SetText(string.rep('Привіт ', 35))
ui.createButton.scripts.OnClick()
assert(type(sentGuildChat) == 'string' and #sentGuildChat <= 255, 'guild chat announce exceeded 255 bytes: ' .. tostring(sentGuildChat and #sentGuildChat))
assert(sentGuildChat:find('^LFG ') and sentGuildChat:find('потрібні: ', 1, true) and sentGuildChat:find(' — Old Kraken$', 1, false), 'unexpected guild chat format: ' .. tostring(sentGuildChat))
sentGuildChat = nil
function IsInGroup() return true end
function GetNumGroupMembers() return 2 end
ui.tabBar.tabs.create.scripts.OnClick()
selectActivityCard('sfk')
ui.titleBox:SetText('SFK party')
ui.descriptionBox:SetText('')
ui.createButton.scripts.OnClick()
assert(type(sentGuildChat) == 'string' and sentGuildChat:find('^LFG SFK party · lvl 22–30 · потрібні: Танк, Лікар, DPS — Old Kraken$'), 'unexpected guild chat announce: ' .. tostring(sentGuildChat))
IsInGroup = nil
GetNumGroupMembers = nil

OldKraken.listeners.GROUP_FINDER_NEW(wcGroup)
local alert
for _, frame in ipairs(createdFrames) do if rawget(frame, 'alertArt') then alert = frame; break end end
assert(alert and alert.alertArt:IsShown() and alert.alertArt.texture == 131882,
    'Unexpected alert art: ' .. tostring(alert and alert.alertArt:IsShown()) .. ', ' .. tostring(alert and alert.alertArt.texture))
assert(alert.alertArt.width == 90 and alert.alertArt.height == 118)
assert(alert.alertArt.texCoord[2] - alert.alertArt.texCoord[1]
    == alert.alertArt.texCoord[4] - alert.alertArt.texCoord[3])
assert(alert.alertCaption.text == 'НОВЕ ОГОЛОШЕННЯ')
assert(alert.alertTitle.text:find(wcGroup.title, 1, true))
assert(alert.alertHint.text=='' and not alert.alertHint:IsShown())
assert(alert.groupKey == wcGroup.owner .. '\\001' .. wcGroup.id)
alert.scripts.OnClick(alert, 'LeftButton')
assert(not alert:IsShown() and ui.details.text:find(wcGroup.title, 1, true))
OldKraken.listeners.GROUP_FINDER_NEW_REQUEST(tankGroup, 'Another Applicant', 'healer')
assert(alert.alertArt:IsShown() and alert.alertArt.width == 52 and alert.alertArt.height == 52)
assert(alert.width == 480 and alert.height == 122)
assert(alert.alertChrome:IsShown() and alert.alertFooter.height == 26)
assert(alert.alertCaption.text == 'НОВА ЗАЯВКА')
assert(alert.alertHint.text:find('ЛКМ — мої оголошення', 1, true) and alert.alertHint.text:find('ПКМ — сховати', 1, true))
alert.dragging = false
alert.scripts.OnUpdate(alert, 8)
assert(alert:IsShown() and alert.alpha == 1)
alert.scripts.OnUpdate(alert, 0.5)
assert(alert:IsShown() and alert.alpha == 0.5)
alert.scripts.OnUpdate(alert, 0.5)
assert(not alert:IsShown() and alert.alpha == 0)
local guildEvents = {opened=nil}
function guildEvents:AlertsEnabled() return true end
function guildEvents:ShowEvent(key) self.opened = key end
OldKraken.GuildEvents = guildEvents
OldKraken.listeners.GUILD_EVENTS_NEW('raid-key', {title='Guild raid', owner='Tester', when=12345})
assert(alert.alertCaption.text == 'ПОДІЯ ГІЛЬДІЇ')
alert.scripts.OnClick(alert, 'RightButton')
assert(guildEvents.opened == nil and not alert:IsShown())
OldKraken.listeners.GUILD_EVENTS_NEW('raid-key', {title='Guild raid', owner='Tester', when=12345})
alert.scripts.OnClick(alert, 'LeftButton')
assert(guildEvents.opened == 'raid-key')
assert(alertSoundCalls == 1)

local offlineNow = 5000
local origGetTime, origCTimer = GetTime, C_Timer
local scheduledTimers = {}
C_Timer = { After = function(delay, fn) scheduledTimers[#scheduledTimers + 1] = {delay=delay, fn=fn} end }
function GetTime() return offlineNow end
function GetNumGuildMembers() return 3 end
function GetGuildRosterInfo(i)
    if i == 1 then return 'Offline Leader', 'Member', 1, 35, 'Warrior', 'Orgrimmar', '', '', false, false, 'WARRIOR'
    elseif i == 2 then return 'Party Leader', 'Member', 1, 36, 'Priest', 'Orgrimmar', '', '', true, false, 'PRIEST'
    elseif i == 3 then return 'Cross-Realm', 'Member', 1, 42, 'Mage', 'Orgrimmar', '', '', true, false, 'MAGE' end
end
local origUnitName = UnitName
function UnitName(unit)
    if unit == 'party1' then return 'Party Leader' end
    return origUnitName(unit)
end
local offlineKey = 'Offline Leader\\001off-1'
local partyKey = 'Party Leader\\001party-1'
f.groups[offlineKey] = {
    id='off-1', owner='Offline Leader', title='RFK', category='dungeon', dungeon='rfk',
    description='', role='tank', maxSize=5, minLevel=25, maxLevel=35,
    members={'Offline Leader'}, memberRoles={['Offline Leader']='tank'},
    revision=1, closed=false, seenAt=offlineNow,
}
f.groups[partyKey] = {
    id='party-1', owner='Party Leader', title='SM', category='dungeon', dungeon='sm',
    description='', role='healer', maxSize=5, minLevel=30, maxLevel=40,
    members={'Party Leader'}, memberRoles={['Party Leader']='healer'},
    revision=1, closed=false, seenAt=offlineNow,
}
f.pending[offlineKey] = 'pending'
f.pendingVersions[offlineKey] = 1001
f.pendingRoles[offlineKey] = 'dps'
f.pending[partyKey] = 'pending'
local origClassColors = RAID_CLASS_COLORS
RAID_CLASS_COLORS = {MAGE = {r = 0.2, g = 0.4, b = 0.8}}
local crossKey = 'Cross Realm\\001cross-1'
f.groups[crossKey] = {
    id='cross-1', owner='Cross Realm', title='Uldaman', category='dungeon', dungeon='uld',
    description='', role='dps', maxSize=5, minLevel=40, maxLevel=45,
    members={'Cross Realm'}, memberRoles={['Cross Realm']='dps'},
    revision=1, closed=false, seenAt=offlineNow,
}
f.pending[crossKey] = 'pending'
ui.tabBar.tabs.applications.scripts.OnClick()
assert(#ui.visible == 3)
local sawOffline, sawPending, sawCrossLabel = false, false, false
for i = 1, 3 do
    if ui.visible[i].key == offlineKey then sawOffline = ui.rows[i].status.text == 'ОФЛАЙН' end
    if ui.visible[i].key == partyKey then sawPending = ui.rows[i].status.text == 'ОЧІКУЄ' end
    if ui.visible[i].key == crossKey then
        sawCrossLabel = ui.rows[i].meta.text:find('|cff3366ccCross Realm|r (42)', 1, true) ~= nil
    end
end
RAID_CLASS_COLORS = origClassColors
assert(sawOffline, 'offline owner application should show ОФЛАЙН')
assert(sawPending, 'party owner in guild roster must remain online and show ОЧІКУЄ')
assert(sawCrossLabel, 'playerLabel should resolve class color and level across Name-Realm and Name Realm')
assert(ui.deleteButtons[1]:IsShown(), 'delete button should be shown on applications tab')
assert(#scheduledTimers >= 1, 'offline prune timer should be scheduled')
offlineNow = offlineNow + 301
local pendingTimers = scheduledTimers; scheduledTimers = {}
for _, t in ipairs(pendingTimers) do t.fn() end
assert(f.pending[offlineKey] == nil and f.pendingVersions[offlineKey] == nil and f.pendingRoles[offlineKey] == nil,
    'offline owner application and metadata should auto-prune via timer without manual UI click')
assert(f.pending[partyKey] == 'pending', 'party owner application must not be pruned')
-- Segmented role selector smoke checks: visibility, button count, active role, dropdown filters, creationRoles.
local origRoles = UnitGetAvailableRoles
function UnitGetAvailableRoles(unit) if unit == 'player' then return true, true, true end end
ui.tabBar.tabs.all.scripts.OnClick()
ui.searchFilter:SetText('Uldaman')
ui.searchFilter.scripts.OnTextChanged()
ui.rows[1].scripts.OnClick()
assert(ui.roleButton and ui.roleButton.buttons and ui.roleButton.badge)
assert(not ui.roleButton:IsShown(), 'pending application cannot apply so role selector is hidden')
f.pending[crossKey] = nil
ui.tabBar.tabs.all.scripts.OnClick()
ui.searchFilter:SetText('Uldaman')
ui.searchFilter.scripts.OnTextChanged()
ui.rows[1].scripts.OnClick()
assert(ui.roleButton:IsShown() and ui.roleButton.mode == 'buttons' and #ui.roleButton.allowedRoles == 3)
assert(ui.roleButton.buttons[1]:IsShown() and ui.roleButton.buttons[2]:IsShown() and ui.roleButton.buttons[3]:IsShown() and not ui.roleButton.buttons[4]:IsShown())
ui.roleButton.buttons[1].scripts.OnClick(ui.roleButton.buttons[1])
assert(ui.roleButton.selectedRole == 'tank')
ui.searchFilter:SetText('')
ui.searchFilter.scripts.OnTextChanged()
selectDropdown(ui.categoryFilter, 'dungeon')
selectDropdown(ui.roleFilter, 'tank')
selectDropdown(ui.roleFilter, '')
selectDropdown(ui.categoryFilter, 'all')
ui.tabBar.tabs.create.scripts.OnClick()
assert(not ui.roleButton:IsShown() and #ui.creationRoles == 3 and ui.creationRoles[1].role == 'tank')
ui.tabBar.tabs.all.scripts.OnClick()
UnitGetAvailableRoles = origRoles

UnitName = origUnitName
GetTime = origGetTime
C_Timer = origCTimer
function GetNumGuildMembers() return 0 end
function GetGuildRosterInfo() end
''')
print('UI smoke checks passed')


lua.execute('function UnitLevel() return 18 end')
