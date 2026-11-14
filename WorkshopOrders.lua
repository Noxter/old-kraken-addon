-- Guild crafting requests; the customer owns the authoritative order state.
local Orders={}
OldKraken.WorkshopOrders=Orders
local comm,codec=OldKraken.Communication,OldKraken.GroupFinder
local professionNames={[171]='Алхімія',[164]='Ковальство',[165]='Шкірництво',[197]='Кравецтво',[202]='Інженерія',[333]='Зачарування',[185]='Кулінарія',[129]='Перша допомога',[186]='Гірництво'}
local professionIDs={171,164,165,197,202,333,185,129,186}
local materialNames={customer='Замовника',crafter='Майстра',mixed='Спільні'}
local statusNames={open='Шукає майстра',assigned='У роботі',delivered='Передано',done='Виконано',cancelled='Скасовано'}
local deadlineNames={[3600]='1 година',[21600]='6 годин',[86400]='Доба',[604800]='Тиждень'}
local professionIcons={[171]=136240,[164]=136241,[165]=136247,[197]=136249,[202]=136243,[333]=136244,[185]=133971,[129]=135966,[186]=136248}
local statusColors={open={0.35,0.88,0.53},assigned={0.40,0.72,1},delivered={1,0.78,0.30},done={0.70,0.75,0.80},cancelled={1,0.42,0.38},expired={0.72,0.72,0.72}}
local CARDS_PER_PAGE=4
local active,identity,profile,scope,own,observed,intents=false,nil,nil,nil,{}, {}, {}
local dirty,sequence,nextSync,lastQuery={},0,0,-60
local window,selected,offset,view,profession,materials,deadline,orderRows=nil,nil,0,'all',171,'customer',86400,{}
local statusFilter,professionFilter='all',0
local searchQuery=''
local chosenRecipe
local refresh

