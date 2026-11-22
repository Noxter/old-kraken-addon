from pathlib import Path

from lupa.lua51 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
messages = {}
function print(...) end
function CreateFrame() return {RegisterEvent=function() end, SetScript=function() end} end
function UnitName() return 'Tester' end
function IsInGuild() return true end
function GetGuildInfo() return 'Guild' end
function GetServerTime() return 1234567890 end
now = 100
function GetTime() return now end
function strsplit(delimiter, s)
  return s:match('^([^%^]*)%^([^%^]*)%^([^%^]*)%^([^%^]*)$')
end
Enum = {SendAddonMessageResult = { Success=0, AddonMessageThrottle=1, ChannelThrottle=2, AddOnMessageLockdown=3 }}
result = 0
C_ChatInfo = { SendAddonMessage=function(prefix, message, channel)
  table.insert(messages, message); return result
end }
''')
lua.execute((Path(__file__).resolve().parents[1] / 'Communication.lua').read_text(encoding='utf-8'))
lua.execute('''
local c = OldKraken.Communication
c.ready = true
local relayed
assert(c:RegisterHandler('WORELAY', function(sender, id, payload) relayed=payload end))
assert(c:SendProtocol('WORELAY', string.rep('я', 100)))
local relayParts={}; for i,entry in ipairs(c.queue) do relayParts[i]=entry.message end
assert(#relayParts==3)
for i=#relayParts,1,-1 do c:OnAddonMessage(c.PREFIX,relayParts[i],'GUILD','Relay') end
assert(relayed==string.rep('я',100))
for i=#c.queue,1,-1 do table.remove(c.queue,i) end
local got
assert(c:RegisterHandler('ANNOUNCE', function(sender, id, payload) got = {sender,id,payload} end))
assert(not c:RegisterHandler('ANNOUNCE', function() end))
local ok = c:SendProtocol('ANNOUNCE', 'Привіт^тест')
assert(ok and #c.queue == 1 and #c.queue[1].message <= 240)
local packet = c.queue[1].message
c:OnAddonMessage(c.PREFIX, packet, 'GUILD', 'Author-Realm')
assert(got[1] == 'Author-Realm' and got[3] == 'Привіт^тест')
local count = c.stats.received
c:OnAddonMessage(c.PREFIX, 'GF2^ANNOUNCE^1-2-3^1^1^F', 'GUILD', 'Author')
assert(c.stats.received == count and c.stats.invalid == 1)
assert(not c:SendProtocol('ANNOUNCE', string.rep('x', 2561)))
result = 1
for i=1,8 do c:Pump(); now=now+100 end
assert(#c.queue==1 and c.stats.dropped==0)
result=0; c:Pump(); assert(#c.queue==0)
result = 0
c:SendTest()
c:Pump()
assert(messages[#messages]:match('^TEST%^'))
c:OnAddonMessage(c.PREFIX, 'TEST^id^Other^Other', 'GUILD', 'Other')
c:Pump()
assert(messages[#messages]:match('^ACK%^id%^Other%^Tester$'))
local calls, actual = 0, nil
assert(c:RegisterHandler('SYNC', function(sender, id, payload) calls = calls + 1; actual = payload end))
assert(c:SendProtocol('SYNC', string.rep('ж', 100)))
local parts = {}
for i, entry in ipairs(c.queue) do parts[i] = entry.message end
assert(#parts == 3)
c:OnAddonMessage(c.PREFIX, parts[3], 'GUILD', 'Other')
c:OnAddonMessage(c.PREFIX, parts[1], 'GUILD', 'Other')
c:OnAddonMessage(c.PREFIX, parts[1], 'GUILD', 'Other')
assert(calls == 0)
c:OnAddonMessage(c.PREFIX, parts[2], 'GUILD', 'Other')
assert(calls == 1 and actual == string.rep('ж', 100))
c:OnAddonMessage(c.PREFIX, parts[2], 'GUILD', 'Other')
assert(calls == 1)
assert(c:RequestSync())
-- A missing part must not deliver; an expired assembly cannot be completed
-- by a delayed fragment from that assembly.
local received = c.stats.received
local fresh = c:SendProtocol('SYNC', string.rep('x', 81))
assert(fresh)
local first, second = c.queue[#c.queue - 1].message, c.queue[#c.queue].message
c:OnAddonMessage(c.PREFIX, first, 'GUILD', 'Late')
now = now + 121
c:OnAddonMessage(c.PREFIX, second, 'GUILD', 'Late')
assert(c.stats.received == received)
-- Atomic enqueue: insufficient space must not leave partial messages.
while #c.queue < c.BACKGROUND_LIMIT-1 do assert(c:QueueMessage('test')) end
local queued = #c.queue
assert(not c:SendProtocol('SYNC', string.rep('z', 81)))
assert(#c.queue == queued)
local before = c.stats.invalid
assert(c:RegisterHandler('UPDATE', function() error('broken handler') end))
c:OnAddonMessage(c.PREFIX, 'GF2^UPDATE^1-2-3^1^1^41', 'GUILD', 'Other')
assert(c.stats.invalid == before + 1)
c:OnAddonMessage(c.PREFIX, 'GF2^UPDATE^1-2-3^1^1^41', 'GUILD', 'Other')
assert(c.stats.invalid == before + 2)
''')
print('Communication checks passed')


def transport_client():
    runtime = LuaRuntime(unpack_returned_tuples=True)
    runtime.execute('''
    OldKraken={}; now=100; guild='A'; sent={}; prints=0; events={}; result=0
    function print() prints=prints+1; if printThrows then error('print failed') end end
    function GetTime() return now end
    function GetServerTime() return 1234567890 end
    function IsInGuild() return true end
    function GetGuildInfo() return guild end
    function UnitName() return 'Tester' end
    function CreateFrame() return {RegisterEvent=function() end,SetScript=function() end} end
    function OldKraken:Fire(...) events[#events+1]={...}; if fireThrows then error('listener failed') end end
    Enum={SendAddonMessageResult={Success=0,AddonMessageThrottle=1,ChannelThrottle=2,AddOnMessageLockdown=3}}
    C_ChatInfo={SendAddonMessage=function(_,message)
        if throwing then error('send failed') end
        if result==0 or result==nil then sent[#sent+1]=message end
        return result
    end}
    ''')
    runtime.execute((Path(__file__).resolve().parents[1] / 'Communication.lua').read_text(encoding='utf-8'))
    runtime.execute('c=OldKraken.Communication; c.ready=true')
    return runtime


def scenario(code):
    transport_client().execute(code)


# Failed entries back off independently, and a whole failed job is removed once.
for fail_mode in ('throwing=true', 'result=77'):
    scenario('''
    assert(c:SendProtocol('ANNOUNCE',string.rep('a',160)))
    local job=c.queue[1].job
    assert(c:SendProtocol('CEVENT','other')); local other=c.queue[3].job
    ''' + fail_mode + '''
    c:Pump(); local entry=c.queue[1]
    local attempts,backoff,nextTry=entry.errorAttempts,entry.errorBackoff,entry.nextTryAt
    assert(attempts==1 and backoff==2 and c.retryAt==0)
    throwing=false; result=0; c:Pump()
    assert(#sent==1 and sent[1]:find('GF2^ANNOUNCE^',1,true)==1)
    c:Pump(); assert(#sent==2 and sent[2]:find('GF2^CEVENT^',1,true)==1)
    assert(entry.errorAttempts==attempts and entry.errorBackoff==backoff and entry.nextTryAt==nextTry)
    ''' + fail_mode + '''
    for i=2,5 do now=entry.nextTryAt+1; c:Pump() end
    assert(#c.queue==0 and c.stats.dropped==1 and c.pendingTransmissions[job.key]==nil)
    assert(c:SendProtocol('ANNOUNCE',string.rep('a',160)))
    assert(c.pendingTransmissions[c.queue[1].job.key]~=job)
    ''')

scenario('''
assert(c:QueueMessage('one')); assert(c:QueueMessage('two')); assert(c:QueueMessage('three'))
c.queue[1].priority=2; c.queue[2].priority=1; c.queue[3].priority=0
c:Pump(); c:Pump(); c:Pump(); assert(sent[1]=='three' and sent[2]=='two' and sent[3]=='one')
assert(c:QueueMessage('first')); assert(c:QueueMessage('second')); c:Pump(); c:Pump()
assert(sent[4]=='first' and sent[5]=='second')
''')

# Known throttles affect the global barrier; unknown results and throws do not.
for setup in ("Enum=nil; result=77", "Enum.SendAddonMessageResult.ChannelThrottle=nil; result=2", "throwing=true"):
    scenario("assert(c:QueueMessage('x')); " + setup + "; c:Pump(); assert(c.queue[1].errorAttempts==1 and c.retryAt==0 and c.backoff==0)")
for value in (1, 2, 3):
    scenario(f"assert(c:QueueMessage('x')); result={value}; c:Pump(); assert(c.retryAt>now and c.backoff==2 and not c.queue[1].errorAttempts)")
scenario("assert(c:QueueMessage('x')); result=nil; c:Pump(); assert(#c.queue==0 and c.stats.sent==1)")
scenario("assert(c:QueueMessage('x')); C_ChatInfo=nil; c:Pump(); assert(c.retryAt>now and c.stats.dropped==0 and not c.queue[1].errorAttempts)")
scenario("assert(c:QueueMessage('x')); result=9; c:Pump(); now=c.queue[1].nextTryAt+1; result=0; c:Pump(); assert(c.stats.dropped==0 and #sent==1)")

# Multiple snapshots retain the dependency until the last one leaves the queue.
for drop_first in (False, True):
    scenario('''
    local snapshot='2:id5:owner'..string.rep('s',100)
    local snapshot2='2:id5:owner'..string.rep('t',100)
    assert(c:SendProtocol('SYNC',snapshot)); local first=c.queue[1].job
    assert(c:SendProtocol('SYNC',snapshot2)); local second=c.queue[3].job
    assert(c:SendProtocol('JOIN','5:owner2:id'))
    for _,e in ipairs(c.queue) do if e.job==second then e.nextTryAt=now+100 end end
    ''' + ('''
    result=99; for i=1,5 do c:Pump(); if i<5 then now=c.queue[1].nextTryAt+1 end end
    assert(c.stats.dropped==1 and c.pendingTransmissions[first.key]==nil)
    result=0
    ''' if drop_first else '''
    c:Pump(); c:Pump(); assert(c.pendingTransmissions[first.key]==nil)
    ''') + '''
    local n=#sent; c:Pump(); assert(#sent==n)
    now=now+200; c:Pump(); c:Pump(); c:Pump()
    assert(sent[#sent]:find('GF2^JOIN^',1,true)==1)
    ''')

scenario('''
assert(c:SendProtocol('SYNC','2:id5:owner'..string.rep('s',100)))
local snapshot=c.queue[1].job; c.queue[1].nextTryAt=now+20
assert(c:SendProtocol('JOIN','5:owner2:id')); assert(c:SendProtocol('QUERY','free'))
c:Pump(); assert(sent[1]==snapshot.messages[2])
c:Pump(); assert(sent[2]:find('GF2^QUERY^',1,true)==1)
local n=#sent; c:Pump(); assert(#sent==n)
now=now+21; c:Pump(); c:Pump(); assert(sent[#sent]:find('GF2^JOIN^',1,true)==1)
''')
scenario('''
assert(c:SendProtocol('SYNC','2:id5:owner'..string.rep('s',100)))
for _,e in ipairs(c.queue) do e.nextTryAt=now+20 end
assert(c:SendProtocol('JOIN','5:owner2:id')); assert(c:SendProtocol('QUERY','free'))
c:Pump(); assert(#sent==1 and sent[1]:find('GF2^QUERY^',1,true)==1)
c:Pump(); assert(#sent==1)
now=now+21; c:Pump(); c:Pump(); c:Pump(); assert(sent[#sent]:find('GF2^JOIN^',1,true)==1)
''')

scenario('''
assert(c:SendProtocol('SYNC','2:id5:owner'..string.rep('s',100)))
local old=c.queue[1].job
for _,e in ipairs(c.queue) do e.nextTryAt=now+10 end
guild='B'; assert(c:SendProtocol('JOIN','5:owner2:id')); c:Pump()
assert(#sent==1 and sent[1]:find('GF2^JOIN^',1,true)==1 and c.stats.dropped==0)
now=now+11; c:Pump(); assert(#c.queue==0 and c.stats.dropped==1 and c.pendingTransmissions[old.key]==nil and prints==0)
''')

# Critical notifications are protected even if either callback throws.
for kind in ('JOIN', 'ANNOUNCE', 'WORDER', 'SYNC', 'QUERY', 'CVSTATE'):
    for print_throws, fire_throws in ((False, False), (True, True)):
        critical = kind in ('JOIN', 'ANNOUNCE', 'WORDER')
        scenario(f"""
        assert(c:SendProtocol('{kind}', 'payload')); local e=c.queue[1]; result=88
        printThrows={'true' if print_throws else 'false'}; fireThrows={'true' if fire_throws else 'false'}
        for i=1,5 do c:Pump(); if i<5 then now=e.nextTryAt+1 end end
        assert(c.stats.dropped==1 and #c.queue==0)
        assert(prints=={1 if critical else 0} and #events=={1 if critical else 0})
        if #events>0 then assert(events[1][1]=='COMMUNICATION_SEND_FAILED' and events[1][2]=='{kind}' and events[1][3]==e.job.id and events[1][4]=='88') end
        """)
scenario("assert(c:QueueMessage('OKP^HERE')); local e=c.queue[1]; result=9; for i=1,5 do c:Pump(); if i<5 then now=e.nextTryAt+1 end end; assert(c.stats.dropped==1 and prints==0 and #events==0)")

# Replay preserves errors only for remaining parts, and cannot evade the limit.
for trigger_deferred in (False, True):
    scenario('''
    assert(c:SendProtocol('ANNOUNCE',string.rep('x',200))); local job=c.queue[1].job
    c:Pump(); result=9; c:Pump(); local failed=c.queue[1]
    local backoff=failed.errorBackoff; failed.nextTryAt=now+200
    ''' + ("c.queue[2].nextTryAt=now+300; now=now+201" if trigger_deferred else "now=now+91") + '''
    c:Pump(); assert(c.stats.restarted==1 and job.remaining==3 and not job.startedAt)
    local e=c.queue[2]; assert(e.part==2 and e.errorAttempts==1 and e.errorBackoff==backoff and e.nextTryAt==300)
    assert(not c.queue[1].errorAttempts and not c.queue[3].errorAttempts)
    assert(c:SendProtocol('WORDER','unrelated')); assert(not c.queue[#c.queue].errorAttempts)
    c.queue[#c.queue].nextTryAt=now+1000
    for _,item in ipairs(c.queue) do if item.part~=2 then item.nextTryAt=now+1000 end end
    for i=2,5 do now=math.max(now,e.nextTryAt)+1; c:Pump() end
    assert(#c.queue==1 and c.queue[1].job.kind=='WORDER' and c.stats.dropped==1 and c.pendingTransmissions[job.key]==nil)
    ''')

# Reserve accepted fragments and restore them on replay at a full queue.
scenario('''
assert(c:SendProtocol('JOIN',string.rep('j',160))); local job=c.queue[1].job
c:Pump(); assert(job.remaining==1)
while c:QueueMessage('filler') do end
assert(#c.queue==4095 and c.stats.backpressure==1)
assert(c:SendProtocol('JOIN',string.rep('j',160)))
assert(not c:SendProtocol('JOIN','new'))
now=now+91; c:Pump(); assert(#c.queue==4096 and job.remaining==2 and c.stats.restarted==1)
assert(c.pendingTransmissions[job.key]==job)
assert(c.queue[#c.queue-1].job==job and c.queue[#c.queue].job==job)
''')

scenario('''
assert(c:SendProtocol('SYNC',string.rep('s',160))); c:Pump()
assert(c:SendProtocol('WORDER',string.rep('w',160))); c:Pump()
c.retryAt=now+50; c.backoff=8; c:ClearProtocolState()
assert(#c.queue==1 and c.queue[1].job.kind=='WORDER' and c.retryAt==now+50 and c.backoff==8)
while c:QueueMessage('filler') do end
assert(#c.queue==4095)
''')
scenario("assert(c:SendProtocol('SYNC','x')); c.retryAt=now+50; c.backoff=8; c:ClearProtocolState(); assert(#c.queue==0 and c.retryAt==0 and c.backoff==0)")

# Two active reservations are counted once each and released independently.
for cleanup in ('complete', 'drop', 'guild', 'clear'):
    scenario('''
    assert(c:SendProtocol('SYNC',string.rep('s',160))); local one=c.queue[1].job
    c:Pump()
    assert(c:SendProtocol('WORDER',string.rep('w',160))); local two=c.queue[2].job
    c:Pump()
    while c:QueueMessage('filler') do end
    assert(#c.queue==4094 and one.remaining==1 and two.remaining==1)
    for _,e in ipairs(c.queue) do
        if e.job==two then e.nextTryAt=now+1000 elseif not e.job then e.priority=2 end
    end
    ''' + {
        'complete': "c:Pump(); assert(one.remaining==0 and c.pendingTransmissions[one.key]==nil)",
        'drop': "local e=c.queue[1]; e.errorAttempts=4; result=99; c:Pump(); assert(one.remaining==0 and c.stats.dropped==1)",
        'guild': "guild='B'; c:Pump(); assert(one.remaining==0 and c.stats.dropped==1)",
        'clear': "c:ClearProtocolState(); assert(one.remaining==0 and c.pendingTransmissions[one.key]==nil)",
    }[cleanup] + '''
    assert(two.remaining==1 and c.pendingTransmissions[two.key]==two)
    assert(c:QueueMessage('reclaimed')); assert(c:QueueMessage('reclaimed again')); assert(not c:QueueMessage('full'))
    ''')

# Admission limits include replay reservations, deduplication wins over pressure,
# and replayed parts join the end of the current equal-priority queue.
scenario('''
assert(c:SendProtocol('JOIN',string.rep('a',160))); local started=c.queue[1].job; c:Pump()
while #c.queue<c.BACKGROUND_LIMIT-1 do assert(c:QueueMessage('filler')) end
local size=#c.queue; local pressure=c.stats.backpressure
assert(not c:SendProtocol('SYNC','background') and #c.queue==size and c.stats.backpressure==pressure+1)
assert(c:SendProtocol('JOIN','action'))
while c:QueueMessage('filler') do end
size=#c.queue; assert(size==4095)
assert(c:SendProtocol('JOIN',string.rep('a',160)))
assert(not c:SendProtocol('JOIN','another') and #c.queue==size)
''')
scenario('''
assert(c:SendProtocol('WORDER',string.rep('a',160))); local first=c.queue[1].job
c:Pump(); assert(c:SendProtocol('WORDER','b')); local second=c.queue[2].job
now=now+91; c:Pump(); assert(c.stats.restarted==1)
assert(c.queue[1].job==second and c.queue[2].job==first and c.queue[3].job==first)
c:Pump(); assert(sent[#sent]==second.messages[1])
''')

# A failed job must not remove another active job's deduplication key.
scenario('''
assert(c:SendProtocol('JOIN','bad')); local first=c.queue[1].job
assert(c:SendProtocol('JOIN','good')); local second=c.queue[2].job
local e=c.queue[1]; result=99; c:Pump()
c.queue[2].nextTryAt=now+1000
for i=2,5 do now=e.nextTryAt+1; c:Pump() end
assert(c.pendingTransmissions[first.key]==nil and c.pendingTransmissions[second.key]==second)
assert(c:SendProtocol('JOIN','bad') and c.pendingTransmissions[first.key]~=first)
''')

print('Transport reliability regression checks passed')
