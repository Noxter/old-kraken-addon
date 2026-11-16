-- Guild-only event calendar. The event owner is authoritative for signups.
local Events = {}
OldKraken.GuildEvents = Events
local comm, codec = OldKraken.Communication, OldKraken.GroupFinder
local kinds = {raid='Рейд', dungeon='Підземелля', pvp='PvP', guild='Збір гільдії'}
local roles = {tank='Танк', healer='Лікар', dps='DPS', flex='Учасник'}
local statuses = {pending='Очікує', accepted='Прийнято', reserve='Резерв', rejected='Відхилено'}
local roleColors = {tank='ff66b3ff', healer='ff69dc8c', dps='ffff7a6e', flex='ffffd06a'}
local statusColors = {pending='ffffc36b', accepted='ff69dc8c', reserve='ff66b3ff', rejected='ffff7a6e'}
local statusCode = {pending='P',accepted='A',reserve='R',rejected='D'}
local codeStatus = {P='pending',A='accepted',R='reserve',D='rejected'}
local active, identity, profile, storage = false, nil, nil, nil
local events, directEvents, relayEvents, dirty, intents, newDirty, relayDirty = {}, {}, {}, {}, {}, {}, {}
local sequence, lastQuery, nextRetry = 0, 0, 0
local relayStats = {invalid_payload=0, rejected_relay_cancelled=0, rejected_relay_sender=0, rejected_relay_mismatch=0, rejected_relay_stale=0, rejected_relay_equivocation=0, rejected_direct_stale=0, rejected_direct_equivocation=0, rejected_capacity=0}
local window, selected, rows, currentRole, currentKind = nil, nil, {}, 'flex', 'raid'
local refresh
local page = 1
local EVENTS_PER_PAGE = 4
local catalog = OldKraken.ActivityCatalog
local activityLabels = {['']='Не вибрано'}
StaticPopupDialogs.OLDKRAKEN_EVENT_DELETE={
    text='Видалити подію «%s»? Учасники отримають сповіщення про скасування.', button1='Видалити', button2='Назад',
    timeout=0, whileDead=true, hideOnEscape=true, preferredIndex=3,
    OnAccept=function(_,callback) if type(callback)=='function' then callback() end end,
}
for _,options in ipairs({catalog.dungeon,catalog.raid}) do
    for _,entry in ipairs(options) do if entry.value~='' then activityLabels[entry.value]=entry.label end end
end
local function validActivity(kind, id)
    if id=='' then return true end
    if type(id)~='string' then return false end
    for _,entry in ipairs(catalog[kind] or {}) do if entry.value==id then return true end end
    return false
end

local function validText(s, low, high)
    return type(s) == 'string' and #s >= low and #s <= high and not s:find('[%z\1-\31\127]')
