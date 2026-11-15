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
