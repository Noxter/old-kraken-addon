-- Guild profession directory. Each character publishes only their own snapshot.
local Workshop = {}
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
local pending, queryPending, forceBroadcast, lastReply, nextScan = false, false, false, -60, 0
local scanState
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
local function changed()
    if render then render() end
    if type(OldKraken.Fire)=='function' then OldKraken:Fire('WORKSHOP_PROFESSIONS_CHANGED') end
end
-- Avoid treating an unavailable or temporarily empty API as proof of no skills.
local function scan()
    if type(GetProfessions)~='function' or type(GetProfessionInfo)~='function' then return nil end
    local ok,a,b,c,d,e,f=pcall(GetProfessions)
    if not ok then return nil end
    local indexes={a,b,c,d,e,f}; local found, list={},{}
    for i=1,6 do
        local index=integer(indexes[i],1,100000)
        if index then
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
    if #list==0 then return nil end
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
    if not integer(timestamp,1,GetServerTime()+600) or not integer(n,1,12) or #f~=2+n*3 then return nil end
    local found,list={},{}
    for i=1,n do
        local id,rank,maximum=tonumber(f[i*3]),tonumber(f[i*3+1]),tonumber(f[i*3+2])
        if not integer(id,1,1000000) or not byID[id] or found[id] or not integer(rank,1,9999) or not integer(maximum,1,9999) then return nil end
        found[id]=true; list[#list+1]={id=id,rank=rank,maximum=maximum}
    end
    return {timestamp=timestamp,list=list}
end
comm:RegisterHandler('WKPROF',function(sender,_,payload)
    if not active or not usable(sender,'string') or sender=='' or #sender>128 then return end
    local value=decode(payload); if not value then return end
    if sender==identity then return end
    if records[sender] and records[sender].timestamp>=value.timestamp then return end
    if not records[sender] and count(records)>=1000 then return end
    records[sender]=value; changed()
end)
comm:RegisterHandler('WKQUERY',function(sender,_,payload)
    if not active or payload~='' or sender==identity then return end
    local now=GetTime(); if now-lastReply<30 then return end
    lastReply=now; forceBroadcast=true; nextScan=0
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
    local db=OldKraken.DB
    if type(db.workshop)~='table' then db.workshop={} end
    if type(db.workshop.guilds)~='table' then db.workshop.guilds={} end
    if type(db.workshop.guilds[key])~='table' then db.workshop.guilds[key]={} end
    local scope=db.workshop.guilds[key]
    if type(scope.records)~='table' then scope.records={} end
    active,identity,profile,store,records=true,name,key,scope,scope.records
    nativeProfessions={}
    scanState=nil
    pending,queryPending,forceBroadcast,lastReply,nextScan=false,true,true,-60,0
    changed()
end
function Workshop:RefreshNativeProfessions()
    if not active or type(C_Club)~='table' or type(C_Club.GetGuildClubId)~='function' or type(C_Club.GetClubMembers)~='function' or type(C_Club.GetMemberInfo)~='function' then return false end
    local ok,club=pcall(C_Club.GetGuildClubId); if not ok or not integer(club,1,9000000000000000) then return false end
    local got,members=pcall(C_Club.GetClubMembers,club); if not got or not usable(members,'table') then return false end
    local fresh={}
    for index,memberID in ipairs(members) do
        if index>10000 then break end
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
    nativeProfessions=fresh; return true
end
function Workshop:GetMemberProfessions(name)
    if not active or not usable(name,'string') then return {} end
    local record=records[name]; local result={}
    if usable(record,'table') and usable(record.list,'table') then
        for _,p in ipairs(record.list) do
            if usable(p,'table') and byID[p.id] then result[#result+1]={id=p.id,rank=p.rank,maximum=p.maximum,timestamp=record.timestamp} end
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
                    found[name]={name=name,rank=integer(p.rank,1,9999),maximum=integer(p.maximum,1,9999),timestamp=record.timestamp}
                    break
                end
            end
        end
    end
    for name,list in pairs(nativeProfessions) do
        if usable(name,'string') and usable(list,'table') and not found[name] then
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
    if not list then changed(); return false end
    local previous=records[identity]
    if type(previous)=='table' and type(previous.list)=='table' then
        local found={}; for _,entry in ipairs(list) do found[entry.id]=true end
        for _,entry in ipairs(previous.list) do
            if type(entry)=='table' and byID[entry.id] and not found[entry.id] then
                scanState=false; changed(); return false
            end
        end
    end
    if type(previous)=='table' and type(previous.list)=='table' and not forceBroadcast then
        local ok,prior=pcall(encode,{timestamp=1,list=previous.list})
        if ok and prior==encode({timestamp=1,list=list}) and integer(previous.timestamp,1,GetServerTime()+600) and GetServerTime()-previous.timestamp<86400 then return true end
    end
    local previousTime=type(previous)=='table' and integer(previous.timestamp,1,GetServerTime()+600) or nil
    local snapshot={timestamp=math.max(GetServerTime(),(previousTime or 0)+1),list=list}
    forceBroadcast=false
    records[identity]=snapshot; pending=true; changed(); return true
end
local listener=CreateFrame('Frame')
for _,event in ipairs({'PLAYER_LOGIN','PLAYER_GUILD_UPDATE','GUILD_ROSTER_UPDATE','SKILL_LINES_CHANGED','CHAT_MSG_SKILL','TRADE_SKILL_SHOW'}) do
    pcall(listener.RegisterEvent,listener,event)
end
listener:SetScript('OnEvent',function(_,event)
    if event=='PLAYER_LOGIN' or event=='PLAYER_GUILD_UPDATE' or event=='GUILD_ROSTER_UPDATE' then connect(); changed()
    elseif active then nextScan=0 end
end)
if C_Timer and type(C_Timer.NewTicker)=='function' then
    C_Timer.NewTicker(3,function()
        connect(); if not active then return end
        local now=GetTime()
        if now>=nextScan then updateOwn(); nextScan=now+60 end
        if queryPending and comm:SendProtocol('WKQUERY','') then queryPending=false end
        if pending and records[identity] and comm:SendProtocol('WKPROF',encode(records[identity])) then pending=false end
    end)
end

local function button(parent,text,x,y,width,callback,variant)
    local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate'); OldKraken.UIStyle.Button(b,variant)
    b:SetSize(width,24); b:SetPoint('TOPLEFT',parent,'TOPLEFT',x,y); b:SetText(text); b:SetScript('OnClick',callback); return b
end
render=function()
    if not frame then return end
    frame.heading:SetText(scanState==false and 'Власні дані професій не отримано. Відкрийте професію.' or 'Оберіть професію, щоб переглянути рецепти та майстрів.')
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
        f.professionTab=button(f,'Професії',18,-38,110,function() Workshop:Show('professions') end)
        f.ordersTab=button(f,'Замовлення',136,-38,120,function()
            if OldKraken.WorkshopOrders then OldKraken.WorkshopOrders:Show() end
        end)
        for _,tab in ipairs({f.professionTab,f.ordersTab}) do
            tab.activeBar=tab:CreateTexture(nil,'ARTWORK')
            tab.activeBar:SetPoint('BOTTOMLEFT',tab,'BOTTOMLEFT',2,1)
            tab.activeBar:SetSize(tab==f.professionTab and 106 or 116,2)
            tab.activeBar:SetColorTexture(unpack(OldKraken.UIStyle.Colors.brandGold))
        end
        f.newOrder=button(f.ordersView or f,'Нове замовлення',720,-38,150,function()
            if OldKraken.WorkshopOrders then OldKraken.WorkshopOrders:OpenCreateForm() end
        end,'primary')
        f.newOrder:Hide()
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
        card.detail=card:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); card.detail:SetPoint('TOPLEFT',card,'TOPLEFT',45,-24); card.detail:SetWidth(180); card.detail:SetJustifyH('LEFT'); card.detail:SetWordWrap(false)
        card:SetScript('OnEnter',function(self) if GameTooltip then GameTooltip:SetOwner(self,'ANCHOR_RIGHT'); GameTooltip:SetText(entry.name); GameTooltip:AddLine('Натисніть, щоб переглянути рецепти гільдії.',1,1,1,true); GameTooltip:Show() end end)
        card:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
        f.professionCards[i]=card
    end
    if not embedded then
        button(content,'Замовлення',20,-472,145,function() if OldKraken.WorkshopOrders then OldKraken.WorkshopOrders:Show() end end)
    end
    button(content,'Пошук рецептів',embedded and 20 or 175,y(-315),155,function() if OldKraken.WorkshopRecipes then OldKraken.WorkshopRecipes:Show() end end)
    local note=content:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); note:SetPoint('TOPLEFT',content,'TOPLEFT',200,y(-321)); note:SetText('Відкрийте професії, щоб зчитати рецепти.')
    content:HookScript('OnShow',render)
    f:Hide(); return f
end
OldKraken:On('WORKSHOP_RECIPES_CHANGED',function() if frame and frame:IsShown() then render() end end)
function Workshop:SetView(view)
    if not frame or not frame.professionView then return end
    local showOrders=view=='orders'
    frame.professionView:SetShown(not showOrders)
    if frame.ordersView then frame.ordersView:SetShown(showOrders) end
    frame.professionTab.activeBar:SetShown(not showOrders)
    frame.ordersTab.activeBar:SetShown(showOrders)
    if frame.newOrder then frame.newOrder:SetShown(showOrders) end
    if showOrders and OldKraken.WorkshopOrders then OldKraken.WorkshopOrders:RefreshEmbedded() end
end
function Workshop:Show(view)
    connect(); if not active then print('Old Kraken: майстерня доступна після входу до гільдії.'); return end
    if OldKraken.UIHub then
        OldKraken.UIHub:ShowPage('workshop')
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
    local record=records[identity]
    if type(record)~='table' or type(record.list)~='table' then return false end
    for _,entry in ipairs(record.list) do if type(entry)=='table' and entry.id==id then return true end end
    return false
end
