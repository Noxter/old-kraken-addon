from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
SOURCES = [(ROOT / name).read_text(encoding='utf-8') for name in (
    'GroupFinder.lua', 'Workshop.lua', 'WorkshopRecipes.lua', 'WorkshopOrders.lua')]


def client(name, embedded=False):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().player = name
    lua.globals().embedded = embedded
    lua.execute('''
        now=1700000000; clock=100; outgoing={}; timers={}; frames={}; notices={}; handlers={}
        OldKraken={DB={settings={}},UIStyle={
            Colors={brandGold={0.88,0.69,0.32,1}},
            Button=function(button,variant) button.variant=variant end,
            Window=function() end,Dropdown=function() end,Input=function() end,
        }}
        if embedded then
            OldKraken.UIHub={pages={}}
            function OldKraken.UIHub:RegisterPage(key,title,shortcut,create)
                self.pages[key]={title=title,create=create}
            end
            function OldKraken.UIHub:ShowPage(key)
                local page=self.pages[key]; assert(page,'missing Hub page '..key)
                if not page.frame then page.frame=page.create(CreateFrame('Frame')) end
                self.currentPage=key; page.frame:Show(); return page.frame
            end
        end
        function OldKraken:On() end
        function OldKraken:Fire(...) notices[#notices+1]={...} end
        function print(...) end
        function UnitName() return player,'Mon' end
        function GetGuildInfo() return 'Guild' end
        function GetRealmName() return 'Realm' end
        function GetServerTime() return now end
        function GetTime() return clock end
        function date() return 'date' end
        function GetProfessions() return 1 end
        function GetProfessionInfo() return 'Alchemy',nil,50,300,nil,nil,171 end
        UIParent={}; UISpecialFrames={}; StaticPopupDialogs={}
        function StaticPopup_Show(name,a,b,callback)
            popup={callback=callback,GetFrameStrata=function() return 'DIALOG' end,SetFrameStrata=function() end,HookScript=function() end}
            return popup
        end
        function UIDropDownMenu_SetWidth() end
        function UIDropDownMenu_SetText(f,text) f.text=text end
        function UIDropDownMenu_Initialize(f,fn) f.dropdown=fn end
        function UIDropDownMenu_CreateInfo() return {} end
        function UIDropDownMenu_AddButton(item) choices[#choices+1]=item end
        function selectOption(frame,value)
            choices={}; frame.dropdown(frame,1)
            for _,item in ipairs(choices) do if item.value==value then item.func(); return end end
            error('missing option '..tostring(value))
        end
        local methods={}
        function methods:SetSize(width,height) self.width=width; self.height=height end
        function methods:SetScript(k,fn) self.scripts[k]=fn end
        function methods:RegisterEvent(event) self.events[event]=true end
        function methods:SetText(text) self.text=text; if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end end
        function methods:GetText() return self.text or '' end
        function methods:GetParent() return self.parent end
        function methods:Show() self.shown=true end
        function methods:Hide() self.shown=false end
        function methods:SetShown(v) self.shown=v end
        function methods:IsShown() return self.shown end
        function methods:GetStringHeight() return 10 end
        function methods:CreateFontString() return CreateFrame() end
        function methods:CreateTexture() return CreateFrame() end
        function methods:GetFontString() return CreateFrame() end
        function methods:Enable() self.enabled=true end
        function methods:Disable() self.enabled=false end
        local meta={__index=function(_,k) if k=='TitleText' then return nil end; return methods[k] or function() end end}
        function CreateFrame(_,name,parent)
            local f=setmetatable({scripts={},events={},parent=parent},meta)
            if name then _G[name]=f end
            frames[#frames+1]=f; return f
        end
        function click(text)
            for _,f in ipairs(frames) do if f.text==text and f.scripts.OnClick and f.shown~=false then f.scripts.OnClick(f); return end end
            error('button not found: '..text)
        end
        C_Timer={NewTicker=function(_,fn) timers[#timers+1]=fn end}
        OldKraken.Communication={queue={}}
        function OldKraken.Communication:RegisterHandler(kind,fn) handlers[kind]=fn end
        function OldKraken.Communication:SendProtocol(kind,payload) outgoing[#outgoing+1]={kind,payload}; return true end
    ''')
    for source in SOURCES:
        lua.execute(source)
    lua.execute('for _,f in ipairs(frames) do if f.events.PLAYER_LOGIN then f.scripts.OnEvent(f,"PLAYER_LOGIN") end end')
    return lua


def tick(lua):
    lua.execute('clock=clock+4; for _,f in ipairs(timers) do f() end')


