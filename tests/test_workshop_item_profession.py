from test_workshop_orders import client,tick,flush

owner=client('Owner'); worker=client('Worker')
tick(owner); tick(worker)
owner.execute('''
OldKraken.WorkshopOrders:Show()
pickOrderRecipe(OldKrakenWorkshopOrdersFrame.orderForm,'Profession check',171,0,9101)
click('Опублікувати')
''')
tick(owner); flush(owner,worker)
worker.execute('''
local scope=OldKraken.DB.workshop.guilds['Realm\\001Guild']
local key,order=next(scope.orderObserved); assert(order)
function GetProfessions() return nil end
for _,f in ipairs(frames) do if f.events.SKILL_LINES_CHANGED then f.scripts.OnEvent(f,'SKILL_LINES_CHANGED') end end
assert(not OldKraken.Workshop:HasProfession(171))
OldKraken.WorkshopOrders:Show(key)
local panel=OldKrakenWorkshopOrdersFrame
assert(not panel.offer:IsShown())
panel.offer.scripts.OnClick(panel.offer)
assert(not scope.orderIntents['Worker Mon'][key],'hidden button handler must not bypass profession eligibility')
function GetProfessions() return 1 end
for _,f in ipairs(frames) do if f.events.SKILL_LINES_CHANGED then f.scripts.OnEvent(f,'SKILL_LINES_CHANGED') end end
assert(OldKraken.Workshop:HasProfession(171))
scope.recipes['Worker Mon'][9101]={recipe=9101,item=0,profession=171,seen=now,name='Profession check',product='Profession check'}
OldKraken.WorkshopOrders:Show(key); assert(panel.offer:IsShown())
-- Cached recipe knowledge cannot substitute for a currently learned profession.
scope.recipes['Worker Mon'][123]={recipe=123,item=456,profession=171,seen=now,name='Cached',product='Cached'}
order.itemID=456; order.recipeID=123
function GetProfessions() return nil end
for _,f in ipairs(frames) do if f.events.SKILL_LINES_CHANGED then f.scripts.OnEvent(f,'SKILL_LINES_CHANGED') end end
OldKraken.WorkshopOrders:Show(key); panel.offer.scripts.OnClick(panel.offer)
assert(not scope.orderIntents['Worker Mon'][key])
order.status='assigned'; order.worker='Worker Mon'; order.assignment=1
OldKraken.WorkshopOrders:Show(key)
assert(not panel.delivered:IsShown())
panel.delivered.scripts.OnClick(panel.delivered)
assert(not scope.orderIntents['Worker Mon'][key])
-- Missing item names are loaded asynchronously, never displayed as IDs.
local loaded=false; local requests=0
C_Item={GetItemNameByID=function() if loaded then return 'Silk Cloth' end end,
GetItemIconByID=function() return 132905 end,
RequestLoadItemDataByID=function() requests=requests+1 end}
local recipes=OldKraken.WorkshopRecipes
local text=recipes:ItemLabel(4306)
assert(text:find('|T132905:22:22',1,true) and not text:find('4306',1,true))
for i=1,20 do recipes:ItemLabel(4306) end
assert(requests==1,'missing item data requests must be throttled')
loaded=true
for _,f in ipairs(frames) do if f.events.ITEM_DATA_LOAD_RESULT then f.scripts.OnEvent(f,'ITEM_DATA_LOAD_RESULT',4306,true) end end
text=recipes:ItemLabel(4306)
assert(text:find('Silk Cloth',1,true) and not text:find('4306',1,true))
''')
owner.execute('''
function GetProfessions() return nil end
for _,f in ipairs(frames) do if f.events.SKILL_LINES_CHANGED then f.scripts.OnEvent(f,'SKILL_LINES_CHANGED') end end
local scope=OldKraken.DB.workshop.guilds['Realm\\001Guild']
local key=next(scope.orderOwners['Owner Mon'])
OldKraken.WorkshopOrders:Show(key)
local panel=OldKrakenWorkshopOrdersFrame
assert(panel.cancel:IsShown(),'customer actions must remain available without the crafting profession')
''')
print('PASS: current profession required for offer/delivery, cached recipes cannot bypass it, native skill changes, customer controls, item icons/names and async loading throttle')
other=client('NoProfession'); tick(other)
other.execute('''
function GetProfessions() return nil end
for _,f in ipairs(frames) do if f.events.SKILL_LINES_CHANGED then f.scripts.OnEvent(f,'SKILL_LINES_CHANGED') end end
notices={}
''')
worker.execute('''
function GetProfessions() return 1 end
for _,f in ipairs(frames) do if f.events.SKILL_LINES_CHANGED then f.scripts.OnEvent(f,'SKILL_LINES_CHANGED') end end
notices={}
''')
owner.execute('''
OldKraken.WorkshopOrders:Show()
pickOrderRecipe(OldKrakenWorkshopOrdersFrame.orderForm,'item:98765',171,0,9102)
click('Опублікувати')
''')
tick(owner)
packets=[(owner.globals().outgoing[i][1],owner.globals().outgoing[i][2]) for i in range(1,len(owner.globals().outgoing)+1)]
flush(owner,worker,True)
for kind,payload in packets*2:
    handler=other.globals().handlers[kind]
    if handler: handler('Owner Mon','GUILD',payload)
worker.execute('''
local count=0
for _,notice in ipairs(notices) do if notice[1]=='WORKSHOP_ORDER_NOTICE' and notice[2]=='Нове замовлення: item:98765' then count=count+1 end end
assert(count==1,'new order for a learned profession must notify once even if the recipe is unknown')
''')
other.execute('''
for _,notice in ipairs(notices) do assert(not (notice[1]=='WORKSHOP_ORDER_NOTICE' and notice[2]:find('Нове замовлення:',1,true)),'must not notify without the profession') end
''')
print('PASS: new-order notices match current profession even with unknown recipe knowledge, and duplicate snapshots do not repeat notices')
