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
local active, identity, profile, store, records = false, nil, nil, nil, {}
local pending, queryPending, forceBroadcast, lastReply, nextScan = false, false, false, -60, 0
local scanState
local frame, rows, offset, filterID, query, onlineOnly = nil, {}, 0, 0, '', false
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
local function changed() if render then render() end end
local function lower(text)
    text=text:lower():gsub('\208[\144-\175]',function(pair)
        local b=pair:byte(2)
        if b<=159 then return string.char(208,b+32) end
        return string.char(209,b-32)
    end)
    local special={['\208\132']='\209\148',['\208\134']='\209\150',['\208\135']='\209\151',['\210\144']='\210\145'}
    return (text:gsub('[\208\210][\128-\191]',special))
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
        active,identity,profile,store,records=false,nil,nil,nil,{}
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
    scanState=nil
    pending,queryPending,forceBroadcast,lastReply,nextScan=false,true,true,-60,0
    changed()
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

local function onlineIndex()
    local online={}
    if type(GetNumGuildMembers)~='function' or type(GetGuildRosterInfo)~='function' then return online end
    local ok,total=pcall(GetNumGuildMembers)
    if not ok or not integer(total,0,10000) then return online end
    for i=1,total do
        local success,name,_,_,_,_,_,_,_,isOnline=pcall(GetGuildRosterInfo,i)
        if success and usable(name,'string') and usable(isOnline,'boolean') then online[name]=isOnline end
    end
    return online
end
local function button(parent,text,x,y,width,callback,variant)
    local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate'); OldKraken.UIStyle.Button(b,variant)
    b:SetSize(width,24); b:SetPoint('TOPLEFT',parent,'TOPLEFT',x,y); b:SetText(text); b:SetScript('OnClick',callback); return b
