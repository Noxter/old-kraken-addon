local T = OldKraken.Translate or function(text) return text end
local function chatInfo(msg)
    if OldKraken.Print then OldKraken:Print(msg) else print('|cff2ec4b6Old Kraken|r: ' .. tostring(msg or ''):gsub('^|c%x%x%x%x%x%x%x%xOld Kraken|r:%s*', ''):gsub('^Old Kraken:%s*', '')) end
end
local function chatError(msg)
    if OldKraken.PrintError then OldKraken:PrintError(msg) else print('|cffff5555Old Kraken|r: ' .. tostring(msg or ''):gsub('^|c%x%x%x%x%x%x%x%xOld Kraken|r:%s*', ''):gsub('^Old Kraken:%s*', '')) end
end
-- Guild crafting requests; the customer owns the authoritative order state.
local Orders={}
OldKraken.WorkshopOrders=Orders
local comm,codec=OldKraken.Communication,OldKraken.GroupFinder
local professionNames={[171]='Алхімія',[164]='Ковальство',[165]='Шкірництво',[197]='Кравецтво',[202]='Інженерія',[333]='Зачарування',[185]='Кулінарія',[129]='Перша допомога',[186]='Гірництво'}
local professionIDs={171,164,165,197,202,333,185,129,186}
local materialNames={customer='Замовника',crafter='Майстра',mixed='Спільні'}
local statusNames={open='Шукає майстра',assigned='У роботі',delivered='Передано',done='Виконано',cancelled='Скасовано',deleted='Видалено'}
local deadlineNames={[3600]='1 година',[21600]='6 годин',[86400]='Доба',[604800]='Тиждень'}
local professionIcons={[171]=136240,[164]=136241,[165]=136247,[197]=136249,[202]=136243,[333]=136244,[185]=133971,[129]=135966,[186]=136248}
local statusColors={open={0.35,0.88,0.53},assigned={0.40,0.72,1},delivered={1,0.78,0.30},done={0.35,0.88,0.53},cancelled={1,0.42,0.38},expired={1,0.58,0.25}}
local CARDS_PER_PAGE=4
local active,identity,profile,scope,own,observed,intents=false,nil,nil,nil,{}, {}, {}
local dirty,relayDirty,sequence,nextSync,lastQueries,nextDisplay={}, {},0,0,{},0
local requestDirty,paymentDirty,resultDirty,resultRelayDirty={},{},{},{}
local nextRelaySweep=0
local lastSnapshotQuery=-60
local RELAY_LIMIT,RELAY_TTL=1000,2592000
local window,selected,offset,view,profession,materials,deadline,orderRows=nil,nil,0,'all',0,'customer',86400,{}
local statusFilter,professionFilter='all',0
local searchQuery=''
local chosenRecipe
local refresh
OldKraken:On('WORKSHOP_ALERT_SETTING', function() if window and refresh then refresh() end end)
local saveDraft,restoreDraft,clearDraft
local restoringDraft=false
local function recipePlaceholder() return T('Обрати рецепт') end

local function readableFont(text,size,spacing)
    local font = OldKraken.UIStyle and OldKraken.UIStyle.FontPath and OldKraken.UIStyle.FontPath() or text:GetFont()
    if font then text:SetFont(font,size,'OUTLINE') end
    text:SetShadowColor(0,0,0,1); text:SetShadowOffset(1,-1)
    if spacing then text:SetSpacing(spacing) end
end
local function textOK(s,min,max) return type(s)=='string' and #s>=min and #s<=max and not s:find('[%z\1-\31\127]') end
local function int(n,min,max) return type(n)=='number' and n==n and n%1==0 and n>=min and n<=max end
local function orderItemName(id)
    if not int(id,1,100000000) then return nil end
    if OldKraken.WorkshopRecipes and type(OldKraken.WorkshopRecipes.ItemName)=='function' then
        return OldKraken.WorkshopRecipes:ItemName(id)
    end
    if C_Item and type(C_Item.GetItemNameByID)=='function' then
        local ok,value=pcall(C_Item.GetItemNameByID,id); if ok and textOK(value,1,160) then return value end
    end
    if type(GetItemInfo)=='function' then
        local ok,value=pcall(GetItemInfo,id); if ok and textOK(value,1,160) then return value end
    end
    return nil
end
local function recipeOutputItemName(recipeID)
    if not int(recipeID,1,100000000) or type(C_TradeSkillUI)~='table' then return nil end
    if type(C_TradeSkillUI.GetRecipeOutputItemData)=='function' then
        local ok,data=pcall(C_TradeSkillUI.GetRecipeOutputItemData,recipeID)
        if ok and type(data)=='table' then
            if int(data.itemID,1,100000000) then
                return orderItemName(data.itemID) or T('Завантаження назви…')
            end
            if type(data.hyperlink)=='string' then
                local linked=data.hyperlink:match('%[([^%]]+)%]')
                if textOK(linked,1,160) then return linked end
            end
        end
    end
    if type(C_TradeSkillUI.GetRecipeSchematic)=='function' then
        local ok,data=pcall(C_TradeSkillUI.GetRecipeSchematic,recipeID,false)
        if ok and type(data)=='table' and int(data.outputItemID,1,100000000) then
            return orderItemName(data.outputItemID) or T('Завантаження назви…')
        end
    end
    return nil
end
local function displayOrderItem(o)
    if type(o)~='table' then return '' end
    if int(o.itemID,1,100000000) then
        return orderItemName(o.itemID) or T('Завантаження назви…')
    end
    if int(o.recipeID,1,100000000) then
        return recipeOutputItemName(o.recipeID) or T('Назва предмета недоступна')
    end
    return o.item or ''
