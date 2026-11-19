from pathlib import Path
import runpy
from lupa.lua51 import LuaRuntime

source = (Path(__file__).resolve().parents[1] / 'GroupFinderUI.lua').read_text(encoding='utf-8')
marker = 'local OFFLINE_APPLICATION_TTL = 300'
block = source.split(marker, 1)[1].split('refreshPeople = function()', 1)[0]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
local now=1000
local GetTime=function() return now end
local refresh=function() end
local Finder={identity='Me Realm',groups={},pending={},pendingVersions={},pendingRoles={},Changed=function() end}
''' + marker + block + r'''
local key='Other Realm\001g'
local group={owner='Other Realm',id='g',closed=false}
Finder.groups[key]=group; guildRosterLoaded=true; people={['Other Realm']={online=false}}
pruneOfflineApplications(); assert(ownerOfflineSince[key]==1000 and not isGroupHiddenByOfflineOwner(key,group))
now=1299; pruneOfflineApplications(); assert(not isGroupHiddenByOfflineOwner(key,group))
now=1300; pruneOfflineApplications(); assert(isGroupHiddenByOfflineOwner(key,group) and Finder.groups[key]==group)
people={}; pruneOfflineApplications(); assert(ownerOfflineSince[key]==nil and not isGroupHiddenByOfflineOwner(key,group))
people={['Other Realm']={online=false}}; pruneOfflineApplications(); assert(ownerOfflineSince[key]==1300)
guildRosterLoaded=false; pruneOfflineApplications(); assert(ownerOfflineSince[key]==nil)
guildRosterLoaded=true; people={['Other Realm']={online=false}}; pruneOfflineApplications()
now=1500; people={['Other Realm']={online=true}}; pruneOfflineApplications()
assert(ownerOfflineSince[key]==nil and not isGroupHiddenByOfflineOwner(key,group))
people={['Other Realm']={online=false}}; Finder.pending[key]='closed'; group.closed=true
pruneOfflineApplications(); assert(ownerOfflineSince[key]==1500)
now=1800; pruneOfflineApplications(); assert(Finder.pending[key]==nil and ownerOfflineSince[key]==nil)
-- A missing group does not prevent an offline owner's application expiring.
Finder.groups[key]=nil; Finder.pending[key]='reject'; Finder.pendingVersions[key]=2; Finder.pendingRoles[key]='dps'
now=2000; pruneOfflineApplications(); assert(ownerOfflineSince[key]==2000 and Finder.pending[key]=='reject')
now=2299; pruneOfflineApplications(); assert(Finder.pending[key]=='reject')
now=2300; pruneOfflineApplications()
assert(Finder.pending[key]==nil and Finder.pendingVersions[key]==nil and Finder.pendingRoles[key]==nil and ownerOfflineSince[key]==nil)
Finder.pending[key]='pending'; now=2400; pruneOfflineApplications(); people={}; now=2500; pruneOfflineApplications()
assert(Finder.pending[key]=='pending' and ownerOfflineSince[key]==nil)
Finder.groups[key]=42; people={['Other Realm']={online=false}}
now=2600; pruneOfflineApplications(); now=2900; pruneOfflineApplications()
assert(Finder.pending[key]==nil and ownerOfflineSince[key]==nil)
''')
print('Phase 1 offline checks passed')

# Exercise the actual cards and tab filter, not only the extracted timer helper.
root = Path(__file__).resolve().parents[1]
ui = runpy.run_path(str(root / 'tests/test_ui_smoke.py'))['lua']
ui.execute(r'''
local finder=OldKraken.GroupFinder
local now=2000; local online=false
GetTime=function() return now end
GetNumGuildMembers=function() return 1 end
GetGuildRosterInfo=function() return 'Remote-Realm',nil,nil,60,nil,nil,nil,nil,online,nil,'WARRIOR' end
local key='Remote Realm\001remote'
local group={id='remote',owner='Remote Realm',title='!Offline test',category='quest',dungeon='',
    role='dps',maxSize=5,minLevel=1,maxLevel=60,description='',members={'Remote Realm'},closed=false,seenAt=2000}
finder.groups[key]=group
finder:Show(); local window=OldKrakenGroupFinderFrame
window.tabBar.tabs.all.scripts.OnClick()
local function visible()
    for _,entry in ipairs(window.visible) do if entry.key==key then return true end end
    return false
