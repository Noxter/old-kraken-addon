"""Group Finder teardown must not destroy other subsystems' protocol traffic.

deactivate() calls Communication:ClearProtocolState(), which currently drops every
queued GF2^ message: Workshop Sync pages and Guild Events announcements as well as
Group Finder's own. It also discards inbound reassembly buffers for all kinds.
"""

from pathlib import Path

from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
OldKraken = {DB = {groupFinder = {}}, events = {}}
function OldKraken:Fire() end
function OldKraken:On() end
guild = 'Guild'
function GetGuildInfo() return guild end
function GetRealmName() return 'Realm' end
function UnitName() return 'Hok', 'Realm' end
function GetServerTime() return 1700000000 end
function GetTime() return 100 end
function IsInGuild() return true end
Enum = {SendAddonMessageResult = {Success = 0}}
sentMessages = {}
C_ChatInfo = {SendAddonMessage = function(_, message) sentMessages[#sentMessages + 1] = message; return 0 end}
C_Timer = {NewTicker = function(_, fn) tick = fn end}
function CreateFrame()
    local frame = {scripts = {}}
    function frame:RegisterEvent() end
    function frame:SetScript(name, fn) self.scripts[name] = fn; login = fn end
    return frame
end
''')
for name in ['Communication.lua', 'GroupFinder.lua', 'GroupFinderIntegration.lua']:
    lua.execute((root / name).read_text(encoding='utf-8'))
lua.execute(r'''
local comm = OldKraken.Communication
comm.ready = true
login() -- activate the Group Finder integration so teardown has state to clear

-- Group Finder teardown is triggered by a profile change (guild/realm/identity).
local function deactivateGroupFinder()
    guild = 'Other guild'
    login()
end

local function queued(kind)
    local count = 0
    for _, entry in ipairs(comm.queue) do
        if entry.message:match('^GF2%^([A-Z]+)%^') == kind then count = count + 1 end
    end
    return count
end

assert(comm:SendProtocol('WRPAGE', 'workshop page'))
assert(comm:SendProtocol('CEVENT', 'guild event'))
assert(comm:SendProtocol('ANNOUNCE', 'group announce'))
assert(queued('WRPAGE') == 1 and queued('CEVENT') == 1 and queued('ANNOUNCE') == 1)

deactivateGroupFinder()

assert(queued('WRPAGE') == 1, 'Group Finder teardown dropped queued Workshop Sync traffic')
assert(queued('CEVENT') == 1, 'Group Finder teardown dropped queued Guild Events traffic')
assert(queued('ANNOUNCE') == 0, 'Group Finder teardown must clear its own queued traffic')
''')
lua.execute(r'''
local comm = OldKraken.Communication
comm.ready = true
received = 0
comm:RegisterHandler('WRPAGE', function() received = received + 1 end)
-- First half of a two-part Workshop Sync page from another player.
local part = string.rep('x', 80)
local hex = part:gsub('.', function(c) return string.format('%02X', string.byte(c)) end)
comm:OnAddonMessage(comm.PREFIX, 'GF2^WRPAGE^1700000000-1-1^1^2^' .. hex, 'GUILD', 'Peer')

guild = 'Third guild'
login()

comm:OnAddonMessage(comm.PREFIX, 'GF2^WRPAGE^1700000000-1-1^2^2^' .. hex:sub(1, 2), 'GUILD', 'Peer')
assert(received == 1, 'Group Finder teardown discarded a partially received Workshop Sync page')
''')
print('Protocol state scope checks passed')
