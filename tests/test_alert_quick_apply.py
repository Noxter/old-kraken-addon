from pathlib import Path
import runpy

root=Path(__file__).resolve().parents[1]
lua=runpy.run_path(str(root/'tests/test_graphical_alerts.py'))['lua']
lua.execute('''
local finder=OldKraken.GroupFinder
local alert
for _,frame in ipairs(createdFrames) do if rawget(frame,'alertCaption') then alert=frame end end
local group={id='quick-apply',owner='Other Tank',title='Quick apply',category='dungeon',dungeon='rfc',role='tank',maxSize=5,minLevel=13,maxLevel=18,description='',members={'Other Tank'},memberRoles={}}
local key=group.owner..'\\001'..group.id
finder.groups[key]=group
local opened=0
local originalShow=finder.Show
function finder:Show() opened=opened+1; return originalShow(self) end
OldKraken.listeners.GROUP_FINDER_NEW(group)
local healer=alert.roleSlots[2]
assert(healer.role=='healer' and not healer.occupied)
local sequence=finder.requestSequence
healer.scripts.OnClick(healer,'LeftButton')
assert(finder.pending[key]=='pending' and finder.pendingRoles[key]=='healer')
assert(finder.requestSequence>sequence and opened==0)
assert(alert:IsShown() and healer.label.text=='Заявку подано')
sequence=finder.requestSequence
alert.roleSlots[3].scripts.OnClick(alert.roleSlots[3],'LeftButton')
assert(finder.requestSequence==sequence and opened==0,'pending applications must not be duplicated')
finder.pending[key]=nil
group.members[2]='New healer'; group.memberRoles['New healer']='healer'
healer.scripts.OnClick(healer,'LeftButton')
assert(finder.pending[key]==nil and opened==0,'stale free slots must not bypass role availability')
group.closed=true
healer.scripts.OnClick(healer,'LeftButton'); assert(opened==0 and finder.pending[key]==nil)
group.closed=false
OldKraken.listeners.GROUP_FINDER_NEW(group)
alert.remaining=0.1; alert.alpha=0.1
function alert:IsMouseOver() return true end
alert.scripts.OnUpdate(alert,100)
assert(alert:IsShown() and alert.remaining==9 and alert.alpha==1,'hover must prevent expiry and restore opacity')
function alert:IsMouseOver() return false end
alert.scripts.OnUpdate(alert,8.5)
assert(alert:IsShown() and alert.alpha==0.5)
alert.scripts.OnUpdate(alert,0.5); assert(not alert:IsShown())
OldKraken.listeners.GROUP_FINDER_NEW(group)
local free=alert.roleSlots[3]
free.scripts.OnClick(free,'RightButton')
assert(not alert:IsShown() and opened==0,'right click dismisses without applying/opening')
''')
print('PASS: role-specific quick apply without navigation, duplicate/stale guards, hover pause/reset, fade after leaving and right-click dismissal')