end
local function key(owner,id) return owner..'\001'..id end
local function nameOK(s) return textOK(s,1,128) end
local function idOK(s) return textOK(s,1,64) and s:match('^[%w%-]+$')~=nil end
local function size(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
local function relayKey(owner,id,actor) return key(owner,id)..'\001'..actor end
local function validAction(action) return action=='offer' or action=='withdraw' or action=='delivered' end
local function validReceipt(result) return result=='ok' or result=='state' or result=='stale' or result=='capacity' or result=='missing' end
local function validRelay(entry,kind)
    if type(entry)~='table' or not nameOK(entry.owner) or not nameOK(entry.actor) or entry.owner==entry.actor or not idOK(entry.id)
        or not int(entry.stored,1,GetServerTime()+600) or GetServerTime()-entry.stored>RELAY_TTL then return false end
    if kind=='payment' then return int(entry.assignment,0,2147483647) and int(entry.amount,1,1000000000) end
    if not validAction(entry.action) or not int(entry.version,1,9000000000000000) or not int(entry.assignment,0,2147483647) then return false end
    if kind=='result' then return validReceipt(entry.result) and int(entry.rev,0,2147483647) end
    return true
end
local function putRelay(target,entry,kind)
    if not validRelay(entry,kind) then return nil end
    local k=relayKey(entry.owner,entry.id,entry.actor); local old=target[k]
    if not old and size(target)>=RELAY_LIMIT then return nil end
    if kind=='payment' then
        if old and (old.assignment>entry.assignment or (old.assignment==entry.assignment and old.amount>=entry.amount)) then return k end
    elseif old and old.version>=entry.version then return k end
    target[k]=entry; return k
end
local function scheduleRelay(scheduled,k)
    local due=GetTime()+math.random(2,20)
    if type(scheduled[k])~='number' or due<scheduled[k] then scheduled[k]=due end
end
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
local changedPending=false
local function changed()
    if changedPending then return end
    if not (window and window:IsShown()) then return end
    local function flush()
        changedPending=false
        if window and window:IsShown() then if refresh then refresh() end end
    end
    if C_Timer and C_Timer.After then changedPending=true; C_Timer.After(0.15,flush) else flush() end
end

local function notify(title,subtitle,k) OldKraken:Fire('WORKSHOP_ORDER_NOTICE',title,subtitle,k) end
local function rewardCopper(o) return (o.reward or 0)*10000+(o.rewardSilver or 0)*100 end
local function formatReward(o)
    local g,s=o.reward or 0,o.rewardSilver or 0
    if g>0 and s>0 then return g..T(' зол. ')..s..T(' ср.') end
    if g==0 and s>0 then return s..T(' ср.') end
    return g..T(' зол.')
end
local function encode(o)
    local fields={o.owner,o.id,o.rev,o.created,o.deadline,o.profession,o.item,o.quantity,o.reward,o.materials,o.note,o.status,o.worker or ''}
    local candidates={}; for name in pairs(o.candidates) do candidates[#candidates+1]=name end; table.sort(candidates)
    fields[#fields+1]=#candidates; for _,name in ipairs(candidates) do fields[#fields+1]=name end
    local ackNames={}; for name in pairs(o.acks or {}) do ackNames[#ackNames+1]=name end; table.sort(ackNames)
    fields[#fields+1]=#ackNames; for _,name in ipairs(ackNames) do fields[#fields+1]=name; fields[#fields+1]=string.format('%.0f',o.acks[name]) end
    fields[#fields+1]=o.itemID or 0; fields[#fields+1]=o.recipeID or 0; fields[#fields+1]=o.paidByWorker or 0; fields[#fields+1]=o.assignment or 0; fields[#fields+1]=o.rewardSilver or 0
    return codec._pack(fields)
end
local function decode(payload,sender,isRelay)
    local f=codec._unpackFields(payload,80); if not f or #f<15 then return nil end
    local owner,id,rev,created,due,prof,item,qty,reward,mats,note,status,worker,n=unpack(f,1,14)
    rev,created,due,prof,qty,reward,n=tonumber(rev),tonumber(created),tonumber(due),tonumber(prof),tonumber(qty),tonumber(reward),tonumber(n)
    local now=GetServerTime()
    if not nameOK(owner) or (not isRelay and owner~=sender) or not idOK(id) or not int(rev,1,2147483647) or not int(created,now-2592000,now+600)
        or not int(due,created+1,created+2592000) or not professionNames[prof] or not textOK(item,1,160) or not int(qty,1,200)
        or not int(reward,0,100000) or not materialNames[mats] or not textOK(note,0,180) or not statusNames[status]
        or (worker~='' and not nameOK(worker)) or not int(n,0,20) or #f<15+n then return nil end
    if (status=='assigned' or status=='delivered' or status=='done') and worker=='' then return nil end
    if status=='open' and worker~='' then return nil end
    local candidates={}
    for i=1,n do local name=f[14+i]; if not nameOK(name) or name==owner or candidates[name] then return nil end; candidates[name]=true end
    local countIndex=15+n; local ackCount=tonumber(f[countIndex]); if not int(ackCount,0,20) then return nil end
    local endIndex=countIndex+ackCount*2
    if #f~=endIndex and #f~=endIndex+2 and #f~=endIndex+3 and #f~=endIndex+4 and #f~=endIndex+5 then return nil end
    local acks={}
    for i=1,ackCount do
        local name,version=f[countIndex+i*2-1],tonumber(f[countIndex+i*2])
        if not nameOK(name) or name==owner or acks[name] or not int(version,1,9000000000000000) then return nil end
        acks[name]=version
    end
    local itemID,recipeID=tonumber(f[endIndex+1] or 0),tonumber(f[endIndex+2] or 0)
    local paidByWorker=tonumber(f[endIndex+3] or 0)
    local assignment=tonumber(f[endIndex+4] or 0)
    local rewardSilver=tonumber(f[endIndex+5] or 0)
    if not int(rewardSilver,0,99) then return nil end
    if not int(itemID,0,100000000) or not int(recipeID,0,100000000) or not int(paidByWorker,0,reward*10000+rewardSilver*100) or not int(assignment,0,rev) then return nil end
    return {owner=owner,id=id,rev=rev,created=created,deadline=due,profession=prof,item=item,itemID=itemID,recipeID=recipeID,quantity=qty,reward=reward,rewardSilver=rewardSilver,materials=mats,note=note,status=status,worker=worker~='' and worker or nil,candidates=candidates,acks=acks,paidByWorker=paidByWorker,assignment=assignment}
end
function Orders:NormalizeMigrationOrder(orderKey, order, requiredOwner)
    if type(order)~='table' or type(order.candidates)~='table' or type(order.acks)~='table' then return nil end
    local encoded,payload=pcall(encode,order)
    if not encoded or type(payload)~='string' then return nil end
    local decoded,valid=pcall(decode,payload,order.owner)
    if not decoded or not valid or orderKey~=key(valid.owner,valid.id)
        or (requiredOwner and valid.owner~=requiredOwner) then return nil end
    if not requiredOwner then
        valid.relayed=order.relayed==true
        valid.ownerRev=valid.relayed and (int(order.ownerRev,0,valid.rev) and order.ownerRev or 0) or valid.rev
    end
    return valid
end
local function persist()
    if not scope then return end
    scope.orderOwners[identity]=own; scope.orderObserved=observed; scope.orderIntents[identity]=intents; scope.orderSequences[identity]=sequence
end
local function get(k) return own[k] or observed[k] end
local function fits(o) local ok,payload=pcall(encode,o); return ok and #payload<=2560 end
local function displayStatus(o)
    if (o.status=='open' or o.status=='assigned') and o.deadline<GetServerTime() then return 'expired' end
    return o.status
end
local function canCraft(o)
    if not OldKraken.Workshop or not OldKraken.Workshop:HasProfession(o.profession) then return false,false end
    if (o.itemID or 0)>0 or (o.recipeID or 0)>0 then
        return OldKraken.WorkshopRecipes and OldKraken.WorkshopRecipes:Knows(o.itemID or 0,o.recipeID or 0),false
    end
    return OldKraken.Workshop and OldKraken.Workshop:HasProfession(o.profession),true
end

local function validRealm(realm)
    if OldKraken.Database and type(OldKraken.Database.IsValidRealm)=='function' then
        return OldKraken.Database:IsValidRealm(realm)
    end
    if type(issecretvalue)=='function' and issecretvalue(realm) then return false end
    return textOK(realm,1,128)
end

local function connect()
    local name=me(); local guild=type(GetGuildInfo)=='function' and GetGuildInfo('player'); local realm=type(GetRealmName)=='function' and GetRealmName()
    if not name or not textOK(guild,1,128) or not validRealm(realm) or not OldKraken.DB then
        active,identity,profile,scope,own,observed,intents,dirty,relayDirty=false,nil,nil,nil,{}, {}, {}, {}, {}
        requestDirty,paymentDirty,resultDirty,resultRelayDirty={},{},{},{}
        if window then window:Hide() end; return
    end
    if OldKraken.Database and type(OldKraken.Database.MigrateWorkshopScope)=='function' then
        OldKraken.Database:MigrateWorkshopScope(realm,guild,false)
    end
    local guildKey=realm..'\001'..guild
    if active and identity==name and profile==guildKey then return end
    local db=OldKraken.DB; if type(db.workshop)~='table' then db.workshop={} end
    if type(db.workshop.guilds)~='table' then db.workshop.guilds={} end
    if type(db.workshop.guilds[guildKey])~='table' then db.workshop.guilds[guildKey]={} end
    scope=db.workshop.guilds[guildKey]
    for _,field in ipairs({'orderOwners','orderObserved','orderIntents','orderSequences','orderRelays','orderDeliveryTallies','orderActionRelays','orderPaymentRelays','orderResults','orderResultRelays','orderDrafts'}) do if type(scope[field])~='table' then scope[field]={} end end
    scope.orderActionRelays={}; scope.orderPaymentRelays={}
    if type(scope.orderDeliveryTallies[name])~='table' then scope.orderDeliveryTallies[name]={} end
    active,identity,profile=true,name,guildKey
    own,observed,intents,dirty,relayDirty={}, {}, {}, {}, {}
    requestDirty,paymentDirty,resultDirty,resultRelayDirty={},{},{},{}
    local function loadOrders(source,target,requireOwner)
        if type(source)~='table' then return end
        for k,o in pairs(source) do
            if size(target)>=100 then break end
            if type(o)=='table' and type(o.candidates)=='table' and type(o.acks)=='table' and nameOK(o.owner) and (not requireOwner or o.owner==identity) then
                local ok,payload=pcall(encode,o); local valid=ok and decode(payload,o.owner)
                if valid and k==key(valid.owner,valid.id) then
                    if not requireOwner then
                        valid.relayed=o.relayed==true
                        valid.ownerRev=valid.relayed and (int(o.ownerRev,0,valid.rev) and o.ownerRev or 0) or valid.rev
                    end
                    target[k]=valid
                end
            end
        end
    end
    loadOrders(scope.orderOwners[name],own,true); loadOrders(scope.orderObserved,observed,false)
    for k,payload in pairs(scope.orderRelays) do
        local o=type(payload)=='string' and #payload<=2560 and decode(payload,nil,true)
        if not o or o.owner==identity or k~=key(o.owner,o.id) then scope.orderRelays[k]=nil end
    end
    local stored=scope.orderIntents[name]
    if type(stored)=='table' then for k,v in pairs(stored) do
        if type(k)=='string' and #k<194 and type(v)=='table' and validAction(v.action) and int(v.version,1,9000000000000000) then
            intents[k]={action=v.action,version=v.version,assignment=int(v.assignment,0,2147483647) and v.assignment or 0,receiptRev=int(v.receiptRev,1,2147483647) and v.receiptRev or nil}
            requestDirty[k]=true
        end
    end end
    for _,config in ipairs({{scope.orderResults,'result',resultDirty},{scope.orderResultRelays,'result',resultRelayDirty}}) do
        local entries,kind,scheduled=config[1],config[2],config[3]; local count=0
        for k,entry in pairs(entries) do
            if count>=RELAY_LIMIT or not validRelay(entry,kind) or k~=relayKey(entry.owner,entry.id,entry.actor) then entries[k]=nil
            else count=count+1 end
        end
    end
    sequence=int(scope.orderSequences[name],0,9000000000000000) and scope.orderSequences[name] or 0
    for k in pairs(own) do dirty[k]=true end
    nextSync,lastQueries,nextRelaySweep,lastSnapshotQuery=0,{},0,-60; persist()
    if window and restoreDraft then restoreDraft() end
    changed()
end
local function create(item,qty,reward,note,recipe,rewardSilver)
    qty,reward=tonumber(qty),tonumber(reward)
    rewardSilver=tonumber(rewardSilver==nil and 0 or (rewardSilver=='' and 0 or rewardSilver))
    if not active or not textOK(item,1,160) or not int(qty,1,200) or not int(reward,0,100000) or not int(rewardSilver,0,99) or not textOK(note,0,180) or not professionNames[profession] then return false end
    if size(own)>=100 then return false end
    local now=GetServerTime(); sequence=math.max(sequence+1,now*1000)
    local id=tostring(now)..'-'..tostring(math.random(100000,999999))..'-'..tostring(sequence%1000000)
    local itemID=recipe and recipe.item or tonumber(item:match('item:(%d+)')) or 0
    local recipeID=recipe and recipe.recipe or 0
    if not int(itemID,0,100000000) or not int(recipeID,0,100000000) then return false end
    local o={owner=identity,id=id,rev=1,created=now,deadline=now+deadline,profession=profession,item=item,itemID=itemID,recipeID=recipeID,quantity=qty,reward=reward,rewardSilver=rewardSilver,materials=materials,note=note,status='open',candidates={},acks={}}
    if not fits(o) then return false end
    local k=key(identity,id); own[k]=o; dirty[k]=true; selected=k; persist(); changed(); return true
end
local function intent(k,action)
    local o=get(k); if not active or not o or o.owner==identity or intents[k] then return false end
    if action=='offer' and not canCraft(o) then return false end
    if action=='delivered' and (not OldKraken.Workshop or not OldKraken.Workshop:HasProfession(o.profession)) then return false end
    if action=='offer' and (o.status~='open' or o.deadline<GetServerTime() or o.candidates[identity]) then return false end
    if action=='withdraw' and not ((o.status=='open' and o.candidates[identity]) or (o.status=='assigned' and o.worker==identity)) then return false end
    if action=='delivered' and not (o.status=='assigned' and o.worker==identity) then return false end
    sequence=math.max(sequence+1,GetServerTime()*1000); intents[k]={action=action,version=sequence,assignment=o.assignment or 0}; requestDirty[k]=true; nextSync=0; persist(); changed(); return true
end
local function ownerAction(k,action,actor)
    local o=own[k]; if not active or not o then return false end
    local oldStatus,oldWorker,oldDeadline,oldCandidates,oldPaid,oldAssignment=o.status,o.worker,o.deadline,o.candidates,o.paidByWorker,o.assignment
    if action=='choose' then
        if o.status~='open' or not o.candidates[actor] or o.deadline<GetServerTime() then return false end
        o.status,o.worker,o.assignment='assigned',actor,o.rev+1
    elseif action=='finish' then if o.status~='delivered' then return false end; o.status='done'
    elseif action=='received' then if o.status~='assigned' and o.status~='delivered' then return false end; o.status='done'
    elseif action=='cancel' then if o.status=='done' or o.status=='cancelled' or o.status=='deleted' then return false end; o.status='cancelled'
    elseif action=='delete' then if o.status=='deleted' then return false end; o.status='deleted'
    elseif action=='reopen' then
        local now=GetServerTime()
        if o.status~='assigned' or o.deadline>=now or now+86400>o.created+2592000 then return false end
        o.status,o.worker,o.deadline,o.candidates,o.paidByWorker,o.assignment='open',nil,now+86400,{},0,0
    else return false end
    o.rev=o.rev+1
    if not fits(o) then o.status,o.worker,o.deadline,o.candidates,o.paidByWorker,o.assignment,o.rev=oldStatus,oldWorker,oldDeadline,oldCandidates,oldPaid,oldAssignment,o.rev-1; return false end
    dirty[k]=true; persist(); changed(); return true
end

local function materialRequirements(o)
    if o.recipeID==0 or type(C_TradeSkillUI)~='table' or type(C_TradeSkillUI.GetRecipeSchematic)~='function' then return nil end
    local ok,result=pcall(function()
        local s=C_TradeSkillUI.GetRecipeSchematic(o.recipeID,false)
        if type(s)~='table' or type(s.reagentSlotSchematics)~='table' then return nil end
        local yield=int(s.quantityMin,1,10000) and s.quantityMin or 1
        local crafts=math.ceil(o.quantity/yield); local need={}
        local basic=type(Enum)=='table' and type(Enum.CraftingReagentType)=='table' and Enum.CraftingReagentType.Basic or 1
        for _,slot in ipairs(s.reagentSlotSchematics) do
            if type(slot)=='table' and (slot.reagentType==nil or slot.reagentType==basic) and type(slot.reagents)=='table' then
                local reagent=slot.reagents[1]; local id=type(reagent)=='table' and reagent.itemID
                if int(id,1,100000000) and int(slot.quantityRequired,1,10000) then need[id]=(need[id] or 0)+slot.quantityRequired*crafts end
            end
        end
        return next(need) and need or nil
    end)
    return ok and result or nil
end
local function take(pool,id,wanted)
    local available=pool[id] or 0; local used=math.max(0,math.min(available,wanted))
    if used>0 then pool[id]=available-used end
    return used
end
local function tallyFor(k,o)
    local all=scope.orderDeliveryTallies[identity]; local tally=all[k]
    if type(tally)~='table' or tally.worker~=o.worker or (tally.assignment or 0)~=(o.assignment or 0) then
        tally={worker=o.worker,assignment=o.assignment or 0,materials={},items=0,money=0}; all[k]=tally
    end
    if type(tally.materials)~='table' then tally.materials={} end
    return tally
end
local function partnerName(value)
    if not nameOK(value) then return nil end
    local base=value:match('^([^%-]+)') or value; local found={}
    for _,source in ipairs({own,observed}) do for _,o in pairs(source) do
        for _,name in ipairs({o.owner,o.worker or ''}) do
            if name~=identity and name~='' and (name==value or name==base) then found[name]=true end
        end
    end end
    local result; for name in pairs(found) do if result and result~=name then return nil end; result=name end
    return result
end
function Orders:RecordExchange(partner,given,received,givenMoney,receivedMoney)
    if not active or not scope then return false end
    partner=partnerName(partner); if not partner then return false end
    local function pool(source)
        local out={}; if type(source)=='table' then for id,n in pairs(source) do if int(id,1,100000000) and int(n,1,1000000) then out[id]=n end end end; return out
    end
    given,received=pool(given),pool(received)
    givenMoney=int(givenMoney,0,1000000000) and givenMoney or 0; receivedMoney=int(receivedMoney,0,1000000000) and receivedMoney or 0
    local list={}
    for _,source in ipairs({own,observed}) do for k,o in pairs(source) do
        if (o.status=='assigned' or o.status=='delivered') and o.worker and ((o.owner==identity and o.worker==partner) or (o.worker==identity and o.owner==partner)) then list[#list+1]={key=k,order=o} end
    end end
    table.sort(list,function(a,b) if a.order.created~=b.order.created then return a.order.created<b.order.created end return a.key<b.key end)
    local updated=false
    for _,entry in ipairs(list) do
        local o=entry.order; local isOwner=o.owner==identity; local tally=tallyFor(entry.key,o); local moved=0
        tally.items=int(tally.items,0,o.quantity) and tally.items or 0
        tally.money=int(tally.money,0,1000000000) and tally.money or 0
        if o.itemID>0 then
            local amount=take(isOwner and received or given,o.itemID,o.quantity-tally.items)
            tally.items=tally.items+amount; moved=moved+amount
        end
        local needs=(o.materials=='customer' or o.materials=='mixed') and materialRequirements(o)
        if needs then for id,need in pairs(needs) do
            local prior=int(tally.materials[id],0,10000000) and tally.materials[id] or 0
            local amount=take(isOwner and given or received,id,math.max(0,need-prior))
            tally.materials[id]=prior+amount; moved=moved+amount
        end end
        local remaining=math.max(0,rewardCopper(o)-tally.money)
        local money=math.min(isOwner and givenMoney or receivedMoney,remaining)
        if money>0 then tally.money=tally.money+money; if isOwner then givenMoney=givenMoney-money else receivedMoney=receivedMoney-money end; moved=moved+money end
        if moved>0 then updated=true end
    end
    if updated then nextSync=0; persist(); changed() end
    return updated
end
local function finalizeExchanges()
    local all=scope.orderDeliveryTallies[identity]
    for k,tally in pairs(all) do
        local o=get(k)
        if type(tally)=='table' and o and o.worker==tally.worker and (tally.assignment or 0)==(o.assignment or 0) and o.itemID>0 and int(tally.items,0,o.quantity) and tally.items>=o.quantity then
            if o.owner==identity and (o.status=='assigned' or o.status=='delivered') and (o.paidByWorker or 0)>=rewardCopper(o) then ownerAction(k,'received')
            elseif o.worker==identity and o.status=='assigned' and not intents[k] then intent(k,'delivered') end
        end
    end
end

local function sameOrder(a,b)
    return a.owner==b.owner and a.id==b.id and a.created==b.created and a.profession==b.profession
        and a.item==b.item and a.itemID==b.itemID and a.recipeID==b.recipeID
        and a.quantity==b.quantity and a.reward==b.reward and (a.rewardSilver or 0)==(b.rewardSilver or 0) and a.materials==b.materials and a.note==b.note
end
local function confirmPending(k,o,direct)
    local pending=intents[k]
    if not pending or not o then return end
    local acknowledged=(o.acks[identity] or 0)>=pending.version
    local relayedConfirmation=pending.receiptRev and o.rev>=pending.receiptRev and acknowledged
    if not ((direct and (acknowledged or o.status=='deleted')) or relayedConfirmation) then return end
    local applied=(pending.action=='offer' and (o.candidates[identity] or o.worker==identity))
        or (pending.action=='withdraw' and not o.candidates[identity] and o.worker~=identity)
        or (pending.action=='delivered' and (o.status=='delivered' or o.status=='done') and o.worker==identity)
    intents[k]=nil; requestDirty[k]=nil
    if not applied and not relayedConfirmation then notify(T('Дію щодо замовлення не виконано'),displayOrderItem(o)..T(' · стан змінився'),k) end
end
local function receiveOrder(sender,payload,isRelay)
    if not active or not nameOK(sender) or sender==identity or type(payload)~='string' or #payload>2560 then return end
    local o=decode(payload,sender,isRelay); if not o or o.owner==identity or (isRelay and sender==o.owner) then return end
    local k=key(o.owner,o.id); local previous=observed[k]
    if previous and not sameOrder(previous,o) then
        if isRelay or not previous.relayed then return end
        local direct=scope.orderRelays[k] and decode(scope.orderRelays[k],nil,true)
        if direct and not sameOrder(direct,o) then return end
    end
    if isRelay then
        if previous and previous.rev>=o.rev then return end
        o.relayed=true; o.ownerRev=previous and (previous.ownerRev or (not previous.relayed and previous.rev) or 0) or 0
    else
        local ownerRev=previous and (previous.ownerRev or (not previous.relayed and previous.rev) or 0) or 0
        if o.rev<ownerRev then return end
        if previous and not previous.relayed and previous.rev==o.rev and encode(previous)~=encode(o) then return end
        o.ownerRev=o.rev
    end
    if not previous and size(observed)>=100 then return end
    if not isRelay then
        scope.orderRelays[k]=payload
    end
    observed[k]=o
    confirmPending(k,o,not isRelay)
    if not isRelay and not previous and o.status=='open' and o.rev==1 and GetServerTime()-o.created<=120 then
        local settings=OldKraken.DB and OldKraken.DB.settings
        local matches=OldKraken.Workshop and OldKraken.Workshop:HasProfession(o.profession)
        local known=OldKraken.WorkshopRecipes and OldKraken.WorkshopRecipes:Knows(o.itemID or 0,o.recipeID or 0)
        local manual=not known
        if type(settings)=='table' and settings.workshopOrderAlerts~=false and matches then
            notify(T('Нове замовлення: ')..displayOrderItem(o),professionNames[o.profession]..' · '..o.owner..(manual and T(' · рецепт не підтверджено') or ''),k)
        end
    elseif previous and o.rev>previous.rev then
        local itemTitle=displayOrderItem(o)
        if o.worker==identity and previous.worker~=identity and o.status=='assigned' then notify(T('Вас обрано майстром'),itemTitle..' · '..o.owner,k)
        elseif previous.worker==identity and previous.status=='assigned' and o.status=='open' then notify(T('Замовлення перевідкрито'),itemTitle..' · '..o.owner,k)
        elseif previous.candidates[identity] and o.status=='assigned' and o.worker~=identity and previous.status=='open' then notify(T('Обрано іншого майстра'),itemTitle..' · '..o.owner,k)
        elseif (previous.worker==identity or previous.candidates[identity]) and (o.status=='cancelled' or o.status=='deleted') and previous.status~='cancelled' and previous.status~='done' and previous.status~='deleted' then notify(T('Замовлення скасовано'),itemTitle..' · '..o.owner,k)
        elseif previous.worker==identity and o.status=='done' and previous.status~='done' then notify(T('Замовлення підтверджено'),itemTitle..' · '..o.owner,k) end
    end
    persist(); changed()
end
comm:RegisterHandler('WORDER',function(sender,_,payload) receiveOrder(sender,payload,false) end)
comm:RegisterHandler('WORELAY',function(sender,_,payload) receiveOrder(sender,payload,true) end)
local function resultPayload(entry)
    return codec._pack({entry.owner,entry.id,entry.actor,entry.action,string.format('%.0f',entry.version),entry.assignment,entry.result,entry.rev})
end
local function rememberResult(request,result,rev)
    local entry={owner=identity,id=request.id,actor=request.actor,action=request.action,version=request.version,
        assignment=request.assignment,result=result,rev=rev or 0,stored=GetServerTime()}
    local k=putRelay(scope.orderResults,entry,'result')
    if k and scope.orderResults[k].version==entry.version then resultDirty[k]=true
    else comm:SendProtocol('WORESULT',resultPayload(entry)) end
end
local function applyRequest(request)
    local sender,action,version,assignment=request.actor,request.action,request.version,request.assignment
    local k=key(identity,request.id); local o=own[k]
    local resultKey=relayKey(identity,request.id,sender)
    local previousResult=scope.orderResults[resultKey]
    if previousResult and previousResult.version==version then
        if previousResult.action==action and previousResult.assignment==assignment then resultDirty[resultKey]=true; if o then dirty[k]=true end end
        return
    end
    if not o then rememberResult(request,'missing'); return end
    if (o.acks[sender] or 0)>=version then
        dirty[k]=true
        -- An older saved order can contain an acknowledgement without its
        -- original outcome. Do not invent a failure for an already applied action.
        return
    end
    -- Do not mutate the order unless its result can be retained for delivery.
    if not previousResult and size(scope.orderResults)>=RELAY_LIMIT then rememberResult(request,'capacity',o.rev); return end
    if (action=='delivered' or (action=='withdraw' and o.status=='assigned' and o.worker==sender)) and assignment~=(o.assignment or 0) then rememberResult(request,'stale',o.rev); return end
    if not o.acks[sender] and size(o.acks)>=20 then rememberResult(request,'capacity',o.rev); return end
    local prevStatus,prevWorker,wasCandidate,prevAck,prevPaid,prevAssignment=o.status,o.worker,o.candidates[sender],o.acks[sender],o.paidByWorker,o.assignment
    local applied=false
    if action=='offer' and o.status=='open' and o.deadline>=GetServerTime() and size(o.candidates)<20 then o.candidates[sender]=true; applied=true
    elseif action=='withdraw' and o.status=='open' then o.candidates[sender]=nil; applied=true
    elseif action=='withdraw' and o.status=='assigned' and o.worker==sender then o.status,o.worker,o.paidByWorker,o.assignment='open',nil,0,0; o.candidates[sender]=nil; applied=true
    elseif action=='delivered' and o.status=='assigned' and o.worker==sender then o.status='delivered'; applied=true end
    o.acks[sender]=version; o.rev=o.rev+1
    if not fits(o) then o.status,o.worker,o.candidates[sender],o.acks[sender],o.paidByWorker,o.assignment,o.rev=prevStatus,prevWorker,wasCandidate,prevAck,prevPaid,prevAssignment,o.rev-1; rememberResult(request,'capacity',o.rev); return end
    dirty[k]=true; rememberResult(request,applied and 'ok' or 'state',o.rev); persist(); changed()
    if action=='offer' and not wasCandidate and o.candidates[sender] then notify(T('Майстер пропонує допомогу'),sender..' · '..displayOrderItem(o),k)
    elseif action=='delivered' and prevStatus=='assigned' and o.status=='delivered' then notify(T('Майстер позначив передачу'),sender..' · '..displayOrderItem(o),k)
    elseif action=='withdraw' and prevWorker==sender and o.status=='open' then notify(T('Майстер відмовився'),sender..' · '..displayOrderItem(o),k) end
end
local function decodeAction(actor,f,offset)
    local owner,id,action,version,assignment=f[offset],f[offset+1],f[offset+2],tonumber(f[offset+3]),tonumber(f[offset+4] or 0)
    local entry={owner=owner,id=id,actor=actor,action=action,version=version,assignment=assignment,stored=GetServerTime()}
    return validRelay(entry,'action') and entry or nil
end
comm:RegisterHandler('WOREQ',function(sender,_,payload)
    if not active or not nameOK(sender) or sender==identity then return end
    local f=codec._unpackFields(payload,5); if not f or (#f~=4 and #f~=5) then return end
    local request=decodeAction(sender,f,1); if not request then return end
    if request.owner==identity then applyRequest(request) end
end)
comm:RegisterHandler('WOACT',function(sender,_,payload)
    -- A relayer cannot prove the identity of the actor claimed in the payload.
end)
local function applyPayment(entry)
    local k=key(identity,entry.id); local o=own[k]
    if not o or o.worker~=entry.actor or entry.assignment~=(o.assignment or 0) or (o.status~='assigned' and o.status~='delivered') or not int(entry.amount,1,rewardCopper(o)) then return end
    if entry.amount<=(o.paidByWorker or 0) then dirty[k]=true; return end
    local old=o.paidByWorker; o.paidByWorker=entry.amount; o.rev=o.rev+1
    if not fits(o) then o.paidByWorker=old; o.rev=o.rev-1; return end
    dirty[k]=true; persist(); changed()
end
comm:RegisterHandler('WOPAY',function(sender,_,payload)
    if not active or not nameOK(sender) or sender==identity then return end
    local f=codec._unpackFields(payload,4); if not f or #f~=4 then return end
    local entry={owner=f[1],id=f[2],actor=sender,assignment=tonumber(f[3]),amount=tonumber(f[4]),stored=GetServerTime()}
    if not validRelay(entry,'payment') then return end
    if entry.owner==identity then applyPayment(entry) end
end)
comm:RegisterHandler('WOPAYR',function(sender,_,payload)
    -- A relayer cannot prove the identity of the worker claimed in the payload.
end)
local function decodeResult(payload)
    local f=codec._unpackFields(payload,8); if not f or #f~=8 then return nil end
    local entry={owner=f[1],id=f[2],actor=f[3],action=f[4],version=tonumber(f[5]),assignment=tonumber(f[6]),result=f[7],rev=tonumber(f[8]),stored=GetServerTime()}
    if not validRelay(entry,'result') or (entry.result=='ok' and entry.rev<1) then return nil end
    return entry
end
local function receiveResult(entry)
    local k=key(entry.owner,entry.id); local pending=intents[k]
    if not pending or pending.version~=entry.version or pending.action~=entry.action or (pending.assignment or 0)~=entry.assignment then return end
    if entry.result=='ok' then
        pending.receiptRev=entry.rev; nextSync=0
        confirmPending(k,observed[k],false)
    else
        intents[k]=nil; requestDirty[k]=nil
        local message=entry.result=='capacity' and T('Досягнуто ліміту учасників або розміру даних')
            or (entry.result=='stale' and T('Призначення майстра змінилося') or T('Замовлення більше недоступне або його стан змінився'))
        notify(T('Дію щодо замовлення не виконано'),message,k)
    end
    persist(); changed()
end
comm:RegisterHandler('WORESULT',function(sender,_,payload)
    if not active or not nameOK(sender) or sender==identity then return end
    local entry=decodeResult(payload); if not entry or sender~=entry.owner then return end
    if entry.actor==identity then receiveResult(entry); return end
    local k=putRelay(scope.orderResultRelays,entry,'result')
    if k then
        scheduleRelay(resultRelayDirty,k)
    end
end)
comm:RegisterHandler('WORESR',function(sender,_,payload)
    if not active or not nameOK(sender) or sender==identity then return end
    local entry=decodeResult(payload)
    if not entry or entry.actor~=identity or sender==entry.owner then return end
    receiveResult(entry)
end)
comm:RegisterHandler('WOERROR',function(sender,_,payload)
    if not active then return end
    local f=codec._unpackFields(payload,5)
    if not f or #f~=5 or sender~=f[1] or f[3]~=identity or (f[5]~='capacity' and f[5]~='missing' and f[5]~='stale') or not idOK(f[2]) then return end
    local k=key(sender,f[2]); local pending=intents[k]
    if not pending or tonumber(f[4])~=pending.version then return end
    intents[k]=nil; requestDirty[k]=nil; persist(); changed()
    notify(T('Дію щодо замовлення не виконано'),f[5]=='capacity' and T('Досягнуто ліміту учасників або розміру даних') or T('Замовлення більше недоступне'),k)
end)
comm:RegisterHandler('WOQUERY',function(sender,_,payload)
    if not active or payload~='' or not nameOK(sender) or sender==identity then return end
    local now=GetTime(); if lastQueries[sender] and now-lastQueries[sender]<30 then return end
    if not lastQueries[sender] and size(lastQueries)>=1000 then
        for name,seen in pairs(lastQueries) do if now-seen>180 then lastQueries[name]=nil end end
        if size(lastQueries)>=1000 then return end
    end
    lastQueries[sender]=now
    -- Full snapshots are guild broadcasts; suppress duplicate full replays
    -- while still serving actor-specific queued actions for every requester.
    if now-lastSnapshotQuery>=30 then
        lastSnapshotQuery=now
        for k in pairs(own) do dirty[k]=true end
        for k in pairs(scope.orderRelays) do relayDirty[k]=true end
    end
    for k,entry in pairs(scope.orderResults) do if entry.owner==identity and entry.actor==sender then resultDirty[k]=true end end
    for k,entry in pairs(scope.orderResultRelays) do if entry.actor==sender then scheduleRelay(resultRelayDirty,k) end end
end)

local listener=CreateFrame('Frame')
for _,event in ipairs({'PLAYER_LOGIN','PLAYER_GUILD_UPDATE','GUILD_ROSTER_UPDATE'}) do pcall(listener.RegisterEvent,listener,event) end
listener:SetScript('OnEvent',function(_,event)
    connect()
    if event=='GUILD_ROSTER_UPDATE' and refresh and window and window:IsShown() then refresh() end
end)
local function pumpRelay(scheduled,entries,kind,validation,encodeEntry)
    if #comm.queue>8 then return end
    local now=GetTime()
    for k,due in pairs(scheduled) do
        local entry=entries[k]
        if not validRelay(entry,validation) then scheduled[k]=nil; entries[k]=nil
        elseif due==true or (type(due)=='number' and now>=due) then
            if comm:SendProtocol(kind,encodeEntry(entry)) then scheduled[k]=nil end
            return
        end
    end
end
if C_Timer and type(C_Timer.NewTicker)=='function' then C_Timer.NewTicker(3,function()
    connect(); if not active then return end
    local pendingTallies=type(scope.migrationPendingTallies)=='table' and scope.migrationPendingTallies[identity]
    if type(pendingTallies)=='table' and OldKraken.Database and type(OldKraken.Database.IsValidWorkshopTally)=='function' then
        for k,tally in pairs(pendingTallies) do
            local o=get(k)
            if o and not scope.orderDeliveryTallies[identity][k]
                and OldKraken.Database.IsValidWorkshopTally(tally,o.quantity)
                and tally.worker==o.worker and tally.assignment==(o.assignment or 0)
                and tally.money<=rewardCopper(o) then
                scope.orderDeliveryTallies[identity][k]=tally; pendingTallies[k]=nil
            end
        end
    end
    local now=GetTime(); if now>=nextSync then
        if comm:SendProtocol('WOQUERY','') then nextSync=now+180 end
        for k in pairs(intents) do requestDirty[k]=true end
        for k,tally in pairs(scope.orderDeliveryTallies[identity]) do
            local o=observed[k]
            if o and o.worker==identity and type(tally)=='table' and tally.worker==identity and (tally.assignment or 0)==(o.assignment or 0) and int(tally.money,1,rewardCopper(o)) and tally.money>(o.paidByWorker or 0) and (o.status=='assigned' or o.status=='delivered') then
                paymentDirty[k]=true
            end
        end
    end
    if now>=nextRelaySweep then
        nextRelaySweep=now+180
        for _,config in ipairs({{scope.orderResults,'result',resultDirty},{scope.orderResultRelays,'result',resultRelayDirty}}) do
            local entries,kind,scheduled=config[1],config[2],config[3]
            for k,entry in pairs(entries) do
                if not validRelay(entry,kind) then entries[k]=nil; scheduled[k]=nil end
            end
        end
    end
    local expired=false; for k,o in pairs(own) do if o.created<GetServerTime()-2592000 then own[k],dirty[k]=nil,nil; expired=true end end
    for k,o in pairs(observed) do if o.created<GetServerTime()-2592000 then observed[k],intents[k],relayDirty[k],scope.orderRelays[k]=nil,nil,nil,nil; expired=true end end
    for k in pairs(scope.orderDeliveryTallies[identity]) do if not get(k) then scope.orderDeliveryTallies[identity][k]=nil end end
    finalizeExchanges()
    if expired then persist(); changed() end
    if now>=nextDisplay then nextDisplay=now+30; changed() end
    if #comm.queue<=8 then
        for requestKey in pairs(requestDirty) do
            local pending,o=intents[requestKey],observed[requestKey]
            if not pending then requestDirty[requestKey]=nil
            elseif o then
                if comm:SendProtocol('WOREQ',codec._pack({o.owner,o.id,pending.action,string.format('%.0f',pending.version),pending.assignment or 0})) then requestDirty[requestKey]=nil end
                break
            end
        end
    end
    local paymentKey=next(paymentDirty)
    if paymentKey and #comm.queue<=8 then
        local o,tally=observed[paymentKey],scope.orderDeliveryTallies[identity][paymentKey]
        if not o or type(tally)~='table' or o.worker~=identity or tally.worker~=identity or (tally.assignment or 0)~=(o.assignment or 0)
            or (o.status~='assigned' and o.status~='delivered') or not int(tally.money,1,rewardCopper(o)) or tally.money<=(o.paidByWorker or 0) then paymentDirty[paymentKey]=nil
        elseif comm:SendProtocol('WOPAY',codec._pack({o.owner,o.id,o.assignment or 0,tally.money})) then paymentDirty[paymentKey]=nil end
    end
    local k=next(dirty); if k and #comm.queue<=8 then local o=own[k]; if not o or comm:SendProtocol('WORDER',encode(o)) then dirty[k]=nil end end
    local relayKey=next(relayDirty)
    if relayKey and #comm.queue<=8 then
        local payload=scope.orderRelays[relayKey]
        if not payload or comm:SendProtocol('WORELAY',payload) then relayDirty[relayKey]=nil end
    end
    pumpRelay(resultDirty,scope.orderResults,'WORESULT','result',resultPayload)
    pumpRelay(resultRelayDirty,scope.orderResultRelays,'WORESR','result',resultPayload)
end) end

local function button(parent,label,x,y,width,callback,variant,options)
    local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate'); OldKraken.UIStyle.Button(b,variant,options)
    b:SetSize(width,(options and options.height) or 28); b:SetPoint('TOPLEFT',parent,'TOPLEFT',x,y); b:SetText(label); b:SetScript('OnClick',callback); return b
end
local function input(parent,label,x,y,width,initial,options)
    local colors = OldKraken.UIStyle.Colors or {}
    local t=parent:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); t:SetPoint('TOPLEFT',parent,'TOPLEFT',x,y); t:SetText(label)
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(t, 12) end
    if colors.mutedText then t:SetTextColor(colors.mutedText[1], colors.mutedText[2], colors.mutedText[3]) end
    local e=CreateFrame('EditBox',nil,parent,'InputBoxTemplate'); OldKraken.UIStyle.Input(e,options)
    e:SetSize(width,(options and options.height) or 28); e:SetPoint('TOPLEFT',parent,'TOPLEFT',x+4,y-18); e:SetAutoFocus(false); e:SetText(initial or '')
    if type(e.SetTextInsets)=='function' then e:SetTextInsets(10,10,0,0) end
    e:SetScript('OnEscapePressed',function(self) self:ClearFocus() end); return e
end
local function dropdown(parent,name,x,y,width,values,labels,get,set,options)
    local f=CreateFrame('Frame',name,parent,'UIDropDownMenuTemplate'); OldKraken.UIStyle.Dropdown(f,options)
    f:SetPoint('TOPLEFT',parent,'TOPLEFT',x-16,y+3); UIDropDownMenu_SetWidth(f,width-34)
    UIDropDownMenu_Initialize(f,function(_,level)
        for _,v in ipairs(values) do local value=v; local item=UIDropDownMenu_CreateInfo(); item.text=labels[value]; item.value=value; item.checked=get()==value
            item.func=function() set(value); UIDropDownMenu_SetText(f,labels[value]) end; UIDropDownMenu_AddButton(item,level) end
    end)
    UIDropDownMenu_SetText(f,labels[get()]); return f
end
saveDraft=function()
    if restoringDraft or not active or not scope or not identity or not window or not window.orderForm then return end
    local form=window.orderForm
    local item=form.item:GetText() or ''
    scope.orderDrafts[identity]={item=item==recipePlaceholder() and '' or item,quantity=form.quantity:GetText() or '',
        reward='0',rewardSilver='0',note=form.note:GetText() or '',profession=profession,
        materials=materials,deadline=deadline,recipe=chosenRecipe and {item=chosenRecipe.item,recipe=chosenRecipe.recipe,owner=chosenRecipe.owner} or nil}
end
restoreDraft=function()
    if not active or not window or not window.orderForm then return end
    local draft=type(scope.orderDrafts[identity])=='table' and scope.orderDrafts[identity] or {}
    local function value(v,default) return type(v)=='string' and v or default end
    local form=window.orderForm
    restoringDraft=true
    profession=professionNames[draft.profession] and draft.profession or 0
    materials=materialNames[draft.materials] and draft.materials or 'customer'
    deadline=deadlineNames[draft.deadline] and draft.deadline or 86400
    local item=value(draft.item,'')
    form.quantity:SetText(value(draft.quantity,'1'))
    form.note:SetText(value(draft.note,''))
    local recipe=draft.recipe
    chosenRecipe=type(recipe)=='table' and int(recipe.item,0,100000000) and int(recipe.recipe,1,100000000)
        and {item=recipe.item,recipe=recipe.recipe,owner=nameOK(recipe.owner) and recipe.owner or nil} or nil
    local chosenText=chosenRecipe and (orderItemName(chosenRecipe.item) or (item~='' and item) or recipePlaceholder()) or recipePlaceholder()
    form.item:SetText(chosenText)
    UIDropDownMenu_SetText(window.professionMenu,professionNames[profession] or T('Оберіть професію'))
    UIDropDownMenu_SetText(window.materialsMenu,materialNames[materials])
    UIDropDownMenu_SetText(window.deadlineMenu,deadlineNames[deadline])
    if type(form.UpdateItemIcon)=='function' then form.UpdateItemIcon() end
    restoringDraft=false
end
clearDraft=function()
    if active and scope and identity then scope.orderDrafts[identity]=nil end
    restoreDraft()
end
local function showError() chatError(T('Old Kraken: дію не виконано. Оновіть дані або перевірте стан замовлення.')) end
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
StaticPopupDialogs.OLDKRAKEN_ORDER_CARD_DELIVERED={
    text='Позначити замовлення «%s» як передане?', button1='Передав', button2='Назад',
    timeout=0, whileDead=true, hideOnEscape=true, preferredIndex=3,
    OnAccept=function(_,callback) if type(callback)=='function' then callback() end end,
}
StaticPopupDialogs.OLDKRAKEN_ORDER_CARD_FINISH={
    text='Підтвердити отримання замовлення «%s»?', button1='Отримано', button2='Назад',
    timeout=0, whileDead=true, hideOnEscape=true, preferredIndex=3,
    OnAccept=function(_,callback) if type(callback)=='function' then callback() end end,
}
StaticPopupDialogs.OLDKRAKEN_ORDER_REOPEN={
    text='Перевідкрити «%s» на 24 години? Поточного майстра і відгуки буде знято.', button1='Перевідкрити', button2='Назад',
    timeout=0, whileDead=true, hideOnEscape=true, preferredIndex=3,
    OnAccept=function(_,callback) if type(callback)=='function' then callback() end end,
}
StaticPopupDialogs.OLDKRAKEN_ORDER_DELETE={
    text='Видалити замовлення «%s»? Його буде прибрано зі списку гільдії.', button1='Видалити', button2='Назад',
    timeout=0, whileDead=true, hideOnEscape=true, preferredIndex=3,
    OnAccept=function(_,callback) if type(callback)=='function' then callback() end end,
}
local cardActionDialogs={
    cancel='OLDKRAKEN_ORDER_CARD_CANCEL', withdraw='OLDKRAKEN_ORDER_CARD_WITHDRAW',
    delivered='OLDKRAKEN_ORDER_CARD_DELIVERED', finish='OLDKRAKEN_ORDER_CARD_FINISH', reopen='OLDKRAKEN_ORDER_REOPEN', delete='OLDKRAKEN_ORDER_DELETE',
}
local function confirmCardAction(k,action)
    local o=k and get(k)
    if not active or not o or not cardActionDialogs[action] then showError(); return end
    local expectedProfile,expectedIdentity,expectedStatus=profile,identity,o.status
    local function accept()
        local current=get(k)
        if not active or profile~=expectedProfile or identity~=expectedIdentity or not current or current.status~=expectedStatus then showError(); return end
        local ok
        if action=='cancel' or action=='finish' or action=='reopen' or action=='delete' then ok=ownerAction(k,action) else ok=intent(k,action) end
        if not ok then showError() end
    end
    local popup=StaticPopup_Show(cardActionDialogs[action],displayOrderItem(o),nil,accept)
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
local function rosterPresentation()
    local recipes=OldKraken.WorkshopRecipes
    if recipes and type(recipes.GetRosterPresentation)=='function' then return recipes:GetRosterPresentation() end
    return {},{}
end
local function playerLabel(name,classes)
    local recipes=OldKraken.WorkshopRecipes
    if recipes and type(recipes.FormatPlayerName)=='function' then return recipes:FormatPlayerName(name,classes) end
    return name
end
local function onlineLabel(name,online)
    local recipes=OldKraken.WorkshopRecipes
    if recipes and type(recipes.FormatOnlineStatus)=='function' then return recipes:FormatOnlineStatus(name,online) end
    return T('|cff999999невідомо|r')
end
refresh=function()
    if not window or not window:IsShown() then return end
    local online,classes=rosterPresentation()
    local list={}; local seen={}
    for _,source in ipairs({own,observed}) do for k,o in pairs(source) do
        local status=displayStatus(o)
        local available=view=='available' and o.owner~=identity and status=='open' and not o.candidates[identity] and not intents[k]
            and canCraft(o)
        if o.status~='deleted' and not seen[k] and (view=='all' or (view=='mine' and o.owner==identity) or (view=='work' and (o.worker==identity or o.candidates[identity])) or (view=='available' and available))
            and (statusFilter=='all' or statusFilter==status) and (professionFilter==0 or professionFilter==o.profession)
            and (searchQuery=='' or lower(displayOrderItem(o)):find(searchQuery,1,true) or lower(o.item):find(searchQuery,1,true) or lower(o.owner):find(searchQuery,1,true)) then
            seen[k]=true; list[#list+1]={key=k,order=o}
        end
    end end
    table.sort(list,function(a,b) if a.order.created~=b.order.created then return a.order.created>b.order.created end return a.key<b.key end)
    if selected and not seen[selected] then selected=nil end
    offset=math.max(0,math.min(offset,math.max(0,math.ceil(#list/CARDS_PER_PAGE)-1)))
    window.page:SetText((offset+1)..' / '..math.max(1,math.ceil(#list/CARDS_PER_PAGE)))
    window.empty:SetShown(#list==0)
    local alertsOn = OldKraken.DB.settings.workshopOrderAlerts ~= false
    if window.alerts.SetActive then window.alerts:SetActive(alertsOn) end
    if window.alerts.SetDotColor then window.alerts:SetDotColor(alertsOn and 'success' or 'neutral') end
    window.alerts:SetText(alertsOn and T('Нові: увімк.') or T('Нові: вимк.'))
    local pillKinds = {open='success', assigned='warning', delivered='info', done='success', cancelled='neutral', expired='danger'}
    for i,row in ipairs(orderRows) do
        local entry=list[offset*CARDS_PER_PAGE+i]
        if entry then
            local o=entry.order; row.entryKey=entry.key
            row.delete:SetShown(o.owner==identity)
            if row.delete.SetAlpha then row.delete:SetAlpha(0) end
            local stateKey=displayStatus(o)
            row.order=o; row.icon:SetTexture(orderIcon(o))
            row.title:SetText(displayOrderItem(o))
            row.meta:SetText(professionNames[o.profession]..' · '..playerLabel(o.owner,classes))
            row.reward:SetText(o.quantity..T(' шт.')..(rewardCopper(o)>0 and (' · '..formatReward(o)) or '')..T(' · до ')..date('%d.%m %H:%M',o.deadline))
            local statusText=stateKey=='expired' and (o.status=='assigned' and T('У роботі · прострочено') or T('Термін минув')) or statusNames[stateKey]
            if view=='available' and (o.itemID or 0)==0 and (o.recipeID or 0)==0 then statusText=statusText..T(' · лише професія') end
            if type(row.statePill)=='table' and row.statePill.SetKind then
                row.statePill:SetKind(pillKinds[stateKey] or 'neutral')
                row.statePill.label:SetText(statusText)
                row.state:Hide()
            else
                row.state:SetText(statusText)
                row.state:SetTextColor(unpack(statusColors[stateKey] or statusColors.expired))
                row.state:Show()
            end
            local canWithdraw=o.owner~=identity and not intents[entry.key]
                and ((o.status=='open' and o.candidates[identity]) or (o.status=='assigned' and o.worker==identity))
            row.withdraw:SetShown(canWithdraw and true or false)
            if o.owner~=identity and stateKey=='open' and canCraft(o) then
                row.offer:Show()
                row.offer:SetWidth(canWithdraw and 99 or 203)
                if intents[entry.key] then row.offer:SetText(T('Очікується відповідь')); row.offer:Disable()
                elseif o.candidates[identity] then row.offer:SetText(T('Відгук є')); row.offer:Disable()
                else row.offer:SetText(T('Запропонувати допомогу')); row.offer:Enable() end
            else row.offer:Hide() end
            if o.owner==identity and o.status=='open' then
                local applicants={}; for name in pairs(o.candidates) do applicants[#applicants+1]=name end; table.sort(applicants)
                row.applicants:SetText(#applicants>0 and (T('|cffffc36bВідгук:|r ')..playerLabel(applicants[1],classes)..(#applicants>1 and (' +'..(#applicants-1)) or '')) or T('Відгуків ще немає'))
                row.applicants:Show()
                if #applicants>0 then
                    row.choose:SetText(stateKey=='expired' and T('Термін минув') or (T('Обрати (')..#applicants..')'))
                    if stateKey=='expired' then row.choose:Disable() else row.choose:Enable() end
                    row.choose:Show()
                else row.choose:Hide() end
            elseif o.worker then
                row.applicants:SetText(T('|cff9ba9bcМайстер:|r ')..playerLabel(o.worker,classes))
                row.applicants:Show(); row.choose:Hide()
            else row.applicants:Hide(); row.choose:Hide() end
            if o.worker==identity and o.owner~=identity and o.status=='assigned' and OldKraken.Workshop and OldKraken.Workshop:HasProfession(o.profession) then
                row.progress:SetText(intents[entry.key] and T('Очікується відповідь') or T('Передав'))
                row.progress:SetWidth(canWithdraw and 99 or 203)
                if intents[entry.key] then row.progress:Disable() else row.progress:Enable() end
                row.progress:Show()
            elseif o.owner==identity and o.status=='delivered' then
                row.progress:SetWidth(99); row.progress:SetText(T('Отримано')); row.progress:Enable(); row.progress:Show()
            else row.progress:Hide() end
            if o.owner==identity and o.status~='done' and o.status~='cancelled' then
                row.cancel:ClearAllPoints()
                row.cancel:SetPoint('TOPLEFT',row,'TOPLEFT',112,window.embedded and -150 or (o.status=='open' and -109 or -104))
                row.cancel:SetHeight(window.embedded and 24 or (o.status=='open' and 19 or 24)); row.cancel:Show()
            else row.cancel:Hide() end
            if OldKraken.UIStyle.ApplySelection then
                OldKraken.UIStyle.ApplySelection(row, selected==entry.key)
                row:UnlockHighlight()
            elseif selected==entry.key then row:LockHighlight() else row:UnlockHighlight() end
            row:Show()
        else row.entryKey=nil; row.order=nil; row.delete:Hide(); row:UnlockHighlight(); row:Hide() end
    end
    for _,row in ipairs(window.candidates) do row:Hide() end
    local o=selected and get(selected)
    local pending=selected and intents[selected]
    if o then
        local statusKey=displayStatus(o)
        local state=statusKey=='expired' and (o.status=='assigned' and T('У роботі · прострочено') or T('Термін минув')) or statusNames[o.status]
        local stateColor=statusColors[statusKey] or statusColors.expired
        local coloredState=string.format('|cff%02x%02x%02x%s|r',math.floor(stateColor[1]*255+0.5),math.floor(stateColor[2]*255+0.5),math.floor(stateColor[3]*255+0.5),state)
        local hasRecipe=(o.itemID or 0)>0 or (o.recipeID or 0)>0
        local masters=hasRecipe and OldKraken.WorkshopRecipes and OldKraken.WorkshopRecipes:FindMasters(o.itemID or 0,o.recipeID or 0) or {}
        local names={}; for i=1,math.min(#masters,3) do names[#names+1]=playerLabel(masters[i].name,classes)..' ('..date('%d.%m',masters[i].seen)..(GetServerTime()-masters[i].seen>604800 and T(' · застаріло') or '')..')' end
        local known=hasRecipe and (T('\n|cff9ba9bcВідомі майстри:|r ')..(#names>0 and table.concat(names,', ') or T('немає даних'))..(#masters>3 and (' +'..(#masters-3)) or '')) or T('\n|cffffc36bПошук за професією; знання рецепта не підтверджено.|r')
        local tally=scope and scope.orderDeliveryTallies[identity] and scope.orderDeliveryTallies[identity][selected]
        local progress=''
        if type(tally)=='table' and tally.worker==o.worker and (tally.assignment or 0)==(o.assignment or 0) then
            local mats={}; for id,n in pairs(type(tally.materials)=='table' and tally.materials or {}) do
                if int(id,1,100000000) and int(n,1,10000000) then
                    local name; if type(GetItemInfo)=='function' then local ok,value=pcall(GetItemInfo,id); if ok and textOK(value,1,160) then name=value end end
                    mats[#mats+1]=(OldKraken.WorkshopRecipes and OldKraken.WorkshopRecipes.ItemLabel and OldKraken.WorkshopRecipes:ItemLabel(id) or name or T('Завантаження назви…'))..' ×'..n
                end
            end; table.sort(mats)
            local money=tonumber(tally.money) or 0
            progress=T('\n|cff9ba9bcОбмін:|r речі ')..tostring(tally.items or 0)..'/'..o.quantity..T(' · оплата ')..math.floor(money/10000)..T('з ')..math.floor(money%10000/100)..T('с ')..(money%100)..T('м / ')..o.reward..T('з')..((o.rewardSilver or 0)>0 and (' '..o.rewardSilver..T('с')) or '')
            if #mats>0 then progress=progress..T('\n|cff9ba9bcМатеріали:|r ')..table.concat(mats,', ') end
        end
        local deadlineColor=statusKey=='expired' and '|cffff7770' or '|cffffffff'
        local note=o.note~='' and (T('\n\n|cff9ba9bcКоментар:|r ')..o.note) or ''
        local rewardLine=rewardCopper(o)>0 and (T('|cff9ba9bcВинагорода:|r |cffffd35a')..formatReward(o)..'|r\n') or ''
        window.details:SetText('|cffffd35a'..displayOrderItem(o)..' ×'..o.quantity..'|r\n|cff9ba9bc'..professionNames[o.profession]..'|r · '..coloredState..T('\n\n|cff9ba9bcЗамовник:|r ')..playerLabel(o.owner,classes)..(o.relayed and T('\n|cffffc36bДані через гільдію; можуть бути застарілими.|r') or '')..T('\n|cff9ba9bcМайстер:|r ')..(o.worker and (playerLabel(o.worker,classes)..' · '..onlineLabel(o.worker,online)) or T('|cff9ba9bcне обрано|r'))..'\n\n'..rewardLine..T('|cff9ba9bcРесурси:|r ')..materialNames[o.materials]..T('\n|cff9ba9bcТермін:|r ')..deadlineColor..date('%d.%m.%Y %H:%M',o.deadline)..'|r'..known..progress..note..(pending and (pending.receiptRev and T('\n\n|cffffc36bПідтверджено; очікується оновлення стану.|r') or T('\n\n|cffffc36bОчікується підтвердження замовника; дія передається через гільдію.|r')) or ''))
        local choosing=o.owner==identity and o.status=='open'
        local detailsHeight=window.embedded and (choosing and 225 or 360) or (choosing and 110 or 215)
        window.detailsScroll:SetSize(350,detailsHeight)
        window.detailsContent:SetHeight(math.max(detailsHeight,window.details:GetStringHeight()+8))
        local isOwner=o.owner==identity
        window.offer:SetShown(not isOwner and o.status=='open' and o.deadline>=GetServerTime() and not o.candidates[identity] and not pending and canCraft(o))
        window.withdraw:SetShown(not isOwner and not pending and ((o.status=='open' and o.candidates[identity]) or (o.status=='assigned' and o.worker==identity)))
        window.delivered:SetShown(not isOwner and not pending and o.status=='assigned' and o.worker==identity and OldKraken.Workshop and OldKraken.Workshop:HasProfession(o.profession))
        window.finish:SetShown(isOwner and o.status=='delivered')
        window.cancel:SetShown(isOwner and o.status~='done' and o.status~='cancelled')
        window.reopen:SetShown(isOwner and o.status=='assigned' and o.deadline<GetServerTime() and GetServerTime()+86400<=o.created+2592000)
        window.masters:SetShown(hasRecipe)
        if isOwner and o.status=='open' then
            local names={}; for name in pairs(o.candidates) do names[#names+1]=name end; table.sort(names)
            window.candidateTitle:SetText(#names>0 and T('Оберіть майстра:') or T('Пропозицій майстрів поки немає'))
            local scroll=window.candidateScroll
            local height=tonumber((scroll:GetHeight())) or 96
            if height<=0 then height=96 end
            local top=math.max(0,math.min(tonumber((scroll:GetVerticalScroll())) or 0,math.max(0,#names*48-height)))
            if top~=(tonumber((scroll:GetVerticalScroll())) or 0) then scroll:SetVerticalScroll(top) end
            local first=math.floor(top/48)+1
            local count=math.max(0,math.min(math.ceil(height/48)+1,#names-first+1))
            for i=1,count do
                local dataIndex=first+i-1
                local name=names[dataIndex]
                local row=window.candidates[i]
                if not row then
                    row=CreateFrame('Frame',nil,window.candidateContent); row:SetSize(330,46)
                    row.label=row:CreateFontString(nil,'OVERLAY','GameFontHighlight'); row.label:SetPoint('TOPLEFT',row,'TOPLEFT',0,0); row.label:SetSize(200,18); row.label:SetJustifyH('LEFT'); row.label:SetWordWrap(false)
                    row.status=row:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); row.status:SetPoint('TOPLEFT',row,'TOPLEFT',0,-18); row.status:SetSize(200,16); row.status:SetJustifyH('LEFT'); row.status:SetWordWrap(false)
                    readableFont(row.label,14); readableFont(row.status,12)
                    row.hover=CreateFrame('Frame',nil,row); row.hover:SetPoint('TOPLEFT'); row.hover:SetSize(200,34); row.hover:EnableMouse(true)
                    row.hover:SetScript('OnEnter',function(self) if GameTooltip and self.playerText then GameTooltip:SetOwner(self,'ANCHOR_RIGHT'); GameTooltip:SetText(self.playerText); GameTooltip:AddLine(self.statusText,1,1,1,true); GameTooltip:Show() end end)
                    row.hover:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
                    row.choose=button(row,T('Обрати'),210,-7,100,function(self) if not ownerAction(selected,'choose',self:GetParent().person) then showError() end end)
                    window.candidates[i]=row
                end
                local state=statusKey=='expired' and T('|cffff7a6eТермін минув|r') or T('|cffffc36bОчікує вибору|r')
                local title=playerLabel(name,classes); local info=state..' |cff9ba9bc·|r '..onlineLabel(name,online)
                row.person=name; row:ClearAllPoints(); row:SetPoint('TOPLEFT',window.candidateContent,'TOPLEFT',0,-(dataIndex-1)*48)
                row.label:SetText(title); row.status:SetText(info); row.hover.playerText=title; row.hover.statusText=info
                if statusKey=='expired' then row.choose:Disable() else row.choose:Enable() end
                row:Show()
            end
            window.candidateContent:SetHeight(math.max(96,#names*48)); window.candidateTitle:Show(); window.candidateScroll:Show()
        else window.candidateTitle:Hide(); window.candidateScroll:Hide() end
    else
        window.details:SetText(T('|cff9ba9bcОберіть замовлення зі списку.|r')); window.detailsScroll:SetSize(350,window.embedded and 360 or 215); window.detailsContent:SetHeight(window.embedded and 360 or 215); window.offer:Hide(); window.withdraw:Hide(); window.delivered:Hide(); window.finish:Hide(); window.cancel:Hide(); window.reopen:Hide(); window.masters:Hide(); window.candidateTitle:Hide(); window.candidateScroll:Hide()
    end
end
local function createWindow(parent)
    local embedded=parent~=nil
    local shift=embedded and 32 or 0
    local function y(value) return value-shift end
    local f
    if embedded then
        f=CreateFrame('Frame',nil,parent)
    else
        f=CreateFrame('Frame','OldKrakenWorkshopOrdersFrame',UIParent,'BasicFrameTemplateWithInset')
        table.insert(UISpecialFrames,'OldKrakenWorkshopOrdersFrame')
        f:SetMovable(true); f:RegisterForDrag('LeftButton'); f:SetScript('OnDragStart',f.StartMoving); f:SetScript('OnDragStop',f.StopMovingOrSizing)
        OldKraken.UIStyle.Window(f)
    end
    f.embedded=embedded
    f:SetSize(900,embedded and 608 or 650); f:SetPoint('CENTER',parent or UIParent,'CENTER'); f:SetClampedToScreen(true); f:EnableMouse(not embedded)
    if OldKraken.BindGuildTitle then OldKraken.BindGuildTitle(f, T('Замовлення')) end
    local colors = OldKraken.UIStyle.Colors or {}
    if embedded and OldKraken.UIStyle.PanelFrame then
        f.filterPanel = OldKraken.UIStyle.PanelFrame(f, 'buttonEdge')
        f.filterPanel:SetSize(900, 52)
        f.filterPanel:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, -98)
        f.detailPanel = OldKraken.UIStyle.PanelFrame(f, 'buttonEdge')
        f.detailPanel:SetSize(402, 444)
        f.detailPanel:SetPoint('TOPLEFT', f, 'TOPLEFT', 498, -162)
    end
    local views={all=T('Усі замовлення'),available=T('Доступні мені'),mine=T('Мої замовлення'),work=T('Моя робота')}
    dropdown(f,'OldKrakenOrdersView',embedded and 10 or 18,embedded and -107 or y(-42),embedded and 158 or 190,{'all','available','mine','work'},views,function() return view end,function(v) view=v; offset=0; refresh() end,{rounded=true})
    local statusLabels={all=T('Усі стани'),open=T('Шукає майстра'),assigned=T('У роботі'),delivered=T('Передано'),done=T('Виконано'),cancelled=T('Скасовано'),expired=T('Термін минув')}
    dropdown(f,'OldKrakenOrdersStatus',embedded and 174 or 500,embedded and -107 or y(-42),embedded and 126 or 165,{'all','open','assigned','delivered','done','cancelled','expired'},statusLabels,function() return statusFilter end,function(v) statusFilter=v; offset=0; refresh() end,{rounded=true})
    local professionLabels={[0]=T('Усі професії')}; local filterIDs={0}
    for _,id in ipairs(professionIDs) do professionLabels[id]=professionNames[id]; filterIDs[#filterIDs+1]=id end
    dropdown(f,'OldKrakenOrdersFilterProfession',embedded and 306 or 675,embedded and -107 or y(-42),embedded and 142 or 185,filterIDs,professionLabels,function() return professionFilter end,function(v) professionFilter=v; offset=0; refresh() end,{rounded=true})
    if embedded and OldKraken.UIStyle.Chip then
        f.alerts = OldKraken.UIStyle.Chip(f, T('Нові: увімк.'), {dot = 'success', width = 126, height = 34, rounded = true})
        f.alerts:SetPoint('TOPLEFT', f, 'TOPLEFT', 658, -107)
        f.alerts:SetScript('OnClick', function() local s=OldKraken.DB.settings; s.workshopOrderAlerts=s.workshopOrderAlerts==false; OldKraken:Fire('WORKSHOP_ALERT_SETTING') end)
    else
        f.alerts=button(f,T('Нові: увімк.'),235,y(-42),145,function() local s=OldKraken.DB.settings; s.workshopOrderAlerts=s.workshopOrderAlerts==false; OldKraken:Fire('WORKSHOP_ALERT_SETTING') end,nil,{rounded=true,height=34})
    end
    button(f,T('Оновити'),embedded and 792 or 390,embedded and -107 or y(-42),embedded and 98 or 100,function() nextSync=0; chatInfo(T('Old Kraken: запит замовлень поставлено в чергу.')) end,nil,{rounded=true,height=34})
    f.empty=f:CreateFontString(nil,'OVERLAY','GameFontHighlight'); f.empty:SetPoint('TOPLEFT',f,'TOPLEFT',embedded and 16 or 25,embedded and -180 or y(-88)); f.empty:SetWidth(430); f.empty:SetJustifyH('LEFT'); f.empty:SetText(T('Замовлень не знайдено. Змініть фільтри або створіть замовлення.'))
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(f.empty, 13) end
    if colors.mutedText then f.empty:SetTextColor(colors.mutedText[1], colors.mutedText[2], colors.mutedText[3]) end
    f.orderRows=orderRows
    for i=1,CARDS_PER_PAGE do
        local col=(i-1)%2; local line=math.floor((i-1)/2)
        local card=button(f,'',embedded and (col*244) or (18+col*229),embedded and (-162-line*182) or y(-80-line*142),embedded and 236 or 219,function(self) if self.entryKey then selected=self.entryKey; refresh() end end)
        card:SetHeight(embedded and 172 or 134)
        card.icon=card:CreateTexture(nil,'ARTWORK'); card.icon:SetPoint('TOPLEFT',card,'TOPLEFT',10,-10); card.icon:SetSize(34,34)
        local function label(template,y)
            local text=card:CreateFontString(nil,'OVERLAY',template); text:SetPoint('TOPLEFT',card,'TOPLEFT',50,y); text:SetPoint('RIGHT',card,'RIGHT',-8,0); text:SetJustifyH('LEFT'); text:SetWordWrap(false); return text
        end
        card.title=label('GameFontNormal',-8); card.meta=label('GameFontHighlightSmall',embedded and -30 or -25)
        card.title:ClearAllPoints(); card.title:SetPoint('TOPLEFT',card,'TOPLEFT',50,-8); card.title:SetPoint('RIGHT',card,'RIGHT',-30,0)
        card.delete=CreateFrame('Button',nil,card); card.delete:SetSize(24,24); card.delete:SetPoint('TOPRIGHT',card,'TOPRIGHT',-5,-5)
        local delGlyph = card.delete:CreateTexture(nil,'ARTWORK')
        delGlyph:SetTexture('Interface\\AddOns\\' .. (OldKraken and OldKraken.name or 'OldKraken') .. '\\Media\\IconTrash.tga')
        delGlyph:SetSize(15,15); delGlyph:SetPoint('CENTER',card.delete,'CENTER',0,0)
        delGlyph:SetVertexColor(0.9,0.32,0.3,1)
        card.delete.glyph = delGlyph
        card.delete:SetScript('OnClick',function(self) confirmCardAction(self:GetParent().entryKey,'delete') end)
        card.delete:SetScript('OnEnter',function(self)
            if self.SetAlpha then self:SetAlpha(1) end
            if GameTooltip then GameTooltip:SetOwner(self,'ANCHOR_RIGHT'); GameTooltip:SetText(T('Видалити замовлення')); GameTooltip:Show() end
        end)
        card.delete:SetScript('OnLeave',function(self)
            if self.SetAlpha then self:SetAlpha(0) end
            if GameTooltip then GameTooltip:Hide() end
        end)
        card.delete:Hide()
        readableFont(card.title,embedded and 14 or 13)
        readableFont(card.meta,embedded and 12 or 11)
        card.reward=label('GameFontHighlight',embedded and -54 or -42); card.state=label('GameFontNormal',embedded and -78 or -59)
        readableFont(card.reward,12); readableFont(card.state,12)
        if OldKraken.UIStyle.PillBadge then
            card.statePill = OldKraken.UIStyle.PillBadge(card, T('Відкрито'), 'success', {width = 136, height = 24, fontSize = 11, bold = true, rounded = true})
            card.statePill:SetPoint('TOPLEFT', card, 'TOPLEFT', 10, embedded and -76 or -59)
            card.statePill.label:SetWidth(120)
            card.statePill.label:SetJustifyH('CENTER')
        end
        card.offer=button(card,T('Запропонувати допомогу'),8,embedded and -150 or -104,203,function(self)
            local k=self:GetParent().entryKey
            if not k or not intent(k,'offer') then showError() end
        end)
        card.progress=button(card,T('Передав'),8,embedded and -150 or -104,203,function(self)
            local k=self:GetParent().entryKey; local o=k and get(k)
            if not o then showError(); return end
            if o.owner==identity and o.status=='delivered' then
                confirmCardAction(k,'finish')
            elseif o.worker==identity and o.status=='assigned' then
                confirmCardAction(k,'delivered')
            else showError() end
        end)
        card.withdraw=button(card,T('Відмовитися'),112,embedded and -150 or -104,99,function(self)
            local k=self:GetParent().entryKey
            confirmCardAction(k,'withdraw')
        end)
        card.cancel=button(card,T('Скасувати'),112,embedded and -150 or -104,99,function(self)
            local k=self:GetParent().entryKey
            confirmCardAction(k,'cancel')
        end)
        card.applicants=card:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
        card.applicants:SetPoint('TOPLEFT',card,'TOPLEFT',8,embedded and -112 or -80); card.applicants:SetWidth(203); card.applicants:SetJustifyH('LEFT'); card.applicants:SetWordWrap(false)
        readableFont(card.applicants,12)
        card.menu=CreateFrame('Frame','OldKrakenOrderCardMenu'..i,card,'UIDropDownMenuTemplate')
        UIDropDownMenu_Initialize(card.menu,function(menu,level)
            local target=menu.orderKey; local o=target and own[target]
            if not o or o.status~='open' or o.deadline<GetServerTime() then return end
            local names={}; for name in pairs(o.candidates) do names[#names+1]=name end; table.sort(names)
            local online,classes=rosterPresentation()
            for _,name in ipairs(names) do
                local person=name; local item=UIDropDownMenu_CreateInfo(); item.text=playerLabel(person,classes)..T(' · |cffffc36bОчікує|r · ')..onlineLabel(person,online); item.notCheckable=true
                item.func=function() if not ownerAction(target,'choose',person) then showError() end end
                UIDropDownMenu_AddButton(item,level)
            end
        end,'MENU')
        card.choose=button(card,T('Обрати'),8,embedded and -150 or -109,99,function(self)
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
        card.choose:SetHeight(embedded and 24 or 19)
        card:SetScript('OnEnter',function(self)
            if self.delete and self.delete:IsShown() and self.delete.SetAlpha then self.delete:SetAlpha(1) end
            local o=self.order; if not o or not GameTooltip then return end
            local _,classes=rosterPresentation()
            GameTooltip:SetOwner(self,'ANCHOR_RIGHT'); GameTooltip:SetText(displayOrderItem(o))
            GameTooltip:AddLine(T('Замовник: ')..playerLabel(o.owner,classes),1,1,1,true)
            if o.worker then GameTooltip:AddLine(T('Майстер: ')..playerLabel(o.worker,classes),1,1,1,true) end
            local state=displayStatus(o); local color=statusColors[state] or statusColors.expired
            local status=state=='expired' and (o.status=='assigned' and T('У роботі · прострочено') or T('Термін минув')) or statusNames[state]
            GameTooltip:AddLine(T('Статус: ')..status,color[1],color[2],color[3],true)
            GameTooltip:AddLine(T('Професія: ')..professionNames[o.profession],1,1,1,true)
            GameTooltip:AddLine(T('Кількість: ')..o.quantity..(rewardCopper(o)>0 and (T(' · Винагорода: ')..formatReward(o)) or ''),1,1,1,true)
            GameTooltip:AddLine(T('Термін: ')..date('%d.%m.%Y %H:%M',o.deadline),1,1,1,true)
            GameTooltip:AddLine(T('Натисніть, щоб переглянути деталі'),0.6,0.9,1,true); GameTooltip:Show()
        end)
        card:SetScript('OnLeave',function(self)
            if self.delete and self.delete.SetAlpha then self.delete:SetAlpha(0) end
            if GameTooltip then GameTooltip:Hide() end
        end)
        orderRows[i]=card
    end
    local prevPage=button(f,'‹',embedded and 159 or 18,embedded and -534 or y(-368),44,function() offset=offset-1; refresh() end,nil,{rounded=true,height=28})
    f.page=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    if embedded then f.page:SetPoint('CENTER',prevPage,'RIGHT',37,0); f.page:SetJustifyH('CENTER')
    else f.page:SetPoint('TOPLEFT',f,'TOPLEFT',75,y(-374)) end
    button(f,'›',embedded and 277 or 130,embedded and -534 or y(-368),44,function() offset=offset+1; refresh() end,nil,{rounded=true,height=28})
    local searchLabel=f:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); searchLabel:SetPoint('TOPLEFT',f,'TOPLEFT',205,y(-375)); searchLabel:SetText(T('Пошук'))
    if embedded then searchLabel:Hide() end
    local search=CreateFrame('EditBox',nil,f,'InputBoxTemplate'); OldKraken.UIStyle.Input(search)
    search:SetPoint('TOPLEFT',f,'TOPLEFT',embedded and 456 or 265,embedded and -107 or y(-370)); search:SetSize(embedded and 194 or 195,embedded and 34 or 22); search:SetAutoFocus(false)
    if embedded then search:SetTextInsets(8,8,0,0) end
    local searchHint=search:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    searchHint:SetPoint('LEFT',search,'LEFT',10,0); searchHint:SetText(T('Пошук замовлення'))
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(searchHint, 13) end
    if colors.mutedText then searchHint:SetTextColor(colors.mutedText[1], colors.mutedText[2], colors.mutedText[3]) end
    searchHint:SetShown(embedded)
    search:SetScript('OnTextChanged',function(self)
        local txt = self:GetText() or ''
        searchHint:SetShown(embedded and txt == '')
        searchQuery=lower(txt); offset=0; refresh()
    end)
    search:SetScript('OnEscapePressed',function(self) self:ClearFocus() end)
    local detailHost = type(f.detailPanel)=='table' and f.detailPanel or f
    local detailsHeader=detailHost:CreateFontString(nil,'OVERLAY','GameFontNormalLarge'); detailsHeader:SetPoint('TOPLEFT',f,'TOPLEFT',embedded and 516 or 495,embedded and -178 or y(-80)); detailsHeader:SetText(T('Деталі замовлення'))
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(detailsHeader, 15, true) end
    if colors.brandGold then detailsHeader:SetTextColor(colors.brandGold[1], colors.brandGold[2], colors.brandGold[3]) end
    local detailsScroll=CreateFrame('ScrollFrame','OldKrakenOrderDetailsScroll',f,'UIPanelScrollFrameTemplate'); detailsScroll:SetPoint('TOPLEFT',f,'TOPLEFT',embedded and 516 or 495,embedded and -206 or y(-105)); detailsScroll:SetSize(embedded and 356 or 350,embedded and 196 or 110); f.detailsScroll=detailsScroll
    if OldKraken.UIStyle.ScrollBar then OldKraken.UIStyle.ScrollBar(detailsScroll) end
    f.detailsContent=CreateFrame('Frame',nil,detailsScroll); f.detailsContent:SetSize(embedded and 344 or 340,embedded and 196 or 110); detailsScroll:SetScrollChild(f.detailsContent)
    f.details=f.detailsContent:CreateFontString(nil,'OVERLAY','GameFontHighlight'); f.details:SetPoint('TOPLEFT'); f.details:SetWidth(embedded and 344 or 340); f.details:SetJustifyH('LEFT'); f.details:SetJustifyV('TOP')
    readableFont(f.details,14,3)
    f.candidateTitle=detailHost:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); f.candidateTitle:SetPoint('TOPLEFT',f,'TOPLEFT',embedded and 516 or 495,embedded and -414 or y(-225))
    f.candidateScroll=CreateFrame('ScrollFrame','OldKrakenOrdersCandidatesScroll',f,'UIPanelScrollFrameTemplate'); f.candidateScroll:SetPoint('TOPLEFT',f,'TOPLEFT',embedded and 516 or 495,embedded and -434 or y(-244)); f.candidateScroll:SetSize(embedded and 356 or 350,embedded and 110 or 96)
    if OldKraken.UIStyle.ScrollBar then OldKraken.UIStyle.ScrollBar(f.candidateScroll) end
    f.candidateContent=CreateFrame('Frame',nil,f.candidateScroll); f.candidateContent:SetSize(330,96); f.candidateScroll:SetScrollChild(f.candidateContent); f.candidates={}
    local previousScroll=f.candidateScroll:GetScript('OnVerticalScroll')
    f.candidateScroll:SetScript('OnVerticalScroll',function(self,value)
        if previousScroll then previousScroll(self,value) end
        changed()
    end)
    local actX = embedded and 516 or 495
    local actY = embedded and -556 or y(-345)
    f.offer=button(f,T('Запропонувати'),actX,actY,130,function() if not selected or not intent(selected,'offer') then showError() end end,'primary',{rounded=true,height=34})
    f.withdraw=button(f,T('Відмовитися'),actX,actY,120,function() if not selected or not intent(selected,'withdraw') then showError() end end,nil,{rounded=true,height=34})
    f.delivered=button(f,T('Передав'),actX+128,actY,100,function() if not selected or not intent(selected,'delivered') then showError() end end,'primary',{rounded=true,height=34})
    f.finish=button(f,T('Отримано'),actX,actY,110,function() if not selected or not ownerAction(selected,'finish') then showError() end end,'primary',{rounded=true,height=34})
    f.cancel=button(f,T('Скасувати'),actX+118,actY,110,function() if not selected or not ownerAction(selected,'cancel') then showError() end end,'danger',{rounded=true,height=34})
    f.reopen=button(f,T('Перевідкрити'),actX,actY,120,function() confirmCardAction(selected,'reopen') end,'primary',{rounded=true,height=34})
    f.masters=button(f,T('Майстри'),embedded and 778 or 735,actY,106,function()
        local o=selected and get(selected)
        if o and OldKraken.WorkshopRecipes then OldKraken.WorkshopRecipes:ShowMasters(o.itemID or 0,o.recipeID or 0) end
    end,nil,{rounded=true,height=34})
    local form=f
    if embedded then
        form=CreateFrame('Frame','OldKrakenWorkshopOrderCreateFrame',parent)
        form:SetSize(900,480); form:SetPoint('TOPLEFT',parent,'TOPLEFT',0,-98); form:EnableMouse(true)
        if OldKraken.UIStyle.PanelFrame then
            form.panel = OldKraken.UIStyle.PanelFrame(form, 'buttonEdge')
            form.panel:SetSize(900, 300)
            form.panel:SetPoint('TOPLEFT', form, 'TOPLEFT', 0, 0)
        end
        f.createForm=form
    end
    local formHost = type(form.panel)=='table' and form.panel or form
    local function formY(standalone,compact) return embedded and compact or standalone end
    local heading=formHost:CreateFontString(nil,'OVERLAY','GameFontNormal')
    heading:SetPoint('TOPLEFT',form,'TOPLEFT',embedded and 20 or 18,formY(-395,-16)); heading:SetText(T('Нове замовлення'))
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(heading, 15, true) end
    if colors.brandGold then heading:SetTextColor(colors.brandGold[1], colors.brandGold[2], colors.brandGold[3]) end
    local professionMenu
    local function chooseRecipe()
        if not OldKraken.WorkshopRecipes then showError(); return end
        OldKraken.WorkshopRecipes:Choose(function(r,owner)
            if not nameOK(owner) or owner==identity or not professionNames[r.profession] then return end
            profession=r.profession; UIDropDownMenu_SetText(professionMenu,professionNames[profession])
            local label=orderItemName(r.item) or (r.product~='' and r.product or r.name)
            form.item:SetText(label); chosenRecipe={item=r.item,recipe=r.recipe,owner=owner}
            if type(form.UpdateItemIcon)=='function' then form.UpdateItemIcon() end
            saveDraft()
        end,profession)
    end
    local recipeLabel=formHost:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); recipeLabel:SetPoint('TOPLEFT',form,'TOPLEFT',embedded and 20 or 18,formY(-420,-48)); recipeLabel:SetText(T('Рецепт'))
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(recipeLabel, 12) end
    if colors.mutedText then recipeLabel:SetTextColor(colors.mutedText[1], colors.mutedText[2], colors.mutedText[3]) end
    form.item=button(formHost,recipePlaceholder(),embedded and 20 or 18,formY(-438,-68),embedded and 700 or 300,chooseRecipe,nil,{rounded=true,height=34})
    form.itemIcon=form.item:CreateTexture(nil,'ARTWORK')
    form.itemIcon:SetSize(22,22); form.itemIcon:SetPoint('LEFT',form.item,'LEFT',10,0); form.itemIcon:Hide()
    form.UpdateItemIcon=function()
        local fs=type(form.item.GetFontString)=='function' and form.item:GetFontString()
        if chosenRecipe then
            form.itemIcon:SetTexture(orderIcon({itemID=chosenRecipe.item or 0,profession=profession}))
            form.itemIcon:Show()
            if type(fs)=='table' then fs:ClearAllPoints(); fs:SetPoint('LEFT',form.item,'LEFT',38,0); fs:SetPoint('RIGHT',form.item,'RIGHT',-12,0); fs:SetJustifyH('LEFT') end
        else
            form.itemIcon:Hide()
            if type(fs)=='table' then fs:ClearAllPoints(); fs:SetPoint('CENTER',form.item,'CENTER',0,0); fs:SetJustifyH('CENTER') end
        end
    end
    form.quantity=input(formHost,T('Кількість'),embedded and 740 or 335,formY(-420,-48),embedded and 140 or 65,'1',{height=34})
    form.note=input(formHost,T('Коментар'),embedded and 20 or 18,formY(-475,-120),embedded and 500 or 360,'',{height=34})
    for _,field in ipairs({form.quantity,form.note}) do field:SetScript('OnTextChanged',saveDraft) end
    local professionChoices={[0]=T('Оберіть професію')}; for id,name in pairs(professionNames) do professionChoices[id]=name end
    professionMenu=dropdown(formHost,'OldKrakenOrderProfession',embedded and 540 or 400,formY(-492,-138),embedded and 170 or 170,professionIDs,professionChoices,function() return profession end,function(v) if profession~=v and chosenRecipe then chosenRecipe=nil; form.item:SetText(recipePlaceholder()); if type(form.UpdateItemIcon)=='function' then form.UpdateItemIcon() end end; profession=v; saveDraft() end,{rounded=true})
    f.professionMenu=professionMenu
    f.orderForm=form
    local profLabel=formHost:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); profLabel:SetPoint('TOPLEFT',form,'TOPLEFT',embedded and 540 or 400,formY(-475,-120)); profLabel:SetText(T('Професія'))
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(profLabel, 12) end
    if colors.mutedText then profLabel:SetTextColor(colors.mutedText[1], colors.mutedText[2], colors.mutedText[3]) end
    f.materialsMenu=dropdown(formHost,'OldKrakenOrderMaterials',embedded and 726 or 580,formY(-492,-138),embedded and 154 or 140,{'customer','crafter','mixed'},materialNames,function() return materials end,function(v) materials=v; saveDraft() end,{rounded=true})
    local matLabel=formHost:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); matLabel:SetPoint('TOPLEFT',form,'TOPLEFT',embedded and 726 or 580,formY(-475,-120)); matLabel:SetText(T('Ресурси'))
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(matLabel, 12) end
    if colors.mutedText then matLabel:SetTextColor(colors.mutedText[1], colors.mutedText[2], colors.mutedText[3]) end
    f.deadlineMenu=dropdown(formHost,'OldKrakenOrderDeadline',embedded and 20 or 18,formY(-550,-212),160,{3600,21600,86400,604800},deadlineNames,function() return deadline end,function(v) deadline=v; saveDraft() end,{rounded=true})
    local dueLabel=formHost:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); dueLabel:SetPoint('TOPLEFT',form,'TOPLEFT',embedded and 20 or 18,formY(-533,-194)); dueLabel:SetText(T('Термін'))
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(dueLabel, 12) end
    if colors.mutedText then dueLabel:SetTextColor(colors.mutedText[1], colors.mutedText[2], colors.mutedText[3]) end
    button(formHost,T('Опублікувати'),embedded and 700 or 650,formY(-548,-212),180,function()
        if not professionNames[profession] then chatError(T('Old Kraken: оберіть професію або рецепт.')); return end
        if not chosenRecipe or form.item:GetText()==recipePlaceholder() or form.item:GetText()=='' then chatError(T('Old Kraken: оберіть рецепт для замовлення.')); return end
        if chosenRecipe and chosenRecipe.owner==identity then chatError(T('Old Kraken: для замовлення оберіть рецепт іншого майстра.')); return end
        if create(form.item:GetText(),form.quantity:GetText(),'0',form.note:GetText(),chosenRecipe,'0') then
            clearDraft()
            if embedded and OldKraken.Workshop then OldKraken.Workshop:Show('orders') end
            chatInfo(T('Old Kraken: замовлення збережено та поставлено в чергу.'))
        else showError() end
    end,'primary',{rounded=true,height=38})
    local note=formHost:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); note:SetPoint('TOPLEFT',form,'TOPLEFT',embedded and 20 or 18,formY(-603,-264)); note:SetText(T('|cffffc36bВажливо:|r передачу реагентів і готової речі гравці виконують у грі самостійно (обмін або пошта).'))
    if OldKraken.UIStyle.Font then OldKraken.UIStyle.Font(note, 13) end
    note:SetTextColor(0.95, 0.88, 0.72)
    f:HookScript('OnShow',refresh)
    if embedded then form:Hide() end
    f:Hide(); return f
end
function Orders:Show(k)
    connect(); if not active then chatError(T('Old Kraken: замовлення доступні учасникам гільдії.')); return end
    if k and get(k) then selected=k end
    if OldKraken.UIHub and OldKraken.Workshop then
        OldKraken.Workshop:Show('orders')
        return
    end
    if not window then window=createWindow(); restoreDraft() end
    window:Show(); refresh()
end
function Orders:SupportsProfession(id) return professionNames[id]~=nil end
function Orders:GetOpenCounts()
    connect(); if not active then return 0,0 end
    local openCount,availableCount=0,0
    for _,source in ipairs({own,observed}) do
        for _,o in pairs(source) do
            if type(o)=='table' and o.status~='deleted' and displayStatus(o)=='open' then
                openCount=openCount+1
                if o.owner~=identity and canCraft(o) then availableCount=availableCount+1 end
            end
        end
    end
    return openCount,availableCount
end
function Orders:ShowRecipe(r,owner)
    if type(r)~='table' or not professionNames[r.profession] or not int(r.recipe,1,100000000) or not int(r.item,0,100000000) then
        chatError(T('Old Kraken: замовлення для цієї професії недоступне.')); return
    end
    connect(); if not active then return end
    if not nameOK(owner) or owner==identity then
        chatError(T('Old Kraken: для замовлення оберіть рецепт іншого майстра.')); return
    end
    if OldKraken.UIHub and OldKraken.Workshop then
        OldKraken.UIHub:ShowPage('workshop')
    else self:Show() end
    if not window then return end
    local form=window.orderForm
    if form~=window and not self:OpenCreateForm() then return end
    profession=r.profession
    UIDropDownMenu_SetText(window.professionMenu,professionNames[profession])
    form.item:SetText(r.product~='' and r.product or r.name)
    chosenRecipe={item=r.item,recipe=r.recipe,owner=owner}
    if type(form.UpdateItemIcon)=='function' then form.UpdateItemIcon() end
    saveDraft()
    if not OldKraken.UIHub then form:Raise() end
end
function Orders:CreatePanel(parent)
    if not window then window=createWindow(parent); restoreDraft() end
    return window
end
function Orders:RefreshEmbedded()
    if window then refresh() end
end
function Orders:OpenCreateForm()
    if not window or not window.createForm then
        chatError(T('Old Kraken: форма нового замовлення недоступна; відкрийте вкладку замовлень у Hub.'))
        return false
    end
    if OldKraken.UIHub and OldKraken.Workshop then OldKraken.Workshop:Navigate('orderCreate')
    else window.createForm:Show() end
    return true
end
function Orders:ShowCreatePanel(show)
    if window and window.createForm then window.createForm:SetShown(show) end
end
OldKraken:On('WORKSHOP_SCOPE_MIGRATED',function(migratedProfile)
    if not active or profile~=migratedProfile then return end
    local savedSequence=scope.orderSequences[identity]
    if int(savedSequence,0,9000000000000000) then sequence=math.max(sequence,savedSequence) end
    for k in pairs(own) do dirty[k]=true end
    for k in pairs(intents) do requestDirty[k]=true end
    nextSync=0
    if window and restoreDraft then restoreDraft() end
    changed()
end)
OldKraken:On('WORKSHOP_SCOPE_DRAFT_RESTORED',function(migratedProfile)
    if active and profile==migratedProfile and window and restoreDraft then restoreDraft() end
end)
OldKraken:On('WORKSHOP_RECIPES_CHANGED',changed)
OldKraken:On('WORKSHOP_INDEX_CHANGED',changed)

OldKraken:On('WORKSHOP_ITEM_DATA_CHANGED',changed)
OldKraken:On('WORKSHOP_PROFESSIONS_CHANGED',changed)

if OldKraken.LocalizeTable then
    OldKraken.LocalizeTable(professionNames)
    OldKraken.LocalizeTable(materialNames)
    OldKraken.LocalizeTable(statusNames)
    OldKraken.LocalizeTable(deadlineNames)
    OldKraken.LocalizeTable(StaticPopupDialogs.OLDKRAKEN_ORDER_CARD_CANCEL)
    OldKraken.LocalizeTable(StaticPopupDialogs.OLDKRAKEN_ORDER_CARD_WITHDRAW)
    OldKraken.LocalizeTable(StaticPopupDialogs.OLDKRAKEN_ORDER_CARD_DELIVERED)
    OldKraken.LocalizeTable(StaticPopupDialogs.OLDKRAKEN_ORDER_CARD_FINISH)
    OldKraken.LocalizeTable(StaticPopupDialogs.OLDKRAKEN_ORDER_REOPEN)
    OldKraken.LocalizeTable(StaticPopupDialogs.OLDKRAKEN_ORDER_DELETE)
end
