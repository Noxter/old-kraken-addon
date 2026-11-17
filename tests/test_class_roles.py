"""Role eligibility comes from game API responses, never a class-name table."""
from pathlib import Path
import runpy
from lupa.lua51 import LuaRuntime

root=Path(__file__).resolve().parents[1]
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
OldKraken={}; gameRoles={tank=false,healer=false,dps=true}
function GetServerTime() return 1700000000 end
function GetTime() return 100 end
function UnitClass() return 'Warlock','WARLOCK' end
function UnitGetAvailableRoles(unit)
    if unit=='player' then return gameRoles.tank,gameRoles.healer,gameRoles.dps end
end
sent={}
''')
lua.execute((root/'GroupFinder.lua').read_text(encoding='utf-8'))
lua.execute('''
local f=OldKraken.GroupFinder
f:Initialize('Me',function(kind,payload) sent[#sent+1]={kind,payload}; return true end)
assert(not f:CanPerformRole('Me','tank') and not f:CanPerformRole('Me','healer') and f:CanPerformRole('Me','dps'))
assert(not f:Create('Invalid','dungeon','',5,1,60,'tank'))
-- Even though UnitClass still reports WARLOCK, native game roles are authoritative.
gameRoles={tank=true,healer=false,dps=false}
assert(f:CanPerformRole('Me','tank') and not f:CanPerformRole('Me','dps'))
assert(f:PreferredRole()=='tank')
local ok,id=f:Create('Native','dungeon','',5,1,60,'tank'); assert(ok)
local function join(name,role,code,version)
    return f:ReceiveJoin(name,f._pack({'Me',id,role,'apply',tostring(version),code}))
end
assert(not join('Remote','healer','001',1))
assert(join('Remote','dps','001',1))
assert(f:CanPerformRole('Remote','dps') and not f:CanPerformRole('Remote','tank'))
assert(join('Healer','healer','010',1))
assert(f:Decide(id,'Healer',true))
f.requests[id]['Remote']='tank'; assert(not f:Decide(id,'Remote',true))
assert(not join('Bad','dps','garbage',1))
assert(not f:CanPerformRole('Unknown','tank'),'unknown native data must not be guessed')
-- A directly visible game unit overrides capabilities reported in a message.
function UnitExists(unit) return unit=='Visible' end
local native=UnitGetAvailableRoles
function UnitGetAvailableRoles(unit) if unit=='Visible' then return false,false,true end; return native(unit) end
assert(not join('Visible','tank','111',1))
f.groups['Owner\\001remote']={owner='Owner',id='remote',category='dungeon',maxSize=5,members={'Owner'},role='tank'}
gameRoles={tank=false,healer=true,dps=false}
assert(f:Apply('Owner','remote','healer'))
local fields=f._unpackFields(sent[#sent][2],6)
assert(fields[6]=='010' and fields[3]=='healer')
assert(not f:Apply('Owner','remote','dps'))
-- Fallback native API is used when UnitGetAvailableRoles supplies nothing.
UnitGetAvailableRoles=nil
C_LFGList={GetAvailableRoles=function() return false,true,false end}
assert(f:CanPerformRole('Me','healer') and not f:CanPerformRole('Me','tank'))
''')
ui=runpy.run_path(str(root/'tests/test_ui_smoke.py'))['lua']
ui.execute('''
function UnitGetAvailableRoles(unit) if unit=='player' then return false,false,true end end
local f=OldKrakenGroupFinderFrame
for _,control in ipairs(f.creationRoles) do function control:SetEnabled(value) self.enabled=value end end
for _,entry in ipairs(f.tabs) do if entry.key=='create' then entry.button.scripts.OnClick() end end
assert(not f.creationRoles[1].enabled and not f.creationRoles[2].enabled and f.creationRoles[3].enabled)
dropdownItems={}; f.roleButton.dropdownInit(f.roleButton,1)
for _,item in ipairs(dropdownItems) do assert(item.value~='tank' and item.value~='healer') end
''')
print('PASS: native role APIs, no class assumptions, changing capabilities, role payload, remote acceptance, live-unit precedence, API fallback and UI restrictions')
