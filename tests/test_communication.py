from pathlib import Path

from lupa.lua51 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
messages = {}
function print(...) end
function CreateFrame() return {RegisterEvent=function() end, SetScript=function() end} end
function UnitName() return 'Tester' end
function IsInGuild() return true end
function GetServerTime() return 1234567890 end
function GetTime() return 100 end
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
for i=1,5 do c:Pump() end
assert(#c.queue == 0 and c.stats.dropped == 1)
result = 0
c:SendTest()
c:Pump()
assert(messages[#messages]:match('^TEST%^'))
c:OnAddonMessage(c.PREFIX, 'TEST^id^Other^Other', 'GUILD', 'Other')
c:Pump()
assert(messages[#messages]:match('^ACK%^id%^Other%^Tester$'))
local calls = 0
assert(c:RegisterHandler('SYNC', function(sender, id, payload) calls = calls + 1; assert(payload == string.rep('ж', 100)) end))
assert(c:SendProtocol('SYNC', string.rep('ж', 100)))
local parts = {}
for i, entry in ipairs(c.queue) do parts[i] = entry.message end
assert(#parts == 3)
c:OnAddonMessage(c.PREFIX, parts[3], 'GUILD', 'Other')
c:OnAddonMessage(c.PREFIX, parts[1], 'GUILD', 'Other')
c:OnAddonMessage(c.PREFIX, parts[1], 'GUILD', 'Other')
assert(calls == 0)
c:OnAddonMessage(c.PREFIX, parts[2], 'GUILD', 'Other')
assert(calls == 1)
c:OnAddonMessage(c.PREFIX, parts[2], 'GUILD', 'Other')
assert(calls == 1)
assert(c:RequestSync())
''')
print('Communication checks passed')

