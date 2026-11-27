import subprocess
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
FILES = ('GroupFinder.lua', 'Workshop.lua', 'WorkshopRecipes.lua', 'WorkshopOrders.lua')


def load_sources(ref=None):
    if ref is None:
        return [(ROOT / name).read_text(encoding='utf-8') for name in FILES]
    return [
        subprocess.check_output(['git', 'show', f'{ref}:{name}'], cwd=ROOT).decode('utf-8')
        for name in FILES
    ]


def client(name, ref=None):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().player = name
    lua.execute('''
        now=1700000000; clock=100; outgoing={}; timers={}; frames={}; notices={}; handlers={}; choices={}
        OldKraken={DB={settings={}},UIStyle={
            Colors={brandGold={0.88,0.69,0.32,1}},
            Button=function(button,variant) button.variant=variant end,
            Window=function() end,Dropdown=function() end,Input=function() end,
        }}
        OldKraken.listeners={}
        function OldKraken:On(name,fn) self.listeners[name]=self.listeners[name] or {}; table.insert(self.listeners[name],fn) end
        function OldKraken:Fire(name,...) notices[#notices+1]={name,...}; for _,fn in ipairs(self.listeners[name] or {}) do fn(...) end end
        function print(...) end
        function UnitName() return player,'Mon' end
        function GetGuildInfo() return 'Guild' end
        function GetRealmName() return 'Realm' end
        function GetServerTime() return now end
        function GetTime() return clock end
        function date() return 'date' end
        function GetProfessions() return 1 end
        function GetProfessionInfo() return 'Alchemy',nil,50,300,nil,nil,171 end
        local TEST_RECIPE_NAMES={[9001]='Manual potion',[9002]='Silver potion'}
        C_TradeSkillUI={GetRecipeOutputItemData=function(id) local n=TEST_RECIPE_NAMES[id]; if n then return {hyperlink='['..n..']'} end end}
        UIParent={}; UISpecialFrames={}; StaticPopupDialogs={}
        function StaticPopup_Show(name,a,b,callback)
            popup={callback=callback,GetFrameStrata=function() return 'DIALOG' end,SetFrameStrata=function() end,HookScript=function() end}
            return popup
        end
        function UIDropDownMenu_SetWidth() end
        function UIDropDownMenu_SetText(f,text) f.text=text end
        function UIDropDownMenu_Initialize(f,fn) f.dropdown=fn end
        function UIDropDownMenu_CreateInfo() return {} end
        function UIDropDownMenu_AddButton(item,level) item.level=level or 1; choices[#choices+1]=item end
        function CloseDropDownMenus() end
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
        function pickOrderRecipe(form, name, prof, itemId, recipeId)
            local p = prof or 171
            local rid = recipeId or 9001
            local iid = itemId or 0
            local scope = OldKraken.DB.workshop.guilds['Realm\\001Guild']
            scope.recipes['Helper Crafter'] = scope.recipes['Helper Crafter'] or {}
            scope.recipes['Helper Crafter'][rid] = {recipe=rid, item=iid, profession=p, seen=now, name=name, product=name}
            OldKraken:Fire('INITIALIZED', OldKraken.DB)
            form.item.scripts.OnClick(form.item)
            for _, row in ipairs(frames) do
                if type(row.entry)=='table' and type(row.entry.record)=='table' and row.entry.record.recipe==rid and row.scripts.OnClick then
                    row.scripts.OnClick(row)
                    return
                end
            end
            error('recipe row not found: '..tostring(rid))
        end
        C_Timer={NewTicker=function(_,fn) timers[#timers+1]=fn end}
        OldKraken.Communication={queue={}}
        function OldKraken.Communication:RegisterHandler(kind,fn) handlers[kind]=fn end
        function OldKraken.Communication:SendProtocol(kind,payload) outgoing[#outgoing+1]={kind,payload}; return true end
    ''')
    for source in load_sources(ref):
        lua.execute(source)
    lua.execute('for _,f in ipairs(frames) do if f.events.PLAYER_LOGIN then f.scripts.OnEvent(f,"PLAYER_LOGIN") end end')
    return lua


def tick(lua):
    lua.execute('clock=clock+4; for _,f in ipairs(timers) do f() end')


def flush(sender, recipients):
    outgoing = sender.globals().outgoing
    packets = [(outgoing[i][1], outgoing[i][2]) for i in range(1, len(outgoing) + 1)]
    sender.execute('outgoing={}')
    sender_name = sender.globals().player + ' Mon'
    for recipient in recipients:
        handlers = recipient.globals().handlers
        for kind, payload in packets:
            handler = handlers[kind]
            if handler:
                handler(sender_name, 'GUILD', payload)
    return packets


