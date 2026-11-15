from pathlib import Path
import runpy

root=Path(__file__).resolve().parents[1]
lua=runpy.run_path(str(root/'tests/test_ui_smoke.py'))['lua']
lua.execute('''
local shown,text=0,nil
GameTooltip={
    SetOwner=function() end,
    SetText=function(_,value,...) assert(select('#',...)==0,'unsupported tooltip SetText arguments'); text=value end,
    Show=function() shown=shown+1 end,
    Hide=function() end,
}
local ui=OldKrakenGroupFinderFrame
ui.cancelButton.scripts.OnEnter(ui.cancelButton)
assert(text=='Закрити набір: оголошення зникне з відкритих груп.')
ui.bumpButton.scripts.OnEnter(ui.bumpButton)
assert(text:find('5 хвилин',1,true))
assert(shown==2)
ui.cancelButton.scripts.OnLeave(); ui.bumpButton.scripts.OnLeave()
''')
print('PASS: close and reannounce tooltips use the target-client SetText signature')