local function textOK(s,min,max) return type(s)=='string' and #s>=min and #s<=max and not s:find('[%z\1-\31\127]') end
local function int(n,min,max) return type(n)=='number' and n==n and n%1==0 and n>=min and n<=max end
local function key(owner,id) return owner..'\001'..id end
local function nameOK(s) return textOK(s,1,128) end
local function idOK(s) return textOK(s,1,64) and s:match('^[%w%-]+$')~=nil end
local function size(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
local function lower(text)
    text=text:lower():gsub('\208[\144-\175]',function(pair)
        local b=pair:byte(2); if b<=159 then return string.char(208,b+32) end; return string.char(209,b-32)
    end)
    local special={['\208\132']='\209\148',['\208\134']='\209\150',['\208\135']='\209\151',['\210\144']='\210\145'}
    return (text:gsub('[\208\210][\128-\191]',special))
end
local function me()
    if type(UnitName)~='function' then return nil end
    local a,b=UnitName('player'); if not nameOK(a) then return nil end
    if type(b)=='string' and b~='' then a=a..' '..b end
    return nameOK(a) and a or nil
end
local function changed() if refresh then refresh() end end
local function notify(title,subtitle,k) OldKraken:Fire('WORKSHOP_ORDER_NOTICE',title,subtitle,k) end
local function encode(o)
    local fields={o.owner,o.id,o.rev,o.created,o.deadline,o.profession,o.item,o.quantity,o.reward,o.materials,o.note,o.status,o.worker or ''}
    local candidates={}; for name in pairs(o.candidates) do candidates[#candidates+1]=name end; table.sort(candidates)
    fields[#fields+1]=#candidates; for _,name in ipairs(candidates) do fields[#fields+1]=name end
    local ackNames={}; for name in pairs(o.acks or {}) do ackNames[#ackNames+1]=name end; table.sort(ackNames)
    fields[#fields+1]=#ackNames; for _,name in ipairs(ackNames) do fields[#fields+1]=name; fields[#fields+1]=string.format('%.0f',o.acks[name]) end
    fields[#fields+1]=o.itemID or 0; fields[#fields+1]=o.recipeID or 0
    return codec._pack(fields)
end
local function decode(payload,sender)
    local f=codec._unpackFields(payload,80); if not f or #f<15 then return nil end
    local owner,id,rev,created,due,prof,item,qty,reward,mats,note,status,worker,n=unpack(f,1,14)
    rev,created,due,prof,qty,reward,n=tonumber(rev),tonumber(created),tonumber(due),tonumber(prof),tonumber(qty),tonumber(reward),tonumber(n)
    local now=GetServerTime()
    if not nameOK(owner) or owner~=sender or not idOK(id) or not int(rev,1,2147483647) or not int(created,now-2592000,now+600)
        or not int(due,created+1,created+604800) or not professionNames[prof] or not textOK(item,1,160) or not int(qty,1,200)
        or not int(reward,0,100000) or not materialNames[mats] or not textOK(note,0,180) or not statusNames[status]
        or (worker~='' and not nameOK(worker)) or not int(n,0,20) or #f<15+n then return nil end
    if (status=='assigned' or status=='delivered' or status=='done') and worker=='' then return nil end
    if status=='open' and worker~='' then return nil end
    local candidates={}
    for i=1,n do local name=f[14+i]; if not nameOK(name) or name==owner or candidates[name] then return nil end; candidates[name]=true end
    local countIndex=15+n; local ackCount=tonumber(f[countIndex]); if not int(ackCount,0,20) then return nil end
    local endIndex=countIndex+ackCount*2
    if #f~=endIndex and #f~=endIndex+2 then return nil end
    local acks={}
    for i=1,ackCount do
        local name,version=f[countIndex+i*2-1],tonumber(f[countIndex+i*2])
        if not nameOK(name) or name==owner or acks[name] or not int(version,1,9000000000000000) then return nil end
        acks[name]=version
    end
    local itemID,recipeID=tonumber(f[endIndex+1] or 0),tonumber(f[endIndex+2] or 0)
    if not int(itemID,0,100000000) or not int(recipeID,0,100000000) then return nil end
    return {owner=owner,id=id,rev=rev,created=created,deadline=due,profession=prof,item=item,itemID=itemID,recipeID=recipeID,quantity=qty,reward=reward,materials=mats,note=note,status=status,worker=worker~='' and worker or nil,candidates=candidates,acks=acks}
end
local function persist()
    if not scope then return end
    scope.orderOwners[identity]=own; scope.orderObserved=observed; scope.orderIntents[identity]=intents; scope.orderSequences[identity]=sequence
end
local function get(k) return own[k] or observed[k] end
local function fits(o) local ok,payload=pcall(encode,o); return ok and #payload<=2560 end

local function connect()
    local name=me(); local guild=type(GetGuildInfo)=='function' and GetGuildInfo('player'); local realm=type(GetRealmName)=='function' and GetRealmName()
    if not name or not textOK(guild,1,128) or type(realm)~='string' or not OldKraken.DB then
        active,identity,profile,scope,own,observed,intents,dirty=false,nil,nil,nil,{}, {}, {}, {}
        if window then window:Hide() end; return
    end
    local guildKey=realm..'\001'..guild
    if active and identity==name and profile==guildKey then return end
    local db=OldKraken.DB; if type(db.workshop)~='table' then db.workshop={} end
    if type(db.workshop.guilds)~='table' then db.workshop.guilds={} end
    if type(db.workshop.guilds[guildKey])~='table' then db.workshop.guilds[guildKey]={} end
    scope=db.workshop.guilds[guildKey]
    for _,field in ipairs({'orderOwners','orderObserved','orderIntents','orderSequences'}) do if type(scope[field])~='table' then scope[field]={} end end
    active,identity,profile=true,name,guildKey
    own,observed,intents,dirty={}, {}, {}, {}
    local function loadOrders(source,target,requireOwner)
        if type(source)~='table' then return end
        for k,o in pairs(source) do
            if size(target)>=100 then break end
            if type(o)=='table' and type(o.candidates)=='table' and type(o.acks)=='table' and nameOK(o.owner) and (not requireOwner or o.owner==identity) then
                local ok,payload=pcall(encode,o); local valid=ok and decode(payload,o.owner)
                if valid and k==key(valid.owner,valid.id) then target[k]=valid end
            end
        end
    end
    loadOrders(scope.orderOwners[name],own,true); loadOrders(scope.orderObserved,observed,false)
    local stored=scope.orderIntents[name]
    if type(stored)=='table' then for k,v in pairs(stored) do
        if type(k)=='string' and #k<194 and type(v)=='table' and (v.action=='offer' or v.action=='withdraw' or v.action=='delivered') and int(v.version,1,9000000000000000) then intents[k]={action=v.action,version=v.version} end
    end end
    sequence=int(scope.orderSequences[name],0,9000000000000000) and scope.orderSequences[name] or 0
    for k in pairs(own) do dirty[k]=true end
    nextSync,lastQuery=0,-60; persist(); changed()
end
local function create(item,qty,reward,note,recipe)
    qty,reward=tonumber(qty),tonumber(reward)
    if not active or not textOK(item,1,160) or not int(qty,1,200) or not int(reward,0,100000) or not textOK(note,0,180) or not professionNames[profession] then return false end
    if size(own)>=100 then return false end
    local now=GetServerTime(); sequence=math.max(sequence+1,now*1000)
    local id=tostring(now)..'-'..tostring(math.random(100000,999999))..'-'..tostring(sequence%1000000)
    local itemID=recipe and recipe.item or tonumber(item:match('item:(%d+)')) or 0
    local recipeID=recipe and recipe.recipe or 0
    if not int(itemID,0,100000000) or not int(recipeID,0,100000000) then return false end
    local o={owner=identity,id=id,rev=1,created=now,deadline=now+deadline,profession=profession,item=item,itemID=itemID,recipeID=recipeID,quantity=qty,reward=reward,materials=materials,note=note,status='open',candidates={},acks={}}
    if not fits(o) then return false end
    local k=key(identity,id); own[k]=o; dirty[k]=true; selected=k; persist(); changed(); return true
end
local function intent(k,action)
    local o=get(k); if not active or not o or o.owner==identity or intents[k] then return false end
    if action=='offer' and (o.status~='open' or o.deadline<GetServerTime() or o.candidates[identity]) then return false end
    if action=='withdraw' and not ((o.status=='open' and o.candidates[identity]) or (o.status=='assigned' and o.worker==identity)) then return false end
    if action=='delivered' and not (o.status=='assigned' and o.worker==identity) then return false end
    sequence=math.max(sequence+1,GetServerTime()*1000); intents[k]={action=action,version=sequence}; nextSync=0; persist(); changed(); return true
end
local function ownerAction(k,action,actor)
    local o=own[k]; if not active or not o then return false end
    local oldStatus,oldWorker=o.status,o.worker
    if action=='choose' then
        if o.status~='open' or not o.candidates[actor] or o.deadline<GetServerTime() then return false end
        o.status,o.worker='assigned',actor
    elseif action=='finish' then if o.status~='delivered' then return false end; o.status='done'
    elseif action=='cancel' then if o.status=='done' or o.status=='cancelled' then return false end; o.status='cancelled'
    else return false end
    o.rev=o.rev+1
    if not fits(o) then o.status,o.worker,o.rev=oldStatus,oldWorker,o.rev-1; return false end
    dirty[k]=true; persist(); changed(); return true
end

comm:RegisterHandler('WORDER',function(sender,_,payload)
    if not active or sender==identity then return end
    local o=decode(payload,sender); if not o then return end
    local k=key(o.owner,o.id); local previous=observed[k]
    if previous and previous.rev>o.rev then return end
    if previous and previous.rev==o.rev and encode(previous)~=encode(o) then return end
    if not previous and size(observed)>=100 then return end
    observed[k]=o
    local pending=intents[k]
    if pending and (o.acks[identity] or 0)>=pending.version then
        local applied=(pending.action=='offer' and o.candidates[identity]) or (pending.action=='withdraw' and not o.candidates[identity] and o.worker~=identity) or (pending.action=='delivered' and o.status=='delivered' and o.worker==identity)
        intents[k]=nil
        if not applied then notify('Дію щодо замовлення не виконано',o.item..' · стан змінився',k) end
    end
    if not previous and o.status=='open' and o.rev==1 and GetServerTime()-o.created<=120 then
        local settings=OldKraken.DB and OldKraken.DB.settings
        if type(settings)=='table' and settings.workshopOrderAlerts~=false and OldKraken.WorkshopRecipes
            and OldKraken.WorkshopRecipes:Knows(o.itemID or 0,o.recipeID or 0) then
            notify('Нове замовлення: '..o.item,professionNames[o.profession]..' · '..o.owner,k)
        end
    elseif previous and o.rev>previous.rev then
        if o.worker==identity and previous.worker~=identity and o.status=='assigned' then notify('Вас обрано майстром',o.item..' · '..o.owner,k)
        elseif previous.candidates[identity] and o.status=='assigned' and o.worker~=identity and previous.status=='open' then notify('Обрано іншого майстра',o.item..' · '..o.owner,k)
        elseif (previous.worker==identity or previous.candidates[identity]) and o.status=='cancelled' and previous.status~='cancelled' then notify('Замовлення скасовано',o.item..' · '..o.owner,k)
        elseif previous.worker==identity and o.status=='done' and previous.status~='done' then notify('Замовлення підтверджено',o.item..' · '..o.owner,k) end
    end
    persist(); changed()
end)
comm:RegisterHandler('WOREQ',function(sender,_,payload)
    if not active or not nameOK(sender) or sender==identity then return end
    local f=codec._unpackFields(payload,4); if not f or #f~=4 or f[1]~=identity or not idOK(f[2]) then return end
    local action,version=f[3],tonumber(f[4]); if (action~='offer' and action~='withdraw' and action~='delivered') or not int(version,1,9000000000000000) then return end
    local function reject(reason) comm:SendProtocol('WOERROR',codec._pack({identity,f[2],sender,string.format('%.0f',version),reason})) end
    local k=key(identity,f[2]); local o=own[k]; if not o then reject('missing'); return end
    if (o.acks[sender] or 0)>=version then dirty[k]=true; return end
    if not o.acks[sender] and size(o.acks)>=20 then reject('capacity'); return end
    local prevStatus,prevWorker,wasCandidate,prevAck=o.status,o.worker,o.candidates[sender],o.acks[sender]
    if action=='offer' and o.status=='open' and o.deadline>=GetServerTime() and size(o.candidates)<20 then o.candidates[sender]=true
    elseif action=='withdraw' and o.status=='open' then o.candidates[sender]=nil
    elseif action=='withdraw' and o.status=='assigned' and o.worker==sender then o.status,o.worker='open',nil; o.candidates[sender]=nil
    elseif action=='delivered' and o.status=='assigned' and o.worker==sender then o.status='delivered' end
    o.acks[sender]=version; o.rev=o.rev+1
    if not fits(o) then o.status,o.worker,o.candidates[sender],o.acks[sender],o.rev=prevStatus,prevWorker,wasCandidate,prevAck,o.rev-1; reject('capacity'); return end
    dirty[k]=true; persist(); changed()
    if action=='offer' and not wasCandidate and o.candidates[sender] then notify('Майстер пропонує допомогу',sender..' · '..o.item,k)
    elseif action=='delivered' and prevStatus=='assigned' and o.status=='delivered' then notify('Майстер позначив передачу',sender..' · '..o.item,k)
    elseif action=='withdraw' and prevWorker==sender and o.status=='open' then notify('Майстер відмовився',sender..' · '..o.item,k) end
end)
comm:RegisterHandler('WOERROR',function(sender,_,payload)
    if not active then return end
    local f=codec._unpackFields(payload,5)
    if not f or #f~=5 or sender~=f[1] or f[3]~=identity or (f[5]~='capacity' and f[5]~='missing') or not idOK(f[2]) then return end
    local k=key(sender,f[2]); local pending=intents[k]
    if not pending or tonumber(f[4])~=pending.version then return end
    intents[k]=nil; persist(); changed()
    notify('Дію щодо замовлення не виконано',f[5]=='capacity' and 'Досягнуто ліміту учасників або розміру даних' or 'Замовлення більше недоступне',k)
end)
comm:RegisterHandler('WOQUERY',function(sender,_,payload)
    if not active or payload~='' or sender==identity then return end
    local now=GetTime(); if now-lastQuery<30 then return end; lastQuery=now
    for k in pairs(own) do dirty[k]=true end
end)

local listener=CreateFrame('Frame')
for _,event in ipairs({'PLAYER_LOGIN','PLAYER_GUILD_UPDATE','GUILD_ROSTER_UPDATE'}) do pcall(listener.RegisterEvent,listener,event) end
listener:SetScript('OnEvent',function() connect() end)
if C_Timer and type(C_Timer.NewTicker)=='function' then C_Timer.NewTicker(3,function()
    connect(); if not active then return end
    local now=GetTime(); if now>=nextSync then
        if comm:SendProtocol('WOQUERY','') then nextSync=now+180 end
        for k,pending in pairs(intents) do local o=observed[k]; if o then comm:SendProtocol('WOREQ',codec._pack({o.owner,o.id,pending.action,string.format('%.0f',pending.version)})) end end
    end
    local expired=false; for k,o in pairs(own) do if o.created<GetServerTime()-2592000 then own[k],dirty[k]=nil,nil; expired=true end end
    for k,o in pairs(observed) do if o.created<GetServerTime()-2592000 then observed[k],intents[k]=nil,nil; expired=true end end
    if expired then persist(); changed() end
    local k=next(dirty); if k then local o=own[k]; if not o or comm:SendProtocol('WORDER',encode(o)) then dirty[k]=nil end end
end) end

local function button(parent,label,x,y,width,callback)
    local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate'); OldKraken.UIStyle.Button(b)
    b:SetSize(width,24); b:SetPoint('TOPLEFT',parent,'TOPLEFT',x,y); b:SetText(label); b:SetScript('OnClick',callback); return b
end
local function input(parent,label,x,y,width,initial)
    local t=parent:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); t:SetPoint('TOPLEFT',parent,'TOPLEFT',x,y); t:SetText(label)
    local e=CreateFrame('EditBox',nil,parent,'InputBoxTemplate'); e:SetSize(width,22); e:SetPoint('TOPLEFT',parent,'TOPLEFT',x+4,y-18); e:SetAutoFocus(false); e:SetText(initial or '')
    e:SetScript('OnEscapePressed',function(self) self:ClearFocus() end); return e
end
local function dropdown(parent,name,x,y,width,values,labels,get,set)
    local f=CreateFrame('Frame',name,parent,'UIDropDownMenuTemplate'); OldKraken.UIStyle.Dropdown(f)
    f:SetPoint('TOPLEFT',parent,'TOPLEFT',x-16,y+3); UIDropDownMenu_SetWidth(f,width-34)
    UIDropDownMenu_Initialize(f,function(_,level)
        for _,v in ipairs(values) do local value=v; local item=UIDropDownMenu_CreateInfo(); item.text=labels[value]; item.value=value; item.checked=get()==value
            item.func=function() set(value); UIDropDownMenu_SetText(f,labels[value]) end; UIDropDownMenu_AddButton(item,level) end
    end)
    UIDropDownMenu_SetText(f,labels[get()]); return f
end
local function showError() print('Old Kraken: дію не виконано. Оновіть дані або перевірте стан замовлення.') end
StaticPopupDialogs.OLDKRAKEN_ORDER_CARD_CANCEL={
    text='Скасувати замовлення «%s»?', button1='Скасувати', button2='Назад',
    timeout=0, whileDead=true, hideOnEscape=true, preferredIndex=3,
    OnAccept=function(_,callback) if type(callback)=='function' then callback() end end,
}
StaticPopupDialogs.OLDKRAKEN_ORDER_CARD_WITHDRAW={
    text='Відмовитися від замовлення «%s»?', button1='Відмовитися', button2='Назад',
    timeout=0, whileDead=true, hideOnEscape=true, preferredIndex=3,
    OnAccept=function(_,callback) if type(callback)=='function' then callback() end end,
}
local function confirmCardAction(k,action)
    local o=k and get(k)
    if not active or not o or (action~='cancel' and action~='withdraw') then showError(); return end
    local expectedProfile,expectedIdentity,expectedStatus=profile,identity,o.status
    local function accept()
        local current=get(k)
        if not active or profile~=expectedProfile or identity~=expectedIdentity or not current or current.status~=expectedStatus then showError(); return end
        local ok
        if action=='cancel' then ok=ownerAction(k,'cancel') else ok=intent(k,'withdraw') end
        if not ok then showError() end
    end
    local popup=StaticPopup_Show(action=='cancel' and 'OLDKRAKEN_ORDER_CARD_CANCEL' or 'OLDKRAKEN_ORDER_CARD_WITHDRAW',o.item,nil,accept)
    if not popup then showError(); return end
    if not popup.oldKrakenRestoreHook then
        popup:HookScript('OnHide',function(self)
            if self.oldKrakenStrata then self:SetFrameStrata(self.oldKrakenStrata); self.oldKrakenStrata=nil end
        end)
        popup.oldKrakenRestoreHook=true
    end
    if not popup.oldKrakenStrata then popup.oldKrakenStrata=popup:GetFrameStrata() end
    popup:SetFrameStrata('FULLSCREEN_DIALOG')
end
local function orderIcon(o)
    local getIcon=type(C_Item)=='table' and C_Item.GetItemIconByID or GetItemIcon
    if (o.itemID or 0)>0 and type(getIcon)=='function' then
        local ok,icon=pcall(getIcon,o.itemID)
        if ok and not (type(issecretvalue)=='function' and issecretvalue(icon)) and (type(icon)=='number' or type(icon)=='string') then return icon end
    end
    return professionIcons[o.profession] or 134400
end
refresh=function()
    if not window or not window:IsShown() then return end
    local list={}; local seen={}
    for _,source in ipairs({own,observed}) do for k,o in pairs(source) do
        local status=o.status=='open' and o.deadline<GetServerTime() and 'expired' or o.status
        local available=view=='available' and o.owner~=identity and status=='open' and not o.candidates[identity] and not intents[k]
            and OldKraken.WorkshopRecipes and OldKraken.WorkshopRecipes:Knows(o.itemID or 0,o.recipeID or 0)
        if not seen[k] and (view=='all' or (view=='mine' and o.owner==identity) or (view=='work' and (o.worker==identity or o.candidates[identity])) or (view=='available' and available))
            and (statusFilter=='all' or statusFilter==status) and (professionFilter==0 or professionFilter==o.profession)
            and (searchQuery=='' or lower(o.item):find(searchQuery,1,true) or lower(o.owner):find(searchQuery,1,true)) then
            seen[k]=true; list[#list+1]={key=k,order=o}
        end
    end end
    table.sort(list,function(a,b) if a.order.created~=b.order.created then return a.order.created>b.order.created end return a.key<b.key end)
    if selected and not seen[selected] then selected=nil end
    offset=math.max(0,math.min(offset,math.max(0,math.ceil(#list/CARDS_PER_PAGE)-1)))
    window.page:SetText((offset+1)..' / '..math.max(1,math.ceil(#list/CARDS_PER_PAGE)))
    window.empty:SetShown(#list==0)
    window.alerts:SetText((OldKraken.DB.settings.workshopOrderAlerts~=false) and 'Нові: увімк.' or 'Нові: вимк.')
    for i,row in ipairs(orderRows) do
        local entry=list[offset*CARDS_PER_PAGE+i]
        if entry then
            local o=entry.order; row.entryKey=entry.key
            local stateKey=o.status=='open' and o.deadline<GetServerTime() and 'expired' or o.status
            row.order=o; row.icon:SetTexture(orderIcon(o))
            row.title:SetText(o.item)
            row.meta:SetText(professionNames[o.profession]..' · '..o.owner)
            row.reward:SetText(o.quantity..' шт. · '..o.reward..' зол. · до '..date('%d.%m %H:%M',o.deadline))
            row.state:SetText(stateKey=='expired' and 'Термін минув' or statusNames[stateKey])
            row.state:SetTextColor(unpack(statusColors[stateKey] or statusColors.expired))
            local canWithdraw=o.owner~=identity and not intents[entry.key]
                and ((o.status=='open' and o.candidates[identity]) or (o.status=='assigned' and o.worker==identity))
            row.withdraw:SetShown(canWithdraw and true or false)
            if o.owner~=identity and stateKey=='open' then
                row.offer:Show()
                row.offer:SetWidth(canWithdraw and 99 or 203)
                if intents[entry.key] then row.offer:SetText('Очікується відповідь'); row.offer:Disable()
                elseif o.candidates[identity] then row.offer:SetText('Відгук є'); row.offer:Disable()
                else row.offer:SetText('Запропонувати допомогу'); row.offer:Enable() end
            else row.offer:Hide() end
            if o.owner==identity and o.status=='open' then
                local applicants={}; for name in pairs(o.candidates) do applicants[#applicants+1]=name end; table.sort(applicants)
                row.applicants:SetText(#applicants>0 and ('Відгуки: '..applicants[1]..(#applicants>1 and (' +'..(#applicants-1)) or '')) or 'Відгуків ще немає')
                row.applicants:Show()
                if #applicants>0 then
                    row.choose:SetText(stateKey=='expired' and 'Термін минув' or ('Обрати ('..#applicants..')'))
                    if stateKey=='expired' then row.choose:Disable() else row.choose:Enable() end
                    row.choose:Show()
                else row.choose:Hide() end
            else row.applicants:Hide(); row.choose:Hide() end
            if o.worker==identity and o.owner~=identity and o.status=='assigned' then
                row.progress:SetText(intents[entry.key] and 'Очікується відповідь' or 'Передав')
                row.progress:SetWidth(canWithdraw and 99 or 203)
                if intents[entry.key] then row.progress:Disable() else row.progress:Enable() end
                row.progress:Show()
            elseif o.owner==identity and o.status=='delivered' then
                row.progress:SetWidth(99); row.progress:SetText('Отримано'); row.progress:Enable(); row.progress:Show()
            else row.progress:Hide() end
            if o.owner==identity and o.status~='done' and o.status~='cancelled' then
                row.cancel:ClearAllPoints()
                row.cancel:SetPoint('TOPLEFT',row,'TOPLEFT',112,o.status=='open' and -94 or -84)
                row.cancel:SetHeight(o.status=='open' and 19 or 24); row.cancel:Show()
            else row.cancel:Hide() end
            if selected==entry.key then row:LockHighlight() else row:UnlockHighlight() end
            row:Show()
        else row.entryKey=nil; row.order=nil; row:UnlockHighlight(); row:Hide() end
    end
    for _,row in ipairs(window.candidates) do row:Hide() end
    local o=selected and get(selected)
    local pending=selected and intents[selected]
    if o then
        local state=o.status=='open' and o.deadline<GetServerTime() and 'Термін минув' or statusNames[o.status]
        local hasRecipe=(o.itemID or 0)>0 or (o.recipeID or 0)>0
        local masters=hasRecipe and OldKraken.WorkshopRecipes and OldKraken.WorkshopRecipes:FindMasters(o.itemID or 0,o.recipeID or 0) or {}
        local names={}; for i=1,math.min(#masters,3) do names[#names+1]=masters[i].name..' ('..date('%d.%m',masters[i].seen)..')' end
        local known=hasRecipe and ('\nВідомі майстри: '..(#names>0 and table.concat(names,', ') or 'немає даних')..(#masters>3 and (' +'..(#masters-3)) or '')) or '\nМайстри: оберіть рецепт або посилання на предмет'
        window.details:SetText(o.item..' ×'..o.quantity..'\n'..professionNames[o.profession]..' · '..state..'\nЗамовник: '..o.owner..'\nВинагорода: '..o.reward..' зол. · Ресурси: '..materialNames[o.materials]..'\nТермін: '..date('%d.%m.%Y %H:%M',o.deadline)..'\nМайстер: '..(o.worker or 'не обрано')..known..'\n'..o.note..(pending and '\nОчікується відповідь замовника' or ''))
        window.detailsContent:SetHeight(math.max(132,window.details:GetStringHeight()+8))
        local isOwner=o.owner==identity
        window.offer:SetShown(not isOwner and o.status=='open' and o.deadline>=GetServerTime() and not o.candidates[identity] and not pending)
        window.withdraw:SetShown(not isOwner and not pending and ((o.status=='open' and o.candidates[identity]) or (o.status=='assigned' and o.worker==identity)))
        window.delivered:SetShown(not isOwner and not pending and o.status=='assigned' and o.worker==identity)
        window.finish:SetShown(isOwner and o.status=='delivered')
        window.cancel:SetShown(isOwner and o.status~='done' and o.status~='cancelled')
        window.masters:SetShown(hasRecipe)
        if isOwner and o.status=='open' then
            local names={}; for name in pairs(o.candidates) do names[#names+1]=name end; table.sort(names)
            window.candidateTitle:SetText(#names>0 and 'Оберіть майстра:' or 'Пропозицій майстрів поки немає')
            for i,name in ipairs(names) do
                local row=window.candidates[i]
                if not row then
                    row=CreateFrame('Frame',nil,window.candidateContent); row:SetSize(330,28)
                    row.label=row:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); row.label:SetPoint('LEFT',row,'LEFT',0,0); row.label:SetWidth(200); row.label:SetJustifyH('LEFT')
                    row.choose=button(row,'Обрати',210,0,100,function(self) if not ownerAction(selected,'choose',self:GetParent().person) then showError() end end)
                    window.candidates[i]=row
                end
                row.person=name; row:ClearAllPoints(); row:SetPoint('TOPLEFT',window.candidateContent,'TOPLEFT',0,-(i-1)*30); row.label:SetText(name); row:Show()
            end
            window.candidateContent:SetHeight(math.max(90,#names*30)); window.candidateTitle:Show(); window.candidateScroll:Show()
        else window.candidateTitle:Hide(); window.candidateScroll:Hide() end
    else
        window.details:SetText('Оберіть замовлення зі списку.'); window.offer:Hide(); window.withdraw:Hide(); window.delivered:Hide(); window.finish:Hide(); window.cancel:Hide(); window.masters:Hide(); window.candidateTitle:Hide(); window.candidateScroll:Hide()
    end
end
local function createWindow()
    local f=CreateFrame('Frame','OldKrakenWorkshopOrdersFrame',UIParent,'BasicFrameTemplateWithInset')
    table.insert(UISpecialFrames,'OldKrakenWorkshopOrdersFrame'); f:SetSize(900,650); f:SetPoint('CENTER'); f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag('LeftButton'); f:SetScript('OnDragStart',f.StartMoving); f:SetScript('OnDragStop',f.StopMovingOrSizing)
    OldKraken.UIStyle.Window(f); if f.TitleText then f.TitleText:SetText('Old Kraken — Замовлення') end
    local views={all='Усі замовлення',available='Доступні мені',mine='Мої замовлення',work='Моя робота'}
    dropdown(f,'OldKrakenOrdersView',18,-42,190,{'all','available','mine','work'},views,function() return view end,function(v) view=v; offset=0; refresh() end)
    f.alerts=button(f,'Нові: увімк.',235,-42,145,function() local s=OldKraken.DB.settings; s.workshopOrderAlerts=s.workshopOrderAlerts==false; refresh() end)
    button(f,'Оновити',390,-42,100,function() nextSync=0; print('Old Kraken: запит замовлень поставлено в чергу.') end)
    local statusLabels={all='Усі стани',open='Шукає майстра',assigned='У роботі',delivered='Передано',done='Виконано',cancelled='Скасовано',expired='Термін минув'}
    dropdown(f,'OldKrakenOrdersStatus',500,-42,165,{'all','open','assigned','delivered','done','cancelled','expired'},statusLabels,function() return statusFilter end,function(v) statusFilter=v; offset=0; refresh() end)
    local professionLabels={[0]='Усі професії'}; local filterIDs={0}
    for _,id in ipairs(professionIDs) do professionLabels[id]=professionNames[id]; filterIDs[#filterIDs+1]=id end
    dropdown(f,'OldKrakenOrdersFilterProfession',675,-42,185,filterIDs,professionLabels,function() return professionFilter end,function(v) professionFilter=v; offset=0; refresh() end)
    f.empty=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); f.empty:SetPoint('TOPLEFT',f,'TOPLEFT',25,-88); f.empty:SetWidth(430); f.empty:SetJustifyH('LEFT'); f.empty:SetText('Замовлень не знайдено. Змініть фільтри або створіть замовлення.')
    for i=1,CARDS_PER_PAGE do
        local col=(i-1)%2; local line=math.floor((i-1)/2)
        local card=button(f,'',18+col*229,-80-line*124,219,function(self) if self.entryKey then selected=self.entryKey; refresh() end end)
        card:SetHeight(116)
        card.icon=card:CreateTexture(nil,'ARTWORK'); card.icon:SetPoint('TOPLEFT',card,'TOPLEFT',7,-8); card.icon:SetSize(34,34)
        local function label(template,y)
            local text=card:CreateFontString(nil,'OVERLAY',template); text:SetPoint('TOPLEFT',card,'TOPLEFT',48,y); text:SetPoint('RIGHT',card,'RIGHT',-6,0); text:SetJustifyH('LEFT'); text:SetWordWrap(false); return text
        end
        card.title=label('GameFontNormal',-6); card.meta=label('GameFontHighlightSmall',-25)
        card.reward=label('GameFontHighlightSmall',-42); card.state=label('GameFontNormalSmall',-59)
        card.offer=button(card,'Запропонувати допомогу',8,-84,203,function(self)
            local k=self:GetParent().entryKey
            if not k or not intent(k,'offer') then showError() end
        end)
        card.progress=button(card,'Передав',8,-84,203,function(self)
            local k=self:GetParent().entryKey; local o=k and get(k)
            if not o then showError(); return end
            if o.owner==identity and o.status=='delivered' then
                if not ownerAction(k,'finish') then showError() end
            elseif o.worker==identity and o.status=='assigned' then
                if not intent(k,'delivered') then showError() end
            else showError() end
        end)
        card.withdraw=button(card,'Відмовитися',112,-84,99,function(self)
            local k=self:GetParent().entryKey
            confirmCardAction(k,'withdraw')
        end)
        card.cancel=button(card,'Скасувати',112,-84,99,function(self)
            local k=self:GetParent().entryKey
            confirmCardAction(k,'cancel')
        end)
        card.applicants=card:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
        card.applicants:SetPoint('TOPLEFT',card,'TOPLEFT',8,-76); card.applicants:SetWidth(203); card.applicants:SetJustifyH('LEFT'); card.applicants:SetWordWrap(false)
        card.menu=CreateFrame('Frame','OldKrakenOrderCardMenu'..i,card,'UIDropDownMenuTemplate')
        UIDropDownMenu_Initialize(card.menu,function(menu,level)
            local target=menu.orderKey; local o=target and own[target]
            if not o or o.status~='open' or o.deadline<GetServerTime() then return end
            local names={}; for name in pairs(o.candidates) do names[#names+1]=name end; table.sort(names)
            for _,name in ipairs(names) do
                local person=name; local item=UIDropDownMenu_CreateInfo(); item.text=person; item.notCheckable=true
                item.func=function() if not ownerAction(target,'choose',person) then showError() end end
                UIDropDownMenu_AddButton(item,level)
            end
        end,'MENU')
        card.choose=button(card,'Обрати',8,-94,99,function(self)
            local parent=self:GetParent(); parent.menu.orderKey=parent.entryKey
            if not parent.menu.orderKey then return end
            ToggleDropDownMenu(1,nil,parent.menu,self,0,0)
            local list=_G.DropDownList1
            if list and list:IsShown() then
                if not list.oldKrakenRestoreHook then
                    list:HookScript('OnHide',function(menu) if menu.oldKrakenStrata then menu:SetFrameStrata(menu.oldKrakenStrata); menu.oldKrakenStrata=nil end end)
                    list.oldKrakenRestoreHook=true
                end
                if not list.oldKrakenStrata then list.oldKrakenStrata=list:GetFrameStrata() end
                list:SetFrameStrata('FULLSCREEN_DIALOG')
            end
        end)
        card.choose:SetHeight(19)
        card:SetScript('OnEnter',function(self)
            local o=self.order; if not o or not GameTooltip then return end
            GameTooltip:SetOwner(self,'ANCHOR_RIGHT'); GameTooltip:SetText(o.item)
            GameTooltip:AddLine('Замовник: '..o.owner,1,1,1,true)
            GameTooltip:AddLine('Професія: '..professionNames[o.profession],1,1,1,true)
            GameTooltip:AddLine('Кількість: '..o.quantity..' · Винагорода: '..o.reward..' зол.',1,1,1,true)
            GameTooltip:AddLine('Термін: '..date('%d.%m.%Y %H:%M',o.deadline),1,1,1,true)
            GameTooltip:AddLine('Натисніть, щоб переглянути деталі',0.6,0.9,1,true); GameTooltip:Show()
        end)
        card:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
        orderRows[i]=card
    end
    button(f,'‹',18,-342,44,function() offset=offset-1; refresh() end)
    f.page=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); f.page:SetPoint('TOPLEFT',f,'TOPLEFT',75,-348)
    button(f,'›',130,-342,44,function() offset=offset+1; refresh() end)
    local searchLabel=f:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); searchLabel:SetPoint('TOPLEFT',f,'TOPLEFT',205,-349); searchLabel:SetText('Пошук')
    local search=CreateFrame('EditBox',nil,f,'InputBoxTemplate'); search:SetPoint('TOPLEFT',f,'TOPLEFT',265,-344); search:SetSize(195,22); search:SetAutoFocus(false)
    search:SetScript('OnTextChanged',function(self) searchQuery=lower(self:GetText() or ''); offset=0; refresh() end)
    search:SetScript('OnEscapePressed',function(self) self:ClearFocus() end)
    local detailsScroll=CreateFrame('ScrollFrame','OldKrakenOrderDetailsScroll',f,'UIPanelScrollFrameTemplate'); detailsScroll:SetPoint('TOPLEFT',f,'TOPLEFT',495,-80); detailsScroll:SetSize(340,132)
    f.detailsContent=CreateFrame('Frame',nil,detailsScroll); f.detailsContent:SetSize(330,132); detailsScroll:SetScrollChild(f.detailsContent)
    f.details=f.detailsContent:CreateFontString(nil,'OVERLAY','GameFontHighlight'); f.details:SetPoint('TOPLEFT'); f.details:SetWidth(330); f.details:SetJustifyH('LEFT'); f.details:SetJustifyV('TOP')
    f.candidateTitle=f:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); f.candidateTitle:SetPoint('TOPLEFT',f,'TOPLEFT',495,-225)
    f.candidateScroll=CreateFrame('ScrollFrame','OldKrakenOrdersCandidatesScroll',f,'UIPanelScrollFrameTemplate'); f.candidateScroll:SetPoint('TOPLEFT',f,'TOPLEFT',495,-244); f.candidateScroll:SetSize(340,90)
    f.candidateContent=CreateFrame('Frame',nil,f.candidateScroll); f.candidateContent:SetSize(330,90); f.candidateScroll:SetScrollChild(f.candidateContent); f.candidates={}
    f.offer=button(f,'Запропонувати',495,-345,130,function() if not selected or not intent(selected,'offer') then showError() end end)
    f.withdraw=button(f,'Відмовитися',495,-345,130,function() if not selected or not intent(selected,'withdraw') then showError() end end)
    f.delivered=button(f,'Передав',630,-345,100,function() if not selected or not intent(selected,'delivered') then showError() end end)
    f.finish=button(f,'Отримано',495,-345,110,function() if not selected or not ownerAction(selected,'finish') then showError() end end)
    f.cancel=button(f,'Скасувати',610,-345,110,function() if not selected or not ownerAction(selected,'cancel') then showError() end end)
    f.masters=button(f,'Майстри',735,-345,110,function()
        local o=selected and get(selected)
        if o and OldKraken.WorkshopRecipes then OldKraken.WorkshopRecipes:ShowMasters(o.itemID or 0,o.recipeID or 0) end
    end)
    local heading=f:CreateFontString(nil,'OVERLAY','GameFontNormal'); heading:SetPoint('TOPLEFT',f,'TOPLEFT',18,-395); heading:SetText('Нове замовлення')
    f.item=input(f,'Предмет або посилання',18,-420,300,''); f.quantity=input(f,'Кількість',335,-420,65,'1'); f.reward=input(f,'Винагорода (зол.)',420,-420,120,'0')
    f.item:SetScript('OnTextChanged',function() chosenRecipe=nil end)
    f.note=input(f,'Коментар',18,-475,360,'')
    local professionMenu=dropdown(f,'OldKrakenOrderProfession',400,-492,170,professionIDs,professionNames,function() return profession end,function(v) if profession~=v then chosenRecipe=nil end; profession=v end)
    button(f,'Обрати рецепт',560,-438,160,function()
        if not OldKraken.WorkshopRecipes then showError(); return end
        OldKraken.WorkshopRecipes:Choose(function(r)
            if not f:IsShown() or not professionNames[r.profession] then return end
            profession=r.profession; UIDropDownMenu_SetText(professionMenu,professionNames[profession])
            f.item:SetText(r.product~='' and r.product or r.name); chosenRecipe={item=r.item,recipe=r.recipe}
        end)
    end)
    local profLabel=f:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); profLabel:SetPoint('TOPLEFT',f,'TOPLEFT',400,-475); profLabel:SetText('Професія')
    dropdown(f,'OldKrakenOrderMaterials',580,-492,140,{'customer','crafter','mixed'},materialNames,function() return materials end,function(v) materials=v end)
    local matLabel=f:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); matLabel:SetPoint('TOPLEFT',f,'TOPLEFT',580,-475); matLabel:SetText('Ресурси')
    dropdown(f,'OldKrakenOrderDeadline',18,-550,150,{3600,21600,86400,604800},deadlineNames,function() return deadline end,function(v) deadline=v end)
    local dueLabel=f:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); dueLabel:SetPoint('TOPLEFT',f,'TOPLEFT',18,-533); dueLabel:SetText('Термін')
    button(f,'Опублікувати',650,-548,160,function()
        if create(f.item:GetText(),f.quantity:GetText(),f.reward:GetText(),f.note:GetText(),chosenRecipe) then f.item:SetText(''); f.note:SetText(''); print('Old Kraken: замовлення збережено та поставлено в чергу.') else showError() end
    end)
    local note=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); note:SetPoint('TOPLEFT',f,'TOPLEFT',18,-603); note:SetText('Передачу речі й оплату гравці виконують у грі самостійно.')
    f:Hide(); return f
end
function Orders:Show(k)
    connect(); if not active then print('Old Kraken: замовлення доступні учасникам гільдії.'); return end
    if k and get(k) then selected=k end
    if not window then window=createWindow() end
    window:Show(); refresh()
end
OldKraken:On('WORKSHOP_RECIPES_CHANGED',function() changed() end)
