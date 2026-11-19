from pathlib import Path
import ast
import runpy
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
SETUP = r"""
OldKraken={events=0,Fire=function(self) self.events=self.events+1 end}
now=100; guild='A'; player='Noxter'; surname='Moon'; specID=1485
secret={}
function issecretvalue(v) return v==secret end
function GetTime() return now end
function GetServerTime() return 12345 end
function GetGuildInfo() return guild end
function IsInGuild() return guild~='' end
function UnitName() return player,surname end
function GetRealmName() return 'Realm' end
function strsplit(_,s) return s:match('^([^%^]*)%^([^%^]*)%^([^%^]*)%^([^%^]*)$') end
frames={}
function CreateFrame()
 local f={events={},scripts={}}
 function f:RegisterEvent(e) self.events[e]=true end
 function f:SetScript(e,fn) self.scripts[e]=fn end
 frames[#frames+1]=f; return f
end
C_SpecializationInfo={GetSpecialization=function() return 1 end,GetSpecializationInfo=function() return specID end}
function GetSpecializationInfoByID(id) return id,'Hunter','',626000,'DAMAGER','HUNTER' end
C_ChatInfo={RegisterAddonMessagePrefix=function() return true end,SendAddonMessage=function() return 0 end}
function print() end
"""


def runtime(path='Communication.lua'):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(SETUP)
    lua.execute((ROOT / path).read_text(encoding='utf-8'))
    return lua