def restart(lua):
    lua.execute('''
        saved=OldKraken.DB; OldKraken={DB=saved,UIStyle={Button=function() end,Window=function() end,Dropdown=function() end,Input=function() end}}
        function OldKraken:On() end; function OldKraken:Fire(...) notices[#notices+1]={...} end
        OldKraken.Communication={queue={}}; function OldKraken.Communication:RegisterHandler(kind,fn) handlers[kind]=fn end
        function OldKraken.Communication:SendProtocol(kind,payload) outgoing[#outgoing+1]={kind,payload}; return true end
        frames={}; timers={}; handlers={}; outgoing={}
    ''')
    for source in SOURCES:
        lua.execute(source)
    lua.execute('for _,f in ipairs(frames) do if f.events.PLAYER_LOGIN then f.scripts.OnEvent(f,"PLAYER_LOGIN") end end')


def flush(sender, recipient, repeat=False):
    outgoing = sender.globals().outgoing
    packets = [(outgoing[i][1], outgoing[i][2]) for i in range(1, len(outgoing)+1)]
    sender.execute('outgoing={}')
    handlers = recipient.globals().handlers
    for kind, payload in packets * (2 if repeat else 1):
        handler = handlers[kind]
        if handler:
            handler(sender.globals().player + ' Mon', 'GUILD', payload)


def test_orders():
    alice, bob = client('Alice'), client('Bob')
    tick(alice); tick(bob)
    alice.execute('''
        OldKraken.WorkshopOrders:Show(); local f=OldKrakenWorkshopOrdersFrame
        f.item:SetText('Manual potion'); click('Опублікувати')
        local s=OldKraken.DB.workshop.guilds['Realm\\001Guild']; assert(next(s.orderOwners['Alice Mon'])==nil)
        selectOption(OldKrakenOrderProfession,171); click('Опублікувати')
        for k,v in pairs(s.orderOwners['Alice Mon']) do orderKey=k; order=v end
        assert(order and order.profession==171 and order.status=='open')
    ''')
    tick(alice); flush(alice, bob, True)


    bob.execute('''
        local s=OldKraken.DB.workshop.guilds['Realm\\001Guild']; for k,v in pairs(s.orderObserved) do orderKey=k; order=v end
        assert(order and order.item=='Manual potion')
        local n=0; for _,e in ipairs(notices) do if e[1]=='WORKSHOP_ORDER_NOTICE' and e[2]=='Нове замовлення: Manual potion' then n=n+1; assert(e[3]:find('рецепт не підтверджено')) end end; assert(n==1)
        OldKraken.WorkshopOrders:Show(); selectOption(OldKrakenOrdersView,'available')
        click('Запропонувати допомогу')
    ''')
    tick(bob); flush(bob, alice, True); tick(alice); flush(alice, bob)
    alice.execute('''
        assert(order.candidates['Bob Mon']); OldKraken.WorkshopOrders:Show(orderKey)
        local b=OldKrakenWorkshopOrdersFrame.candidates[1].choose; b.scripts.OnClick(b)
    ''')
    tick(alice); flush(alice, bob)
    bob.execute('assert(order.status=="open"); for k,v in pairs(OldKraken.DB.workshop.guilds["Realm\\001Guild"].orderObserved) do order=v end; assert(order.status=="assigned"); local p=OldKraken.DB.workshop.guilds["Realm\\001Guild"].orderIntents["Bob Mon"][orderKey]; assert(not p,"pending: "..(p and p.action or "none"))')
    bob.execute("selectOption(OldKrakenOrdersView,'all'); OldKraken.WorkshopOrders:Show(orderKey); local b=OldKrakenWorkshopOrdersFrame.delivered; b.scripts.OnClick(b); local s=OldKraken.DB.workshop.guilds['Realm\\001Guild']; assert(s.orderIntents['Bob Mon'][orderKey] and s.orderIntents['Bob Mon'][orderKey].action=='delivered', 'delivery intent missing')")
    tick(bob); flush(bob, alice, True); tick(alice); flush(alice, bob)
    alice.execute("assert(order.status=='delivered', 'status before finish: '..order.status); OldKraken.WorkshopOrders:Show(orderKey); local b=OldKrakenWorkshopOrdersFrame.finish; b.scripts.OnClick(b); assert(order.status=='done', 'status after finish: '..order.status)")
    tick(alice); flush(alice, bob)
    bob.execute('''
        local s=OldKraken.DB.workshop.guilds['Realm\\001Guild']; assert(s.orderObserved[orderKey].status=='done')
        s.recipes['Bob Mon'][456]={recipe=456,item=0,profession=171,seen=now,name='Test',product=''}
        assert(OldKraken.WorkshopRecipes:Knows(987,456)); assert(#OldKraken.WorkshopRecipes:FindMasters(987,456)==1)
    ''')
    alice.execute('''
        local f=OldKrakenWorkshopOrdersFrame; f.item:SetText('Late potion')
        selectOption(OldKrakenOrderProfession,171); click('Опублікувати')
        for k,v in pairs(OldKraken.DB.workshop.guilds['Realm\\001Guild'].orderOwners['Alice Mon']) do if v.item=='Late potion' then orderKey=k; order=v end end
    ''')
    tick(alice); flush(alice, bob)
    bob.execute("OldKraken.WorkshopOrders:Show(); selectOption(OldKrakenOrdersView,'all'); click('Запропонувати допомогу')")
    tick(bob); flush(bob, alice); tick(alice); flush(alice, bob)
    alice.execute("OldKraken.WorkshopOrders:Show(orderKey); local b=OldKrakenWorkshopOrdersFrame.candidates[1].choose; b.scripts.OnClick(b); assert(order.status=='assigned'); now=now+86401")
    alice.execute('''
        OldKraken.WorkshopOrders:Show(orderKey); local f=OldKrakenWorkshopOrdersFrame
        assert(f.reopen:IsShown()); assert(f.details.text:find('прострочено'))
        f.reopen.scripts.OnClick(f.reopen); assert(order.status=='assigned')
        popup.callback(); assert(order.status=='open' and order.worker==nil and next(order.candidates)==nil and order.deadline==now+86400)
    ''')
    tick(alice); flush(alice, bob)
    alice.execute('''
        saved=OldKraken.DB; OldKraken={DB=saved,UIStyle={Button=function() end,Window=function() end,Dropdown=function() end,Input=function() end}}
        function OldKraken:On() end; function OldKraken:Fire() end
        OldKraken.Communication={queue={}}; function OldKraken.Communication:RegisterHandler(kind,fn) handlers[kind]=fn end
        function OldKraken.Communication:SendProtocol(kind,payload) outgoing[#outgoing+1]={kind,payload}; return true end
        frames={}; timers={}; handlers={}
    ''')
    for source in SOURCES:
        alice.execute(source)
    alice.execute('''
        for _,f in ipairs(frames) do if f.events.PLAYER_LOGIN then f.scripts.OnEvent(f,'PLAYER_LOGIN') end end
        local restored=OldKraken.DB.workshop.guilds['Realm\\001Guild'].orderOwners['Alice Mon'][orderKey]
        assert(restored and restored.status=='open' and restored.deadline==now+86400)
    ''')


