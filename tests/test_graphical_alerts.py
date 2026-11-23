from pathlib import Path
import runpy

ROOT=Path(__file__).resolve().parents[1]
lua=runpy.run_path(str(ROOT/'tests/test_ui_smoke.py'))['lua']
lua.execute('''
local finder=OldKraken.GroupFinder
local alert
for _,frame in ipairs(createdFrames) do if rawget(frame,'alertCaption') then alert=frame end end
assert(alert)
local meta=getmetatable(alert); local old=meta.__index
meta.__index=function(self,key)
    if key=='GetScript' then return function(frame,event) return frame.scripts[event] end end
    return old(self,key)
end
local group={id='graphics',owner='Tank Owner',title='Graphical group',category='dungeon',dungeon='rfc',role='tank',maxSize=5,minLevel=13,maxLevel=18,description='',members={'Tank Owner','Healer Friend'},memberRoles={['Healer Friend']='healer'},partyObserved={['Healer Friend']=true}}
finder.groups[group.owner..'\\001'..group.id]=group
OldKraken.listeners.GROUP_FINDER_NEW(group)
assert(alert.height==204 and #alert.roleSlots==5)
local occupied=0
for i,slot in ipairs(alert.roleSlots) do
    assert(slot:IsShown())
    if slot.occupied then occupied=occupied+1 end
    assert(slot.ring.texture:find('RoleSlot.tga',1,true))
end
assert(occupied==2)
assert(alert.roleSlots[1].role=='tank' and alert.roleSlots[1].memberName=='Tank Owner')
assert(alert.roleSlots[2].role=='healer' and alert.roleSlots[2].memberName=='Healer Friend')
assert(alert.roleSlots[3].role=='dps' and not alert.roleSlots[3].occupied)
assert(alert.alertSubtitle.text:find('У складі: 2 із 5',1,true))
assert(not alert.alertSubtitle.text:find('Вільні ролі',1,true))
GameTooltip={SetOwner=function() end,SetText=function(_,text,...) assert(select('#',...)==0); tooltip=text end,Show=function() end,Hide=function() end}
alert.roleSlots[2].scripts.OnEnter(alert.roleSlots[2]); assert(tooltip:find('Healer Friend',1,true))
local before=#createdFrames
for i=1,30 do OldKraken.listeners.GROUP_FINDER_NEW(group) end
assert(#createdFrames==before,'notification slots must be reused')
alert.roleSlots[1].scripts.OnClick(nil,'LeftButton')
assert(not alert:IsShown() and OldKraken.UIHub.currentPage=='groups')
OldKraken.listeners.GROUP_FINDER_NEW(group)
alert.roleSlots[1].scripts.OnClick(nil,'RightButton'); assert(not alert:IsShown())
group.members={'Tank Owner','Unknown Role'}; group.memberRoles={}
OldKraken.listeners.GROUP_FINDER_NEW(group)
assert(alert.roleSlots[5].role=='' and alert.roleSlots[5].memberName=='Unknown Role')
assert(alert.roleSlots[5].icon.texture:find('QuestionMark',1,true),'must not invent a role')
OldKraken.listeners.GROUP_FINDER_NEW_REQUEST(group,'Applicant','healer')
assert(alert.width==480 and alert.height==112 and alert.alertChrome:IsShown() and alert.alertFooter.height==26)
assert(alert.alertArt:IsShown() and alert.alertArt.width==52 and alert.alertArt.height==52)
for _,slot in ipairs(alert.roleSlots) do assert(not slot:IsShown()) end
OldKraken.listeners.GUILD_EVENTS_NEW_SIGNUP('e1',{owner='Owner',title='MC',activity='mc',size=10,statuses={Owner='accepted',Person='accepted'}},'Person','dps')
assert(alert.alertSubtitle.text:find('(2/10)',1,true),'event_signup must show participant count')
assert(alert.alertArt.texture~=nil and alert.alertArt.texture~='OldKrakenEmblem.tga','event_signup must show activity art')
finder:PreviewAlert('group'); assert(alert.roleSlots[1]:IsShown() and alert.height==204)
group.category='raid'; group.maxSize=200; group.members={'Tank Owner'}
for i=2,200 do group.members[i]='Raider '..i end
OldKraken.listeners.GROUP_FINDER_NEW(group)
assert(#alert.roleSlots==5 and alert.alertSubtitle.text:find('195',1,true))
''')
data=(ROOT/'Media/RoleSlot.tga').read_bytes()
assert len(data)==18+64*64*4 and data[2]==2 and data[16]==32
for name in ['package-alpha.yml','package-release.yml']:
    assert 'Media/RoleSlot.tga' in (ROOT/'.github/workflows'/name).read_text()
print('PASS: graphical five-role notification slots, member labels, vacancies, unknown roles, tooltips, clicks, reuse, generic groups and packaged circle texture')
