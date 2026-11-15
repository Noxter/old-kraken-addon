from pathlib import Path
import runpy

root=Path(__file__).resolve().parents[1]
lua=runpy.run_path(str(root/'tests/test_graphical_alerts.py'))['lua']
lua.execute('''
local finder=OldKraken.GroupFinder
local alert
for _,frame in ipairs(createdFrames) do if rawget(frame,'alertCaption') then alert=frame end end
local group={id='live',revision=1,owner='Live Tank',title='Live',category='dungeon',dungeon='rfc',role='tank',maxSize=5,minLevel=13,maxLevel=18,description='',members={'Live Tank'},memberRoles={}}
local key=group.owner..'\\001'..group.id
finder.groups[key]=group
OldKraken.listeners.GROUP_FINDER_NEW(group)
for _,control in ipairs(alert.roleSlots) do function control:SetEnabled(value) self.enabled=value end end
alert.remaining=4; alert.alpha=0.8
group.members[2]='Healer'; group.memberRoles.Healer='healer'; group.revision=2
OldKraken.listeners.GROUP_FINDER_CHANGED()
assert(alert.roleSlots[2].occupied and alert.roleSlots[2].memberName=='Healer' and not alert.roleSlots[2].enabled)
assert(alert.alertSubtitle.text:find('У складі: 2 із 5',1,true))
assert(alert.alertSubtitle.text:find('Вільних місць: 3',1,true))
assert(alert.remaining==4 and alert.alpha==0.8,'updates must not restart notification lifetime')
-- A stale DPS circle must not submit to another free DPS slot after its own slot fills.
local stale=alert.roleSlots[3]
group.members[3]='DPS One'; group.memberRoles['DPS One']='dps'; group.revision=3
local sequence=finder.requestSequence
stale.scripts.OnClick(stale,'LeftButton')
assert(finder.requestSequence==sequence and not finder.pending[key])
assert(stale.occupied and not stale.enabled)
-- Reopened slots become available immediately on the next authoritative update.
table.remove(group.members,2); group.memberRoles.Healer=nil; group.revision=4
OldKraken.listeners.GROUP_FINDER_CHANGED()
assert(not alert.roleSlots[2].occupied and alert.roleSlots[2].enabled)
-- New table instances received from peers update the same open notification.
local newer={}; for k,v in pairs(group) do newer[k]=v end
newer.members={'Live Tank','DPS One','DPS Two','DPS Three','Healer'}
newer.memberRoles={['DPS One']='dps',['DPS Two']='dps',['DPS Three']='dps',Healer='healer'}
newer.revision=5; finder.groups[key]=newer
OldKraken.listeners.GROUP_FINDER_CHANGED()
for _,control in ipairs(alert.roleSlots) do assert(control.occupied and not control.enabled) end
assert(alert.alertSubtitle.text:find('Вільних місць: 0',1,true))
local allocated=#createdFrames
for i=1,500 do OldKraken.listeners.GROUP_FINDER_CHANGED() end
assert(#createdFrames==allocated)
newer.closed=true; newer.revision=6
OldKraken.listeners.GROUP_FINDER_CHANGED(); assert(not alert:IsShown())
''')
print('PASS: immediate live composition, disabled occupied circles, exact-slot stale-click guard, reopened roles, full/closed groups, unchanged lifetime and bounded update allocation')
