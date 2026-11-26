"""Bound UI allocation and per-event work for a 500-member roster."""
from pathlib import Path
import runpy
from lupa.lua51 import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]
test=runpy.run_path(str(ROOT/'tests/test_roster_invite.py'))
lua=test['lua']
lua.execute('''
local roster=OldKraken.GuildRoster
OldKraken.DB.settings.roster.search=''
OldKraken.DB.settings.roster.sort='name'
OldKraken.DB.settings.roster.status='all'
-- Reset the addon filter selected by the menu tests.
menuItems={}; OldKrakenRosterAddonFilter.initialize(nil,1); menuItems[1].func()
function GetNumGuildMembers() return 500 end
function GetGuildRosterInfo(i) return string.format('Member %03d',i),'Member',1,60,'Mage','City',nil,nil,true,'','MAGE' end
local professions=0
OldKraken.Workshop={RefreshNativeProfessions=function() end,GetMemberProfessions=function() professions=professions+1; return {} end}
local scroll=OldKrakenRosterScrollFrame
scroll.offset=0
function scroll:GetHeight() return 440 end
function scroll:GetVerticalScroll() return self.offset end
function scroll:SetVerticalScroll(value) self.offset=value; self.scripts.OnVerticalScroll(self,value) end
roster:Load()
-- viewport=440, ROW_HEIGHT=40 -> math.ceil(440 / 40) + 1 = 12 visible pooled rows.
assert(professions==12)
local initial=#createdFrames
assert(initial<650,'must not allocate rows for all 500 members')
local function visible()
    local result={}
    for _,frame in ipairs(createdFrames) do
        if type(frame.member)=='table' and frame:IsShown() then result[#result+1]=frame end
    end
    return result
end
assert(#visible()==12 and visible()[1].member.name=='Member 001')
for offset=0,19600,400 do
    scroll:SetVerticalScroll(offset)
    assert(#visible()<=12 and #createdFrames==initial)
end
assert(visible()[11].member.name=='Member 500')
local first=visible()[1]
first.scripts.OnClick(first,'RightButton')
assert(menuItems[1].text==first.member.name)
-- Shrinking the filtered list clamps the old scroll position and clears stale rows.
OldKraken.DB.settings.roster.search='Member 500'
roster:Render()
assert(scroll.offset==0 and #visible()==1 and visible()[1].member.name=='Member 500')
OldKraken.DB.settings.roster.search='no results'; roster:Render(); assert(#visible()==0)
-- Bursty roster/presence notifications cause one reload, not 500 reloads.
local loads,renders=0,0
local oldLoad,oldRender=roster.Load,roster.Render
function roster:Load() loads=loads+1; return oldLoad(self) end
function roster:Render() renders=renders+1; return oldRender(self) end
local eventFrame
for _,frame in ipairs(createdFrames) do if type(frame.scripts.OnUpdate)=='function' and type(frame.scripts.OnEvent)=='function' then eventFrame=frame end end
assert(eventFrame)
OldKrakenRosterFrame:Show()
for i=1,500 do eventFrame.scripts.OnEvent(); roster:ScheduleRefresh(false) end
assert(loads==0 and renders==0)
eventFrame.scripts.OnUpdate(nil,0.1); assert(loads==0)
eventFrame.scripts.OnUpdate(nil,0.1); assert(loads==1 and renders==1)
OldKrakenRosterFrame:Hide(); eventFrame.scripts.OnEvent()
eventFrame.scripts.OnUpdate(nil,1); assert(loads==1)
OldKrakenRosterFrame:Show(); eventFrame.scripts.OnUpdate(nil,0.2); assert(loads==2)
''')

# Native profession scanning yields between 25-member batches and caches results.
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
handlers={}
OldKraken={DB={},Communication={RegisterHandler=function(_,k,fn) handlers[k]=fn end},Fire=function() end,On=function() end}
function UnitName() return 'Me' end
function GetRealmName() return 'Realm' end
function GetGuildInfo() return 'Guild' end
function GetTime() return 100 end
function GetServerTime() return 1700000000 end
function CreateFrame() return {RegisterEvent=function() end,SetScript=function(_,_,fn) eventHandler=fn end} end
timers={}; C_Timer={After=function(_,fn) timers[#timers+1]=fn end,NewTicker=function() end}
scanned=0
local members={}; for i=1,500 do members[i]=i end
C_Club={GetGuildClubId=function() return 1 end,GetClubMembers=function() return members end,
GetMemberInfo=function(_,id) scanned=scanned+1; return {name='Member '..id,profession1ID=171} end}
''')
lua.execute((ROOT/'GroupFinder.lua').read_text(encoding='utf-8'))
lua.execute((ROOT/'Workshop.lua').read_text(encoding='utf-8'))
lua.execute('''
eventHandler(nil,'PLAYER_LOGIN')
assert(OldKraken.Workshop:RefreshNativeProfessions())
assert(scanned==0 and #timers==1)
while #timers>0 do
    local before=scanned; table.remove(timers,1)(); assert(scanned-before<=25)
end
assert(scanned==500)
OldKraken.Workshop:RefreshNativeProfessions(); assert(scanned==500 and #timers==0)
assert(OldKraken.Workshop:GetMemberProfessions('Member 500')[1].id==171)
-- Verify crafting -> gathering -> secondary sorting in GetMemberProfessions
handlers.WKPROF('Mixed Guy','GUILD',OldKraken.GroupFinder._pack({1700000000,4,185,300,300,182,225,300,333,250,300,171,300,300}))
local sortedProfs = OldKraken.Workshop:GetMemberProfessions('Mixed Guy')
assert(#sortedProfs == 4 and sortedProfs[1].id == 171 and sortedProfs[2].id == 333 and sortedProfs[3].id == 182 and sortedProfs[4].id == 185)
''')
for name in ['StatusOnline','StatusOffline']:
    asset=ROOT/'Media'/f'{name}.tga'
    data=asset.read_bytes()
    assert len(data)==18+16*16*4 and data[2]==2 and data[16]==32
    for workflow in ['package-alpha.yml','package-release.yml']:
        assert f'Media/{name}.tga' in (ROOT/'.github/workflows'/workflow).read_text()
print('PASS: 500-member bounded row pool, scrolling, filters, menu identity, batched events, chunked native professions and packaged status textures')
