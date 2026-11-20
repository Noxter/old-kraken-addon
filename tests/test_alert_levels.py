from pathlib import Path
import runpy
root=Path(__file__).resolve().parents[1]
lua=runpy.run_path(str(root/'tests/test_ui_smoke.py'))['lua']
lua.execute('''
local alert
for _,frame in ipairs(createdFrames) do if rawget(frame,'alertCaption') then alert=frame end end
local group={id='levels',owner='Level Owner',title='Level test',category='dungeon',dungeon='rfc',role='tank',maxSize=5,minLevel=13,maxLevel=18,members={'Level Owner'},memberRoles={}}
OldKraken.GroupFinder.groups[group.owner..'\\001'..group.id]=group
for _,level in ipairs({12,13,18,19,0}) do
    function UnitLevel() return level end
    alert:Hide()
    OldKraken.listeners.GROUP_FINDER_NEW(group)
    assert(alert:IsShown()==(level>=13 and level<=18),'level boundary '..level)
end
UnitLevel=nil; alert:Hide(); OldKraken.listeners.GROUP_FINDER_NEW(group); assert(not alert:IsShown())
group.category='quest'; alert:Hide(); OldKraken.listeners.GROUP_FINDER_NEW(group); assert(not alert:IsShown())
function UnitLevel() return 12 end
alert:Hide(); OldKraken.listeners.GROUP_FINDER_NEW(group); assert(not alert:IsShown())
function UnitLevel() return 15 end
alert:Hide(); OldKraken.listeners.GROUP_FINDER_NEW(group); assert(alert:IsShown())
group.minLevel, group.maxLevel = 1, 60
function UnitLevel() return 5 end
alert:Hide(); OldKraken.listeners.GROUP_FINDER_NEW(group); assert(alert:IsShown())
''')
print('PASS: group alerts respect inclusive level bounds across categories; unknown levels suppressed')
