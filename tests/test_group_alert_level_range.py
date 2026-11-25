from pathlib import Path
import runpy

root = Path(__file__).resolve().parents[1]
lua = runpy.run_path(str(root / 'tests/test_ui_smoke.py'))['lua']
lua.execute('''
local alert
for _, frame in ipairs(createdFrames) do
    if rawget(frame, 'alertCaption') then
        alert = frame
        break
    end
end
assert(alert, 'alert frame not found')

local function fireGroup(opts, playerLevel)
    if type(playerLevel) == 'function' then
        UnitLevel = playerLevel
    elseif playerLevel == false then
        UnitLevel = nil
    else
        UnitLevel = function() return playerLevel end
    end
    local group = {
        id = opts.id or 'lvl-range',
        owner = opts.owner or 'Range Owner',
        title = opts.title or 'Range test',
        category = opts.category or 'dungeon',
        dungeon = opts.dungeon,
        role = 'tank',
        maxSize = opts.maxSize or 5,
        minLevel = opts.minLevel,
        maxLevel = opts.maxLevel,
        members = {'Range Owner'},
        memberRoles = {},
    }
    OldKraken.GroupFinder.groups[group.owner .. '\\001' .. group.id] = group
    alert:Hide()
    OldKraken.listeners.GROUP_FINDER_NEW(group)
    return alert:IsShown()
end

-- 1-2. ESW (24-29), group 24-60: 27 shown, 42 suppressed
assert(fireGroup({dungeon = 'excavation', minLevel = 24, maxLevel = 60}, 27), '1. ESW 24-60 level 27 must show')
assert(not fireGroup({dungeon = 'excavation', minLevel = 24, maxLevel = 60}, 42), '2. ESW 24-60 level 42 must hide')

-- 3-4. ESW (24-29), group 26-28: 25 suppressed, 27 shown
assert(not fireGroup({dungeon = 'excavation', minLevel = 26, maxLevel = 28}, 25), '3. ESW 26-28 level 25 must hide')
assert(fireGroup({dungeon = 'excavation', minLevel = 26, maxLevel = 28}, 27), '4. ESW 26-28 level 27 must show')

-- 5-6. RFC (13-18), group 13-60: 20 suppressed, 15 shown
assert(not fireGroup({dungeon = 'rfc', minLevel = 13, maxLevel = 60}, 20), '5. RFC 13-60 level 20 must hide')
assert(fireGroup({dungeon = 'rfc', minLevel = 13, maxLevel = 60}, 15), '6. RFC 13-60 level 15 must show')

-- 7. Legacy activity with defined bounds (sm: 30-46), group 1-60
assert(not fireGroup({dungeon = 'sm', minLevel = 1, maxLevel = 60}, 29), '7a. Legacy SM 1-60 level 29 must hide')
assert(fireGroup({dungeon = 'sm', minLevel = 1, maxLevel = 60}, 30), '7b. Legacy SM 1-60 level 30 must show')
assert(fireGroup({dungeon = 'sm', minLevel = 1, maxLevel = 60}, 46), '7c. Legacy SM 1-60 level 46 must show')
assert(not fireGroup({dungeon = 'sm', minLevel = 1, maxLevel = 60}, 47), '7d. Legacy SM 1-60 level 47 must hide')

-- 8. Raid with defined bounds (onyxia: 60-60), group 1-60
assert(not fireGroup({category = 'raid', dungeon = 'onyxia', maxSize = 40, minLevel = 1, maxLevel = 60}, 59), '8a. Raid Onyxia 1-60 level 59 must hide')
assert(fireGroup({category = 'raid', dungeon = 'onyxia', maxSize = 40, minLevel = 1, maxLevel = 60}, 60), '8b. Raid Onyxia 1-60 level 60 must show')

-- 9. Custom activity without catalog ID (and non-dungeon/raid category): preserves group-only filtering
assert(not fireGroup({category = 'dungeon', dungeon = 'custom-unknown', minLevel = 20, maxLevel = 50}, 19), '9a. Custom dungeon level 19 must hide')
assert(fireGroup({category = 'dungeon', dungeon = 'custom-unknown', minLevel = 20, maxLevel = 50}, 20), '9b. Custom dungeon level 20 must show')
assert(fireGroup({category = 'dungeon', dungeon = '', minLevel = 20, maxLevel = 50}, 50), '9c. Empty dungeon level 50 must show')
assert(not fireGroup({category = 'quest', dungeon = 'excavation', minLevel = 20, maxLevel = 50}, 19), '9d. Quest category level 19 must hide')
assert(fireGroup({category = 'quest', dungeon = 'excavation', minLevel = 20, maxLevel = 50}, 42), '9e. Quest category level 42 must show')

-- 10. Missing or invalid UnitLevel -> suppressed for group with defined range
assert(not fireGroup({dungeon = 'excavation', minLevel = 24, maxLevel = 60}, false), '10a. Missing UnitLevel must hide')
assert(not fireGroup({dungeon = 'excavation', minLevel = 24, maxLevel = 60}, function() return nil end), '10b. nil UnitLevel must hide')
assert(not fireGroup({dungeon = 'excavation', minLevel = 24, maxLevel = 60}, 0), '10c. 0 UnitLevel must hide')
assert(not fireGroup({dungeon = 'excavation', minLevel = 24, maxLevel = 60}, -1), '10d. -1 UnitLevel must hide')
assert(not fireGroup({dungeon = 'excavation', minLevel = 24, maxLevel = 60}, function() return 'bad' end), '10e. Non-numeric UnitLevel must hide')

-- 11. Non-overlapping group range vs activity range (ESW 24-29, group 40-60)
assert(not fireGroup({dungeon = 'excavation', minLevel = 40, maxLevel = 60}, 27), '11a. Non-overlapping ESW 40-60 level 27 must hide')
assert(not fireGroup({dungeon = 'excavation', minLevel = 40, maxLevel = 60}, 45), '11b. Non-overlapping ESW 40-60 level 45 must hide')

-- 12. Disabled Group Finder alerts -> suppressed regardless of matching level
local origGroupAlertsEnabled = OldKraken.GroupFinder.GroupAlertsEnabled
OldKraken.GroupFinder.GroupAlertsEnabled = function() return false end
assert(not fireGroup({dungeon = 'excavation', minLevel = 24, maxLevel = 60}, 27), '12. Disabled alerts must hide even when level matches')
OldKraken.GroupFinder.GroupAlertsEnabled = origGroupAlertsEnabled

-- 13. Partially specified group bounds with catalog activity -> still enforces catalog bounds
assert(not fireGroup({dungeon = 'excavation', minLevel = nil, maxLevel = 60}, 42), '13a. nil minLevel ESW level 42 must hide')
assert(fireGroup({dungeon = 'excavation', minLevel = nil, maxLevel = 60}, 27), '13b. nil minLevel ESW level 27 must show')
assert(not fireGroup({dungeon = 'excavation', minLevel = 26, maxLevel = nil}, 25), '13c. nil maxLevel ESW level 25 must hide')
assert(fireGroup({dungeon = 'excavation', minLevel = 26, maxLevel = nil}, 29), '13d. nil maxLevel ESW level 29 must show')

-- 14. Category mismatch (e.g. raid with dungeon ID) -> ignores mismatched catalog range, uses group range
assert(fireGroup({category = 'raid', dungeon = 'excavation', minLevel = 24, maxLevel = 60}, 42), '14a. Raid with dungeon ID must use group range')
assert(not fireGroup({category = 'dungeon', dungeon = 'onyxia', minLevel = 20, maxLevel = 30}, 60), '14b. Dungeon with raid ID must use group range')
''')
print('PASS: group alert activity level range intersection checks passed')
