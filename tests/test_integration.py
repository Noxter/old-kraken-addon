from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
OldKraken={DB={groupFinder={}}, events={}}
function OldKraken:Fire(name) self.events[name]=(self.events[name] or 0)+1 end
function UnitName() return 'Hok', 'Mon' end
function GetRealmName() return 'CAMWOW EU4 Realm 5 PvE' end
guild='Guild'
function GetGuildInfo() return guild end
function GetServerTime() return 1700000000 end
function GetTime() return 100 end
function CreateFrame() return {RegisterEvent=function() end, SetScript=function(_,_,fn) login=fn end} end
C_Timer={NewTicker=function(_,fn) tick=fn end}
handlers={}; OldKraken.Communication={}
function OldKraken.Communication:RegisterHandler(kind,fn) handlers[kind]=fn end
function OldKraken.Communication:SendProtocol() return true end
function OldKraken.Communication:RequestSync() return true end
cleared=0
function OldKraken.Communication:ClearProtocolState() cleared=cleared+1 end
''')
for name in ['GroupFinder.lua', 'GroupFinderIntegration.lua']:
    lua.execute((root / name).read_text(encoding='utf-8'))
lua.execute('''
local f=OldKraken.GroupFinder
-- Owned groups migrate; ambiguous short-name application data is discarded.
local profile='CAMWOW EU4 Realm 5 PvE'..'\\001'..'Guild'..'\\001'..'Hok'
local acceptedKey='Alice Moon'..'\\001'..'accepted-group'
local old=setmetatable({}, {__index=f}); old:Initialize('Hok', function() return true end)
assert(old:Create('Old group','dungeon','',5,1,60,'tank'))
local oldGroup; for _,g in pairs(old.groups) do oldGroup=g end
oldGroup.members={'Hok','Noxter','Hok Moon'}
OldKraken.DB.groupFinder[profile]={records={old:EncodeGroup(oldGroup)},pending={legacy='pending'}}
login()
assert(f.identity == 'Hok Mon')
local migrated=f.groups['Hok Mon'..'\\001'..oldGroup.id]
assert(migrated and migrated.members[1]=='Hok Mon' and #migrated.members == 2 and migrated.members[2] == 'Hok Moon')
assert(migrated.revision == oldGroup.revision + 1)
local forged=migrated.revision
local forgedGroup={}
for k,v in pairs(migrated) do forgedGroup[k]=v end
forgedGroup.revision=forged+1
handlers.UPDATE('Hok Moon','spoof',f:EncodeGroup(forgedGroup))
assert(f.groups['Hok Mon'..'\\001'..oldGroup.id].revision == forged)
assert(OldKraken.DB.groupFinder[profile].legacyShortNames == nil)
assert(next(f.pending) == nil)
local other=setmetatable({}, {__index=f}); other:Initialize('Noxter Moon',function() return true end)
assert(other:Create('Remote group','quest','',5,1,60,'dps'))
local group; for _,g in pairs(other.groups) do group=g end
local payload=other:EncodeGroup(group)
handlers.ANNOUNCE('Noxter Forged','1',payload)
assert(not f.groups['Noxter Moon'..'\\001'..group.id])
handlers.ANNOUNCE('Noxter Moon','2',payload)
assert(f.groups['Noxter Moon'..'\\001'..group.id])
-- Two distinct characters with the same given name are not conflated.
local twin=setmetatable({}, {__index=f}); twin:Initialize('Hok Moon',function() return true end)
assert(twin:Create('Twin group','quest','',5,1,60,'dps'))
local twinGroup; for _,g in pairs(twin.groups) do twinGroup=g end
handlers.ANNOUNCE('Hok Moon','3',twin:EncodeGroup(twinGroup))
assert(f.groups['Hok Moon'..'\\001'..twinGroup.id])
assert(f.groups['Hok Mon'..'\\001'..oldGroup.id])
f.pending[acceptedKey]='accept'
f:Changed()
guild='Other'; login()
assert(cleared==1 and f.active and next(f.groups)==nil)
guild='Guild'; login()
assert(cleared==2 and f.groups['Hok Mon'..'\\001'..oldGroup.id] and f.pending[acceptedKey]=='accept')
''')
print('Integration checks passed')
