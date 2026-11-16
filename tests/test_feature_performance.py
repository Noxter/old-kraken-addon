"""Large guild UI/profession-cache regression checks with deferred timers."""
from pathlib import Path
import runpy
from test_workshop_orders import client
import test_workshop_orders as fixture

ROOT=Path(__file__).resolve().parents[1]

# Exercise the real group window, 500 listings, a full raid and event bursts.
state=runpy.run_path(str(ROOT/'tests/test_ui_smoke.py'))
lua=state['lua']
lua.execute('''
deferred={}
C_Timer={After=function(_,fn) deferred[#deferred+1]=fn end}
function drain()
    local guard=0
    while #deferred>0 do guard=guard+1; assert(guard<10000); table.remove(deferred,1)() end
end
local finder=OldKraken.GroupFinder
finder.groups={}; finder.pending={}; finder.requests={}
for i=1,500 do
    local owner=string.format('Owner %03d',i)
    local id='12345-'..i..'-1'
    finder.groups[owner..'\\001'..id]={id=id,owner=owner,title='Group '..i,category='raid',dungeon='',description='',role='dps',minLevel=1,maxLevel=60,maxSize=200,members={owner},closed=false}
end
local ui=OldKrakenGroupFinderFrame
ui:Show()
for _,tab in ipairs(ui.tabs) do if tab.key=='all' then tab.button.scripts.OnClick() end end
selectDropdown(ui.categoryFilter,'all')
selectDropdown(ui.dungeonFilter,'')
selectDropdown(ui.roleFilter,'')
selectDropdown(ui.freeFilter,false)
ui.searchFilter:SetText(''); ui.levelFilter:SetText('')
local allocations=#createdFrames
for i=1,500 do OldKraken.listeners.GROUP_FINDER_CHANGED() end
assert(#deferred==1,'500 group updates must coalesce')
drain()
assert(#ui.visible==500 and #ui.rows==5)
assert(#createdFrames==allocations,'updates must reuse cards')
local card=ui.rows[1]
local selected=ui.visible[1].group
selected.members={selected.owner}
for i=2,200 do selected.members[i]='Raid member '..i end
card.scripts.OnClick(card)
assert(#ui.memberRows<=7,'raid details must use a bounded row pool')
local scroll=ui.detailsScroll
scroll.position=0
function scroll:GetHeight() return 210 end
function scroll:GetVerticalScroll() return self.position end
function scroll:SetVerticalScroll(value) self.position=value end
scroll.position=7600
scroll.scripts.OnVerticalScroll(scroll,scroll.position); drain()
assert(#ui.memberRows<=7)
ui:Hide()
for i=1,500 do OldKraken.listeners.GROUP_FINDER_CHANGED() end
assert(#deferred==0,'hidden group window must not queue UI work')
''')

