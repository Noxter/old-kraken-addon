local T = OldKraken.Translate or function(text) return text end
local function chatInfo(msg)
    if OldKraken.Print then OldKraken:Print(msg) else print('|cff2ec4b6Old Kraken|r: ' .. tostring(msg or ''):gsub('^|c%x%x%x%x%x%x%x%xOld Kraken|r:%s*', ''):gsub('^Old Kraken:%s*', '')) end
end
local function chatError(msg)
    if OldKraken.PrintError then OldKraken:PrintError(msg) else print('|cffff5555Old Kraken|r: ' .. tostring(msg or ''):gsub('^|c%x%x%x%x%x%x%x%xOld Kraken|r:%s*', ''):gsub('^Old Kraken:%s*', '')) end
end
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
OldKraken:On('WORKSHOP_SCOPE_MIGRATED',function(migratedProfile)
    if active and profile==migratedProfile then changed() end
end)
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

local function validRealm(realm)
    if OldKraken.Database and type(OldKraken.Database.IsValidRealm)=='function' then
        return OldKraken.Database:IsValidRealm(realm)
    end
    return usable(realm,'string') and #realm>=1 and #realm<=128 and not realm:find('[%z\1-\31\127]')
end

local function connect()
    local name=fullName()
    local guild=type(GetGuildInfo)=='function' and GetGuildInfo('player')
    local realm=type(GetRealmName)=='function' and GetRealmName() or nil
    if not name or not usable(guild,'string') or guild=='' or #guild>128 or guild:find('[%z\1-\31\127]') or not validRealm(realm) or not OldKraken.DB then
        active,identity,profile,store,records,nativeProfessions=false,nil,nil,nil,{},{}
        if frame and not OldKraken.UIHub then frame:Hide() end
        return
    end
    if OldKraken.Database and type(OldKraken.Database.MigrateWorkshopScope)=='function' then
        OldKraken.Database:MigrateWorkshopScope(realm,guild,false)
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
function Workshop:IsActive()
    return active == true
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
    return entry and entry.name or T('Невідома професія'), art and art[1] or 134400
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
for _,event in ipairs({'PLAYER_LOGIN','PLAYER_ENTERING_WORLD','PLAYER_GUILD_UPDATE','GUILD_ROSTER_UPDATE','SKILL_LINES_CHANGED','LEARNED_SPELL_IN_SKILL_LINE','CHAT_MSG_SKILL','TRADE_SKILL_SHOW'}) do
    pcall(listener.RegisterEvent,listener,event)