def test_incomplete_profession_scan():
    lua = client('Tester')
    tick(lua)
    lua.execute('''
        local s=OldKraken.DB.workshop.guilds['Realm\\001Guild']; savedTimestamp=s.records['Tester Mon'].timestamp
        function GetProfessionInfo() return 'Blacksmithing',nil,50,300,nil,nil,164 end
        now=now+90000; clock=clock+90
    ''')
    tick(lua)
    lua.execute('''
        local r=OldKraken.DB.workshop.guilds['Realm\\001Guild'].records['Tester Mon']
        assert(r.timestamp==savedTimestamp and r.list[1].id==171)
    ''')


def test_partial_recipe_scan_retains_records():
    lua = client('Tester')
    lua.execute('''
        local s=OldKraken.DB.workshop.guilds['Realm\\001Guild']
        s.recipes['Tester Mon'][456]={recipe=456,item=987,profession=171,seen=now,name='Test',product=''}
        C_TradeSkillUI={
            IsTradeSkillLinked=function() return false end, IsTradeSkillGuild=function() return false end,
            IsNPCCrafting=function() return false end, GetBaseProfessionInfo=function() return {professionID=171} end,
            GetAllRecipeIDs=function() return {456} end, GetRecipeInfo=function() return {learned=false} end,
        }
        for _,f in ipairs(frames) do if f.events.TRADE_SKILL_SHOW then f.scripts.OnEvent(f,'TRADE_SKILL_SHOW') end end
    ''')
    tick(lua)
    lua.execute("assert(OldKraken.DB.workshop.guilds['Realm\\001Guild'].recipes['Tester Mon'][456])")