def test_alpha_to_old_decoders():
    alpha_sender = client('Alice', ref=None)
    v040_recv = client('Bob', ref='v0.4.0')
    v057_recv = client('Carol', ref='v0.5.7')
    tick(alpha_sender); tick(v040_recv); tick(v057_recv)

    # 1. Create order on alpha with rewardSilver = 0 -> v0.4.0 rejects, 0.5.7 accepts
    alpha_sender.execute('''
        OldKraken.WorkshopOrders:Show(); local f=OldKrakenWorkshopOrdersFrame
        pickOrderRecipe(f.orderForm,'Manual potion',171,0,9001); click('Опублікувати')
        local s=OldKraken.DB.workshop.guilds['Realm\\001Guild']
        for k,v in pairs(s.orderOwners['Alice Mon']) do orderKey=k; order=v end
        assert(order and (order.rewardSilver or 0)==0)
    ''')
    tick(alpha_sender)
    pkts_zero = flush(alpha_sender, [v040_recv, v057_recv])
    assert any(k == 'WORDER' for k, _ in pkts_zero)
    v040_recv.execute('''
        local s=OldKraken.DB.workshop.guilds['Realm\\001Guild']
        assert(next(s.orderObserved)==nil, 'v0.4.0 must reject 5-trailer WORDER even with rewardSilver=0')
    ''')
    v057_recv.execute('''
        local s=OldKraken.DB.workshop.guilds['Realm\\001Guild']
        local count=0; for _,v in pairs(s.orderObserved) do count=count+1; assert(v.item=='Manual potion' and (v.rewardSilver or 0)==0) end
        assert(count==1)
    ''')

    # 2. Create second order on alpha with non-zero rewardSilver = 50 -> v0.4.0 rejects, 0.5.7 accepts
    alpha_sender.execute('''
        local f=OldKrakenWorkshopOrdersFrame
        pickOrderRecipe(f.orderForm,'Silver potion',171,0,9002); click('Опублікувати')
        local s=OldKraken.DB.workshop.guilds['Realm\\001Guild']
        local newest
        for k,v in pairs(s.orderOwners['Alice Mon']) do if v.item=='Silver potion' then newest=k; v.rewardSilver=50 end end
        assert(newest)
    ''')
    tick(alpha_sender)
    pkts_silver = flush(alpha_sender, [v040_recv, v057_recv])
    assert any(k == 'WORDER' for k, _ in pkts_silver)
    v040_recv.execute('''
        local s=OldKraken.DB.workshop.guilds['Realm\\001Guild']
        assert(next(s.orderObserved)==nil, 'v0.4.0 must reject WORDER with rewardSilver=50')
    ''')
    v057_recv.execute('''
        local s=OldKraken.DB.workshop.guilds['Realm\\001Guild']
        local found=false
        for _,v in pairs(s.orderObserved) do
            if v.item=='Silver potion' then assert(v.rewardSilver==50); found=true end
        end
        assert(found)
    ''')


def test_old_encoders_to_alpha():
    v040_sender = client('Bob', ref='v0.4.0')
    v057_sender = client('Carol', ref='v0.5.7')
    alpha_recv = client('Alice', ref=None)
    tick(v040_sender); tick(v057_sender); tick(alpha_recv)

    # 1. v0.4.0 (4 trailing fields) -> alpha accepts with rewardSilver = 0
    v040_sender.execute('''
        OldKraken.WorkshopOrders:Show(); local f=OldKrakenWorkshopOrdersFrame
        selectOption(OldKrakenOrderProfession, 171)
        f.orderForm.item:SetText('Manual potion'); click('Опублікувати')
    ''')
    tick(v040_sender)
    pkts_040 = flush(v040_sender, [alpha_recv])
    assert any(k == 'WORDER' for k, _ in pkts_040)
    alpha_recv.execute('''
        local s=OldKraken.DB.workshop.guilds['Realm\\001Guild']
        local found=false
        for _,v in pairs(s.orderObserved) do
            if v.owner=='Bob Mon' then assert(v.item=='Manual potion' and (v.rewardSilver or 0)==0); found=true end
        end
        assert(found)
    ''')

    # 2. 0.5.7 (5 trailing fields, rewardSilver=50) -> alpha accepts
    v057_sender.execute('''
        OldKraken.WorkshopOrders:Show(); local f=OldKrakenWorkshopOrdersFrame
        pickOrderRecipe(f.orderForm,'Silver potion',171,0,9002); click('Опублікувати')
        local s=OldKraken.DB.workshop.guilds['Realm\\001Guild']
        for _,v in pairs(s.orderOwners['Carol Mon']) do v.rewardSilver=50 end
    ''')
    tick(v057_sender)
    pkts_057 = flush(v057_sender, [alpha_recv])
    assert any(k == 'WORDER' for k, _ in pkts_057)
    alpha_recv.execute('''
        local s=OldKraken.DB.workshop.guilds['Realm\\001Guild']
        local found=false
        for _,v in pairs(s.orderObserved) do
            if v.owner=='Carol Mon' then assert(v.item=='Silver potion' and v.rewardSilver==50); found=true end
        end
        assert(found)
    ''')


if __name__ == '__main__':
    test_alpha_to_old_decoders()
    test_old_encoders_to_alpha()
    print('WorkshopOrders backward compatibility checks passed')
