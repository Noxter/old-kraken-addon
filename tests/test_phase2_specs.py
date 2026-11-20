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


class SpecTwo(unittest.TestCase):
    def setUp(self):
        self.lua = runtime()
        self.lua.execute(r"""
OldKraken.DB={roster={}}; clock=1701000000; cfgID=5; treeID=20; spent=20
points={10,7,3}; ranks={[3]=2,[10]=1}; nodeList={10,3}
function GetServerTime() return clock end
C_ClassTalents={GetActiveConfigID=function() return cfgID end}
C_Traits={
 GetConfigInfo=function() return {treeIDs={treeID}} end,
 GetTreeCurrencyInfo=function() return {{spent=spent}} end,
 GetTreeNodes=function() return nodeList end,
 GetNodeInfo=function(_,id) return {ranksPurchased=ranks[id] or 0} end}
function header(name,index,icon)
 return {Name={GetText=function() return name end},
         Text={GetText=function() return tostring(points[index]) end},
         Icon={GetTexture=function() return icon end}}
end
hooks={}; talentFrame={treeHeaders={header(' Marksmanship ',1,123),header('Survival',2,456),header('Beast',3,789)}}
function talentFrame:RefreshTreeHeaders() end
function talentFrame:HookScript(name,fn) hooks[name]=fn end
function hooksecurefunc(_,name,fn) hooks[name]=fn end
PlayerSpellsFrame={TalentsFrame=talentFrame}
c=OldKraken.Communication; c.ready=true; c:HasRosterAddon('X')
function msg(sender,seq,icon,pts,name)
 c:OnAddonMessage(c.PREFIX,'OKP^SPEC2^'..seq..'^'..icon..'^'..pts..'^'..name,'GUILD',sender or 'Other')
end
function queued()
 local t={}; for _,entry in ipairs(c.queue) do t[#t+1]=entry.message end; return table.concat(t,';')
end
""")

    def test_01_valid_and_legacy_precedence(self):
        self.lua.execute(r"""
local invalid=c.stats.invalid
c:OnAddonMessage(c.PREFIX,'OKP^SPEC^1485','GUILD','Other')
assert(c.rosterSpecs['Other-Realm'].source=='spec1' and c:GetRosterSpec('Other')==nil and c.stats.invalid==invalid)
msg('Other',1,123,'10/7/3','Marksman')
local s=c:GetRosterSpec('Other'); assert(s.name=='Marksman' and s.icon==123 and s.points=='10/7/3')
c:OnAddonMessage(c.PREFIX,'OKP^SPEC^1485','GUILD','Other')
assert(c:GetRosterSpec('Other').name=='Marksman')
msg('Other',2,0,'0/0/0',''); assert(c:GetRosterSpec('Other')==nil and c.rosterSpecs['Other-Realm'].reset)
c:OnAddonMessage(c.PREFIX,'OKP^SPEC^1485','GUILD','Other')
assert(c.rosterSpecs['Other-Realm'].reset)
msg('Other',3,0,'3/5/1','Survival'); s=c:GetRosterSpec('Other')
assert(s and s.name=='Survival' and s.icon==nil and s.points=='3/5/1')
""")

    def test_02_old_client_and_message_order(self):
        for source in ('tests/fixtures/communication_0_5_3.lua', 'tests/fixtures/communication_0_5_4_alpha_1.lua'):
            old = runtime(source)
            old.execute(r"""
local c=OldKraken.Communication; local before=c.stats.invalid
c:OnAddonMessage(c.PREFIX,'OKP^SPEC2^1^123^10/7/3^Marksman','GUILD','Other')
assert(c.stats.invalid==before and c:HasRosterAddon('Other'))
""")
        self.lua.execute(r"""
msg('Other',11,0,'0/0/0','')
msg('Other',10,123,'10/7/3','Old'); assert(c.rosterSpecs['Other-Realm'].reset)
msg('Other',12,123,'10/7/3','New'); assert(c:GetRosterSpec('Other').name=='New')
""")

    def test_03_local_cache_signature_and_ties(self):
        self.lua.execute(r"""
local s=c:GetLocalTraitSignature(); assert(s.distSig=='20|3:2,10:1')
cfgID=9; assert(c:GetLocalTraitSignature().distSig==s.distSig)
assert(c:GetRosterSpec('Noxter Moon')==nil)
c:RefreshLocalTreeSpec(); s=c:GetRosterSpec('Noxter'); assert(s.name=='Marksmanship' and s.points=='10/7/3' and s.icon==123)
local cache=OldKraken.DB.roster.localSpecs['Realm\001Noxter Moon']; assert(cache.distSig=='20|3:2,10:1')
guild='B'; c:HasRosterAddon('X'); assert(c:GetRosterSpec('Noxter').name=='Marksmanship')
ranks[10]=2; assert(c:GetRosterSpec('Noxter')==nil and next(OldKraken.DB.roster.localSpecs)==nil)
points={10,10,0}; c:RefreshLocalTreeSpec(); assert(c:GetRosterSpec('Noxter')==nil)
points={5,5,5}; c:RefreshLocalTreeSpec(); assert(c:GetRosterSpec('Noxter')==nil)
spent=0; points={0,0,0}; c:RefreshLocalTreeSpec(); assert(c:GetRosterSpec('Noxter')==nil)
""")

    def test_04_ui_and_trait_failures_are_not_partial(self):
        self.lua.execute(r"""
local old=C_Traits.GetNodeInfo
C_Traits.GetNodeInfo=function(_,id) if id==3 then error('bad node') end return old(nil,id) end
assert(c:GetLocalTraitSignature()==nil)
C_Traits.GetNodeInfo=function(_,id) if id==3 then return nil end return old(nil,id) end
assert(c:GetLocalTraitSignature()==nil)
C_Traits.GetNodeInfo=function(_,id) if id==3 then return {ranksPurchased=secret} end return old(nil,id) end
assert(c:GetLocalTraitSignature()==nil)
C_Traits.GetNodeInfo=old
local nodes=C_Traits.GetTreeNodes
C_Traits.GetTreeNodes=function() error('bad nodes') end; assert(c:GetLocalTraitSignature()==nil)
C_Traits.GetTreeNodes=function() return nil end; assert(c:GetLocalTraitSignature()==nil)
C_Traits.GetTreeNodes=nodes
nodeList={10,secret}; assert(c:GetLocalTraitSignature()==nil); nodeList={10,3}
talentFrame.treeHeaders=nil; c:RefreshLocalTreeSpec(); assert(c:GetRosterSpec('Noxter')==nil)
talentFrame.treeHeaders={header('A',1,1),header('B',2,2),header('C',3,3)}
talentFrame.treeHeaders[1].Name.GetText=function() return secret end
c:RefreshLocalTreeSpec(); assert(c:GetRosterSpec('Noxter')==nil)
talentFrame.treeHeaders[1].Name.GetText=function() error('bad ui') end
c:RefreshLocalTreeSpec(); assert(c:GetRosterSpec('Noxter')==nil)
talentFrame.treeHeaders[1].Name.GetText=function() return 'Valid' end
talentFrame.treeHeaders[1].Icon.GetTexture=function() return secret end
c:RefreshLocalTreeSpec(); assert(c:GetRosterSpec('Noxter')==nil)
talentFrame.treeHeaders[1].Icon.GetTexture=function() return 123 end
c:RefreshLocalTreeSpec(); assert(c:GetRosterSpec('Noxter').icon==123)
""")

    def test_05_local_and_remote_ttl(self):
        self.lua.execute(r"""
c:RefreshLocalTreeSpec(); local entry=OldKraken.DB.roster.localSpecs['Realm\001Noxter Moon']
clock=clock+604800; assert(c:GetRosterSpec('Noxter'))
clock=clock+1; assert(c:GetRosterSpec('Noxter')==nil)
OldKraken.DB.roster.localSpecs['Realm\001Noxter Moon']=entry
entry.updatedAt=clock+601; assert(c:GetRosterSpec('Noxter')==nil)
OldKraken.DB.roster.localSpecs['Realm\001Noxter Moon']=entry
entry.updatedAt=clock+600; assert(c:GetRosterSpec('Noxter'))
msg('Other',1,0,'10/7/3','Remote'); now=3700; assert(c:GetRosterSpec('Other'))
now=3701; assert(c:GetRosterSpec('Other')==nil)
msg('Other',2,0,'0/0/0',''); now=7302; assert(c:GetRosterSpec('Other')==nil and c.rosterSpecs['Other-Realm']==nil)
""")

    def test_06_bad_wire_messages(self):
        self.lua.execute(r"""
local invalid=c.stats.invalid
local bad={'0^1^10/7/3^Name','1^1^10/10/0^Tie','1^1^5/5/5^Tie',
 '1^0^00/0/0^','1^00^0/0/0^','1^1^0/0/0^','1^0^0/0/0^Name',
 '1^1^10/7/3^bad^extra','1^1^10/7/3^bad|escape','1^1^10/7/3^',
 '1^1^1000/0/0^Name','1^1^10/7/3^'..string.char(192,128),
 '1^1^10/7/3^'..string.rep('x',231)}
for _,v in ipairs(bad) do
 c:OnAddonMessage(c.PREFIX,'OKP^SPEC2^'..v,'GUILD','Other')
 assert(next(c.rosterSpecs)==nil)
end
assert(c.stats.invalid==invalid and (not OldKraken.DB.roster.specSequences or next(OldKraken.DB.roster.specSequences)==nil))
""")

    def test_07_hwm_duplicates_expiry_and_reload(self):
        self.lua.execute(r"""
msg('Other',10,123,'10/7/3','A'); local n=OldKraken.events
now=101; msg('Other',10,123,'10/7/3','A'); assert(OldKraken.events==n and c.rosterSpecs['Other-Realm'].receivedAt==101)
msg('Other',10,123,'10/7/3','B'); assert(c:GetRosterSpec('Other').name=='A' and OldKraken.events==n)
msg('Other',11,0,'0/0/0',''); now=3702; assert(c:GetRosterSpec('Other')==nil)
msg('Other',10,123,'10/7/3','A'); assert(c.rosterSpecs['Other-Realm']==nil)
msg('Other',11,0,'0/0/0',''); assert(c.rosterSpecs['Other-Realm']==nil)
""")
        self.lua.execute((ROOT / 'Communication.lua').read_text(encoding='utf-8'))
        self.lua.execute(r"""
c=OldKraken.Communication; c.ready=true
msg('Other',10,123,'10/7/3','A'); assert(c:GetRosterSpec('Other')==nil)
msg('Other',12,123,'10/7/3','C'); assert(c:GetRosterSpec('Other').name=='C')
""")

    def test_08_guild_isolation_and_hwm_cap(self):
        self.lua.execute(r"""
c:RefreshLocalTreeSpec(); local localEntry=OldKraken.DB.roster.localSpecs['Realm\001Noxter Moon']
msg('Other',10,123,'10/7/3','A'); guild='B'; c:HasRosterAddon('X')
assert(next(c.rosterSpecs)==nil and OldKraken.DB.roster.localSpecs['Realm\001Noxter Moon']==localEntry)
msg('Other',1,123,'10/7/3','B'); assert(c:GetRosterSpec('Other').name=='B')
guild='A'; c:HasRosterAddon('X'); msg('Other',9,123,'10/7/3','Old'); assert(c:GetRosterSpec('Other')==nil)
local h=OldKraken.DB.roster.specSequences
for k in pairs(h) do h[k]=nil end
for i=1,1024 do h['k'..i]={seq=1,payload='x',updatedAt=clock-i} end
h.k1.updatedAt=clock-2592001
msg('New',1,1,'2/1/0','New'); assert(h.k1==nil and h.k1024~=nil)
msg('Newer',1,1,'2/1/0','Newer'); assert(h.k1024==nil)
""")

    def test_09_hwm_age_and_crash_semantics(self):
        self.lua.execute(r"""
msg('Other',10,123,'10/7/3','A')
local h=OldKraken.DB.roster.specSequences
clock=clock+2592000; msg('Other',9,123,'10/7/3','Old'); assert(c:GetRosterSpec('Other').name=='A')
clock=clock+1; msg('Other',9,123,'10/7/3','Old'); assert(c:GetRosterSpec('Other').name=='Old')
-- A receiver crash restores the last saved HWM.
h['Realm\001A\001Other-Realm']=nil; c.rosterSpecs={}
msg('Other',10,123,'10/7/3','After crash'); assert(c:GetRosterSpec('Other').name=='After crash')
msg('Other',100001,123,'10/7/3','First'); local saved=h['Realm\001A\001Other-Realm'].payload
msg('Other',100001,123,'10/7/3','Conflict'); assert(h['Realm\001A\001Other-Realm'].payload==saved and c:GetRosterSpec('Other').name=='First')
msg('Other',100000,123,'10/7/3','Old sender'); assert(c:GetRosterSpec('Other').name=='First')
msg('Other',100002,123,'10/7/3','Recovered'); assert(c:GetRosterSpec('Other').name=='Recovered')
""")

    def test_10_retry_and_saved_sequence(self):
        self.lua.execute(r"""
c:RefreshLocalTreeSpec(); assert(queued():find('OKP^SPEC2^',1,true))
local key='Realm\001Noxter Moon'; local seq=OldKraken.DB.roster.localSpecSeq[key]
c.queue={}; assert(not c:SendLocalSpec(false))
assert(not c:SendLocalSpec(true) and c.pendingSpecForce)
now=105; assert(not c:SendLocalSpec(false) and c.pendingSpecForce)
now=110; c:Pump(); assert(not c.pendingSpecForce and OldKraken.DB.roster.localSpecSeq[key]==seq+1)
now=120; c.queue={}; for i=1,8 do c.queue[i]={message='test'} end
assert(c:SendLocalSpec(true) and #c.queue==9)
now=130; c.queue={}; for i=1,9 do c.queue[i]={message='test'} end
assert(not c:SendLocalSpec(true) and c.pendingSpecForce)
c.queue={}; c:Pump(); assert(not c.pendingSpecForce)
now=131; assert(not c:SendLocalSpec(true)); guild='B'; c:Pump()
assert(not c.pendingSpecForce and not c.pendingSpecBroadcast)
""")
        self.lua.execute((ROOT / 'Communication.lua').read_text(encoding='utf-8'))
        self.lua.execute(r"""
c=OldKraken.Communication; c.ready=true; c:HasRosterAddon('X'); c.queue={}
local key='Realm\001Noxter Moon'; local old=OldKraken.DB.roster.localSpecSeq[key]
assert(c:SendLocalSpec(true)); assert(OldKraken.DB.roster.localSpecSeq[key]==old+1)
""")

    def test_11_hooks_and_reset_broadcast(self):
        self.lua.execute(r"""
frames[1].scripts.OnEvent(frames[1],'ADDON_LOADED','Blizzard_PlayerSpells')
assert(hooks.RefreshTreeHeaders and hooks.OnShow and not OldKraken.DB.roster.localSpecs)
hooks.OnShow(); local events=OldKraken.events; local count=#c.queue
hooks.RefreshTreeHeaders(); hooks.OnShow(); assert(OldKraken.events==events and #c.queue==count)
now=110; spent=0; points={0,0,0}; hooks.RefreshTreeHeaders()
assert(queued():find('^0^0/0/0^',1,true))
""")

    def test_12_queue_failure_preserves_sequence_and_force(self):
        self.lua.execute(r"""
c:RefreshLocalTreeSpec(); local key='Realm\001Noxter Moon'
local seq=OldKraken.DB.roster.localSpecSeq[key]; local reply=c.lastSpecReply; local payload=c.lastBroadcastSpecPayload
now=110; local original=c.QueueMessage; c.QueueMessage=function() return false end
assert(not c:SendLocalSpec(true) and c.pendingSpecForce and c.pendingSpecBroadcast)
assert(c.lastSpecReply==reply and c.lastBroadcastSpecPayload==payload and OldKraken.DB.roster.localSpecSeq[key]==seq)
c.QueueMessage=original; c:Pump(); assert(OldKraken.DB.roster.localSpecSeq[key]==seq+1)
""")

    def test_13_sender_crash_sequence_reuse(self):
        self.lua.execute(r"""
clock=1700000001; c:RefreshLocalTreeSpec(); c.queue={}; c.lastSpecReply=nil
local key='Realm\001Noxter Moon'
msg('Other',100001,123,'10/7/3','Before crash')
local h=OldKraken.DB.roster.specSequences['Realm\001A\001Other-Realm']
local saved=h.payload
OldKraken.DB.roster.localSpecSeq[key]=100000; c.localSpecSeq=nil
assert(c:SendLocalSpec(true))
assert(c.queue[1].message:find('OKP^SPEC2^100001^',1,true)==1)
c:OnAddonMessage(c.PREFIX,c.queue[1].message,'GUILD','Other')
assert(h.payload==saved and c:GetRosterSpec('Other').name=='Before crash')
now=110; c.queue={}; assert(c:SendLocalSpec(true))
assert(c.queue[1].message:find('OKP^SPEC2^100002^',1,true)==1)
c:OnAddonMessage(c.PREFIX,c.queue[1].message,'GUILD','Other')
assert(c:GetRosterSpec('Other').name=='Marksmanship')
""")

    def test_14_registration_and_login_order(self):
        lua=LuaRuntime(unpack_returned_tuples=True)
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
        lua.execute(r"""
local c=OldKraken.Communication; local calls={}
c.RequestRosterPresence=function() calls[#calls+1]='query' end
c.SendLocalSpec=function(_,force) assert(force); calls[#calls+1]='spec' end
frames[1].scripts.OnEvent(frames[1],'PLAYER_LOGIN')
assert(calls[1]=='query' and calls[2]=='spec')
assert(frames[1].events.PLAYER_LOGIN and frames[1].events.CHAT_MSG_ADDON)
""")

    def test_15_legacy_local_id_api_is_unchanged(self):
        self.lua.execute(r"""
assert(c:GetLocalSpecID()==1485)
local api=C_SpecializationInfo
for _,v in ipairs({0,-1,1.5,10000000,secret}) do specID=v; assert(c:GetLocalSpecID()==nil) end
specID=1485
C_SpecializationInfo=nil; assert(c:GetLocalSpecID()==nil)
C_SpecializationInfo={GetSpecialization=function() error('failure') end,GetSpecializationInfo=api.GetSpecializationInfo}
assert(c:GetLocalSpecID()==nil)
C_SpecializationInfo=api
""")

    def test_16_talent_events_and_forced_reset(self):
        self.lua.execute(r"""
local f=frames[1]
local calls={}; local original=c.SendLocalSpec
c.SendLocalSpec=function(_,force) calls[#calls+1]=force; return false end
f.scripts.OnEvent(f,'PLAYER_SPECIALIZATION_CHANGED','target'); assert(#calls==0)
f.scripts.OnEvent(f,'PLAYER_SPECIALIZATION_CHANGED','player')
f.scripts.OnEvent(f,'ACTIVE_TALENT_GROUP_CHANGED')
assert(#calls==2 and calls[1]==false and calls[2]==false)
c.SendLocalSpec=original
points={10,10,0}; c:RefreshLocalTreeSpec()
assert(not queued():find('OKP^SPEC2^',1,true))
assert(not c:SendLocalSpec(true) and #c.queue==0)
spent=0; points={0,0,0}
assert(c:SendLocalSpec(true))
assert(queued():find('^0^0/0/0^',1,true))
""")

    def test_17_reload_cached_signature_and_changed_config(self):
        self.lua.execute("c:RefreshLocalTreeSpec(); assert(c:GetRosterSpec('Noxter'))")
        self.lua.execute((ROOT / 'Communication.lua').read_text(encoding='utf-8'))
        self.lua.execute(r"""
c=OldKraken.Communication; c.ready=true; cfgID=91
assert(c:GetRosterSpec('Noxter').name=='Marksmanship')
ranks[10]=3
assert(c:GetRosterSpec('Noxter')==nil)
assert(OldKraken.DB.roster.localSpecs['Realm\001Noxter Moon']==nil)
""")

    def test_18_trait_and_header_validation(self):
        self.lua.execute(r"""
local active=C_ClassTalents.GetActiveConfigID
C_ClassTalents.GetActiveConfigID=function() return secret end; assert(c:GetLocalTraitSignature()==nil)
C_ClassTalents.GetActiveConfigID=function() error('config') end; assert(c:GetLocalTraitSignature()==nil)
C_ClassTalents.GetActiveConfigID=active
local info=C_Traits.GetConfigInfo
C_Traits.GetConfigInfo=function() return {treeIDs={secret}} end; assert(c:GetLocalTraitSignature()==nil)
C_Traits.GetConfigInfo=info
local currency=C_Traits.GetTreeCurrencyInfo
C_Traits.GetTreeCurrencyInfo=function() return {{spent=secret}} end; assert(c:GetLocalTraitSignature()==nil)
C_Traits.GetTreeCurrencyInfo=currency
local head=talentFrame.treeHeaders[1]
head.Text.GetText=function() return secret end; c:RefreshLocalTreeSpec(); assert(c:GetRosterSpec('Noxter')==nil)
head.Text.GetText=function() return '10x' end; c:RefreshLocalTreeSpec(); assert(c:GetRosterSpec('Noxter')==nil)
head.Text.GetText=function() return ' 10 ' end
head.Name.GetText=function() return 'bad|name' end; c:RefreshLocalTreeSpec(); assert(c:GetRosterSpec('Noxter')==nil)
head.Name.GetText=function() return string.char(192,128) end; c:RefreshLocalTreeSpec(); assert(c:GetRosterSpec('Noxter')==nil)
head.Name.GetText=function() return 'Valid' end
head.Icon.GetTexture=function() error('icon') end; c:RefreshLocalTreeSpec(); assert(c:GetRosterSpec('Noxter')==nil)
""")

    def test_state_01_zero_spent_is_reset(self):
        self.lua.execute(r"""
spent=0; points={0,0,0}
local state,spec=c:GetLocalTreeSpec(); assert(state=='reset' and spec==nil)
assert(c:SendLocalSpec(true) and queued():find('^0^0/0/0^',1,true))
""")

    def test_state_02_tied_10_10_is_unknown(self):
        self.lua.execute(r"""
points={10,10,0}; c:RefreshLocalTreeSpec()
local state,spec=c:GetLocalTreeSpec()
assert(state=='unknown' and spec==nil and not c:SendLocalSpec(true) and #c.queue==0)
""")

    def test_state_03_tied_5_5_5_is_unknown(self):
        self.lua.execute(r"""
spent=15; points={5,5,5}; c:RefreshLocalTreeSpec()
assert(c:GetLocalTreeSpec()=='unknown' and not c:SendLocalSpec(true) and #c.queue==0)
""")

    def test_state_04_invalid_and_secret_headers_are_unknown(self):
        self.lua.execute(r"""
local h=talentFrame.treeHeaders[3]
points={0,0,0}
for _,value in ipairs({secret,'bad','-1','1.5'}) do
 h.Text.GetText=function() return value end
 c:RefreshLocalTreeSpec()
 assert(c:GetLocalTreeSpec()=='unknown' and not c:SendLocalSpec(true) and #c.queue==0)
end
talentFrame.treeHeaders=nil; c:RefreshLocalTreeSpec()
assert(c:GetLocalTreeSpec()=='unknown' and #c.queue==0)
""")

    def test_state_05_header_total_must_match_spent(self):
        self.lua.execute(r"""
local key='Realm\001Noxter Moon'
for _,p in ipairs({{0,0,0},{10,7,2},{30,0,0}}) do
 points=p; c:RefreshLocalTreeSpec()
 assert(c:GetLocalTreeSpec()=='unknown' and OldKraken.DB.roster.localSpecs[key]==nil)
 assert(not c:SendLocalSpec(true) and #c.queue==0)
end
""")

    def test_state_06_active_to_unknown_keeps_broadcast(self):
        self.lua.execute(r"""
spent=26; points={26,0,0}; c:RefreshLocalTreeSpec()
assert(c:GetRosterSpec('Noxter') and #c.queue==1)
local payload=c.lastBroadcastSpecPayload; local events=OldKraken.events
c.queue={}; spent=20; points={10,10,0}; now=110; c:RefreshLocalTreeSpec()
assert(c:GetRosterSpec('Noxter')==nil and c.lastBroadcastSpecPayload==payload and #c.queue==0)
assert(OldKraken.DB.roster.localSpecs['Realm\001Noxter Moon']==nil and OldKraken.events==events+1)
c:RefreshLocalTreeSpec(); assert(OldKraken.events==events+1 and #c.queue==0)
""")

    def test_state_07_active_to_reset(self):
        self.lua.execute(r"""
c:RefreshLocalTreeSpec(); assert(#c.queue==1)
c.queue={}; now=110; spent=0; points={0,0,0}
c:RefreshLocalTreeSpec()
assert(c:GetLocalTreeSpec()=='reset' and not c:GetRosterSpec('Noxter'))
assert(OldKraken.DB.roster.localSpecs['Realm\001Noxter Moon']==nil)
assert(c.lastBroadcastSpecPayload=='0^0/0/0^' and queued():find('^0^0/0/0^',1,true))
""")

    def test_state_08_reset_to_active(self):
        self.lua.execute(r"""
spent=0; points={0,0,0}; assert(c:SendLocalSpec(true))
c.queue={}; now=110; spent=20; points={10,7,3}; c:RefreshLocalTreeSpec()
local state,spec=c:GetLocalTreeSpec()
assert(state=='active' and spec.name=='Marksmanship' and spec.points=='10/7/3')
assert(queued():find('^123^10/7/3^Marksmanship',1,true))
""")

    def test_state_09_unknown_to_active(self):
        self.lua.execute(r"""
points={10,10,0}; c:RefreshLocalTreeSpec()
assert(c:GetLocalTreeSpec()=='unknown' and not c:SendLocalSpec(true))
points={3,14,3}; now=110; c:RefreshLocalTreeSpec()
local state,spec=c:GetLocalTreeSpec()
assert(state=='active' and spec.name=='Survival' and queued():find('^456^3/14/3^Survival',1,true))
""")

    def test_state_10_pending_force_does_not_create_reset(self):
        self.lua.execute(r"""
c:RefreshLocalTreeSpec(); local payload=c.lastBroadcastSpecPayload
c.queue={}; points={10,10,0}; c:RefreshLocalTreeSpec()
c.pendingSpecBroadcast=true; c.pendingSpecForce=true
assert(not c:SendLocalSpec(true) and not c.pendingSpecBroadcast and not c.pendingSpecForce)
assert(c.lastBroadcastSpecPayload==payload and #c.queue==0)
c:Pump(); assert(#c.queue==0)
""")

    def test_state_11_mismatched_cached_total_is_cleared(self):
        self.lua.execute(r"""
c:RefreshLocalTreeSpec(); local key='Realm\001Noxter Moon'
local cache=OldKraken.DB.roster.localSpecs[key]
cache.points='11/7/3'
local state,spec=c:GetLocalTreeSpec()
assert(state=='unknown' and spec==nil and OldKraken.DB.roster.localSpecs[key]==nil)
OldKraken.DB.roster.localSpecs[key]=123
c:RefreshLocalTreeSpec(); assert(c:GetRosterSpec('Noxter').points=='10/7/3')
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
