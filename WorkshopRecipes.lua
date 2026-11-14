-- On-demand guild recipe search. Never treat a filtered scan as a complete list.
local Recipes={}
OldKraken.WorkshopRecipes=Recipes
local comm,codec=OldKraken.Communication,OldKraken.GroupFinder
local professionNames={[171]='Алхімія',[164]='Ковальство',[165]='Шкірництво',[197]='Кравецтво',[202]='Інженерія',[333]='Зачарування',[185]='Кулінарія',[129]='Перша допомога',[186]='Гірництво'}
local active,identity,profile,scope,people=false,nil,nil,nil,{}
local scanPending,tradeOpen,sendQueue=false,false,{}
local activeQuery,sequence,lastQuery,lastIncoming=nil,0,-60,{}
local frame,rows,offset,resultSet=nil,{},0,{}
local scanStatus='Відкрийте свої професії; шукайте назву рецепта, предмета або вставте посилання на предмет.'
local render
local function usable(v,t) return not (type(issecretvalue)=='function' and issecretvalue(v)) and type(v)==t end
local function integer(n,lo,hi) return usable(n,'number') and n==n and n%1==0 and n>=lo and n<=hi end
local function safeText(s,lo,hi) return usable(s,'string') and #s>=lo and #s<=hi and not s:find('[%z\1-\31\127]') end
local function lower(text)
    text=text:lower():gsub('\208[\144-\175]',function(pair)
        local b=pair:byte(2); if b<=159 then return string.char(208,b+32) end; return string.char(209,b-32)
    end)
    local map={['\208\132']='\209\148',['\208\134']='\209\150',['\208\135']='\209\151',['\210\144']='\210\145'}
    return (text:gsub('[\208\210][\128-\191]',map))