def test_order_relay_and_owner_authority():
    alice, bob, carol, dave = (client(name) for name in ('Alice', 'Bob', 'Carol', 'Dave'))
    tick(alice); tick(bob)
    alice.execute('''
        OldKraken.WorkshopOrders:Show(); OldKrakenWorkshopOrdersFrame.item:SetText('Relay potion')
        selectOption(OldKrakenOrderProfession,171); click('Опублікувати')
        for k,v in pairs(OldKraken.DB.workshop.guilds['Realm\\001Guild'].orderOwners['Alice Mon']) do orderKey=k; order=v end
    ''')
    tick(alice); flush(alice, bob)
    bob.execute('''
        local s=OldKraken.DB.workshop.guilds['Realm\\001Guild']
        for k,v in pairs(s.orderObserved) do orderKey=k; order=v end
        assert(order and not order.relayed and s.orderRelays[orderKey])
    ''')
    bob.execute('clock=clock+40')
    tick(carol); flush(carol, bob); tick(bob); flush(bob, carol, True)
    carol.execute('''
        local s=OldKraken.DB.workshop.guilds['Realm\\001Guild']
        for k,v in pairs(s.orderObserved) do orderKey=k; order=v end
        assert(order and order.item=='Relay potion' and order.relayed and order.ownerRev==0)
        assert(not s.orderRelays[orderKey])
        OldKraken.WorkshopOrders:Show(orderKey); assert(OldKrakenWorkshopOrdersFrame.details.text:find('через гільдію'))
        for _,row in ipairs(OldKrakenWorkshopOrdersFrame.orderRows) do if row.entryKey==orderKey then assert(not row.delete:IsShown()) end end
        click('Запропонувати допомогу')
        assert(s.orderIntents['Carol Mon'][orderKey])
    ''')
    restart(carol); restart(bob)
    carol.execute('''
        local s=OldKraken.DB.workshop.guilds['Realm\\001Guild']; assert(s.orderObserved[orderKey].relayed)
        assert(s.orderIntents['Carol Mon'][orderKey] and not s.orderRelays[orderKey])
    ''')
    bob.execute("assert(OldKraken.DB.workshop.guilds['Realm\\001Guild'].orderRelays[orderKey])")
    tick(dave); flush(dave, carol); tick(carol); flush(carol, dave)
    dave.execute("assert(next(OldKraken.DB.workshop.guilds['Realm\\001Guild'].orderObserved)==nil)")
    # A relay may carry a forged higher revision; the owner's next direct snapshot wins.
    bob.execute('''
        local p=OldKraken.DB.workshop.guilds['Realm\\001Guild'].orderRelays[orderKey]
        local f=OldKraken.GroupFinder._unpackFields(p,80); f[3]='999'; fake=OldKraken.GroupFinder._pack(f)
        f[7]='Forged item'; forged=OldKraken.GroupFinder._pack(f); direct=p
    ''')
    eve=client('Eve')
    eve.globals().handlers['WORELAY']('Bob Mon','GUILD',bob.globals().forged)
    eve.globals().handlers['WORDER']('Alice Mon','GUILD',bob.globals().direct)
    eve.execute("local s=OldKraken.DB.workshop.guilds['Realm\\001Guild']; local o; for _,v in pairs(s.orderObserved) do o=v end; assert(o and o.item=='Relay potion' and o.rev==1 and not o.relayed)")
    carol.globals().handlers['WORELAY']('Bob Mon', 'GUILD', bob.globals().fake)
    carol.execute("assert(OldKraken.DB.workshop.guilds['Realm\\001Guild'].orderObserved[orderKey].rev==999)")
    carol.execute('clock=clock+180')
    tick(carol); flush(carol, alice, True); tick(alice)
    alice.execute('''
        for _,packet in ipairs(outgoing) do if packet[1]=='WORDER' then
            local f=OldKraken.GroupFinder._unpackFields(packet[2],80); f[3]='1000'; spoofedAck=OldKraken.GroupFinder._pack(f)
        end end
        assert(spoofedAck)
    ''')
    carol.globals().handlers['WORELAY']('Bob Mon','GUILD',alice.globals().spoofedAck)
    carol.execute("local s=OldKraken.DB.workshop.guilds['Realm\\001Guild']; assert(s.orderObserved[orderKey].rev==1000 and s.orderIntents['Carol Mon'][orderKey])")
    flush(alice, carol)
    carol.execute('''
        local s=OldKraken.DB.workshop.guilds['Realm\\001Guild']; local o=s.orderObserved[orderKey]
        assert(o.rev==2 and not o.relayed and o.candidates['Carol Mon'])
        assert(not s.orderIntents['Carol Mon'][orderKey] and s.orderRelays[orderKey])
    ''')
    # A previously observed terminal state can be recovered while the owner is offline.
    alice.execute("OldKraken.WorkshopOrders:Show(orderKey); local b=OldKrakenWorkshopOrdersFrame.cancel; b.scripts.OnClick(b); assert(order.status=='cancelled')")
    tick(alice); flush(alice, bob)
    bob.execute("assert(OldKraken.DB.workshop.guilds['Realm\\001Guild'].orderObserved[orderKey].status=='cancelled')")
    dave.execute("clock=clock+40; OldKraken.Communication:SendProtocol('WOQUERY','')")
    bob.execute('clock=clock+40')
    flush(dave,bob); tick(bob); flush(bob,dave)
    dave.execute("local s=OldKraken.DB.workshop.guilds['Realm\\001Guild']; local o; for _,v in pairs(s.orderObserved) do o=v end; assert(o and o.status=='cancelled' and o.relayed)")
    alice.execute('''
        OldKraken.WorkshopOrders:Show(orderKey)
        local card; for _,row in ipairs(OldKrakenWorkshopOrdersFrame.orderRows) do if row.entryKey==orderKey then card=row end end
        assert(card and card.delete:IsShown()); card.delete.scripts.OnClick(card.delete)
        assert(order.status=='cancelled'); popup.callback()
        assert(order.status=='deleted' and not card:IsShown())
    ''')
    tick(alice); flush(alice,bob)
    bob.execute("assert(OldKraken.DB.workshop.guilds['Realm\\001Guild'].orderObserved[orderKey].status=='deleted'); OldKraken.WorkshopOrders:Show(); for _,row in ipairs(OldKrakenWorkshopOrdersFrame.orderRows) do assert(row.entryKey~=orderKey) end")
    restart(alice); restart(bob)
    alice.execute("assert(OldKraken.DB.workshop.guilds['Realm\\001Guild'].orderOwners['Alice Mon'][orderKey].status=='deleted')")
    bob.execute("assert(OldKraken.DB.workshop.guilds['Realm\\001Guild'].orderObserved[orderKey].status=='deleted')")
    bob.execute('clock=clock+40'); dave.execute("OldKraken.Communication:SendProtocol('WOQUERY','')")
    flush(dave,bob); tick(bob); flush(bob,dave)
    dave.execute("local s=OldKraken.DB.workshop.guilds['Realm\\001Guild']; local o; for _,v in pairs(s.orderObserved) do o=v end; assert(o and o.status=='deleted')")


