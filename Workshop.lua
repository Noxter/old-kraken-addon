-- Guild profession directory. Each character publishes only their own snapshot.
local Workshop = {currentView='professions', navigationStack={}}
OldKraken.Workshop = Workshop
local comm, codec = OldKraken.Communication, OldKraken.GroupFinder
local professions = {
    {id=171, name='Алхімія'}, {id=164, name='Ковальство'},
    {id=165, name='Шкірництво'}, {id=197, name='Кравецтво'},
    {id=202, name='Інженерія'}, {id=333, name='Зачарування'},
    {id=186, name='Гірництво'}, {id=182, name='Травництво'},
    {id=393, name='Свіжування'}, {id=185, name='Кулінарія'},
    {id=129, name='Перша допомога'}, {id=356, name='Риболовля'},
}
local byID = {}
for _,entry in ipairs(professions) do byID[entry.id]=entry end
local professionArt={
    [171]={136240,'Alchemy'}, [164]={136241,'Blacksmithing'}, [165]={136247,'Leatherworking'},
    [197]={136249,'Tailoring'}, [202]={136243,'Engineering'}, [333]={136244,'Enchanting'},
    [186]={136248,'Mining'}, [182]={136246,'Herbalism'}, [393]={134366,'Skinning'},
    [185]={133971,'Cooking'}, [129]={135966,'FirstAid'}, [356]={136245,'Fishing'},
}
local active, identity, profile, store, records = false, nil, nil, nil, {}
local nativeProfessions={}
local ownProfessionCache
local nativeScan, lastNativeScan
local professionRelayDirty={}
local pending, queryPending, forceBroadcast, lastReply, nextScan = false, false, false, -60, 0
local scanState
local scanStarted,dropCandidate=nil,nil
local frame
local render

local function usable(value, wanted)
    if type(issecretvalue)=='function' and issecretvalue(value) then return false end
    return type(value)==wanted
end
local function fullName()
    if type(UnitName)~='function' then return nil end
    local first,last=UnitName('player')
    if not usable(first,'string') or first=='' or #first>128 then return nil end
    if usable(last,'string') and last~='' then first=first..' '..last end
    if #first>128 then return nil end
    return first
end
local function integer(value, low, high)
    if not usable(value,'number') or value~=value or value%1~=0 or value<low or value>high then return nil end
    return value