end
local function count(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
local function myName()
    if type(UnitName)~='function' then return nil end
    local a,b=UnitName('player'); if not safeText(a,1,128) then return nil end
    if usable(b,'string') and b~='' then a=a..' '..b end
    if safeText(a,1,128) then return a end
end
local function changed() if render then render() end end
local function validRecord(r)
    return type(r)=='table' and integer(r.recipe,1,100000000) and integer(r.item,0,100000000)
        and integer(r.profession,1,1000000) and professionNames[r.profession] and integer(r.seen,1,GetServerTime()+600)
        and safeText(r.name,1,120) and safeText(r.product,0,120)
end
local function connect()
    local name=myName(); local guild=type(GetGuildInfo)=='function' and GetGuildInfo('player')
    local realm=type(GetRealmName)=='function' and GetRealmName()
    if not name or not safeText(guild,1,128) or not usable(realm,'string') or not OldKraken.DB then
        active,identity,profile,scope,people=false,nil,nil,nil,{}; activeQuery=nil; sendQueue={}
        if frame then frame:Hide() end; return
    end
    local k=realm..'\001'..guild
    if active and identity==name and profile==k then return end
    local db=OldKraken.DB; if type(db.workshop)~='table' then db.workshop={} end
    if type(db.workshop.guilds)~='table' then db.workshop.guilds={} end
    if type(db.workshop.guilds[k])~='table' then db.workshop.guilds[k]={} end
    scope=db.workshop.guilds[k]; if type(scope.recipes)~='table' then scope.recipes={} end
    active,identity,profile,people=true,name,k,scope.recipes
    if type(people[name])~='table' then people[name]={} end
    activeQuery,sendQueue,lastIncoming,resultSet=nil,{}, {}, {}
    changed()
end
local function callBool(api,name,required)
    if type(api[name])~='function' then return not required end
    local ok,value=pcall(api[name]); return ok and usable(value,'boolean') and value==false
end
local function personalTradeSkill(api)
    -- Do not attribute a linked, guild, or NPC profession to the player.
    if not callBool(api,'IsTradeSkillLinked',true) or not callBool(api,'IsTradeSkillGuild',true)
        or not callBool(api,'IsNPCCrafting',true) or not callBool(api,'IsTradeSkillGuildMember',false)
        or not callBool(api,'IsDataSourceChanging',false) then return false end
    if type(api.IsTradeSkillReady)=='function' then
        local ok,ready=pcall(api.IsTradeSkillReady); if not ok or not usable(ready,'boolean') or not ready then return false end
    end
    return true
end
local function outputInfo(api,id)
    local item,product=0,''
    if type(api.GetRecipeOutputItemData)=='function' then
        local ok,data=pcall(api.GetRecipeOutputItemData,id)
        if ok and usable(data,'table') then
            if integer(data.itemID,1,100000000) then item=data.itemID end
            if usable(data.hyperlink,'string') then product=data.hyperlink:match('%[([^%]]+)%]') or '' end
        end
    end
    if item==0 and type(api.GetRecipeSchematic)=='function' then
        local ok,data=pcall(api.GetRecipeSchematic,id,false)
        if ok and usable(data,'table') and integer(data.outputItemID,1,100000000) then item=data.outputItemID end
    end
    if product=='' and item>0 and type(GetItemInfo)=='function' then
        local ok,name=pcall(GetItemInfo,item); if ok and safeText(name,1,120) then product=name end
    end
    if not safeText(product,0,120) then product='' end
    return item,product
end
local function playerHasProfession(profession)
    if type(GetProfessions)~='function' or type(GetProfessionInfo)~='function' then return false end
    local ok,a,b,c,d,e,f=pcall(GetProfessions); if not ok then return false end
    local indexes={a,b,c,d,e,f}
    for i=1,6 do
        if integer(indexes[i],1,100000) then
            local success,_,_,_,_,_,_,skillLine=pcall(GetProfessionInfo,indexes[i])
            if success and integer(skillLine,1,1000000) and skillLine==profession then return true end
        end
    end
    return false
end
local function scan()
    if not active or not tradeOpen or type(C_TradeSkillUI)~='table' then return end
    local api=C_TradeSkillUI
    if not personalTradeSkill(api) or type(api.GetBaseProfessionInfo)~='function' or type(api.GetRecipeInfo)~='function' then return end
    local ok,prof=pcall(api.GetBaseProfessionInfo)
    if not ok or not usable(prof,'table') then return end
    local profession=integer(prof.professionID,1,1000000) and prof.professionID or nil
    if not professionNames[profession] or not playerHasProfession(profession) then return end
    local got,ids=false,nil
    if type(api.GetAllRecipeIDs)=='function' then got,ids=pcall(api.GetAllRecipeIDs) end
    if (not got or not usable(ids,'table') or #ids==0) and type(api.GetFilteredRecipeIDs)=='function' then got,ids=pcall(api.GetFilteredRecipeIDs) end
    if not got or not usable(ids,'table') then return end
    local own=people[identity]; local ownCount=count(own); local seen=GetServerTime(); local touched=0
    for index,id in ipairs(ids) do
        if index>10000 then break end
        if integer(id,1,100000000) then
            local success,info=pcall(api.GetRecipeInfo,id)
            if success and usable(info,'table') and usable(info.learned,'boolean') then
                if info.learned and safeText(info.name,1,120) then
                    local item,product=outputInfo(api,id)
                    local previous=own[id]
                    if product=='' and type(previous)=='table' and previous.item==item and safeText(previous.product,0,120) then product=previous.product end
                    if ownCount<5000 or previous then
                        if not previous then ownCount=ownCount+1 end
                        own[id]={recipe=id,item=item,profession=profession,seen=seen,name=info.name,product=product}; touched=touched+1
                    end
                elseif info.learned==false and type(own[id])=='table' and own[id].profession==profession then
                    own[id]=nil; ownCount=math.max(0,ownCount-1)
                end
            end
        end
    end
    scanStatus='Останнє зчитування: '..touched..' вивчених рецептів. Список може бути відфільтрований.'
    if frame and frame:IsShown() then frame.status:SetText(scanStatus) end
    return true
end
local function matches(r,query)
    if not validRecord(r) then return false end
    local item=query:match('^item:(%d+)$')
    if item then return r.item==tonumber(item) end
    return lower(r.name):find(query,1,true)~=nil or lower(r.product):find(query,1,true)~=nil
end
local function resolveProduct(r)
    if validRecord(r) and r.product=='' and r.item>0 and type(GetItemInfo)=='function' then
        local ok,name=pcall(GetItemInfo,r.item)
        if ok and safeText(name,1,120) then r.product=name end
    end
end
local function addCached(query)
    resultSet={}
    for name,items in pairs(people) do
        if safeText(name,1,128) and type(items)=='table' then
            for _,r in pairs(items) do
                if count(resultSet)>=500 then return end
                resolveProduct(r)
                if matches(r,query) then resultSet[name..'\001'..r.recipe]={owner=name,record=r} end
            end
        end
    end
end
local function search(value)
    if not active or not safeText(value,1,200) then print('Old Kraken: введіть назву або посилання на предмет.'); return false end
    local item=value:match('item:(%d+)')
    local q=item and ('item:'..item) or lower(value:match('^%s*(.-)%s*$'))
    if not safeText(q,3,80) then print('Old Kraken: введіть назву або посилання на предмет.'); return false end
    local now=GetTime(); if now-lastQuery<10 then print('Old Kraken: повторіть пошук через кілька секунд.'); return false end
    sequence=sequence+1
    local token=tostring(GetServerTime())..'-'..tostring(math.random(100000,999999))..'-'..sequence
    offset=0; addCached(q)
    if not comm:SendProtocol('WRQUERY',codec._pack({token,q})) then activeQuery=nil; changed(); print('Old Kraken: показано збережені результати; запит гільдії надіслати не вдалося.'); return false end
    lastQuery=now; activeQuery={token=token,query=q,untilTime=now+120}; changed(); return true
end
comm:RegisterHandler('WRQUERY',function(sender,_,payload)
    if not active or not safeText(sender,1,128) or sender==identity then return end
    local f=codec._unpackFields(payload,2)
    if not f or #f~=2 or not safeText(f[1],1,64) or not f[1]:match('^[%d%-]+$') or not safeText(f[2],3,80) then return end
    local now=GetTime(); if lastIncoming[sender] and now-lastIncoming[sender]<10 then return end
    if not lastIncoming[sender] and count(lastIncoming)>=1000 then return end
    lastIncoming[sender]=now
    local found={}
    for _,r in pairs(people[identity] or {}) do resolveProduct(r); if matches(r,f[2]) then found[#found+1]=r end end
    table.sort(found,function(a,b) return a.recipe<b.recipe end)
    for i=1,math.min(#found,12) do
        if #sendQueue>=100 then break end
        local r=found[i]; local msg=codec._pack({sender,f[1],r.recipe,r.item,r.profession,r.seen,r.name,r.product})
        sendQueue[#sendQueue+1]={payload=msg,expires=now+120}
    end
end)
comm:RegisterHandler('WRRESULT',function(sender,_,payload)
    if not active or not activeQuery or GetTime()>activeQuery.untilTime or not safeText(sender,1,128) then return end
    local f=codec._unpackFields(payload,8)
    if not f or #f~=8 or f[1]~=identity or f[2]~=activeQuery.token then return end
    local r={recipe=tonumber(f[3]),item=tonumber(f[4]),profession=tonumber(f[5]),seen=tonumber(f[6]),name=f[7],product=f[8]}
    if not matches(r,activeQuery.query) then return end
    if type(people[sender])~='table' then if count(people)>=1000 then return end; people[sender]={} end
    if not people[sender][r.recipe] and count(people[sender])>=5000 then return end
    local old=people[sender][r.recipe]
    if not validRecord(old) or old.seen<=r.seen then people[sender][r.recipe]=r end
    local k=sender..'\001'..r.recipe
    if resultSet[k] or count(resultSet)<500 then resultSet[k]={owner=sender,record=people[sender][r.recipe]} end
    changed()
end)

local events=CreateFrame('Frame')
for _,event in ipairs({'PLAYER_LOGIN','PLAYER_GUILD_UPDATE','GUILD_ROSTER_UPDATE','TRADE_SKILL_SHOW','TRADE_SKILL_LIST_UPDATE','TRADE_SKILL_DATA_SOURCE_CHANGED','TRADE_SKILL_CLOSE'}) do pcall(events.RegisterEvent,events,event) end
events:SetScript('OnEvent',function(_,event)
    if event=='PLAYER_LOGIN' or event=='PLAYER_GUILD_UPDATE' or event=='GUILD_ROSTER_UPDATE' then connect()
    elseif event=='TRADE_SKILL_CLOSE' then tradeOpen=false; scanPending=false
    elseif event=='TRADE_SKILL_SHOW' then tradeOpen=true; scanPending=true
    elseif tradeOpen then scanPending=true end
end)
if C_Timer and type(C_Timer.NewTicker)=='function' then C_Timer.NewTicker(3,function()
    connect(); if not active then return end
    if scanPending then
        scanPending=false
        local ok,completed=pcall(scan)
        if not ok or not completed then
            scanStatus='Не вдалося зчитати власну професію. Відкрийте її та перевірте доступність API.'
            if frame and frame:IsShown() then frame.status:SetText(scanStatus) end
        end
    end
    while #sendQueue>0 and sendQueue[1].expires<GetTime() do table.remove(sendQueue,1) end
    if #sendQueue>0 and #comm.queue<=8 and comm:SendProtocol('WRRESULT',sendQueue[1].payload) then table.remove(sendQueue,1) end
end) end

local function button(parent,label,x,y,width,callback)
    local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate'); OldKraken.UIStyle.Button(b)
    b:SetSize(width,24); b:SetPoint('TOPLEFT',parent,'TOPLEFT',x,y); b:SetText(label); b:SetScript('OnClick',callback); return b
end
local function onlineIndex()
    local result={}; if type(GetNumGuildMembers)~='function' or type(GetGuildRosterInfo)~='function' then return result end
    local ok,n=pcall(GetNumGuildMembers); if not ok or not integer(n,0,10000) then return result end
    for i=1,n do local success,name,_,_,_,_,_,_,_,online=pcall(GetGuildRosterInfo,i)
        if success and usable(name,'string') and usable(online,'boolean') then result[name]=online end end
    return result
end
render=function()
    if not frame or not frame:IsShown() then return end
    local online=onlineIndex(); local list={}
    for _,entry in pairs(resultSet) do if validRecord(entry.record) then list[#list+1]=entry end end
    table.sort(list,function(a,b) if a.record.name~=b.record.name then return a.record.name<b.record.name end return a.owner<b.owner end)
    offset=math.max(0,math.min(offset,math.max(0,math.ceil(#list/12)-1)))
    frame.page:SetText((offset+1)..' / '..math.max(1,math.ceil(#list/12)))
    frame.count:SetText('Знайдено: '..#list..' · результати можуть бути застарілими або неповними')
    for i,row in ipairs(rows) do
        local entry=list[offset*12+i]
        if entry then
            local r=entry.record; row.entry=entry
            row:SetText((r.product~='' and r.product or r.name)..' · '..entry.owner..' · '..professionNames[r.profession]..' · '..(online[entry.owner] and 'у грі' or 'офлайн / невідомо')..' · '..date('%d.%m.%Y',r.seen))
            row:Show()
        else row.entry=nil; row:Hide() end
    end
end
local function createWindow()
    local f=CreateFrame('Frame','OldKrakenWorkshopRecipesFrame',UIParent,'BasicFrameTemplateWithInset')
    table.insert(UISpecialFrames,'OldKrakenWorkshopRecipesFrame'); f:SetSize(820,520); f:SetPoint('CENTER'); f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
    f:RegisterForDrag('LeftButton'); f:SetScript('OnDragStart',f.StartMoving); f:SetScript('OnDragStop',f.StopMovingOrSizing); OldKraken.UIStyle.Window(f)
    if f.TitleText then f.TitleText:SetText('Old Kraken — Пошук рецептів') end
    f.query=CreateFrame('EditBox',nil,f,'InputBoxTemplate'); f.query:SetSize(460,24); f.query:SetPoint('TOPLEFT',f,'TOPLEFT',24,-48); f.query:SetAutoFocus(false)
    f.query:SetScript('OnEscapePressed',function(self) self:ClearFocus() end)
    f.query:SetScript('OnEnterPressed',function(self) if search(self:GetText() or '') then self:ClearFocus() end end)
    button(f,'Знайти',500,-48,120,function() search(f.query:GetText() or '') end)
    f.count=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); f.count:SetPoint('TOPLEFT',f,'TOPLEFT',20,-78)
    for i=1,12 do
        rows[i]=button(f,'',20,-102-(i-1)*26,770,function(self)
            if self.entry and self.entry.owner~=identity and type(ChatFrame_SendTell)=='function' then ChatFrame_SendTell(self.entry.owner) end
        end)
        local text=rows[i]:GetFontString(); if text then text:ClearAllPoints(); text:SetPoint('LEFT',rows[i],'LEFT',8,0); text:SetPoint('RIGHT',rows[i],'RIGHT',-8,0); text:SetJustifyH('LEFT') end
    end
    button(f,'‹',20,-425,44,function() offset=offset-1; render() end)
    f.page=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); f.page:SetPoint('TOPLEFT',f,'TOPLEFT',75,-430)
    button(f,'›',130,-425,44,function() offset=offset+1; render() end)
    f.status=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); f.status:SetPoint('TOPLEFT',f,'TOPLEFT',20,-465); f.status:SetWidth(760); f.status:SetJustifyH('LEFT')
    f.status:SetText(scanStatus)
    f:Hide(); return f
end
function Recipes:Show()
    connect(); if not active then print('Old Kraken: пошук рецептів доступний членам гільдії.'); return end
    if not frame then frame=createWindow() end
    frame:Show(); render()
end
