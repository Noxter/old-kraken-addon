local T = OldKraken.Translate or function(text) return text end
local function chatInfo(msg)
    if OldKraken.Print then OldKraken:Print(msg) else print('|cff2ec4b6Old Kraken|r: ' .. tostring(msg or ''):gsub('^|c%x%x%x%x%x%x%x%xOld Kraken|r:%s*', ''):gsub('^Old Kraken:%s*', '')) end
end
local function chatError(msg)
    if OldKraken.PrintError then OldKraken:PrintError(msg) else print('|cffff5555Old Kraken|r: ' .. tostring(msg or ''):gsub('^|c%x%x%x%x%x%x%x%xOld Kraken|r:%s*', ''):gsub('^Old Kraken:%s*', '')) end
end
-- On-demand guild recipe search. Never treat a filtered scan as a complete list.
local Recipes={}
OldKraken.WorkshopRecipes=Recipes
local comm,codec=OldKraken.Communication,OldKraken.GroupFinder
local professionNames={[171]='Алхімія',[164]='Ковальство',[165]='Шкірництво',[197]='Кравецтво',[202]='Інженерія',[333]='Зачарування'}
local active,identity,profile,scope,people=false,nil,nil,nil,{}
local pendingLearned,learnAttempts,learnWarned={},{},{}
local recipeCatalog,catalogCursor,catalogPending,catalogSize=nil,nil,false,0
local scanPending,tradeOpen,sendQueue=false,false,{}
local activeQuery,sequence,lastQuery,lastIncoming=nil,0,-60,{}
local forgetChecks,lastScanProfession={},nil
local frame,rows,offset,resultSet=nil,{},0,{}
local PAGE_SIZE=10
local selectRecipe,selectedEntry,selectedRecipeMaster,viewOwner
local pickerProfession=0
local professionContext, selectedMaster, tab, mastersOnline, temporaryProfessionContext = nil, nil, 'recipes', false, false
local selectedType, lastTypeContextKey = 'all', ''
local typeCache, itemDataRevision, typeScanJob = {}, 0, nil
local availableTypeCache = { rev = -1, itemRev = -1, key = '', list = {'all'}, set = {all = true} }
local restoringView=false
local resultQuery
local tabStates={}
local recipeChanged=false
local indexRevision=0
local summaryCache,itemIndex,itemProfessionIndex={},{},{}
local indexedRevision=-1
local indexJob,searchJob
local ownItems,ownItemsRevision={},-1
local scanStatus
local initialScanStatus = 'Відкрийте свої професії; шукайте назву рецепта, предмета або вставте посилання на предмет.'
local render, matches
local activeItemNames, activeSpellNames, activeDisplayNames
local renderApiCalls = 0
local function usable(v,t) return not (type(issecretvalue)=='function' and issecretvalue(v)) and type(v)==t end
local function integer(n,lo,hi) return usable(n,'number') and n==n and n%1==0 and n>=lo and n<=hi end
local ignoredProfessions={[185]=true,[129]=true,[356]=true,[186]=true,[182]=true,[393]=true}
local function isIgnoredProfession(prof)
    return prof~=nil and ignoredProfessions[prof]==true
end
local function knownProfessionID(prof)
    return prof~=nil and (professionNames[prof]~=nil or ignoredProfessions[prof]==true)
end
local function resolveRecipeProfession(id)
    local prof
    if type(C_TradeSkillUI)=='table' then
        if type(C_TradeSkillUI.GetProfessionInfoByRecipeID)=='function' then
            local ok,data=pcall(C_TradeSkillUI.GetProfessionInfoByRecipeID,id)
            if ok and usable(data,'table') then
                if integer(data.parentProfessionID,1,1000000) and knownProfessionID(data.parentProfessionID) then prof=data.parentProfessionID
                elseif integer(data.professionID,1,1000000) and knownProfessionID(data.professionID) then prof=data.professionID end
            end
        end
        if not prof and type(C_TradeSkillUI.GetTradeSkillLineForRecipe)=='function' then
            local ok,line=pcall(C_TradeSkillUI.GetTradeSkillLineForRecipe,id)
            if ok and integer(line,1,1000000) and knownProfessionID(line) then prof=line end
        end
    end
    if not prof and recipeCatalog and type(recipeCatalog[id])=='table' and knownProfessionID(recipeCatalog[id].profession) then
        prof=recipeCatalog[id].profession
    end
    return prof
end
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
local function changed(reason)
    if OldKraken.perfEnabled and type(OldKraken.PerfRecord)=='function' then
        OldKraken:PerfRecord('wk.recipes.chg.'..(reason or 'other'), 0)
    end
    if changedPending then
        if OldKraken.perfEnabled and type(OldKraken.PerfRecord)=='function' then
            OldKraken:PerfRecord('wk.recipes.chg.coalesced', 0)
        end
        return
    end
    if not (frame and frame:IsShown()) then return end
    local function flush()
        changedPending=false
        if frame and frame:IsShown() then if render then render('changed') end end
    end
    if C_Timer and C_Timer.After then changedPending=true; C_Timer.After(0.15,flush) else flush() end
end

OldKraken:On('WORKSHOP_SCOPE_MIGRATED',function(migratedProfile)
    if not active or profile~=migratedProfile then return end
    indexRevision=indexRevision+1; indexedRevision=-1
    summaryCache,itemIndex,itemProfessionIndex={},{},{}; indexJob,searchJob=nil,nil
    ownItemsRevision=-1; recipeChanged=true
    local saved=scope.recipeVersions[identity]
    if integer(saved,0,8999999999999999) then
        scope.recipeVersions[identity]=math.max(saved+1,GetServerTime()*1000)
    end
    changed('scopeMigrated')
end)

local function validRecord(r)
    return type(r)=='table' and integer(r.recipe,1,100000000) and integer(r.item,0,100000000)
        and integer(r.profession,1,1000000) and professionNames[r.profession] and integer(r.seen,1,GetServerTime()+600)
        and safeText(r.name,1,120) and safeText(r.product,0,120)
end
local function validRealm(realm)
    if OldKraken.Database and type(OldKraken.Database.IsValidRealm)=='function' then
        return OldKraken.Database:IsValidRealm(realm)
    end
    return safeText(realm,1,128)
end
local function resolveRealm()
    if OldKraken.Database and type(OldKraken.Database.GetRealmScope)=='function' then
        return OldKraken.Database:GetRealmScope()
    end
    local realm=type(GetRealmName)=='function' and GetRealmName() or nil
    if validRealm(realm) then return realm end
    if type(issecretvalue)=='function' and issecretvalue(realm) then return nil end
    if realm=='' then return 'Forever' end
    return nil
end
local function connect()
    local name=myName(); local guild=type(GetGuildInfo)=='function' and GetGuildInfo('player')
    local realm=resolveRealm()
    if not name or not safeText(guild,1,128) or not validRealm(realm) or not OldKraken.DB then
        if Recipes.CancelPicker then Recipes:CancelPicker() end
        active,identity,profile,scope,people=false,nil,nil,nil,{}; activeQuery=nil; sendQueue={}; pendingLearned,learnAttempts,learnWarned={},{},{}
        tabStates={}
        indexRevision=indexRevision+1; indexedRevision=-1; summaryCache,itemIndex,itemProfessionIndex={},{},{}; indexJob,searchJob=nil,nil
        if frame then frame:Hide() end; return
    end
    if OldKraken.Database and type(OldKraken.Database.MigrateWorkshopScope)=='function' then
        OldKraken.Database:MigrateWorkshopScope(realm,guild,false)
    end
    local k=realm..'\001'..guild
    if active and identity==name and profile==k then return end
    if Recipes.CancelPicker then Recipes:CancelPicker() end
    tabStates={}
    indexRevision=indexRevision+1; indexedRevision=-1; summaryCache,itemIndex,itemProfessionIndex={},{},{}; indexJob,searchJob=nil,nil
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
    pendingLearned,learnAttempts,learnWarned=scope.pendingRecipes[name],{},{}
    activeQuery,sendQueue,lastIncoming,resultSet,forgetChecks,lastScanProfession=nil,{}, {}, {}, {},nil
    local removals=type(scope.pendingProfessionRemovals)=='table' and scope.pendingProfessionRemovals[name]
    if type(removals)=='table' and type(Recipes.ForgetProfession)=='function' then
        for profession in pairs(removals) do Recipes:ForgetProfession(profession,name,k) end
    end
    changed('connect')