def test_embedded_orders():
    lua = client('Cara', embedded=True)
    tick(lua)
    lua.execute('''
        OldKraken.WorkshopOrders:Show()
        local workshop=OldKraken.UIHub.pages.workshop.frame
        assert(OldKraken.UIHub.currentPage=='workshop')
        assert(workshop.ordersView and workshop.ordersView:IsShown())
        assert(workshop.ordersView.width==900 and workshop.ordersView.height==590)
        assert(not workshop.professionView:IsShown())
        assert(workshop.ordersTab.activeBar:IsShown() and not workshop.professionTab.activeBar:IsShown())
        assert(not OldKrakenWorkshopOrdersFrame, 'embedded orders created a separate window')
        assert(workshop.newOrder:IsShown())
        assert(workshop.newOrder.variant=='primary', 'new-order action is not styled as primary')
        workshop.professionTab.scripts.OnClick(workshop.professionTab)
        assert(workshop.professionView:IsShown() and not workshop.ordersView:IsShown())
        assert(workshop.professionTab.activeBar:IsShown() and not workshop.ordersTab.activeBar:IsShown())
        workshop.ordersTab.scripts.OnClick(workshop.ordersTab)
        assert(workshop.ordersView:IsShown() and not workshop.professionView:IsShown())
        workshop.newOrder.scripts.OnClick(workshop.newOrder)
        local form=workshop.ordersView.createForm
        assert(form:IsShown(), 'new-order form did not open modally')
        assert(form.width==720 and form.height==320, 'new-order form is not compact')
        form.item:SetText('Embedded potion')
        selectOption(OldKrakenOrderProfession,171)
        click('Опублікувати')
        assert(not form:IsShown(), 'successful order creation did not close the modal')
        local orders=OldKraken.DB.workshop.guilds['Realm\\001Guild'].orderOwners['Cara Mon']
        local order; for _,entry in pairs(orders) do order=entry end
        assert(order and order.item=='Embedded potion' and order.status=='open')
        OldKraken.WorkshopOrders:Show(order.id)
        assert(workshop.ordersView.details.text:find('Embedded potion'))
        assert(not OldKrakenWorkshopOrdersFrame, 'opening an order escaped the Hub')
    ''')
    print('Embedded workshop order checks passed')


if __name__ == '__main__':
    test_orders()
    test_embedded_orders()
    test_incomplete_profession_scan()
    test_partial_recipe_scan_retains_records()
    test_order_relay_and_owner_authority()
    print('Workshop order checks passed')
