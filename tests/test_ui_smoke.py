from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
OldKraken = {listeners = {}}; UIParent = {GetWidth=function() return 0 end}; StaticPopupDialogs = {}; UISpecialFrames = {}
OldKraken.UIStyle = {
    Window = function() end,
    Button = function() end,
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
function print(...) end
function GetServerTime() return 12345 end
function GetTime() return 1 end
local methods = {}
function methods:SetText(v) self.text = v end
function methods:GetText() return self.text or '' end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetShown(value) self.shown = value end
function methods:IsShown() return self.shown end
function methods:GetStringHeight() return 0 end
function methods:SetScript(name, fn) self.scripts[name] = fn end
function methods:CreateFontString() return CreateFrame() end
function methods:CreateTexture() return CreateFrame() end
local meta = {__index=function(_, k) if k == 'TitleText' then return nil end; return methods[k] or function() end end}
function CreateFrame(_, name)
    local frame = setmetatable({scripts={}}, meta)
    if name then _G[name] = frame end
    return frame
end
''')
for name in ['GroupFinder.lua', 'GroupFinderUI.lua']:
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
addGroup('Other dungeon', 'dungeon', 'wc', 'tank', 5, 20, 30)
addGroup('Higher level dungeon', 'dungeon', 'rfc', 'tank', 5, 40, 50)
addGroup('Full quest', 'quest', '', 'dps', 1, 20, 30)
f:Show()
assert(OldKraken.listeners.GROUP_FINDER_CHANGED)
OldKraken.listeners.GROUP_FINDER_CHANGED()

local ui = OldKrakenGroupFinderFrame
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
selectTab('mine'); filtersShown(false)
selectTab('applications'); filtersShown(false)
selectTab('create'); filtersShown(false)
selectTab('all'); filtersShown(true)

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

selectTab('create')
ui.titleBox:SetText('Created from form')
ui.descriptionBox:SetText('Fresh listing')
ui.maxBox:SetText('5')
ui.minBox:SetText('20')
ui.maxLevelBox:SetText('30')
selectDropdown(ui.dungeonButton, 'rfc')
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
''')
print('UI smoke checks passed')