end
local function storeRecipe(owner,r,relayed,authoritative)
    if type(people[owner])~='table' then if count(people)>=1000 then return nil end; people[owner]={} end
    if type(scope.recipeSources[owner])~='table' then scope.recipeSources[owner]={} end
    if type(scope.recipeTombstones[owner])~='table' then scope.recipeTombstones[owner]={} end
    local records,sources=people[owner],scope.recipeSources[owner]
    local tomb=scope.recipeTombstones[owner][r.recipe]
    if relayed and sources[r.recipe]~=true and (validRecord(records[r.recipe]) or validRecord(tomb)) then return records[r.recipe] end
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
    if relayed and sources[r.recipe]~=true and (validRecord(old) or validRecord(tomb)) then return false end
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
        if isIgnoredProfession(r.profession) then
            pendingLearned[r.recipe],learnAttempts[r.recipe],learnWarned[r.recipe]=nil,nil,nil
        elseif #sendQueue<100 then
            pendingLearned[r.recipe]=nil; learnAttempts[r.recipe]=nil; learnWarned[r.recipe]=nil
            local payload=codec._pack({r.recipe,r.item,r.profession,r.seen,r.name,r.product})
            sendQueue[#sendQueue+1]={kind='WRLEARN',payload=payload,expires=GetTime()+120}
        end
    end
    if activeQuery and matches and matches(r,activeQuery.query) then
        local resultKey=identity..'\001'..r.recipe
        if resultSet[resultKey] or count(resultSet)<500 then resultSet[resultKey]={owner=identity,record=r} end
        if not deferRefresh then changed('ownLearn') end
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
    pendingLearned[id],learnAttempts[id],learnWarned[id],forgetChecks[id]=nil,nil,nil,nil
    if #sendQueue<100 then
        sendQueue[#sendQueue+1]={kind='WRFORGET',payload=codec._pack({removed.recipe,removed.item,removed.profession,removed.seen,removed.name,removed.product}),expires=GetTime()+600}
    end
    indexRevision=indexRevision+1; recipeChanged=true; if not deferRefresh then changed('forget') end; return true
end
function Recipes:ForgetProfession(profession,expectedIdentity,expectedProfile)
    if not active or not professionNames[profession] or identity~=expectedIdentity or profile~=expectedProfile then return false end
    local ids={}; for id,r in pairs(people[identity] or {}) do if validRecord(r) and r.profession==profession then ids[#ids+1]=id end end
    local changedAny=false; for _,id in ipairs(ids) do if forgetRecipe(id,true) then changedAny=true end end
    if changedAny then changed('forget') end
    if type(scope.pendingProfessionRemovals)=='table' and type(scope.pendingProfessionRemovals[identity])=='table' then scope.pendingProfessionRemovals[identity][profession]=nil end
    return true,changedAny
end
local function scanLearned(id)
    if not active or not integer(id,1,100000000) or type(C_TradeSkillUI)~='table' then return false end
    local api=C_TradeSkillUI
    if type(api.GetRecipeInfo)~='function' then return false end
    local ok,info=pcall(api.GetRecipeInfo,id)
    if not ok or not usable(info,'table') or not usable(info.learned,'boolean') or not info.learned or not safeText(info.name,1,120) then return false end
    local profession=resolveRecipeProfession(id)
    if not profession or isIgnoredProfession(profession) or not playerHasProfession(profession) then return false end
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
    if touched>0 or removedAny then changed('scanLearned') end
    scanStatus=T('Останнє зчитування: ')..touched..T(' вивчених рецептів. Список може бути відфільтрований.')
    if frame and frame:IsShown() then frame.status:SetText(scanStatus) end
    return true
end
local function getItemInfo(id)
    if not id or id<=0 then return false end
    local fn=(C_Item and type(C_Item.GetItemInfo)=='function' and C_Item.GetItemInfo) or (type(GetItemInfo)=='function' and GetItemInfo)
    if not fn then return false end
    if activeItemNames then renderApiCalls = renderApiCalls + 1 end
    return pcall(fn,id)
end
local function clientItemName(id)
    if not id or id<=0 then return nil end
    if activeItemNames then
        local hit=activeItemNames[id]
        if hit~=nil then return hit or nil end
    end
    local resolved
    if C_Item and type(C_Item.GetItemNameByID)=='function' then
        if activeItemNames then renderApiCalls = renderApiCalls + 1 end
        local ok,value=pcall(C_Item.GetItemNameByID,id)
        if ok and safeText(value,1,120) then resolved=value end
    end
    if not resolved then
        local ok,value=getItemInfo(id)
        if ok and safeText(value,1,120) then resolved=value end
    end
    if activeItemNames then activeItemNames[id]=resolved or false end
    return resolved
end
local function clientSpellName(id)
    if not id or id<=0 then return nil end
    if activeSpellNames then
        local hit=activeSpellNames[id]
        if hit~=nil then return hit or nil end
    end
    local resolved
    if C_Spell and type(C_Spell.GetSpellName)=='function' then
        if activeSpellNames then renderApiCalls = renderApiCalls + 1 end
        local ok,value=pcall(C_Spell.GetSpellName,id)
        if ok and safeText(value,1,120) then resolved=value end
    end
    if not resolved and type(GetSpellInfo)=='function' then
        if activeSpellNames then renderApiCalls = renderApiCalls + 1 end
        local ok,value=pcall(GetSpellInfo,id)
        if ok and safeText(value,1,120) then resolved=value end
    end
    if activeSpellNames then activeSpellNames[id]=resolved or false end
    return resolved
end
local function displayRecipeName(r)
    if type(r)~='table' then return '' end
    if activeDisplayNames then
        local cached=activeDisplayNames[r]
        if cached~=nil then return cached end
    end
    local result
    local localName=r.item>0 and clientItemName(r.item) or clientSpellName(r.recipe)
    if localName then
        result=localName
    else
        local cat=recipeCatalog and recipeCatalog[r.recipe]
        if type(cat)=='table' then
            local catText=cat.product~='' and cat.product or cat.name
            if isAsciiText(catText) then result=catText end
        end
        if not result then result=r.product~='' and r.product or r.name end
    end
    if activeDisplayNames then activeDisplayNames[r]=result end
    return result
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
    if validRecord(r) and r.product=='' and r.item>0 then
        local ok,name=getItemInfo(r.item)
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
        local t0 = OldKraken.perfEnabled and type(debugprofilestop) == 'function' and debugprofilestop() or nil
        local budget, visited = 200, 0
        while budget>0 and ownerIndex<=#owners do
            if not records then
                currentOwner=owners[ownerIndex]; records={}; recordIndex=1
                if safeText(currentOwner,1,128) and type(source[currentOwner])=='table' then
                    for _,r in pairs(source[currentOwner]) do records[#records+1]=r end
                end
            end
            local r=records[recordIndex]
            if r then
                recordIndex=recordIndex+1; budget=budget-1; visited=visited+1
                if visit(currentOwner,r)==false then
                    if t0 and OldKraken.PerfRecord then OldKraken:PerfRecord('wk.recipes.scan', debugprofilestop() - t0, visited) end
                    done(); return
                end
            else ownerIndex=ownerIndex+1; records=nil; budget=budget-1 end
        end
        if t0 and OldKraken.PerfRecord then OldKraken:PerfRecord('wk.recipes.scan', debugprofilestop() - t0, visited) end
        if ownerIndex>#owners then done()
        elseif C_Timer and C_Timer.After then C_Timer.After(0,step) else return step() end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0,step) else step() end
end
local function ensureRecipeIndex()
    if indexedRevision==indexRevision or indexJob then return end
    local job={revision=indexRevision}; indexJob=job
    local summaries,seen,items,itemProfs={},{},{},{}
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
                local byProf=itemProfs[r.item] or {}; itemProfs[r.item]=byProf
                local profOwners=byProf[r.profession] or {}; byProf[r.profession]=profOwners
                profOwners[name]=math.max(profOwners[name] or 0,r.seen)
            end
        end
    end,function()
        summaryCache,itemIndex,itemProfessionIndex=summaries,items,itemProfs; indexedRevision=job.revision; indexJob=nil
        OldKraken:Fire('WORKSHOP_INDEX_CHANGED')
    end,function() return indexJob==job end)
end
local function addCached(query,filter,professionFilter)
    resultQuery=query
    resultSet={}
    local limit=(query=='' or query:match('^prof:%d+$')) and 5000 or 500
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
    end,function() changed('addCached') end,function() return searchJob==job end)
end
local function search(value)
    if not active or not safeText(value,1,200) then chatError(T('Old Kraken: введіть назву або посилання на предмет.')); return false end
    local item=value:match('item:(%d+)')
    local q=item and ('item:'..item) or lower(value:match('^%s*(.-)%s*$'))
    if not safeText(q,3,80) then chatError(T('Old Kraken: введіть назву або посилання на предмет.')); return false end
    local now=GetTime()
    offset=0; addCached(q,nil,selectRecipe and pickerProfession or nil)
    if now-lastQuery<10 then
        if activeQuery and activeQuery.query~=q then activeQuery=nil end
        changed('search'); chatInfo(T('Old Kraken: показано збережені результати; повторіть запит гільдії через кілька секунд.')); return false
    end
    sequence=sequence+1
    local token=tostring(GetServerTime())..'-'..tostring(math.random(100000,999999))..'-'..sequence
    if not comm:SendProtocol('WRQUERY',codec._pack({token,q})) then activeQuery=nil; changed('search'); chatError(T('Old Kraken: показано збережені результати; запит гільдії надіслати не вдалося.')); return false end
    lastQuery=now; activeQuery={token=token,query=q,untilTime=now+(q:match('^prof:%d+$') and 600 or 120)}; changed('search'); return true
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
local function targetMatchesSelf(part1)
    if not active or not identity then return true end
    local first,last,sz=part1:find('(%d+):',1)
    if first~=1 or not sz or #sz>4 then return true end
    sz=tonumber(sz)
    if not sz or last+sz>#part1 then return true end
    return part1:sub(last+1,last+sz)==identity
end
if type(comm.part1Filters)=='table' then
    comm.part1Filters.WRBATCH=targetMatchesSelf
    comm.part1Filters.WRRESULT=targetMatchesSelf
end
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
            local stored=storeRecipe(sender,r,false,true)
            if stored then
                local k=sender..'\001'..r.recipe
                if resultSet[k] or resultCount<5000 then if not resultSet[k] then resultCount=resultCount+1 end; resultSet[k]={owner=sender,record=stored} end
                updated=true
            end
        end
    end
    if updated then changed('net'); indexRevision=indexRevision+1; recipeChanged=true end
end)
comm:RegisterHandler('WRRESULT',function(sender,_,payload)
    if not active or not activeQuery or GetTime()>activeQuery.untilTime or not safeText(sender,1,128) then return end
    local f=codec._unpackFields(payload,8)
    if not f or #f~=8 or f[1]~=identity or f[2]~=activeQuery.token then return end
    local r={recipe=tonumber(f[3]),item=tonumber(f[4]),profession=tonumber(f[5]),seen=tonumber(f[6]),name=f[7],product=f[8]}
    if not matches(r,activeQuery.query) then return end
    if type(people[sender])~='table' then if count(people)>=1000 then return end; people[sender]={} end
    if not people[sender][r.recipe] and count(people[sender])>=5000 then return end
    local stored=storeRecipe(sender,r,false,true); if not stored then return end
    local k=sender..'\001'..r.recipe
    if resultSet[k] or count(resultSet)<500 then resultSet[k]={owner=sender,record=stored} end
    changed('net'); indexRevision=indexRevision+1; recipeChanged=true
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
    local stored=storeRecipe(sender,r,false,true); if not stored then return end
    if activeQuery and GetTime()<=activeQuery.untilTime then
        local k=sender..'\001'..r.recipe
        if matches(stored,activeQuery.query) and (resultSet[k] or count(resultSet)<500) then resultSet[k]={owner=sender,record=stored}
        elseif resultSet[k] then resultSet[k]=nil end
    end
    changed('net'); indexRevision=indexRevision+1; recipeChanged=true
end)
comm:RegisterHandler('WRFORGET',function(sender,_,payload)
    if not active or not safeText(sender,1,128) or sender==identity then return end
    local f=codec._unpackFields(payload,6); if not f or #f~=6 then return end
    local r={recipe=tonumber(f[1]),item=tonumber(f[2]),profession=tonumber(f[3]),seen=tonumber(f[4]),name=f[5],product=f[6],deleted=true}
    if validRecord(r) and storeTombstone(sender,r,false,true) then changed('net'); indexRevision=indexRevision+1; recipeChanged=true end
end)

local lastSpellsCatalogScan=-60
local events=CreateFrame('Frame')
for _,event in ipairs({'PLAYER_LOGIN','PLAYER_GUILD_UPDATE','GUILD_ROSTER_UPDATE','TRADE_SKILL_SHOW','TRADE_SKILL_LIST_UPDATE','TRADE_SKILL_DATA_SOURCE_CHANGED','TRADE_SKILL_CLOSE','NEW_RECIPE_LEARNED','SPELLS_CHANGED','SKILL_LINES_CHANGED','LEARNED_SPELL_IN_SKILL_LINE'}) do pcall(events.RegisterEvent,events,event) end
events:SetScript('OnEvent',function(_,event,recipeID)
    if event=='PLAYER_LOGIN' or event=='PLAYER_GUILD_UPDATE' or event=='GUILD_ROSTER_UPDATE' then connect()
    elseif event=='NEW_RECIPE_LEARNED' then
        connect()
        if active and integer(recipeID,1,100000000) then
            if isIgnoredProfession(resolveRecipeProfession(recipeID)) then
                pendingLearned[recipeID],learnAttempts[recipeID],learnWarned[recipeID]=nil,nil,nil
            elseif pendingLearned[recipeID] or count(pendingLearned)<1000 then
                pendingLearned[recipeID]=true; learnAttempts[recipeID]=0; learnWarned[recipeID]=nil
                if tradeOpen then scanPending=true end
            end
        end
    elseif event=='LEARNED_SPELL_IN_SKILL_LINE' then
        catalogCursor=nil; catalogPending=true; lastSpellsCatalogScan=GetTime()
        if tradeOpen then scanPending=true end
    elseif event=='SPELLS_CHANGED' then
        local now=GetTime()
        if now-lastSpellsCatalogScan>=60 then catalogCursor=nil; catalogPending=true; lastSpellsCatalogScan=now end
        if tradeOpen then scanPending=true end
    elseif event=='TRADE_SKILL_CLOSE' then tradeOpen=false; scanPending=false; forgetChecks={}; lastScanProfession=nil
    elseif event=='TRADE_SKILL_SHOW' then tradeOpen=true; scanPending=true; learnAttempts={}
    elseif tradeOpen then scanPending=true end
end)
local function pendingRecipeName(id)
    if type(C_TradeSkillUI)=='table' and type(C_TradeSkillUI.GetRecipeInfo)=='function' then
        local ok,info=pcall(C_TradeSkillUI.GetRecipeInfo,id)
        if ok and usable(info,'table') and safeText(info.name,1,120) then return info.name end
    end
    if recipeCatalog and type(recipeCatalog[id])=='table' and safeText(recipeCatalog[id].name,1,120) then
        return recipeCatalog[id].name
    end
    if type(C_Spell)=='table' and type(C_Spell.GetSpellName)=='function' then
        local ok,name=pcall(C_Spell.GetSpellName,id)
        if ok and safeText(name,1,120) then return name end
    end
    if type(GetSpellInfo)=='function' then
        local ok,name=pcall(GetSpellInfo,id)
        if ok and safeText(name,1,120) then return name end
    end
    return nil
