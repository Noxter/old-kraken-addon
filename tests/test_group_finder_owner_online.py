"""An unknown group owner must not be treated as offline.

pruneOfflineApplications() removes a pending application once
OFFLINE_APPLICATION_TTL elapses. isOwnerOnline() answers "offline" whenever the
owner is missing from `people`, so any name-representation mismatch between the
guild roster (Name-Realm) and the model identity (Name Realm) silently discards a
valid application while the owner is online.
"""

from pathlib import Path

from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
ui = (root / "GroupFinderUI.lua").read_text(encoding="utf-8")
start = "local OFFLINE_APPLICATION_TTL = 300"
end = "refreshPeople = function()"
block = ui.split(start, 1)[1].split(end, 1)[0]

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(
    """
local NOW = 1000
local GetTime = function() return NOW end
local Finder = {identity = 'Me Realm', pending = {}, pendingVersions = {}, pendingRoles = {}, groups = {},
    Changed = function(self) end}
"""
    + start
    + block
    + r"""
local KEY = 'Owner Realm\001g1'
local function reset(roster, elapsed)
    people = roster
    guildRosterLoaded = true
    -- The owner was first seen as offline `elapsed` seconds ago.
    ownerOfflineSince = {[KEY] = NOW - (elapsed or 400)}
    Finder.pending = {[KEY] = 'apply'}
    Finder.pendingVersions = {[KEY] = 1}
    Finder.pendingRoles = {[KEY] = 'dps'}
    Finder.groups = {[KEY] = {owner = 'Owner Realm', id = 'g1'}}
end

-- Same person under the roster's own key format: online, so the application stays.
reset({['Owner-Realm'] = {online = true}})
pruneOfflineApplications()
assert(Finder.pending[KEY] ~= nil,
    'an owner known online under another name representation must not be pruned')

-- Owner absent from the roster data entirely: unknown is not the same as offline.
reset({})
pruneOfflineApplications()
assert(Finder.pending[KEY] ~= nil,
    'an owner missing from the roster must not be pruned as if offline')

-- Genuinely offline owner still expires: the 5-minute prune must keep working.
reset({['Owner Realm'] = {online = false}})
pruneOfflineApplications()
assert(Finder.pending[KEY] == nil, 'an owner confirmed offline must still be pruned after the TTL')
assert(Finder.pendingVersions[KEY] == nil and Finder.pendingRoles[KEY] == nil)

-- Normalisation must not match a different realm's character with the same name,
-- even when that other entry is offline: a false match would prune a live
-- application.
reset({['Owner-Realm2'] = {online = false}})
pruneOfflineApplications()
assert(Finder.pending[KEY] ~= nil,
    'a same-named character from another realm must not count as this owner')

-- A confirmed-offline owner is pruned only once the full TTL has elapsed.
reset({['Owner-Realm'] = {online = false}}, 100)
pruneOfflineApplications()
assert(Finder.pending[KEY] ~= nil, 'an offline owner must not be pruned before the TTL elapses')
assert(ownerOfflineSince[KEY] == NOW - 100,
    'the offline window must keep counting from when the owner was first seen offline')
"""
)
print("Group Finder owner online-state checks passed")