original_sources=fixture.SOURCES
fixture.SOURCES=['''
OldKraken.listeners={}
function OldKraken:On(event,fn)
    local bucket=self.listeners[event] or {}; self.listeners[event]=bucket; bucket[#bucket+1]=fn
end
function OldKraken:Fire(event,...)
    notices[#notices+1]={event,...}
    for _,fn in ipairs(self.listeners[event] or {}) do fn(...) end
end
''']+original_sources
lua=client('Load')
fixture.SOURCES=original_sources
lua.execute('''
deferred={}; timeReads=0
C_Timer.After=function(_,fn) deferred[#deferred+1]=fn end
function GetServerTime() timeReads=timeReads+1; return now end
function drain()
    local guard=0
    while #deferred>0 do guard=guard+1; assert(guard<10000); table.remove(deferred,1)() end
end
local scope=OldKraken.DB.workshop.guilds['Realm\\001Guild']
for i=1,500 do
    local entries={}; scope.recipes['Crafter '..i]=entries
    for id=1,200 do entries[id]={recipe=id,item=100000+id,profession=171,seen=now,name='Recipe '..id,product='Item '..id} end
end
local recipes=OldKraken.WorkshopRecipes
local before=timeReads
local summary=recipes:GetProfessionSummaries()
assert(timeReads==before and #deferred==1,'opening summaries must not synchronously scan 100,000 recipes')
local batches=0
while #deferred>0 do
    before=timeReads; table.remove(deferred,1)(); batches=batches+1
    assert(timeReads-before<=200,'recipe indexing exceeded per-frame budget')
end
assert(batches>500)
summary=recipes:GetProfessionSummaries()
assert(summary[171].recipes==200 and summary[171].members==500)
before=timeReads
for i=1,500 do recipes:GetProfessionSummaries() end
assert(timeReads==before and #deferred==0,'summaries must reuse the completed index')
assert(#recipes:FindMasters(100001,0)==500)
assert(#recipes:FindMasters(0,1)==500)
for id=1,200 do scope.recipes['Load Mon'][id]={recipe=id,item=100000+id,profession=171,seen=now,name='Recipe '..id,product='Item '..id} end
before=timeReads
for i=1,500 do assert(recipes:Knows(100001,0)) end
assert(timeReads-before<=200,'availability checks must reuse the local item index')
-- Searches with no matches must yield, and newer searches supersede older ones.
recipes:ShowMasters(999999,0)
assert(#deferred>0)
recipes:ShowMasters(100001,0)
drain()
assert(OldKrakenWorkshopRecipesFrame.count.text:find('500',1,true),OldKrakenWorkshopRecipesFrame.count.text)
assert(OldKrakenWorkshopRecipesFrame.query.text=='item:100001')
-- Seed 500 public orders and exercise bounded cards/candidate rows.
for i=1,500 do
    local owner='Crafter '..i
    local id=tostring(now)..'-'..i..'-1'
    local k=owner..'\\001'..id
    scope.orderObserved[k]={owner=owner,id=id,rev=1,created=now,deadline=now+86400,profession=171,item='Item '..i,itemID=100001,recipeID=1,quantity=1,reward=1,materials='customer',note='',status='open',candidates={},acks={}}
end
OldKraken.WorkshopOrders:Show()
local panel=OldKrakenWorkshopOrdersFrame
assert(panel.page.text=='1 / 125')
local initial=#frames
for i=1,30 do OldKraken.WorkshopOrders:Show() end
assert(#frames==initial,'order cards must be reused')
-- One owned order with many applicants exercises row virtualization/rebinding.
local k='Load Mon\\001'..now..'-999-1'
local applicants={}; for i=1,500 do applicants[string.format('Applicant %03d',i)]=true end
scope.orderOwners['Load Mon'][k]={owner='Load Mon',id=now..'-999-1',rev=1,created=now,deadline=now+86400,profession=171,item='Owned',itemID=0,recipeID=0,quantity=1,reward=1,materials='customer',note='',status='open',candidates=applicants,acks={}}
OldKraken.WorkshopOrders:Show(k)
assert(#panel.candidates==3)
local scroll=panel.candidateScroll
scroll.position=0
function scroll:GetHeight() return 96 end
function scroll:GetVerticalScroll() return self.position end
function scroll:SetVerticalScroll(value) self.position=value end
scroll.position=23904
scroll.scripts.OnVerticalScroll(scroll,scroll.position); drain()
assert(#panel.candidates==3 and panel.candidates[2].person=='Applicant 500')
drain()
local before=#frames
for i=1,500 do OldKraken:Fire('WORKSHOP_RECIPES_CHANGED'); OldKraken:Fire('WORKSHOP_INDEX_CHANGED') end
assert(#deferred==2,'visible recipes and orders must coalesce their updates')
drain(); assert(#frames==before,'bursts must not allocate new widgets')
panel:Hide(); OldKrakenWorkshopRecipesFrame:Hide()
for i=1,500 do OldKraken:Fire('WORKSHOP_RECIPES_CHANGED'); OldKraken:Fire('WORKSHOP_INDEX_CHANGED') end
assert(#deferred==0,'hidden Workshop windows must not render')
-- A later direct snapshot invalidates the cached index and is reflected after rebuild.
assert(recipes:ImportSnapshot('Crafter 1',{{recipe=201,item=999999,profession=171,seen=now,name='New recipe',product='New item'}},false,false))
recipes:GetProfessionSummaries(); assert(#deferred>0)
drain()
assert(recipes:GetProfessionSummaries()[171].recipes==201)
assert(#recipes:FindMasters(999999,0)==1)
''')
print('PASS: 500 group listings, bounded raid/order rows, burst coalescing, hidden UI, 100,000 recipes in 200-record batches, summary/item caches, search cancellation and 500 orders')
