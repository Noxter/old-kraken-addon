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
assert(f.roleButton.mode=='badge' and #f.roleButton.allowedRoles==1 and f.roleButton.allowedRoles[1]=='dps')
assert(f.roleButton.badge:IsShown() and not f.roleButton.buttons[1]:IsShown())

-- Switch to a group in 'all' tab with multi-role capabilities and verify dungeon vs non-dungeon role context.
local Finder=OldKraken.GroupFinder
Finder.groups['Lead\\001d1']={owner='Lead',id='d1',category='dungeon',maxSize=5,members={'Lead'},role='tank',title='D1',description='',minLevel=1,maxLevel=60,updated=GetServerTime()}
Finder.groups['Lead\\001r1']={owner='Lead',id='r1',category='raid',maxSize=20,members={'Lead'},role='tank',title='R1',description='',minLevel=1,maxLevel=60,updated=GetServerTime()}
function UnitGetAvailableRoles(unit) if unit=='player' then return true,true,true end end
for _,entry in ipairs(f.tabs) do if entry.key=='all' then entry.button.scripts.OnClick() end end
f.searchFilter:SetText('D1')
f.searchFilter.scripts.OnTextChanged()
f.rows[1].scripts.OnClick()
assert(f.roleButton:IsShown() and f.roleButton.mode=='buttons' and #f.roleButton.allowedRoles==3, 'dungeon must expose 3 role buttons without flex')
assert(f.roleButton.buttons[1]:IsShown() and f.roleButton.buttons[2]:IsShown() and f.roleButton.buttons[3]:IsShown() and not f.roleButton.buttons[4]:IsShown())
f.roleButton.buttons[2].scripts.OnClick(f.roleButton.buttons[2])
assert(f.roleButton.selectedRole=='healer', 'clicking role segment must update shared role in one click')

-- Select raid group: flex becomes available because CanPerformRole('Me','flex') is true.
f.searchFilter:SetText('R1')
f.searchFilter.scripts.OnTextChanged()
f.rows[1].scripts.OnClick()
assert(f.roleButton.mode=='buttons' and #f.roleButton.allowedRoles==4 and f.roleButton.allowedRoles[4]=='flex')

-- Select flex in raid, then switch to dungeon: flex must be cleared and never sent to Finder:Apply.
f.roleButton.buttons[4].scripts.OnClick(f.roleButton.buttons[4])
assert(f.roleButton.selectedRole=='flex')

local origApply=Finder.Apply
local applyCalls={}
Finder.Apply=function(self,owner,id,chosenRole)
    applyCalls[#applyCalls+1]={owner=owner,id=id,role=chosenRole}
    return false
end
function f.applyButton:SetEnabled(v) self.enabled=v end

f.searchFilter:SetText('D1')
f.searchFilter.scripts.OnTextChanged()
f.rows[1].scripts.OnClick()
local hasFlex=false
for _,r in ipairs(f.roleButton.allowedRoles) do if r=='flex' then hasFlex=true end end
assert(not hasFlex, 'flex must not appear in dungeon allowedRoles')
assert(f.roleButton.selectedRole~='flex' and (f.roleButton.selectedRole=='tank' or f.roleButton.selectedRole=='healer' or f.roleButton.selectedRole=='dps'))
assert(f.applyButton:IsShown() and f.applyButton.enabled==true)
f.applyButton.scripts.OnClick(f.applyButton)
assert(#applyCalls==1 and applyCalls[1].role==f.roleButton.selectedRole and applyCalls[1].role~='flex')

-- Valid role click passes exact selected role to Finder:Apply.
f.roleButton.buttons[2].scripts.OnClick(f.roleButton.buttons[2])
assert(f.roleButton.selectedRole=='healer')
f.applyButton.scripts.OnClick(f.applyButton)
assert(#applyCalls==2 and applyCalls[2].role=='healer')

-- Restrict native roles to 2 in dungeon context, then 0: UI updates on refresh and spy proves Finder:Apply is never called.
function UnitGetAvailableRoles(unit) if unit=='player' then return true,false,true end end
f.searchFilter.scripts.OnTextChanged()
assert(f.roleButton.mode=='buttons' and #f.roleButton.allowedRoles==2 and f.roleButton.selectedRole==Finder:PreferredRole())

function UnitGetAvailableRoles(unit) if unit=='player' then return false,false,false end end
f.searchFilter.scripts.OnTextChanged()
assert(f.roleButton.mode=='none' and f.roleButton.selectedRole=='' and f.roleButton.badge:IsShown())
assert(f.applyButton:IsShown() and f.applyButton.enabled==false, 'applyButton must be disabled when 0 roles are available')
local callsBeforeNone=#applyCalls
f.applyButton.scripts.OnClick(f.applyButton)
assert(#applyCalls==callsBeforeNone, '0 available roles must not invoke Finder:Apply')

-- Check applyButton hidden when already applied, closed, or no group selected.
function UnitGetAvailableRoles(unit) if unit=='player' then return true,true,true end end
Finder.pending['Lead\\001d1']='pending'
f.searchFilter.scripts.OnTextChanged()
assert(not f.applyButton:IsShown(), 'applyButton must be hidden when application is pending')
Finder.pending['Lead\\001d1']=nil
Finder.groups['Lead\\001d1'].closed=true
f.searchFilter.scripts.OnTextChanged()
assert(not f.applyButton:IsShown(), 'applyButton must be hidden when group is closed')
f.searchFilter:SetText('__nonexistent__')
f.searchFilter.scripts.OnTextChanged()
assert(not f.applyButton:IsShown(), 'applyButton must be hidden when no group is selected')

Finder.Apply=origApply
''')
print('PASS: native role APIs, no class assumptions, changing capabilities, role payload, remote acceptance, live-unit precedence, API fallback and UI restrictions')
