-- Guild crafting requests; the customer owns the authoritative order state.
local Orders={}
OldKraken.WorkshopOrders=Orders
local comm,codec=OldKraken.Communication,OldKraken.GroupFinder
local professionNames={[171]='Алхімія',[164]='Ковальство',[165]='Шкірництво',[197]='Кравецтво',[202]='Інженерія',[333]='Зачарування',[185]='Кулінарія',[129]='Перша допомога',[186]='Гірництво'}
local professionIDs={171,164,165,197,202,333,185,129,186}
local materialNames={customer='Замовника',crafter='Майстра',mixed='Спільні'}
local statusNames={open='Шукає майстра',assigned='У роботі',delivered='Передано',done='Виконано',cancelled='Скасовано'}
local deadlineNames={[3600]='1 година',[21600]='6 годин',[86400]='Доба',[604800]='Тиждень'}
local active,identity,profile,scope,own,observed,intents=false,nil,nil,nil,{}, {}, {}
local dirty,sequence,nextSync,lastQuery={},0,0,-60
local window,selected,offset,view,profession,materials,deadline,orderRows=nil,nil,0,'all',171,'customer',86400,{}
local refresh

local function textOK(s,min,max) return type(s)=='string' and #s>=min and #s<=max and not s:find('[%z\1-\31\127]') end
local function int(n,min,max) return type(n)=='number' and n==n and n%1==0 and n>=min and n<=max end
local function key(owner,id) return owner..'\001'..id end
local function nameOK(s) return textOK(s,1,128) end
local function idOK(s) return textOK(s,1,64) and s:match('^[%w%-]+$')~=nil end
local function size(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
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
    local countIndex=15+n; local ackCount=tonumber(f[countIndex]); if not int(ackCount,0,20) or #f~=countIndex+ackCount*2 then return nil end
    local acks={}
    for i=1,ackCount do
        local name,version=f[countIndex+i*2-1],tonumber(f[countIndex+i*2])
        if not nameOK(name) or name==owner or acks[name] or not int(version,1,9000000000000000) then return nil end
        acks[name]=version
    end
    return {owner=owner,id=id,rev=rev,created=created,deadline=due,profession=prof,item=item,quantity=qty,reward=reward,materials=mats,note=note,status=status,worker=worker~='' and worker or nil,candidates=candidates,acks=acks}
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
local function create(item,qty,reward,note)
    qty,reward=tonumber(qty),tonumber(reward)
    if not active or not textOK(item,1,160) or not int(qty,1,200) or not int(reward,0,100000) or not textOK(note,0,180) or not professionNames[profession] then return false end
    if size(own)>=100 then return false end
    local now=GetServerTime(); sequence=math.max(sequence+1,now*1000)
    local id=tostring(now)..'-'..tostring(math.random(100000,999999))..'-'..tostring(sequence%1000000)
    local o={owner=identity,id=id,rev=1,created=now,deadline=now+deadline,profession=profession,item=item,quantity=qty,reward=reward,materials=materials,note=note,status='open',candidates={},acks={}}
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
    if previous and previous.rev==o.rev and encode(previous)~=payload then return end
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
        if type(settings)=='table' and settings.workshopOrderAlerts~=false then notify('Нове замовлення: '..o.item,professionNames[o.profession]..' · '..o.owner,k) end
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
refresh=function()
    if not window or not window:IsShown() then return end
    local list={}; local seen={}
    for _,source in ipairs({own,observed}) do for k,o in pairs(source) do
        if not seen[k] and (view=='all' or (view=='mine' and o.owner==identity) or (view=='work' and (o.worker==identity or o.candidates[identity]))) then
            seen[k]=true; list[#list+1]={key=k,order=o}
        end
    end end
    table.sort(list,function(a,b) if a.order.created~=b.order.created then return a.order.created>b.order.created end return a.key<b.key end)
    offset=math.max(0,math.min(offset,math.max(0,math.ceil(#list/8)-1)))
    window.page:SetText((offset+1)..' / '..math.max(1,math.ceil(#list/8)))
    window.alerts:SetText((OldKraken.DB.settings.workshopOrderAlerts~=false) and 'Нові: увімк.' or 'Нові: вимк.')
    for i,row in ipairs(orderRows) do
        local entry=list[offset*8+i]
        if entry then
            local o=entry.order; row.entryKey=entry.key
            local state=o.status=='open' and o.deadline<GetServerTime() and 'Термін минув' or statusNames[o.status]
            row:SetText(o.item..' ×'..o.quantity..' · '..state)
            if selected==entry.key then row:LockHighlight() else row:UnlockHighlight() end
            row:Show()
        else row.entryKey=nil; row:UnlockHighlight(); row:Hide() end
    end
    for _,row in ipairs(window.candidates) do row:Hide() end
    local o=selected and get(selected)
    local pending=selected and intents[selected]
    if o then
        local state=o.status=='open' and o.deadline<GetServerTime() and 'Термін минув' or statusNames[o.status]
        window.details:SetText(o.item..' ×'..o.quantity..'\n'..professionNames[o.profession]..' · '..state..'\nЗамовник: '..o.owner..'\nВинагорода: '..o.reward..' зол. · Ресурси: '..materialNames[o.materials]..'\nТермін: '..date('%d.%m.%Y %H:%M',o.deadline)..'\nМайстер: '..(o.worker or 'не обрано')..'\n'..o.note..(pending and '\nОчікується відповідь замовника' or ''))
        window.detailsContent:SetHeight(math.max(132,window.details:GetStringHeight()+8))
        local isOwner=o.owner==identity
        window.offer:SetShown(not isOwner and o.status=='open' and o.deadline>=GetServerTime() and not o.candidates[identity] and not pending)
        window.withdraw:SetShown(not isOwner and not pending and ((o.status=='open' and o.candidates[identity]) or (o.status=='assigned' and o.worker==identity)))
        window.delivered:SetShown(not isOwner and not pending and o.status=='assigned' and o.worker==identity)
        window.finish:SetShown(isOwner and o.status=='delivered')
        window.cancel:SetShown(isOwner and o.status~='done' and o.status~='cancelled')
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
        window.details:SetText('Оберіть замовлення зі списку.'); window.offer:Hide(); window.withdraw:Hide(); window.delivered:Hide(); window.finish:Hide(); window.cancel:Hide(); window.candidateTitle:Hide(); window.candidateScroll:Hide()
    end
end
local function createWindow()
    local f=CreateFrame('Frame','OldKrakenWorkshopOrdersFrame',UIParent,'BasicFrameTemplateWithInset')
    table.insert(UISpecialFrames,'OldKrakenWorkshopOrdersFrame'); f:SetSize(900,650); f:SetPoint('CENTER'); f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag('LeftButton'); f:SetScript('OnDragStart',f.StartMoving); f:SetScript('OnDragStop',f.StopMovingOrSizing)
    OldKraken.UIStyle.Window(f); if f.TitleText then f.TitleText:SetText('Old Kraken — Замовлення') end
    local views={all='Усі замовлення',mine='Мої замовлення',work='Моя робота'}
    dropdown(f,'OldKrakenOrdersView',18,-42,190,{'all','mine','work'},views,function() return view end,function(v) view=v; offset=0; refresh() end)
    f.alerts=button(f,'Нові: увімк.',235,-42,145,function() local s=OldKraken.DB.settings; s.workshopOrderAlerts=s.workshopOrderAlerts==false; refresh() end)
    button(f,'Оновити',390,-42,100,function() nextSync=0; print('Old Kraken: запит замовлень поставлено в чергу.') end)
    for i=1,8 do orderRows[i]=button(f,'',18,-80-(i-1)*32,450,function(self) if self.entryKey then selected=self.entryKey; refresh() end end) end
    button(f,'‹',18,-342,44,function() offset=offset-1; refresh() end)
    f.page=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); f.page:SetPoint('TOPLEFT',f,'TOPLEFT',75,-348)
    button(f,'›',130,-342,44,function() offset=offset+1; refresh() end)
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
    local heading=f:CreateFontString(nil,'OVERLAY','GameFontNormal'); heading:SetPoint('TOPLEFT',f,'TOPLEFT',18,-395); heading:SetText('Нове замовлення')
    f.item=input(f,'Предмет або посилання',18,-420,300,''); f.quantity=input(f,'Кількість',335,-420,65,'1'); f.reward=input(f,'Винагорода (зол.)',420,-420,120,'0')
    f.note=input(f,'Коментар',18,-475,360,'')
    dropdown(f,'OldKrakenOrderProfession',400,-492,170,professionIDs,professionNames,function() return profession end,function(v) profession=v end)
    local profLabel=f:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); profLabel:SetPoint('TOPLEFT',f,'TOPLEFT',400,-475); profLabel:SetText('Професія')
    dropdown(f,'OldKrakenOrderMaterials',580,-492,140,{'customer','crafter','mixed'},materialNames,function() return materials end,function(v) materials=v end)
    local matLabel=f:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); matLabel:SetPoint('TOPLEFT',f,'TOPLEFT',580,-475); matLabel:SetText('Ресурси')
    dropdown(f,'OldKrakenOrderDeadline',18,-550,150,{3600,21600,86400,604800},deadlineNames,function() return deadline end,function(v) deadline=v end)
    local dueLabel=f:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); dueLabel:SetPoint('TOPLEFT',f,'TOPLEFT',18,-533); dueLabel:SetText('Термін')
    button(f,'Опублікувати',650,-548,160,function()
        if create(f.item:GetText(),f.quantity:GetText(),f.reward:GetText(),f.note:GetText()) then f.item:SetText(''); f.note:SetText(''); print('Old Kraken: замовлення збережено та поставлено в чергу.') else showError() end
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
