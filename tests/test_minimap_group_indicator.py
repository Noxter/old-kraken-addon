from pathlib import Path

from lupa.lua51 import LuaRuntime


root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
OldKraken={listeners={}, UIStyle={Colors={window={0,0,0,1}, brandGold={1,1,0,1}},
    EmblemPath=function() return 'emblem' end}}
function OldKraken:On(name,fn)
    self.listeners[name]=self.listeners[name] or {}; table.insert(self.listeners[name],fn)
end
function OldKraken:Fire(name,...) for _,fn in ipairs(self.listeners[name] or {}) do fn(...) end end
function GetTime() return now end
function GetServerTime() return 100000 end
now=0; level=20; tank=false; healer=false; dps=false
function UnitLevel() return level end
function UnitGetAvailableRoles() return tank,healer,dps end
function UnitName() return 'Me' end
function InCombatLockdown() return true end
Minimap={GetFrameLevel=function() return 1 end,GetWidth=function() return 100 end,GetHeight=function() return 100 end}
GameTooltip={lines={}}
function GameTooltip:SetOwner() self.lines={} end
function GameTooltip:SetText(text) self.title=text end
function GameTooltip:AddLine(text) self.lines[#self.lines+1]=text end
function GameTooltip:Show() end
function GameTooltip:Hide() end
local methods={}
function methods:SetScript(k,v) self.scripts[k]=v end
function methods:RegisterEvent(k) self.events[k]=true end
function methods:CreateTexture() return CreateFrame() end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false end
function methods:SetTexture(t) self.texture=t end
local meta={__index=function(_,k) return methods[k] or function() end end}
frames={}
function CreateFrame(_,name)
    local f=setmetatable({scripts={},events={}},meta)
    if name then _G[name]=f end
    frames[#frames+1]=f
    return f
end
C_Timer={NewTicker=function(seconds,fn) assert(seconds==10); indicatorTick=fn end}
''')
for name in ('GroupFinder.lua', 'Minimap.lua'):
    lua.execute((root / name).read_text(encoding='utf-8'))

lua.execute('''
local f=OldKraken.GroupFinder
f:Initialize('Me',function() return true end)
f.active=true
OldKraken:Fire('INITIALIZED',{settings={minimapAngle=225,groupFinderNotifications=false}})
local button=OldKrakenMinimapButton
local indicator=button.groupIndicator
assert(not indicator.shown and indicator.texture:find('StatusOnline.tga',1,true))
assert(type(indicatorTick)=='function')
local dungeon={owner='Other',id='1',category='dungeon',maxSize=5,minLevel=20,maxLevel=30,
    role='tank',members={'Other'},memberRoles={},seenAt=now}
f.groups.one=dungeon
tank=true; OldKraken:Fire('GROUP_FINDER_CHANGED')
assert(not indicator.shown, 'a tank cannot fill a second tank slot')
healer=true; OldKraken:Fire('GROUP_FINDER_CHANGED')
assert(indicator.shown, 'a matching free healer slot is indicated even in combat with alerts disabled')
button.scripts.OnEnter(button)
assert(GameTooltip.lines[1]:find('1',1,true))

level=30; indicatorTick(); assert(indicator.shown, 'upper level bound is inclusive')
level=31; indicatorTick(); assert(not indicator.shown)
level=19; indicatorTick(); assert(not indicator.shown)
level=20; indicatorTick(); assert(indicator.shown, 'lower level bound is inclusive')
dungeon.members={'Other','Heal','Dps1','Dps2','Dps3'}
dungeon.memberRoles={Heal='healer',Dps1='dps',Dps2='dps',Dps3='dps'}
OldKraken:Fire('GROUP_FINDER_CHANGED'); assert(not indicator.shown, 'full groups are excluded')
dungeon.members={'Other','Me'}; dungeon.memberRoles={Me='healer'}
OldKraken:Fire('GROUP_FINDER_CHANGED'); assert(not indicator.shown, 'already joined groups are excluded')
dungeon.members={'Other'}; dungeon.memberRoles={}; dungeon.closed=true
OldKraken:Fire('GROUP_FINDER_CHANGED'); assert(not indicator.shown)
dungeon.closed=false; dungeon.hidden=true
OldKraken:Fire('GROUP_FINDER_CHANGED'); assert(not indicator.shown)
dungeon.hidden=false; dungeon.owner='Me'; dungeon.members={'Me'}
OldKraken:Fire('GROUP_FINDER_CHANGED'); assert(not indicator.shown, 'own groups are excluded')

local quest={owner='Another',id='2',category='quest',maxSize=5,minLevel=1,maxLevel=60,
    role='dps',members={'Another'},memberRoles={},seenAt=now}
f.groups.two=quest
OldKraken:Fire('GROUP_FINDER_CHANGED'); assert(indicator.shown, 'non-dungeon vacancy accepts an available role')
tank=false; healer=false; dps=false
indicatorTick(); assert(not indicator.shown, 'no available roles means no match')
dps=true; indicatorTick(); assert(indicator.shown)
f.active=false; indicatorTick(); assert(not indicator.shown, 'inactive finder has no indicator')
f.active=true; indicatorTick(); assert(indicator.shown)
now=3601; f:Prune(); indicatorTick(); assert(not indicator.shown, 'expired listings stop matching')

quest.seenAt=now; f.groups.two=quest; OldKraken:Fire('GROUP_FINDER_CHANGED'); assert(indicator.shown)
level=61
for _,frame in ipairs(frames) do if frame.events.PLAYER_LEVEL_UP then frame.scripts.OnEvent(frame,'PLAYER_LEVEL_UP') end end
assert(not indicator.shown, 'level change updates the indicator immediately')
button.scripts.OnEnter(button)
for _,line in ipairs(GameTooltip.lines) do assert(not line:find('Підходящих груп',1,true)) end
''')
print('Minimap group indicator checks passed')