end
local function count(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
local scheduleRenderPending=false
local function scheduleRender()
    if scheduleRenderPending then return end
    if not (frame and frame:IsShown() and (not frame.professionView or frame.professionView:IsShown())) then return end
    local function flush()
        scheduleRenderPending=false
        if frame and frame:IsShown() and (not frame.professionView or frame.professionView:IsShown()) then if render then render() end end
    end
    if C_Timer and C_Timer.After then scheduleRenderPending=true; C_Timer.After(0.15,flush) else flush() end
end
local function changed()
    scheduleRender()
    if type(OldKraken.Fire)=='function' then OldKraken:Fire('WORKSHOP_PROFESSIONS_CHANGED') end
end
-- Nil or invalid indexes and temporarily unavailable APIs are not removals.
local function scan()
    if type(GetProfessions)~='function' or type(GetProfessionInfo)~='function' then return nil end
    local ok,a,b,c,d,e,f=pcall(GetProfessions)
    if not ok then return nil end
    local indexes={a,b,c,d,e,f}; local found, seenIndexes, list={},{},{}
    for i=1,6 do
        if type(issecretvalue)=='function' and issecretvalue(indexes[i]) then return nil end
        local index=integer(indexes[i],1,100000)
        if indexes[i]~=nil and not index then return nil end
        if index then
            if seenIndexes[index] then return nil end; seenIndexes[index]=true
            local success,_,_,rank,maximum,_,_,line=pcall(GetProfessionInfo,index)
            if success then
                local id=integer(line,1,1000000)
                local r,m=integer(rank,1,9999),integer(maximum,1,9999)
                if not id or not r or not m then return nil end
                if id and byID[id] and r and m and not found[id] then
                    found[id]=true; list[#list+1]={id=id,rank=r,maximum=m}
                end
            else return nil end
        end
    end
    if #list==0 then
        if type(IsLoggedIn)~='function' or type(UnitExists)~='function' then return nil end
        local loginOk,logged=pcall(IsLoggedIn); local playerOk,player=pcall(UnitExists,'player')
        if not loginOk or not playerOk or not usable(logged,'boolean') or not logged
            or not ((usable(player,'boolean') and player) or (usable(player,'number') and player==1)) then return nil end
    end
    table.sort(list,function(x,y) return x.id<y.id end)
    return list
end
local function encode(record)
    local fields={record.timestamp,#record.list}
    for _,p in ipairs(record.list) do fields[#fields+1]=p.id; fields[#fields+1]=p.rank; fields[#fields+1]=p.maximum end
    return codec._pack(fields)
end
local function decode(payload)
    local f=codec._unpackFields(payload,38)
    if not f or #f<2 then return nil end
    local timestamp,n=tonumber(f[1]),tonumber(f[2])
    if not integer(timestamp,1,GetServerTime()+600) or not integer(n,0,12) or #f~=2+n*3 then return nil end
    local found,list={},{}
    for i=1,n do
        local id,rank,maximum=tonumber(f[i*3]),tonumber(f[i*3+1]),tonumber(f[i*3+2])
        if not integer(id,1,1000000) or not byID[id] or found[id] or not integer(rank,1,9999) or not integer(maximum,1,9999) then return nil end
        found[id]=true; list[#list+1]={id=id,rank=rank,maximum=maximum}
    end
    return {timestamp=timestamp,list=list}
end
local function receiveProfession(owner,payload,relayed)
    local value=decode(payload); if not value or owner==identity then return end
    local old=records[owner]
    if type(old)~='table' or not integer(old.timestamp,1,GetServerTime()+600) then old=nil end
    if type(old)=='table' then
        local lastDirect=integer(old.directTimestamp,0,GetServerTime()+600) or (not old.relayed and old.timestamp or 0)
        if relayed then if old.timestamp>=value.timestamp then return end
        elseif value.timestamp<lastDirect or (not old.relayed and old.timestamp==value.timestamp) then return
        elseif old.relayed and value.timestamp<old.timestamp then old.directTimestamp=math.max(lastDirect,value.timestamp); return end
        value.directTimestamp=relayed and lastDirect or value.timestamp
    else
        if count(records)>=1000 then return end
        value.directTimestamp=relayed and 0 or value.timestamp
    end
    value.relayed=relayed and true or false
    if not relayed then store.professionRelays[owner]=payload
    else store.professionRelays[owner]=nil; professionRelayDirty[owner]=nil end
    records[owner]=value; changed()
end
comm:RegisterHandler('WKPROF',function(sender,_,payload)
    if not active or not usable(sender,'string') or sender=='' or #sender>128 or sender==identity then return end
    receiveProfession(sender,payload,false)
end)
comm:RegisterHandler('WKRELAY',function(sender,_,payload)
    if not active or not usable(sender,'string') or sender=='' or #sender>128 or sender==identity then return end
    local f=codec._unpackFields(payload,2)
    if not f or #f~=2 or not usable(f[1],'string') or f[1]=='' or #f[1]>128 or f[1]:find('[%z\1-\31\127]') or f[1]==sender or f[1]==identity then return end
    receiveProfession(f[1],f[2],true)
end)
comm:RegisterHandler('WKQUERY',function(sender,_,payload)
    if not active or payload~='' or sender==identity then return end
    local now=GetTime(); if now-lastReply<30 then return end
    lastReply=now; forceBroadcast=true; nextScan=0
    for owner in pairs(store.professionRelays) do professionRelayDirty[owner]=true end
end)

local function connect()
    local name=fullName()
    local guild=type(GetGuildInfo)=='function' and GetGuildInfo('player')
    local realm=type(GetRealmName)=='function' and GetRealmName() or nil
    if not name or not usable(guild,'string') or guild=='' or #guild>128 or not usable(realm,'string') or not OldKraken.DB then
        active,identity,profile,store,records,nativeProfessions=false,nil,nil,nil,{},{}
        if frame then frame:Hide() end
        return
    end
    local key=realm..'\001'..guild
    if active and profile==key and identity==name then return end
    Workshop.navigationStack={}; Workshop.currentView='professions'
    if frame and frame.professionView and Workshop.SetView then Workshop:SetView('professions') end
    local db=OldKraken.DB
    if type(db.workshop)~='table' then db.workshop={} end
    if type(db.workshop.guilds)~='table' then db.workshop.guilds={} end
    if type(db.workshop.guilds[key])~='table' then db.workshop.guilds[key]={} end
    local scope=db.workshop.guilds[key]
    if type(scope.records)~='table' then scope.records={} end
    if type(scope.professionRelays)~='table' then scope.professionRelays={} end
    active,identity,profile,store,records=true,name,key,scope,scope.records
    professionRelayDirty={}
    for owner,payload in pairs(scope.professionRelays) do
        if not usable(owner,'string') or owner=='' or #owner>128 or type(payload)~='string' or not decode(payload) then scope.professionRelays[owner]=nil end
    end
    nativeProfessions={}
    nativeScan,lastNativeScan=nil,nil
    scanState=nil
    scanStarted,dropCandidate=type(GetTime)=='function' and GetTime() or nil,nil
    pending,queryPending,forceBroadcast,lastReply,nextScan=false,true,true,-60,0
    changed()
end
function Workshop:RefreshNativeProfessions()
    if not active or type(C_Club)~='table' or type(C_Club.GetGuildClubId)~='function' or type(C_Club.GetClubMembers)~='function' or type(C_Club.GetMemberInfo)~='function' then return false end
    local now=GetTime()
    if nativeScan or (lastNativeScan and now-lastNativeScan<30) then return true end
    local ok,club=pcall(C_Club.GetGuildClubId); if not ok or not integer(club,1,9000000000000000) then return false end
    local got,members=pcall(C_Club.GetClubMembers,club); if not got or not usable(members,'table') then return false end
    local fresh={}
    local job={profile=profile,identity=identity,index=1}
    nativeScan=job
    lastNativeScan=now
    local function step()
      if nativeScan~=job or not active or profile~=job.profile or identity~=job.identity then
          if nativeScan==job then nativeScan=nil end
          return
      end
      local stop=math.min(#members,job.index+24,10000)
      for index=job.index,stop do
        local memberID=members[index]
        local success,info=pcall(C_Club.GetMemberInfo,club,memberID)
        if success and usable(info,'table') and usable(info.name,'string') and info.name~='' then
            local list={}; local seen={}
            for i=1,2 do
                local id=info['profession'..i..'ID']
                if integer(id,1,1000000) and byID[id] and not seen[id] then
                    list[#list+1]={id=id,native=true}; seen[id]=true
                end
            end
            if #list>0 then fresh[info.name]=list end
        end
      end
      job.index=stop+1
      if job.index<=math.min(#members,10000) then
          if C_Timer and C_Timer.After then C_Timer.After(0,step) else step() end
      else
          nativeProfessions=fresh; nativeScan=nil
          if C_Timer and C_Timer.After then changed() end
      end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0,step) else step() end
    return true
end
function Workshop:GetMemberProfessions(name)
    if not active or not usable(name,'string') then return {} end
    local record=records[name]; local result={}
    if usable(record,'table') and usable(record.list,'table') then
        for _,p in ipairs(record.list) do
            if usable(p,'table') and byID[p.id] then result[#result+1]={id=p.id,rank=p.rank,maximum=p.maximum,timestamp=record.timestamp,relayed=record.relayed==true} end
        end
    elseif nativeProfessions[name] then
        for _,p in ipairs(nativeProfessions[name]) do result[#result+1]=p end
    end
    return result
end
function Workshop:ProfessionInfo(id)
    local entry=byID[id]; local art=professionArt[id]
    return entry and entry.name or 'Невідома професія', art and art[1] or 134400
end
function Workshop:GetProfessionMasters(id)
    if not active or not byID[id] then return {} end
    local found={}
    for name,record in pairs(records) do
        if usable(name,'string') and usable(record,'table') and usable(record.list,'table') then
            for _,p in ipairs(record.list) do
                if usable(p,'table') and p.id==id then
                    found[name]={name=name,rank=integer(p.rank,1,9999),maximum=integer(p.maximum,1,9999),timestamp=record.timestamp,relayed=record.relayed==true}
                    break
                end
            end
        end
    end
    for name,list in pairs(nativeProfessions) do
        if usable(name,'string') and usable(list,'table') and not found[name] and not records[name] then
            for _,p in ipairs(list) do
                if usable(p,'table') and p.id==id then found[name]={name=name,native=true}; break end
            end
        end
    end
    local result={}; for _,entry in pairs(found) do result[#result+1]=entry end
    table.sort(result,function(a,b) return a.name<b.name end)
    return result
end

local function updateOwn()
    local list=scan(); scanState=list~=nil
    if not list then dropCandidate=nil; changed(); return false end
    local previous=records[identity]
    local removed={}
    if type(previous)=='table' and type(previous.list)=='table' then
        local found={}; for _,entry in ipairs(list) do found[entry.id]=true end
        for _,entry in ipairs(previous.list) do
            if type(entry)=='table' and byID[entry.id] and not found[entry.id] then
                removed[#removed+1]=entry.id
            end
        end
    end
    if #removed>0 or (#list==0 and not previous) then
        local fingerprint=encode({timestamp=1,list=list}); local now=GetTime()
        if not dropCandidate or dropCandidate.fingerprint~=fingerprint then dropCandidate={fingerprint=fingerprint,first=now,count=1}
        else dropCandidate.count=dropCandidate.count+1 end
        if not scanStarted or now-scanStarted<15 or now-dropCandidate.first<6 or dropCandidate.count<3 then
            scanState='checking'; changed(); return false
        end
    end
    dropCandidate=nil
    if type(previous)=='table' and type(previous.list)=='table' and not forceBroadcast then
        local ok,prior=pcall(encode,{timestamp=1,list=previous.list})
        if ok and prior==encode({timestamp=1,list=list}) and integer(previous.timestamp,1,GetServerTime()+600) and GetServerTime()-previous.timestamp<86400 then return true end
    end
    local previousTime=type(previous)=='table' and integer(previous.timestamp,1,GetServerTime()+600) or nil
    local snapshot={timestamp=math.max(GetServerTime(),(previousTime or 0)+1),list=list}
    forceBroadcast=false
    records[identity]=snapshot; pending=true
    if #removed>0 then
        if type(store.pendingProfessionRemovals)~='table' then store.pendingProfessionRemovals={} end
        if type(store.pendingProfessionRemovals[identity])~='table' then store.pendingProfessionRemovals[identity]={} end
        for _,id in ipairs(removed) do
            store.pendingProfessionRemovals[identity][id]=true
            if OldKraken.WorkshopRecipes and type(OldKraken.WorkshopRecipes.ForgetProfession)=='function' then OldKraken.WorkshopRecipes:ForgetProfession(id,identity,profile) end
        end
    end
    changed(); return true
end
local listener=CreateFrame('Frame')
for _,event in ipairs({'PLAYER_LOGIN','PLAYER_GUILD_UPDATE','GUILD_ROSTER_UPDATE','SKILL_LINES_CHANGED','LEARNED_SPELL_IN_SKILL_LINE','CHAT_MSG_SKILL','TRADE_SKILL_SHOW'}) do
    pcall(listener.RegisterEvent,listener,event)
end
listener:SetScript('OnEvent',function(_,event)
    ownProfessionCache=nil
    if event=='PLAYER_LOGIN' or event=='PLAYER_GUILD_UPDATE' or event=='GUILD_ROSTER_UPDATE' then connect(); changed()
    elseif active then nextScan=0; changed() end
end)
if C_Timer and type(C_Timer.NewTicker)=='function' then
    C_Timer.NewTicker(3,function()
        connect(); if not active then return end
        local now=GetTime()
        if now>=nextScan then local complete=updateOwn(); nextScan=now+(complete and 60 or (scanState=='checking' and 3 or 15)) end
        if queryPending and comm:SendProtocol('WKQUERY','') then queryPending=false end
        if pending and records[identity] and comm:SendProtocol('WKPROF',encode(records[identity])) then pending=false end
        local owner=next(professionRelayDirty)
        if owner and #comm.queue<=8 then
            local payload=store.professionRelays[owner]
            if not payload or owner==identity or comm:SendProtocol('WKRELAY',codec._pack({owner,payload})) then professionRelayDirty[owner]=nil end
        end
    end)
end

local function button(parent,text,x,y,width,callback,variant)
    local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate'); OldKraken.UIStyle.Button(b,variant)
    b:SetSize(width,24); b:SetPoint('TOPLEFT',parent,'TOPLEFT',x,y); b:SetText(text); b:SetScript('OnClick',callback); return b
end
render=function()
    if not frame or not frame:IsShown() or (frame.professionView and not frame.professionView:IsShown()) then return end
    frame.heading:SetText(scanState=='checking' and 'Перевіряємо зміни професій…' or (scanState==false and 'Власні дані професій не отримано. Відкрийте професію.' or 'Оберіть професію, щоб переглянути майстрів.'))
    local summaries=OldKraken.WorkshopRecipes and OldKraken.WorkshopRecipes:GetProfessionSummaries() or {}
    for _,card in ipairs(frame.professionCards) do
        local summary=summaries[card.profession]
        card.detail:SetText(summary and (summary.recipes..' рецептів · '..summary.members..' майстрів') or 'Немає збережених рецептів')
    end
end
local function createWindow(parent)
    local f
    if parent then
        f=CreateFrame('Frame','OldKrakenWorkshopFrame',parent)
    else
        f=CreateFrame('Frame','OldKrakenWorkshopFrame',UIParent,'BasicFrameTemplateWithInset')
    end
    if not parent then
        table.insert(UISpecialFrames,'OldKrakenWorkshopFrame')
        f:SetMovable(true); f:RegisterForDrag('LeftButton'); f:SetScript('OnDragStart',f.StartMoving); f:SetScript('OnDragStop',f.StopMovingOrSizing)
        OldKraken.UIStyle.Window(f)
    end
    local embedded=parent~=nil
    f:SetSize(embedded and 900 or 780,embedded and 590 or 520); f:SetPoint('CENTER',parent or UIParent,'CENTER'); f:SetClampedToScreen(true); f:EnableMouse(true)
    if f.TitleText then f.TitleText:SetText('Old Kraken — Майстерня') end
    local content=f
    local verticalShift=embedded and 32 or 0
    local function y(value) return value-verticalShift end
    if embedded then
        f.professionView=CreateFrame('Frame',nil,f); f.professionView:SetAllPoints(f)
        if OldKraken.WorkshopOrders and OldKraken.WorkshopOrders.CreatePanel then
            f.ordersView=OldKraken.WorkshopOrders:CreatePanel(f)
        else
            f.ordersView=CreateFrame('Frame',nil,f); f.ordersView:Hide()
        end
        content=f.professionView
        if OldKraken.WorkshopRecipes and OldKraken.WorkshopRecipes.CreatePanel then
            f.recipesView=OldKraken.WorkshopRecipes:CreatePanel(f)
        else
            f.recipesView=false
        end
        f.professionTab=button(f,'Професії',18,-38,110,function() Workshop:Show('professions') end)
        f.recipeTab=button(f,'Рецепти',136,-38,110,function()
            if OldKraken.WorkshopRecipes and OldKraken.WorkshopRecipes.SelectTab then OldKraken.WorkshopRecipes:SelectTab('recipes') end
        end)
        f.masterTab=button(f,'Майстри',254,-38,110,function()
            if OldKraken.WorkshopRecipes and OldKraken.WorkshopRecipes.SelectTab then OldKraken.WorkshopRecipes:SelectTab('masters') end
        end)
        f.ordersTab=button(f,'Замовлення',372,-38,120,function()
            if OldKraken.WorkshopOrders then OldKraken.WorkshopOrders:Show() end
        end)
        for _,tab in ipairs({f.professionTab,f.recipeTab,f.masterTab,f.ordersTab}) do
            tab.activeBar=tab:CreateTexture(nil,'ARTWORK')
            tab.activeBar:SetPoint('BOTTOMLEFT',tab,'BOTTOMLEFT',2,1)
            tab.activeBar:SetSize(tab==f.ordersTab and 116 or 106,2)
            tab.activeBar:SetColorTexture(unpack(OldKraken.UIStyle.Colors.brandGold))
        end
        f.newOrder=button(f.ordersView or f,'Нове замовлення',720,-38,150,function()
            if OldKraken.WorkshopOrders then OldKraken.WorkshopOrders:OpenCreateForm() end
        end,'primary')
        f.newOrder:Hide()
        f.back=button(f,'‹ Назад',570,-38,130,function() Workshop:Back() end)
        f.back:Hide()
        f:HookScript('OnHide',function()
            local recipes=OldKraken.WorkshopRecipes
            if recipes and recipes.IsPicking and recipes:IsPicking() then
                if Workshop.currentView=='recipes' then Workshop:Back() else recipes:CancelPicker() end
            end
        end)
    end
    button(content,'Оновити',590,y(-43),120,function() forceBroadcast=true; nextScan=0; queryPending=true; print('Old Kraken: запит професій поставлено в чергу.') end)
    f.heading=content:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); f.heading:SetPoint('TOPLEFT',content,'TOPLEFT',20,y(-52))
    f.professionCards={}
    for i,p in ipairs(professions) do
        local entry=p; local col=(i-1)%3; local line=math.floor((i-1)/3)
        local card=button(content,'',20+col*242,y(-100-line*47),232,function()
            if OldKraken.WorkshopRecipes then OldKraken.WorkshopRecipes:ShowProfession(entry.id) end
        end)
        card:SetHeight(42); card.profession=entry.id
        local art=card:CreateTexture(nil,'BACKGROUND',nil,1); art:SetAllPoints(card)
        local image=professionArt[entry.id]; local atlas=image and ('Profession-background-card-'..image[2])
        local ok,info=false,nil
        if atlas and C_Texture and type(C_Texture.GetAtlasInfo)=='function' then ok,info=pcall(C_Texture.GetAtlasInfo,atlas) end
        if ok and type(info)=='table' and info.file and info.leftTexCoord and info.rightTexCoord and info.topTexCoord and info.bottomTexCoord then
            art:SetTexture(info.file); art:SetTexCoord(info.leftTexCoord,info.rightTexCoord,info.topTexCoord,info.bottomTexCoord); art:SetAlpha(0.55)
        else art:SetColorTexture(0.10,0.12,0.15,1) end
        local shade=card:CreateTexture(nil,'BACKGROUND',nil,2); shade:SetAllPoints(card); shade:SetColorTexture(0,0,0,0.4)
        local icon=card:CreateTexture(nil,'ARTWORK'); icon:SetSize(32,32); icon:SetPoint('LEFT',card,'LEFT',6,0); icon:SetTexture(image and image[1] or 134400)
        local name=card:CreateFontString(nil,'OVERLAY','GameFontNormal'); name:SetPoint('TOPLEFT',card,'TOPLEFT',45,-5); name:SetWidth(180); name:SetJustifyH('LEFT'); name:SetWordWrap(false); name:SetText(entry.name)
        local detail=card:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); detail:SetPoint('TOPLEFT',card,'TOPLEFT',45,-24); detail:SetWidth(180); detail:SetJustifyH('LEFT'); detail:SetWordWrap(false)
        card.detail=detail
        card:SetScript('OnEnter',function(self) if GameTooltip then GameTooltip:SetOwner(self,'ANCHOR_RIGHT'); GameTooltip:SetText(entry.name); GameTooltip:AddLine('Натисніть, щоб переглянути майстрів'); GameTooltip:Show() end end)
        card:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
        f.professionCards[i]=card
    end
    if not embedded then
        button(content,'Замовлення',20,-472,145,function() if OldKraken.WorkshopOrders then OldKraken.WorkshopOrders:Show() end end)
    end
    if not embedded then button(content,'Пошук рецептів',175,y(-315),155,function() if OldKraken.WorkshopRecipes then OldKraken.WorkshopRecipes:Show() end end) end
    local note=content:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); note:SetPoint('TOPLEFT',content,'TOPLEFT',embedded and 20 or 200,y(-321)); note:SetText('Відкрийте професії, щоб переглянути майстрів.')
    content:HookScript('OnShow',render)
    f:Hide(); return f
end
OldKraken:On('WORKSHOP_RECIPES_CHANGED',scheduleRender)
OldKraken:On('WORKSHOP_INDEX_CHANGED',scheduleRender)
function Workshop:UpdateTabs()
    if not frame or not frame.professionView then return end
    local view=self.currentView
    local recipeTab=OldKraken.WorkshopRecipes and OldKraken.WorkshopRecipes.GetTab and OldKraken.WorkshopRecipes:GetTab() or 'recipes'
    frame.professionTab.activeBar:SetShown(view=='professions')
    frame.recipeTab.activeBar:SetShown(view=='recipes' and recipeTab=='recipes')
    frame.masterTab.activeBar:SetShown(view=='recipes' and recipeTab=='masters')
    frame.ordersTab.activeBar:SetShown(view=='orders' or view=='orderCreate')
end
function Workshop:SetView(view)
    if not frame or not frame.professionView then return end
    if self.currentView=='recipes' and view~='recipes' and OldKraken.WorkshopRecipes and OldKraken.WorkshopRecipes.CancelPicker then
        OldKraken.WorkshopRecipes:CancelPicker()
    end
    self.currentView=view
    frame.professionView:SetShown(view=='professions')
    if frame.ordersView then frame.ordersView:SetShown(view=='orders') end
    if frame.recipesView then frame.recipesView:SetShown(view=='recipes') end
    if OldKraken.WorkshopOrders and OldKraken.WorkshopOrders.ShowCreatePanel then OldKraken.WorkshopOrders:ShowCreatePanel(view=='orderCreate') end
    self:UpdateTabs()
    if frame.newOrder then frame.newOrder:SetShown(view=='orders') end
    if frame.back then frame.back:SetShown(#self.navigationStack>0) end
    if view=='orders' and OldKraken.WorkshopOrders then OldKraken.WorkshopOrders:RefreshEmbedded() end
    if view=='recipes' and OldKraken.WorkshopRecipes and OldKraken.WorkshopRecipes.RefreshPanel then OldKraken.WorkshopRecipes:RefreshPanel() end
end
function Workshop:Navigate(view,force)
    if self.currentView==view and not force then return false end
    local entry={view=self.currentView}
    if entry.view=='recipes' and OldKraken.WorkshopRecipes and OldKraken.WorkshopRecipes.CaptureView then
        entry.recipes=OldKraken.WorkshopRecipes:CaptureView()
    end
    self.navigationStack[#self.navigationStack+1]=entry
    if #self.navigationStack>20 then table.remove(self.navigationStack,1) end
    self:SetView(view)
    return true
end
function Workshop:Back()
    if self.currentView=='recipes' and OldKraken.WorkshopRecipes and OldKraken.WorkshopRecipes.CancelPicker then
        OldKraken.WorkshopRecipes:CancelPicker()
    end
    local entry=table.remove(self.navigationStack)
    if not entry then return end
    self:SetView(entry.view)
    if entry.recipes and OldKraken.WorkshopRecipes then OldKraken.WorkshopRecipes:RestoreView(entry.recipes) end
end
function Workshop:Show(view)
    connect(); if not active then print('Old Kraken: майстерня доступна після входу до гільдії.'); return end
    if OldKraken.UIHub then
        OldKraken.UIHub:ShowPage('workshop')
        self.navigationStack={}
        self:SetView(view or 'professions')
    else
        if not frame then frame=createWindow() end
        frame:Show()
    end
    render()
end
if OldKraken.UIHub then
    OldKraken.UIHub:RegisterPage('workshop','Майстерня','04',function(parent)
        if not frame then frame=createWindow(parent) end
        return frame
    end)
end
function Workshop:HasProfession(id)
    if not active or not identity then return false end
    if type(GetProfessions)=='function' and type(GetProfessionInfo)=='function' then
        if not ownProfessionCache then
            ownProfessionCache={}
            local result={pcall(GetProfessions)}
            if result[1] then
                for i=2,7 do
                    local index=result[i]
                    if integer(index,1,100000) then
                        local info={pcall(GetProfessionInfo,index)}
                        if info[1] and integer(info[8],1,1000000) then ownProfessionCache[info[8]]=true end
                    end
                end
            end
        end
        return ownProfessionCache[id]==true
    end
    local record=records[identity]
    if type(record)~='table' or type(record.list)~='table' then return false end
    for _,entry in ipairs(record.list) do if type(entry)=='table' and entry.id==id then return true end end
    return false
end
