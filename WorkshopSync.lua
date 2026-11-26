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
    local name=player(); local guild=type(GetGuildInfo)=='function' and GetGuildInfo('player'); local realm=resolveRealm()
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
local validatedSnapshots=setmetatable({},{__mode='k'})
local function snapshot(owner)
    if owner==identity then return recipes:ExportSnapshot() end
    local saved=store.recipeDirectSnapshots[owner]
    if type(saved)~='table' or not int(saved.rev,1,9000000000000000) or type(saved.records)~='table' or #saved.records>5000 then return nil end
    local cached=validatedSnapshots[saved]
    if cached and cached.rev==saved.rev and cached.count==#saved.records then return saved.rev,saved.records end
    for _,r in ipairs(saved.records) do if not recipes:ValidateSnapshotRecord(r) then return nil end end
    validatedSnapshots[saved]={rev=saved.rev,count=#saved.records}
    return saved.rev,saved.records
end
local function snapshotMeta(owner)
    if owner==identity then
        if type(recipes.ExportSnapshotMeta)=='function' then return recipes:ExportSnapshotMeta() end
        local rev,recs=recipes:ExportSnapshot(); return rev,recs and #recs or nil
    end
    local rev,recs=snapshot(owner); return rev,recs and #recs or nil
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
local function targetMatchesSelf(part1)
    if not active or not identity then return true end
    local first, last, sz = part1:find('(%d+):', 1)
    if first ~= 1 or not sz or #sz > 4 then return true end
    sz = tonumber(sz)
    if not sz or last + sz > #part1 then return true end
    return part1:sub(last + 1, last + sz) == identity
end
if type(comm.part1Filters)=='table' then
    comm.part1Filters.WRPAGE=targetMatchesSelf
    comm.part1Filters.WRGET=targetMatchesSelf
end
local MAX_STALL_ATTEMPTS = 2
local function storeBackup(pending, sender, rev, count)
    if type(pending.backups) ~= 'table' then pending.backups = {} end
    if type(pending.failed) == 'table' and pending.failed[sender] then return end
    local existing = pending.backups[sender]
    if existing and existing.rev > rev then return end
    if not existing and size(pending.backups) >= 8 then return end
    pending.backups[sender] = { rev = rev, count = count }
end
local function pickBackup(pending, owner)
    if type(pending.backups) ~= 'table' then return nil end
    local bestName, bestEntry
    for name, entry in pairs(pending.backups) do
        if not (type(pending.failed) == 'table' and pending.failed[name]) then
            if not bestEntry
                or entry.rev > bestEntry.rev
                or (entry.rev == bestEntry.rev and (name == owner or (bestName ~= owner and name < bestName))) then
                bestName, bestEntry = name, entry
            end
        end
    end
    if bestName then pending.backups[bestName] = nil end
    return bestName, bestEntry
end
comm:RegisterHandler('WRIDX',function(sender,_,payload)
    if not active or not text(sender,128) or sender==identity then return end
    local f=codec._unpackFields(payload,4); if not f or #f~=4 or not text(f[1],128) or not text(f[2],128) then return end
    if f[1]~=identity then
        local target,owner,rev=f[1],f[2],tonumber(f[3])
        if owner~=identity and int(rev,1,9000000000000000) then
            local k=target..'\001'..owner
            local entry=indices[k]
            if entry~=nil then
                local saved=store.recipeDirectSnapshots[owner]
                local ourRev=type(saved)=='table' and tonumber(saved.rev) or 0
                if rev>=(ourRev or 0) then
                    if sender==owner or (entry.seenRelay and entry.seenRelay~=sender) then
                        indices[k]=nil; indexCount=math.max(0,indexCount-1)
                    else
                        entry.seenRelay=sender
                    end
                end
            end
        end
        return
    end
    if f[2]==identity then return end
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
            if not direct or rev<=pending.rev then
                if sender~=pending.provider then storeBackup(pending,sender,rev,count) end
                return
            end
        elseif not direct and (pending.provider==sender or now-pending.lastProgress<45) then
            if sender~=pending.provider then storeBackup(pending,sender,rev,count) end
            return
        end
    end
    if not pending and size(incoming)>=8 then return end
    local backups=pending and pending.backups or {}
    local failed=pending and pending.failed or {}
    backups[sender]=nil
    failed[sender]=nil
    incoming[owner]={provider=sender,rev=rev,count=count,parts={},partPayloads={},received=0,recordCount=0,expires=now+21600,lastProgress=now,lastNewProgress=now,sent=false,stalledAttempts=0,backups=backups,failed=failed}
end)
local function handleWRGET(sender,payload)
    if not active or not text(sender,128) or sender==identity then return end
    local f=codec._unpackFields(payload,3); if not f or #f~=3 or f[1]~=identity or not text(f[2],128) then return end
    local rev,records=snapshot(f[2]); if not rev or rev~=tonumber(f[3]) then return end
    local jobKey=sender..'\001'..f[2]
    if jobs[jobKey] or size(jobs)>=10 then return end
    local headerBytes=#codec._pack({sender,f[2],string.format('%.0f',rev),999,999})
    local chunks,chunk,chunkBytes={}, {}, headerBytes
    for _,r in ipairs(records) do
        local fields={r.recipe,r.item,r.profession,r.seen,r.name,r.product,r.deleted and 'D' or 'L'}
        local fieldsBytes=#codec._pack(fields)
        if #chunk>0 and (#chunk+7>112 or chunkBytes+fieldsBytes>2300) then
            chunks[#chunks+1]=chunk; chunk=fields; chunkBytes=headerBytes+fieldsBytes
        else
            for _,v in ipairs(fields) do chunk[#chunk+1]=v end
            chunkBytes=chunkBytes+fieldsBytes
        end
    end
    if #chunk>0 or #chunks==0 then chunks[#chunks+1]=chunk end
    jobs[jobKey]={target=sender,owner=f[2],rev=rev,chunks=chunks,pos=1,expires=GetTime()+21600}
end
comm:RegisterHandler('WRGET',function(sender,_,payload)
    local t0 = OldKraken and OldKraken.perfEnabled and type(debugprofilestop) == 'function' and debugprofilestop() or nil
    handleWRGET(sender,payload)
    if t0 and OldKraken.PerfRecord then OldKraken:PerfRecord('wk.wrget', debugprofilestop() - t0) end
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
    local progressNow=GetTime()
    pending.total=total; pending.parts[part]=records; pending.partPayloads[part]=payload
    pending.recordCount=pending.recordCount+#records; pending.received=pending.received+1; pending.lastProgress=progressNow; pending.lastNewProgress=progressNow; pending.stalledAttempts=0
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
local function runSyncTick()
    connect(); if not active then return end
    local now=GetTime()
    if now>=nextQuery and comm:SendProtocol('WRQ','') then nextQuery=now+600 end
    for owner,pending in pairs(incoming) do
        if now>=pending.expires or now-pending.lastProgress>=180 then incoming[owner]=nil
        else
            if pending.sent and pending.lastRequest and now-pending.lastRequest>=45 then
                local hasBackup=type(pending.backups)=='table' and next(pending.backups)~=nil
                local stalledNoNew=(now-(pending.lastNewProgress or pending.lastProgress))>=45
                local stalledNoActivity=(now-pending.lastProgress)>=45
                if (pending.stalledAttempts or 0)>=MAX_STALL_ATTEMPTS and (stalledNoActivity or (hasBackup and stalledNoNew)) then
                    pending.failed=pending.failed or {}
                    pending.failed[pending.provider]=true
                    local nextProvider,backup=pickBackup(pending,owner)
                    if nextProvider then
                        pending.provider=nextProvider; pending.rev=backup.rev; pending.count=backup.count
                        pending.parts={}; pending.partPayloads={}; pending.received=0; pending.recordCount=0; pending.total=nil
                        pending.sent=false; pending.stalledAttempts=0; pending.lastProgress=now; pending.lastNewProgress=now
                    else
                        incoming[owner]=nil
                        pending=nil
                        if nextQuery>now+60 then nextQuery=now+60 end
                    end
                else
                    pending.sent=false
                end
            end
            if pending and not pending.sent and #comm.queue<=8 and comm:SendProtocol('WRGET',codec._pack({pending.provider,owner,string.format('%.0f',pending.rev)})) then
                pending.sent=true; pending.lastRequest=now; pending.stalledAttempts=(pending.stalledAttempts or 0)+1
            end
        end
    end
    local k,index=next(indices)
    if k and #comm.queue<=8 then
        local rev,recordCount=snapshotMeta(index.owner)
        if now>=index.expires or not rev or comm:SendProtocol('WRIDX',codec._pack({index.target,index.owner,string.format('%.0f',rev),recordCount})) then
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
end
if C_Timer and type(C_Timer.NewTicker)=='function' then C_Timer.NewTicker(3,function()
    local t0 = OldKraken and OldKraken.perfEnabled and type(debugprofilestop) == 'function' and debugprofilestop() or nil
    runSyncTick()
    if t0 and OldKraken.PerfRecord then OldKraken:PerfRecord('wk.sync', debugprofilestop() - t0) end
end) end
