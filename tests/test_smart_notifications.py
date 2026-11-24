from pathlib import Path
import runpy

ROOT = Path(__file__).resolve().parents[1]
lua = runpy.run_path(str(ROOT / 'tests/test_ui_smoke.py'))['lua']
lua.execute((ROOT / 'Database.lua').read_text(encoding='utf-8'))
lua.execute((ROOT / 'Locale.lua').read_text(encoding='utf-8'))
lua.execute("local prevPages = OldKraken.UIHub.pages; _G.__savedPages = prevPages")
lua.execute((ROOT / 'UIHub.lua').read_text(encoding='utf-8'))
lua.execute("for k, v in pairs(_G.__savedPages or {}) do if not OldKraken.UIHub.pages[k] then OldKraken.UIHub.pages[k] = v end end")
lua.execute("if OldKraken.listeners and OldKraken.listeners.INITIALIZED then OldKraken.listeners.INITIALIZED() end")

lua.execute('''
local finder = OldKraken.GroupFinder

local function findAlert()
    for _, frame in ipairs(createdFrames) do
        if rawget(frame, 'alertCaption') then return frame end
    end
    return nil
end

local function fireCombatEnd()
    for _, frame in ipairs(createdFrames) do
        if type(frame) == 'table' and type(frame.scripts) == 'table' and type(frame.scripts.OnEvent) == 'function' then
            pcall(frame.scripts.OnEvent, frame, 'PLAYER_REGEN_ENABLED')
        end
    end
end

-- Helper to capture print() and PlaySound()
local chatLogs = {}
local origPrint = print
print = function(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    chatLogs[#chatLogs + 1] = table.concat(parts, ' ')
end

local soundPlays = 0
local fakeNow = 1000
GetTime = function() return fakeNow end
SOUNDKIT = { READY_CHECK = 8960 }
PlaySound = function() soundPlays = soundPlays + 1 end

local function resetMocks()
    chatLogs = {}
    soundPlays = 0
    fakeNow = fakeNow + 100
    InCombatLockdown = function() return false end
    IsInInstance = function() return false, 'none' end
    local alert = findAlert()
    if alert then alert:Hide() end
end

-- 1. Settings: default smartNotifications = true, existing profile backfill, UIHub toggle
OldKrakenDB = {}
OldKraken.Database.Initialize()
assert(OldKraken.DB.settings.smartNotifications == true, 'default smartNotifications must be true')
local legacyDb = { schemaVersion = 3, settings = { language = 'ukUA' }, roster = {}, events = {}, groupFinder = {}, workshop = {} }
OldKrakenDB = legacyDb
OldKraken.Database.Initialize()
assert(legacyDb.settings.smartNotifications == true, 'existing profile must receive smartNotifications = true')

-- Test initial UI state when smartNotifications = false before opening settings
OldKraken.DB.settings.smartNotifications = false
OldKraken.UIHub.pages.settings.frame = nil
OldKraken.UIHub:ShowPage('settings')
local settingsPage = OldKraken.UIHub.pages.settings.frame
local smartBtn
for _, frame in ipairs(createdFrames) do
    if frame.parent == settingsPage and type(frame.text) == 'string' and frame.text:find('Розумні сповіщення', 1, true) then
        smartBtn = frame
        break
    end
end
assert(smartBtn, 'UIHub settings page must contain Smart Notifications toggle button')
assert(smartBtn.text == 'Розумні сповіщення: |cff9aa5b1вимк.|r', 'initial button text must reflect saved false state without clicking, got: ' .. tostring(smartBtn.text))

-- Set back to true and re-open/refresh settings page lifecycle
OldKraken.DB.settings.smartNotifications = true
OldKraken.UIHub:ShowPage('groups')
OldKraken.UIHub:ShowPage('settings')
if settingsPage.scripts and settingsPage.scripts.OnShow then settingsPage.scripts.OnShow(settingsPage) end
assert(smartBtn.text == 'Розумні сповіщення: |cff69dc8cувімк.|r', 're-opening settings must reflect true state')

-- Clicking toggles both directions
smartBtn.scripts.OnClick(smartBtn)
assert(OldKraken.DB.settings.smartNotifications == false, 'clicking UIHub toggle must disable smartNotifications')
assert(smartBtn.text == 'Розумні сповіщення: |cff9aa5b1вимк.|r')
smartBtn.scripts.OnClick(smartBtn)
assert(OldKraken.DB.settings.smartNotifications == true, 'clicking UIHub toggle again must re-enable smartNotifications')
assert(smartBtn.text == 'Розумні сповіщення: |cff69dc8cувімк.|r')

-- Prepare own and foreign groups
finder.identity = 'Leader Mon'
local ownGroup1 = {
    id = 'g1', owner = 'Leader Mon', title = 'Own RFC', category = 'dungeon', dungeon = 'rfc',
    role = 'tank', maxSize = 5, minLevel = 13, maxLevel = 18, description = '',
    members = {'Leader Mon'}, memberRoles = {}, closed = false,
}
local ownGroup2 = {
    id = 'g2', owner = 'Leader Mon', title = 'Own WC', category = 'dungeon', dungeon = 'wc',
    role = 'tank', maxSize = 5, minLevel = 15, maxLevel = 22, description = '',
    members = {'Leader Mon'}, memberRoles = {}, closed = false,
}
local otherGroup = {
    id = 'g3', owner = 'Other Owner', title = 'Other Group', category = 'dungeon', dungeon = 'rfc',
    role = 'tank', maxSize = 5, minLevel = 13, maxLevel = 18, description = '',
    members = {'Other Owner'}, memberRoles = {}, closed = false,
}
local gk1 = ownGroup1.owner .. '\\001' .. ownGroup1.id
local gk2 = ownGroup2.owner .. '\\001' .. ownGroup2.id
local gk3 = otherGroup.owner .. '\\001' .. otherGroup.id
finder.groups[gk1] = ownGroup1
finder.groups[gk2] = ownGroup2
finder.groups[gk3] = otherGroup
finder.requests["g1"] = {}
finder.requests["g2"] = {}

-- Ensure player level matches dungeon level filter
UnitLevel = function() return 15 end

-- 2. Open world out of combat: background events show banner and sound without redundant chat log
resetMocks()
OldKraken.listeners.GROUP_FINDER_NEW(otherGroup)
local alert = findAlert()
assert(alert and alert:IsShown(), 'open world out of combat must show background group banner')
assert(soundPlays == 1 and #chatLogs == 0)

-- 3. Party and Raid out of combat: background events muted (no banner, no sound); decision/workshop/event/event_signup log to chat, group does not; request shown normally
for _, instType in ipairs({'party', 'raid'}) do
    resetMocks()
    IsInInstance = function() return true, instType end
    OldKraken.listeners.GROUP_FINDER_NEW(otherGroup)
    assert(not alert:IsShown(), instType .. ' out of combat must suppress group banner')
    assert(soundPlays == 0, instType .. ' out of combat must suppress sound')
    assert(#chatLogs == 0, instType .. ' out of combat must not log group banner to chat')

    OldKraken.listeners.GROUP_FINDER_APPLICATION_STATUS(otherGroup, 'reject')
    assert(not alert:IsShown() and soundPlays == 0 and #chatLogs == 1, instType .. ' must suppress decision banner and log to chat')

    OldKraken.listeners.WORKSHOP_ORDER_NOTICE('Замовлення', 'Тест', 'ord1')
    assert(not alert:IsShown() and soundPlays == 0 and #chatLogs == 2, instType .. ' must suppress workshop banner and log to chat')

    OldKraken.listeners.GUILD_EVENTS_NEW('ev1', {owner = 'Org', title = 'Raid', when = 1700000000})
    assert(not alert:IsShown() and soundPlays == 0 and #chatLogs == 3, instType .. ' must suppress event banner and log to chat')

    OldKraken.listeners.GUILD_EVENTS_NEW_SIGNUP('ev1', {owner = 'Org', title = 'Raid'}, 'Player', 'dps')
    assert(not alert:IsShown() and soundPlays == 0 and #chatLogs == 4, instType .. ' must suppress event_signup banner and log to chat')

    -- Request in party/raid out of combat must still show normally without redundant chat log
    fakeNow = fakeNow + 100
    OldKraken.listeners.GROUP_FINDER_NEW_REQUEST(ownGroup1, 'Helper', 'healer')
    assert(alert:IsShown() and soundPlays == 1 and #chatLogs == 4,
        instType .. ' out of combat must show request banner: shown=' .. tostring(alert:IsShown()) .. ' sound=' .. tostring(soundPlays) .. ' logs=' .. tostring(#chatLogs))
end

-- 4. PvP and Arena out of combat: instance filter must NOT suppress background banners
for _, instType in ipairs({'pvp', 'arena'}) do
    resetMocks()
    IsInInstance = function() return true, instType end
    OldKraken.listeners.GROUP_FINDER_NEW(otherGroup)
    assert(alert:IsShown() and soundPlays == 1 and #chatLogs == 0, instType .. ' out of combat must NOT suppress background banner')
end

-- 5. IsInInstance pcall error / nil / invalid return must NOT activate suppression
for _, badFn in ipairs({
    function() error('api error') end,
    function() return nil, 'party' end,
    function() return true, nil end,
    function() return 'yes', 'raid' end,
    function() return true, 'unknown_zone' end,
}) do
    resetMocks()
    IsInInstance = badFn
    OldKraken.listeners.GROUP_FINDER_NEW(otherGroup)
    assert(alert:IsShown() and soundPlays == 1, 'invalid/error IsInInstance must not suppress banner')
end

-- 6. Combat suppresses all banners & sounds (including request and Preview), preserves chat for decision/workshop/event/event_signup only
resetMocks()
InCombatLockdown = function() return true end
OldKraken.listeners.GROUP_FINDER_NEW(otherGroup)
assert(not alert:IsShown() and soundPlays == 0 and #chatLogs == 0)
finder:PreviewAlert('group')
assert(not alert:IsShown() and soundPlays == 0 and #chatLogs == 0, 'Preview during combat must NOT show banner or sound')
OldKraken.listeners.GROUP_FINDER_APPLICATION_STATUS(otherGroup, 'reject')
assert(not alert:IsShown() and soundPlays == 0 and #chatLogs == 1, 'decision during combat must log to chat')
fireCombatEnd()
assert(not alert:IsShown() and soundPlays == 0, 'background/preview events must NOT be deferred after combat')

-- 7. PreviewAlert in open world and party/raid out of combat bypasses instance filter
for _, inst in ipairs({{false, 'none'}, {true, 'party'}, {true, 'raid'}}) do
    resetMocks()
    IsInInstance = function() return inst[1], inst[2] end
    finder:PreviewAlert('group')
    assert(alert:IsShown() and soundPlays == 1 and #chatLogs == 0, 'Preview out of combat must bypass instance filter: ' .. inst[2])
end

-- 8. Deferred requests during combat: single, multiple, multi-group, deduplicated re-apply, withdraw, accept/reject, closed/deleted group
-- 8a. Single request during combat -> 'Нові заявки: 1'
resetMocks()
InCombatLockdown = function() return true end
finder.requests["g1"]['App1'] = 'dps'
OldKraken.listeners.GROUP_FINDER_NEW_REQUEST(ownGroup1, 'App1', 'dps')
assert(not alert:IsShown() and soundPlays == 0 and #chatLogs == 0)
InCombatLockdown = function() return false end
fireCombatEnd()
assert(alert:IsShown() and soundPlays == 1, 'deferred single request must show after combat')
assert(alert.alertTitle.text == 'Нові заявки: 1', 'got: ' .. tostring(alert.alertTitle.text))
assert(alert.groupKey == gk1)

-- Duplicate PLAYER_REGEN_ENABLED must not re-fire
alert:Hide(); soundPlays = 0
fireCombatEnd()
assert(not alert:IsShown() and soundPlays == 0, 'duplicate PLAYER_REGEN_ENABLED must not duplicate banner')

-- 8b. Multiple applicants across two own groups + re-apply deduplication -> 'Нові заявки: 3' and deterministic lastGroupKey = gk2
resetMocks()
InCombatLockdown = function() return true end
finder.requests["g1"]['App1'] = 'dps'
OldKraken.listeners.GROUP_FINDER_NEW_REQUEST(ownGroup1, 'App1', 'dps')
finder.requests["g1"]['App1'] = nil -- withdraw
finder.requests["g1"]['App1'] = 'healer' -- re-apply
OldKraken.listeners.GROUP_FINDER_NEW_REQUEST(ownGroup1, 'App1', 'healer')
finder.requests["g1"]['App2'] = 'tank'
OldKraken.listeners.GROUP_FINDER_NEW_REQUEST(ownGroup1, 'App2', 'tank')
finder.requests["g2"]['App3'] = 'dps'
OldKraken.listeners.GROUP_FINDER_NEW_REQUEST(ownGroup2, 'App3', 'dps')
assert(not alert:IsShown() and soundPlays == 0)
InCombatLockdown = function() return false end
fireCombatEnd()
assert(alert:IsShown() and soundPlays == 1)
assert(alert.alertTitle.text == 'Нові заявки: 3', 'expected 3 unique applicants, got: ' .. tostring(alert.alertTitle.text))
assert(alert.groupKey == gk2, 'lastGroupKey must deterministically pick gk2')

-- 8c. Withdraw / accept / reject during combat -> excluded; if 0 remain, nothing shown
resetMocks()
InCombatLockdown = function() return true end
finder.requests["g1"]['AppWithdrawn'] = 'dps'
OldKraken.listeners.GROUP_FINDER_NEW_REQUEST(ownGroup1, 'AppWithdrawn', 'dps')
finder.requests["g1"]['AppHandled'] = 'healer'
OldKraken.listeners.GROUP_FINDER_NEW_REQUEST(ownGroup1, 'AppHandled', 'healer')
-- Simulate withdraw + accept/reject before combat ends
finder.requests["g1"]['AppWithdrawn'] = nil
finder.requests["g1"]['AppHandled'] = nil
InCombatLockdown = function() return false end
fireCombatEnd()
assert(not alert:IsShown() and soundPlays == 0, 'withdrawn/handled requests must not show after combat')

-- 8d. Group closed or deleted during combat -> excluded
resetMocks()
InCombatLockdown = function() return true end
finder.requests["g1"]['AppClosed'] = 'dps'
OldKraken.listeners.GROUP_FINDER_NEW_REQUEST(ownGroup1, 'AppClosed', 'dps')
ownGroup1.closed = true
finder.requests["g2"]['AppDeleted'] = 'healer'
OldKraken.listeners.GROUP_FINDER_NEW_REQUEST(ownGroup2, 'AppDeleted', 'healer')
finder.groups[gk2] = nil
InCombatLockdown = function() return false end
fireCombatEnd()
assert(not alert:IsShown() and soundPlays == 0, 'closed/deleted group requests must not show after combat')

-- Restore groups for navigation tests
ownGroup1.closed = false
finder.groups[gk2] = ownGroup2

-- 9. Navigation from aggregated banner click
local function findRequestsWindow()
    for _, frame in ipairs(createdFrames) do
        if type(frame) == 'table' and rawget(frame, 'entries') ~= nil and rawget(frame, 'count') ~= nil then
            return frame
        end
    end
    return nil
end

local function findGroupDetailTitle()
    local groupsPage = OldKraken.UIHub.pages.groups and OldKraken.UIHub.pages.groups.frame
    local heading = groupsPage and groupsPage.detailsHeading
    if heading and heading:IsShown() then return heading end
    return nil
end

-- 9a. Valid own open group with active request -> selects group and opens requestsWindow
finder.requests["g1"] = {}
finder.requests["g2"] = {}
resetMocks()
InCombatLockdown = function() return true end
finder.requests["g1"]['NavApp'] = 'dps'
OldKraken.listeners.GROUP_FINDER_NEW_REQUEST(ownGroup1, 'NavApp', 'dps')
InCombatLockdown = function() return false end
fireCombatEnd()
assert(alert:IsShown() and alert.groupKey == gk1)
alert.scripts.OnClick(alert, 'LeftButton')
assert(not alert:IsShown() and OldKraken.UIHub.currentPage == 'groups', 'clicking aggregated banner must open Group Finder')
local reqWin = findRequestsWindow()
assert(reqWin and reqWin:IsShown(), 'requests window must open for valid target group')
assert(#reqWin.entries >= 1 and reqWin.entries[1].name == 'NavApp' and reqWin.entries[1].id == 'g1' and reqWin.entries[1].selected == true,
    'requests window must display requests of selected group gk1')
assert(findGroupDetailTitle() and findGroupDetailTitle().text == 'Own RFC', 'valid group Own RFC must be selected in detail panel')

-- 9b. Closed group before click -> opens Group Finder without selecting closed group or opening requestsWindow
resetMocks()
InCombatLockdown = function() return true end
finder.requests["g1"]['ClosedClickApp'] = 'dps'
OldKraken.listeners.GROUP_FINDER_NEW_REQUEST(ownGroup1, 'ClosedClickApp', 'dps')
InCombatLockdown = function() return false end
fireCombatEnd()
assert(alert:IsShown() and alert.groupKey == gk1)
ownGroup1.closed = true
alert.scripts.OnClick(alert, 'LeftButton')
assert(not alert:IsShown() and OldKraken.UIHub.currentPage == 'groups')
assert(not reqWin:IsShown(), 'closed group must not open requests window')
assert(not findGroupDetailTitle(), 'closed group must not be selected')
ownGroup1.closed = false

-- 9c. Group with no active requests before click -> opens Group Finder without forced selection
resetMocks()
InCombatLockdown = function() return true end
finder.requests["g1"]['NoReqApp'] = 'dps'
OldKraken.listeners.GROUP_FINDER_NEW_REQUEST(ownGroup1, 'NoReqApp', 'dps')
InCombatLockdown = function() return false end
fireCombatEnd()
assert(alert:IsShown() and alert.groupKey == gk1)
finder.requests["g1"] = {}
alert.scripts.OnClick(alert, 'LeftButton')
assert(not alert:IsShown() and OldKraken.UIHub.currentPage == 'groups')
assert(not reqWin:IsShown(), 'group with no active requests must not open requests window')
assert(not findGroupDetailTitle(), 'group with no active requests must not be selected')

-- 9d. Deleted group before click -> opens Group Finder without forced selection
resetMocks()
InCombatLockdown = function() return true end
finder.requests["g2"]['GhostApp'] = 'dps'
OldKraken.listeners.GROUP_FINDER_NEW_REQUEST(ownGroup2, 'GhostApp', 'dps')
InCombatLockdown = function() return false end
fireCombatEnd()
assert(alert:IsShown() and alert.groupKey == gk2)
finder.groups[gk2] = nil
alert.scripts.OnClick(alert, 'LeftButton')
assert(not alert:IsShown() and OldKraken.UIHub.currentPage == 'groups', 'clicking banner after group vanished must open Group Finder cleanly')
assert(not reqWin:IsShown(), 'deleted group must not open requests window')
assert(not findGroupDetailTitle(), 'deleted group must not be selected')

-- 9e. Foreign owner group -> opens Group Finder without selecting foreign group
finder.requests["g3"] = { ForeignApp = 'dps' }
alert.kind = 'request'
alert.groupKey = gk3
alert:Show()
alert.scripts.OnClick(alert, 'LeftButton')
assert(not alert:IsShown() and OldKraken.UIHub.currentPage == 'groups')
assert(not reqWin:IsShown(), 'foreign owner group must not open requests window')
assert(not findGroupDetailTitle(), 'foreign owner group must not be selected')

-- 9f. Missing DB.settings treats smartNotifications as enabled (consistent with UIHub)
local savedSettings = OldKraken.DB.settings
OldKraken.DB.settings = nil
resetMocks()
IsInInstance = function() return true, 'party' end
OldKraken.listeners.GROUP_FINDER_NEW(otherGroup)
assert(not alert:IsShown() and soundPlays == 0, 'missing DB.settings must treat smartNotifications as enabled')
OldKraken.DB.settings = savedSettings

-- 10. Disabling smartNotifications = false restores old behavior completely
OldKraken.DB.settings.smartNotifications = false
resetMocks()
IsInInstance = function() return true, 'raid' end
InCombatLockdown = function() return true end
OldKraken.listeners.GROUP_FINDER_NEW(otherGroup)
assert(alert:IsShown() and soundPlays == 1, 'with smartNotifications=false, raid+combat must still show banner and sound')
finder.requests["g1"]['OldBehaviorApp'] = 'dps'
OldKraken.listeners.GROUP_FINDER_NEW_REQUEST(ownGroup1, 'OldBehaviorApp', 'dps')
assert(alert:IsShown() and alert.alertTitle.text:find('OldBehaviorApp', 1, true), 'with smartNotifications=false, request shows immediately even in combat')
alert:Hide(); soundPlays = 0
InCombatLockdown = function() return false end
fireCombatEnd()
assert(not alert:IsShown() and soundPlays == 0, 'with smartNotifications=false, no deferred aggregation runs after combat')

print = origPrint
''')

print('PASS: smart notifications (settings, instance/combat rules, preview, deferred request aggregation, navigation, disable fallback)')
