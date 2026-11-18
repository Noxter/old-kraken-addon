from pathlib import Path
from lupa.lua51 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('OldKraken = {}; now = 10; function GetTime() return now end; function GetServerTime() return 1234567890 end')
lua.execute((Path(__file__).resolve().parents[1] / 'GroupFinder.lua').read_text(encoding='utf-8'))
lua.execute('''
local model = OldKraken.GroupFinder
local sent = {}
model:Initialize('Alice-Realm', function(kind, payload) sent[#sent+1] = {kind,payload}; return true end)
assert(model.Edit == nil)
assert(model:Create('Печера', 'dungeon', 'Рівень 20+', 5, 1, 60, 'tank'))
local group
for _, g in pairs(model.groups) do group = g end
assert(group and group.owner == 'Alice-Realm')
assert(model:RoleAvailable(group, 'healer'))
assert(not model:RoleAvailable(group, 'tank'))
assert(not model:RoleAvailable(group, 'flex'))
local snapshot = model:EncodeGroup(group)
local clone = {}
setmetatable(clone, {__index = model})
clone:Initialize('Bob-Realm', function() return true end)
assert(not clone:ReceiveGroup('Mallory-Realm', snapshot))
assert(clone:ReceiveGroup('Alice-Realm', snapshot))
assert(not clone:ReceiveGroup('Alice-Realm', snapshot))
now = 100
assert(not clone:ReceiveGroup('Alice-Realm', snapshot))
assert(clone.groups['Alice-Realm' .. '\\001' .. group.id].seenAt == 100)
local applicationKey = 'Alice-Realm' .. '\\001' .. group.id
clone.pending[applicationKey] = 'pending'
clone.pendingVersions[applicationKey], clone.pendingRoles[applicationKey] = 1234567890001, 'healer'
assert(model:ReceiveJoin('Bob-Realm', model._pack({'Alice-Realm', group.id, 'healer', 'apply', '1234567890001'})))
assert(model:ReceiveJoin('Eve-Realm', model._pack({'Alice-Realm', group.id, '', 'withdraw', '1234567890002'})))
assert(not model:ReceiveJoin('Eve-Realm', model._pack({'Alice-Realm', group.id, '', 'apply', '1234567890001'})))
assert(model:Decide(group.id, 'Bob-Realm', true))
assert(#group.members == 2 and group.revision == 2)
assert(not model:RoleAvailable(group, 'healer'))
assert(model:RoleAvailable(group, 'dps'))
assert(clone:ReceiveGroup('Alice-Realm', model:EncodeGroup(group)))
assert(clone.pending[applicationKey] == nil)
assert(clone.pendingVersions[applicationKey] == nil and clone.pendingRoles[applicationKey] == nil)
clone.pending[applicationKey] = 'pending'
clone.pendingVersions[applicationKey], clone.pendingRoles[applicationKey] = 1234567890002, 'healer'
assert(clone:ReceiveResponse('Alice-Realm', model._pack({'Alice-Realm', group.id, 'Bob-Realm', 'reject', '1234567890002'})))
assert(clone.pending[applicationKey] == 'reject')
assert(clone.pendingVersions[applicationKey] == nil and clone.pendingRoles[applicationKey] == nil)
assert(clone:DismissApplication('Alice-Realm', group.id))
assert(clone.pending[applicationKey] == nil)
assert(not clone:ReceiveGroup('Mallory-Realm', model:EncodeGroup(group)))
assert(not model:ReceiveJoin('Mallory-Realm', 'garbage'))
local blocked, attempts = true, 0
model.send = function(kind, payload)
    if kind == 'SYNC' then attempts = attempts + 1; return not blocked end
    return true
end
model:OnQuery()
assert(not model:SyncStep() and attempts == 1)
blocked = false
assert(model:SyncStep() and attempts == 2)
assert(model:SyncStep() and attempts == 2)
assert(model:Cancel(group.id))
assert(clone:ReceiveGroup('Alice-Realm', model:EncodeGroup(group)))
assert(clone.groups['Alice-Realm' .. '\\001' .. group.id].closed)
assert(not clone:ReceiveGroup('Alice-Realm', snapshot))
now = 4000
clone:Prune()
assert(clone.groups['Alice-Realm' .. '\\001' .. group.id] == nil)
assert(model:Create('Нова група', 'dungeon', 'Інше підземелля', 5, 25, 35, 'healer', 'wc'))
local replacement
for _, g in pairs(model.groups) do if g.title == 'Нова група' then replacement = g end end
assert(group.closed and replacement and replacement.id ~= group.id)
assert(replacement.dungeon == 'wc' and replacement.title == 'Нова група')
local sentUpdates = 0
local allowUpdateSend = true
local origSend = model.send
model.send = function(kind, payload)
    if kind == 'UPDATE' then
        if not allowUpdateSend then return false end
        sentUpdates = sentUpdates + 1
    end
    return origSend(kind, payload)
end
assert(model:UpdateDescription(replacement.id, 'Оновлений опис групи'))
assert(replacement.description == 'Оновлений опис групи' and sentUpdates == 1)
local prevRev = replacement.revision
allowUpdateSend = false
local okRollback = model:UpdateDescription(replacement.id, 'Неуспішний опис')
assert(not okRollback and replacement.description == 'Оновлений опис групи' and replacement.revision == prevRev,
    'UpdateDescription did not roll back description and revision on send failure')
''')

print('Group model checks passed')