end
listener:SetScript('OnEvent',function(_,event)
    ownProfessionCache=nil
    if event=='PLAYER_LOGIN' or event=='PLAYER_ENTERING_WORLD' or event=='PLAYER_GUILD_UPDATE' or event=='GUILD_ROSTER_UPDATE' then connect(); changed()
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

local function pluralUk(n, one, few, many)
    if OldKraken.GetLanguage and OldKraken.GetLanguage() == 'enUS' then
        return n == 1 and one or many
    end
    local mod100, mod10 = n % 100, n % 10
    if mod100 >= 11 and mod100 <= 14 then return many end
    if mod10 == 1 then return one end
    if mod10 >= 2 and mod10 <= 4 then return few end
    return many
end
local GATHERING_PROFESSIONS = {[186]=true, [182]=true, [393]=true}
local SECONDARY_PROFESSIONS = {[185]=true, [129]=true, [356]=true}
function Workshop:IsGatheringProfession(id) return GATHERING_PROFESSIONS[id] == true end
function Workshop:IsSecondaryProfession(id) return SECONDARY_PROFESSIONS[id] == true end
function Workshop:PluralUk(n, one, few, many) return pluralUk(n, one, few, many) end

local function button(parent,text,x,y,width,callback,variant,options)
    local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate'); OldKraken.UIStyle.Button(b,variant,options)
    b:SetSize(width,(options and options.height) or 28); b:SetPoint('TOPLEFT',parent,'TOPLEFT',x,y); b:SetText(text); b:SetScript('OnClick',callback); return b
end
render=function()
    if not frame or not frame:IsShown() or (frame.professionView and not frame.professionView:IsShown()) then return end
    frame.heading:SetText(scanState=='checking' and T('Перевіряємо зміни професій…') or (scanState==false and T('Власні дані професій не отримано. Відкрийте професію у грі.') or T('Оберіть професію, щоб переглянути майстрів і рецепти.')))
    local summaries=OldKraken.WorkshopRecipes and OldKraken.WorkshopRecipes:GetProfessionSummaries() or {}
    local online = OldKraken.WorkshopRecipes and OldKraken.WorkshopRecipes.GetRosterPresentation and OldKraken.WorkshopRecipes:GetRosterPresentation() or {}
    local totalRecipes, onlineMastersMap = 0, {}
    for _,card in ipairs(frame.professionCards) do
        local summary=summaries[card.profession]
        if summary then
            local rWord = pluralUk(summary.recipes, T('рецепт'), T('рецепти'), T('рецептів'))
            local mWord = pluralUk(summary.members, T('майстер'), T('майстри'), T('майстрів'))
            card.detail:SetText(summary.recipes..' '..rWord..' · '..summary.members..' '..mWord)
            totalRecipes = totalRecipes + (summary.recipes or 0)
        else
            card.detail:SetText(T('Немає збережених рецептів'))
        end
        if card.online then
            local onCount = 0
            for _, m in ipairs(Workshop:GetProfessionMasters(card.profession)) do
                if m.name == identity or online[m.name] == true then
                    onCount = onCount + 1
                    onlineMastersMap[m.name] = true
                end
            end
            if onCount > 0 then
                card.online:SetText('|cff68d98c• ' .. onCount .. T(' онлайн|r'))
            else
                card.online:SetText(T('|cff9ba9bcНемає майстрів онлайн|r'))
            end
        end
    end
    if type(frame.ordersSummaryLine1) == 'table' then
        local openCount, availableCount = 0, 0
        if OldKraken.WorkshopOrders and OldKraken.WorkshopOrders.GetOpenCounts then
            openCount, availableCount = OldKraken.WorkshopOrders:GetOpenCounts()
        end
        local oWord = pluralUk(openCount, T('відкрите замовлення'), T('відкритих замовлення'), T('відкритих замовлень'))
        frame.ordersSummaryLine1:SetText(T('У гільдії зараз |cffffd35a') .. openCount .. '|r ' .. oWord .. '.')
        frame.ordersSummaryLine2:SetText(T('Доступно вам для виконання: |cff68d98c') .. availableCount .. '|r.')
    end
    if type(frame.recipesSummaryLine1) == 'table' then
        local onlineMasters = 0
        for _ in pairs(onlineMastersMap) do onlineMasters = onlineMasters + 1 end
        local rWord = pluralUk(totalRecipes, T('рецепт'), T('рецепти'), T('рецептів'))
        local mWord = pluralUk(onlineMasters, T('майстер онлайн'), T('майстри онлайн'), T('майстрів онлайн'))
        frame.recipesSummaryLine1:SetText(T('У базі гільдії збережено |cffffd35a') .. totalRecipes .. '|r ' .. rWord .. '.')
        frame.recipesSummaryLine2:SetText(T('Зараз у мережі |cff68d98c') .. onlineMasters .. '|r ' .. mWord .. '.')
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
    f:SetSize(embedded and 900 or 780,embedded and 608 or 520); f:SetPoint('CENTER',parent or UIParent,'CENTER'); f:SetClampedToScreen(true); f:EnableMouse(true)
    if OldKraken.BindGuildTitle then OldKraken.BindGuildTitle(f, T('Майстерня')) end
    local colors = OldKraken.UIStyle.Colors or {}
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
        if OldKraken.UIStyle.SegmentedTabs then
            f.tabBar = OldKraken.UIStyle.SegmentedTabs(f, {
                {key = 'professions', label = T('Професії'), width = 102},
                {key = 'recipes', label = T('Рецепти'), width = 96},
                {key = 'masters', label = T('Майстри'), width = 96},
                {key = 'orders', label = T('Замовлення'), width = 112},
            }, function(key)
                if key == 'professions' then Workshop:Show('professions')
                elseif key == 'recipes' or key == 'masters' then
                    if OldKraken.WorkshopRecipes and OldKraken.WorkshopRecipes.SelectTab then OldKraken.WorkshopRecipes:SelectTab(key) end
                elseif key == 'orders' then
                    if OldKraken.WorkshopOrders then OldKraken.WorkshopOrders:Show() end
                end
            end, {active = 'professions', height = 40, edgeKey = 'buttonEdge', rounded = true})
            f.tabBar:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, -47)
            if type(f.tabBar.SetFrameLevel)=='function' then f.tabBar:SetFrameLevel(((type(f.GetFrameLevel)=='function' and f:GetFrameLevel()) or 1)+10) end
            f.professionTab = f.tabBar.tabs.professions
            f.recipeTab = f.tabBar.tabs.recipes
            f.masterTab = f.tabBar.tabs.masters
            f.ordersTab = f.tabBar.tabs.orders
        else
            local function legacyTab(label, xPos, onClick)
                local b=button(f,label,xPos,-47,104,onClick)
                b.activeBar=b:CreateTexture(nil,'OVERLAY'); b.activeBar:SetHeight(2); b.activeBar:SetPoint('BOTTOMLEFT',b,'BOTTOMLEFT',2,1); b.activeBar:SetPoint('BOTTOMRIGHT',b,'BOTTOMRIGHT',-2,1); b.activeBar:Hide()
                return b
            end
            f.professionTab=legacyTab(T('Професії'),0,function() Workshop:Show('professions') end)
            f.recipeTab=legacyTab(T('Рецепти'),110,function()
                if OldKraken.WorkshopRecipes and OldKraken.WorkshopRecipes.SelectTab then OldKraken.WorkshopRecipes:SelectTab('recipes') end
            end)
            f.masterTab=legacyTab(T('Майстри'),214,function()
                if OldKraken.WorkshopRecipes and OldKraken.WorkshopRecipes.SelectTab then OldKraken.WorkshopRecipes:SelectTab('masters') end
            end)
            f.ordersTab=legacyTab(T('Замовлення'),318,function()
                if OldKraken.WorkshopOrders then OldKraken.WorkshopOrders:Show() end
            end)
        end
        f.newOrder=button(f.ordersView or f,T('Нове замовлення'),750,-50,150,function()
            if OldKraken.WorkshopOrders then OldKraken.WorkshopOrders:OpenCreateForm() end
        end,'primary',{rounded=true,height=34})
        f.newOrder:Hide()
        f.back=button(f,T('‹ Назад'),770,-50,130,function() Workshop:Back() end,nil,{rounded=true,height=34})
        if type(f.back.SetFrameLevel)=='function' then f.back:SetFrameLevel(((type(f.GetFrameLevel)=='function' and f:GetFrameLevel()) or 1)+10) end
        f.back:Hide()
        f:HookScript('OnHide',function()
            local recipes=OldKraken.WorkshopRecipes
            if recipes and recipes.IsPicking and recipes:IsPicking() then
                if Workshop.currentView=='recipes' then Workshop:Back() else recipes:CancelPicker() end
            end
        end)
    end
    button(content,T('Оновити'),embedded and 770 or 590,embedded and -50 or y(-43),embedded and 130 or 120,function() forceBroadcast=true; nextScan=0; queryPending=true; chatInfo(T('Old Kraken: запит професій поставлено в чергу.')) end,nil,{rounded=true,height=34})
    f.heading=content:CreateFontString(nil,'OVERLAY','GameFontHighlight')
    f.heading:SetPoint('TOPLEFT',content,'TOPLEFT',embedded and 0 or 20,embedded and -104 or y(-52))
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(f.heading, 13) end
    if colors.mutedText then f.heading:SetTextColor(colors.mutedText[1], colors.mutedText[2], colors.mutedText[3]) end
    f.professionCards={}
    local cardW = embedded and 288 or 232
    local cardH = embedded and 82 or 42
    local stepX = embedded and 306 or 242
    local stepY = embedded and 96 or 47
    local startX = embedded and 0 or 20
    local startY = embedded and -134 or y(-100)
    local gridProfessions = {}
    for _,p in ipairs(professions) do
        if not GATHERING_PROFESSIONS[p.id] and (not embedded or not SECONDARY_PROFESSIONS[p.id]) then
            gridProfessions[#gridProfessions+1]=p
        end
    end
    local cols = 3
    for i,p in ipairs(gridProfessions) do
        local entry=p; local col=(i-1)%cols; local line=math.floor((i-1)/cols)
        local card=button(content,'',startX+col*stepX,startY-line*stepY,cardW,function()
            if OldKraken.WorkshopRecipes then OldKraken.WorkshopRecipes:ShowProfession(entry.id) end
        end,nil,{height=cardH})
        card:SetHeight(cardH); card.profession=entry.id
        local art=card:CreateTexture(nil,'BACKGROUND',nil,1); art:SetAllPoints(card)
        local image=professionArt[entry.id]; local atlas=image and ('Profession-background-card-'..image[2])
        local ok,info=false,nil
        if atlas and C_Texture and type(C_Texture.GetAtlasInfo)=='function' then ok,info=pcall(C_Texture.GetAtlasInfo,atlas) end
        if ok and type(info)=='table' and info.file and info.leftTexCoord and info.rightTexCoord and info.topTexCoord and info.bottomTexCoord then
            art:SetTexture(info.file); art:SetTexCoord(info.leftTexCoord,info.rightTexCoord,info.topTexCoord,info.bottomTexCoord); art:SetAlpha(0.45)
        else
            local panelBg = colors.panel or {0.055, 0.07, 0.095, 0.96}
            art:SetColorTexture(panelBg[1], panelBg[2], panelBg[3], 1)
        end
        local shade=card:CreateTexture(nil,'BACKGROUND',nil,2); shade:SetAllPoints(card); shade:SetColorTexture(0,0,0,0.45)
        local iconSize = embedded and 44 or 32
        local icon=card:CreateTexture(nil,'ARTWORK'); icon:SetSize(iconSize,iconSize); icon:SetPoint('LEFT',card,'LEFT',embedded and 16 or 12,0); icon:SetTexture(image and image[1] or 134400)
        local textLeft = embedded and 72 or 45
        local name=card:CreateFontString(nil,'OVERLAY','GameFontNormal')
        name:SetPoint('TOPLEFT',card,'TOPLEFT',textLeft,embedded and -12 or -5); name:SetWidth(cardW - textLeft - 14); name:SetJustifyH('LEFT'); name:SetWordWrap(false); name:SetText(entry.name)
        if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(name, embedded and 14 or 13, true) end
        if colors.brandGold then name:SetTextColor(colors.brandGold[1], colors.brandGold[2], colors.brandGold[3]) end
        local detail=card:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
        detail:SetPoint('TOPLEFT',card,'TOPLEFT',textLeft,embedded and -34 or -24); detail:SetWidth(cardW - textLeft - 14); detail:SetJustifyH('LEFT'); detail:SetWordWrap(false)
        if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(detail, 12) end
        if colors.mutedText then detail:SetTextColor(colors.mutedText[1], colors.mutedText[2], colors.mutedText[3]) end
        card.detail=detail
        if embedded then
            local onLine=card:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
            onLine:SetPoint('TOPLEFT',card,'TOPLEFT',textLeft,-54); onLine:SetWidth(cardW - textLeft - 14); onLine:SetJustifyH('LEFT'); onLine:SetWordWrap(false)
            if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(onLine, 12) end
            card.online=onLine
        end
        card:SetScript('OnEnter',function(self) if GameTooltip then GameTooltip:SetOwner(self,'ANCHOR_RIGHT'); GameTooltip:SetText(entry.name); GameTooltip:AddLine(T('Натисніть, щоб переглянути майстрів і рецепти')); GameTooltip:Show() end end)
        card:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
        f.professionCards[i]=card
    end
    if embedded and OldKraken.UIStyle.PanelFrame then
        local function makeSummaryPanel(xPos, titleText, hintText)
            local p = OldKraken.UIStyle.PanelFrame(content, 'buttonEdge')
            p:SetSize(440, 210); p:SetPoint('TOPLEFT', content, 'TOPLEFT', xPos, -346)
            local title = p:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
            title:SetPoint('TOPLEFT', p, 'TOPLEFT', 18, -18); title:SetText(titleText)
            if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(title, 15, true) end
            if colors.brandGold then title:SetTextColor(colors.brandGold[1], colors.brandGold[2], colors.brandGold[3]) end
            local line1 = p:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
            line1:SetPoint('TOPLEFT', p, 'TOPLEFT', 18, -50); line1:SetWidth(404); line1:SetJustifyH('LEFT')
            if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(line1, 13) end
            local line2 = p:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
            line2:SetPoint('TOPLEFT', p, 'TOPLEFT', 18, -74); line2:SetWidth(404); line2:SetJustifyH('LEFT')
            if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(line2, 13) end
            local hint = p:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
            hint:SetPoint('TOPLEFT', p, 'TOPLEFT', 18, -106); hint:SetWidth(404); hint:SetJustifyH('LEFT'); hint:SetWordWrap(true)
            if type(hint.SetSpacing) == 'function' then hint:SetSpacing(3) end
            if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(hint, 12) end
            if colors.mutedText then hint:SetTextColor(colors.mutedText[1], colors.mutedText[2], colors.mutedText[3]) end
            hint:SetText(hintText)
            return p, line1, line2
        end
        local op, o1, o2 = makeSummaryPanel(0, T('Активні замовлення'), T('Оберіть або створіть запит на крафт для учасників гільдії.'))
        f.ordersSummaryPanel, f.ordersSummaryLine1, f.ordersSummaryLine2 = op, o1, o2
        button(op, T('Відкрити замовлення'), 18, -158, 185, function()
            if OldKraken.WorkshopOrders then OldKraken.WorkshopOrders:Show() end
        end, 'primary', {rounded=true, height=34})
        button(op, T('Створити'), 213, -158, 115, function()
            if OldKraken.WorkshopOrders then
                OldKraken.WorkshopOrders:Show()
                OldKraken.WorkshopOrders:OpenCreateForm()
            end
        end, nil, {rounded=true, height=34})
        local rp, r1, r2 = makeSummaryPanel(460, T('Пошук рецептів і майстри'), T('Шукайте потрібний предмет за назвою або перегляньте список майстрів.'))
        f.recipesSummaryPanel, f.recipesSummaryLine1, f.recipesSummaryLine2 = rp, r1, r2
        button(rp, T('Знайти рецепт'), 18, -158, 155, function()
            if OldKraken.WorkshopRecipes then OldKraken.WorkshopRecipes:SelectTab('recipes') end
        end, 'primary', {rounded=true, height=34})
        button(rp, T('Усі майстри'), 183, -158, 140, function()
            if OldKraken.WorkshopRecipes then OldKraken.WorkshopRecipes:SelectTab('masters') end
        end, nil, {rounded=true, height=34})
    end
    if not embedded then
        button(content,T('Замовлення'),20,-472,145,function() if OldKraken.WorkshopOrders then OldKraken.WorkshopOrders:Show() end end)
        button(content,T('Пошук рецептів'),175,y(-315),155,function() if OldKraken.WorkshopRecipes then OldKraken.WorkshopRecipes:Show() end end)
        local note=content:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); note:SetPoint('TOPLEFT',content,'TOPLEFT',200,y(-321)); note:SetText(T('Відкрийте професії, щоб переглянути майстрів.'))
    end
    content:HookScript('OnShow',render)
    f:Hide(); return f