end
assert(visible())
local badge
local card
for _,row in ipairs(window.rows) do if row.entry and row.entry.key==key then badge=row.statusPill; card=row end end
assert(badge and badge.kind=='warning' and badge.label.text=='Офлайн')
assert(card); card.scripts.OnClick(card)
assert(window.detailsHeading:IsShown() and window.applyButton:IsShown())
now=2299; finder:Show(); assert(visible() and window.detailsHeading:IsShown() and window.applyButton:IsShown())
now=2300; finder:Show(); assert(not visible() and finder.groups[key]==group)
assert(not window.detailsHeading:IsShown() and not window.applyButton:IsShown())
-- A missing online field is unknown, not a confirmed offline record.
online=nil; finder:Show(); assert(visible())
now=2601; finder:Show(); assert(visible())
online=false; finder:Show(); assert(visible())
finder.pending[key]='reject'; window.tabBar.tabs.applications.scripts.OnClick()
card=nil
for _,row in ipairs(window.rows) do if row.entry and row.entry.key==key then card=row; break end end
assert(card); card.scripts.OnClick(card); assert(window.detailsHeading:IsShown())
finder.pending[key]=nil; window.tabBar.tabs.all.scripts.OnClick()
card=nil
for _,row in ipairs(window.rows) do if row.entry and row.entry.key==key then card=row; break end end
assert(card); card.scripts.OnClick(card); assert(window.applyButton:IsShown())
now=2901; window.applyButton.scripts.OnClick()
assert(not visible() and not window.applyButton:IsShown() and finder.pending[key]==nil)
-- A roster transition must reset an existing timer while the window is hidden.
local rosterEvents
for _,frame in ipairs(createdFrames) do
    if rawget(frame,'events') and frame.events.GUILD_ROSTER_UPDATE and frame.events.GROUP_ROSTER_UPDATE
        and frame.scripts and frame.scripts.OnEvent then rosterEvents=frame; break end
end
assert(rosterEvents)
window:Hide(); now=2902; online=true; rosterEvents.scripts.OnEvent(rosterEvents,'GUILD_ROSTER_UPDATE')
now=2903; online=false; rosterEvents.scripts.OnEvent(rosterEvents,'GUILD_ROSTER_UPDATE')
now=2904; finder:Show(); assert(visible())
now=3203; finder:Show(); assert(not visible())
online=true; finder:Show(); assert(visible())
-- A party unit with an unavailable connection API must not override a
-- confirmed offline guild record with an invented online state.
local originalUnitName, originalUnitClass, originalUnitLevel, originalConnected = UnitName, UnitClass, UnitLevel, UnitIsConnected
UnitName=function(unit) if unit=='party1' then return 'Remote','Realm' end end
UnitClass=function() return 'Warrior','WARRIOR' end
UnitLevel=function() return 60 end
UnitIsConnected=function() return nil end
online=false; finder:Show()
badge=nil
for _,row in ipairs(window.rows) do if row.entry and row.entry.key==key then badge=row.statusPill end end
assert(badge and badge.label.text=='Офлайн')
online=true; finder:Show()
for _,row in ipairs(window.rows) do if row.entry and row.entry.key==key then badge=row.statusPill end end
assert(badge.label.text=='Відкрито')
online=nil; finder:Show()
for _,row in ipairs(window.rows) do if row.entry and row.entry.key==key then badge=row.statusPill end end
assert(badge.label.text=='Відкрито')
online=false; UnitIsConnected=function() return true end; finder:Show()
for _,row in ipairs(window.rows) do if row.entry and row.entry.key==key then badge=row.statusPill end end
assert(badge.label.text=='Відкрито')
group.owner='Remote-Realm'; finder:Show()
for _,row in ipairs(window.rows) do if row.entry and row.entry.key==key then badge=row.statusPill end end
assert(badge.label.text=='Відкрито')
group.owner='Remote Realm'
UnitName=function(unit) if unit=='party1' then return 'Remote','Realm2' end end
finder:Show()
for _,row in ipairs(window.rows) do if row.entry and row.entry.key==key then badge=row.statusPill end end
assert(badge.label.text=='Офлайн')
UnitName,UnitClass,UnitLevel,UnitIsConnected=originalUnitName,originalUnitClass,originalUnitLevel,originalConnected
for _,entry in pairs(finder.groups) do if not entry.seenAt then entry.seenAt=now end end
now=5601; finder:Prune(); assert(finder.groups[key]==nil)
-- A listing arriving while the page is hidden starts its grace period without
-- waiting for the user to open the page or another guild roster event.
now=6000; online=false; window:Hide()
local newKey='Remote Realm\001new'
local newGroup={id='new',owner='Remote Realm',title='!New listing',category='quest',dungeon='',
    role='dps',maxSize=5,minLevel=1,maxLevel=60,description='',members={'Remote Realm'},closed=false,seenAt=now}
finder.groups[newKey]=newGroup
local timers={}
C_Timer={After=function(delay,fn) timers[#timers+1]={delay=delay,fn=fn} end}
for i=1,200 do OldKraken.listeners.GROUP_FINDER_CHANGED(newGroup) end
assert(#timers==1 and timers[1].delay==0)
table.remove(timers,1).fn()
now=6300; finder:Show()
for _,entry in ipairs(window.visible) do assert(entry.key~=newKey) end
assert(finder.groups[newKey]==newGroup)
''')
print('Phase 1 offline card checks passed')
