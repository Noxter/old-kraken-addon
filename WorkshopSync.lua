-- Versioned recipe snapshots; only snapshots received directly from their owner are relayed.
local comm,codec,recipes=OldKraken.Communication,OldKraken.GroupFinder,OldKraken.WorkshopRecipes
local active,identity,profile,store=false,nil,nil,nil
local indices,indexCount,jobs,incoming,lastRequest={},0,{},{},{}
local nextQuery=0
local function int(n,min,max) return type(n)=='number' and n==n and n%1==0 and n>=min and n<=max end
local function text(s,max) return type(s)=='string' and #s>0 and #s<=max and not s:find('[%z\1-\31\127]') end
local function size(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
local function player()
    if type(UnitName)~='function' then return nil end
    local a,b=UnitName('player'); if not text(a,128) then return nil end
    if type(b)=='string' and b~='' then a=a..' '..b end
    return text(a,128) and a or nil
end
local function validRealm(realm)
    if OldKraken.Database and type(OldKraken.Database.IsValidRealm)=='function' then
        return OldKraken.Database:IsValidRealm(realm)
    end
    if type(issecretvalue)=='function' and issecretvalue(realm) then return false end
    return text(realm,128)
end
local function connect()
    local name=player(); local guild=type(GetGuildInfo)=='function' and GetGuildInfo('player'); local realm=type(GetRealmName)=='function' and GetRealmName()
    if not name or not text(guild,128) or not validRealm(realm) or not OldKraken.DB then
        active,identity,profile,store=false,nil,nil,nil; indices,indexCount,jobs,incoming,lastRequest={},0,{},{},{}; return
    end
    if OldKraken.Database and type(OldKraken.Database.MigrateWorkshopScope)=='function' then
        OldKraken.Database:MigrateWorkshopScope(realm,guild,false)
    end
    local key=realm..'\001'..guild
    if active and identity==name and profile==key then return end
    local db=OldKraken.DB; if type(db.workshop)~='table' then db.workshop={} end
    if type(db.workshop.guilds)~='table' then db.workshop.guilds={} end
    if type(db.workshop.guilds[key])~='table' then db.workshop.guilds[key]={} end
    store=db.workshop.guilds[key]
    if type(store.recipeDirectSnapshots)~='table' then store.recipeDirectSnapshots={} end
    if type(store.recipeSnapshotViews)~='table' then store.recipeSnapshotViews={} end
    active,identity,profile=true,name,key
    indices,indexCount,jobs,incoming,lastRequest={},0,{},{},{}; nextQuery=0
end
local function snapshot(owner)
    if owner==identity then return recipes:ExportSnapshot() end
    local saved=store.recipeDirectSnapshots[owner]
    if type(saved)~='table' or not int(saved.rev,1,9000000000000000) or type(saved.records)~='table' or #saved.records>5000 then return nil end
    for _,r in ipairs(saved.records) do if not recipes:ValidateSnapshotRecord(r) then return nil end end
    return saved.rev,saved.records
end
local function scheduleIndex(target,owner)
    local k=target..'\001'..owner
    if indices[k]==nil then
        if indexCount>=2000 then return end
        indexCount=indexCount+1
    end
    indices[k]={target=target,owner=owner,expires=GetTime()+1800}
end
comm:RegisterHandler('WRQ',function(sender,_,payload)
    if not active or not text(sender,128) or sender==identity or payload~='' then return end
    local now=GetTime(); if lastRequest[sender] and now-lastRequest[sender]<60 then return end
    if not lastRequest[sender] and size(lastRequest)>=1000 then return end
    lastRequest[sender]=now; scheduleIndex(sender,identity)
    for owner in pairs(store.recipeDirectSnapshots) do if owner~=identity then scheduleIndex(sender,owner) end end
end)
comm:RegisterHandler('WRIDX',function(sender,_,payload)
    if not active or not text(sender,128) or sender==identity then return end
    local f=codec._unpackFields(payload,4); if not f or #f~=4 or f[1]~=identity or not text(f[2],128) or f[2]==identity then return end
    local owner,rev,count=f[2],tonumber(f[3]),tonumber(f[4])
    if not int(rev,1,9000000000000000) or rev>GetServerTime()*1000+600000 or not int(count,0,5000) then return end
    local old=store.recipeSnapshotViews[owner]; local oldRev=type(old)=='table' and old.rev or 0
    local directRev=type(old)=='table' and old.directRev or 0
    if not int(oldRev,0,9000000000000000) then oldRev=0 end
    if not int(directRev,0,9000000000000000) then directRev=0 end
    local direct=sender==owner
    if direct then
        if rev<directRev or (rev==oldRev and not (type(old)=='table' and old.relayed)) then return end
    elseif rev<=oldRev then return end
    local pending=incoming[owner]
    local now=GetTime()
    if pending and now<pending.expires and now-pending.lastProgress<180 then
        if pending.provider==owner then
            if not direct or rev<=pending.rev then return end
        elseif not direct and (pending.provider==sender or now-pending.lastProgress<45) then return end
    end
    if not pending and size(incoming)>=8 then return end
    incoming[owner]={provider=sender,rev=rev,count=count,parts={},partPayloads={},received=0,recordCount=0,expires=now+21600,lastProgress=now,sent=false}
end)
comm:RegisterHandler('WRGET',function(sender,_,payload)
    if not active or not text(sender,128) or sender==identity then return end
    local f=codec._unpackFields(payload,3); if not f or #f~=3 or f[1]~=identity or not text(f[2],128) then return end
    local rev,records=snapshot(f[2]); if not rev or rev~=tonumber(f[3]) then return end
    local jobKey=sender..'\001'..f[2]
    if jobs[jobKey] or size(jobs)>=10 then return end
    local chunks,chunk={},{}
    for _,r in ipairs(records) do
        local fields={r.recipe,r.item,r.profession,r.seen,r.name,r.product,r.deleted and 'D' or 'L'}
        local nextChunk={unpack(chunk)}; for _,v in ipairs(fields) do nextChunk[#nextChunk+1]=v end
        local probe={sender,f[2],string.format('%.0f',rev),999,999}; for _,v in ipairs(nextChunk) do probe[#probe+1]=v end
        if #nextChunk>112 or #codec._pack(probe)>2300 then chunks[#chunks+1]=chunk; chunk=fields else chunk=nextChunk end
    end
    if #chunk>0 or #chunks==0 then chunks[#chunks+1]=chunk end
    jobs[jobKey]={target=sender,owner=f[2],rev=rev,chunks=chunks,pos=1,expires=GetTime()+21600}
end)
comm:RegisterHandler('WRPAGE',function(sender,_,payload)
    if not active or not text(sender,128) or sender==identity then return end
    local f=codec._unpackFields(payload,117)
    if not f or #f<5 or (#f-5)%7~=0 or f[1]~=identity or not text(f[2],128) then return end
    local owner,rev,part,total=f[2],tonumber(f[3]),tonumber(f[4]),tonumber(f[5]); local pending=incoming[owner]
    if not pending or pending.provider~=sender or pending.rev~=rev or not int(part,1,5000) or not int(total,1,math.max(1,pending.count)) or part>total or (pending.total and pending.total~=total) or (#f==5 and pending.count>0) then return end
    if GetTime()>=pending.expires then incoming[owner]=nil; return end
    if pending.parts[part] then
        -- A replay may need many minutes to reach a missing late page.
        -- Only an identical page from the selected provider proves activity.
        if pending.partPayloads[part]==payload then pending.lastProgress=GetTime() end
        return
    end
    local records={}
    for i=6,#f,7 do
        if f[i+6]~='D' and f[i+6]~='L' then return end
        local r={recipe=tonumber(f[i]),item=tonumber(f[i+1]),profession=tonumber(f[i+2]),seen=tonumber(f[i+3]),name=f[i+4],product=f[i+5],deleted=f[i+6]=='D' and true or nil}
        if not recipes:ValidateSnapshotRecord(r) then return end
        records[#records+1]=r
    end
    if pending.recordCount+#records>pending.count then incoming[owner]=nil; return end
    pending.total=total; pending.parts[part]=records; pending.partPayloads[part]=payload
    pending.recordCount=pending.recordCount+#records; pending.received=pending.received+1; pending.lastProgress=GetTime()
    if pending.received~=total then return end
    local all,seen={},{}
    for i=1,total do for _,r in ipairs(pending.parts[i]) do
        if seen[r.recipe] or #all>=5000 then incoming[owner]=nil; return end
        seen[r.recipe]=true; all[#all+1]=r
    end end
    if #all~=pending.count then incoming[owner]=nil; return end
    local old=store.recipeSnapshotViews[owner]; local lastDirect=type(old)=='table' and tonumber(old.directRev) or 0
    lastDirect=lastDirect or 0
    if (sender==owner and rev<lastDirect) or (sender~=owner and type(old)=='table' and rev<=(tonumber(old.rev) or 0)) then incoming[owner]=nil; return end
    local mayOverride=sender==owner
    if recipes:ImportSnapshot(owner,all,sender~=owner,mayOverride) then
        store.recipeSnapshotViews[owner]={rev=rev,directRev=sender==owner and rev or lastDirect,relayed=sender~=owner}
        if sender==owner then store.recipeDirectSnapshots[owner]={rev=rev,records=all}
        elseif type(store.recipeDirectSnapshots[owner])=='table' and (tonumber(store.recipeDirectSnapshots[owner].rev) or 0)<rev then
            store.recipeDirectSnapshots[owner]=nil
        end
    end
    incoming[owner]=nil
end)
local listener=CreateFrame('Frame')
for _,event in ipairs({'PLAYER_LOGIN','PLAYER_GUILD_UPDATE','GUILD_ROSTER_UPDATE'}) do pcall(listener.RegisterEvent,listener,event) end
listener:SetScript('OnEvent',connect)
if C_Timer and type(C_Timer.NewTicker)=='function' then C_Timer.NewTicker(3,function()
    connect(); if not active then return end
    local now=GetTime()
    if now>=nextQuery and comm:SendProtocol('WRQ','') then nextQuery=now+180 end
    for owner,pending in pairs(incoming) do
        if now>=pending.expires or now-pending.lastProgress>=180 then incoming[owner]=nil
        else
            if pending.sent and pending.lastRequest and now-pending.lastRequest>=45 then pending.sent=false end
            if not pending.sent and #comm.queue<=8 and comm:SendProtocol('WRGET',codec._pack({pending.provider,owner,string.format('%.0f',pending.rev)})) then pending.sent=true; pending.lastRequest=now end
        end
    end
    local k,index=next(indices)
    if k and #comm.queue<=8 then
        local rev,records=snapshot(index.owner)
        if now>=index.expires or not rev or comm:SendProtocol('WRIDX',codec._pack({index.target,index.owner,string.format('%.0f',rev),#records})) then
            if indices[k]~=nil then indices[k]=nil; indexCount=math.max(0,indexCount-1) end
        end
    end
    local jobKey,job=next(jobs)
    if jobKey and #comm.queue<=8 then
        if now>=job.expires then jobs[jobKey]=nil else
            local fields={job.target,job.owner,string.format('%.0f',job.rev),job.pos,#job.chunks}
            for _,v in ipairs(job.chunks[job.pos]) do fields[#fields+1]=v end
            if comm:SendProtocol('WRPAGE',codec._pack(fields)) then job.pos=job.pos+1; if job.pos>#job.chunks then jobs[jobKey]=nil end end
        end
    end
end) end
