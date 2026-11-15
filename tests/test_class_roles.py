from pathlib import Path
from lupa.lua51 import LuaRuntime
import runpy

root=Path(__file__).resolve().parents[1]
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
OldKraken={}; now=1700000000
function GetServerTime() return now end
function GetTime() return 100 end
localClass='WARLOCK'
function UnitClass() return 'Class',localClass end
reads=0
function GetNumGuildMembers() return 3 end
function GetGuildRosterInfo(i)
    reads=reads+1
    local names={'Lock','Priest','Warrior'}
    local classes={'WARLOCK','PRIEST','WARRIOR'}
    return names[i],'Member',0,60,'Class','Zone',nil,nil,true,'',classes[i]
end
''')
lua.execute((root/'GroupFinder.lua').read_text(encoding='utf-8'))
lua.execute('''
local f=OldKraken.GroupFinder
f:Initialize('Me',function() return true end)
assert(not f:CanPerformRole('Me','tank') and not f:CanPerformRole('Me','healer'))
assert(f:CanPerformRole('Me','dps'))
assert(not f:Create('Invalid','dungeon','',5,1,60,'tank'))
assert(not f:Create('Invalid','dungeon','',5,1,60,'healer'))
local tanks={WARRIOR=true,PALADIN=true,DRUID=true}
local healers={PRIEST=true,PALADIN=true,DRUID=true,SHAMAN=true}
for _,class in ipairs({'WARRIOR','PALADIN','DRUID','PRIEST','SHAMAN','HUNTER','ROGUE','MAGE','WARLOCK'}) do
    localClass=class
    assert(f:CanPerformRole('Me','tank')==(tanks[class]==true))
    assert(f:CanPerformRole('Me','healer')==(healers[class]==true))
end
localClass='WARRIOR'
local ok,id=f:Create('Valid','dungeon','',5,1,60,'tank'); assert(ok)
local function join(name,role,version)
    return f:ReceiveJoin(name,f._pack({'Me',id,role,'apply',tostring(version)}))
end
assert(not join('Lock','tank',1))
assert(not join('Lock','healer',1))
assert(join('Lock','dps',1))
assert(join('Priest','healer',1))
assert(not join('Warrior','healer',1))
assert(f:Decide(id,'Priest',true))
f.requests[id]['Lock']='tank'
assert(not f:Decide(id,'Lock',true),'persisted or injected invalid roles must not be accepted')
local before=reads
for i=1,500 do f:CanPerformRole('Lock','healer') end
assert(reads==before,'must cache the guild class index')
f.groups['Warrior\\001remote']={id='remote',owner='Warrior',category='dungeon',maxSize=5,members={'Warrior'},role='tank'}
localClass='WARLOCK'
assert(not f:Apply('Warrior','remote','healer'))
assert(f:Apply('Warrior','remote','dps'))
''')
print('PASS: nine-class role matrix, create/apply/receive/accept enforcement and cached 500-member lookup workload')
ui_lua=runpy.run_path(str(root/'tests/test_ui_smoke.py'))['lua']
ui_lua.execute('''
function UnitClass() return 'Warlock','WARLOCK' end
local ui=OldKrakenGroupFinderFrame
for _,control in ipairs(ui.creationRoles) do function control:SetEnabled(value) self.enabled=value end end
for _,entry in ipairs(ui.tabs) do if entry.key=='create' then entry.button.scripts.OnClick() end end
assert(not ui.creationRoles[1].enabled and not ui.creationRoles[2].enabled and ui.creationRoles[3].enabled)
dropdownItems={}; ui.roleButton.dropdownInit(ui.roleButton,1)
for _,item in ipairs(dropdownItems) do assert(item.value~='tank' and item.value~='healer') end
''')
print('PASS: Warlock creation buttons and application role menu exclude tank/healer')
