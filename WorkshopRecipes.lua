-- On-demand guild recipe search. Never treat a filtered scan as a complete list.
local Recipes={}
OldKraken.WorkshopRecipes=Recipes
local comm,codec=OldKraken.Communication,OldKraken.GroupFinder
local professionNames={[171]='Алхімія',[164]='Ковальство',[165]='Шкірництво',[197]='Кравецтво',[202]='Інженерія',[333]='Зачарування',[185]='Кулінарія',[129]='Перша допомога',[186]='Гірництво',[182]='Травництво',[393]='Свіжування',[356]='Риболовля'}
local active,identity,profile,scope,people=false,nil,nil,nil,{}
local pendingLearned,learnAttempts={},{}
local recipeCatalog,catalogCursor,catalogPending,catalogSize=nil,nil,false,0
local scanPending,tradeOpen,sendQueue=false,false,{}
local activeQuery,sequence,lastQuery,lastIncoming=nil,0,-60,{}
local forgetChecks,lastScanProfession={},nil
local frame,rows,offset,resultSet=nil,{},0,{}
local PAGE_SIZE=10
local selectRecipe,selectedEntry,viewOwner
local pickerProfession=0
local professionContext, selectedMaster, tab, mastersOnline = nil, nil, 'recipes', false
local restoringView=false
local resultQuery
local tabStates={}
local recipeChanged=false
local indexRevision=0
local summaryCache,itemIndex={},{}
local indexedRevision=-1
local indexJob,searchJob
local ownItems,ownItemsRevision={},-1
local scanStatus='Відкрийте свої професії; шукайте назву рецепта, предмета або вставте посилання на предмет.'
local render, matches
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
local changedPending=false
local function changed()
    if changedPending then return end
    if not (frame and frame:IsShown()) then return end
    local function flush()
        changedPending=false
        if frame and frame:IsShown() then if render then render() end end
    end
    if C_Timer and C_Timer.After then changedPending=true; C_Timer.After(0.15,flush) else flush() end
end

local function validRecord(r)
    return type(r)=='table' and integer(r.recipe,1,100000000) and integer(r.item,0,100000000)
        and integer(r.profession,1,1000000) and professionNames[r.profession] and integer(r.seen,1,GetServerTime()+600)
        and safeText(r.name,1,120) and safeText(r.product,0,120)
end
local function connect()
    local name=myName(); local guild=type(GetGuildInfo)=='function' and GetGuildInfo('player')
    local realm=type(GetRealmName)=='function' and GetRealmName()
    if not name or not safeText(guild,1,128) or not usable(realm,'string') or not OldKraken.DB then
        if Recipes.CancelPicker then Recipes:CancelPicker() end
        active,identity,profile,scope,people=false,nil,nil,nil,{}; activeQuery=nil; sendQueue={}; pendingLearned,learnAttempts={},{}
        tabStates={}
        indexRevision=indexRevision+1; indexedRevision=-1; summaryCache,itemIndex={},{}; indexJob,searchJob=nil,nil
        if frame then frame:Hide() end; return
    end
    local k=realm..'\001'..guild
    if active and identity==name and profile==k then return end
    if Recipes.CancelPicker then Recipes:CancelPicker() end
    tabStates={}
    indexRevision=indexRevision+1; indexedRevision=-1; summaryCache,itemIndex={},{}; indexJob,searchJob=nil,nil
    local db=OldKraken.DB; if type(db.workshop)~='table' then db.workshop={} end
    if type(db.workshop.recipeCatalog)~='table' then db.workshop.recipeCatalog={} end
    recipeCatalog,catalogCursor,catalogPending=db.workshop.recipeCatalog,nil,true
    catalogSize=count(recipeCatalog)
    if type(db.workshop.guilds)~='table' then db.workshop.guilds={} end
    if type(db.workshop.guilds[k])~='table' then db.workshop.guilds[k]={} end
    scope=db.workshop.guilds[k]; if type(scope.recipes)~='table' then scope.recipes={} end
    if type(scope.recipeSources)~='table' then scope.recipeSources={} end
    if type(scope.recipeVersions)~='table' then scope.recipeVersions={} end
    if type(scope.recipeVersionSeen)~='table' then scope.recipeVersionSeen={} end
    if type(scope.recipeTombstones)~='table' then scope.recipeTombstones={} end
    active,identity,profile,people=true,name,k,scope.recipes
    if type(people[name])~='table' then people[name]={} end
    if type(scope.recipeTombstones[name])~='table' then scope.recipeTombstones[name]={} end
    if not integer(scope.recipeVersions[name],1,9000000000000000) then scope.recipeVersions[name]=GetServerTime()*1000 end
    if type(scope.pendingRecipes)~='table' then scope.pendingRecipes={} end
    if type(scope.pendingRecipes[name])~='table' then scope.pendingRecipes[name]={} end
    pendingLearned,learnAttempts=scope.pendingRecipes[name],{}
    activeQuery,sendQueue,lastIncoming,resultSet,forgetChecks,lastScanProfession=nil,{}, {}, {}, {},nil
    local removals=type(scope.pendingProfessionRemovals)=='table' and scope.pendingProfessionRemovals[name]
    if type(removals)=='table' and type(Recipes.ForgetProfession)=='function' then
        for profession in pairs(removals) do Recipes:ForgetProfession(profession,name,k) end
    end
    changed()
end
local function storeRecipe(owner,r,relayed,authoritative)
    if type(people[owner])~='table' then if count(people)>=1000 then return nil end; people[owner]={} end
    if type(scope.recipeSources[owner])~='table' then scope.recipeSources[owner]={} end
    if type(scope.recipeTombstones[owner])~='table' then scope.recipeTombstones[owner]={} end
    local records,sources=people[owner],scope.recipeSources[owner]
    local tomb=scope.recipeTombstones[owner][r.recipe]
    if validRecord(tomb) then
        if tomb.seen>=r.seen and not (authoritative and not relayed and sources[r.recipe]==true) then return nil end
        scope.recipeTombstones[owner][r.recipe]=nil
    end
    local old=records[r.recipe]
    if not validRecord(old) or (authoritative and not relayed and sources[r.recipe]==true) or old.seen<=r.seen then
        records[r.recipe]=r; sources[r.recipe]=relayed and true or false
    end
    return records[r.recipe]
