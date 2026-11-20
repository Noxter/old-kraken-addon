from pathlib import Path
import runpy
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
OldKraken={DB={groupFinder={}}, events={}}
function OldKraken:Fire(name, group)
    self.events[name]=(self.events[name] or 0)+1
    if name=='GROUP_FINDER_CHANGED' then self.lastChanged=group end
end
now=1700000000; mono=100; guild='Guild'; sent={}; failCancel=false; failKind=nil; messages={}
function print(text) messages[#messages+1]=text end
function UnitName() return 'Hok','Mon' end
function GetRealmName() return 'Realm' end
function GetGuildInfo() return guild end
function GetServerTime() return now end
function GetTime() return mono end
function CreateFrame() return {RegisterEvent=function() end, SetScript=function(_,_,fn) login=fn end} end
C_Timer={NewTicker=function(_,fn) tick=fn end}
handlers={}; OldKraken.Communication={}
function OldKraken.Communication:RegisterHandler(kind,fn) handlers[kind]=fn end
function OldKraken.Communication:SendProtocol(kind,payload)
    if type(payload)=='string' and #payload>2560 then return false end
    if (kind=='CANCEL' and failCancel) or kind==failKind then return false end
    sent[#sent+1]={kind=kind,payload=payload}; return true
end
function OldKraken.Communication:RequestSync() return true end
function OldKraken.Communication:ClearProtocolState() end
''')
for name in ('GroupFinder.lua', 'GroupFinderIntegration.lua'):
    lua.execute((root / name).read_text(encoding='utf-8'))
lua.execute(r'''
login(); f=OldKraken.GroupFinder
profile=OldKraken.DB.groupFinder['Realm\001Guild\001Hok']
local ok; ok,id=f:Create('Test','quest','start',5,1,60,'dps'); assert(ok)
key='Hok Mon\001'..id; group=f.groups[key]
assert(profile.lastActivity[id]==now and #profile.records==1)
local initial=now
now=initial+1200; guild=nil; login(); guild='Guild'; login()
assert(f.lastActivity[id]==initial and profile.lastActivity[id]==initial)
group=f.groups[key]
f:OnQuery(); f:SyncStep(); assert(profile.lastActivity[id]==initial)
assert(f:UpdateDescription(id,'start')); assert(profile.lastActivity[id]==initial)
now=initial+1300; assert(f:UpdateDescription(id,'changed'))
assert(profile.lastActivity[id]==now)
local updated=now
f.requests[id]={['Applicant Realm']='dps'}
f.requestVersions[id..'\001Applicant Realm']=1
now=now+1; assert(f:Decide(id,'Applicant Realm',false)); assert(profile.lastActivity[id]==now)
local decided=now
now=decided+3599; tick(); assert(not group.closed)
now=decided+3600; failCancel=true; local count=#messages; tick()
assert(not group.closed and #messages==count and profile.lastActivity[id]==decided)
failCancel=false; tick(); assert(group.closed and profile.lastActivity[id]==nil and #messages==count+1)
tick(); assert(#messages==count+1)
now=now+5; assert(f:Reopen(id)); assert(profile.lastActivity[id]==now)
assert(f:Cancel(id)); assert(profile.lastActivity[id]==nil)
assert(f:Reopen(id)); assert(f:Delete(id)); assert(profile.lastActivity[id]==nil)

-- Successful owner actions extend activity; rejected sends and automatic
-- synchronization do not. A reannounce also obeys its cooldown.
now=now+10; ok,actions=f:Create('Actions','quest','',5,1,60,'dps'); assert(ok)
local actionGroup=f.groups['Hok Mon\001'..actions]
local start=now; assert(not f:Reannounce(actions)); assert(profile.lastActivity[actions]==start)
now=now+301; failKind='BUMP'; assert(not f:Reannounce(actions)); assert(profile.lastActivity[actions]==start)
failKind=nil; assert(f:Reannounce(actions)); assert(profile.lastActivity[actions]==now)
now=now+1; f.requests[actions]={['Joiner Realm']='dps'}
assert(f:Decide(actions,'Joiner Realm',true)); assert(profile.lastActivity[actions]==now)
now=now+1; failKind='UPDATE'; assert(not f:RemoveMember(actions,'Joiner Realm')); assert(profile.lastActivity[actions]==now-1)
failKind=nil; assert(f:RemoveMember(actions,'Joiner Realm')); assert(profile.lastActivity[actions]==now)
local beforeSync=now; now=now+1; f:SyncPartyMembers({}); f:OnQuery()
while next(f.syncPending) or next(f.decisionSync) do assert(f:SyncStep()) end
assert(profile.lastActivity[actions]==beforeSync)
assert(f:Cancel(actions))

-- An expired listing is closed before activation even if CANCEL cannot queue.
now=now+10; ok,id2=f:Create('Expired','quest','',5,1,60,'dps'); assert(ok)
key2='Hok Mon\001'..id2; local rev=f.groups[key2].revision
guild=nil; login(); now=now+3600; failCancel=true; sent={}; guild='Guild'; login()
assert(f.groups[key2].closed and f.groups[key2].revision==rev+1)
assert(profile.lastActivity[id2]==nil)
f:OnQuery(); while next(f.syncPending) or next(f.decisionSync) do assert(f:SyncStep()) end
local sawClosed=false
for _, packet in ipairs(sent) do
    if packet.kind=='SYNC' then
        local fields=f._unpackFields(packet.payload,215)
        if fields[1]==id2 then assert(fields[4]=='1'); sawClosed=true end
    end
end
assert(sawClosed)
failCancel=false

-- Legacy profiles recover timestamps from the newer valid creation/bump time.
now=now+10; ok,id3=f:Create('Legacy','quest','',5,1,60,'dps'); assert(ok)
local created=now; guild=nil; login()
profile.lastActivity[id3]='bad'; profile.lastBump={ [id3]=created+60 }; now=created+100
guild='Guild'; login(); assert(f.lastActivity[id3]==created+60)
for _,bad in ipairs({0,-10,'bad',now+50000}) do
    profile.lastBump[id3]=bad
    assert(f:GetReannounceRemaining(id3)==200)
    assert(profile.lastBump[id3]==nil)
end
profile.lastBump='damaged'; assert(f:GetReannounceRemaining(id3)==200)
assert(type(profile.lastBump)=='table')

-- Never emit an out-of-range revision when a saved listing reaches the limit.
local maxGroup=f.groups['Hok Mon\001'..id3]
maxGroup.revision=2147483647
local before=#sent
assert(not f:UpdateDescription(id3,'cannot increment') and not f:Cancel(id3))
local synced=f:SyncPartyMembers({'New Member'}); assert(not synced and #sent==before)
assert(maxGroup.revision==2147483647 and not maxGroup.closed)
f:Changed(); guild=nil; login()
now=now+4000; guild='Guild'; login(); maxGroup=f.groups['Hok Mon\001'..id3]
assert(maxGroup and maxGroup.closed and maxGroup.revision==2147483647)
-- Remote announcements and snapshots identify the changed group to UI tracking.
local remote=setmetatable({onPersist=false},{__index=f}); remote:Initialize('Remote Realm',function() return true end)
local created,remoteId=remote:Create('Remote','quest','',5,1,60,'dps'); assert(created)
local remoteGroup=remote.groups['Remote Realm\001'..remoteId]
handlers.ANNOUNCE('Remote Realm','packet',remote:EncodeGroup(remoteGroup))
assert(OldKraken.lastChanged==f.groups['Remote Realm\001'..remoteId])
remoteGroup.revision=remoteGroup.revision+1
handlers.SYNC('Remote Realm','packet',remote:EncodeGroup(remoteGroup))
assert(OldKraken.lastChanged==f.groups['Remote Realm\001'..remoteId])

-- Closing a maximum-sized listing must stay encodable when revision 9 becomes 10.
now=now+10; local sizeOK,sizeId=f:Create('Large','quest','',200,1,60,'dps'); assert(sizeOK)
local sizeKey='Hok Mon\001'..sizeId; local sizeGroup=f.groups[sizeKey]
sizeGroup.revision=9; sizeGroup.memberRoles={['Hok Mon']='dps'}
for i=1,199 do
    local name=string.format('Member%03d',i)
    sizeGroup.members[#sizeGroup.members+1]=name
    sizeGroup.memberRoles[name]=i==1 and 'healer' or 'dps'
end
local exact=false
for length=0,500 do
    sizeGroup.description=string.rep('x',length)
    if #f:EncodeGroup(sizeGroup)==2560 then exact=true; break end
end
assert(exact and #f:EncodeGroup(sizeGroup)==2560)
f:Changed(); assert(not f:UpdateDescription(sizeId,sizeGroup.description..'z'))
local fullDescription=sizeGroup.description
assert(f:Cancel(sizeId))
assert(sizeGroup.closed and #f:EncodeGroup(sizeGroup)<=2560)
guild=nil; login(); guild='Guild'; login(); sizeGroup=f.groups[sizeKey]
assert(sizeGroup and sizeGroup.closed and #sizeGroup.members==200)
assert(sizeGroup.memberRoles.Member001=='healer' and sizeGroup.memberRoles.Member002=='dps')
assert(#f:EncodeGroup(sizeGroup)<=2560)
local receiver=setmetatable({onPersist=false},{__index=f})
receiver:Initialize('Receiver Realm',function() return true end)
local closedPayload=f:EncodeGroup(sizeGroup)
assert(receiver:ReceiveGroup('Hok Mon',closedPayload))
local received=receiver.groups[sizeKey]; mono=mono+1
assert(not receiver:ReceiveGroup('Hok Mon',closedPayload) and received.seenAt==mono)
local reopened, reason=f:Reopen(sizeId)
assert(not reopened and reason=='payload' and sizeGroup.closed)
assert(f:UpdateDescription(sizeId,fullDescription:sub(1,-5)))
assert(sizeGroup.closed and f.lastActivity[sizeId]==nil)
assert(f:Reopen(sizeId) and #f:EncodeGroup(sizeGroup)<=2560)
local openPayload=f:EncodeGroup(sizeGroup)
assert(receiver:ReceiveGroup('Hok Mon',openPayload))
received=receiver.groups[sizeKey]; mono=mono+1
assert(not receiver:ReceiveGroup('Hok Mon',openPayload) and received.seenAt==mono)
assert(received.memberRoles.Member001=='healer' and received.memberRoles.Member002=='dps')
guild=nil; login(); guild='Guild'; login(); sizeGroup=f.groups[sizeKey]
assert(sizeGroup and not sizeGroup.closed and sizeGroup.memberRoles.Member001=='healer')

-- Startup expiration must also persist a decodable compact snapshot when
-- CANCEL is unavailable, and retain the owner roles through another reload.
sizeGroup.revision=9; sizeGroup.description=fullDescription
assert(#f:EncodeGroup(sizeGroup)==2560); f:Changed()
guild=nil; login(); now=now+3600; failCancel=true; guild='Guild'; login()
sizeGroup=f.groups[sizeKey]; assert(sizeGroup and sizeGroup.closed and #f:EncodeGroup(sizeGroup)<=2560)
f:OnQuery(); local syncSteps=0
while next(f.syncPending) or next(f.decisionSync) do
    assert(f:SyncStep()); syncSteps=syncSteps+1; assert(syncSteps<500)
end
assert(syncSteps>0)
guild=nil; login(); guild='Guild'; login(); sizeGroup=f.groups[sizeKey]
assert(sizeGroup and sizeGroup.closed and sizeGroup.memberRoles.Member001=='healer')
failCancel=false

-- When observed-party data is the only part needing compaction, roles remain
-- on the wire and observed membership is restored locally after reload.
now=now+10; local partyOK,partyId=f:Create('Party','quest','',125,1,60,'dps'); assert(partyOK)
local partyKey='Hok Mon\001'..partyId; local partyGroup=f.groups[partyKey]
partyGroup.revision=9; partyGroup.memberRoles={['Hok Mon']='dps'}; partyGroup.partyObserved={}
for i=1,124 do
    local name=string.format('Person%03d-Long',i)
    partyGroup.members[#partyGroup.members+1]=name
    partyGroup.memberRoles[name]=i==1 and 'healer' or 'dps'
    if i%2==0 then partyGroup.partyObserved[name]=true end
end
local partyExact=false
for length=0,500 do
    partyGroup.description=string.rep('y',length)
    if #f:EncodeGroup(partyGroup)==2560 then partyExact=true; break end
end
assert(partyExact); f:Changed(); assert(f:Cancel(partyId))
local compact=f:EncodeGroup(partyGroup)
local peer=setmetatable({onPersist=false},{__index=f}); peer:Initialize('Peer Realm',function() return true end)
assert(peer:ReceiveGroup('Hok Mon',compact) and peer.groups[partyKey].memberRoles['Person001-Long']=='healer')
guild=nil; login(); guild='Guild'; login(); partyGroup=f.groups[partyKey]
assert(partyGroup and partyGroup.partyObserved['Person002-Long'] and partyGroup.memberRoles['Person001-Long']=='healer')

-- Legacy senders may provide a maximum-sized snapshot with no optional fields.
-- Closing it can require dropping a member from the closed wire snapshot, but
-- the owner must recover the complete list and peers must deduplicate it.
local legacyPayload
for width=70,110 do
    local fields={'legacyMinimal','Hok Mon',9,'0','Minimal','quest','',25,25,1,60,'dps','Hok Mon'}
    for i=1,23 do fields[#fields+1]=string.format('%02d',i)..string.rep('m',width-2) end
    for last=1,128 do
        fields[37]=string.rep('z',last)
        local encoded=f._pack(fields)
        if #encoded==2560 then legacyPayload=encoded; break end
    end
    if legacyPayload then break end
end
assert(legacyPayload and f:ReceiveGroup('Hok Mon',legacyPayload))
local legacyKey='Hok Mon\001legacyMinimal'; local legacy=f.groups[legacyKey]
assert(#legacy.members==25 and #f:EncodeGroup(legacy)==2560)
assert(f:GetReannounceRemaining('legacyMinimal')==0)
now=now+100; assert(f:GetReannounceRemaining('legacyMinimal')==0)
f.lastActivity.legacyMinimal=now; f:Changed()
assert(f:Cancel('legacyMinimal'))
local legacyClosed=f:EncodeGroup(legacy); assert(#legacyClosed<=2560)
local legacyPeer=setmetatable({onPersist=false},{__index=f}); legacyPeer:Initialize('Legacy Peer',function() return true end)
assert(legacyPeer:ReceiveGroup('Hok Mon',legacyClosed))
local peerGroup=legacyPeer.groups[legacyKey]
assert(#peerGroup.members<#legacy.members)
mono=mono+1; assert(not legacyPeer:ReceiveGroup('Hok Mon',legacyClosed) and peerGroup.seenAt==mono)
guild=nil; login(); guild='Guild'; login(); legacy=f.groups[legacyKey]
assert(legacy and legacy.closed and #legacy.members==25 and legacy.members[25]==string.rep('z',#legacy.members[25]))

-- Reserve a revision for the eventual closure; closed edits must also leave
-- enough revisions for both reopening and a subsequent close.
now=now+10; local guardOK,guardId=f:Create('Revision guard','quest','',5,1,60,'dps'); assert(guardOK)
local guard=f.groups['Hok Mon\001'..guardId]
guard.revision=2147483646
local changed,why=f:UpdateDescription(guardId,'change')
assert(not changed and why=='revision' and guard.revision==2147483646)
assert(f:Cancel(guardId) and guard.revision==2147483647)
local reopened,why=f:Reopen(guardId); assert(not reopened and why=='revision')
local guard2OK,guard2Id=f:Create('Closed revision guard','quest','',5,1,60,'dps'); assert(guard2OK)
local guard2=f.groups['Hok Mon\001'..guard2Id]; assert(f:Cancel(guard2Id))
guard2.revision=2147483645
local edited,why=f:UpdateDescription(guard2Id,'change'); assert(not edited and why=='revision')
assert(f:Reopen(guard2Id) and guard2.revision==2147483646)
assert(f:Cancel(guard2Id) and guard2.revision==2147483647)
''')
print('Phase 1 activity checks passed')

ui = runpy.run_path(str(root / 'tests/test_ui_smoke.py'))['lua']
ui.execute(r'''
local finder=OldKraken.GroupFinder
local ok,id=finder:Create('!Closed edit','quest','long description',5,1,60,'dps'); assert(ok)
assert(finder:Cancel(id))
finder:Show(); local window=OldKrakenGroupFinderFrame
window.tabBar.tabs.mine.scripts.OnClick()
local card
for _,row in ipairs(window.rows) do if row.entry and row.entry.group.id==id then card=row; break end end
assert(card); card.scripts.OnClick(card)
assert(window.editDescButton:IsShown()); window.editDescButton.scripts.OnClick()
window.editDescBox:SetText('shorter'); window.saveDescButton.scripts.OnClick()
local group=finder.groups[finder.identity..'\001'..id]
assert(group.closed and group.description=='shorter' and finder.lastActivity[id]==nil)
''')
print('Closed listing description editing checks passed')
