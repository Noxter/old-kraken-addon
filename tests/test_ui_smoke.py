from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
OldKraken = {name = 'OldKraken', listeners = {}}; UIParent = {GetWidth=function() return 0 end}; StaticPopupDialogs = {}; UISpecialFrames = {}
OldKraken.UIStyle = {
    Colors = {
        brandGold = {0.88, 0.69, 0.32, 1},
        panelEdge = {0.33, 0.26, 0.14, 0.68},
        text = {0.93, 0.94, 0.96},
        mutedText = {0.63, 0.67, 0.73},
    },
    EmblemPath = function() return 'OldKrakenEmblem.tga' end,
    Window = function() end,
    Button = function() end,
    Input = function() end,
    Dropdown = function() end,
    Panel = function() end,
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
function methods:SetSize(width, height) self.width = width; self.height = height end
function methods:SetTexture(texture) self.texture = texture end
function methods:SetTexCoord(...) self.texCoord = {...} end
function methods:SetAlpha(value) self.alpha = value end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetShown(value) self.shown = value end
function methods:IsShown() return self.shown end
function methods:GetStringHeight() return 0 end
function methods:SetScript(name, fn) self.scripts[name] = fn end
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
assert(ui.previousPageButton:IsShown() and ui.nextPageButton:IsShown() and ui.listPage:IsShown())
assert(ui.tabs[1].button.activeMark:IsShown())
assert(not ui.tabs[2].button.activeMark:IsShown())
assert(ui.previousPageButton.width == 80 and ui.previousPageButton.height == 36)
assert(ui.nextPageButton.width == 80 and ui.nextPageButton.height == 36)
assert(ui.rows[1].art.width == 70 and ui.rows[1].art.height == 70)
assert(ui.rows[1].art.texCoord[2] - ui.rows[1].art.texCoord[1]
    == ui.rows[1].art.texCoord[4] - ui.rows[1].art.texCoord[3])
selectTab('mine'); filtersShown(false)
assert(ui.tabs[4].button.activeMark:IsShown() and not ui.tabs[1].button.activeMark:IsShown())
selectTab('applications'); filtersShown(false)
selectTab('create'); filtersShown(false)
assert(not ui.previousPageButton:IsShown() and not ui.nextPageButton:IsShown() and not ui.listPage:IsShown())
selectTab('all'); filtersShown(true)
assert(ui.previousPageButton:IsShown() and ui.nextPageButton:IsShown())

selectDropdown(ui.roleFilter, 'healer')
assert(hasTitle('Tank needs healer'))
assert(not hasTitle('Healer has no open slot'))
assert(not hasTitle('Full dungeon'))
assert(not hasTitle('Full quest'))

selectDropdown(ui.roleFilter, '')
selectDropdown(ui.categoryFilter, 'dungeon')
assert(#ui.visible == 5)
selectDropdown(ui.dungeonFilter, 'rfc')
assert(#ui.visible == 4)
selectDropdown(ui.freeFilter, true)
assert(#ui.visible == 3 and not hasTitle('Full dungeon'))
ui.levelFilter:SetText('25')
ui.levelFilter.scripts.OnTextChanged()
assert(#ui.visible == 2)
ui.searchFilter:SetText('Tank needs healer')
ui.searchFilter.scripts.OnTextChanged()
assert(#ui.visible == 1 and hasTitle('Tank needs healer'))
assert(not ui.previousPageButton:IsShown() and not ui.nextPageButton:IsShown() and not ui.listPage:IsShown())

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
assert(not alert.alertArt:IsShown())
assert(alert.alertCaption.text == 'НОВА ЗАЯВКА')
assert(alert.alertHint.text:find('Клік — мої оголошення', 1, true))
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
''')
print('UI smoke checks passed')