end
local function storeTombstone(owner,r,relayed,authoritative)
    if type(people[owner])~='table' then if count(people)>=1000 then return false end; people[owner]={} end
    if type(scope.recipeSources[owner])~='table' then scope.recipeSources[owner]={} end
    if type(scope.recipeTombstones[owner])~='table' then scope.recipeTombstones[owner]={} end
    local records,tombs,sources=people[owner],scope.recipeTombstones[owner],scope.recipeSources[owner]
    local old,tomb=records[r.recipe],tombs[r.recipe]
    local directOverride=authoritative and not relayed and sources[r.recipe]==true
    if validRecord(old) and old.seen>r.seen and not directOverride then return false end
    if validRecord(tomb) and tomb.seen>=r.seen and not directOverride then return false end
    if not old and not tomb and count(records)+count(tombs)>=5000 then return false end
    records[r.recipe]=nil; tombs[r.recipe]={recipe=r.recipe,item=r.item,profession=r.profession,seen=r.seen,name=r.name,product=r.product,deleted=true}
    sources[r.recipe]=relayed and true or false
    local k=owner..'\001'..r.recipe; resultSet[k]=nil
    if selectedEntry and selectedEntry.owner==owner and selectedEntry.record.recipe==r.recipe then selectedEntry=nil end
    return true
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
local function isAsciiText(value) return type(value)=='string' and value~='' and not value:find('[\128-\255]') end
local function recordLearned(r,deferRefresh)
    local own=people[identity]; local previous=own[r.recipe]
    local tomb=scope.recipeTombstones[identity][r.recipe]
    if not previous and not tomb and count(own)+count(scope.recipeTombstones[identity])>=5000 then return false end
    if validRecord(previous) then r.seen=math.max(r.seen,previous.seen) end
    if validRecord(tomb) then r.seen=math.max(r.seen,tomb.seen+1); if not validRecord(r) then return false end end
    if r.product=='' and type(previous)=='table' and previous.item==r.item and safeText(previous.product,0,120) then r.product=previous.product end
    local lastVersionSeen=tonumber(scope.recipeVersionSeen[identity]) or 0
    if not validRecord(previous) or previous.item~=r.item or previous.profession~=r.profession or previous.name~=r.name or previous.product~=r.product
        or (r.seen>previous.seen and GetServerTime()-lastVersionSeen>=3600) then
        scope.recipeVersions[identity]=math.max((scope.recipeVersions[identity] or 0)+1,GetServerTime()*1000)
        scope.recipeVersionSeen[identity]=GetServerTime()
    end
    own[r.recipe]=r; scope.recipeTombstones[identity][r.recipe]=nil
    if recipeCatalog and (recipeCatalog[r.recipe] or catalogSize<10000) then
        local existing=recipeCatalog[r.recipe]
        if not existing then catalogSize=catalogSize+1 end
        local catName=r.name
        local catProduct=r.product
        if type(existing)=='table' then
            if isAsciiText(existing.name) and not isAsciiText(catName) then catName=existing.name end
            if isAsciiText(existing.product) and not isAsciiText(catProduct) then catProduct=existing.product end
        end
        recipeCatalog[r.recipe]={recipe=r.recipe,item=r.item,profession=r.profession,seen=r.seen,name=catName,product=catProduct}
    end
    indexRevision=indexRevision+1; recipeChanged=true
    if pendingLearned[r.recipe] then
        if #sendQueue<100 then
            pendingLearned[r.recipe]=nil; learnAttempts[r.recipe]=nil
            local payload=codec._pack({r.recipe,r.item,r.profession,r.seen,r.name,r.product})
            sendQueue[#sendQueue+1]={kind='WRLEARN',payload=payload,expires=GetTime()+120}
        end
    end
    if activeQuery and matches and matches(r,activeQuery.query) then
        local resultKey=identity..'\001'..r.recipe
        if resultSet[resultKey] or count(resultSet)<500 then resultSet[resultKey]={owner=identity,record=r} end
        if not deferRefresh then changed() end
    end
    return true
end
local function forgetRecipe(id,deferRefresh)
    local own=people[identity]; local old=own and own[id]
    if not validRecord(old) then return false end
    local removed={recipe=old.recipe,item=old.item,profession=old.profession,seen=math.max(GetServerTime(),old.seen),name=old.name,product=old.product,deleted=true}
    if not storeTombstone(identity,removed,false) then return false end
    scope.recipeVersions[identity]=math.max((scope.recipeVersions[identity] or 0)+1,GetServerTime()*1000)
    scope.recipeVersionSeen[identity]=GetServerTime()
    pendingLearned[id],learnAttempts[id],forgetChecks[id]=nil,nil,nil
    if #sendQueue<100 then
        sendQueue[#sendQueue+1]={kind='WRFORGET',payload=codec._pack({removed.recipe,removed.item,removed.profession,removed.seen,removed.name,removed.product}),expires=GetTime()+600}
    end
    indexRevision=indexRevision+1; recipeChanged=true; if not deferRefresh then changed() end; return true
end
function Recipes:ForgetProfession(profession,expectedIdentity,expectedProfile)
    if not active or not professionNames[profession] or identity~=expectedIdentity or profile~=expectedProfile then return false end
    local ids={}; for id,r in pairs(people[identity] or {}) do if validRecord(r) and r.profession==profession then ids[#ids+1]=id end end
    local changedAny=false; for _,id in ipairs(ids) do if forgetRecipe(id,true) then changedAny=true end end
    if changedAny then changed() end
    if type(scope.pendingProfessionRemovals)=='table' and type(scope.pendingProfessionRemovals[identity])=='table' then scope.pendingProfessionRemovals[identity][profession]=nil end
    return true,changedAny
end
local function scanLearned(id)
    if not active or not integer(id,1,100000000) or type(C_TradeSkillUI)~='table' then return false end
    local api=C_TradeSkillUI
    if type(api.GetRecipeInfo)~='function' then return false end
    local ok,info=pcall(api.GetRecipeInfo,id)
    if not ok or not usable(info,'table') or not usable(info.learned,'boolean') or not info.learned or not safeText(info.name,1,120) then return false end
    local profession
    if type(api.GetProfessionInfoByRecipeID)=='function' then
        local success,data=pcall(api.GetProfessionInfoByRecipeID,id)
        if success and usable(data,'table') then
            if integer(data.parentProfessionID,1,1000000) and professionNames[data.parentProfessionID] then profession=data.parentProfessionID
            elseif integer(data.professionID,1,1000000) and professionNames[data.professionID] then profession=data.professionID end
        end
    end
    if not profession and type(api.GetTradeSkillLineForRecipe)=='function' then
        local success,line=pcall(api.GetTradeSkillLineForRecipe,id)
        if success and integer(line,1,1000000) and professionNames[line] then profession=line end
    end
    if not profession or not playerHasProfession(profession) then return false end
    local item,product=outputInfo(api,id)
    return recordLearned({recipe=id,item=item,profession=profession,seen=GetServerTime(),name=info.name,product=product})
end
local function scan()
    if not active or not tradeOpen or type(C_TradeSkillUI)~='table' then return end
    local api=C_TradeSkillUI
    if not personalTradeSkill(api) or type(api.GetBaseProfessionInfo)~='function' or type(api.GetRecipeInfo)~='function' then return end
    local ok,prof=pcall(api.GetBaseProfessionInfo)
    if not ok or not usable(prof,'table') then return end
    local profession=integer(prof.professionID,1,1000000) and prof.professionID or nil
    if not professionNames[profession] or not playerHasProfession(profession) then return end
    if lastScanProfession~=profession then forgetChecks={}; lastScanProfession=profession end
    local got,ids=false,nil
    if type(api.GetAllRecipeIDs)=='function' then got,ids=pcall(api.GetAllRecipeIDs) end
    local full=got and usable(ids,'table') and #ids>0 and #ids<=10000
    if (not got or not usable(ids,'table') or #ids==0) and type(api.GetFilteredRecipeIDs)=='function' then got,ids=pcall(api.GetFilteredRecipeIDs) end
    if not got or not usable(ids,'table') then return end
    local own=people[identity]; local ownCount=count(own); local seen=GetServerTime(); local touched=0
    local candidates,seenIDs={},{}
    if full then
        if type(api.IsTradeSkillReady)~='function' or type(api.IsDataSourceChanging)~='function' then full=false
        else
            local readyOk,ready=pcall(api.IsTradeSkillReady); local changingOk,changing=pcall(api.IsDataSourceChanging)
            if not readyOk or not changingOk or ready~=true or changing~=false then full=false end
        end
        for index in pairs(ids) do if not integer(index,1,#ids) then full=false; break end end
    end
    for index,id in ipairs(ids) do
        if index>10000 then break end
        if not integer(id,1,100000000) or seenIDs[id] then full=false
        else
            seenIDs[id]=true
            local success,info=pcall(api.GetRecipeInfo,id)
            if success and usable(info,'table') and usable(info.learned,'boolean') then
                if info.learned and safeText(info.name,1,120) then
                    local item,product=outputInfo(api,id)
                    local previous=own[id]
                    if ownCount<5000 or previous then
                        if recordLearned({recipe=id,item=item,profession=profession,seen=seen,name=info.name,product=product},true) then
                            if not previous then ownCount=ownCount+1 end; touched=touched+1
                        end
                    end
                elseif info.learned==false and info.isDummyRecipe~=true and validRecord(own[id]) and own[id].profession==profession then candidates[id]=true
                elseif info.learned==true then full=false end
            else full=false end
        end
    end
    local removedAny=false
    if full then
        local readyOk,ready=pcall(api.IsTradeSkillReady); local changingOk,changing=pcall(api.IsDataSourceChanging)
        if not readyOk or not changingOk or ready~=true or changing~=false then full=false end
    end
    for id,check in pairs(forgetChecks) do
        if check.profession==profession and (not full or not candidates[id]) then forgetChecks[id]=nil end
    end
    if full then
        local now=GetTime()
        for id in pairs(candidates) do
            local check=forgetChecks[id]
            if not check or check.profession~=profession then check={profession=profession,first=now,count=0}; forgetChecks[id]=check end
            check.count=check.count+1
            if check.count>=3 and now-check.first>=6 then if forgetRecipe(id,true) then removedAny=true end else scanPending=true end
        end
    end
    if touched>0 or removedAny then changed() end
    scanStatus='Останнє зчитування: '..touched..' вивчених рецептів. Список може бути відфільтрований.'
    if frame and frame:IsShown() then frame.status:SetText(scanStatus) end
    return true
end
local function clientItemName(id)
    if not id or id<=0 then return nil end
    if C_Item and type(C_Item.GetItemNameByID)=='function' then
        local ok,value=pcall(C_Item.GetItemNameByID,id); if ok and safeText(value,1,120) then return value end
    end
    if type(GetItemInfo)=='function' then
        local ok,value=pcall(GetItemInfo,id); if ok and safeText(value,1,120) then return value end
    end
    return nil
end
local function clientSpellName(id)
    if not id or id<=0 then return nil end
    if C_Spell and type(C_Spell.GetSpellName)=='function' then
        local ok,value=pcall(C_Spell.GetSpellName,id); if ok and safeText(value,1,120) then return value end
    end
    if type(GetSpellInfo)=='function' then
        local ok,value=pcall(GetSpellInfo,id); if ok and safeText(value,1,120) then return value end
    end
    return nil
end
local function displayRecipeName(r)
    if type(r)~='table' then return '' end
    local localName=r.item>0 and clientItemName(r.item) or clientSpellName(r.recipe)
    if localName then return localName end
    local cat=recipeCatalog and recipeCatalog[r.recipe]
    if type(cat)=='table' then
        local catText=cat.product~='' and cat.product or cat.name
        if isAsciiText(catText) then return catText end
    end
    return r.product~='' and r.product or r.name
end
matches=function(r,query)
    if not validRecord(r) then return false end
    local profession=query:match('^prof:(%d+)$')
    if profession then return r.profession==tonumber(profession) end
    local item=query:match('^item:(%d+)$')
    if item then return r.item==tonumber(item) end
    local recipe=query:match('^recipe:(%d+)$')
    if recipe then return r.recipe==tonumber(recipe) end
    return lower(r.name):find(query,1,true)~=nil or lower(r.product):find(query,1,true)~=nil or lower(displayRecipeName(r)):find(query,1,true)~=nil
end
local function resolveProduct(r)
    if validRecord(r) and r.product=='' and r.item>0 and type(GetItemInfo)=='function' then
        local ok,name=pcall(GetItemInfo,r.item)
        if ok and safeText(name,1,120) then r.product=name end
    end
end
local function textFilter(text)
    return lower((text or ''):match('^%s*(.-)%s*$'))
end
local function matchesFilter(r,filter)
    if filter=='' then return true end
    local recipe=filter:match('^recipe:(%d+)$')
    if recipe then return r.recipe==tonumber(recipe) end
    filter=filter:match('item:(%d+)') or filter
    return lower(r.name):find(filter,1,true)~=nil or lower(r.product):find(filter,1,true)~=nil or lower(displayRecipeName(r)):find(filter,1,true)~=nil or tostring(r.item):find(filter,1,true)~=nil
end
local function scanCachedRecords(visit,done,valid)
    local owners={}; for name in pairs(people) do owners[#owners+1]=name end
    local source=people
    local ownerIndex,records,recordIndex,currentOwner=1,nil,1,nil
    local function step()
        if people~=source or (valid and not valid()) then return end
        local budget=200
        while budget>0 and ownerIndex<=#owners do
            if not records then
                currentOwner=owners[ownerIndex]; records={}; recordIndex=1
                if safeText(currentOwner,1,128) and type(source[currentOwner])=='table' then
                    for _,r in pairs(source[currentOwner]) do records[#records+1]=r end
                end
            end
            local r=records[recordIndex]
            if r then
                recordIndex=recordIndex+1; budget=budget-1
                if visit(currentOwner,r)==false then done(); return end
            else ownerIndex=ownerIndex+1; records=nil; budget=budget-1 end
        end
        if ownerIndex>#owners then done()
        elseif C_Timer and C_Timer.After then C_Timer.After(0,step) else return step() end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0,step) else step() end
end
local function ensureRecipeIndex()
    if indexedRevision==indexRevision or indexJob then return end
    local job={revision=indexRevision}; indexJob=job
    local summaries,seen,items={},{},{}
    scanCachedRecords(function(name,r)
        if validRecord(r) then
            local summary=summaries[r.profession] or {recipes=0,members=0}; summaries[r.profession]=summary
            local id=r.profession..':'..r.recipe
            if not seen[id] then seen[id]=true; summary.recipes=summary.recipes+1 end
            local who=r.profession..':'..name
            if not seen[who] then seen[who]=true; summary.members=summary.members+1 end
            if r.item>0 then
                local owners=items[r.item] or {}; items[r.item]=owners
                owners[name]=math.max(owners[name] or 0,r.seen)
            end
        end
    end,function()
        summaryCache,itemIndex=summaries,items; indexedRevision=job.revision; indexJob=nil
        OldKraken:Fire('WORKSHOP_INDEX_CHANGED')
    end,function() return indexJob==job end)
end
local function addCached(query,filter,professionFilter)
    resultQuery=query
    resultSet={}
    local limit=query:match('^prof:%d+$') and 5000 or 500
    local found=0
    local job={}; searchJob=job
    scanCachedRecords(function(name,r)
        if found>=limit then return false end
        resolveProduct(r)
        if matches(r,query) and (not professionFilter or professionFilter==0 or r.profession==professionFilter) then
            if (not filter or matchesFilter(r,filter)) and (not selectRecipe or (OldKraken.WorkshopOrders and OldKraken.WorkshopOrders:SupportsProfession(r.profession))) then
                local key=name..'\001'..r.recipe
                if not resultSet[key] then found=found+1 end
                resultSet[key]={owner=name,record=r}
            end
        end
    end,function() changed() end,function() return searchJob==job end)
end
local function search(value)
    if not active or not safeText(value,1,200) then print('Old Kraken: введіть назву або посилання на предмет.'); return false end
    local item=value:match('item:(%d+)')
    local q=item and ('item:'..item) or lower(value:match('^%s*(.-)%s*$'))
    if not safeText(q,3,80) then print('Old Kraken: введіть назву або посилання на предмет.'); return false end
    local now=GetTime()
    offset=0; addCached(q,nil,selectRecipe and pickerProfession or nil)
    if now-lastQuery<10 then
        if activeQuery and activeQuery.query~=q then activeQuery=nil end
        changed(); print('Old Kraken: показано збережені результати; повторіть запит гільдії через кілька секунд.'); return false
    end
    sequence=sequence+1
    local token=tostring(GetServerTime())..'-'..tostring(math.random(100000,999999))..'-'..sequence
    if not comm:SendProtocol('WRQUERY',codec._pack({token,q})) then activeQuery=nil; changed(); print('Old Kraken: показано збережені результати; запит гільдії надіслати не вдалося.'); return false end
    lastQuery=now; activeQuery={token=token,query=q,untilTime=now+(q:match('^prof:%d+$') and 600 or 120)}; changed(); return true
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
    if f[2]:match('^prof:%d+$') then
        local batch={sender,f[1]}; local n=0
        local function flush()
            if n==0 or #sendQueue>=100 then return false end
            sendQueue[#sendQueue+1]={kind='WRBATCH',payload=codec._pack(batch),expires=now+600}; batch={sender,f[1]}; n=0; return true
        end
        for _,r in ipairs(found) do
            local fields={r.recipe,r.item,r.profession,r.seen,r.name,r.product}
            local candidate={unpack(batch)}; for _,value in ipairs(fields) do candidate[#candidate+1]=value end
            if n>=16 or #codec._pack(candidate)>2300 then
                if not flush() then break end
                candidate={sender,f[1]}; for _,value in ipairs(fields) do candidate[#candidate+1]=value end
            end
            batch=candidate; n=n+1
        end
        flush(); return
    end
    for i=1,math.min(#found,12) do
        if #sendQueue>=100 then break end
        local r=found[i]; local msg=codec._pack({sender,f[1],r.recipe,r.item,r.profession,r.seen,r.name,r.product})
        sendQueue[#sendQueue+1]={payload=msg,expires=now+120}
    end
end)
comm:RegisterHandler('WRBATCH',function(sender,_,payload)
    if not active or not activeQuery or GetTime()>activeQuery.untilTime or not safeText(sender,1,128) or sender==identity then return end
    local f=codec._unpackFields(payload,98)
    if not f or #f<8 or (#f-2)%6~=0 or #f>98 or f[1]~=identity or f[2]~=activeQuery.token or not activeQuery.query:match('^prof:%d+$') then return end
    if type(people[sender])~='table' then if count(people)>=1000 then return end; people[sender]={} end
    local updated=false; local cachedCount=count(people[sender]); local resultCount=count(resultSet)
    for i=3,#f,6 do
        local r={recipe=tonumber(f[i]),item=tonumber(f[i+1]),profession=tonumber(f[i+2]),seen=tonumber(f[i+3]),name=f[i+4],product=f[i+5]}
        if matches(r,activeQuery.query) and (people[sender][r.recipe] or cachedCount<5000) then
            local old=people[sender][r.recipe]
            if not old then cachedCount=cachedCount+1 end
            local stored=storeRecipe(sender,r,false)
            if stored then
                local k=sender..'\001'..r.recipe
                if resultSet[k] or resultCount<5000 then if not resultSet[k] then resultCount=resultCount+1 end; resultSet[k]={owner=sender,record=stored} end
                updated=true
            end
        end
    end
    if updated then changed(); indexRevision=indexRevision+1; recipeChanged=true end
end)
comm:RegisterHandler('WRRESULT',function(sender,_,payload)
    if not active or not activeQuery or GetTime()>activeQuery.untilTime or not safeText(sender,1,128) then return end
    local f=codec._unpackFields(payload,8)
    if not f or #f~=8 or f[1]~=identity or f[2]~=activeQuery.token then return end
    local r={recipe=tonumber(f[3]),item=tonumber(f[4]),profession=tonumber(f[5]),seen=tonumber(f[6]),name=f[7],product=f[8]}
    if not matches(r,activeQuery.query) then return end
    if type(people[sender])~='table' then if count(people)>=1000 then return end; people[sender]={} end
    if not people[sender][r.recipe] and count(people[sender])>=5000 then return end
    local stored=storeRecipe(sender,r,false); if not stored then return end
    local k=sender..'\001'..r.recipe
    if resultSet[k] or count(resultSet)<500 then resultSet[k]={owner=sender,record=stored} end
    changed(); indexRevision=indexRevision+1; recipeChanged=true
end)
comm:RegisterHandler('WRLEARN',function(sender,_,payload)
    if not active or not safeText(sender,1,128) or sender==identity then return end
    local f=codec._unpackFields(payload,6); if not f or #f~=6 then return end
    local r={recipe=tonumber(f[1]),item=tonumber(f[2]),profession=tonumber(f[3]),seen=tonumber(f[4]),name=f[5],product=f[6]}
    if not validRecord(r) then return end
    if type(people[sender])~='table' then if count(people)>=1000 then return end; people[sender]={} end
    if not people[sender][r.recipe] and count(people[sender])>=5000 then return end
    local old=people[sender][r.recipe]
    local sources=scope.recipeSources[sender]
    if validRecord(old) and old.seen>=r.seen and not (type(sources)=='table' and sources[r.recipe]) then return end
    local stored=storeRecipe(sender,r,false); if not stored then return end
    if activeQuery and GetTime()<=activeQuery.untilTime then
        local k=sender..'\001'..r.recipe
        if matches(stored,activeQuery.query) and (resultSet[k] or count(resultSet)<500) then resultSet[k]={owner=sender,record=stored}
        elseif resultSet[k] then resultSet[k]=nil end
    end
    changed(); indexRevision=indexRevision+1; recipeChanged=true
end)
comm:RegisterHandler('WRFORGET',function(sender,_,payload)
    if not active or not safeText(sender,1,128) or sender==identity then return end
    local f=codec._unpackFields(payload,6); if not f or #f~=6 then return end
    local r={recipe=tonumber(f[1]),item=tonumber(f[2]),profession=tonumber(f[3]),seen=tonumber(f[4]),name=f[5],product=f[6],deleted=true}
    if validRecord(r) and storeTombstone(sender,r,false) then changed(); indexRevision=indexRevision+1; recipeChanged=true end
end)

local events=CreateFrame('Frame')
for _,event in ipairs({'PLAYER_LOGIN','PLAYER_GUILD_UPDATE','GUILD_ROSTER_UPDATE','TRADE_SKILL_SHOW','TRADE_SKILL_LIST_UPDATE','TRADE_SKILL_DATA_SOURCE_CHANGED','TRADE_SKILL_CLOSE','NEW_RECIPE_LEARNED','SPELLS_CHANGED','SKILL_LINES_CHANGED','LEARNED_SPELL_IN_SKILL_LINE'}) do pcall(events.RegisterEvent,events,event) end
events:SetScript('OnEvent',function(_,event,recipeID)
    if event=='PLAYER_LOGIN' or event=='PLAYER_GUILD_UPDATE' or event=='GUILD_ROSTER_UPDATE' then connect()
    elseif event=='NEW_RECIPE_LEARNED' then
        connect()
        if active and integer(recipeID,1,100000000) and (pendingLearned[recipeID] or count(pendingLearned)<1000) then
            pendingLearned[recipeID]=true; learnAttempts[recipeID]=0
            if tradeOpen then scanPending=true end
        end
    elseif event=='SPELLS_CHANGED' or event=='LEARNED_SPELL_IN_SKILL_LINE' then catalogCursor=nil; catalogPending=true; if tradeOpen then scanPending=true end
    elseif event=='TRADE_SKILL_CLOSE' then tradeOpen=false; scanPending=false; forgetChecks={}; lastScanProfession=nil
    elseif event=='TRADE_SKILL_SHOW' then tradeOpen=true; scanPending=true; learnAttempts={}
    elseif tradeOpen then scanPending=true end
end)
if C_Timer and type(C_Timer.NewTicker)=='function' then C_Timer.NewTicker(3,function()
    connect(); if not active then return end
    if scanPending then
        scanPending=false
        local ok,completed=pcall(scan)
        if not ok or not completed then
            forgetChecks={}; lastScanProfession=nil
            scanStatus='Не вдалося зчитати власну професію. Відкрийте її та перевірте доступність API.'
            if frame and frame:IsShown() then frame.status:SetText(scanStatus) end
        end
    end
    if catalogPending and recipeCatalog then
        local known=type(IsPlayerSpell)=='function' and IsPlayerSpell or (type(C_SpellBook)=='table' and type(C_SpellBook.IsSpellKnown)=='function' and C_SpellBook.IsSpellKnown)
        if known then
            local profs={}
            for _=1,50 do
                local id,r=next(recipeCatalog,catalogCursor); catalogCursor=id
                if not id then catalogPending=false; break end
                -- The spell book alone can report known non-recipe spells; it
                -- must not reverse a confirmed recipe removal.
                if validRecord(r) and not people[identity][r.recipe] and not scope.recipeTombstones[identity][r.recipe] then
                    if profs[r.profession]==nil then profs[r.profession]=playerHasProfession(r.profession) end
                    if profs[r.profession] then
                        local ok,value=pcall(known,r.recipe)
                        if ok and usable(value,'boolean') and value then
                            recordLearned({recipe=r.recipe,item=r.item,profession=r.profession,seen=GetServerTime(),name=r.name,product=r.product})
                        end
                    end
                end
            end
        else catalogPending=false end
    end
    for id in pairs(pendingLearned) do
        if not integer(id,1,100000000) then pendingLearned[id]=nil
        elseif (learnAttempts[id] or 0)<10 then
            local ok,done=pcall(scanLearned,id)
            if not ok or not done or pendingLearned[id] then
                learnAttempts[id]=(learnAttempts[id] or 0)+1
                if learnAttempts[id]==10 then print('Old Kraken: новий рецепт очікує даних гри. Відкрийте відповідну професію, щоб завершити оновлення.') end
            end
            break
        end
    end
    while #sendQueue>0 and sendQueue[1].expires<GetTime() do table.remove(sendQueue,1) end
    if #sendQueue>0 and #comm.queue<=8 and comm:SendProtocol(sendQueue[1].kind or 'WRRESULT',sendQueue[1].payload) then table.remove(sendQueue,1) end
    if recipeChanged then recipeChanged=false; OldKraken:Fire('WORKSHOP_RECIPES_CHANGED') end
end) end

local function button(parent,label,x,y,width,callback,variant,options)
    local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate'); OldKraken.UIStyle.Button(b,variant,options)
    b:SetSize(width,(options and options.height) or 28); b:SetPoint('TOPLEFT',parent,'TOPLEFT',x,y); b:SetText(label); b:SetScript('OnClick',callback); return b
end
local function onlineIndex()
    local result,classes={},{}
    if type(UnitClass)=='function' and identity then
        local ok,_,class=pcall(UnitClass,'player')
        if ok and usable(class,'string') then classes[identity]=class end
    end
    if type(GetNumGuildMembers)~='function' or type(GetGuildRosterInfo)~='function' then return result,classes end
    local ok,n=pcall(GetNumGuildMembers); if not ok or not integer(n,0,10000) then return result,classes end
    for i=1,n do
        local success,name,_,_,_,_,_,_,_,online,_,class=pcall(GetGuildRosterInfo,i)
        if success and usable(name,'string') then
            if usable(online,'boolean') then result[name]=online end
            if usable(class,'string') then classes[name]=class end
        end
    end
    return result,classes
end
local function playerLabel(name,classes)
    local class=classes[name]
    local color=type(RAID_CLASS_COLORS)=='table' and class and RAID_CLASS_COLORS[class]
    if usable(color,'table') and usable(color.r,'number') and usable(color.g,'number') and usable(color.b,'number')
        and color.r>=0 and color.r<=1 and color.g>=0 and color.g<=1 and color.b>=0 and color.b<=1 then
        return string.format('|cff%02x%02x%02x%s|r',math.floor(color.r*255),math.floor(color.g*255),math.floor(color.b*255),name)
    end
    return '|cffffffff'..name..'|r'
end
local function statusLabel(name,online)
    if name==identity or online[name]==true then return '|cff4cde80онлайн|r' end
    if online[name]==false then return '|cff999999офлайн|r' end
    return '|cff999999невідомо|r'
end
function Recipes:GetRosterPresentation() return onlineIndex() end
function Recipes:FormatPlayerName(name,classes) return playerLabel(name,classes or {}) end
function Recipes:FormatOnlineStatus(name,online) return statusLabel(name,online or {}) end
local bopCache={}
local function isBindOnPickup(r)
    local id=r and r.item or 0
    if id<=0 then return false end
    local cached=bopCache[id]
    if cached~=nil then return cached end
    if type(GetItemInfo)=='function' then
        local ok,_,_,_,_,_,_,_,_,_,_,_,_,_,bindType=pcall(GetItemInfo,id)
        if ok and type(bindType)=='number' then
            cached=bindType==1
            bopCache[id]=cached
            return cached
        end
    end
    return false
end
local function recipeIcon(r)
    local getIcon=type(C_Item)=='table' and C_Item.GetItemIconByID or GetItemIcon
    if r.item>0 and type(getIcon)=='function' then
        local ok,icon=pcall(getIcon,r.item); if ok and (usable(icon,'number') or usable(icon,'string')) then return icon end
    end
    if type(C_Spell)=='table' and type(C_Spell.GetSpellTexture)=='function' then
        local ok,icon=pcall(C_Spell.GetSpellTexture,r.recipe); if ok and (usable(icon,'number') or usable(icon,'string')) then return icon end
    end
    return 134400
end
local requestedItems,pendingItems={},{}
function Recipes:ItemLabel(id)
    local name,icon
    if C_Item and type(C_Item.GetItemNameByID)=='function' then
        local ok,value=pcall(C_Item.GetItemNameByID,id); if ok and safeText(value,1,160) then name=value end
    end
    if not name and type(GetItemInfo)=='function' then
        local ok,value=pcall(GetItemInfo,id); if ok and safeText(value,1,160) then name=value end
    end
    local getIcon=C_Item and C_Item.GetItemIconByID or GetItemIcon
    if type(getIcon)=='function' then local ok,value=pcall(getIcon,id); if ok and (usable(value,'number') or usable(value,'string')) then icon=value end end
    if not name then
        pendingItems[id]=true
        local now=GetTime()
        if not requestedItems[id] or now-requestedItems[id]>=5 then
            requestedItems[id]=now
            if C_Item and type(C_Item.RequestLoadItemDataByID)=='function' then pcall(C_Item.RequestLoadItemDataByID,id) end
        end
    end
    return '|T'..tostring(icon or 134400)..':22:22:0:0|t |cffffffff'..(name or 'Завантаження назви…')..'|r'
end
local itemEvents=CreateFrame('Frame')
for _,event in ipairs({'GET_ITEM_INFO_RECEIVED','ITEM_DATA_LOAD_RESULT'}) do pcall(itemEvents.RegisterEvent,itemEvents,event) end
itemEvents:SetScript('OnEvent',function(_,_,id,success)
    if pendingItems[id] and success~=false then
        pendingItems[id]=nil; changed()
        OldKraken:Fire('WORKSHOP_ITEM_DATA_CHANGED')
    end
end)
local function showItemTooltip(anchor,itemID,recipeID)
    if not GameTooltip then return end
    GameTooltip:SetOwner(anchor,'ANCHOR_RIGHT')
    local shown=false
    if (itemID or 0)>0 then
        if type(GameTooltip.SetItemByID)=='function' then shown=pcall(GameTooltip.SetItemByID,GameTooltip,itemID) end
        if not shown and type(GameTooltip.SetHyperlink)=='function' then shown=pcall(GameTooltip.SetHyperlink,GameTooltip,'item:'..itemID) end
    elseif (recipeID or 0)>0 then
        if type(GameTooltip.SetSpellByID)=='function' then shown=pcall(GameTooltip.SetSpellByID,GameTooltip,recipeID) end
        if not shown and type(GameTooltip.SetHyperlink)=='function' then shown=pcall(GameTooltip.SetHyperlink,GameTooltip,'spell:'..recipeID) end
    end
    if shown then GameTooltip:Show() else GameTooltip:Hide() end
end
local function reagentEntries(r)
    if type(C_TradeSkillUI)~='table' or type(C_TradeSkillUI.GetRecipeSchematic)~='function' then return 'Матеріали: дані гри недоступні.',{} end
    local ok,schematic=pcall(C_TradeSkillUI.GetRecipeSchematic,r.recipe,false)
    if not ok or not usable(schematic,'table') or not usable(schematic.reagentSlotSchematics,'table') then return 'Матеріали: гра не надала даних для цього рецепта.',{} end
    local items={}
    for _,slot in ipairs(schematic.reagentSlotSchematics) do
        if #items>=8 then items[#items+1]={text='…'}; break end
        if usable(slot,'table') and usable(slot.reagents,'table') then
            local reagent=slot.reagents[1]; local id=usable(reagent,'table') and reagent.itemID
            if integer(id,1,100000000) then
                local amount=integer(slot.quantityRequired,1,10000) and slot.quantityRequired or 1
                local getCount=type(C_Item)=='table' and C_Item.GetItemCount or GetItemCount
                local countText=''; if type(getCount)=='function' then local got,value=pcall(getCount,id); if got and integer(value,0,10000000) then countText=' · у сумках: '..value end end
                items[#items+1]={id=id,text=Recipes:ItemLabel(id)..' |cffffd36b×'..amount..'|r'..countText}
            end
        end
    end
    if #items==0 then return 'Матеріали: гра не надала даних для цього рецепта.',{} end
    return 'Матеріали:',items
end
local function resizeInfo()
    if frame and frame.infoContent then
        local rowsHeight=0
        for _,row in ipairs(frame.reagentRows or {}) do if row:IsShown() then rowsHeight=rowsHeight+26 end end
        local reagents=frame.embedded and (frame.detailReagents:GetStringHeight()+rowsHeight+24) or 0
        frame.infoContent:SetHeight(math.max(frame.embedded and 262 or 110,frame.detailInfo:GetStringHeight()+reagents+8))
    end
end
render=function()
    if not frame or not frame:IsShown() then return end
    local online,classes=onlineIndex(); local list={}; local grouped={}
    local mastersView=tab=='masters' and not selectRecipe
    local function hideReagentRows()
        for _,row in ipairs(frame.reagentRows or {}) do row.itemID=nil; row:Hide() end
    end
    local filter=textFilter(frame.query:GetText())
    if frame.queryHint then
        frame.queryHint:SetText(mastersView and 'Пошук майстра за ім’ям' or 'Пошук рецепта або предмета')
        frame.queryHint:SetShown((frame.query:GetText() or '') == '')
    end
    if frame.TitleText then frame.TitleText:SetText(professionContext and ('Old Kraken — '..professionNames[professionContext]) or 'Old Kraken — Пошук рецептів') end
    frame.searchLabel:SetText(selectRecipe and 'Фільтр за професією' or (mastersView and 'Пошук майстра за ім’ям' or 'Пошук рецепта або предмета'))
    frame.searchLabel:SetShown(not frame.embedded)
    if professionContext then
        frame.status:SetText(viewOwner and ('Рецепти майстра: '..viewOwner..' · дані можуть бути неповними.') or 'Дані можуть бути неповними або застарілими.')
    end
    frame.recipeTab:SetShown(not frame.embedded and professionContext~=nil and not selectRecipe)
    frame.masterTab:SetShown(not frame.embedded and professionContext~=nil and not selectRecipe)
    frame.recipeTab.activeBar:SetShown(not frame.embedded and professionContext~=nil and tab=='recipes' and not selectRecipe)
    frame.masterTab.activeBar:SetShown(not frame.embedded and professionContext~=nil and tab=='masters' and not selectRecipe)
    if frame.embedded and OldKraken.Workshop then OldKraken.Workshop:UpdateTabs() end
    if frame.embedded then frame.context:SetText(selectRecipe and 'Оберіть рецепт для замовлення' or (professionContext and professionNames[professionContext] or (mastersView and 'Усі професії' or 'Усі рецепти'))) end
    frame.masterRecipes:SetShown(mastersView and selectedMaster~=nil)
    frame.cancelPick:SetShown(selectRecipe~=nil)
    frame.pickProfession:SetShown(selectRecipe~=nil)
    frame.onlineOnly:SetShown(mastersView and true or false)
    if mastersView then
        if frame.onlineOnly.SetActive then
            frame.onlineOnly:SetActive(mastersOnline)
            if frame.onlineOnly.SetDotColor then frame.onlineOnly:SetDotColor(mastersOnline and 'success' or 'neutral') end
            frame.onlineOnly:SetText(mastersOnline and 'Лише онлайн: так' or 'Лише онлайн: ні')
        else
            frame.onlineOnly:SetText(mastersOnline and 'Лише онлайн: так' or 'Лише онлайн: ні')
        end
        local masters={}
        local workshop=OldKraken.Workshop
        if workshop then
            for id in pairs(professionNames) do
                local isGathering=workshop.IsGatheringProfession and workshop:IsGatheringProfession(id)
                if (not professionContext and not isGathering) or professionContext==id then
                    for _,entry in ipairs(workshop:GetProfessionMasters(id)) do entry.profession=id; masters[#masters+1]=entry end
                end
            end
        end
        for _,entry in ipairs(masters) do
            if (not viewOwner or entry.name==viewOwner) and (not mastersOnline or entry.name==identity or online[entry.name]==true)
                and (filter=='' or lower(entry.name):find(filter,1,true)) then list[#list+1]=entry end
        end
        table.sort(list,function(a,b)
            local aOnline=a.name==identity or online[a.name]==true; local bOnline=b.name==identity or online[b.name]==true
            if aOnline~=bOnline then return aOnline end
            if a.name~=b.name then return a.name<b.name end
            return (professionNames[a.profession] or '')<(professionNames[b.profession] or '')
        end)
        offset=math.max(0,math.min(offset,math.max(0,math.ceil(#list/PAGE_SIZE)-1)))
        frame.page:SetText((offset+1)..' / '..math.max(1,math.ceil(#list/PAGE_SIZE)))
        frame.count:SetText('Майстрів: '..#list..' · рівень і дата за останніми доступними даними')
        for i,row in ipairs(rows) do
            local entry=list[offset*PAGE_SIZE+i]
            if entry then
                local _,icon=OldKraken.Workshop:ProfessionInfo(entry.profession)
                row.entry=entry; row.icon:SetTexture(icon); row.name:SetText(playerLabel(entry.name,classes))
                local level=entry.rank and entry.maximum and (entry.rank..'/'..entry.maximum) or 'рівень невідомий'
                local state=statusLabel(entry.name,online)
                local dated=integer(entry.timestamp,1,GetServerTime()+600)
                local stale=dated and GetServerTime()-entry.timestamp>604800
                row.meta:SetText((professionContext and '' or professionNames[entry.profession]..' · ')..(stale and '|cffffb347застаріло|r · ' or (not dated and 'дата невідома · ' or ''))..level..' · '..state..(entry.relayed and ' · через гільдію' or ''))
                if OldKraken.UIStyle.ApplySelection then
                    OldKraken.UIStyle.ApplySelection(row, selectedMaster and selectedMaster.name==entry.name and selectedMaster.profession==entry.profession)
                    row:UnlockHighlight()
                elseif selectedMaster and selectedMaster.name==entry.name and selectedMaster.profession==entry.profession then row:LockHighlight() else row:UnlockHighlight() end
                row:Show()
            else row.entry=nil; row:UnlockHighlight(); row:Hide() end
        end
        frame.detailIcon:SetShown(selectedMaster~=nil); frame.order:Hide()
        frame.whisper:SetShown(selectedMaster~=nil and selectedMaster.name~=identity and online[selectedMaster.name]==true)
        if selectedMaster then
            local _,icon=OldKraken.Workshop:ProfessionInfo(selectedMaster.profession)
            frame.detailIcon:SetTexture(icon); frame.detailTitle:SetText(playerLabel(selectedMaster.name,classes))
            local level=selectedMaster.rank and selectedMaster.maximum and (selectedMaster.rank..'/'..selectedMaster.maximum) or 'невідомий'
            local state=statusLabel(selectedMaster.name,online)
            local dated=integer(selectedMaster.timestamp,1,GetServerTime()+600)
            local updated=dated and (date('%d.%m.%Y %H:%M',selectedMaster.timestamp)..(GetServerTime()-selectedMaster.timestamp>604800 and ' · |cffffb347застаріло|r' or '')) or 'невідомо'
            frame.detailInfo:SetText(professionNames[selectedMaster.profession]..'\nРівень: '..level..'\nСтатус: '..state..'\nОновлено: '..updated..(selectedMaster.relayed and '\nОтримано через гільдію' or ''))
            frame.detailReagents:SetText(''); hideReagentRows()
        else
            frame.detailTitle:SetText('Оберіть майстра'); frame.detailInfo:SetText('Виберіть майстра зі списку.'); frame.detailReagents:SetText(''); hideReagentRows()
        end
        resizeInfo(); return
    end
    local list,grouped,groupCounts,groupOnline={},{},{},{}
    local byRecipe=not selectRecipe and not viewOwner and not (filter and (filter:find('^item:') or filter:find('^recipe:')))
    for _,entry in pairs(resultSet) do
        if validRecord(entry.record) and (not viewOwner or entry.owner==viewOwner) and (not professionContext or entry.record.profession==professionContext)
            and (not selectRecipe or ((pickerProfession==0 or entry.record.profession==pickerProfession) and OldKraken.WorkshopOrders and OldKraken.WorkshopOrders:SupportsProfession(entry.record.profession)))
            and not isBindOnPickup(entry.record)
            and matchesFilter(entry.record,filter) then
            if byRecipe then
                local id=entry.record.recipe; local old=grouped[id]
                groupCounts[id]=(groupCounts[id] or 0)+1
                if online[entry.owner] then groupOnline[id]=(groupOnline[id] or 0)+1 end
                local other=entry.owner~=identity
                local oldOther=old and old.owner~=identity
                if not old or (other and not oldOther) or (other==oldOther and ((online[entry.owner] and not online[old.owner]) or ((online[entry.owner] and true or false)==(online[old.owner] and true or false) and entry.record.seen>old.record.seen))) then grouped[id]=entry end
            else list[#list+1]=entry end
        end
    end
    if byRecipe then for _,entry in pairs(grouped) do list[#list+1]=entry end end
    table.sort(list,function(a,b) local an,bn=displayRecipeName(a.record),displayRecipeName(b.record); if an~=bn then return an<bn end return a.owner<b.owner end)
    offset=math.max(0,math.min(offset,math.max(0,math.ceil(#list/PAGE_SIZE)-1)))
    frame.page:SetText((offset+1)..' / '..math.max(1,math.ceil(#list/PAGE_SIZE)))
    frame.count:SetText('Знайдено: '..#list..' · результати можуть бути застарілими або неповними')
    for i,row in ipairs(rows) do
        local entry=list[offset*PAGE_SIZE+i]
        if entry then
            local r=entry.record; row.entry=entry
            row.icon:SetTexture(recipeIcon(r))
            row.name:SetText(displayRecipeName(r))
            local totalMasters=byRecipe and (groupCounts[r.recipe] or 1) or 1
            if byRecipe and totalMasters>1 then
                local onCount=groupOnline[r.recipe] or 0
                local onText=onCount>0 and ('|cff68d98c'..onCount..' онлайн|r') or '|cff9ba9bcофлайн|r'
                local mWord=OldKraken.Workshop and OldKraken.Workshop.PluralUk and OldKraken.Workshop:PluralUk(totalMasters,'майстер','майстри','майстрів') or 'майстрів'
                row.meta:SetText(professionNames[r.profession]..' · '..totalMasters..' '..mWord..' · '..onText)
            else
                row.meta:SetText((selectRecipe and entry.owner==identity and '|cffffb347Ваш рецепт|r · ' or '')..(GetServerTime()-r.seen>604800 and '|cffffb347застаріло|r · ' or '')..playerLabel(entry.owner,classes)..' · '..professionNames[r.profession]..' · '..statusLabel(entry.owner,online))
            end
            if OldKraken.UIStyle.ApplySelection then
                OldKraken.UIStyle.ApplySelection(row, selectedEntry and selectedEntry.owner==entry.owner and selectedEntry.record.recipe==r.recipe)
                row:UnlockHighlight()
            elseif selectedEntry and selectedEntry.owner==entry.owner and selectedEntry.record.recipe==r.recipe then row:LockHighlight() else row:UnlockHighlight() end
            row:Show()
        else row.entry=nil; row:UnlockHighlight(); row:Hide() end
    end
    local entry=selectedEntry; local r=entry and entry.record
    frame.detailIcon:SetShown(r~=nil); frame.whisper:SetShown(r~=nil and entry.owner~=identity)
    frame.order:SetShown(r~=nil and entry.owner~=identity and OldKraken.WorkshopOrders and OldKraken.WorkshopOrders:SupportsProfession(r.profession) or false)
    if r then
        frame.detailIcon:SetTexture(recipeIcon(r))
        frame.detailTitle:SetText(displayRecipeName(r))
        local masters=Recipes:FindMasters(r.item,r.recipe); local names={}
        table.sort(masters,function(a,b) if (online[a.name] and true or false)~=(online[b.name] and true or false) then return online[a.name] and true or false end return a.name<b.name end)
        for i=1,math.min(#masters,8) do local m=masters[i]; names[#names+1]=playerLabel(m.name,classes)..' · '..statusLabel(m.name,online)..(GetServerTime()-m.seen>604800 and ' · |cffffb347застаріло|r' or '') end
        frame.detailInfo:SetText(professionNames[r.profession]..'\nЗбережено: '..date('%d.%m.%Y',r.seen)..(GetServerTime()-r.seen>604800 and ' · застаріло' or '')..'\n\nМайстри: '..#masters..'\n'..(#names>0 and table.concat(names,'\n') or 'Немає даних')..(#masters>8 and '\n…' or '')..(entry.owner==identity and '\n\nЦе ваш рецепт. Оберіть рецепт іншого майстра, щоб створити замовлення.' or ''))
        local header,items=reagentEntries(r)
        frame.detailReagents:SetText(header)
        for i,row in ipairs(frame.reagentRows or {}) do
            local item=items[i]
            if item then row.itemID=item.id; row.label:SetText(item.text); row:Show()
            else row.itemID=nil; row:Hide() end
        end
    else
        frame.detailTitle:SetText('Оберіть рецепт'); frame.detailInfo:SetText('Перегляньте збережені рецепти або знайдіть предмет.'); frame.detailReagents:SetText(''); hideReagentRows()
    end
    resizeInfo()
end
local function switchTab(nextTab)
    if tab==nextTab then return end
    local key=professionContext or 0
    local states=tabStates[key] or {}; tabStates[key]=states
    states[tab]={query=frame.query:GetText() or '',offset=offset,owner=viewOwner,
        selected=selectedEntry,master=selectedMaster,online=mastersOnline}
    local saved=states[nextTab] or {}
    tab=nextTab
    viewOwner,selectedEntry,selectedMaster=saved.owner,saved.selected,saved.master
    offset,mastersOnline=saved.offset or 0,saved.online==true
    if selectedEntry then
        local stored=people[selectedEntry.owner] and people[selectedEntry.owner][selectedEntry.record.recipe]
        selectedEntry=validRecord(stored) and {owner=selectedEntry.owner,record=stored} or nil
    end
    if selectedMaster and OldKraken.Workshop then
        local name,profession=selectedMaster.name,selectedMaster.profession or professionContext
        selectedMaster=nil
        for _,master in ipairs(OldKraken.Workshop:GetProfessionMasters(profession)) do
            if master.name==name then master.profession=profession; selectedMaster=master; break end
        end
    end
    restoringView=true; frame.query:SetText(saved.query or ''); restoringView=false
    if nextTab=='recipes' and not professionContext then addCached('',textFilter(saved.query)) end
    render()
end
local function readableFont(text,size,spacing)
    local font = OldKraken.UIStyle and OldKraken.UIStyle.FontPath and OldKraken.UIStyle.FontPath() or text:GetFont()
    if font then text:SetFont(font,size,'OUTLINE') end
    text:SetShadowColor(0,0,0,1); text:SetShadowOffset(1,-1)
    if spacing then text:SetSpacing(spacing) end
end
local function createWindow(parent)
    local f
    if parent then
        f=CreateFrame('Frame','OldKrakenWorkshopRecipesFrame',parent)
        f:SetSize(900,542); f:SetPoint('TOPLEFT',parent,'TOPLEFT',0,-65)
    else
        f=CreateFrame('Frame','OldKrakenWorkshopRecipesFrame',UIParent,'BasicFrameTemplateWithInset')
        table.insert(UISpecialFrames,'OldKrakenWorkshopRecipesFrame'); f:SetSize(750,470); f:SetPoint('CENTER'); f:SetMovable(true); f:SetClampedToScreen(true)
        f:RegisterForDrag('LeftButton'); f:SetScript('OnDragStart',f.StartMoving); f:SetScript('OnDragStop',f.StopMovingOrSizing); OldKraken.UIStyle.Window(f)
    end
    f.embedded=parent~=nil
    f:EnableMouse(true)
    if f.TitleText then f.TitleText:SetText('Old Kraken — Пошук рецептів') end
    local colors = OldKraken.UIStyle.Colors or {}
    if parent then
        if OldKraken.UIStyle.PanelFrame then
            f.filterPanel = OldKraken.UIStyle.PanelFrame(f, 'buttonEdge')
            f.filterPanel:SetSize(900, 52)
            f.filterPanel:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, -52)
            f.detailPanel = OldKraken.UIStyle.PanelFrame(f, 'buttonEdge')
            f.detailPanel:SetSize(402, 398)
            f.detailPanel:SetPoint('TOPLEFT', f, 'TOPLEFT', 498, -126)
        end
        f.context=f:CreateFontString(nil,'OVERLAY','GameFontNormal')
        f.context:SetPoint('TOPLEFT',f,'TOPLEFT',0,-30)
        if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(f.context, 14, true) end
        if colors.brandGold then f.context:SetTextColor(colors.brandGold[1], colors.brandGold[2], colors.brandGold[3]) end
    end
    f.recipeTab=button(f,'Рецепти',20,-38,120,function() switchTab('recipes') end)
    f.masterTab=button(f,'Майстри',148,-38,120,function() switchTab('masters') end)
    for _,item in ipairs({f.recipeTab,f.masterTab}) do
        item.activeBar=item:CreateTexture(nil,'ARTWORK'); item.activeBar:SetPoint('BOTTOMLEFT',item,'BOTTOMLEFT',2,1); item.activeBar:SetSize(116,2)
        item.activeBar:SetColorTexture(unpack(OldKraken.UIStyle.Colors.brandGold))
    end
    f.query=CreateFrame('EditBox',nil,f,'InputBoxTemplate'); OldKraken.UIStyle.Input(f.query)
    f.query:SetSize(300,34); f.query:SetPoint('TOPLEFT',f,'TOPLEFT',24,-74); f.query:SetAutoFocus(false); f.query:SetTextInsets(8,8,0,0)
    f.query:SetText('')
    f.queryHint=f.query:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    f.queryHint:SetPoint('LEFT',f.query,'LEFT',10,0); f.queryHint:SetText('Пошук рецепта або предмета')
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(f.queryHint, 13) end
    if colors.mutedText then f.queryHint:SetTextColor(colors.mutedText[1], colors.mutedText[2], colors.mutedText[3]) end
    f.searchLabel=f:CreateFontString(nil,'OVERLAY','GameFontHighlight'); f.searchLabel:SetPoint('TOPLEFT',f,'TOPLEFT',455,-49)
    f.query:SetScript('OnTextChanged',function(self)
        if f.queryHint then f.queryHint:SetShown((self:GetText() or '')=='') end
        if restoringView then return end
        selectedEntry=nil; selectedMaster=nil; offset=0
        if tab~='masters' and not professionContext then addCached('',textFilter(f.query:GetText()),selectRecipe and pickerProfession or nil) end
        render()
    end)
    f.query:SetScript('OnEscapePressed',function(self) self:ClearFocus() end)
    local function submitSearch()
        if professionContext or tab=='masters' then offset=0; render(); f.query:ClearFocus(); return end
        selectedEntry=nil; viewOwner=nil; if search(f.query:GetText() or '') then f.query:ClearFocus() end
    end
    f.query:SetScript('OnEnterPressed',submitSearch)
    f.searchButton=button(f,'Знайти',335,-74,105,submitSearch,'primary',{rounded=true,height=34})
    if OldKraken.UIStyle.Chip then
        f.onlineOnly = OldKraken.UIStyle.Chip(f, 'Лише онлайн: ні', {dot = 'success', width = 170, height = 34, rounded = true})
        f.onlineOnly:SetPoint('TOPLEFT', f, 'TOPLEFT', 455, -74)
        f.onlineOnly:SetScript('OnClick', function() mastersOnline=not mastersOnline; selectedMaster=nil; offset=0; render() end)
    else
        f.onlineOnly=button(f,'Лише онлайн: ні',455,-74,160,function() mastersOnline=not mastersOnline; selectedMaster=nil; offset=0; render() end,nil,{rounded=true,height=34})
    end
    f.pickProfession=CreateFrame('Frame','OldKrakenRecipePickerProfession',f,'UIDropDownMenuTemplate'); OldKraken.UIStyle.Dropdown(f.pickProfession,{rounded=true})
    f.pickProfession:SetPoint('TOPLEFT',f,'TOPLEFT',439,-71); UIDropDownMenu_SetWidth(f.pickProfession,160)
    UIDropDownMenu_Initialize(f.pickProfession,function(_,level)
        local ids={0}; for id in pairs(professionNames) do if OldKraken.WorkshopOrders and OldKraken.WorkshopOrders:SupportsProfession(id) then ids[#ids+1]=id end end
        table.sort(ids,function(a,b) if a==b then return false elseif a==0 then return true elseif b==0 then return false end; return professionNames[a]<professionNames[b] end)
        for _,id in ipairs(ids) do
            local value=id; local info=UIDropDownMenu_CreateInfo(); info.text=value==0 and 'Усі професії' or professionNames[value]; info.value=value; info.checked=pickerProfession==value
            info.func=function() pickerProfession=value; offset=0; UIDropDownMenu_SetText(f.pickProfession,info.text); addCached('',textFilter(f.query:GetText()),pickerProfession); render() end
            UIDropDownMenu_AddButton(info,level)
        end
    end)
    f.pickProfession:Hide()
    f.count=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); f.count:SetPoint('TOPLEFT',f,'TOPLEFT',20,-104)
    for i=1,PAGE_SIZE do
        rows[i]=button(f,'',20,-125-(i-1)*26,410,function(self)
            f.infoScroll:SetVerticalScroll(0)
            if self.entry and tab=='masters' and not selectRecipe then selectedMaster=self.entry; render()
            elseif self.entry and selectRecipe then
                if self.entry.owner==identity then print('Old Kraken: для замовлення оберіть рецепт іншого майстра.'); return end
                local entry=self.entry
                local callback=selectRecipe; Recipes:CancelPicker()
                if OldKraken.UIHub and OldKraken.Workshop then OldKraken.Workshop:Back() else f:Hide() end
                callback(entry.record,entry.owner)
            elseif self.entry then selectedEntry=self.entry; render() end
        end)
        rows[i].icon=rows[i]:CreateTexture(nil,'ARTWORK'); rows[i].icon:SetSize(21,21); rows[i].icon:SetPoint('LEFT',rows[i],'LEFT',3,0)
        rows[i].name=rows[i]:CreateFontString(nil,'OVERLAY','GameFontNormal'); rows[i].name:SetPoint('TOPLEFT',rows[i],'TOPLEFT',29,-1); rows[i].name:SetWidth(370); rows[i].name:SetJustifyH('LEFT'); rows[i].name:SetWordWrap(false)
        rows[i].meta=rows[i]:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); rows[i].meta:SetPoint('BOTTOMLEFT',rows[i],'BOTTOMLEFT',29,1); rows[i].meta:SetWidth(370); rows[i].meta:SetJustifyH('LEFT'); rows[i].meta:SetWordWrap(false)
    end
    f.detailIcon=f:CreateTexture(nil,'ARTWORK'); f.detailIcon:SetSize(46,46); f.detailIcon:SetPoint('TOPLEFT',f,'TOPLEFT',450,-128)
    f.detailTitle=f:CreateFontString(nil,'OVERLAY','GameFontNormal'); f.detailTitle:SetPoint('TOPLEFT',f,'TOPLEFT',505,-131); f.detailTitle:SetWidth(220); f.detailTitle:SetJustifyH('LEFT'); f.detailTitle:SetWordWrap(true)
    f.infoScroll=CreateFrame('ScrollFrame','OldKrakenWorkshopRecipesInfoScroll',f,'UIPanelScrollFrameTemplate'); f.infoScroll:SetPoint('TOPLEFT',f,'TOPLEFT',450,-184); f.infoScroll:SetSize(255,110)
    if OldKraken.UIStyle.ScrollBar then OldKraken.UIStyle.ScrollBar(f.infoScroll) end
    f.infoContent=CreateFrame('Frame',nil,f.infoScroll); f.infoContent:SetSize(245,110); f.infoScroll:SetScrollChild(f.infoContent)
    f.detailInfo=f.infoContent:CreateFontString(nil,'OVERLAY','GameFontHighlight'); f.detailInfo:SetPoint('TOPLEFT'); f.detailInfo:SetWidth(245); f.detailInfo:SetJustifyH('LEFT'); f.detailInfo:SetJustifyV('TOP')
    f.detailReagents=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); f.detailReagents:SetPoint('TOPLEFT',f,'TOPLEFT',450,-302); f.detailReagents:SetWidth(275); f.detailReagents:SetJustifyH('LEFT'); f.detailReagents:SetJustifyV('TOP')
    f.reagentRows={}
    for i=1,9 do
        local row=CreateFrame('Frame',nil,f)
        row:SetSize(275,22); row:SetPoint('TOPLEFT',f.detailReagents,'BOTTOMLEFT',0,-8-(i-1)*26); row:EnableMouse(true)
        row.label=row:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); row.label:SetAllPoints(row); row.label:SetJustifyH('LEFT'); row.label:SetWordWrap(false)
        readableFont(row.label,13)
        row:SetScript('OnEnter',function(self) if self.itemID then showItemTooltip(self,self.itemID,0) end end)
        row:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
        row:Hide(); f.reagentRows[i]=row
    end
    f.whisper=button(f,'Шепнути',450,-410,110,function()
        local name=tab=='masters' and selectedMaster and selectedMaster.name or (selectedEntry and selectedEntry.owner)
        if name and name~=identity and type(ChatFrame_SendTell)=='function' then ChatFrame_SendTell(name) end
    end,nil,{rounded=true,height=34})
    f.order=button(f,'Замовити',570,-410,120,function() if selectedEntry and OldKraken.WorkshopOrders then OldKraken.WorkshopOrders:ShowRecipe(selectedEntry.record,selectedEntry.owner) end end,'primary',{rounded=true,height=34})
    f.masterRecipes=button(f,'Рецепти майстра',570,-410,160,function()
        if not selectedMaster then return end
        if OldKraken.UIHub and OldKraken.Workshop then OldKraken.Workshop:Navigate('recipes',true) end
        local masterProfession=selectedMaster.profession
        viewOwner=selectedMaster.name; tab='recipes'; selectedEntry=nil; selectedMaster=nil; offset=0; f.query:SetText(''); render()
        if not professionContext then professionContext=masterProfession; search('prof:'..professionContext); render() end
    end,'primary',{rounded=true,height=34})
    f.previousPage=button(f,'‹',20,-394,44,function() offset=offset-1; render() end,nil,{rounded=true,height=28})
    f.page=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); f.page:SetPoint('TOPLEFT',f,'TOPLEFT',75,-399)
    f.nextPage=button(f,'›',130,-394,44,function() offset=offset+1; render() end,nil,{rounded=true,height=28})
    f.status=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); f.status:SetPoint('TOPLEFT',f,'TOPLEFT',20,-438); f.status:SetWidth(410); f.status:SetJustifyH('LEFT')
    f.status:SetText(scanStatus)
    f.cancelPick=button(f,'Скасувати вибір',570,-438,145,function()
        if OldKraken.UIHub and OldKraken.Workshop then OldKraken.Workshop:Back()
        else Recipes:CancelPicker(); f:Hide() end
    end,nil,{rounded=true,height=30})
    if parent then
        local function place(control,x,y,width,height)
            control:ClearAllPoints(); control:SetPoint('TOPLEFT',f,'TOPLEFT',x,y)
            if width and height then control:SetSize(width,height) end
        end
        place(f.context,0,-30)
        place(f.query,12,-61,320,34); place(f.searchButton,342,-61,104,34)
        place(f.onlineOnly,462,-61,172,34); place(f.pickProfession,446,-61)
        place(f.count,0,-108)
        if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(f.count, 12) end
        if colors.mutedText then f.count:SetTextColor(colors.mutedText[1], colors.mutedText[2], colors.mutedText[3]) end
        for i,row in ipairs(rows) do
            place(row,0,-126-(i-1)*34,482,32)
            row.icon:SetSize(24,24)
            row.name:ClearAllPoints(); row.name:SetPoint('TOPLEFT',row,'TOPLEFT',36,-2); row.name:SetWidth(436)
            row.meta:ClearAllPoints(); row.meta:SetPoint('BOTTOMLEFT',row,'BOTTOMLEFT',36,2); row.meta:SetWidth(436)
        end
        if type(f.detailPanel)=='table' then
            f.detailIcon:SetParent(f.detailPanel)
            f.detailTitle:SetParent(f.detailPanel)
        end
        place(f.detailIcon,514,-140,46,46)
        place(f.detailTitle,572,-144); f.detailTitle:SetWidth(312)
        place(f.infoScroll,514,-198,356,262)
        f.infoContent:SetSize(344,262); f.detailInfo:SetWidth(344)
        f.detailReagents:SetParent(f.infoContent); f.detailReagents:ClearAllPoints()
        f.detailReagents:SetPoint('TOPLEFT',f.detailInfo,'BOTTOMLEFT',0,-16); f.detailReagents:SetWidth(344)
        for i,row in ipairs(f.reagentRows) do
            row:SetParent(f.infoContent); row:SetSize(344,22); row:ClearAllPoints()
            row:SetPoint('TOPLEFT',f.detailReagents,'BOTTOMLEFT',0,-8-(i-1)*26)
        end
        place(f.whisper,514,-474,132,34); place(f.order,658,-474,226,34)
        place(f.masterRecipes,658,-474,226,34)
        place(f.previousPage,160,-480,44,28)
        f.page:ClearAllPoints(); f.page:SetPoint('CENTER',f.previousPage,'RIGHT',37,0); f.page:SetJustifyH('CENTER')
        place(f.nextPage,278,-480,44,28)
        place(f.status,0,-514); f.status:SetWidth(482)
        place(f.cancelPick,740,-512,160,30)
    end
    for _,row in ipairs(rows) do
        readableFont(row.name,parent and 14 or 12)
        readableFont(row.meta,parent and 12 or 10)
    end
    readableFont(f.detailTitle,16,2)
    f.detailTitle:SetHeight(48)
    local detailHover=CreateFrame('Frame',nil,type(f.detailPanel)=='table' and f.detailPanel or f)
    detailHover:SetPoint('TOPLEFT',f.detailIcon,'TOPLEFT',0,0)
    detailHover:SetPoint('BOTTOMRIGHT',f.detailTitle,'BOTTOMRIGHT',0,0)
    detailHover:EnableMouse(true)
    detailHover:SetScript('OnEnter',function(self)
        if tab=='masters' or not selectedEntry or not selectedEntry.record then return end
        local r=selectedEntry.record
        showItemTooltip(self,r.item,r.recipe)
    end)
    detailHover:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
    readableFont(f.detailInfo,14,3)
    readableFont(f.detailReagents,13,3)
    readableFont(f.searchLabel,13)
    readableFont(f.count,12)
    readableFont(f.status,12)
    readableFont(f.page,12)
    if colors.mutedText then f.status:SetTextColor(colors.mutedText[1],colors.mutedText[2],colors.mutedText[3]) end
    if parent then readableFont(f.context,14) end
    f.cancelPick:Hide()
    if not parent then f:SetScript('OnHide',function() Recipes:CancelPicker() end) end
    f:Hide(); return f
end
function Recipes:CreatePanel(parent)
    if not frame then frame=createWindow(parent) end
    return frame
end
function Recipes:RefreshPanel() render() end
function Recipes:IsPicking() return selectRecipe~=nil end
function Recipes:CancelPicker() selectRecipe=nil; pickerProfession=0 end
function Recipes:GetTab() return selectRecipe and 'recipes' or tab end
function Recipes:SelectTab(nextTab)
    if nextTab~='recipes' and nextTab~='masters' then return end
    if selectRecipe and OldKraken.UIHub and OldKraken.Workshop then OldKraken.Workshop:Back() end
    if not OldKraken.Workshop or OldKraken.Workshop.currentView~='recipes' then
        self:Show(); if not active or not frame then return end
        addCached('')
        restoringView=true; frame.query:SetText(''); restoringView=false
        if OldKraken.Workshop then OldKraken.Workshop:RefreshNativeProfessions() end
    end
    self:CancelPicker()
    switchTab(nextTab)
    render()
end
function Recipes:CaptureView()
    return {profession=professionContext,master=selectedMaster,tab=tab,online=mastersOnline,
        selected=selectedEntry,owner=viewOwner,offset=offset,
        results=resultSet,resultQuery=resultQuery,activeQuery=activeQuery,query=frame and frame.query:GetText() or '',status=frame and frame.status:GetText() or ''}
end
function Recipes:RestoreView(state)
    professionContext,selectedMaster,tab,mastersOnline=state.profession,state.master,state.tab,state.online
    selectedEntry,viewOwner,offset,resultSet,resultQuery=state.selected,state.owner,state.offset,state.results,state.resultQuery
    self:CancelPicker()
    activeQuery=state.activeQuery and GetTime()<=state.activeQuery.untilTime and state.activeQuery or nil
    if resultQuery then addCached(resultQuery) end
    if selectedEntry then
        local stored=people[selectedEntry.owner] and people[selectedEntry.owner][selectedEntry.record.recipe]
        selectedEntry=validRecord(stored) and {owner=selectedEntry.owner,record=stored} or nil
    end
    if selectedMaster and OldKraken.Workshop then
        local selectedProfession=selectedMaster.profession or professionContext
        local previousName=selectedMaster.name; selectedMaster=nil
        for _,master in ipairs(OldKraken.Workshop:GetProfessionMasters(selectedProfession)) do
            if master.name==previousName then master.profession=selectedProfession; selectedMaster=master; break end
        end
    end
    restoringView=true; frame.query:SetText(state.query or ''); restoringView=false
    if tab=='recipes' and not professionContext then addCached('',textFilter(state.query)) end
    frame.status:SetText(state.status or ''); render()
end
function Recipes:Show(forceNavigation)
    connect(); if not active then print('Old Kraken: пошук рецептів доступний членам гільдії.'); return end
    if OldKraken.UIHub and OldKraken.Workshop then
        OldKraken.UIHub:ShowPage('workshop')
        if OldKraken.Workshop.currentView=='recipes' and not forceNavigation and not selectRecipe then frame:Show(); render(); return end
        self:CancelPicker()
        OldKraken.Workshop:Navigate('recipes',forceNavigation)
    elseif not frame then frame=createWindow() end
    professionContext,selectedMaster,tab,viewOwner,selectRecipe=nil,nil,'recipes',nil,nil
    restoringView=true; frame.query:SetText(''); restoringView=false
    addCached('')
    frame:Show(); render()
end
function Recipes:ExportSnapshot()
    if not active or not scope or type(people[identity])~='table' then return nil end
    local out={}
    for _,r in pairs(people[identity]) do
        if validRecord(r) then out[#out+1]={recipe=r.recipe,item=r.item,profession=r.profession,seen=r.seen,name=r.name,product=r.product} end
    end
    for _,r in pairs(scope.recipeTombstones[identity] or {}) do
        if validRecord(r) then out[#out+1]={recipe=r.recipe,item=r.item,profession=r.profession,seen=r.seen,name=r.name,product=r.product,deleted=true} end
    end
    if #out>5000 then return nil end
    table.sort(out,function(a,b) return a.recipe<b.recipe end)
    return scope.recipeVersions[identity],out
end
function Recipes:ImportSnapshot(owner,records,relayed,allowOverride)
    if not active or not safeText(owner,1,128) or owner==identity or type(records)~='table' or #records>5000 then return false end
    for _,r in ipairs(records) do if not validRecord(r) or (r.deleted~=nil and r.deleted~=true) then return false end end
    if type(people[owner])~='table' then if count(people)>=1000 then return false end; people[owner]={} end
    local current=people[owner]
    if type(scope.recipeTombstones[owner])~='table' then scope.recipeTombstones[owner]={} end
    local total=count(current)+count(scope.recipeTombstones[owner])
    for _,r in ipairs(records) do
        local old=current[r.recipe] or scope.recipeTombstones[owner][r.recipe]
        if old or total<5000 then
            if not old then total=total+1 end
            local authoritative=not relayed and allowOverride~=false
            if r.deleted then storeTombstone(owner,r,relayed,authoritative)
            else
            local stored=storeRecipe(owner,r,relayed,authoritative)
            if stored and activeQuery and matches(stored,activeQuery.query) then
                local k=owner..'\001'..r.recipe
                if resultSet[k] or count(resultSet)<5000 then resultSet[k]={owner=owner,record=stored} end
            end
            end
        end
    end
    indexRevision=indexRevision+1; recipeChanged=true; changed(); return true
end
function Recipes:ValidateSnapshotRecord(r) return validRecord(r) and (r.deleted==nil or r.deleted==true) and true or false end
function Recipes:GetProfessionSummaries()
    ensureRecipeIndex()
    return summaryCache
end
function Recipes:ShowProfession(profession,forceNavigation)
    if not professionNames[profession] then return end
    if not forceNavigation and OldKraken.Workshop and OldKraken.Workshop.currentView=='recipes' and professionContext==profession and tab=='recipes' and not viewOwner and not selectRecipe then
        self:Show(); return
    end
    self:Show(true); if not active or not frame then return end
    selectRecipe=nil; selectedEntry=nil; viewOwner=nil; professionContext=profession; selectedMaster=nil; tab='recipes'; mastersOnline=false
    if OldKraken.Workshop then OldKraken.Workshop:RefreshNativeProfessions() end
    frame.query:SetText('')
    frame.status:SetText(professionNames[profession]..': збережені рецепти та відповіді онлайн-майстрів; список може бути неповним.')
    search('prof:'..profession); frame:Raise(); render()
end
function Recipes:ShowMemberProfession(name,profession)
    if not safeText(name,1,128) or not professionNames[profession] then return end
    self:ShowProfession(profession,true)
    if active and frame then
        viewOwner=name; selectedEntry=nil
        frame.status:SetText(name..' · '..professionNames[profession]..': збережені рецепти; список може бути неповним.')
        render()
    end
end
function Recipes:Choose(callback,profession)
    if type(callback)~='function' then return end
    self:Show(); if not active or not frame then return end
    selectRecipe=callback; selectedEntry=nil; viewOwner=nil; resultSet={}; resultQuery=nil; activeQuery=nil; offset=0
    pickerProfession=professionNames[profession] and profession or 0
    restoringView=true; frame.query:SetText(''); restoringView=false
    UIDropDownMenu_SetText(frame.pickProfession,pickerProfession==0 and 'Усі професії' or professionNames[pickerProfession])
    addCached('',nil,pickerProfession)
    frame.status:SetText('Оберіть рецепт іншого майстра. Власні рецепти позначено у списку.')
    frame:Raise(); render()
end
function Recipes:FindMasters(itemID,recipeID)
    local found={}
    if not integer(itemID,0,100000000) or not integer(recipeID,0,100000000) or (itemID==0 and recipeID==0) then return {} end
    if recipeID>0 then
        for name,records in pairs(people) do
            local r=type(records)=='table' and records[recipeID]
            if safeText(name,1,128) and validRecord(r) then found[name]=r.seen end
        end
    end
    if itemID>0 then
        ensureRecipeIndex()
        for name,seen in pairs(itemIndex[itemID] or {}) do found[name]=math.max(found[name] or 0,seen) end
    end
    local out={}; for name,seen in pairs(found) do out[#out+1]={name=name,seen=seen} end
    table.sort(out,function(a,b) return a.name<b.name end); return out
end
function Recipes:Knows(itemID,recipeID)
    if not active or not identity or not integer(itemID,0,100000000) or not integer(recipeID,0,100000000) or (itemID==0 and recipeID==0) then return false end
    local own=people[identity]
    if type(own)~='table' then return false end
    if recipeID>0 and validRecord(own[recipeID]) then return true end
    if itemID==0 then return false end
    if ownItemsRevision~=indexRevision then
        ownItems={}
        for _,r in pairs(own) do if validRecord(r) and r.item>0 then ownItems[r.item]=true end end
        ownItemsRevision=indexRevision
    end
    return ownItems[itemID]==true
end
function Recipes:ShowMasters(itemID,recipeID)
    self:Show(true); if not active or not frame then return end
    selectRecipe=nil; selectedEntry=nil; viewOwner=nil
    local query=itemID>0 and ('item:'..itemID) or ('recipe:'..recipeID)
    frame.query:SetText(query); frame.status:SetText('Відомі майстри; дата показує останнє зчитування рецепта.')
    search(query); frame:Raise()
end
OldKraken:On('WORKSHOP_PROFESSIONS_CHANGED',function() if tab=='masters' then changed() end end)
OldKraken:On('WORKSHOP_INDEX_CHANGED',changed)
