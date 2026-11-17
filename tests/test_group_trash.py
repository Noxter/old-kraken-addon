from pathlib import Path
import runpy
root=Path(__file__).resolve().parents[1]
lua=runpy.run_path(str(root/'tests/test_ui_smoke.py'))['lua']
lua.execute('''
local f=OldKraken.GroupFinder
local sent={}
f:Initialize('Tester',function(kind,payload) sent[#sent+1]=kind; return true end)
f.active=true
local ok,id=f:Create('Delete my group','quest','',5,1,60,'dps',''); assert(ok)
local key=f.identity..'\\001'..id
local ui=OldKrakenGroupFinderFrame
local function mine()
    for _,item in ipairs(ui.tabs) do if item.key=='mine' then item.button.scripts.OnClick(); return end end
end
mine()
local remove=ui.deleteButtons[1]
assert(remove:IsShown() and remove.parent==ui.rows[1],'trash must be inside the clipped card')
remove.scripts.OnClick()
assert(f.groups[key].hidden and f.groups[key].closed)
assert(sent[#sent]=='CANCEL','open listing deletion must synchronize cancellation')
assert(#ui.visible==0)
local ok,closedId=f:Create('Already closed','quest','',5,1,60,'dps',''); assert(ok)
assert(f:Cancel(closedId)); mine()
assert(ui.deleteButtons[1]:IsShown(),'closed listings must remain deletable')
ui.deleteButtons[1].scripts.OnClick()
assert(#ui.visible==0)
local own=f.groups[key]
local other={}; for k,v in pairs(own) do other[k]=v end
other.owner='Other'; other.id='other'; other.hidden=nil; other.closed=nil
f.groups['Other\\001other']=other
mine(); assert(#ui.visible==0 and not ui.deleteButtons[1]:IsShown())
assert(not f:Delete('other') and not other.hidden)
''')
print('PASS: visible in-card trash, own open/closed deletion, cancellation broadcast, owner-only guard')
