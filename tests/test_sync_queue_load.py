from pathlib import Path
from lupa.lua51 import LuaRuntime

root=Path(__file__).resolve().parents[1]
source=(root/'Communication.lua').read_text(encoding='utf-8')
def client():
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
    OldKraken={}; now=100; prints=0; calls=0; result=0; sent={}
    function print() prints=prints+1 end
    function GetTime() return now end
    function GetServerTime() return 1700000000 end
    function IsInGuild() return true end
    guild='Guild'; function GetGuildInfo() return guild end
    function UnitName() return 'Me' end
    function CreateFrame() return {RegisterEvent=function() end,SetScript=function() end} end
    Enum={SendAddonMessageResult={Success=0,AddonMessageThrottle=1,ChannelThrottle=2,AddOnMessageLockdown=3}}
    C_ChatInfo={SendAddonMessage=function(_,message) calls=calls+1; if throwing then error('temporary') end; if result==0 then sent[#sent+1]=message end; return result end}
    ''')
    lua.execute(source);lua.execute('OldKraken.Communication.ready=true')
    return lua

lua=client()
lua.execute('''
local c=OldKraken.Communication
packets={}
for i=1,500 do
    local payload=string.format('%03d',i)..string.rep('x',100)
    local ok,id=c:SendProtocol('SYNC',payload); assert(ok)
    local size=#c.queue
    local repeated,repeatedID=c:SendProtocol('SYNC',payload)
    assert(repeated and repeatedID==id and #c.queue==size)
end
assert(#c.queue==1000 and c.stats.deduplicated==500)
for _,entry in ipairs(c.queue) do
    if entry.part==1 then packets[#packets+1]={entry.message,entry.job.messages[2]} end
end
assert(c:SendProtocol('JOIN','important application'))
result=1
for i=1,100 do
    now=math.max(now,c.retryAt)+1
    c:Pump()
    local before=calls
    c:Pump(); assert(calls==before,'backoff must prevent repeated API calls')
end
assert(#c.queue==1001 and c.stats.dropped==0 and prints==0)
assert(c.retryAt-now<=61 and c.backoff==60)
result=3; now=c.retryAt+1; c:Pump(); assert(#c.queue==1001)
throwing=true; now=c.retryAt+1; c:Pump(); assert(#c.queue==1001 and prints==0)
throwing=false; result=0; now=c.retryAt+1
while #c.queue>0 do c:Pump(); now=now+0.7 end
assert(#sent==1001 and sent[1]:find('GF2^JOIN^',1,true)==1)
assert(c.stats.dropped==0 and prints==0 and next(c.pendingTransmissions)==nil)
''')
receiver=client()
receiver.execute('received=0; assert(OldKraken.Communication:RegisterHandler("SYNC",function() received=received+1 end))')
for part in [1,2]:
    for i in range(1,501):
        receiver.globals().OldKraken.Communication.OnAddonMessage(receiver.globals().OldKraken.Communication,'OLDKRKN',lua.globals().packets[i][part],'GUILD',f'Member {i}')
receiver.execute('assert(received==500 and OldKraken.Communication.stats.invalid==0)')

lua=client()
lua.execute('''
local c=OldKraken.Communication
assert(c:SendProtocol('SYNC',string.rep('x',200)))
c:Pump(); assert(#c.queue==2)
result=1; c:Pump(); now=now+130
c:Pump(); assert(#c.queue==3 and c.stats.restarted==1)
result=0
while #c.queue>0 do c:Pump(); now=now+0.7 end
assert(#sent==4 and c.stats.dropped==0)
-- Bulk work cannot consume the action reserve; refusal is atomic and silent.
for i=1,c.BACKGROUND_LIMIT do assert(c:QueueMessage('packet '..i)) end
local size=#c.queue
assert(not c:SendProtocol('SYNC','background') and #c.queue==size)
assert(c:SendProtocol('JOIN','user action') and #c.queue==size+1)
assert(prints==0)
-- Do not transmit queued state to a different guild after switching guilds.
c:ClearProtocolState(); c.queue={}; c.pendingTransmissions={}
assert(c:SendProtocol('SYNC','old guild state'))
guild='Other'; local before=#sent; c:Pump()
assert(#sent==before and #c.queue==0)
''')
print('PASS: 500 queued/deduplicated snapshots, 500 concurrent receiver assemblies, 100 throttles without loss/spam, exponential backoff, action priority/reserve, interrupted multipart replay and guild isolation')
