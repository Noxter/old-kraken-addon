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
# WoW Forever 1.60.1 build 71037 reports these actual Enum values.
for value in (3, 8, 11):
    scenario(f"""
    Enum.SendAddonMessageResult={{Success=0,AddonMessageThrottle=3,ChannelThrottle=8,AddOnMessageLockdown=11}}
    assert(c:QueueMessage('x')); result={value}; c:Pump()
    assert(c.retryAt>now and c.backoff==2 and not c.queue[1].errorAttempts)
    result=0; now=c.retryAt+1; c:Pump(); assert(#c.queue==0 and c.stats.dropped==0 and #sent==1)
    """)
for value in (1, 2):
    scenario(f"""
    Enum.SendAddonMessageResult={{Success=0,AddonMessageThrottle=3,ChannelThrottle=8,AddOnMessageLockdown=11}}
    assert(c:QueueMessage('x')); result={value}; c:Pump()
    assert(c.retryAt==0 and c.queue[1].errorAttempts==1)
    """)
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
assert(c:SendProtocol('SYNC','2:id5:owner'..string.rep('a',100)))
assert(c:SendProtocol('SYNC','2:id5:owner'..string.rep('b',100)))
local first=c.queue[1].job; local last=c.queue[3].job
assert(c:SendProtocol('JOIN','5:owner2:id'))
c:Pump(); c:Pump(); assert(not c.pendingTransmissions[first.key])
local failed=c.queue[1]; result=99
for i=1,5 do
    c:Pump()
    if i<5 then
        for _,e in ipairs(c.queue) do if e.job==last then e.nextTryAt=failed.nextTryAt end end
        local n=#sent; c:Pump(); assert(#sent==n)
        now=failed.nextTryAt+1
    end