end
render=function()
    if not frame then return end
    local online=onlineIndex(); local list={}
    for name,record in pairs(records) do
        if usable(name,'string') and type(record)=='table' and type(record.list)=='table' then
            for _,p in ipairs(record.list) do
                local skill=type(p)=='table' and byID[p.id]
                if skill and (filterID==0 or p.id==filterID) and (not onlineOnly or online[name] or name==identity)
                    and (query=='' or lower(name):find(query,1,true) or lower(skill.name):find(query,1,true)) then
                    list[#list+1]={name=name,skill=skill,rank=p.rank,maximum=p.maximum,timestamp=record.timestamp,online=online[name] or name==identity}
                end
            end
        end
    end
    table.sort(list,function(a,b) if a.skill.id~=b.skill.id then return a.skill.name<b.skill.name end; return a.name<b.name end)
    local pageCount=math.max(1,math.ceil(#list/12))
    offset=math.min(offset,pageCount-1)
    frame.page:SetText((offset+1)..' / '..pageCount)
    frame.previousPage:SetShown(pageCount>1)
    frame.nextPage:SetShown(pageCount>1)
    frame.count:SetText('Записів: '..#list..' · дата — останнє отримане оновлення'..(scanState==false and ' · власні дані не отримано' or ''))
    frame.online:SetText(onlineOnly and 'Лише онлайн: так' or 'Лише онлайн: ні')
    for i,row in ipairs(rows) do
        local entry=list[offset*12+i]
        if entry then
            row.entry=entry
            local dateText=integer(entry.timestamp,1,GetServerTime()+600) and date('%d.%m.%Y %H:%M',entry.timestamp) or 'невідомо'
            local stale=not integer(entry.timestamp,1,GetServerTime()+600) or GetServerTime()-entry.timestamp>604800
            row:SetText(entry.skill.name..'  ·  '..entry.name..'  ·  '..tostring(entry.rank)..'/'..tostring(entry.maximum)..'  ·  '..(entry.online and 'у грі' or 'офлайн / невідомо')..'  ·  '..dateText..(stale and ' · застаріло' or ''))
            row:Show()
        else row.entry=nil; row:Hide() end
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
    local search=CreateFrame('EditBox',nil,content,'InputBoxTemplate'); OldKraken.UIStyle.Input(search)
    search:SetSize(200,22); search:SetPoint('TOPLEFT',content,'TOPLEFT',20,y(-45)); search:SetAutoFocus(false)
    search:SetScript('OnTextChanged',function(self) query=lower(self:GetText() or ''); offset=0; render() end)
    search:SetScript('OnEscapePressed',function(self) self:ClearFocus() end)
    local drop=CreateFrame('Frame','OldKrakenWorkshopProfession',content,'UIDropDownMenuTemplate'); OldKraken.UIStyle.Dropdown(drop)
    drop:SetPoint('TOPLEFT',content,'TOPLEFT',220,y(-40)); UIDropDownMenu_SetWidth(drop,160)
    UIDropDownMenu_Initialize(drop,function(_,level)
        local all=UIDropDownMenu_CreateInfo(); all.text='Усі професії'; all.checked=filterID==0; all.func=function() filterID=0; offset=0; UIDropDownMenu_SetText(drop,'Усі професії'); render() end; UIDropDownMenu_AddButton(all,level)
        for _,p in ipairs(professions) do local entry=p; local item=UIDropDownMenu_CreateInfo(); item.text=entry.name; item.checked=filterID==entry.id
            item.func=function() filterID=entry.id; offset=0; UIDropDownMenu_SetText(drop,entry.name); render() end; UIDropDownMenu_AddButton(item,level) end
    end)
    UIDropDownMenu_SetText(drop,'Усі професії')
    f.online=button(content,'Лише онлайн: ні',430,y(-43),145,function() onlineOnly=not onlineOnly; offset=0; render() end)
    button(content,'Оновити',590,y(-43),120,function() forceBroadcast=true; nextScan=0; queryPending=true; print('Old Kraken: запит професій поставлено в чергу.') end)
    f.count=content:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); f.count:SetPoint('TOPLEFT',content,'TOPLEFT',20,y(-78))
    for i=1,12 do
        rows[i]=button(content,'',20,y(-103-(i-1)*(embedded and 30 or 26)),embedded and 845 or 725,function(self)
            local entry=self.entry
            if entry and entry.online and entry.name~=identity and type(ChatFrame_SendTell)=='function' then ChatFrame_SendTell(entry.name) end
        end)
        local font=rows[i]:GetFontString(); if font then font:ClearAllPoints(); font:SetJustifyH('LEFT'); font:SetPoint('LEFT',rows[i],'LEFT',8,0); font:SetPoint('RIGHT',rows[i],'RIGHT',-8,0) end
    end
    f.previousPage=button(content,'‹',embedded and 362 or 295,y(embedded and -477 or -430),44,function() offset=math.max(0,offset-1); render() end)
    f.page=content:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    f.page:SetPoint('TOPLEFT',content,'TOPLEFT',embedded and 418 or 351,y(embedded and -482 or -435)); f.page:SetWidth(64); f.page:SetJustifyH('CENTER')
    f.nextPage=button(content,'›',embedded and 494 or 427,y(embedded and -477 or -430),44,function() offset=offset+1; render() end)
    if not embedded then
        button(content,'Замовлення',20,-472,145,function() if OldKraken.WorkshopOrders then OldKraken.WorkshopOrders:Show() end end)
    end
    button(content,'Пошук рецептів',embedded and 20 or 175,y(embedded and -525 or -472),155,function() if OldKraken.WorkshopRecipes then OldKraken.WorkshopRecipes:Show() end end)
    local note=content:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); note:SetPoint('TOPLEFT',content,'TOPLEFT',345,y(embedded and -531 or -478)); note:SetText('Відкрийте професії, щоб зчитати рецепти.')
    content:HookScript('OnShow',render)
    f:Hide(); return f
end
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
