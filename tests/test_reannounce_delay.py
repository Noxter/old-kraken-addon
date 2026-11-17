from pathlib import Path
import sys
from lupa.lua51 import LuaRuntime
root=Path(__file__).resolve().parents[1]
lua=LuaRuntime(unpack_returned_tuples=True)
setup=(root/'tests/test_integration.py').read_text(encoding='utf-8').split("lua.execute('''",1)[1].split("''')",1)[0]
lua.execute(setup)
lua.execute('now=1700000000; function GetServerTime() return now end')
lua.execute((root/'GroupFinder.lua').read_text(encoding='utf-8'))
lua.execute((root/'GroupFinderIntegration.lua').read_text(encoding='utf-8'))
lua.execute('''
login(nil,'PLAYER_LOGIN')
local f=OldKraken.GroupFinder
local ok,id=f:Create('Test','dungeon','',5,1,60,'tank')
assert(ok)
local sent,reason,seconds=f:Reannounce(id)
assert(not sent and reason=='cooldown' and seconds==300)
now=now+299
sent,reason,seconds=f:Reannounce(id)
assert(not sent and reason=='cooldown' and seconds==1)
now=now+1; assert(f:Reannounce(id))
sent,reason,seconds=f:Reannounce(id)
assert(not sent and seconds==300)
now=now+300
function OldKraken.Communication:SendProtocol() return false end
sent,reason=f:Reannounce(id); assert(not sent and reason=='queue')
function OldKraken.Communication:SendProtocol() return true end
assert(f:Reannounce(id))
''')
# Reload the integration while retaining saved profile data.
lua.execute((root/'GroupFinderIntegration.lua').read_text(encoding='utf-8'))
lua.execute('''
login(nil,'PLAYER_LOGIN')
local f=OldKraken.GroupFinder
local ok,id=f:Create('Reload check','dungeon','',5,1,60,'tank')
assert(ok)
now=now+300; assert(f:Reannounce(id))
savedID=id
''')
lua.execute((root/'GroupFinderIntegration.lua').read_text(encoding='utf-8'))
lua.execute('''
login(nil,'PLAYER_LOGIN')
-- Restore the model record (Create normally persists through its API wrapper).
local f=OldKraken.GroupFinder
f.groups[f.identity..'\\001'..savedID]={id=savedID,closed=false}
local ok,reason,seconds=f:Reannounce(savedID)
assert(not ok and reason=='cooldown' and seconds==300)
''')
print('PASS: initial delay, 299/300-second boundary, repeated delay, queue failure, saved cooldown after reload')
ui=(root/'GroupFinderUI.lua').read_text(encoding='utf-8')
lua.execute('assert(loadstring(...))',ui)
countdown=ui.split('local function UpdateReannounceButton(control)',1)[1].split('local dungeonOptions',1)[0]
view=LuaRuntime(unpack_returned_tuples=True)
view.execute('''
local selected='group'
local seconds=300
local Finder={groups={group={id='id'}},GetReannounceRemaining=function() return seconds end}
local function UpdateReannounceButton(control)
'''+countdown+'''
local control={SetText=function(self,text) self.text=text end,SetEnabled=function(self,value) self.enabled=value end}
UpdateReannounceButton(control)
assert(control.text=='Анонс через 05:00' and not control.enabled)
seconds=61; UpdateReannounceButton(control); assert(control.text=='Анонс через 01:01')
seconds=1; UpdateReannounceButton(control); assert(control.text=='Анонс через 00:01' and not control.enabled)
seconds=0; UpdateReannounceButton(control); assert(control.text=='Оновити набір' and control.enabled)
selected=nil; UpdateReannounceButton(control); assert(not control.enabled)
''')
print('PASS: UI countdown 05:00 / 01:01 / 00:01, button enabled at zero, cleared selection')