end
local function pendingRecipeProfession(id)
    local prof=resolveRecipeProfession(id)
    if prof and professionNames[prof] and not isIgnoredProfession(prof) and playerHasProfession(prof) then return T(professionNames[prof]) end
    return nil
end
local function playerCraftingProfessionsText()
    if type(GetProfessions)~='function' or type(GetProfessionInfo)~='function' then return nil end
    local ok,a,b,c,d,e,f=pcall(GetProfessions); if not ok then return nil end
    local indexes={a,b,c,d,e,f}
    local list,seen={},{}
    for i=1,6 do
        if integer(indexes[i],1,100000) then
            local success,_,_,_,_,_,_,skillLine=pcall(GetProfessionInfo,indexes[i])
            if success and integer(skillLine,1,1000000) and professionNames[skillLine] and not isIgnoredProfession(skillLine) and not seen[skillLine] then
                seen[skillLine]=true; list[#list+1]=T(professionNames[skillLine])
            end
        end
    end
    return #list>0 and table.concat(list,' / ') or nil
end
local function formatPendingNotice(ids)
    local names,profs,seenNames,seenProfs={},{},{},{}
    local namedCount=0
    for _,id in ipairs(ids) do
        local rname=pendingRecipeName(id)
        if rname then
            namedCount=namedCount+1
            if not seenNames[rname] and #names<3 then seenNames[rname]=true; names[#names+1]=rname end
        end
        local pname=pendingRecipeProfession(id)
        if pname and not seenProfs[pname] then seenProfs[pname]=true; profs[#profs+1]=pname end
    end
    local extra=#ids-#names
    local recipePart=''
    if #names>0 then
        recipePart=' «'..table.concat(names,'», «')..'»'
        if extra>0 then
            local unnamed=#ids-namedCount
            if unnamed>0 and namedCount>#names then
                recipePart=recipePart..string.format(T(' (та ще %d, з них %d без назви)'),extra,unnamed)
            elseif unnamed>0 then
                recipePart=recipePart..string.format(T(' (та ще %d без назви)'),unnamed)
            else
                recipePart=recipePart..string.format(T(' (та ще %d)'),extra)
            end
        end
    elseif #ids>1 then
        recipePart=string.format(T(' (%d без назви)'),#ids)
    end
    local profPart=#profs>0 and table.concat(profs,' / ') or playerCraftingProfessionsText()
    if profPart then
        return string.format(T('Old Kraken: ваш новий рецепт%s очікує даних гри. Відкрийте свою професію (%s), щоб завершити оновлення.'),recipePart,profPart)
    end
    return string.format(T('Old Kraken: ваш новий рецепт%s очікує даних гри. Відкрийте вікно своєї професії, щоб завершити оновлення.'),recipePart)
end
local function runRecipeTick()
    connect(); if not active then return end
    if scanPending then
        scanPending=false
        local ok,completed=pcall(scan)
        if not ok or not completed then
            forgetChecks={}; lastScanProfession=nil
            scanStatus=T('Не вдалося зчитати власну професію. Відкрийте її та перевірте доступність API.')
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
    if next(pendingLearned)~=nil then
        local newlyTimedOut,checked={},0
        local pendingIds={}
        for id in pairs(pendingLearned) do
            if integer(id,1,100000000) then pendingIds[#pendingIds+1]=id
            else pendingLearned[id],learnAttempts[id],learnWarned[id]=nil,nil,nil end
        end
        table.sort(pendingIds)
        for _,id in ipairs(pendingIds) do
            if isIgnoredProfession(resolveRecipeProfession(id)) then
                pendingLearned[id],learnAttempts[id],learnWarned[id]=nil,nil,nil
            else
                local stored=people[identity] and people[identity][id]
                if validRecord(stored) then
                    if isIgnoredProfession(stored.profession) then
                        pendingLearned[id],learnAttempts[id],learnWarned[id]=nil,nil,nil
                    else
                        learnAttempts[id]=0; learnWarned[id]=nil
                        if #sendQueue<100 then
                            pendingLearned[id],learnAttempts[id],learnWarned[id]=nil,nil,nil
                            local payload=codec._pack({stored.recipe,stored.item,stored.profession,stored.seen,stored.name,stored.product})
                            sendQueue[#sendQueue+1]={kind='WRLEARN',payload=payload,expires=GetTime()+120}
                        end
                    end
                elseif (learnAttempts[id] or 0)<10 then
                    local ok,done=pcall(scanLearned,id)
                    if ok and done then
                        learnAttempts[id]=0; learnWarned[id]=nil
                    else
                        learnAttempts[id]=(learnAttempts[id] or 0)+1
                        if learnAttempts[id]==10 and not learnWarned[id] then
                            learnWarned[id]=true
                            newlyTimedOut[#newlyTimedOut+1]=id
                        end
                    end
                    checked=checked+1; if checked>=50 then break end
                end
            end
        end
        if #newlyTimedOut>0 then chatInfo(formatPendingNotice(newlyTimedOut)) end
    end
    while #sendQueue>0 and sendQueue[1].expires<GetTime() do table.remove(sendQueue,1) end
    if #sendQueue>0 and #comm.queue<=8 and comm:SendProtocol(sendQueue[1].kind or 'WRRESULT',sendQueue[1].payload) then table.remove(sendQueue,1) end
    if recipeChanged then recipeChanged=false; OldKraken:Fire('WORKSHOP_RECIPES_CHANGED') end
end
if C_Timer and type(C_Timer.NewTicker)=='function' then C_Timer.NewTicker(3,function()
    local t0 = OldKraken and OldKraken.perfEnabled and type(debugprofilestop) == 'function' and debugprofilestop() or nil
    runRecipeTick()
    if t0 and OldKraken.PerfRecord then OldKraken:PerfRecord('wk.recipes', debugprofilestop() - t0) end
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
    if name==identity or online[name]==true then return T('|cff4cde80онлайн|r') end
    if online[name]==false then return T('|cff999999офлайн|r') end
    return T('|cff999999невідомо|r')
end
function Recipes:GetRosterPresentation() return onlineIndex() end
function Recipes:FormatPlayerName(name,classes) return playerLabel(name,classes or {}) end
function Recipes:FormatOnlineStatus(name,online) return statusLabel(name,online or {}) end
local bopCache,requestedItems,pendingItems={},{},{}
local function requestItemData(id)
    if not id or id<=0 then return end
    pendingItems[id]=true
    local now=GetTime()
    if not requestedItems[id] or now-requestedItems[id]>=5 then
        requestedItems[id]=now
        if C_Item and type(C_Item.RequestLoadItemDataByID)=='function' then pcall(C_Item.RequestLoadItemDataByID,id) end
    end
end
local function isBindOnPickup(r)
    local id=r and r.item or 0
    if id<=0 then return false end
    local cached=bopCache[id]
    if cached~=nil then return cached end
    local ok,_,_,_,_,_,_,_,_,_,_,_,_,_,bindType=getItemInfo(id)
    if ok and type(bindType)=='number' then
        cached=bindType==1
        bopCache[id]=cached
        return cached
    end
    requestItemData(id)
    return false
end
local RECIPE_TYPE_LABELS={
    all='Усі типи', armor='Броня', weapon='Зброя', bag='Сумки', trinket='Аксесуари',
    potion='Зілля', elixir='Еліксири', flask='Фляги', enhancement='Покращення',
    explosive='Вибухівка', device='Пристрої', reagent='Реагенти', other='Інше',
    ['armor:head']='Голова', ['armor:shoulder']='Плечі', ['armor:back']='Спина',
    ['armor:chest']='Груди', ['armor:shirt']='Сорочка', ['armor:wrist']='Наручі',
    ['armor:hands']='Рукавиці', ['armor:waist']='Пояс', ['armor:legs']='Штани',
    ['armor:feet']='Чоботи', ['armor:shield']='Щит',
}
local RECIPE_TYPE_ORDER={'armor','weapon','bag','trinket','potion','elixir','flask','enhancement','explosive','device','reagent','other'}
local ARMOR_SLOT_ORDER={
    'armor:head','armor:shoulder','armor:back','armor:chest','armor:shirt',
    'armor:wrist','armor:hands','armor:waist','armor:legs','armor:feet','armor:shield',
}
local EQUIP_LOC_TYPES={
    INVTYPE_BAG='bag', INVTYPE_QUIVER='bag',
    INVTYPE_TRINKET='trinket', INVTYPE_NECK='trinket', INVTYPE_FINGER='trinket',
    INVTYPE_WEAPON='weapon', INVTYPE_2HWEAPON='weapon', INVTYPE_WEAPONMAINHAND='weapon',
    INVTYPE_WEAPONOFFHAND='weapon', INVTYPE_RANGED='weapon', INVTYPE_THROWN='weapon',
    INVTYPE_RANGEDRIGHT='weapon', INVTYPE_HOLDABLE='other',
    INVTYPE_SHIELD='armor:shield', INVTYPE_HEAD='armor:head', INVTYPE_SHOULDER='armor:shoulder', INVTYPE_BODY='armor:shirt',
    INVTYPE_CHEST='armor:chest', INVTYPE_ROBE='armor:chest', INVTYPE_WAIST='armor:waist', INVTYPE_LEGS='armor:legs',
    INVTYPE_FEET='armor:feet', INVTYPE_WRIST='armor:wrist', INVTYPE_HAND='armor:hands', INVTYPE_CLOAK='armor:back',
}
local function matchesRecipeType(cat, selected)
    if selected=='all' then return true end
    if selected=='armor' then return cat=='armor' or cat:sub(1,6)=='armor:' end
    return cat==selected
end
local function typeFilterLabel(selected)
    if not selected or selected=='all' then return RECIPE_TYPE_LABELS.all end
    return T('|cffe0b052Тип: ')..(RECIPE_TYPE_LABELS[selected] or selected)..'|r'
end
local function updateTypeFilterText()
    if frame and frame.typeFilter then UIDropDownMenu_SetText(frame.typeFilter,typeFilterLabel(selectedType)) end
end
local function classifyItemBySubType(itemType, itemSubType, classID)
    local sub=lower((itemSubType or '')..' '..(itemType or ''))
    if sub:find('flask',1,true) or sub:find('насто',1,true) or sub:find('фляг',1,true) then return 'flask' end
    if sub:find('elixir',1,true) or sub:find('эликсир',1,true) or sub:find('еліксир',1,true) then return 'elixir' end
    if sub:find('potion',1,true) or sub:find('зель',1,true) or sub:find('зілл',1,true) then return 'potion' end
    if sub:find('enhancement',1,true) or sub:find('улучшен',1,true) or sub:find('покращ',1,true) then return 'enhancement' end
    if sub:find('explosive',1,true) or sub:find('взрывчат',1,true) or sub:find('вибухів',1,true) then return 'explosive' end
    if sub:find('device',1,true) or sub:find('устройств',1,true) or sub:find('пристро',1,true) then return 'device' end
    if sub:find('bag',1,true) or sub:find('сумк',1,true) then return 'bag' end
    if sub:find('projectile',1,true) or sub:find('боеприпас',1,true) or sub:find('weapon',1,true) or sub:find('оружи',1,true) or sub:find('збро',1,true) then return 'weapon' end
    if sub:find('armor',1,true) or sub:find('доспех',1,true) or sub:find('брон',1,true) then return 'armor' end
    if classID==7 or sub:find('tradeskill',1,true) or sub:find('trade goods',1,true) or sub:find('хозяйственные',1,true)
        or sub:find('реагент',1,true) or sub:find('ремеслен',1,true)
        or sub:find('parts',1,true) or sub:find('детал',1,true) or sub:find('elemental',1,true) or sub:find('стихи',1,true)
        or sub:find('metal',1,true) or sub:find('метал',1,true) or sub:find('cloth',1,true) or sub:find('ткан',1,true)
        or sub:find('leather',1,true) or sub:find('кож',1,true) or sub:find('herb',1,true) or sub:find('трав',1,true) then return 'reagent' end
    return 'other'
end
local function classifyRecipe(r)
    if type(r)~='table' then return 'other' end
    local cacheKey=(r.profession or 0)..'\001'..(r.recipe or 0)..'\001'..(r.item or 0)
    local cached=typeCache[cacheKey]
    if cached then return cached end
    if (r.item or 0)<=0 then
        typeCache[cacheKey]='other'
        return 'other'
    end
    local ok,itemName,_,_,_,_,itemType,itemSubType,_,equipLoc,_,_,classID=getItemInfo(r.item)
    if ok and safeText(itemName,1,160) then
        local cat=(equipLoc and EQUIP_LOC_TYPES[equipLoc]) or classifyItemBySubType(itemType,itemSubType,classID)
        typeCache[cacheKey]=cat
        return cat
    end
    requestItemData(r.item)
    return 'other'
end
local function typeContextKey()
    return (professionContext or 0)..'\001'..(viewOwner or '')..'\001'..(selectRecipe and pickerProfession or -1)
end
local function ensureAvailableTypes()
    local contextKey=typeContextKey()
    if availableTypeCache.rev==indexRevision and availableTypeCache.itemRev==itemDataRevision and availableTypeCache.key==contextKey then
        return availableTypeCache.list, availableTypeCache.set, true
    end
    if typeScanJob and typeScanJob.rev==indexRevision and typeScanJob.itemRev==itemDataRevision and typeScanJob.key==contextKey then
        return {'all'}, {all=true}, false
    end
    local job={rev=indexRevision,itemRev=itemDataRevision,key=contextKey}
    typeScanJob=job
    local present={}
    local targetOwner,targetProf,targetSelect,targetPicker=viewOwner,professionContext,selectRecipe,pickerProfession
    scanCachedRecords(function(owner,r)
        if not targetOwner or owner==targetOwner then
            if validRecord(r) and (not targetProf or r.profession==targetProf)
                and (not targetSelect or ((targetPicker==0 or r.profession==targetPicker) and OldKraken.WorkshopOrders and OldKraken.WorkshopOrders:SupportsProfession(r.profession)))
                and not isBindOnPickup(r) then
                local cat=classifyRecipe(r)
                present[cat]=true
                if cat:sub(1,6)=='armor:' then present.armor=true end
            end
        end
    end,function()
        if typeScanJob~=job then return end
        typeScanJob=nil
        local list,set={'all'},{all=true}
        for _,key in ipairs(RECIPE_TYPE_ORDER) do
            if present[key] then list[#list+1]=key; set[key]=true end
        end
        for _,slot in ipairs(ARMOR_SLOT_ORDER) do
            if present[slot] then set[slot]=true end
        end
        availableTypeCache={rev=job.rev,itemRev=job.itemRev,key=job.key,list=list,set=set}
        changed('typeScan')
    end,function() return typeScanJob==job end)
    return {'all'}, {all=true}, false
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
function Recipes:ItemName(id)
    if not integer(id,1,100000000) then return nil end
    local name=clientItemName(id)
    if not name then requestItemData(id) end
    return name
end
function Recipes:ItemLabel(id)
    local name=self:ItemName(id)
    local icon
    local getIcon=C_Item and C_Item.GetItemIconByID or GetItemIcon
    if type(getIcon)=='function' then local ok,value=pcall(getIcon,id); if ok and (usable(value,'number') or usable(value,'string')) then icon=value end end
    return '|T'..tostring(icon or 134400)..':22:22:0:0|t |cffffffff'..(name or T('Завантаження назви…'))..'|r'
end
local itemEvents=CreateFrame('Frame')
for _,event in ipairs({'GET_ITEM_INFO_RECEIVED','ITEM_DATA_LOAD_RESULT'}) do pcall(itemEvents.RegisterEvent,itemEvents,event) end
itemEvents:SetScript('OnEvent',function(_,_,id,success)
    if pendingItems[id] and success~=false then
        pendingItems[id]=nil
        itemDataRevision=itemDataRevision+1
        changed('itemData')
        OldKraken:Fire('WORKSHOP_ITEM_DATA_CHANGED')
    end
end)
local masterRecipeCountCache={rev=-1,itemRev=-1,counts={}}
local function countCachedMasterRecipes(ownerName, profession)
    local bucket=ownerName and people[ownerName]
    if type(bucket)~='table' then return 0 end
    if masterRecipeCountCache.rev~=indexRevision or masterRecipeCountCache.itemRev~=itemDataRevision then
        masterRecipeCountCache={rev=indexRevision,itemRev=itemDataRevision,counts={}}
    end
    local key=ownerName..'\001'..(profession or 0)
    local cached=masterRecipeCountCache.counts[key]
    if cached~=nil then return cached end
    local count=0
    for _,r in pairs(bucket) do
        if validRecord(r) and (not profession or r.profession==profession) and not isBindOnPickup(r) then
            count=count+1
        end
    end
    masterRecipeCountCache.counts[key]=count
    return count
end
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
    if type(C_TradeSkillUI)~='table' or type(C_TradeSkillUI.GetRecipeSchematic)~='function' then return T('Матеріали: дані гри недоступні.'),{} end
    local ok,schematic=pcall(C_TradeSkillUI.GetRecipeSchematic,r.recipe,false)
    if not ok or not usable(schematic,'table') or not usable(schematic.reagentSlotSchematics,'table') then return T('Матеріали: гра не надала даних для цього рецепта.'),{} end
    local items={}
    for _,slot in ipairs(schematic.reagentSlotSchematics) do
        if #items>=8 then items[#items+1]={text='…'}; break end
        if usable(slot,'table') and usable(slot.reagents,'table') then
            local reagent=slot.reagents[1]; local id=usable(reagent,'table') and reagent.itemID
            if integer(id,1,100000000) then
                local amount=integer(slot.quantityRequired,1,10000) and slot.quantityRequired or 1
                local getCount=type(C_Item)=='table' and C_Item.GetItemCount or GetItemCount
                local countText=''
                if type(getCount)=='function' then
                    local gotBags,bags=pcall(getCount,id)
                    if gotBags and integer(bags,0,10000000) then
                        local gotTotal,total=pcall(getCount,id,true)
                        local totalCount=(gotTotal and integer(total,0,10000000)) and total or bags
                        local bank=math.max(0,totalCount-bags)
                        local color=totalCount>=amount and '|cff69dc8c' or (totalCount>0 and '|cffffd36b' or '|cff9aa5b1')
                        countText=bank>0 and (' · '..color..T('є: ')..bags..' (+'..bank..T(' банк)|r')) or (' · '..color..T('у сумках: ')..bags..'|r')
                    end
                end
                items[#items+1]={id=id,text=Recipes:ItemLabel(id)..' |cffffd36b×'..amount..'|r'..countText}
            end
        end
    end
    if #items==0 then return T('Матеріали: гра не надала даних для цього рецепта.'),{} end
    return T('Матеріали:'),items
end
local function hideDetailMasterRows()
    if not frame then return end
    for _,row in ipairs(frame.detailMasterRows or {}) do row.masterName=nil; row.masterOnline=nil; row:Hide() end
    if frame.detailExtraMasters then frame.detailExtraMasters:SetText(''); frame.detailExtraMasters:Hide() end
end
local function resizeInfo()
    if frame and frame.infoContent then
        local rowsHeight=0
        for _,row in ipairs(frame.reagentRows or {}) do if row:IsShown() then rowsHeight=rowsHeight+26 end end
        local mastersHeight=0
        for _,row in ipairs(frame.detailMasterRows or {}) do if row:IsShown() then mastersHeight=mastersHeight+18 end end
        if frame.detailExtraMasters and frame.detailExtraMasters:IsShown() then
            mastersHeight=mastersHeight+(frame.detailExtraMasters:GetStringHeight() or 14)+4
        end
        local reagents=frame.embedded and (frame.detailReagents:GetStringHeight()+rowsHeight+24) or 0
        frame.infoContent:SetHeight(math.max(frame.embedded and 262 or 110,frame.detailInfo:GetStringHeight()+mastersHeight+reagents+8))
    end
end
local function renderBody()
    if not frame or not frame:IsShown() then return end
    local online,classes=onlineIndex(); local list={}; local grouped={}
    local mastersView=tab=='masters' and not selectRecipe
    local function hideReagentRows()
        for _,row in ipairs(frame.reagentRows or {}) do row.itemID=nil; row:Hide() end
    end
    local filter=textFilter(frame.query:GetText())
    if frame.queryHint then
        frame.queryHint:SetText(mastersView and T('Пошук майстра за ім’ям') or T('Пошук рецепта або предмета'))
        frame.queryHint:SetShown((frame.query:GetText() or '') == '')
    end
    if OldKraken.BindGuildTitle then OldKraken.BindGuildTitle(frame, professionContext and professionNames[professionContext] or T('Пошук рецептів')) end
    frame.searchLabel:SetText(selectRecipe and T('Фільтр за професією') or (mastersView and T('Пошук майстра за ім’ям') or T('Пошук рецепта або предмета')))
    frame.searchLabel:SetShown(not frame.embedded)
    if professionContext then
        frame.status:SetText(viewOwner and (T('Рецепти майстра: ')..viewOwner..T(' · дані можуть бути неповними.')) or T('Дані можуть бути неповними або застарілими.'))
    end
    frame.recipeTab:SetShown(not frame.embedded and professionContext~=nil and not selectRecipe)
    frame.masterTab:SetShown(not frame.embedded and professionContext~=nil and not selectRecipe)
    frame.recipeTab.activeBar:SetShown(not frame.embedded and professionContext~=nil and tab=='recipes' and not selectRecipe)
    frame.masterTab.activeBar:SetShown(not frame.embedded and professionContext~=nil and tab=='masters' and not selectRecipe)
    if frame.embedded and OldKraken.Workshop then OldKraken.Workshop:UpdateTabs() end
    if frame.embedded then frame.context:SetText(selectRecipe and T('Оберіть рецепт для замовлення') or (professionContext and professionNames[professionContext] or (mastersView and T('Усі професії') or T('Усі рецепти')))) end
    frame.masterRecipes:SetShown(mastersView and selectedMaster~=nil)
    frame.cancelPick:SetShown(selectRecipe~=nil)
    frame.pickProfession:SetShown(selectRecipe~=nil)
    local showTypeFilter=not mastersView and (frame.embedded or not selectRecipe)
    local ctxKey=typeContextKey()
    if ctxKey~=lastTypeContextKey then
        lastTypeContextKey=ctxKey
        selectedType='all'
    end
    if frame.typeFilter then
        frame.typeFilter:ClearAllPoints()
        if frame.embedded then
            frame.typeFilter:SetPoint('TOPLEFT',frame,'TOPLEFT',selectRecipe and 638 or 446,-61)
        else
            frame.typeFilter:SetPoint('TOPLEFT',frame,'TOPLEFT',439,-71)
        end
        frame.typeFilter:SetShown(showTypeFilter)
        if showTypeFilter then
            local _,presentTypes,ready=ensureAvailableTypes()
            if ready and availableTypeCache.key==ctxKey and selectedType~='all' and not presentTypes[selectedType] then selectedType='all' end
            updateTypeFilterText()
        end
    end
    local showOnlineOnly=not selectRecipe and not viewOwner
    if frame.onlineOnly then
        frame.onlineOnly:ClearAllPoints()
        if frame.embedded then
            frame.onlineOnly:SetPoint('TOPLEFT',frame,'TOPLEFT',showTypeFilter and 654 or 462,-61)
        else
            frame.onlineOnly:SetPoint('TOPLEFT',frame,'TOPLEFT',showTypeFilter and 638 or 455,-74)
        end
        frame.onlineOnly:SetShown(showOnlineOnly)
        if showOnlineOnly then
            if frame.onlineOnly.SetActive then
                frame.onlineOnly:SetActive(mastersOnline)
                if frame.onlineOnly.SetDotColor then frame.onlineOnly:SetDotColor(mastersOnline and 'success' or 'neutral') end
            end
            frame.onlineOnly:SetText(mastersOnline and T('Лише онлайн: так') or T('Лише онлайн: ні'))
        end
    end
    local perf=OldKraken.perfEnabled and type(debugprofilestop)=='function' and type(OldKraken.PerfRecord)=='function'
    if mastersView then
        local tCollect=perf and debugprofilestop() or nil
        local masters={}
        local workshop=OldKraken.Workshop
        if workshop then
            if type(workshop.GetAllProfessionMasters)=='function' then
                masters=workshop:GetAllProfessionMasters(professionContext or professionNames)
            else
                for id in pairs(professionNames) do
                    if not professionContext or professionContext==id then
                        for _,entry in ipairs(workshop:GetProfessionMasters(id)) do entry.profession=id; masters[#masters+1]=entry end
                    end
                end
            end
        end
        for _,entry in ipairs(masters) do
            if (not viewOwner or entry.name==viewOwner) and (not mastersOnline or entry.name==identity or online[entry.name]==true)
                and (filter=='' or lower(entry.name):find(filter,1,true)) then list[#list+1]=entry end
        end
        if tCollect then OldKraken:PerfRecord('wk.recipes.masters.collect', debugprofilestop() - tCollect, #masters) end
        local tCount=perf and debugprofilestop() or nil
        local hasRecipes={}
        for _,entry in ipairs(list) do
            local k=entry.name..'\001'..(entry.profession or 0)
            if hasRecipes[k]==nil then hasRecipes[k]=countCachedMasterRecipes(entry.name,entry.profession)>0 end
        end
        if tCount then OldKraken:PerfRecord('wk.recipes.masters.counts', debugprofilestop() - tCount, #list) end
        local tSort=perf and debugprofilestop() or nil
        table.sort(list,function(a,b)
            local aOnline=a.name==identity or online[a.name]==true; local bOnline=b.name==identity or online[b.name]==true
            if aOnline~=bOnline then return aOnline end
            local aHas=hasRecipes[a.name..'\001'..(a.profession or 0)]==true
            local bHas=hasRecipes[b.name..'\001'..(b.profession or 0)]==true
            if aHas~=bHas then return aHas end
            if a.name~=b.name then return a.name<b.name end
            return (professionNames[a.profession] or '')<(professionNames[b.profession] or '')
        end)
        if tSort then OldKraken:PerfRecord('wk.recipes.masters.sort', debugprofilestop() - tSort, #list) end
        offset=math.max(0,math.min(offset,math.max(0,math.ceil(#list/PAGE_SIZE)-1)))
        frame.page:SetText((offset+1)..' / '..math.max(1,math.ceil(#list/PAGE_SIZE)))
        frame.count:SetText(T('Майстрів: ')..#list..T(' · рівень і дата за останніми доступними даними'))
        local tRows=perf and debugprofilestop() or nil
        for i,row in ipairs(rows) do
            local entry=list[offset*PAGE_SIZE+i]
            if entry then
                local _,icon=OldKraken.Workshop:ProfessionInfo(entry.profession)
                row.entry=entry; row.icon:SetTexture(icon); row.name:SetText(playerLabel(entry.name,classes))
                local level=entry.rank and entry.maximum and (entry.rank..'/'..entry.maximum) or T('рівень невідомий')
                local state=statusLabel(entry.name,online)
                local dated=integer(entry.timestamp,1,GetServerTime()+600)
                local stale=dated and GetServerTime()-entry.timestamp>604800
                row.meta:SetText((professionContext and '' or professionNames[entry.profession]..' · ')..(stale and T('|cffffb347застаріло|r · ') or (not dated and T('дата невідома · ') or ''))..level..' · '..state..(entry.relayed and T(' · через гільдію') or ''))
                if OldKraken.UIStyle.ApplySelection then
                    OldKraken.UIStyle.ApplySelection(row, selectedMaster and selectedMaster.name==entry.name and selectedMaster.profession==entry.profession)
                    row:UnlockHighlight()
                elseif selectedMaster and selectedMaster.name==entry.name and selectedMaster.profession==entry.profession then row:LockHighlight() else row:UnlockHighlight() end
                row:Show()
            else row.entry=nil; row:UnlockHighlight(); row:Hide() end
        end
        if tRows then OldKraken:PerfRecord('wk.recipes.masters.rows', debugprofilestop() - tRows, #rows) end
        local tDetail=perf and debugprofilestop() or nil
        frame.detailIcon:SetShown(selectedMaster~=nil); frame.order:Hide()
        hideDetailMasterRows()
        frame.whisper:SetShown(selectedMaster~=nil and selectedMaster.name~=identity and online[selectedMaster.name]==true)
        if selectedMaster then
            local _,icon=OldKraken.Workshop:ProfessionInfo(selectedMaster.profession)
            frame.detailIcon:SetTexture(icon); frame.detailTitle:SetText(playerLabel(selectedMaster.name,classes))
            local level=selectedMaster.rank and selectedMaster.maximum and (selectedMaster.rank..'/'..selectedMaster.maximum) or T('невідомий')
            local state=statusLabel(selectedMaster.name,online)
            local dated=integer(selectedMaster.timestamp,1,GetServerTime()+600)
            local updated=dated and (date('%d.%m.%Y %H:%M',selectedMaster.timestamp)..(GetServerTime()-selectedMaster.timestamp>604800 and T(' · |cffffb347застаріло|r') or '')) or T('невідомо')
            local cachedCount=countCachedMasterRecipes(selectedMaster.name,selectedMaster.profession)
            local cacheLine=cachedCount>0 and (T('\nЗбережено рецептів: ')..cachedCount) or T('\n|cffffb347Рецепти ще не синхронізовані|r')
            frame.detailInfo:SetText(professionNames[selectedMaster.profession]..T('\nРівень: ')..level..T('\nСтатус: ')..state..T('\nОновлено: ')..updated..(selectedMaster.relayed and T('\nОтримано через гільдію') or '')..cacheLine)
            frame.detailReagents:SetText(''); hideReagentRows()
        else
            frame.detailTitle:SetText(T('Оберіть майстра')); frame.detailInfo:SetText(T('Виберіть майстра зі списку.')); frame.detailReagents:SetText(''); hideReagentRows()
        end
        resizeInfo()
        if tDetail then OldKraken:PerfRecord('wk.recipes.masters.detail', debugprofilestop() - tDetail) end
        return
    end
    local tFilter=perf and debugprofilestop() or nil
    local filterScanned=0
    local list,grouped,groupCounts={},{},{}
    local byRecipe=not selectRecipe and not viewOwner and not (filter and (filter:find('^item:') or filter:find('^recipe:')))
    for _,entry in pairs(resultSet) do
        if perf then filterScanned=filterScanned+1 end
        if validRecord(entry.record) and (not viewOwner or entry.owner==viewOwner) and (not professionContext or entry.record.profession==professionContext)
            and (not selectRecipe or ((pickerProfession==0 or entry.record.profession==pickerProfession) and OldKraken.WorkshopOrders and OldKraken.WorkshopOrders:SupportsProfession(entry.record.profession)))
            and not isBindOnPickup(entry.record)
            and (not showTypeFilter or selectedType=='all' or matchesRecipeType(classifyRecipe(entry.record),selectedType))
            and (selectRecipe or viewOwner or not mastersOnline or entry.owner==identity or online[entry.owner]==true)
            and matchesFilter(entry.record,filter) then
            if byRecipe then
                local id=entry.record.recipe; local old=grouped[id]
                groupCounts[id]=(groupCounts[id] or 0)+1
                local other=entry.owner~=identity
                local oldOther=old and old.owner~=identity
                if not old or (other and not oldOther) or (other==oldOther and ((online[entry.owner] and not online[old.owner]) or ((online[entry.owner] and true or false)==(online[old.owner] and true or false) and entry.record.seen>old.record.seen))) then grouped[id]=entry end
            else list[#list+1]=entry end
        end
    end
    if byRecipe then for _,entry in pairs(grouped) do list[#list+1]=entry end end
    if tFilter then OldKraken:PerfRecord('wk.recipes.render.filter', debugprofilestop() - tFilter, filterScanned) end
    local tSort=perf and debugprofilestop() or nil
    local sortNames={}
    for i=1,#list do
        local entry=list[i]
        sortNames[entry]=displayRecipeName(entry.record)
    end
    table.sort(list,function(a,b) local an,bn=sortNames[a],sortNames[b]; if an~=bn then return an<bn end return a.owner<b.owner end)
    if tSort then OldKraken:PerfRecord('wk.recipes.render.sort', debugprofilestop() - tSort, #list) end
    offset=math.max(0,math.min(offset,math.max(0,math.ceil(#list/PAGE_SIZE)-1)))
    frame.page:SetText((offset+1)..' / '..math.max(1,math.ceil(#list/PAGE_SIZE)))
    frame.count:SetText(T('Знайдено: ')..#list..T(' · результати можуть бути застарілими або неповними'))
    local indexReady=indexedRevision==indexRevision
    if not indexReady then ensureRecipeIndex() end
    local tRows=perf and debugprofilestop() or nil
    for i,row in ipairs(rows) do
        local entry=list[offset*PAGE_SIZE+i]
        if entry then
            local r=entry.record; row.entry=entry
            row.icon:SetTexture(recipeIcon(r))
            row.name:SetText(displayRecipeName(r))
            local needIndex=byRecipe and (r.item or 0)>0 and not indexReady
            local rowMasters=(byRecipe and not needIndex) and Recipes:FindMasters(r.item,r.recipe,r.profession) or nil
            local totalMasters=byRecipe and math.max(groupCounts[r.recipe] or 1, rowMasters and #rowMasters or 0) or 1
            if needIndex then
                row.meta:SetText(professionNames[r.profession]..' · '..T('|cff9ba9bcОновлення індексу майстрів…|r'))
            elseif byRecipe and totalMasters>1 then
                local onCount=0
                for _,m in ipairs(rowMasters or {}) do if online[m.name] then onCount=onCount+1 end end
                local onText=onCount>0 and ('|cff68d98c'..onCount..T(' онлайн|r')) or T('|cff9ba9bcофлайн|r')
                local mWord=OldKraken.Workshop and OldKraken.Workshop.PluralUk and OldKraken.Workshop:PluralUk(totalMasters,T('майстер'),T('майстри'),T('майстрів')) or T('майстрів')
                row.meta:SetText(professionNames[r.profession]..' · '..totalMasters..' '..mWord..' · '..onText)
            else
                row.meta:SetText((selectRecipe and entry.owner==identity and T('|cffffb347Ваш рецепт|r · ') or '')..(GetServerTime()-r.seen>604800 and T('|cffffb347застаріло|r · ') or '')..playerLabel(entry.owner,classes)..' · '..professionNames[r.profession]..' · '..statusLabel(entry.owner,online))
            end
            if OldKraken.UIStyle.ApplySelection then
                OldKraken.UIStyle.ApplySelection(row, selectedEntry and selectedEntry.owner==entry.owner and selectedEntry.record.recipe==r.recipe)
                row:UnlockHighlight()
            elseif selectedEntry and selectedEntry.owner==entry.owner and selectedEntry.record.recipe==r.recipe then row:LockHighlight() else row:UnlockHighlight() end
            row:Show()
        else row.entry=nil; row:UnlockHighlight(); row:Hide() end
    end
    if tRows then OldKraken:PerfRecord('wk.recipes.render.rows', debugprofilestop() - tRows, #rows) end
    local tDetail=perf and debugprofilestop() or nil
    local entry=selectedEntry; local r=entry and entry.record
    frame.detailIcon:SetShown(r~=nil)
    if r then
        frame.detailIcon:SetTexture(recipeIcon(r))
        frame.detailTitle:SetText(displayRecipeName(r))
        local detailNeedIndex=(r.item or 0)>0 and not indexReady
        local masters=not detailNeedIndex and Recipes:FindMasters(r.item,r.recipe,r.profession) or {}
        if not selectRecipe and not viewOwner and mastersOnline then
            local onlineMasters={}
            for _,m in ipairs(masters) do
                if m.name==identity or online[m.name]==true then onlineMasters[#onlineMasters+1]=m end
            end
            masters=onlineMasters
        end
        table.sort(masters,function(a,b) if (online[a.name] and true or false)~=(online[b.name] and true or false) then return online[a.name] and true or false end return a.name<b.name end)
        if viewOwner~=nil then
            selectedRecipeMaster=viewOwner~=identity and viewOwner or nil
        elseif detailNeedIndex then
        elseif #masters==1 then
            selectedRecipeMaster=masters[1].name~=identity and masters[1].name or nil
        else
            local foundSelected=false
            for _,m in ipairs(masters) do
                if m.name==selectedRecipeMaster and m.name~=identity then foundSelected=true; break end
            end
            if not foundSelected then selectedRecipeMaster=nil end
        end
        local showWhisper=not detailNeedIndex and selectedRecipeMaster~=nil and selectedRecipeMaster~=identity
        local showOrder=entry.owner~=identity and OldKraken.WorkshopOrders and OldKraken.WorkshopOrders:SupportsProfession(r.profession) or false
        frame.whisper:SetShown(showWhisper)
        frame.order:SetShown(showOrder)
        if showOrder then
            frame.order:ClearAllPoints()
            if frame.embedded then
                frame.order:SetPoint('TOPLEFT',frame,'TOPLEFT',showWhisper and 658 or 514,-474)
                frame.order:SetWidth(showWhisper and 226 or 370)
            else
                frame.order:SetPoint('TOPLEFT',frame,'TOPLEFT',showWhisper and 570 or 450,-410)
                frame.order:SetWidth(showWhisper and 120 or 240)
            end
        end
        if detailNeedIndex then
            frame.detailInfo:SetText(professionNames[r.profession]..T(' · Збережено: ')..date('%d.%m.%Y',r.seen)..(GetServerTime()-r.seen>604800 and T(' · застаріло') or '')..T('\n\nМайстри: оновлення індексу…'))
        else
            frame.detailInfo:SetText(professionNames[r.profession]..T(' · Збережено: ')..date('%d.%m.%Y',r.seen)..(GetServerTime()-r.seen>604800 and T(' · застаріло') or '')..T('\n\nМайстри: ')..#masters..(#masters==0 and T('\nНемає даних') or ''))
        end
        local shownMasters=math.min(#masters,5)
        local colors=OldKraken.UIStyle and OldKraken.UIStyle.Colors
        local selColor=(colors and colors.sel) or {0.102,0.141,0.302,1}
        for i,row in ipairs(frame.detailMasterRows or {}) do
            local m=i<=shownMasters and masters[i] or nil
            if m then
                row.masterName=m.name
                row.masterOnline=online[m.name]==true
                row.label:SetText(playerLabel(m.name,classes)..' · '..statusLabel(m.name,online)..(GetServerTime()-m.seen>604800 and T(' · |cffffb347застаріло|r') or '')..(m.name==identity and T(' · |cffffd36bви|r') or ''))
                if row.bg then
                    row.bg:SetShown(m.name==selectedRecipeMaster)
                    if m.name==selectedRecipeMaster and row.bg.SetColorTexture then row.bg:SetColorTexture(selColor[1],selColor[2],selColor[3],0.65) end
                end
                row:Show()
            else
                row.masterName=nil
                row.masterOnline=nil
                if row.bg then row.bg:Hide() end
                row:Hide()
            end
        end
        local anchorBelow=shownMasters>0 and frame.detailMasterRows and frame.detailMasterRows[shownMasters] or frame.detailInfo
        local extraParts={}
        if #masters>5 then extraParts[#extraParts+1]=T('… та ще ')..(#masters-5) end
        if entry.owner==identity then extraParts[#extraParts+1]=T('Це ваш рецепт. Оберіть рецепт іншого майстра, щоб створити замовлення.') end
        if frame.detailExtraMasters then
            if #extraParts>0 then
                frame.detailExtraMasters:ClearAllPoints()
                frame.detailExtraMasters:SetPoint('TOPLEFT',anchorBelow,'BOTTOMLEFT',0,-2)
                frame.detailExtraMasters:SetText(table.concat(extraParts,'\n'))
                frame.detailExtraMasters:Show()
                anchorBelow=frame.detailExtraMasters
            else
                frame.detailExtraMasters:SetText(''); frame.detailExtraMasters:Hide()
            end
        end
        if frame.embedded and frame.detailReagents then
            frame.detailReagents:ClearAllPoints()
            frame.detailReagents:SetPoint('TOPLEFT',anchorBelow,'BOTTOMLEFT',0,-10)
        end
        local header,items=reagentEntries(r)
        frame.detailReagents:SetText(header)
        for i,row in ipairs(frame.reagentRows or {}) do
            local item=items[i]
            if item then row.itemID=item.id; row.label:SetText(item.text); row:Show()
            else row.itemID=nil; row:Hide() end
        end
    else
        frame.whisper:Hide(); frame.order:Hide()
        hideDetailMasterRows()
        if #list==0 and viewOwner then
            if countCachedMasterRecipes(viewOwner,professionContext)==0 then
                frame.detailTitle:SetText(T('Рецепти не синхронізовані'))
                if viewOwner==identity then
                    frame.detailInfo:SetText(T('Відкрийте вікно цієї професії в грі, щоб аддон зберіг ваші рецепти.'))
                elseif online[viewOwner] then
                    frame.detailInfo:SetText(T('У локальному кеші ще немає рецептів ')..viewOwner..T('. Якщо майстер має аддон і відкривав професію, дані підтягнуться під час синхронізації.'))
                else
                    frame.detailInfo:SetText(T('У локальному кеші ще немає рецептів ')..viewOwner..T(', а сам гравець зараз офлайн.'))
                end
            else
                frame.detailTitle:SetText(T('Нічого не знайдено'))
                frame.detailInfo:SetText(T('За поточним пошуком або фільтром типу рецептів не знайдено.'))
            end
        elseif #list==0 and not selectRecipe and mastersOnline then
            frame.detailTitle:SetText(T('Нічого не знайдено'))
            frame.detailInfo:SetText(T('Серед майстрів онлайн рецептів не знайдено. Вимкніть фільтр «Лише онлайн», щоб побачити всі збережені рецепти.'))
        else
            frame.detailTitle:SetText(T('Оберіть рецепт')); frame.detailInfo:SetText(T('Перегляньте збережені рецепти або знайдіть предмет.'))
        end
        frame.detailReagents:SetText(''); hideReagentRows()
    end
    resizeInfo()
    if tDetail then OldKraken:PerfRecord('wk.recipes.render.detail', debugprofilestop() - tDetail) end
end
render=function(source)
    local perf = OldKraken.perfEnabled and type(OldKraken.PerfRecord) == 'function'
    if perf then OldKraken:PerfRecord('wk.recipes.rnd.' .. (source or 'direct'), 0) end
    local t0 = perf and type(debugprofilestop) == 'function' and debugprofilestop() or nil
    activeItemNames, activeSpellNames, activeDisplayNames, renderApiCalls = {}, {}, {}, 0
    local ok, err = pcall(renderBody)
    local calls = renderApiCalls
    activeItemNames, activeSpellNames, activeDisplayNames, renderApiCalls = nil, nil, nil, 0
    if not ok then error(err) end
    if t0 then OldKraken:PerfRecord('wk.recipes.render', debugprofilestop() - t0, calls) end
end
local function switchTab(nextTab)
    if tab==nextTab then return end
    if temporaryProfessionContext and nextTab=='masters' then
        professionContext=nil
        temporaryProfessionContext=false
    end
    local key=professionContext or 0
    local states=tabStates[key] or {}; tabStates[key]=states
    states[tab]={query=frame.query:GetText() or '',offset=offset,owner=viewOwner,
        selected=selectedEntry,master=selectedMaster,online=mastersOnline}
    local saved=states[nextTab] or {}
    tab=nextTab
    viewOwner,selectedEntry,selectedMaster=saved.owner,saved.selected,saved.master
    selectedRecipeMaster=nil
    offset=saved.offset or 0
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
    if OldKraken.BindGuildTitle then OldKraken.BindGuildTitle(f, T('Пошук рецептів')) end
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
    f.recipeTab=button(f,T('Рецепти'),20,-38,120,function() switchTab('recipes') end)
    f.masterTab=button(f,T('Майстри'),148,-38,120,function() switchTab('masters') end)
    for _,item in ipairs({f.recipeTab,f.masterTab}) do
        item.activeBar=item:CreateTexture(nil,'ARTWORK'); item.activeBar:SetPoint('BOTTOMLEFT',item,'BOTTOMLEFT',2,1); item.activeBar:SetSize(116,2)
        item.activeBar:SetColorTexture(unpack(OldKraken.UIStyle.Colors.brandGold))
    end
    f.query=CreateFrame('EditBox',nil,f,'InputBoxTemplate'); OldKraken.UIStyle.Input(f.query)
    f.query:SetSize(300,34); f.query:SetPoint('TOPLEFT',f,'TOPLEFT',24,-74); f.query:SetAutoFocus(false); f.query:SetTextInsets(8,8,0,0)
    f.query:SetText('')
    f.queryHint=f.query:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    f.queryHint:SetPoint('LEFT',f.query,'LEFT',10,0); f.queryHint:SetText(T('Пошук рецепта або предмета'))
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
    f.searchButton=button(f,T('Знайти'),335,-74,105,submitSearch,'primary',{rounded=true,height=34})
    if OldKraken.UIStyle.Chip then
        f.onlineOnly = OldKraken.UIStyle.Chip(f, T('Лише онлайн: ні'), {dot = 'success', width = 170, height = 34, rounded = true})
        f.onlineOnly:SetPoint('TOPLEFT', f, 'TOPLEFT', 455, -74)
        f.onlineOnly:SetScript('OnClick', function() mastersOnline=not mastersOnline; selectedEntry=nil; selectedRecipeMaster=nil; selectedMaster=nil; offset=0; render() end)
    else
        f.onlineOnly=button(f,T('Лише онлайн: ні'),455,-74,160,function() mastersOnline=not mastersOnline; selectedEntry=nil; selectedRecipeMaster=nil; selectedMaster=nil; offset=0; render() end,nil,{rounded=true,height=34})
    end
    f.pickProfession=CreateFrame('Frame','OldKrakenRecipePickerProfession',f,'UIDropDownMenuTemplate'); OldKraken.UIStyle.Dropdown(f.pickProfession,{rounded=true})
    f.pickProfession:SetPoint('TOPLEFT',f,'TOPLEFT',439,-71); UIDropDownMenu_SetWidth(f.pickProfession,parent and 150 or 160)
    UIDropDownMenu_Initialize(f.pickProfession,function(_,level)
        local ids={0}; for id in pairs(professionNames) do if OldKraken.WorkshopOrders and OldKraken.WorkshopOrders:SupportsProfession(id) then ids[#ids+1]=id end end
        table.sort(ids,function(a,b) if a==b then return false elseif a==0 then return true elseif b==0 then return false end; return professionNames[a]<professionNames[b] end)
        for _,id in ipairs(ids) do
            local value=id; local info=UIDropDownMenu_CreateInfo(); info.text=value==0 and T('Усі професії') or professionNames[value]; info.value=value; info.checked=pickerProfession==value
            info.func=function() pickerProfession=value; selectedType='all'; offset=0; UIDropDownMenu_SetText(f.pickProfession,info.text); addCached('',textFilter(f.query:GetText()),pickerProfession); render() end
            UIDropDownMenu_AddButton(info,level)
        end
    end)
    f.pickProfession:Hide()
    f.typeFilter=CreateFrame('Frame','OldKrakenRecipeTypeFilter',f,'UIDropDownMenuTemplate'); OldKraken.UIStyle.Dropdown(f.typeFilter,{rounded=true})
    local menuWidth=parent and 170 or 160
    f.typeFilter:SetPoint('TOPLEFT',f,'TOPLEFT',parent and 446 or 439,parent and -61 or -71); UIDropDownMenu_SetWidth(f.typeFilter,menuWidth)
    UIDropDownMenu_Initialize(f.typeFilter,function(_,level,menuList)
        level=level or 1
        local function applyType(value)
            selectedType=value; offset=0; selectedEntry=nil
            updateTypeFilterText()
            if type(CloseDropDownMenus)=='function' then CloseDropDownMenus() end
            render()
        end
        local types,presentSet,ready=ensureAvailableTypes()
        if not ready then
            if level==1 then
                local allInfo=UIDropDownMenu_CreateInfo()
                allInfo.text=RECIPE_TYPE_LABELS.all; allInfo.value='all'; allInfo.checked=selectedType=='all'; allInfo.minWidth=menuWidth
                allInfo.func=function() applyType('all') end
                UIDropDownMenu_AddButton(allInfo,level)
                local loading=UIDropDownMenu_CreateInfo()
                loading.text=T('Завантаження…'); loading.disabled=true; loading.notCheckable=true; loading.minWidth=menuWidth
                UIDropDownMenu_AddButton(loading,level)
            elseif level==2 and menuList=='armor' then
                local loading=UIDropDownMenu_CreateInfo()
                loading.text=T('Завантаження…'); loading.disabled=true; loading.notCheckable=true; loading.minWidth=140
                UIDropDownMenu_AddButton(loading,level)
            end
            return
        end
        if level==1 then
            for _,typeKey in ipairs(types) do
                local value=typeKey; local info=UIDropDownMenu_CreateInfo()
                info.text=RECIPE_TYPE_LABELS[value] or value; info.value=value
                info.checked=selectedType==value or (value=='armor' and selectedType:sub(1,6)=='armor:')
                info.minWidth=menuWidth
                if value=='armor' then
                    local hasSlots=false
                    for _,slot in ipairs(ARMOR_SLOT_ORDER) do if presentSet[slot] then hasSlots=true; break end end
                    if hasSlots then info.hasArrow=true; info.menuList='armor' end
                end
                info.func=function() applyType(value) end
                UIDropDownMenu_AddButton(info,level)
            end
        elseif level==2 and menuList=='armor' then
            local allArmor=UIDropDownMenu_CreateInfo()
            allArmor.text=T('Уся броня'); allArmor.value='armor'; allArmor.checked=selectedType=='armor'; allArmor.minWidth=140
            allArmor.func=function() applyType('armor') end
            UIDropDownMenu_AddButton(allArmor,level)
            for _,slot in ipairs(ARMOR_SLOT_ORDER) do
                if presentSet[slot] then
                    local value=slot; local info=UIDropDownMenu_CreateInfo()
                    info.text=RECIPE_TYPE_LABELS[value] or value; info.value=value; info.checked=selectedType==value; info.minWidth=140
                    info.func=function() applyType(value) end
                    UIDropDownMenu_AddButton(info,level)
                end
            end
        end
    end)
    UIDropDownMenu_SetText(f.typeFilter,typeFilterLabel('all'))
    local typeToggle=_G['OldKrakenRecipeTypeFilterButton']
    if typeToggle then
        if type(typeToggle.RegisterForClicks)=='function' then typeToggle:RegisterForClicks('LeftButtonUp','RightButtonUp') end
        local origTypeClick=type(typeToggle.GetScript)=='function' and typeToggle:GetScript('OnClick')
        typeToggle:SetScript('OnClick',function(self,mouseButton,down)
            if mouseButton=='RightButton' and selectedType~='all' then
                selectedType='all'; offset=0; selectedEntry=nil
                updateTypeFilterText()
                if type(CloseDropDownMenus)=='function' then CloseDropDownMenus() end
                render()
                return
            end
            if type(origTypeClick)=='function' then origTypeClick(self,mouseButton,down) end
        end)
        typeToggle:SetScript('OnEnter',function(self)
            if GameTooltip and selectedType~='all' then
                GameTooltip:SetOwner(self,'ANCHOR_BOTTOMRIGHT')
                GameTooltip:SetText(T('Активний фільтр: ')..(RECIPE_TYPE_LABELS[selectedType] or selectedType))
                GameTooltip:AddLine(T('Правий клік — скинути фільтр'),0.85,0.85,0.85,true)
                GameTooltip:Show()
            end
        end)
        typeToggle:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
    end
    f.count=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); f.count:SetPoint('TOPLEFT',f,'TOPLEFT',20,-104)
    for i=1,PAGE_SIZE do
        rows[i]=button(f,'',20,-125-(i-1)*26,410,function(self)
            f.infoScroll:SetVerticalScroll(0)
            if self.entry and tab=='masters' and not selectRecipe then selectedMaster=self.entry; render()
            elseif self.entry and selectRecipe then
                if self.entry.owner==identity then chatError(T('Old Kraken: для замовлення оберіть рецепт іншого майстра.')); return end
                local entry=self.entry
                local callback=selectRecipe; Recipes:CancelPicker()
                if OldKraken.UIHub and OldKraken.Workshop then OldKraken.Workshop:Back() else f:Hide() end
                callback(entry.record,entry.owner)
            elseif self.entry then selectedEntry=self.entry; selectedRecipeMaster=nil; render() end
        end)
        rows[i].icon=rows[i]:CreateTexture(nil,'ARTWORK'); rows[i].icon:SetSize(21,21); rows[i].icon:SetPoint('LEFT',rows[i],'LEFT',3,0)
        rows[i].name=rows[i]:CreateFontString(nil,'OVERLAY','GameFontNormal'); rows[i].name:SetPoint('TOPLEFT',rows[i],'TOPLEFT',29,-1); rows[i].name:SetWidth(370); rows[i].name:SetJustifyH('LEFT'); rows[i].name:SetWordWrap(false)
        rows[i].meta=rows[i]:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); rows[i].meta:SetPoint('BOTTOMLEFT',rows[i],'BOTTOMLEFT',29,1); rows[i].meta:SetWidth(370); rows[i].meta:SetJustifyH('LEFT'); rows[i].meta:SetWordWrap(false)
        rows[i]:SetScript('OnEnter',function(self)
            if tab~='masters' and self.entry and self.entry.record then showItemTooltip(self,self.entry.record.item,self.entry.record.recipe) end
        end)
        rows[i]:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
    end
    f.detailIcon=f:CreateTexture(nil,'ARTWORK'); f.detailIcon:SetSize(46,46); f.detailIcon:SetPoint('TOPLEFT',f,'TOPLEFT',450,-128)
    f.detailTitle=f:CreateFontString(nil,'OVERLAY','GameFontNormal'); f.detailTitle:SetPoint('TOPLEFT',f,'TOPLEFT',505,-131); f.detailTitle:SetWidth(220); f.detailTitle:SetJustifyH('LEFT'); f.detailTitle:SetWordWrap(true)
    f.infoScroll=CreateFrame('ScrollFrame','OldKrakenWorkshopRecipesInfoScroll',f,'UIPanelScrollFrameTemplate'); f.infoScroll:SetPoint('TOPLEFT',f,'TOPLEFT',450,-184); f.infoScroll:SetSize(255,110)
    if OldKraken.UIStyle.ScrollBar then OldKraken.UIStyle.ScrollBar(f.infoScroll) end
    local origInfoWheel=type(f.infoScroll.GetScript)=='function' and f.infoScroll:GetScript('OnMouseWheel')
    f.infoScroll:SetScript('OnMouseWheel',function(self,delta)
        if OldKraken.UIHub and OldKraken.UIHub.HandleScaleWheel and OldKraken.UIHub:HandleScaleWheel(delta) then return end
        if type(origInfoWheel)=='function' then origInfoWheel(self,delta)
        elseif type(ScrollFrameTemplate_OnMouseWheel)=='function' then ScrollFrameTemplate_OnMouseWheel(self,delta) end
    end)
    f.infoContent=CreateFrame('Frame',nil,f.infoScroll); f.infoContent:SetSize(245,110); f.infoScroll:SetScrollChild(f.infoContent)
    f.detailInfo=f.infoContent:CreateFontString(nil,'OVERLAY','GameFontHighlight'); f.detailInfo:SetPoint('TOPLEFT'); f.detailInfo:SetWidth(245); f.detailInfo:SetJustifyH('LEFT'); f.detailInfo:SetJustifyV('TOP')
    f.detailMasterRows={}
    for i=1,5 do
        local row=CreateFrame('Button',nil,f.infoContent)
        row:SetSize(245,17)
        row:SetPoint('TOPLEFT',f.detailInfo,'BOTTOMLEFT',0,-2-(i-1)*18)
        row:EnableMouse(true)
        row.bg=row:CreateTexture(nil,'BACKGROUND')
        row.bg:SetAllPoints(row)
        row.bg:SetColorTexture(0.24,0.34,0.68,0.38)
        row.bg:Hide()
        row.label=row:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
        row.label:SetPoint('LEFT',row,'LEFT',4,0)
        row.label:SetWidth(237)
        row.label:SetJustifyH('LEFT')
        row.label:SetWordWrap(false)
        row:SetScript('OnClick',function(self)
            if not self.masterName or self.masterName==identity then return end
            if selectedRecipeMaster==self.masterName then selectedRecipeMaster=nil
            else selectedRecipeMaster=self.masterName end
            render()
        end)
        row:SetScript('OnEnter',function(self)
            if not self.masterName then return end
            if GameTooltip then
                GameTooltip:SetOwner(self,'ANCHOR_TOP')
                if self.masterName==identity then
                    GameTooltip:SetText(T('Це ваш персонаж'))
                else
                    GameTooltip:SetText(self.masterOnline and self.masterName or (self.masterName..T(' (офлайн)')))
                end
                GameTooltip:Show()
            end
        end)
        row:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
        row:Hide()
        f.detailMasterRows[i]=row
    end
    f.detailExtraMasters=f.infoContent:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    f.detailExtraMasters:SetPoint('TOPLEFT',f.detailInfo,'BOTTOMLEFT',0,-94)
    f.detailExtraMasters:SetWidth(245)
    f.detailExtraMasters:SetJustifyH('LEFT')
    f.detailExtraMasters:Hide()
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
    f.whisper=button(f,T('Шепнути'),450,-410,110,function()
        local name=tab=='masters' and selectedMaster and selectedMaster.name or (tab~='masters' and selectedRecipeMaster or nil)
        if name and name~=identity and type(ChatFrame_SendTell)=='function' then ChatFrame_SendTell(name) end
    end,nil,{rounded=true,height=34})
    f.whisper:SetScript('OnEnter',function(self)
        local name=tab=='masters' and selectedMaster and selectedMaster.name or (tab~='masters' and selectedRecipeMaster or nil)
        if GameTooltip and name and name~=identity then
            GameTooltip:SetOwner(self,'ANCHOR_TOP')
            GameTooltip:SetText(T('Шепнути: ')..name)
            GameTooltip:Show()
        end
    end)
    f.whisper:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
    f.order=button(f,T('Замовити'),570,-410,120,function() if selectedEntry and OldKraken.WorkshopOrders then OldKraken.WorkshopOrders:ShowRecipe(selectedEntry.record,selectedEntry.owner) end end,'primary',{rounded=true,height=34})
    f.masterRecipes=button(f,T('Рецепти майстра'),570,-410,160,function()
        if not selectedMaster then return end
        if OldKraken.UIHub and OldKraken.Workshop then OldKraken.Workshop:Navigate('recipes',true) end
        local masterProfession=selectedMaster.profession
        if not professionContext then
            tabStates[0]=tabStates[0] or {}
            tabStates[0].masters={query=f.query:GetText() or '',offset=offset,master=selectedMaster,online=mastersOnline}
        end
        viewOwner=selectedMaster.name; tab='recipes'; selectedEntry=nil; selectedMaster=nil; offset=0; f.query:SetText(''); render()
        if not professionContext then temporaryProfessionContext=true; professionContext=masterProfession; search('prof:'..professionContext); render() end
    end,'primary',{rounded=true,height=34})
    f.previousPage=button(f,'‹',20,-394,44,function() offset=offset-1; render() end,nil,{rounded=true,height=28})
    f.page=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); f.page:SetPoint('TOPLEFT',f,'TOPLEFT',75,-399)
    f.nextPage=button(f,'›',130,-394,44,function() offset=offset+1; render() end,nil,{rounded=true,height=28})
    f.status=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); f.status:SetPoint('TOPLEFT',f,'TOPLEFT',20,-438); f.status:SetWidth(410); f.status:SetJustifyH('LEFT')
    f.status:SetText(scanStatus or T(initialScanStatus))
    f.cancelPick=button(f,T('Скасувати вибір'),570,-438,145,function()
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
        for i,row in ipairs(f.detailMasterRows) do
            row:SetWidth(344); row.label:SetWidth(338)
            row:ClearAllPoints(); row:SetPoint('TOPLEFT',f.detailInfo,'BOTTOMLEFT',0,-2-(i-1)*18)
        end
        f.detailExtraMasters:SetWidth(344)
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
    for _,row in ipairs(f.detailMasterRows) do readableFont(row.label,13) end
    readableFont(f.detailExtraMasters,12)
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
    if not frame then
        local t0 = OldKraken.perfEnabled and type(debugprofilestop) == 'function' and debugprofilestop() or nil
        frame=createWindow(parent)
        if t0 and OldKraken.PerfRecord then OldKraken:PerfRecord('wk.recipes.create', debugprofilestop() - t0) end
    end
    return frame
end
function Recipes:RefreshPanel() render('refreshPanel') end
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
    return {profession=professionContext,tempProf=temporaryProfessionContext,master=selectedMaster,tab=tab,online=mastersOnline,
        selected=selectedEntry,owner=viewOwner,offset=offset,
        results=resultSet,resultQuery=resultQuery,activeQuery=activeQuery,query=frame and frame.query:GetText() or '',status=frame and frame.status:GetText() or ''}
end
function Recipes:RestoreView(state)
    professionContext,temporaryProfessionContext,selectedMaster,tab,mastersOnline=state.profession,state.tempProf==true,state.master,state.tab,state.online
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
local function showRecipes(self,forceNavigation)
    connect(); if not active then chatError(T('Old Kraken: пошук рецептів доступний членам гільдії.')); return end
    if OldKraken.UIHub and OldKraken.Workshop then
        OldKraken.UIHub:ShowPage('workshop')
        if OldKraken.Workshop.currentView=='recipes' and not forceNavigation and not selectRecipe then frame:Show(); render(); return end
        self:CancelPicker()
        OldKraken.Workshop:Navigate('recipes',forceNavigation)
    elseif not frame then frame=createWindow() end
    professionContext,temporaryProfessionContext,selectedMaster,tab,viewOwner,selectRecipe,mastersOnline,selectedType=nil,false,nil,'recipes',nil,nil,false,'all'
    restoringView=true; frame.query:SetText(''); restoringView=false
    addCached('')
    frame:Show(); render('show')
end
function Recipes:Show(forceNavigation)
    local t0 = OldKraken.perfEnabled and type(debugprofilestop) == 'function' and debugprofilestop() or nil
    showRecipes(self,forceNavigation)
    if t0 and OldKraken.PerfRecord then OldKraken:PerfRecord('wk.recipes.show', debugprofilestop() - t0) end
end
function Recipes:ExportSnapshotMeta()
    if not active or not scope or type(people[identity])~='table' then return nil end
    local total=0
    for _,r in pairs(people[identity]) do
        if validRecord(r) then total=total+1; if total>5000 then return nil end end
    end
    for _,r in pairs(scope.recipeTombstones[identity] or {}) do
        if validRecord(r) then total=total+1; if total>5000 then return nil end end
    end
    return scope.recipeVersions[identity],total
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
    indexRevision=indexRevision+1; recipeChanged=true; changed('import'); return true
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
    selectRecipe=nil; selectedEntry=nil; selectedRecipeMaster=nil; viewOwner=nil; professionContext=profession; temporaryProfessionContext=false; selectedMaster=nil; tab='recipes'; mastersOnline=false; selectedType='all'
    if OldKraken.Workshop then OldKraken.Workshop:RefreshNativeProfessions() end
    frame.query:SetText('')
    frame.status:SetText(professionNames[profession]..T(': збережені рецепти та відповіді онлайн-майстрів; список може бути неповним.'))
    search('prof:'..profession); frame:Raise(); render()
end
function Recipes:ShowMemberProfession(name,profession,onBack)
    if not safeText(name,1,128) or not professionNames[profession] then return end
    self:ShowProfession(profession,true)
    if type(onBack)=='function' and OldKraken.Workshop and type(OldKraken.Workshop.navigationStack)=='table' and #OldKraken.Workshop.navigationStack>0 then
        OldKraken.Workshop.navigationStack[#OldKraken.Workshop.navigationStack]={onBack=onBack}
    end
    if active and frame then
        viewOwner=name; selectedEntry=nil
        frame.status:SetText(name..' · '..professionNames[profession]..T(': збережені рецепти; список може бути неповним.'))
        render()
    end
end
function Recipes:Choose(callback,profession)
    if type(callback)~='function' then return end
    self:Show(); if not active or not frame then return end
    selectRecipe=callback; selectedEntry=nil; selectedRecipeMaster=nil; viewOwner=nil; resultSet={}; resultQuery=nil; activeQuery=nil; offset=0; selectedType='all'
    pickerProfession=professionNames[profession] and profession or 0
    restoringView=true; frame.query:SetText(''); restoringView=false
    UIDropDownMenu_SetText(frame.pickProfession,pickerProfession==0 and T('Усі професії') or professionNames[pickerProfession])
    addCached('',nil,pickerProfession)
    frame.status:SetText(T('Оберіть рецепт іншого майстра. Власні рецепти позначено у списку.'))
    frame:Raise(); render()
end
function Recipes:FindMasters(itemID,recipeID,profession)
    local found={}
    if not integer(itemID,0,100000000) or not integer(recipeID,0,100000000) or (itemID==0 and recipeID==0) then return {} end
    if recipeID>0 then
        for name,records in pairs(people) do
            local r=type(records)=='table' and records[recipeID]
            if safeText(name,1,128) and validRecord(r) and (not profession or r.profession==profession) then
                found[name]=math.max(found[name] or 0,r.seen)
            end
        end
    end
    if itemID>0 then
        local stale=indexedRevision~=indexRevision
        local perf=OldKraken.perfEnabled and type(OldKraken.PerfRecord)=='function'
        if stale then
            if perf then OldKraken:PerfRecord('wk.recipes.findMasters.stale', 0) end
            ensureRecipeIndex()
        end
        if indexedRevision==indexRevision then
            local owners=not profession and itemIndex[itemID] or (itemProfessionIndex[itemID] and itemProfessionIndex[itemID][profession])
            for name,seen in pairs(owners or {}) do
                if safeText(name,1,128) then
                    found[name]=math.max(found[name] or 0,seen)
                end
            end
        else
            local tFallback=perf and type(debugprofilestop)=='function' and debugprofilestop() or nil
            local scannedRecords=0
            for name,records in pairs(people) do
                if safeText(name,1,128) and type(records)=='table' then
                    for _,r in pairs(records) do
                        if perf then scannedRecords=scannedRecords+1 end
                        if validRecord(r) and r.item==itemID and (not profession or r.profession==profession) then
                            found[name]=math.max(found[name] or 0,r.seen)
                        end
                    end
                end
            end
            if tFallback then OldKraken:PerfRecord('wk.recipes.findMasters.fallback', debugprofilestop() - tFallback, scannedRecords) end
        end
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
    selectRecipe=nil; selectedEntry=nil; selectedRecipeMaster=nil; viewOwner=nil
    local query=itemID>0 and ('item:'..itemID) or ('recipe:'..recipeID)
    frame.query:SetText(query); frame.status:SetText(T('Відомі майстри; дата показує останнє зчитування рецепта.'))
    search(query); frame:Raise()
end
OldKraken:On('WORKSHOP_PROFESSIONS_CHANGED',function() if tab=='masters' then changed('professions') end end)
OldKraken:On('WORKSHOP_INDEX_CHANGED',function() changed('index') end)

if OldKraken.LocalizeTable then
    OldKraken.LocalizeTable(professionNames)
    OldKraken.LocalizeTable(RECIPE_TYPE_LABELS)
end