class CommunicationPhaseTwo(unittest.TestCase):
    def test_local_and_remote_specs(self):
        lua = runtime()
        lua.execute(r"""
local c=OldKraken.Communication
assert(c:GetLocalSpecID()==1485)
assert(c:GetRosterSpec('Noxter Moon').id==1485)
assert(c:GetRosterSpec('Noxter').id==1485)
assert(c:GetRosterSpec('')==nil and c:GetRosterSpec(secret)==nil)
assert(c:RecordRosterSpec('Other',1485))
local e=OldKraken.events
now=101; assert(c:RecordRosterSpec('Other',1485)); assert(OldKraken.events==e)
assert(c:RecordRosterSpec('Other',2)); assert(OldKraken.events==e+1)
assert(not c:RecordRosterSpec('',1))
for _,v in ipairs({0,-1,1.5,10000000,'1',secret}) do assert(not c:RecordRosterSpec('Other',v)) end
now=3701; assert(c:GetRosterSpec('Other').id==2)
now=3702; assert(c:GetRosterSpec('Other')==nil and next(c.rosterSpecs)==nil)
assert(c:GetRosterSpec('Noxter Moon').id==1485)
local api=C_SpecializationInfo
function GetNumTalentTabs() error('legacy fallback used') end
function GetSpecialization() error('legacy fallback used') end
for _,v in ipairs({0,-1,1.5,10000000,secret}) do specID=v; assert(c:GetLocalSpecID()==nil) end
specID=1485
C_SpecializationInfo=nil; assert(c:GetLocalSpecID()==nil)
C_SpecializationInfo={}; assert(c:GetLocalSpecID()==nil)
C_SpecializationInfo={GetSpecialization=function() return 1 end}; assert(c:GetLocalSpecID()==nil)
for _,v in ipairs({0,-1,1.5,'1',secret}) do
 C_SpecializationInfo={GetSpecialization=function() return v end,GetSpecializationInfo=api.GetSpecializationInfo}
 assert(c:GetLocalSpecID()==nil)
end
C_SpecializationInfo={GetSpecialization=function() return nil end,GetSpecializationInfo=api.GetSpecializationInfo}; assert(c:GetLocalSpecID()==nil)
C_SpecializationInfo={GetSpecialization=function() error('failure') end,GetSpecializationInfo=api.GetSpecializationInfo}; assert(c:GetLocalSpecID()==nil)
C_SpecializationInfo={GetSpecialization=function() return secret end,GetSpecializationInfo=api.GetSpecializationInfo}; assert(c:GetLocalSpecID()==nil)
C_SpecializationInfo={GetSpecialization=function() return 1 end,GetSpecializationInfo=function() error('failure') end}; assert(c:GetLocalSpecID()==nil)
C_SpecializationInfo=api
local globalByID=GetSpecializationInfoByID
GetSpecializationInfoByID=nil
C_SpecializationInfo.GetSpecializationInfoByID=function(id) return id,'Fallback','',7,'DAMAGER' end
assert(c:GetRosterSpec('Noxter').name=='Fallback')
GetSpecializationInfoByID=globalByID
function GetSpecializationInfoByID() return 1,'Hunter','',-1,'TANK' end
local s=c:GetRosterSpec('Noxter'); assert(s.name=='Hunter' and s.icon==nil and s.role=='TANK')
function GetSpecializationInfoByID() return 1,'Hunter','',secret,secret end
s=c:GetRosterSpec('Noxter'); assert(s and s.icon==nil and s.role==nil)
function GetSpecializationInfoByID() return 1,secret end
assert(c:GetRosterSpec('Noxter')==nil)
function GetSpecializationInfoByID() return 1,'' end
assert(c:GetRosterSpec('Noxter')==nil)
function GetSpecializationInfoByID() return 1,nil end
assert(c:GetRosterSpec('Noxter')==nil)
function GetSpecializationInfoByID() error('failure') end
assert(c:GetRosterSpec('Noxter')==nil)
player=secret; assert(c:GetRosterSpec('Noxter')==nil)
player=nil; assert(c:GetRosterSpec('Noxter')==nil)
player=''; assert(c:GetRosterSpec('Noxter')==nil)
""")

    def test_parser_and_guild_lifecycle(self):
        lua = runtime()
        lua.execute(r"""
local c=OldKraken.Communication; c.ready=true
for _,raw in ipairs({'','abc','-1','1.5','0','10000000','1485^extra','1485 '}) do
 c:OnAddonMessage(c.PREFIX,'OKP^SPEC^'..raw,'GUILD','Other'); assert(next(c.rosterSpecs)==nil)
end
for _,id in ipairs({1,1485,9999999}) do
 c:OnAddonMessage(c.PREFIX,'OKP^SPEC^'..id,'GUILD','Other'); assert(c:GetRosterSpec('Other').id==id)
end
c.pendingSpecBroadcast=true; c.pendingSpecForce=true; c.lastSpecReply=now; c.lastBroadcastSpecID=1
c.lastPresenceQuery=now; c.rosterVersions.Other='1'
guild='B'; c:Pump(); assert(not c.pendingSpecBroadcast and not c.pendingSpecForce and next(c.rosterSpecs)==nil)
assert(c.lastSpecReply==nil and c.lastBroadcastSpecID==nil and c.lastPresenceQuery==nil)
assert(next(c.rosterVersions)==nil and next(c.rosterPresence)==nil)
guild=''; local before=OldKraken.events
assert(not c:RecordRosterSpec('Other',1485) and next(c.rosterSpecs)==nil and OldKraken.events==before)
""")

    def test_pending_and_event_entry_points(self):
        lua = runtime()
        lua.execute(r"""
local c=OldKraken.Communication; c.ready=true; c:HasRosterAddon('Me')
assert(c:SendLocalSpec(false) and c.queue[1].message=='OKP^SPEC^1485')
c.queue={}; assert(not c:SendLocalSpec(false))
assert(not c:SendLocalSpec(true) and c.pendingSpecForce)
now=109; c:Pump(); assert(#c.queue==0)
now=110; c:Pump(); assert(c.lastBroadcastSpecID==1485 and c.lastSpecReply==110 and not c.pendingSpecBroadcast)
c.queue={}; specID=1486; now=111; assert(not c:SendLocalSpec(false) and c.pendingSpecBroadcast)
now=120; c:Pump(); assert(c.lastBroadcastSpecID==1486 and not c.pendingSpecBroadcast)
c.queue={}; now=130; for i=1,8 do c.queue[i]={message='dummy'} end
assert(c:SendLocalSpec(true) and #c.queue==9)
c.queue={}; now=140; for i=1,9 do c.queue[i]={message='dummy'} end
assert(not c:SendLocalSpec(true) and c.pendingSpecForce)
c.queue={}; specID=1487; c:Pump(); assert(c.lastBroadcastSpecID==1487)
c.queue={}; now=150; local old=c.QueueMessage
c.QueueMessage=function() return false end
assert(not c:SendLocalSpec(true) and c.pendingSpecBroadcast and c.lastBroadcastSpecID==1487 and c.lastSpecReply==140)
c.QueueMessage=old; c:Pump(); assert(c.lastSpecReply==150)
c.queue={}; now=151; assert(not c:SendLocalSpec(true) and c.pendingSpecForce)
guild='B'; c:Pump(); assert(not c.pendingSpecForce and #c.queue==0)
assert(c:SendLocalSpec(false) and c.lastBroadcastSpecID==1487)
local f=frames[1]; assert(f.events.ACTIVE_TALENT_GROUP_CHANGED and f.events.PLAYER_SPECIALIZATION_CHANGED)
c.queue={}; now=200; specID=1500; f.scripts.OnEvent(f,'PLAYER_SPECIALIZATION_CHANGED','target'); assert(#c.queue==0)
f.scripts.OnEvent(f,'PLAYER_SPECIALIZATION_CHANGED','player'); assert(c.lastBroadcastSpecID==1500)
now=210; specID=1501; f.scripts.OnEvent(f,'ACTIVE_TALENT_GROUP_CHANGED'); assert(c.lastBroadcastSpecID==1501)
now=220; c:OnAddonMessage(c.PREFIX,'OKP^QUERY','GUILD','Other'); assert(c.lastSpecReply==220)
local calls={}; local req,send=c.RequestRosterPresence,c.SendLocalSpec
c.RequestRosterPresence=function() calls[#calls+1]='query' end
c.SendLocalSpec=function(_,force) assert(force); calls[#calls+1]='spec' end
f.scripts.OnEvent(f,'PLAYER_LOGIN'); assert(calls[1]=='query' and calls[2]=='spec')
c.RequestRosterPresence,c.SendLocalSpec=req,send
""")

    def test_pending_force_survives_normal_call(self):
        lua = runtime()
        lua.execute(r"""
local c=OldKraken.Communication; c.ready=true; c:HasRosterAddon('Me')
local sent={}
local sendFn=C_ChatInfo.SendAddonMessage
C_ChatInfo.SendAddonMessage=function(_,msg) sent[#sent+1]=msg; return 0 end
c.lastBroadcastSpecID=1485; c.lastSpecReply=95; now=100
assert(not c:SendLocalSpec(true))
assert(c.pendingSpecBroadcast and c.pendingSpecForce and #c.queue==0 and #sent==0)
now=102; assert(not c:SendLocalSpec(false))
assert(c.pendingSpecBroadcast and c.pendingSpecForce and #c.queue==0 and #sent==0)
now=105; c:Pump()
assert(#sent==1 and sent[1]=='OKP^SPEC^1485')
assert(not c.pendingSpecBroadcast and not c.pendingSpecForce and c.lastSpecReply==105)
C_ChatInfo.SendAddonMessage=sendFn
""")

    def test_login_keeps_presence_throttle(self):
        lua = runtime()
        lua.execute(r"""
local c=OldKraken.Communication; local f=frames[1]
f.scripts.OnEvent(f,'PLAYER_LOGIN')
assert(c.lastPresenceQuery==100 and c.lastSpecReply==100 and #c.queue==2)
c:RequestRosterPresence(); assert(#c.queue==2)
""")

    def test_unsupported_events_are_guarded(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(SETUP)
        lua.execute(r"""
local original=CreateFrame
function CreateFrame()
 local f=original(); local register=f.RegisterEvent
 f.RegisterEvent=function(self,event)
  if event=='ACTIVE_TALENT_GROUP_CHANGED' or event=='PLAYER_SPECIALIZATION_CHANGED' then error('unsupported') end
  return register(self,event)
 end
 return f
end
""")
        lua.execute((ROOT / 'Communication.lua').read_text(encoding='utf-8'))
        lua.execute("assert(frames[1].events.PLAYER_LOGIN and frames[1].events.CHAT_MSG_ADDON)")

    def test_release_053_accepts_spec_message(self):
        lua = runtime('tests/fixtures/communication_0_5_3.lua')
        lua.execute(r"""
local c=OldKraken.Communication; local before=c.stats.invalid
c:OnAddonMessage(c.PREFIX,'OKP^SPEC^1485','GUILD','Other')
assert(c.stats.invalid==before and c:HasRosterAddon('Other'))
""")


class RosterPhaseTwo(unittest.TestCase):
    def test_zone_sort_order(self):
        source = (ROOT / 'GuildRoster.lua').read_text(encoding='utf-8')
        function = source.split('local function SortMembers(a, b)', 1)[1].split('local function CreateColumnHeader', 1)[0]
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute("settings={sort='zone',ascending=true}; local function SortMembers(a,b)" + function + r"""
local function d(n) return {years=0,months=0,days=n,hours=0} end
local entries={
 {name='Zulu',zone='B',lastOnline=nil,isOnline=false},
 {name='Joe',zone='B',lastOnline=d(1),isOnline=false},
 {name='Ann',zone='B',lastOnline=d(1),isOnline=false},
 {name='Carl',zone='A',lastOnline=d(1),isOnline=false},
 {name='Bob',zone='A',lastOnline=d(2),isOnline=false},
 {name='Online',zone='Z',isOnline=true}}
table.sort(entries,SortMembers)
assert(entries[1].name=='Online' and entries[2].name=='Carl' and entries[3].name=='Ann' and entries[4].name=='Joe' and entries[5].name=='Bob' and entries[6].name=='Zulu')
settings.ascending=false; table.sort(entries,SortMembers)
assert(entries[1].name=='Online' and entries[2].name=='Bob' and entries[3].name=='Ann' and entries[4].name=='Joe' and entries[5].name=='Carl' and entries[6].name=='Zulu')
""")

    def test_offline_data_sort_and_row_reuse(self):
        tree = ast.parse((ROOT / 'tests/test_roster_invite.py').read_text(encoding='utf-8'))
        setup = next(ast.literal_eval(node.value) for node in tree.body
                     if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'setup' for t in node.targets))
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(setup)
        lua.execute(r"""
local probe=CreateFrame(); local meta=getmetatable(probe); local old=meta.__index
meta.__index=function(self,key)
 if key=='SetTexture' then return function(o,v) o.texture=v end end
 if key=='SetPoint' then return function(o,...) o.point={...} end end
 if key=='SetWidth' then return function(o,v) o.width=v end end
 return old(self,key)
end
secret={}; function issecretvalue(v) return v==secret end
calls={}; mode='one'; icon=123; specName='Hunter'
function GetNumGuildMembers() return 2 end
function GetGuildRosterInfo(i)
 if i==1 then return 'Online','Rank',1,60,'Warrior','Online Zone',nil,nil,true,'','WARRIOR' end
 return 'Offline','Rank',1,60,'Hunter','Offline Zone',nil,nil,false,'','HUNTER'
end
function GetGuildRosterLastOnline(i)
 calls[i]=(calls[i] or 0)+1
 if mode=='one' then return 0
 elseif mode=='partial' then return 0,nil,nil,nil
 elseif mode=='partial_nonzero' then return 1,nil,nil,nil
 elseif mode=='short' then return 1,2
 elseif mode=='zeros' then return 0,0,0,0
 elseif mode=='many' then return 2,3,4,5
 elseif mode=='secret' then return 0,secret,0,0
 elseif mode=='error' then error('bad')
 elseif mode=='negative' then return 0,0,-1,0
 elseif mode=='fraction' then return 0,0,0,1.5
 elseif mode=='text' then return 0,0,'3',0 end
end
OldKraken.Communication={RequestRosterPresence=function() end,HasRosterAddon=function() return false end,
 GetRosterSpec=function() return specName and {name=specName,icon=icon} end}
""")
        lua.execute((ROOT / 'Locale.lua').read_text(encoding='utf-8'))
        lua.execute("OldKraken.InitializeLocale({settings={language='ukUA'}})")
        lua.execute((ROOT / 'GuildRoster.lua').read_text(encoding='utf-8'))
        lua.execute(r"""
OldKraken.GuildRoster:Show()
local row
for _,f in ipairs(createdFrames) do if type(f.member)=='table' and f.member.name=='Offline' then row=f end end
assert(row and calls[1]==nil and calls[2]==1)
assert(row.cells[5].text=='Офлайн · < 1 год')
assert(row.cellHovers[5].fullText=='Офлайн: < 1 год\nOffline Zone')
assert(row.specIcon.texture==123 and row.specIcon.shown and row.cells[4].width==62)
assert(row.cellHovers[4].width==80 and row.cellHovers[4].point[4]==374)
icon=nil; mode='many'; OldKraken.GuildRoster:Load()
assert(row.cells[5].text=='Офлайн · 2 р 3 міс')
assert(not row.specIcon.shown and rawget(row.specIcon,'texture')==nil and row.cells[4].width==80)
assert(row.cellHovers[4].fullText=='Hunter\nHunter')
for _,v in ipairs({'partial','partial_nonzero','short','secret','error','negative','fraction','text'}) do
 mode=v; OldKraken.GuildRoster:Load(); assert(row.cells[5].text=='Offline Zone')
end
mode='zeros'; OldKraken.GuildRoster:Load(); assert(row.cells[5].text=='Офлайн · < 1 год')
""")

    def test_english_duration_strings(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute("OldKraken={}")
        lua.execute((ROOT / 'Locale.lua').read_text(encoding='utf-8'))
        lua.execute(r"""
OldKraken.InitializeLocale({settings={language='enUS'}})
assert(OldKraken.Translate('< 1 год')=='< 1 h')
assert(OldKraken.Translate('р')=='y' and OldKraken.Translate('міс')=='mo')
assert(OldKraken.Translate('д')=='d' and OldKraken.Translate('год')=='h')
""")


class TooltipsPhaseTwo(unittest.TestCase):
    def test_group_slot_details_and_alert(self):
        lua = runpy.run_path(str(ROOT / 'tests/test_ui_smoke.py'))['lua']
        lua.execute(r"""
OldKraken.Communication=OldKraken.Communication or {}
OldKraken.Communication.GetRosterSpec=function(_,name) return {name='Test Spec'} end
local finder=OldKraken.GroupFinder
local group={id='phase2',owner='Tank Owner',title='Phase 2',category='dungeon',dungeon='rfc',role='tank',maxSize=5,minLevel=1,maxLevel=60,description='',members={'Tank Owner','Healer Friend'},memberRoles={['Healer Friend']='healer'},partyObserved={['Healer Friend']=true}}
finder.groups[group.owner..'\001'..group.id]=group
OldKraken.listeners.GROUP_FINDER_CHANGED()
local ui=OldKrakenGroupFinderFrame
local card
for _,row in ipairs(ui.rows) do if type(row.group)=='table' and row.group.id=='phase2' then card=row end end
if not card then
 for _,row in ipairs(ui.rows) do
  for _,slot in ipairs(type(row.slots)=='table' and row.slots or {}) do if type(slot.member)=='string' then card=row; break end end
  if card then break end
 end
end
assert(card)
local occupied
for _,slot in ipairs(card.slots) do if type(slot.member)=='string' then occupied=slot; break end end
assert(occupied)
local tooltip=''
GameTooltip={SetOwner=function() end,SetText=function(_,v) tooltip=v end,AddLine=function(_,v) tooltip=tooltip..'\n'..v end,Show=function() end,Hide=function() end}
occupied.scripts.OnEnter(occupied); assert(tooltip:find('Test Spec',1,true))
card.scripts.OnClick()
local found=false
for _,row in ipairs(ui.memberRows) do if type(row.hover.memberLabel)=='string' and row.hover.memberLabel:find('Test Spec',1,true) then found=true end end
assert(found)
OldKraken.listeners.GROUP_FINDER_NEW(group)
local alert
for _,frame in ipairs(createdFrames) do if rawget(frame,'alertCaption') then alert=frame end end
assert(alert and alert.roleSlots[1].tooltipText:find('Test Spec',1,true))
""")

    def test_event_participant_tooltip(self):
        lua = runpy.run_path(str(ROOT / 'tests/test_events_ui.py'))['lua']
        lua.execute(r"""
OldKraken.Communication.GetRosterSpec=function(_,name) return {name='Test Spec'} end
local f=OldKrakenEventsFrame
local meta=getmetatable(f.detailsTitle); local old=meta.__index
meta.__index=function(self,key) if key=='GetStringHeight' then return function() return 14 end end; return old(self,key) end
for _,entry in ipairs(f.visible) do entry.event.people.Tester='dps'; entry.event.statuses.Tester='accepted' end
f.eventRows[1].scripts.OnClick()
assert(#f.signupRows>0 and f.signupRows[1].hover.tooltipStatus:find('Test Spec',1,true))
""")


if __name__ == '__main__':
    unittest.main()