end
OldKraken:On('WORKSHOP_RECIPES_CHANGED',scheduleRender)
OldKraken:On('WORKSHOP_INDEX_CHANGED',scheduleRender)
function Workshop:UpdateTabs()
    if not frame or not frame.professionView then return end
    local view=self.currentView
    local recipeTab=OldKraken.WorkshopRecipes and OldKraken.WorkshopRecipes.GetTab and OldKraken.WorkshopRecipes:GetTab() or 'recipes'
    if type(frame.tabBar)=='table' and frame.tabBar.SetActive then
        local activeKey = view == 'professions' and 'professions'
            or ((view == 'orders' or view == 'orderCreate') and 'orders' or recipeTab)
        frame.tabBar:SetActive(activeKey)
    else
        if type(frame.professionTab)=='table' and type(frame.professionTab.activeBar)=='table' then frame.professionTab.activeBar:SetShown(view=='professions') end
        if type(frame.recipeTab)=='table' and type(frame.recipeTab.activeBar)=='table' then frame.recipeTab.activeBar:SetShown(view=='recipes' and recipeTab=='recipes') end
        if type(frame.masterTab)=='table' and type(frame.masterTab.activeBar)=='table' then frame.masterTab.activeBar:SetShown(view=='recipes' and recipeTab=='masters') end
        if type(frame.ordersTab)=='table' and type(frame.ordersTab.activeBar)=='table' then frame.ordersTab.activeBar:SetShown(view=='orders' or view=='orderCreate') end
    end
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
    if frame.back then
        frame.back:SetShown(#self.navigationStack>0)
        frame.back:ClearAllPoints()
        frame.back:SetPoint('TOPLEFT', frame, 'TOPLEFT', (view=='orders' and 612 or 770), -50)
    end
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
    connect(); if not active then chatError(T('Old Kraken: майстерня доступна після входу до гільдії.')); return end
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
        if not active then connect() end
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

if OldKraken.LocalizeTable then
    OldKraken.LocalizeTable(professions, 'name')
end