end
local function eventKey(owner, id) return owner .. '\001' .. id end
local function validID(s) return validText(s, 1, 64) and s:match('^[%w%-]+$') ~= nil end
local function count(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
local function acceptedCount(e)
    local n=0; for name in pairs(e.people) do if (e.statuses[name] or 'accepted')=='accepted' then n=n+1 end end; return n
end
local function character()
    if type(UnitName) ~= 'function' then return nil end
    local a,b = UnitName('player')
    if not validText(a,1,128) then return nil end
    if type(b) == 'string' and b ~= '' then return a .. ' ' .. b end
    return a
end
local function usable(value,kind)
    return type(value)==kind and not (type(issecretvalue)=='function' and issecretvalue(value))
end
local function participantClasses()
    local classes={}
    if type(GetNumGuildMembers)=='function' and type(GetGuildRosterInfo)=='function' then
        local ok,total=pcall(GetNumGuildMembers)
        if ok and usable(total,'number') and total>=0 and total<=10000 then
            for i=1,math.floor(total) do
                local success,name,_,_,_,_,_,_,_,_,_,class=pcall(GetGuildRosterInfo,i)
                if success and usable(name,'string') and name~='' and usable(class,'string') and class~='' then classes[name]=class end
            end
        end
    end
    if type(UnitName)=='function' and type(UnitClass)=='function' then
        local units={'player'}; local raid=false
        if type(IsInRaid)=='function' then local ok,value=pcall(IsInRaid); if ok and (usable(value,'boolean') or usable(value,'number')) then raid=value==true or value==1 end end
        for i=1,raid and 40 or 4 do units[#units+1]=(raid and 'raid' or 'party')..i end
        for _,unit in ipairs(units) do
            local ok,first,last=pcall(UnitName,unit); local got,_,class=pcall(UnitClass,unit)
            if ok and got and usable(first,'string') and first~='' and usable(class,'string') and class~='' then
                local name=first; if usable(last,'string') and last~='' then name=name..' '..last end
                classes[name]=class
            end
        end
    end
    return classes
end
local function participantName(name,classes)
    local class=classes[name]
    local color=class and type(RAID_CLASS_COLORS)=='table' and RAID_CLASS_COLORS[class]
    if type(color)=='table' and usable(color.r,'number') and usable(color.g,'number') and usable(color.b,'number') then
        local function channel(v) return math.floor(math.max(0,math.min(1,v))*255) end
        return string.format('|cff%02x%02x%02x%s|r',channel(color.r),channel(color.g),channel(color.b),name)
    end
    return name
end
local function participantRoleStatus(role,status)
    return (catalog.roleIcons[role] or '')..' |c'..(roleColors[role] or 'ffb5b5b5')..(roles[role] or role)..'|r · |c'..(statusColors[status] or 'ffb5b5b5')..(statuses[status] or 'Невідомо')..'|r'
end
local function participantLabel(name,role,status,classes)
    return participantName(name,classes)..' · '..participantRoleStatus(role,status)
end
local function save()
    if not storage then return end
    storage.owned, storage.observed, storage.intents, storage.sequence = {}, {}, {}, sequence
    for key, e in pairs(directEvents) do
        if e.owner == identity then storage.owned[key] = e else storage.observed[key] = e end
    end
    for key, intent in pairs(intents) do storage.intents[key] = intent end
end
local function encode(e)
    local names = {}; for name in pairs(e.people) do names[#names+1] = name end
    table.sort(names)
    local f = {e.id,e.owner,e.rev,e.when,e.kind,e.size,e.cancelled and '1' or '0',e.title,e.description,#names}
    for _, name in ipairs(names) do f[#f+1]=name; f[#f+1]=e.people[name] end
    f[#f+1]=e.activity or ''
    local codes={}; for _,name in ipairs(names) do codes[#codes+1]=statusCode[(e.statuses or {})[name] or 'accepted'] end
    f[#f+1]=table.concat(codes)
    return codec._pack(f)
end
local function decode(sender, payload, isRelay)
    local f = codec._unpackFields(payload, 212)
    if not f or #f < 10 then return nil end
    local id, owner, rev, when, kind, size, cancelled, title, description, n = unpack(f,1,10)
    rev, when, size, n = tonumber(rev), tonumber(when), tonumber(size), tonumber(n)
    if not validID(id) or not validText(owner,1,128) or (not isRelay and sender ~= owner)
        or not rev or rev % 1 ~= 0 or rev < 1 or rev > 2147483647
        or not when or when % 1 ~= 0 or when < GetServerTime()-172800 or when > GetServerTime()+31622400
        or not kinds[kind] or not size or size % 1 ~= 0 or size < 2 or size > 40
        or (cancelled ~= '0' and cancelled ~= '1') or not validText(title,1,100)
        or not validText(description,0,400) or not n or n % 1 ~= 0 or n < 0 or n > 100 or (#f ~= 10 + n*2 and #f ~= 11 + n*2 and #f ~= 12 + n*2) then return nil end
    local activity=f[11+n*2] or ''
    if not validActivity(kind,activity) then return nil end
    local codes=f[12+n*2]
    if codes and (#codes~=n or codes:find('[^PARD]')) then return nil end
    local people,personStatuses = {},{}
    for i=1,n do
        local name, role = f[9+i*2], f[10+i*2]
        if not validText(name,1,128) or not roles[role] or people[name] then return nil end
        people[name] = role
        personStatuses[name]=codes and codeStatus[codes:sub(i,i)] or 'accepted'
    end
    local e={id=id,owner=owner,rev=rev,when=when,kind=kind,size=size,cancelled=cancelled=='1',title=title,description=description,people=people,statuses=personStatuses,activity=activity}
    if acceptedCount(e)>size then return nil end
    return e
end
local function fire() OldKraken:Fire('GUILD_EVENTS_CHANGED') end

local function receiveEvent(sender, _, payload, isAnnouncement, isRelay, cancellationOnly)
    if not active then return end
    local e = decode(sender, payload, isRelay)
    if not e then relayStats.invalid_payload=relayStats.invalid_payload+1; return end
    local key = eventKey(e.owner,e.id)

    if isRelay then
        -- A relay is display-only: never accept cancellations or announcements
        -- through it, and never let it replace a directly received owner snapshot.
        if cancellationOnly or isAnnouncement or e.cancelled then relayStats.rejected_relay_cancelled=relayStats.rejected_relay_cancelled+1; return end
        if sender == e.owner or e.owner == identity then relayStats.rejected_relay_sender=relayStats.rejected_relay_sender+1; return end
        local direct = directEvents[key]
        if direct and (direct.when~=e.when or direct.kind~=e.kind or direct.title~=e.title
            or direct.description~=e.description or direct.size~=e.size or direct.activity~=e.activity) then relayStats.rejected_relay_mismatch=relayStats.rejected_relay_mismatch+1; return end
        local previous = relayEvents[key]
        if not direct and not previous and not events[key] and count(events)>=100 then relayStats.rejected_capacity=relayStats.rejected_capacity+1; return end
        if previous then
            if previous.rev > e.rev then relayStats.rejected_relay_stale=relayStats.rejected_relay_stale+1; return end
            if previous.rev == e.rev and encode(previous) ~= payload then relayStats.rejected_relay_equivocation=relayStats.rejected_relay_equivocation+1; return end
        end
        e.relayed = true
        e.ownerRev = direct and direct.rev or 0
        relayEvents[key] = e
        storage.relays[key] = payload
        if not direct then events[key] = e end
        fire()
        return
    end

    local old = directEvents[key]
    if old then
        if old.rev > e.rev then relayStats.rejected_direct_stale=relayStats.rejected_direct_stale+1; return end
        if old.rev == e.rev then
            if encode(old) ~= payload then relayStats.rejected_direct_equivocation=relayStats.rejected_direct_equivocation+1; return end
            local intent = intents[key]
            if intent and ((intent.role == 'leave' and not old.people[identity])
                or (intent.role ~= 'leave' and old.people[identity] == intent.role and old.statuses[identity] ~= 'rejected')
                or old.cancelled) then
                intents[key] = nil; save(); fire()
            end
            return
        end
    elseif not events[key] and count(events) >= 100 then
        relayStats.rejected_capacity=relayStats.rejected_capacity+1; return
    end

    e.relayed = nil
    e.ownerRev = e.rev
    e.versions = old and old.versions or nil
    directEvents[key] = e
    events[key] = e
    -- Any direct owner snapshot supersedes the cached relay, even if its
    -- untrusted revision number is larger than the owner's current revision.
    relayEvents[key], storage.relays[key] = nil, nil

    local intent = intents[key]
    if intent and ((intent.role == 'leave' and not e.people[identity])
        or (intent.role ~= 'leave' and e.people[identity] == intent.role and e.statuses[identity] ~= 'rejected')
        or e.cancelled) then intents[key] = nil end

    if e.cancelled and e.owner~=identity and e.people[identity] and e.statuses[identity]~='rejected' and not storage.cancelledSeen[key] then
        storage.cancelledSeen[key]=e.when+172800
        OldKraken:Fire('GUILD_EVENTS_CANCELLED',key,e)
    end
    if not e.cancelled then storage.cancelledSeen[key]=nil end
    save(); fire()
    if isAnnouncement and not old and e.owner~=identity and not e.cancelled then
        local created=tonumber(e.id:match('^(%d+)%-'))
        local age=created and GetServerTime()-created
        if age and age>=0 and age<=120 then OldKraken:Fire('GUILD_EVENTS_NEW',key,e) end
    end
end
comm:RegisterHandler('CEVENT', function(sender,id,payload) receiveEvent(sender,id,payload,false) end)
comm:RegisterHandler('CVNEW', function(sender,id,payload) receiveEvent(sender,id,payload,true) end)
comm:RegisterHandler('CVCANCEL', function(sender,id,payload) receiveEvent(sender,id,payload,false,true,true) end)
comm:RegisterHandler('CVSTATE', function(sender,id,payload) receiveEvent(sender,id,payload,false,true) end)

local function canPerformRole(name,role)
    return role=='flex' or codec:CanPerformRole(name,role)
end
local function updateSignup(sender, owner, id, role, version)
    local key = eventKey(owner,id)
    local e = events[key]
    if not e or e.owner ~= identity or e.cancelled or not validText(sender,1,128)
        or (role ~= 'leave' and not roles[role]) or not version or version % 1 ~= 0 or version < 1 or version > 9000000000000000 then return end
    if role~='leave' and not canPerformRole(sender,role) then return end
    e.versions = e.versions or {}
    if e.versions[sender] and e.versions[sender] >= version then dirty[key]=true; return end
    if not e.versions[sender] and count(e.versions) >= 200 then return end
    if role ~= 'leave' and not e.people[sender] and count(e.people) >= 100 then return end
    local previous = e.people[sender]
    local previousStatus=e.statuses[sender]
    e.people[sender] = role ~= 'leave' and role or nil
    e.statuses[sender] = role~='leave' and (sender==identity and 'accepted' or ((previousStatus and previousStatus~='rejected') and previousStatus or 'pending')) or nil
    if sender==identity and e.statuses[sender]=='accepted' and acceptedCount(e)>e.size then e.people[sender],e.statuses[sender]=previous,previousStatus; return end
    e.rev = e.rev + 1
    if #encode(e) > 2560 then e.people[sender],e.statuses[sender] = previous,previousStatus; e.rev = e.rev - 1; return end
    e.versions[sender] = version
    dirty[key] = true
    if sender == identity then intents[key] = nil end
    save(); fire()
    if sender ~= identity and role ~= 'leave' and (not previous or previousStatus=='rejected') then
        OldKraken:Fire('GUILD_EVENTS_NEW_SIGNUP',key,e,sender,role)
    end
end
comm:RegisterHandler('CEVRSVP', function(sender, _, payload)
    if not active then return end
    local f = codec._unpackFields(payload,5)
    if not f or (#f~=4 and #f~=5) or f[1]~=identity or not validID(f[2]) then return end
    if f[5] then
        if not f[5]:match('^[01][01][01]$') then return end
        local available=codec:GetGameRoles(sender) or {tank=f[5]:sub(1,1)=='1',healer=f[5]:sub(2,2)=='1',dps=f[5]:sub(3,3)=='1'}
        if f[3]~='leave' and f[3]~='flex' and not available[f[3]] then return end
        codec.roleCapabilities=codec.roleCapabilities or {}; codec.roleCapabilities[sender]=available
    end
    updateSignup(sender,f[1],f[2],f[3],tonumber(f[4]))
end)
comm:RegisterHandler('CEVQUERY', function(_, _, payload)
    if not active or payload ~= '' then return end
    local now = GetTime(); if now - lastQuery < 20 then return end; lastQuery = now
    for key,e in pairs(events) do if e.owner == identity then dirty[key]=true end end
    for key in pairs(storage.relays) do relayDirty[key]=true end
end)

function Events:Create(title, description, when, kind, size, activity)
    size=tonumber(size)
    activity=activity or ''
    if not active or not validText(title,1,100) or not validText(description,0,400) or not kinds[kind]
        or not validActivity(kind,activity)
        or not size or size % 1 ~= 0 or size < 2 or size > 40
        or not when or when <= GetServerTime() or when > GetServerTime()+31622400 or count(events)>=100 then return false end
    sequence=sequence+1
    local id=tostring(GetServerTime())..'-'..tostring(math.random(100000,999999))..'-'..sequence
    local e={id=id,owner=identity,rev=1,when=when,kind=kind,size=size,cancelled=false,title=title,description=description,people={},statuses={},versions={},activity=activity}
    local key=eventKey(identity,id); events[key]=e; directEvents[key]=e; dirty[key]=true; newDirty[key]=true; save(); fire(); return true
end
local raidInvites
local function alreadyGrouped(name)
    return (type(UnitInRaid)=='function' and UnitInRaid(name)) or (type(UnitInParty)=='function' and UnitInParty(name))
end
local function canLeadInvites()
    local size=type(GetNumGroupMembers)=='function' and GetNumGroupMembers() or 0
    if not size or size==0 then return true end
    if type(UnitIsGroupLeader)~='function' then return true end
    return UnitIsGroupLeader('player') or (type(UnitIsGroupAssistant)=='function' and UnitIsGroupAssistant('player'))
end
function Events:PumpRaidInvites()
    local job=raidInvites
    if not job then return end
    local e=events[job.key]
    if not active or not e or e.owner~=identity or e.cancelled or e.kind~='raid' or GetTime()>job.expires then raidInvites=nil; return end
    if type(InCombatLockdown)=='function' and InCombatLockdown() then return end
    if not canLeadInvites() then raidInvites=nil; print('Old Kraken: для запрошень потрібні права лідера або помічника рейду.'); return end
    local inRaid=type(IsInRaid)=='function' and IsInRaid()
    local count=type(GetNumGroupMembers)=='function' and GetNumGroupMembers() or 0
    if not inRaid and count and count>0 then
        if not job.convertAt or GetTime()-job.convertAt>=5 then
            local convert=C_PartyInfo and C_PartyInfo.ConvertToRaid or ConvertToRaid
            if type(convert)~='function' then raidInvites=nil; print('Old Kraken: перетворіть групу на рейд вручну.'); return end
            local ok,result=pcall(convert); job.convertAt=GetTime()
            if not ok or result==false then raidInvites=nil; print('Old Kraken: не вдалося перетворити групу на рейд.'); end
        end
        return
    end
    if inRaid and count>=40 then raidInvites=nil; return end
    if not inRaid and job.sentSolo>=4 then return end
    while job.index<=#job.names do
        local name=job.names[job.index]; job.index=job.index+1
        if e.people[name] and e.statuses[name]=='accepted' and name~=identity and not alreadyGrouped(name) then
            local invite=C_PartyInfo and C_PartyInfo.InviteUnit or InviteUnit
            if type(invite)~='function' then raidInvites=nil; print('Old Kraken: API запрошень недоступний.'); return end
            local ok,result=pcall(invite,name)
            if not ok or result==false then raidInvites=nil; print('Old Kraken: не вдалося надіслати запрошення в рейд.'); return end
            if not inRaid then job.sentSolo=job.sentSolo+1 end
            return
        end
    end
    if inRaid then raidInvites=nil end
end
local function queueRaidInvites(key,names)
    local e=events[key]
    if not active or not e or e.owner~=identity or e.cancelled or e.kind~='raid' or not canLeadInvites() then return false end
    if raidInvites and raidInvites.key~=key then return false end
    if not raidInvites then raidInvites={key=key,names={},seen={},index=1,sentSolo=0,expires=GetTime()+300} end
    local added=0
    for _,name in ipairs(names) do
        if name~=identity and e.people[name] and e.statuses[name]=='accepted' and not alreadyGrouped(name) and not raidInvites.seen[name] then
            raidInvites.names[#raidInvites.names+1]=name; raidInvites.seen[name]=true; added=added+1
        end
    end
    Events:PumpRaidInvites()
    return added>0
end
function Events:InviteMember(key,name) return queueRaidInvites(key,{name}) end
function Events:InviteAll(key)
    local e=events[key]; if not e then return false end
    if window.filterEvent~=selected then window.filterEvent=selected; window.roleFilter=false end
        local names={}; for name,role in pairs(e.people) do
            if not window.roleFilter or role==window.roleFilter then names[#names+1]=name end
        end; table.sort(names)
    return queueRaidInvites(key,names)
end
local raidInviteFrame=CreateFrame('Frame')
raidInviteFrame:RegisterEvent('GROUP_ROSTER_UPDATE')
raidInviteFrame:SetScript('OnEvent',function() Events:PumpRaidInvites() end)
local inviteElapsed=0
raidInviteFrame:SetScript('OnUpdate',function(_,elapsed)
    if not raidInvites then inviteElapsed=0; return end
    inviteElapsed=inviteElapsed+elapsed
    if inviteElapsed>=0.8 then inviteElapsed=0; Events:PumpRaidInvites() end
end)

function Events:Cancel(key)
    local e=events[key]; if not active or not e or e.owner~=identity or e.cancelled then return false end
    e.cancelled=true; e.rev=e.rev+1; dirty[key]=true; save(); fire(); return true
end
function Events:Signup(key, role)
    local e=events[key]
    if not active or not e or e.relayed or e.cancelled or (role~='leave' and not roles[role]) then return false end
    if role~='leave' and not canPerformRole(identity,role) then return false end
    if role~='leave' and e.owner==identity and e.statuses[identity]~='accepted' and acceptedCount(e)>=e.size then return false end
    sequence=math.max(sequence+1,GetServerTime()*1000)
    local intent={role=role,version=sequence}; intents[key]=intent
    if e.owner==identity then updateSignup(identity,e.owner,e.id,role,intent.version) end
    save(); nextRetry=0; fire(); return true
end
function Events:Decide(key, name, status)
    local e=events[key]
    if not active or not e or e.owner~=identity or e.cancelled or not e.people[name] or name==identity or not statuses[status] or status=='pending' then return false end
    if (status=='accepted' or status=='reserve') and not canPerformRole(name,e.people[name]) then return false end
    if status=='accepted' and e.statuses[name]~='accepted' and acceptedCount(e)>=e.size then return false end
    if e.statuses[name]==status then return true end
    local previous=e.statuses[name]
    e.statuses[name]=status; e.rev=e.rev+1
    if #encode(e)>2560 then e.statuses[name]=previous; e.rev=e.rev-1; return false end
    dirty[key]=true; save(); fire(); return true
end

local function connect()
    local name, guild = character(), type(GetGuildInfo)=='function' and GetGuildInfo('player')
    local realm = type(GetRealmName)=='function' and GetRealmName() or ''
    if not name or not validText(guild,1,128) or type(realm)~='string' or not OldKraken.DB or type(OldKraken.DB.events)~='table' then
        active=false; events,directEvents,relayEvents,dirty,intents,newDirty,relayDirty={}, {}, {}, {}, {}, {}, {}; selected=nil
        if window then window:Hide() end
        return
    end
    local key=realm..'\001'..guild..'\001'..name
    if active and profile==key then return end
    local root=OldKraken.DB.events
    if root.guildCalendarV1 == nil then root.guildCalendarV1={} end
    if type(root.guildCalendarV1)~='table' then active=false; return end
    if root.guildCalendarV1[key] == nil then root.guildCalendarV1[key]={} end
    if type(root.guildCalendarV1[key])~='table' then active=false; return end
    active,identity,profile,storage=true,name,key,root.guildCalendarV1[key]
    if type(storage.cancelledSeen)~='table' then storage.cancelledSeen={} end
    if type(storage.relays)~='table' then storage.relays={} end
    for k,expiry in pairs(storage.cancelledSeen) do if type(expiry)~='number' or expiry<GetServerTime() then storage.cancelledSeen[k]=nil end end
    events,directEvents,relayEvents,dirty,intents,newDirty,relayDirty={}, {}, {}, {}, {}, {}, {}
    sequence=type(storage.sequence)=='number' and storage.sequence or 0
    if type(storage.owned)=='table' then
        for k,e in pairs(storage.owned) do
            if type(e)=='table' and e.owner==identity and type(e.people)=='table' then
                local ok,payload=pcall(encode,e)
                local valid=ok and decode(identity,payload)
                if valid and k==eventKey(identity,valid.id) then valid.versions=type(e.versions)=='table' and e.versions or {}; events[k]=valid; directEvents[k]=valid; dirty[k]=true end
            end
        end
    end
    if type(storage.observed)=='table' then
        for k,e in pairs(storage.observed) do
            if count(events)>=100 then break end
            if type(e)=='table' and e.owner~=identity and validText(e.owner,1,128) and type(e.people)=='table' then
                local ok,payload=pcall(encode,e)
                local valid=ok and decode(e.owner,payload)
                if valid and k==eventKey(valid.owner,valid.id) then
                    if e.relayed==true then
                        valid.relayed=true; valid.ownerRev=0; relayEvents[k]=valid
                        if not events[k] then events[k]=valid end
                        storage.relays[k]=storage.relays[k] or payload
                    else
                        valid.ownerRev=valid.rev; directEvents[k]=valid; events[k]=valid
                    end
                end
            end
        end
    end
    for k,payload in pairs(storage.relays) do
        local e=type(payload)=='string' and decode(nil,payload,true)
        if not e or e.owner==identity or k~=eventKey(e.owner,e.id) then storage.relays[k]=nil
        else
            e.relayed=true; e.ownerRev=directEvents[k] and directEvents[k].rev or 0
            relayEvents[k]=e
            if not directEvents[k] then events[k]=e end
        end
    end
    if type(storage.intents)=='table' then
        for k,v in pairs(storage.intents) do
            if type(k)=='string' and #k<=193 and type(v)=='table' and (v.role=='leave' or roles[v.role]) and type(v.version)=='number' and v.version>0 and v.version<9000000000000000 then intents[k]={role=v.role,version=v.version} end
        end
    end
    lastQuery, nextRetry = -60, 0
    comm:SendProtocol('CEVQUERY',''); fire()
end
local frame=CreateFrame('Frame')
frame:RegisterEvent('PLAYER_LOGIN'); frame:RegisterEvent('GUILD_ROSTER_UPDATE'); frame:RegisterEvent('GROUP_ROSTER_UPDATE')
frame:SetScript('OnEvent',function(_,event)
    connect()
    if (event=='GUILD_ROSTER_UPDATE' or event=='GROUP_ROSTER_UPDATE') and window and window:IsShown() and refresh then refresh() end
end)
if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(3,function()
        if not active then connect(); return end
        local name,guild=character(),type(GetGuildInfo)=='function' and GetGuildInfo('player')
        if name~=identity or not guild or (type(GetRealmName)=='function' and (GetRealmName()..'\001'..guild..'\001'..name)~=profile) then active=false; connect(); return end
        local removed = false
        for key,e in pairs(events) do
            if e.when < GetServerTime()-172800 then events[key],directEvents[key],relayEvents[key],dirty[key],intents[key],newDirty[key],relayDirty[key],storage.relays[key]=nil,nil,nil,nil,nil,nil,nil,nil; removed=true end
        end
        if removed then save(); fire() end
        local now=GetTime()
        if now>=nextRetry then
            if comm:SendProtocol('CEVQUERY','') then nextRetry=now+180 end
            for key in pairs(intents) do
                local e=events[key]; local intent=intents[key]
                if e and e.owner~=identity then
                    local fields={e.owner,e.id,intent.role,string.format('%.0f',intent.version)}
                    fields[5]=codec:RoleCapabilityCode()
                    comm:SendProtocol('CEVRSVP',codec._pack(fields))
                end
            end
        end
        local key=next(dirty)
        if key then
            local e=events[key]
            local created=e and tonumber(e.id:match('^(%d+)%-'))
            local announce=e and newDirty[key] and not e.cancelled and created and GetServerTime()-created<=120
            if not e or comm:SendProtocol(announce and 'CVNEW' or 'CEVENT',encode(e)) then dirty[key],newDirty[key]=nil,nil end
        end
        local relayKey=next(relayDirty)
        if relayKey and #comm.queue<=8 then
            local payload=storage.relays[relayKey]
            if not payload or comm:SendProtocol('CVSTATE',payload) then relayDirty[relayKey]=nil end
        end
    end)
end

local function parseDate(day, month, year, hour, minute)
    if type(time) ~= 'function' or type(date) ~= 'function' then return nil end
    if not day or not month or not year or type(hour)~='number' or type(minute)~='number' or hour<0 or hour>23 or minute<0 or minute>59 then return nil end
    local ok,stamp=pcall(time,{year=year,month=month,day=day,hour=hour,min=minute,sec=0})
    if not ok or type(stamp)~='number' then return nil end
    local okDate,roundtrip=pcall(date,'*t',stamp)
    if not okDate or type(roundtrip)~='table' or roundtrip.year~=year or roundtrip.month~=month or roundtrip.day~=day or roundtrip.hour~=hour or roundtrip.min~=minute then return nil end
    return stamp
end
local function action(parent, label, x, y, width, callback, variant)
    local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate'); OldKraken.UIStyle.Button(b,variant)
    b:SetSize(width,24); b:SetPoint('TOPLEFT',parent,'TOPLEFT',x,y); b:SetText(label); b:SetScript('OnClick',callback); return b
end
local function field(parent, label, x, y, width, value)
    local caption=parent:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); caption:SetPoint('TOPLEFT',parent,'TOPLEFT',x,y); caption:SetText(label)
    local box=CreateFrame('EditBox',nil,parent,'InputBoxTemplate'); OldKraken.UIStyle.Input(box)
    box:SetPoint('TOPLEFT',parent,'TOPLEFT',x+4,y-18); box:SetSize(width,22); box:SetAutoFocus(false); box:SetText(value or '')
    box.label=caption; box:SetScript('OnEscapePressed',function(self) self:ClearFocus() end); return box
end
local function selectMenu(parent,name,x,y,width,values,labels,get,set,allowed,menuFont)
    local f=CreateFrame('Frame',name,parent,'UIDropDownMenuTemplate'); OldKraken.UIStyle.Dropdown(f)
    f:SetPoint('TOPLEFT',parent,'TOPLEFT',x-16,y+3); UIDropDownMenu_SetWidth(f,width-34); UIDropDownMenu_JustifyText(f,'LEFT')
    UIDropDownMenu_Initialize(f,function(_,level)
        for _,v in ipairs(values) do
            local value=v; local item=UIDropDownMenu_CreateInfo(); item.text=labels[value]; item.value=value; item.checked=get()==value; item.fontObject=menuFont
            item.disabled=allowed and not allowed(value) or false
            item.func=function() if allowed and not allowed(value) then return end; set(value); UIDropDownMenu_SetText(f,labels[value]) end; UIDropDownMenu_AddButton(item,level)
        end
    end)
    if menuFont and _G[name..'Text'] then _G[name..'Text']:SetFontObject(menuFont) end
    UIDropDownMenu_SetText(f,labels[get()]); return f
end
local function selectMinutes(parent,x,y,get,set)
    local f=CreateFrame('Frame','OldKrakenEventsMinute',parent,'UIDropDownMenuTemplate'); OldKraken.UIStyle.Dropdown(f)
    f:SetPoint('TOPLEFT',parent,'TOPLEFT',x-16,y+3); UIDropDownMenu_SetWidth(f,56); UIDropDownMenu_JustifyText(f,'LEFT')
    UIDropDownMenu_Initialize(f,function(_,level,menuValue)
        level=level or 1
        if level==1 then
            for start=0,45,15 do
                local item=UIDropDownMenu_CreateInfo(); item.text=string.format('%02d–%02d',start,start+14); item.hasArrow=true; item.notCheckable=true; item.value=start
                UIDropDownMenu_AddButton(item,level)
            end
        elseif level==2 then
            local list=_G.DropDownList2
            if list then
                if not list.oldKrakenMinuteHook then
                    list:HookScript('OnHide',function(self)
                        if self.oldKrakenMinuteStrata then self:SetFrameStrata(self.oldKrakenMinuteStrata); self.oldKrakenMinuteStrata=nil end
                    end)
                    list.oldKrakenMinuteHook=true
                end
                if not list.oldKrakenMinuteStrata then list.oldKrakenMinuteStrata=list:GetFrameStrata() end
                list:SetFrameStrata('FULLSCREEN_DIALOG')
            end
            local start=tonumber(menuValue or UIDROPDOWNMENU_MENU_VALUE)
            if not start then return end
            for minute=start,start+14 do
                local value=minute; local item=UIDropDownMenu_CreateInfo(); item.text=string.format('%02d',value); item.value=value; item.checked=get()==value
                item.disabled=allowed and not allowed(value) or false
            item.func=function() if allowed and not allowed(value) then return end; set(value); UIDropDownMenu_SetText(f,string.format('%02d',value)) end
                UIDropDownMenu_AddButton(item,level)
            end
        end
    end)
    UIDropDownMenu_SetText(f,string.format('%02d',get())); return f
end
local function datePicker(parent, onChanged)
    local chosen, month, year
    local caption=parent:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
    caption:SetPoint('TOPLEFT',parent,'TOPLEFT',426,-359); caption:SetText('Дата')
    local muted=OldKraken.UIStyle.Colors and OldKraken.UIStyle.Colors.mutedText
    if muted then caption:SetTextColor(muted[1],muted[2],muted[3]) end
    local button=action(parent,'Обрати дату',426,-380,150,function() end)
    button:SetHeight(34)
    parent.dateButton=button; parent.dateCaption=caption
    local popup=CreateFrame('Frame',nil,parent,'BackdropTemplate')
    parent.datePopup=popup
    popup:SetSize(242,250); popup:SetPoint('BOTTOMLEFT',button,'TOPLEFT',0,4)
    popup:SetFrameLevel(parent:GetFrameLevel()+20); popup:EnableMouse(true)
    popup:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
    popup:SetBackdropColor(0.07,0.08,0.09,1); popup:SetBackdropBorderColor(0.3,0.35,0.4,1)
    local months={'Січень','Лютий','Березень','Квітень','Травень','Червень','Липень','Серпень','Вересень','Жовтень','Листопад','Грудень'}
    local title=popup:CreateFontString(nil,'OVERLAY','GameFontNormal'); title:SetPoint('TOP',popup,'TOP',0,-12)
    local cells={}
    local function render()
        title:SetText(months[month]..' '..year)
        local first=date('*t',time({year=year,month=month,day=1,hour=12}))
        local following=month==12 and 1 or month+1
        local followingYear=month==12 and year+1 or year
        local last=date('*t',time({year=followingYear,month=following,day=1,hour=12})-86400).day
        local offset=(first.wday+5)%7
        for i,cell in ipairs(cells) do
            local day=i-offset
            if day>0 and day<=last then
                cell.day=day; cell:SetText(day); cell:Show()
                if chosen and chosen.day==day and chosen.month==month and chosen.year==year then cell:LockHighlight() else cell:UnlockHighlight() end
            else cell.day=nil; cell:UnlockHighlight(); cell:Hide() end
        end
    end
    action(popup,'‹',8,-7,30,function() month=month-1; if month==0 then month=12; year=year-1 end; render() end)
    action(popup,'›',204,-7,30,function() month=month+1; if month==13 then month=1; year=year+1 end; render() end)
    for i,label in ipairs({'Пн','Вт','Ср','Чт','Пт','Сб','Нд'}) do
        local text=popup:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); text:SetPoint('TOPLEFT',popup,'TOPLEFT',11+(i-1)*32,-40); text:SetWidth(30); text:SetText(label)
    end
    for i=1,42 do
        local cell=action(popup,'',8+((i-1)%7)*32,-60-math.floor((i-1)/7)*30,30,function(self)
            chosen={day=self.day,month=month,year=year}; button:SetText(string.format('%02d.%02d.%04d',chosen.day,chosen.month,chosen.year)); popup:Hide()
            if onChanged then onChanged() end
        end)
        cells[i]=cell
    end
    button:SetScript('OnClick',function()
        if popup:IsShown() then popup:Hide(); return end
        local current=chosen or date('*t'); month,year=current.month,current.year; render(); popup:Show()
    end)
    popup:Hide()
    parent:HookScript('OnHide',function() popup:Hide() end)
    return function() return chosen end, function(d, m, y)
        chosen = {day = d, month = m, year = y}
        button:SetText(string.format('%02d.%02d.%04d', d, m, y))
        if onChanged then onChanged() end
    end
end
local function iconAction(button,row,x,texture,hint)
    button:ClearAllPoints(); button:SetPoint('TOPLEFT',row,'TOPLEFT',x,-3); button:SetSize(24,24); button:SetText('')
    button.art=button:CreateTexture(nil,'ARTWORK'); button.art:SetSize(19,19); button.art:SetPoint('CENTER',button,'CENTER',0,0); button.art:SetTexture(texture)
    button:SetScript('OnEnter',function(self)
        if GameTooltip then GameTooltip:SetOwner(self,'ANCHOR_RIGHT'); GameTooltip:SetText(hint); GameTooltip:AddLine(row.member or '',1,1,1); GameTooltip:Show() end
    end)
    button:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
end
local function readableFont(text,size)
    local font=type(text.GetFont)=='function' and text:GetFont() or nil
    if type(font)~='string' or font=='' then font=STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF' end
    text:SetFont(font,size,'OUTLINE')
    text:SetShadowColor(0,0,0,0.9); text:SetShadowOffset(1,-1)
end
local function largeRoleIcon(role,size)
    return ((catalog.roleIcons[role] or '—'):gsub(':16:16:',':'..size..':'..size..':'))
end
local function roleColumnText(e,classes,role)
    local names={}
    for name,memberRole in pairs(e.people) do
        if memberRole==role and (e.statuses[name] or 'accepted')=='accepted' then names[#names+1]=name end
    end
    table.sort(names)
    local labels={tank='Танки',healer='Лікарі',dps='DPS',flex='Інші'}
    local lines={largeRoleIcon(role,24)..' |c'..roleColors[role]..labels[role]..' ('..#names..')|r'}
    for _,name in ipairs(names) do lines[#lines+1]=participantName(name,classes) end
    if #names==0 then lines[#lines+1]='|cff9ba9bc—|r' end
    return table.concat(lines,'\n'),#names
end
refresh=function()
    if not window then return end
    window.eventsTab:SetEnabled(window.creationMode)
    window.createTab:SetEnabled(not window.creationMode)
    if window.tabBar and window.tabBar.SetActive then
        window.tabBar:SetActive(window.creationMode and 'create' or 'events')
    end
    local alertsOn = Events:AlertsEnabled()
    window.alertButton:SetText(alertsOn and 'Сповіщення: увімк.' or 'Сповіщення: вимк.')
    if window.alertDot then
        local c = OldKraken.UIStyle.Colors and (alertsOn and OldKraken.UIStyle.Colors.success or OldKraken.UIStyle.Colors.neutral) or {0.41, 0.86, 0.55, 1}
        window.alertDot:SetColorTexture(c[1], c[2], c[3], 1)
    end
    for _,control in ipairs(window.formControls) do control:SetShown(window.creationMode) end
    if window.creationMode then
        for _,control in ipairs(window.viewControls) do control:Hide() end
        for _,row in ipairs(rows) do row:Hide() end
        if window.UpdateSummary then window:UpdateSummary() end
        if catalog[currentKind] then window:ShowActivityCards() else window.activityCards:Hide() end
        return
    end
    for _,control in ipairs(window.viewControls) do control:Show() end
    if window.datePopup then window.datePopup:Hide() end
    window.activityCards:Hide()
    local list={}
    for key,e in pairs(events) do if not e.cancelled and e.when>=GetServerTime()-172800 then list[#list+1]={key=key,event=e} end end
    table.sort(list,function(a,b) if a.event.when~=b.event.when then return a.event.when<b.event.when end return a.key<b.key end)
    local pageCount=math.max(1,math.ceil(#list/EVENTS_PER_PAGE))
    page=math.max(1,math.min(page,pageCount))
    window.visible=list
    window.pageLabel:SetText(page..' / '..pageCount)
    window.previousPage:SetShown(pageCount>1)
    window.nextPage:SetShown(pageCount>1)
    window.empty:SetShown(#list==0)
    window.emptyAction:SetShown(#list==0)
    for i,row in ipairs(rows) do
        local entry=list[(page-1)*EVENTS_PER_PAGE+i]
        if entry then
            local e=entry.event
            catalog.SetArtwork(row.art,e.activity)
            row.title:SetText(e.title)
            local activity=e.activity~='' and (activityLabels[e.activity] or e.activity) or kinds[e.kind]
            row.meta:SetText(activity..' · '..date('%d.%m %H:%M',e.when)..' · '..acceptedCount(e)..'/'..e.size)
            if selected==entry.key then row:LockHighlight() else row:UnlockHighlight() end
            row:Show(); row.delete:SetShown(e.owner==identity)
        else row:UnlockHighlight(); row.delete:Hide(); row:Hide() end
    end
    local e=selected and events[selected]
    for _,row in ipairs(window.signupRows) do row:Hide() end
    if e and not e.cancelled then
        local classes=participantClasses()
        if window.filterEvent~=selected then window.filterEvent=selected; window.roleFilter=false end
        local names={}; for name,role in pairs(e.people) do
            if not window.roleFilter or role==window.roleFilter then names[#names+1]=name end
        end; table.sort(names)
        local pending=intents[selected]
        local lines={}
        for _,name in ipairs(names) do
            local role=e.people[name]
            lines[#lines+1]=participantLabel(name,role,e.statuses[name],classes)
        end
        local own=e.owner==identity
        window.detailsTitle:SetText(e.title); window.detailsTitle:Show()
        window.details:ClearAllPoints(); window.details:SetPoint('TOPLEFT',window.detailsTitle,'BOTTOMLEFT',0,-8)
        local description=e.description~='' and ('\n\n|cff9ba9bcОпис:|r\n'..e.description) or ''
        local activity=kinds[e.kind]..(e.activity~='' and ' · '..(activityLabels[e.activity] or e.activity) or '')
        window.details:SetText('|cff9ba9bcПодія:|r '..activity..'\n|cff9ba9bcДата:|r |cffffd35a'..date('%d.%m.%Y %H:%M',e.when)..'|r\n|cff9ba9bcАвтор:|r |cff9bcaff'..e.owner..'|r\n|cff9ba9bcПрийнято:|r |cff69dc8c'..acceptedCount(e)..'/'..e.size..'|r'..(e.relayed and '\n|cffffc36bСтан отримано через гільдію|r' or '')..description..(pending and '\n\n|cffffc36bОчікується доставка автору|r' or ''))
        window.roleSummary:ClearAllPoints(); window.roleSummary:SetPoint('TOPLEFT',window.details,'BOTTOMLEFT',0,-14)
        window.roleSummary:SetText('Склад за ролями'); window.roleSummary:Show()
        local columnHeight=0
        for i,role in ipairs({'tank','healer','dps'}) do
            local column=window.roleColumns[i]
            column:ClearAllPoints(); column:SetPoint('TOPLEFT',window.roleSummary,'BOTTOMLEFT',(i-1)*window.detailsWidth/3,-8)
            local text=roleColumnText(e,classes,role)
            column:SetText(text); column:Show()
            local button=window.roleButtons[i]
            button:SetSize(window.detailsWidth/3-7,math.max(30,column:GetStringHeight()))
            button:SetShown(true)
            if window.roleFilter==role then button:LockHighlight() else button:UnlockHighlight() end
            columnHeight=math.max(columnHeight,column:GetStringHeight())
        end
        local flexText,flexCount=roleColumnText(e,classes,'flex')
        window.roleFlex:ClearAllPoints(); window.roleFlex:SetPoint('TOPLEFT',window.roleSummary,'BOTTOMLEFT',0,-columnHeight-18)
        window.roleFlex:SetText(flexText); window.roleFlex:SetShown(flexCount>0)
        window.flexButton:SetShown(flexCount>0); window.flexButton:SetHeight(math.max(30,window.roleFlex:GetStringHeight()))
        local summaryHeight=columnHeight+18+(flexCount>0 and window.roleFlex:GetStringHeight()+8 or 0)
        window.participantHeader:ClearAllPoints(); window.participantHeader:SetPoint('TOPLEFT',window.roleSummary,'BOTTOMLEFT',0,-summaryHeight-14)
        window.participantHeader:SetText('Заявки та учасники'..(window.roleFilter and (' · '..roles[window.roleFilter]) or ' · усі')); window.participantHeader:Show()
        local height=window.detailsTitle:GetStringHeight()+8+window.details:GetStringHeight()+14+window.roleSummary:GetStringHeight()+summaryHeight+14+window.participantHeader:GetStringHeight()+8
        do
            for i,name in ipairs(names) do
                local row=window.signupRows[i]
                if not row then
                    row=CreateFrame('Frame',nil,window.detailsContent); row:SetSize(window.detailsWidth,32)
                    row.label=row:CreateFontString(nil,'OVERLAY','GameFontHighlight'); row.label:SetPoint('TOPLEFT',row,'TOPLEFT',0,0); row.label:SetSize(window.detailsWidth-174,26); row.label:SetJustifyH('LEFT'); row.label:SetWordWrap(false); readableFont(row.label,15)
                    row.roleStatus=row:CreateFontString(nil,'OVERLAY','GameFontHighlight'); row.roleStatus:SetPoint('TOPLEFT',row,'TOPLEFT',window.detailsWidth-168,-3); row.roleStatus:SetSize(28,28); row.roleStatus:SetJustifyH('LEFT'); row.roleStatus:SetWordWrap(false)
                    row.hover=CreateFrame('Frame',nil,row); row.hover:SetPoint('TOPLEFT'); row.hover:SetSize(window.detailsWidth-118,30); row.hover:EnableMouse(true)
                    row.hover:SetScript('OnEnter',function(self) if GameTooltip and self.tooltipName then GameTooltip:SetOwner(self,'ANCHOR_RIGHT'); GameTooltip:SetText(self.tooltipName); GameTooltip:AddLine(self.tooltipStatus,1,1,1,true); GameTooltip:Show() end end)
                    row.hover:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
                    row.accept=action(row,'Прийняти',0,-40,94,function(self) if not Events:Decide(selected,self:GetParent().member,'accepted') then print('Old Kraken: не вдалося прийняти учасника; перевірте вільні місця.') end end,'primary')
                    row.reserve=action(row,'Резерв',100,-40,94,function(self) Events:Decide(selected,self:GetParent().member,'reserve') end)
                    row.reject=action(row,'Відхилити',200,-40,104,function(self) Events:Decide(selected,self:GetParent().member,'rejected') end)
                    row.invite=action(row,'Інвайт у рейд',0,-68,194,function(self) Events:InviteMember(selected,self:GetParent().member) end,'primary')
                    local left=window.detailsWidth-112
                    iconAction(row.accept,row,left,'Interface\\RaidFrame\\ReadyCheck-Ready','Прийняти учасника')
                    iconAction(row.reserve,row,left+28,'Interface\\RaidFrame\\ReadyCheck-Waiting','Перевести в резерв')
                    iconAction(row.reject,row,left+56,'Interface\\RaidFrame\\ReadyCheck-NotReady','Відхилити заявку')
                    iconAction(row.invite,row,left+84,'Interface\\Buttons\\UI-PlusButton-Up','Запросити в рейд')
                    row.state= row:CreateTexture(nil,'ARTWORK'); row.state:SetSize(15,15); row.state:SetPoint('TOPLEFT',row,'TOPLEFT',window.detailsWidth-140,-7)
                    row.state:SetTexture('Interface\\AddOns\\OldKraken\\Media\\RoleSlot.tga')
                    window.signupRows[i]=row
                end
                row.member=name; row:ClearAllPoints(); row:SetPoint('TOPLEFT',window.detailsContent,'TOPLEFT',0,-height-(i-1)*32)
                local role=e.people[name]
                row.label:SetText(participantName(name,classes)); row.roleStatus:SetText(largeRoleIcon(role,26))
                local tint=statusColors[e.statuses[name] or 'accepted'] or statusColors.pending
                row.state:SetVertexColor(tonumber(tint:sub(3,4),16)/255,tonumber(tint:sub(5,6),16)/255,tonumber(tint:sub(7,8),16)/255)
                row.hover.tooltipName=participantName(name,classes); row.hover.tooltipStatus=participantRoleStatus(role,e.statuses[name])
                row.invite:SetShown(own and e.kind=='raid' and name~=identity and e.statuses[name]=='accepted')
                row.accept:SetEnabled(canPerformRole(name,role)); row.reserve:SetEnabled(canPerformRole(name,role))
                row.accept:SetShown(own and name~=identity); row.reserve:SetShown(own and name~=identity); row.reject:SetShown(own and name~=identity); row:Show()
            end
            height=height+#names*32
        end
        local detailsScrollBar = _G.OldKrakenEventsDetailsScrollScrollBar
        if detailsScrollBar and detailsScrollBar.SetShown then detailsScrollBar:SetShown(#names > 5) end
        window.detailsContent:SetHeight(math.max(250,height+8))
        window.inviteAll:SetShown(own and e.kind=='raid')
        window.cancel:SetShown(e.owner==identity)
        if not canPerformRole(identity,currentRole) then currentRole='flex'; UIDropDownMenu_SetText(window.roleMenu,roles[currentRole]) end
        local canJoin=not e.relayed and not pending and (not e.people[identity] or e.statuses[identity]=='rejected')
        window.join:SetShown(canJoin)
        window.roleMenu:SetShown(canJoin)
        window.leave:SetShown(not e.relayed and ((pending and pending.role~='leave') or (not pending and e.people[identity] ~= nil and e.statuses[identity]~='rejected')))
    else
        window.roleSummary:Hide(); window.roleFlex:Hide(); window.flexButton:Hide(); for _,button in ipairs(window.roleButtons) do button:Hide() end; for _,column in ipairs(window.roleColumns) do column:Hide() end
        window.participantHeader:Hide(); window.detailsTitle:Hide(); window.details:ClearAllPoints(); window.details:SetPoint('TOPLEFT',window.detailsContent,'TOPLEFT',0,0)
        window.details:SetText('Оберіть подію зі списку.'); window.inviteAll:Hide(); window.cancel:Hide(); window.join:Hide(); window.leave:Hide(); window.roleMenu:Hide()
        local detailsScrollBar = _G.OldKrakenEventsDetailsScrollScrollBar
        if detailsScrollBar and detailsScrollBar.SetShown then detailsScrollBar:SetShown(false) end
        window.detailsContent:SetHeight(250)
    end
end
local function createWindow(parent)
    local f
    local embedded=parent~=nil
    local shift=embedded and 30 or 0
    local detailsWidth=embedded and 400 or 350
    EVENTS_PER_PAGE=embedded and 6 or 4
    if parent then
        f=CreateFrame('Frame','OldKrakenEventsFrame',parent)
    else
        f=CreateFrame('Frame','OldKrakenEventsFrame',UIParent,'BasicFrameTemplateWithInset')
    end
    if not parent then table.insert(UISpecialFrames,'OldKrakenEventsFrame') end
    f:SetSize(parent and 900 or 840,parent and 607 or 560); f:SetPoint('CENTER',parent or UIParent,'CENTER'); f:SetMovable(not parent); f:EnableMouse(true)
    if not parent then
        f:RegisterForDrag('LeftButton'); f:SetScript('OnDragStart',f.StartMoving); f:SetScript('OnDragStop',f.StopMovingOrSizing)
    end
    f:SetClampedToScreen(true)
    if not parent then OldKraken.UIStyle.Window(f) end
    f.detailsWidth=detailsWidth
    if f.TitleText then f.TitleText:SetText('Old Kraken — Події гільдії') end

    -- Right-side header controls (shared left title 'Івенти' belongs to UIHub)
    local note=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    note:SetPoint('TOPLEFT',f,'TOPLEFT',612,-8); note:SetText('Час — місцевий')
    local muted=OldKraken.UIStyle.Colors and OldKraken.UIStyle.Colors.mutedText
    if muted then note:SetTextColor(muted[1],muted[2],muted[3]) end
    f.timeNote=note

    f.alertButton=action(f,'Сповіщення: увімк.',728,0,172,function() Events:SetAlertsEnabled(not Events:AlertsEnabled()); refresh() end)
    f.alertButton:SetHeight(31)
    local alertLabel=f.alertButton:GetFontString()
    if alertLabel then
        alertLabel:ClearAllPoints()
        alertLabel:SetPoint('LEFT',f.alertButton,'LEFT',26,0)
    end
    f.alertDot=f.alertButton:CreateTexture(nil,'OVERLAY')
    f.alertDot:SetSize(8,8); f.alertDot:SetPoint('LEFT',f.alertButton,'LEFT',12,0)
    local green=OldKraken.UIStyle.Colors and OldKraken.UIStyle.Colors.success or {0.41,0.86,0.55,1}
    f.alertDot:SetColorTexture(green[1],green[2],green[3],1)

    f.creationMode=false
    if OldKraken.UIStyle.SegmentedTabs then
        f.tabBar=OldKraken.UIStyle.SegmentedTabs(f,{
            {key='events',label='Події',width=76},
            {key='create',label='Створити івент',width=144},
        },function(key)
            f.creationMode=(key=='create')
            refresh()
        end,{active='events',height=40})
        f.tabBar:SetPoint('TOPLEFT',f,'TOPLEFT',0,-47)
        f.eventsTab=f.tabBar.tabs.events
        f.createTab=f.tabBar.tabs.create
    else
        f.eventsTab=action(f,'Події',0,-47,100,function() f.creationMode=false; refresh() end)
        f.createTab=action(f,'Створити івент',108,-47,130,function() f.creationMode=true; refresh() end,'primary')
    end

    f.empty=f:CreateFontString(nil,'OVERLAY','GameFontHighlight'); f.empty:SetPoint('TOPLEFT',f,'TOPLEFT',18,-105); f.empty:SetWidth(embedded and 400 or 365); f.empty:SetJustifyH('LEFT'); f.empty:SetText('Найближчих подій немає. Заплануйте першу подію для гільдії.')
    f.emptyAction=action(f,'Створити подію',18,-148,150,function() f.creationMode=true; refresh(); if f.title then f.title:SetFocus() end end,'primary')
    f.eventRows=rows
    for i=1,EVENTS_PER_PAGE do
        local index=i
        rows[i]=action(f,'',0,-103-(i-1)*77,embedded and 420 or 383,function() local entry=f.visible and f.visible[(page-1)*EVENTS_PER_PAGE+index]; if entry then selected=entry.key; refresh() end end)
        rows[i]:SetHeight(70)
        rows[i].art=rows[i]:CreateTexture(nil,'ARTWORK'); rows[i].art:SetPoint('TOPLEFT',rows[i],'TOPLEFT',3,-3); rows[i].art:SetSize(48,48)
        rows[i].title=rows[i]:CreateFontString(nil,'OVERLAY','GameFontNormal'); rows[i].title:SetPoint('TOPLEFT',rows[i],'TOPLEFT',60,-5); rows[i].title:SetWidth(embedded and 352 or 315); rows[i].title:SetJustifyH('LEFT'); rows[i].title:SetWordWrap(true); rows[i].title:SetHeight(34); readableFont(rows[i].title,16)
        rows[i].meta=rows[i]:CreateFontString(nil,'OVERLAY','GameFontHighlight'); rows[i].meta:SetPoint('TOPLEFT',rows[i],'TOPLEFT',60,-42); rows[i].meta:SetWidth(embedded and 352 or 315); rows[i].meta:SetJustifyH('LEFT'); rows[i].meta:SetWordWrap(true); rows[i].meta:SetHeight(27); readableFont(rows[i].meta,13)
        local remove=CreateFrame('Button',nil,rows[i]); rows[i].delete=remove
        remove:SetSize(24,23); remove:SetPoint('LEFT',rows[i],'RIGHT',3,0)
        local function trashPiece(x,y,width,height)
            local texture=remove:CreateTexture(nil,'ARTWORK'); texture:SetColorTexture(0.9,0.32,0.3,1)
            texture:SetSize(width,height); texture:SetPoint('TOPLEFT',remove,'TOPLEFT',x,-y)
        end
        trashPiece(6,6,12,2); trashPiece(9,4,6,2); trashPiece(7,9,2,9); trashPiece(15,9,2,9); trashPiece(7,17,10,2)
        remove:SetScript('OnClick',function()
            local entry=f.visible and f.visible[(page-1)*EVENTS_PER_PAGE+index]; local e=entry and events[entry.key]
            if not active or not e or e.owner~=identity or e.cancelled then return end
            local key,expectedProfile,expectedIdentity=entry.key,profile,identity
            local popup=StaticPopup_Show('OLDKRAKEN_EVENT_DELETE',e.title,nil,function()
                if not active or profile~=expectedProfile or identity~=expectedIdentity or not Events:Cancel(key) then print('Old Kraken: не вдалося видалити подію.'); return end
                if selected==key then selected=nil; refresh() end
            end)
            if not popup then print('Old Kraken: не вдалося відкрити підтвердження видалення.'); return end
            if not popup.oldKrakenRestoreHook then
                popup:HookScript('OnHide',function(self) if self.oldKrakenStrata then self:SetFrameStrata(self.oldKrakenStrata); self.oldKrakenStrata=nil end end)
                popup.oldKrakenRestoreHook=true
            end
            if not popup.oldKrakenStrata then popup.oldKrakenStrata=popup:GetFrameStrata() end
            popup:SetFrameStrata('FULLSCREEN_DIALOG')
        end)
        remove:SetScript('OnEnter',function(self) if GameTooltip then GameTooltip:SetOwner(self,'ANCHOR_RIGHT'); GameTooltip:SetText('Видалити подію'); GameTooltip:Show() end end)
        remove:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
        remove:Hide()
    end
    f.previousPage=action(f,'‹',138+(embedded and 5 or 0),embedded and -568 or -380,45,function() page=page-1; refresh() end)
    f.pageLabel=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    f.pageLabel:SetPoint('TOPLEFT',f,'TOPLEFT',191+(embedded and 5 or 0),embedded and -573 or -385); f.pageLabel:SetWidth(64); f.pageLabel:SetJustifyH('CENTER')
    f.nextPage=action(f,'›',263+(embedded and 5 or 0),embedded and -568 or -380,45,function() page=page+1; refresh() end)
    local scroll=CreateFrame('ScrollFrame','OldKrakenEventsDetailsScroll',f,'UIPanelScrollFrameTemplate'); scroll:SetPoint('TOPLEFT',f,'TOPLEFT',450+shift,-103); scroll:SetSize(detailsWidth,embedded and 450 or 320)
    f.detailsContent=CreateFrame('Frame',nil,scroll); f.detailsContent:SetSize(detailsWidth,250); scroll:SetScrollChild(f.detailsContent); f.signupRows={}
    f.detailsTitle=f.detailsContent:CreateFontString(nil,'OVERLAY','GameFontNormalLarge'); f.detailsTitle:SetPoint('TOPLEFT'); f.detailsTitle:SetWidth(detailsWidth); f.detailsTitle:SetJustifyH('LEFT'); f.detailsTitle:SetWordWrap(true); readableFont(f.detailsTitle,18)
    f.roleSummary=f.detailsContent:CreateFontString(nil,'OVERLAY','GameFontHighlight'); f.roleSummary:SetWidth(detailsWidth); f.roleSummary:SetJustifyH('LEFT'); readableFont(f.roleSummary,15)
    f.roleColumns={}; f.roleButtons={}
    local function roleButton(column,role)
        local button=CreateFrame('Button',nil,f.detailsContent)
        button:SetPoint('TOPLEFT',column,'TOPLEFT',0,0)
        button:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight')
        button:SetScript('OnClick',function()
            f.roleFilter=f.roleFilter~=role and role or false
            scroll:SetVerticalScroll(0); refresh()
        end)
        button:SetScript('OnEnter',function(self)
            if GameTooltip then GameTooltip:SetOwner(self,'ANCHOR_RIGHT'); GameTooltip:SetText('Фільтр: '..roles[role]); GameTooltip:AddLine('Повторний клік — показати всіх',1,1,1); GameTooltip:Show() end
        end)
        button:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
        return button
    end
    for i=1,3 do
        local column=f.detailsContent:CreateFontString(nil,'OVERLAY','GameFontHighlight')
        column:SetWidth(detailsWidth/3-7); column:SetJustifyH('LEFT'); column:SetWordWrap(true); column:SetSpacing(7); readableFont(column,14)
        f.roleColumns[i]=column
        f.roleButtons[i]=roleButton(column,({'tank','healer','dps'})[i])
    end
    f.roleFlex=f.detailsContent:CreateFontString(nil,'OVERLAY','GameFontHighlight'); f.roleFlex:SetWidth(detailsWidth); f.roleFlex:SetJustifyH('LEFT'); readableFont(f.roleFlex,14)
    f.flexButton=roleButton(f.roleFlex,'flex'); f.flexButton:SetWidth(detailsWidth)
    f.participantHeader=f.detailsContent:CreateFontString(nil,'OVERLAY','GameFontNormal'); f.participantHeader:SetWidth(detailsWidth); f.participantHeader:SetJustifyH('LEFT'); readableFont(f.participantHeader,15)
    f.details=f.detailsContent:CreateFontString(nil,'OVERLAY','GameFontHighlight'); f.details:SetPoint('TOPLEFT',f.detailsContent,'TOPLEFT',0,0); f.details:SetWidth(detailsWidth); f.details:SetJustifyH('LEFT'); f.details:SetJustifyV('TOP'); f.details:SetWordWrap(true); f.details:SetSpacing(3); readableFont(f.details,15)
    f.roleMenu=selectMenu(f,'OldKrakenEventsRole',450+shift,embedded and -568 or -395,150,{'tank','healer','dps','flex'},roles,function() return currentRole end,function(v) currentRole=v end,function(v) return canPerformRole(identity,v) end)
    f.join=action(f,'Записатися',605+shift,embedded and -568 or -395,100,function() if selected and not Events:Signup(selected,currentRole) then print('Old Kraken: не вдалося записатися; перевірте місця та зв’язок.') end end,'primary')
    f.leave=action(f,'Виписатися',605+shift,embedded and -568 or -395,100,function() if selected then Events:Signup(selected,'leave') end end)
    f.cancel=action(f,'Скасувати',710+shift,embedded and -568 or -395,105,function() if selected then Events:Cancel(selected) end end)
    f.inviteAll=action(f,'Запросити всіх у рейд',450+shift,-47,170,function() if selected then Events:InviteAll(selected) end end,'primary')
    f.inviteAll:Hide()

    -- =========================================================================
    -- 3-Step Event Creation Form (Figma: Івенти — Створити)
    -- =========================================================================
    local activity=''
    local autoFilledTitle=nil
    local manualTitle=false
    local settingAutoTitle=false
    local hour,minute=0,0
    local getDate, setDate

    local function createStepHeader(num, text, yPos)
        if OldKraken.UIStyle.StepIndicator then
            local s = OldKraken.UIStyle.StepIndicator(f, num, text)
            s:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, yPos)
            return s
        end
        local s = CreateFrame('Frame', nil, f)
        s:SetSize(300, 24); s:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, yPos)
        s.title = s:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
        s.title:SetPoint('LEFT', s, 'LEFT', 0, 0); s.title:SetText(num .. '. ' .. text)
        function s:SetTitle(v) self.title:SetText(v or '') end
        return s
    end

    f.step1 = createStepHeader(1, 'Тип події', -103)
    f.step2 = createStepHeader(2, 'Оберіть рейд', -191)
    f.step3 = createStepHeader(3, 'Деталі', -321)

    -- Step 3 fields: Назва, Дата, Час (hour : minute), Місць stepper (2-40), Опис
    local titleCaption = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    titleCaption:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, -359)
    titleCaption:SetText('Назва · заповнюється автоматично')
    if muted then titleCaption:SetTextColor(muted[1], muted[2], muted[3]) end
    f.title = CreateFrame('EditBox', nil, f, 'InputBoxTemplate')
    OldKraken.UIStyle.Input(f.title)
    f.title:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, -380); f.title:SetSize(414, 34)
    f.title:SetAutoFocus(false); f.title:SetTextInsets(10, 10, 0, 0); f.title:SetText('')
    f.title.label = titleCaption
    f.title:SetScript('OnEscapePressed', function(self) self:ClearFocus() end)
    local rawSetTitleText = f.title.SetText
    function f.title:SetText(value)
        rawSetTitleText(self, value)
        if not settingAutoTitle then
            manualTitle = f.creationMode and type(value) == 'string' and value ~= '' and value ~= autoFilledTitle or false
        end
        if f.UpdateSummary then f:UpdateSummary() end
    end

    local function syncAutoTitle()
        if manualTitle and (f.title:GetText() or '') ~= '' then return end
        local nextTitle = (activity ~= '' and activityLabels[activity]) or kinds[currentKind] or ''
        settingAutoTitle = true
        autoFilledTitle = nextTitle
        f.title:SetText(nextTitle)
        settingAutoTitle = false
    end

    function f:UpdateSummary()
        if not self.summaryLine then return end
        local kindName = kinds[currentKind] or currentKind
        local titleText = (self.title:GetText() or '') ~= '' and self.title:GetText() or ((activity ~= '' and activityLabels[activity]) or kindName)
        local day = getDate and getDate()
        local dateStr = day and string.format('%02d.%02d.%04d %02d:%02d', day.day, day.month, day.year, hour, minute) or string.format('дату не вибрано %02d:%02d', hour, minute)
        local sizeNum = math.max(2, math.min(40, tonumber(self.size:GetText()) or 10))
        self.summaryLine:SetText(string.format('%s · %s · %s · %d місць', kindName, titleText, dateStr, sizeNum))
    end

    f.title:SetScript('OnTextChanged', function() f:UpdateSummary() end)

    getDate, setDate = datePicker(f, function() f:UpdateSummary() end)
    f.SetDate = setDate

    local hourValues,hourLabels={},{}
    for value=0,23 do hourValues[#hourValues+1]=value; hourLabels[value]=string.format('%02d',value) end
    local timeLabel=f:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
    timeLabel:SetPoint('TOPLEFT',f,'TOPLEFT',588,-359); timeLabel:SetText('Час')
    if muted then timeLabel:SetTextColor(muted[1],muted[2],muted[3]) end
    local minuteLabel=f:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
    minuteLabel:SetPoint('TOPLEFT',f,'TOPLEFT',668,-390); minuteLabel:SetText(':')
    f.hourMenu=selectMenu(f,'OldKrakenEventsHour',588,-380,82,hourValues,hourLabels,function() return hour end,function(v) hour=v; f:UpdateSummary() end)
    f.minuteMenu=selectMinutes(f,680,-380,function() return minute end,function(v) minute=v; f:UpdateSummary() end)

    -- Місць stepper (2-40)
    local sizeCaption = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    sizeCaption:SetPoint('TOPLEFT', f, 'TOPLEFT', 770, -359); sizeCaption:SetText('Місць · 2–40')
    if muted then sizeCaption:SetTextColor(muted[1], muted[2], muted[3]) end
    f.size = CreateFrame('EditBox', nil, f, 'InputBoxTemplate')
    OldKraken.UIStyle.Input(f.size)
    f.size:SetPoint('TOPLEFT', f, 'TOPLEFT', 806, -380); f.size:SetSize(58, 34)
    f.size:SetAutoFocus(false); f.size:SetJustifyH('CENTER'); f.size:SetText('10')
    f.size.label = sizeCaption
    f.size:SetScript('OnEscapePressed', function(self) self:ClearFocus() end)
    f.size:SetScript('OnTextChanged', function() f:UpdateSummary() end)
    local function stepSize(delta)
        local current = tonumber(f.size:GetText()) or 10
        local nextVal = math.max(2, math.min(40, current + delta))
        f.size:SetText(tostring(nextVal))
        f:UpdateSummary()
    end
    f.sizeMinus = action(f, '-', 770, -380, 34, function() stepSize(-1) end)
    f.sizeMinus:SetHeight(34)
    f.sizePlus = action(f, '+', 866, -380, 34, function() stepSize(1) end)
    f.sizePlus:SetHeight(34)

    -- Row 2: Опис (full width 900)
    local descCaption = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    descCaption:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, -430); descCaption:SetText('Опис · необов’язково')
    if muted then descCaption:SetTextColor(muted[1], muted[2], muted[3]) end
    f.description = CreateFrame('EditBox', nil, f, 'InputBoxTemplate')
    OldKraken.UIStyle.Input(f.description)
    f.description:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, -451); f.description:SetSize(900, 34)
    f.description:SetAutoFocus(false); f.description:SetTextInsets(10, 10, 0, 0); f.description:SetText('')
    f.description.label = descCaption
    f.descriptionHint = f:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    f.descriptionHint:SetPoint('LEFT', f.description, 'LEFT', 12, 0)
    f.descriptionHint:SetText('Збір, вимоги, консумки…')
    if muted then f.descriptionHint:SetTextColor(muted[1], muted[2], muted[3]) end
    f.description:SetScript('OnEscapePressed', function(self) self:ClearFocus() end)
    f.description:SetScript('OnTextChanged', function(self)
        if f.descriptionHint then f.descriptionHint:SetShown((self:GetText() or '') == '') end
    end)

    -- Step 2: Location cards + 'Без конкретної локації' button
    local activityButton = f:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    activityButton:SetPoint('TOPLEFT', f, 'TOPLEFT', 210, -196); activityButton:SetSize(280, 20); activityButton:SetJustifyH('LEFT')
    f.activityButton = activityButton

    local function chooseActivity(value)
        activity = value
        syncAutoTitle()
        activityButton:SetText(value ~= '' and activityLabels[value] or 'Без конкретної локації')
        if f.noLocationButton and f.noLocationButton.SetActive then
            f.noLocationButton:SetActive(value == '')
        end
        if catalog[currentKind] then f:ShowActivityCards() end
        f:UpdateSummary()
    end

    if OldKraken.UIStyle.Chip then
        f.noLocationButton = OldKraken.UIStyle.Chip(f, 'Без конкретної локації', {width = 182, height = 34, center = true, active = true})
        f.noLocationButton:SetPoint('TOPLEFT', f, 'TOPLEFT', 718, -187)
        f.noLocationButton:SetScript('OnClick', function() chooseActivity('') end)
    else
        f.noLocationButton = action(f, 'Без конкретної локації', 718, -187, 182, function() chooseActivity('') end)
        f.noLocationButton:SetHeight(34)
    end

    local grid = CreateFrame('Frame', nil, f)
    grid:SetSize(900, 74); grid:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, -232)
    grid:SetFrameLevel(f:GetFrameLevel() + 5); grid:EnableMouse(true); grid:EnableMouseWheel(true)
    grid.heading = f.step2.title
    local clip = CreateFrame('Frame', nil, grid); clip:SetPoint('TOPLEFT', grid, 'TOPLEFT', 0, 0); clip:SetSize(900, 70)
    if clip.SetClipsChildren then pcall(clip.SetClipsChildren, clip, true) end
    local body = CreateFrame('Frame', nil, clip); body:SetSize(900, 1)
    grid.cards = {}; grid.offset = 0; grid.full = 1
    function grid:ScrollTo(value)
        self.offset = math.max(0, math.min(math.max(0, self.full - 70), value))
        body:ClearAllPoints(); body:SetPoint('TOPLEFT', clip, 'TOPLEFT', 0, self.offset)
    end
    local function wheel(_, delta) grid:ScrollTo(grid.offset - delta * 70) end
    grid:SetScript('OnMouseWheel', wheel); clip:EnableMouseWheel(true); clip:SetScript('OnMouseWheel', wheel)
    f.activityCards = grid
    function f:ShowActivityCards()
        f.step2:SetTitle(currentKind == 'raid' and 'Оберіть рейд' or (currentKind == 'dungeon' and 'Оберіть підземелля' or 'Локація'))
        local width = 292
        local level = type(UnitLevel) == 'function' and tonumber((UnitLevel('player'))) or 0; level = level or 0
        local count = 0
        local gold = OldKraken.UIStyle.Colors and OldKraken.UIStyle.Colors.brandGold
        for _, entry in ipairs(catalog[currentKind] or {}) do
            if entry.value ~= '' then
                count = count + 1
                local card = grid.cards[count]
                if not card then
                    card = CreateFrame('Button', nil, body); OldKraken.UIStyle.Button(card)
                    card:SetSize(width, 64); card:SetPoint('TOPLEFT', body, 'TOPLEFT', ((count - 1) % 3) * (width + 12), -math.floor((count - 1) / 3) * 70)
                    card.art = card:CreateTexture(nil, 'ARTWORK'); card.art:SetSize(44, 44); card.art:SetPoint('TOPLEFT', card, 'TOPLEFT', 11, -10)
                    card.title = card:CreateFontString(nil, 'OVERLAY', 'GameFontNormal'); card.title:SetPoint('TOPLEFT', card, 'TOPLEFT', 67, -13); card.title:SetSize(width - 75, 20); card.title:SetJustifyH('LEFT'); card.title:SetWordWrap(false)
                    if gold then card.title:SetTextColor(gold[1], gold[2], gold[3]) end
                    card.levels = card:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall'); card.levels:SetPoint('TOPLEFT', card, 'TOPLEFT', 67, -34); card.levels:SetWidth(width - 75); card.levels:SetJustifyH('LEFT')
                    if muted then card.levels:SetTextColor(muted[1], muted[2], muted[3]) end
                    card:SetScript('OnClick', function(self) if self.entry then chooseActivity(self.entry.value) end end)
                    card:EnableMouseWheel(true); card:SetScript('OnMouseWheel', wheel)
                    grid.cards[count] = card
                end
                card.entry = entry
                local fits = level == 0 or (level >= entry.min - 2 and level <= entry.max + 2)
                catalog.SetArtwork(card.art, entry.value); card.art:SetDesaturated(not fits); card.art:SetAlpha(fits and 1 or 0.55)
                card.title:SetText(entry.label)
                card.levels:SetText('рівень ' .. (entry.min == entry.max and tostring(entry.min) or (entry.min .. '–' .. entry.max)) .. (fits and '  |cff69dc8cпід ваш рівень|r' or ''))
                if OldKraken.UIStyle.ApplySelection then OldKraken.UIStyle.ApplySelection(card, entry.value == activity) end
                if entry.value == activity then card:LockHighlight() else card:UnlockHighlight() end
                card:Show()
            end
        end
        for i = count + 1, #grid.cards do grid.cards[i]:Hide(); grid.cards[i].entry = nil end
        grid.full = math.max(1, math.ceil(count / 3) * 70); body:SetHeight(grid.full)
        if grid.kind ~= currentKind then grid.offset = 0; grid.kind = currentKind end
        grid:ScrollTo(grid.offset); grid:Show()
    end
    grid:Hide()
    f:HookScript('OnHide', function() grid:Hide() end)

    -- Step 1: Horizontal event type chips (raid, dungeon, pvp, guild)
    f.kindChips = {}
    local chipOrder = {
        {key = 'raid', label = kinds.raid, width = 80},
        {key = 'dungeon', label = kinds.dungeon, width = 114},
        {key = 'pvp', label = kinds.pvp, width = 76},
        {key = 'guild', label = kinds.guild, width = 128},
    }
    local function showActivity()
        local enabled = catalog[currentKind] ~= nil
        for key, chip in pairs(f.kindChips) do
            if chip.SetActive then chip:SetActive(key == currentKind) end
        end
        f.step2:SetTitle(currentKind == 'raid' and 'Оберіть рейд' or (currentKind == 'dungeon' and 'Оберіть підземелля' or 'Локація'))
        activityButton:SetShown(f.creationMode)
        activityButton:SetText(activity ~= '' and activityLabels[activity] or 'Без конкретної локації')
        if f.noLocationButton and f.noLocationButton.SetActive then f.noLocationButton:SetActive(activity == '') end
        if f.creationMode and enabled then f:ShowActivityCards() else grid:Hide() end
        f:UpdateSummary()
    end
    local chipX = 0
    for _, item in ipairs(chipOrder) do
        local kindKey = item.key
        local chip
        if OldKraken.UIStyle.Chip then
            chip = OldKraken.UIStyle.Chip(f, item.label, {width = item.width, height = 34, center = true, active = (kindKey == currentKind)})
            chip:SetPoint('TOPLEFT', f, 'TOPLEFT', chipX, -138)
        else
            chip = action(f, item.label, chipX, -138, item.width, function() end)
            chip:SetHeight(34)
            function chip:SetActive(a) self.active = a and true or false end
        end
        chip:SetScript('OnClick', function()
            currentKind = kindKey
            activity = ''
            syncAutoTitle()
            showActivity()
        end)
        f.kindChips[kindKey] = chip
        chipX = chipX + item.width + 8
    end
    function f:SelectKind(kindKey)
        if not kinds[kindKey] then return false end
        currentKind = kindKey
        activity = ''
        syncAutoTitle()
        showActivity()
        return true
    end
    local kindLabels = {}
    for value, label in pairs(kinds) do kindLabels[value] = label end
    f.kindMenu = selectMenu(f, 'OldKrakenEventsKind', 0, -138, 180, {'raid', 'dungeon', 'pvp', 'guild'}, kindLabels, function() return currentKind end, function(v) f:SelectKind(v) end)
    f.kindMenu:Hide()

    -- Sticky bottom summary bar (900 x 64 at 0, -543)
    if OldKraken.UIStyle.PanelFrame then
        f.summaryBar = OldKraken.UIStyle.PanelFrame(f)
    else
        f.summaryBar = CreateFrame('Frame', nil, f)
        OldKraken.UIStyle.Panel(f.summaryBar, 0, 0, 900, 64)
    end
    f.summaryBar:SetSize(900, 64)
    f.summaryBar:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, -543)
    f.summaryLine = f.summaryBar:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
    f.summaryLine:SetPoint('LEFT', f.summaryBar, 'LEFT', 17, 0)
    f.summaryLine:SetWidth(560); f.summaryLine:SetJustifyH('LEFT'); f.summaryLine:SetWordWrap(false)

    f.cancelCreate = action(f.summaryBar, 'Скасувати', 593, -13, 110, function()
        f.creationMode = false
        refresh()
    end)
    f.cancelCreate:SetHeight(38)

    f.submit = action(f.summaryBar, 'Створити івент', 713, -13, 170, function()
        local day = getDate()
        local when = day and parseDate(day.day, day.month, day.year, hour, minute)
        if not when then print('Old Kraken: оберіть коректні дату та місцевий час.'); return end
        if Events:Create(f.title:GetText(), f.description:GetText(), when, currentKind, f.size:GetText(), activity) then
            autoFilledTitle = nil
            f.title:SetText(''); f.description:SetText(''); f.creationMode = false; refresh()
            print('Old Kraken: подію збережено; синхронізацію поставлено в чергу.')
        else
            print('Old Kraken: перевірте назву, дату, кількість місць і належність до гільдії.')
        end
    end, 'primary')
    f.submit:SetHeight(38)

    syncAutoTitle()
    showActivity()

    f.formControls = {
        f.step1, f.step2, f.step3,
        f.kindChips.raid, f.kindChips.dungeon, f.kindChips.pvp, f.kindChips.guild,
        f.noLocationButton, activityButton,
        f.title, f.title.label, f.dateButton, f.dateCaption,
        timeLabel, minuteLabel, f.hourMenu, f.minuteMenu,
        f.size, f.size.label, f.sizeMinus, f.sizePlus,
        f.description, f.description.label, f.descriptionHint,
        f.summaryBar, f.cancelCreate, f.submit,
    }
    f.viewControls={f.empty,f.emptyAction,f.previousPage,f.nextPage,f.pageLabel,scroll,f.join,f.leave,f.cancel,f.inviteAll,f.roleMenu}
    f.SetCreationMode=function(_,value) f.creationMode=value==true; refresh() end
    f:HookScript('OnShow',refresh)
    f:Hide(); return f
end
function Events:Show()
    if not active then connect() end
    if not active then print('Old Kraken: календар доступний після входу до гільдії.'); return end
    if OldKraken.UIHub then
        OldKraken.UIHub:ShowPage('events')
    else
        if not window then window=createWindow() end
        window:Show()
    end
    refresh()
end

function Events:ShowEvent(key)
    if window then window.creationMode=false end
    if events[key] and not events[key].cancelled then selected=key end
    self:Show()
end
if OldKraken.UIHub then
    OldKraken.UIHub:RegisterPage('events', 'Івенти', '03', function(parent)
        if not window then window=createWindow(parent) end
        return window
    end)
end
function Events:GetRelayDiagnostics()
    local snapshot={}
    for reason,value in pairs(relayStats) do snapshot[reason]=value end
    return snapshot
end

function Events:PrintRelayDiagnostics()
    local s=self:GetRelayDiagnostics()
    print('|cff2ec4b6Old Kraken|r: Guild Events relay diagnostics (session counters)')
    for _,reason in ipairs({'invalid_payload','rejected_relay_cancelled','rejected_relay_sender','rejected_relay_mismatch','rejected_relay_stale','rejected_relay_equivocation','rejected_direct_stale','rejected_direct_equivocation','rejected_capacity'}) do
        print('  '..reason..': '..s[reason])
    end
end

function Events:AlertsEnabled()
    local settings=OldKraken.DB and OldKraken.DB.settings
    return type(settings)=='table' and settings.guildEventNotifications~=false
end
function Events:SetAlertsEnabled(enabled)
    local settings=OldKraken.DB and OldKraken.DB.settings
    if type(settings)~='table' then return false end
    settings.guildEventNotifications=enabled and true or false
    OldKraken:Fire('GUILD_EVENTS_ALERT_SETTING'); return true
end

OldKraken:On('GUILD_EVENTS_CHANGED',refresh)
