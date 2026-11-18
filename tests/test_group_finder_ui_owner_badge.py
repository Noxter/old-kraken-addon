"""The Group Finder UI must show the offline badge only for a confirmed offline owner.

Both decisions that depend on the owner's state are read out of GroupFinderUI.lua
and executed, so the test covers the expressions the window actually uses: the
badge that turns an application row into "ОФЛАЙН" and the tab counter that feeds
SetBadge('applications'). An unknown owner is neither online nor offline, so it
must not be badged offline and must not be dropped from the counter.
"""

import re
from pathlib import Path

from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
ui = (root / "GroupFinderUI.lua").read_text(encoding="utf-8")

# The owner-state helpers, sliced exactly as the window sees them.
start = "local OFFLINE_APPLICATION_TTL = 300"
end = "refreshPeople = function()"
block = ui.split(start, 1)[1].split(end, 1)[0]

badge = re.search(r"^\s+local offline = (.+)$", ui, re.M)
assert badge, "the application badge no longer takes a local `offline` decision"
badge_expr = badge.group(1)

counter = re.search(r"^\s+if group and (.+?) then pendingApplications = pendingApplications \+ 1 end$",
                    ui, re.M)
assert counter, "the applications counter no longer has a per-application condition"
counter_expr = counter.group(1)

# The extracted decision must be the one that paints the label, not a leftover.
assert "b.status:SetText(offline and 'ОФЛАЙН' or badge.text)" in ui, \
    "the offline label is no longer driven by the `offline` decision"

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
    + """
function BadgeVisible(owner)
    local g = {owner = owner}
    local offline = """
    + badge_expr
    + """
    local shown = offline and true or false
    return shown
end

function Counted(owner)
    local group = {owner = owner}
    local pendingApplications = 0
    if group and """
    + counter_expr
    + """ then pendingApplications = pendingApplications + 1 end
    return pendingApplications
end

local function roster(entries)
    people = entries
    guildRosterLoaded = true
end

-- Owner confirmed online: no badge, application counted.
roster({['Owner-Realm'] = {online = true}})
assert(BadgeVisible('Owner Realm') == false, 'an online owner must not show the offline badge')
assert(Counted('Owner Realm') == 1, 'an online owner must be counted')

-- Owner confirmed offline: badged as offline, left out of the counter.
roster({['Owner-Realm'] = {online = false}})
assert(BadgeVisible('Owner Realm') == true, 'a confirmed offline owner must show the offline badge')
assert(Counted('Owner Realm') == 0, 'a confirmed offline owner must be left out of the counter')

-- Owner unknown (absent from the roster): no badge, still counted.
roster({})
assert(BadgeVisible('Owner Realm') == false, 'an unknown owner must not show the offline badge')
assert(Counted('Owner Realm') == 1, 'an unknown owner must not be dropped from the counter')

-- Owner unknown because only another realm's namesake is known and offline.
roster({['Owner-Realm2'] = {online = false}})
assert(BadgeVisible('Owner Realm') == false, 'a namesake on another realm must not badge this owner')
assert(Counted('Owner Realm') == 1, 'a namesake on another realm must not drop this application')

-- Own application rows keep working before the roster is available.
people, guildRosterLoaded = {}, false
assert(BadgeVisible('Owner Realm') == false and Counted('Owner Realm') == 1)
"""
)
print("Group Finder UI owner-state checks passed")