end
assert(c.stats.dropped==1 and not c.pendingTransmissions[last.key])
result=0; c:Pump(); assert(sent[#sent]:find('GF2^JOIN^',1,true)==1)
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

# The maintained reservation matches independently reconstructed active jobs
# throughout replay, subsequent accepts, cleanup, and another replay.
scenario('''
local function check(expected)
    local computed,seen=0,{}
    for _,e in ipairs(c.queue) do
        local j=e.job
        if j and not seen[j] then
            seen[j]=true
            if j.startedAt and j.remaining>0 then computed=computed+#j.messages-j.remaining end
        end
    end
    assert(computed==expected and c.reservedReplaySlots==computed)
    assert(#c.queue+computed<=c.MAX_QUEUE)
end
assert(c:SendProtocol('JOIN',string.rep('a',240))); local first=c.queue[1].job
assert(c:SendProtocol('WOREQ',string.rep('b',240))); local second=c.queue[4].job
check(0); c:Pump(); check(1)
for _,e in ipairs(c.queue) do if e.job==first then e.nextTryAt=now+10 end end
c:Pump(); check(2)
for _,e in ipairs(c.queue) do if e.job==second then e.nextTryAt=now+1000 end end
now=now+91; c:Pump(); check(1); assert(c.stats.restarted==1)
c:Pump(); check(2)
now=now+91; c:Pump(); check(1); assert(c.stats.restarted==2)
guild='B'; c:Pump(); check(1); assert(first.remaining==0)
now=now+1000; c:Pump(); check(0); assert(second.remaining==0)
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
for kind in ('WORDER', 'SYNC'):
    scenario(f"""
    assert(c:SendProtocol('JOIN',string.rep('r',160))); c:Pump()
    assert(c.reservedReplaySlots==1)
    while #c.queue<c.BACKGROUND_LIMIT-3 do assert(c:QueueMessage('filler')) end
    local before=#c.queue; local pressure=c.stats.backpressure
    assert(c:SendProtocol('{kind}',string.rep('p',160)))
    assert(#c.queue==before+2 and #c.queue+c.reservedReplaySlots==c.BACKGROUND_LIMIT)
    local size=#c.queue
    local ok,reason=c:SendProtocol('{kind}',string.rep('q',160))
    assert(not ok and reason=='queue full' and #c.queue==size and c.stats.backpressure==pressure+1)
    """)
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

# Async WHISPER bounce via CHAT_MSG_SYSTEM: counted credits, manual /w isolation, order independence, pruning, and localized ERR_CHAT_PLAYER_NOT_FOUND_S
scenario('''
ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
local dropped = {}
local origFire = OldKraken.Fire
OldKraken.Fire = function(self, ev, ...)
    if ev == 'COMM_WHISPER_DROPPED' then dropped[#dropped + 1] = { ... } end
    if origFire then return origFire(self, ev, ...) end
end
local origGetVer = c.GetRosterVersion
c.GetRosterVersion = function(_, name) if name == 'Rainira Moonveil' then return '0.5.9-alpha.1' end end

-- 1. Queued (unsent) addon WHISPER for Rainira Moonveil + manual /w bounce -> must NOT drop addon job
assert(c:SendProtocol('WRPAGE', string.rep('x', 200), 'Rainira Moonveil'))
local queuedBefore = #c.queue
assert(queuedBefore > 1)
assert(not c:OnSystemMessage("No player named 'Rainira Moonveil' is currently playing."), 'manual /w before any addon send must not drop addon job')
assert(#c.queue == queuedBefore and #dropped == 0)

-- 2. Addon sends 1 fragment -> bounce drops remaining fragments, counts txDrops once, and ignores duplicate bounce
c:Pump()
assert(#sent == 1)
assert(c:OnSystemMessage("No player named 'Rainira Moonveil' is currently playing."))
assert(#c.queue == 0, 'remaining WRPAGE fragments for bounced target must be dropped')
assert(#dropped == 1 and dropped[1][1] == 'WRPAGE' and dropped[1][2] == 'Rainira Moonveil' and dropped[1][3] == 'targetOffline')
assert(c.traffic.byKind.WRPAGE.txDrops == 1)
assert(c.traffic.byKind.WRPAGE.txDropReasons.targetOffline == 1)

-- Duplicate bounce on a later tick (e.g. manual /w on same target while confirmedOfflineTargets is active) must NOT double-count or suppress
now = now + 1
assert(not c:OnSystemMessage("No player named 'Rainira Moonveil' is currently playing."), 'manual /w after bounce credit consumed must not be swallowed')
assert(c.traffic.byKind.WRPAGE.txDrops == 1)

-- 3. Queuing another WRPAGE for the confirmed-offline target drops without calling SendAddonMessage
assert(c:SendProtocol('WRPAGE', 'short', 'Rainira Moonveil'))
c:Pump()
assert(#sent == 1, 'must not call SendAddonMessage for confirmed-offline target')
assert(#c.queue == 0)
assert(c.traffic.byKind.WRPAGE.txDrops == 2)

-- 4. After TTL expires (now + 15), expired entries are physically pruned and a new addon send succeeds normally
now = now + 15
assert(c:SendProtocol('WRPAGE', 'fresh', 'Rainira Moonveil'))
c:Pump()
assert(#sent == 2, 'after TTL expires and state is pruned, addon WHISPER must send normally')
now = now + 5
assert(not c:OnSystemMessage("No player named 'Rainira Moonveil' is currently playing."), 'expired pending send must be pruned and not match manual /w')

-- 5. Compromise behavior within active 3s pending window: 1st bounce consumes the 1 pending credit, 2nd bounce is not swallowed
now = now + 15
assert(c:SendProtocol('WRPAGE', 'win', 'Rainira Moonveil'))
c:Pump()
now = now + 1
assert(c:OnSystemMessage("No player named 'Rainira Moonveil' is currently playing.") == true, 'within 3s window, 1st bounce consumes 1 credit')
now = now + 1
assert(c:OnSystemMessage("No player named 'Rainira Moonveil' is currently playing.") == false, 'after 1 credit is consumed, subsequent manual /w is not swallowed')

-- 6. Multiple pending credits for the same target (2 sends -> 2 credits; 3rd bounce returns false)
now = now + 15
assert(c:SendProtocol('WRPAGE', 'm1', 'Rainira Moonveil'))
assert(c:SendProtocol('WRPAGE', 'm2', 'Rainira Moonveil'))
c:Pump()
c:Pump()
assert(#c.queue == 0)
local dropsBefore = c.traffic.byKind.WRPAGE.txDrops
assert(c:OnSystemMessage("No player named 'Rainira Moonveil' is currently playing.") == true)
now = now + 1
assert(c:OnSystemMessage("No player named 'Rainira Moonveil' is currently playing.") == true)
now = now + 1
assert(c:OnSystemMessage("No player named 'Rainira Moonveil' is currently playing.") == false)
assert(c.traffic.byKind.WRPAGE.txDrops == dropsBefore, 'no extra txDrops when queue was already empty')

OldKraken.Fire = origFire
c.GetRosterVersion = origGetVer
''')

filter_lua = LuaRuntime(unpack_returned_tuples=True)
filter_lua.execute('''
chatFilters = {}
function ChatFrame_AddMessageEventFilter(ev, fn) chatFilters[ev] = fn end
ERR_CHAT_PLAYER_NOT_FOUND_S = "Гравець [%s] (офлайн) +."
function CreateFrame() return {RegisterEvent=function() end, SetScript=function() end} end
function UnitName() return 'Tester' end
function IsInGuild() return true end
function GetGuildInfo() return 'Guild' end
function GetServerTime() return 1234567890 end
fnow = 100
function GetTime() return fnow end
function strsplit(d, s) return s:match('^([^%^]*)%^([^%^]*)%^([^%^]*)%^([^%^]*)$') end
Enum = {SendAddonMessageResult = { Success=0 }}
C_ChatInfo = { SendAddonMessage=function() return 0 end }
''')
filter_lua.execute((Path(__file__).resolve().parents[1] / 'Communication.lua').read_text(encoding='utf-8'))
filter_lua.execute('''
local c = OldKraken.Communication
c.ready = true
c.GetRosterVersion = function(_, name) if name == 'Rainira Moonveil' then return '0.5.9-alpha.1' end end
assert(type(chatFilters.CHAT_MSG_SYSTEM) == 'function')

-- Filter runs BEFORE OnSystemMessage (localized ERR_CHAT_PLAYER_NOT_FOUND_S with regex special chars):
-- suppresses both ChatFrame calls in the same frame, drops remaining queue once, and OnSystemMessage does not double-count
assert(c:SendProtocol('WRPAGE', string.rep('x', 200), 'Rainira Moonveil'))
c:Pump()
assert(#c.queue > 1)
assert(chatFilters.CHAT_MSG_SYSTEM(nil, 'CHAT_MSG_SYSTEM', "Гравець [Rainira Moonveil] (офлайн) +.") == true)
assert(chatFilters.CHAT_MSG_SYSTEM(nil, 'CHAT_MSG_SYSTEM', "Гравець [Rainira Moonveil] (офлайн) +.") == true)
assert(c:OnSystemMessage("Гравець [Rainira Moonveil] (офлайн) +.") == true)
assert(#c.queue == 0)
assert(c.traffic.byKind.WRPAGE.txDrops == 1, 'filter + OnSystemMessage on same frame must not double-count txDrops')

-- Reverse order: OnSystemMessage runs BEFORE ChatFrame filter on the same frame
fnow = fnow + 15
assert(c:SendProtocol('WRPAGE', string.rep('y', 200), 'Rainira Moonveil'))
c:Pump()
assert(#c.queue > 1)
assert(c:OnSystemMessage("Гравець [Rainira Moonveil] (офлайн) +.") == true)
assert(chatFilters.CHAT_MSG_SYSTEM(nil, 'CHAT_MSG_SYSTEM', "Гравець [Rainira Moonveil] (офлайн) +.") == true)
assert(#c.queue == 0)
assert(c.traffic.byKind.WRPAGE.txDrops == 2, 'reverse order on same frame must drop once')

-- Next frame: manual /w on the SAME target must NOT be suppressed by ChatFrame filter
fnow = fnow + 1
assert(chatFilters.CHAT_MSG_SYSTEM(nil, 'CHAT_MSG_SYSTEM', "Гравець [Rainira Moonveil] (офлайн) +.") == false)

-- Successful addon WHISPER followed by expired RTT window: manual /w on same target must NOT be suppressed
fnow = fnow + 15
assert(c:SendProtocol('WRPAGE', 'ok', 'Rainira Moonveil'))
c:Pump()
fnow = fnow + 4
assert(chatFilters.CHAT_MSG_SYSTEM(nil, 'CHAT_MSG_SYSTEM', "Гравець [Rainira Moonveil] (офлайн) +.") == false)
''')

# Modern ChatFrameUtil.AddMessageEventFilter + Name-Realm WHISPER target vs short-name CHAT_MSG_SYSTEM bounce
realm_lua = LuaRuntime(unpack_returned_tuples=True)
realm_lua.execute('''
chatUtilFilters = {}
ChatFrameUtil = { AddMessageEventFilter = function(ev, fn) chatUtilFilters[ev] = fn end }
ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
function CreateFrame() return {RegisterEvent=function() end, SetScript=function() end} end
function UnitName() return 'Tester' end
function IsInGuild() return true end
function GetGuildInfo() return 'Guild' end
function GetServerTime() return 1234567890 end
rnow = 200
function GetTime() return rnow end
function strsplit(d, s) return s:match('^([^%^]*)%^([^%^]*)%^([^%^]*)%^([^%^]*)$') end
Enum = {SendAddonMessageResult = { Success=0 }}
rsent = {}
C_ChatInfo = { SendAddonMessage=function(_, msg, ch, tgt) rsent[#rsent + 1] = {msg = msg, ch = ch, tgt = tgt}; return 0 end }
''')
realm_lua.execute((Path(__file__).resolve().parents[1] / 'Communication.lua').read_text(encoding='utf-8'))
realm_lua.execute('''
local c = OldKraken.Communication
c.ready = true
c.GetRosterVersion = function(_, name)
    if name == 'Базя Николаевич-Forever' or name == 'Базя Николаевич-Other' or name == 'Daythis Dru-Forever' or name == 'Alex-RealmA' or name == 'Alex-RealmB' then
        return '0.5.9-alpha.1'
    end
end
assert(type(chatUtilFilters.CHAT_MSG_SYSTEM) == 'function')

-- Send WHISPER to Name-Realm, receive short-name EN bounce -> must suppress, drop queue, and block only that Name-Realm for 10s
assert(c:SendProtocol('WRPAGE', string.rep('x', 200), 'Базя Николаевич-Forever'))
c:Pump()
assert(#rsent == 1 and rsent[1].tgt == 'Базя Николаевич-Forever')
assert(#c.queue > 1)
assert(chatUtilFilters.CHAT_MSG_SYSTEM(nil, 'CHAT_MSG_SYSTEM', "No player named 'Базя Николаевич' is currently playing.") == true)
assert(#c.queue == 0)

-- Subsequent send to same Name-Realm within 10s is blocked before SendAddonMessage
rnow = rnow + 5
assert(c:SendProtocol('WRPAGE', 'later', 'Базя Николаевич-Forever'))
c:Pump()
assert(#rsent == 1 and #c.queue == 0)

-- Other realm with same short name must NOT be blocked
assert(c:SendProtocol('WRPAGE', 'other', 'Базя Николаевич-Other'))
c:Pump()
assert(#rsent == 2 and rsent[2].tgt == 'Базя Николаевич-Other')

-- Ambiguous pending targets (Alex-RealmA and Alex-RealmB): short-name bounce must NOT drop or block either realm
rnow = rnow + 10
assert(c:SendProtocol('WRPAGE', 'a1', 'Alex-RealmA'))
c:Pump()
assert(c:SendProtocol('WRPAGE', 'b1', 'Alex-RealmB'))
c:Pump()
assert(c:SendProtocol('WRPAGE', string.rep('a', 200), 'Alex-RealmA'))
assert(c:SendProtocol('WRPAGE', string.rep('b', 200), 'Alex-RealmB'))
local qBeforeAmbig = #c.queue
assert(qBeforeAmbig > 0)
assert(chatUtilFilters.CHAT_MSG_SYSTEM(nil, 'CHAT_MSG_SYSTEM', "No player named 'Alex' is currently playing.") == false)
assert(#c.queue == qBeforeAmbig)
local sentBefore = #rsent
assert(c:SendProtocol('WRPAGE', 'a2', 'Alex-RealmA'))
assert(c:SendProtocol('WRPAGE', 'b2', 'Alex-RealmB'))
-- Drain queue to confirm neither Alex-RealmA nor Alex-RealmB was blocked
while #c.queue > 0 do c:Pump() end
local seenA, seenB = false, false
for i = sentBefore + 1, #rsent do
    if rsent[i].tgt == 'Alex-RealmA' then seenA = true end
    if rsent[i].tgt == 'Alex-RealmB' then seenB = true end
end
assert(seenA and seenB)

-- Ukrainian UALLF bounce pattern with Name-Realm target
rnow = rnow + 10
local sentBeforeUk = #rsent
assert(c:SendProtocol('WRPAGE', string.rep('y', 200), 'Daythis Dru-Forever'))
c:Pump()
assert(#rsent == sentBeforeUk + 1 and #c.queue > 1)
assert(chatUtilFilters.CHAT_MSG_SYSTEM(nil, 'CHAT_MSG_SYSTEM', "Гравця на ім'я «Daythis Dru» зараз немає в грі.") == true)
assert(#c.queue == 0)
''')

# Fallback registration: ChatFrameUtil.AddMessageEventFilter errors -> falls back to ChatFrame_AddMessageEventFilter
fb_lua = LuaRuntime(unpack_returned_tuples=True)
fb_lua.execute('''
fbFilters = {}
ChatFrameUtil = { AddMessageEventFilter = function() error('modern filter unavailable') end }
function ChatFrame_AddMessageEventFilter(ev, fn) fbFilters[ev] = fn end
ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
function CreateFrame() return {RegisterEvent=function() end, SetScript=function() end} end
function UnitName() return 'Tester' end
function IsInGuild() return true end
function GetGuildInfo() return 'Guild' end
function GetServerTime() return 1234567890 end
function GetTime() return 300 end
function strsplit(d, s) return s:match('^([^%^]*)%^([^%^]*)%^([^%^]*)%^([^%^]*)$') end
Enum = {SendAddonMessageResult = { Success=0 }}
C_ChatInfo = { SendAddonMessage=function() return 0 end }
''')
fb_lua.execute((Path(__file__).resolve().parents[1] / 'Communication.lua').read_text(encoding='utf-8'))
fb_lua.execute('''
assert(type(fbFilters.CHAT_MSG_SYSTEM) == 'function')
''')

print('Transport reliability regression checks passed')
