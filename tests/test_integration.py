from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
OldKraken = {DB={groupFinder={}}, listeners={}, events={}}
function OldKraken:Fire(name, ...) self.events[name] = (self.events[name] or 0) + 1 end
function UnitName() return 'Alice' end
guild = 'Guild'
function GetGuildInfo() return guild end
function GetRealmName() return 'Moon' end
function GetServerTime() return 12345 end
function GetTime() return 100 end
function CreateFrame() return {RegisterEvent=function() end, SetScript=function(_, _, fn) login = fn end} end
C_Timer = {NewTicker=function(_, fn) tick = fn end}
local handlers = {}
OldKraken.Communication = {handlers=handlers}
function OldKraken.Communication:RegisterHandler(kind, fn) handlers[kind]=fn end
sent = {}
function OldKraken.Communication:SendProtocol(kind, payload) sent[#sent+1]={kind,payload}; return true end
function OldKraken.Communication:RequestSync() sent[#sent+1]={'QUERY',''}; return true end
cleared = 0
function OldKraken.Communication:ClearProtocolState() cleared = cleared + 1 end
''')
for name in ['GroupFinder.lua', 'GroupFinderIntegration.lua']:
    lua.execute((root / name).read_text(encoding='utf-8'))
lua.execute('''
login()
local f = OldKraken.GroupFinder
assert(f.active and f:Create('Dungeon','dungeon','',5))
f:Changed()
local saved = OldKraken.DB.groupFinder['Moon' .. '\\001' .. 'Guild' .. '\\001' .. 'Alice'].records
assert(#saved == 1)
tick()
assert(sent[1][1] == 'ANNOUNCE' and sent[2][1] == 'QUERY')
assert(sent[3][1] == 'SYNC')
local g
for _, value in pairs(f.groups) do g=value end
local payload = f._pack({'Alice',g.id,'dps','apply','12345001'})
OldKraken.Communication.handlers.JOIN('Bob Moon', 'id', payload)
assert(f.requests[g.id].Bob == 'dps')
local remote = setmetatable({}, {__index=f})
remote:Initialize('Bob', function() return true end)
assert(remote:Create('Remote group','quest','',5))
local remoteGroup
for _, value in pairs(remote.groups) do remoteGroup=value end
handlers.ANNOUNCE('Bob Moon', 'remote-id', remote:EncodeGroup(remoteGroup))
assert(f.groups['Bob\001' .. remoteGroup.id].title == 'Remote group')
assert(OldKraken.events.GROUP_FINDER_CHANGED > 0)
guild = 'Other'
login()
assert(cleared == 1 and f.active and next(f.groups) == nil)
guild = 'Guild'
login()
assert(cleared == 2 and f.active)
local restored
for _, value in pairs(f.groups) do restored=value end
assert(restored and restored.title == 'Dungeon' and f.requests[restored.id].Bob == 'dps')
local stored = OldKraken.DB.groupFinder['Moon' .. '\\001' .. 'Guild' .. '\\001' .. 'Alice']
stored.pending = {['OldOwner\\001oldid']='pending'}
stored.pendingVersions, stored.pendingRoles = nil, nil
guild = 'Other'; login(); guild = 'Guild'; login()
assert(f.pending['OldOwner\\001oldid'] == 'retry')
''')
print('Integration checks passed')
