-- Guild-only event calendar. The event owner is authoritative for signups.
local Events = {}
OldKraken.GuildEvents = Events
local comm, codec = OldKraken.Communication, OldKraken.GroupFinder
local kinds = {raid='Рейд', dungeon='Підземелля', pvp='PvP', guild='Збір гільдії'}
local roles = {tank='Танк', healer='Лікар', dps='DPS', flex='Учасник'}
local statuses = {pending='Очікує', accepted='Прийнято', reserve='Резерв', rejected='Відхилено'}
local statusCode = {pending='P',accepted='A',reserve='R',rejected='D'}
local codeStatus = {P='pending',A='accepted',R='reserve',D='rejected'}
local active, identity, profile, storage = false, nil, nil, nil
local events, dirty, intents, newDirty, relayDirty = {}, {}, {}, {}, {}
local sequence, lastQuery, nextRetry = 0, 0, 0
local window, selected, rows, currentRole, currentKind = nil, nil, {}, 'flex', 'raid'
local page = 1
local catalog = OldKraken.ActivityCatalog
local activityLabels = {['']='Не вибрано'}
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
local function save()
    if not storage then return end
    storage.owned, storage.observed, storage.intents, storage.sequence = {}, {}, {}, sequence
    for key, e in pairs(events) do
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
    local e = decode(sender, payload, isRelay); if not e then return end
    if cancellationOnly and not e.cancelled then return end
    local key = eventKey(e.owner,e.id)
    local old = events[key]
    if isRelay then
        if not old or old.owner==identity or old.cancelled or e.rev<=old.rev
            or old.when~=e.when or old.kind~=e.kind or old.title~=e.title
            or old.description~=e.description or old.size~=e.size or old.activity~=e.activity then return end
        e.relayed=true
        e.ownerRev=old.ownerRev or (not old.relayed and old.rev or 0)
    elseif old and old.relayed then
        -- Ignore owner snapshots older than the last direct owner revision.
        if e.rev < (old.ownerRev or 0) then return end
        if not e.cancelled then storage.cancelledSeen[key]=nil end
        old=nil
    end
    if old and old.rev > e.rev then return end
    if old and old.rev == e.rev then
        if not isRelay and e.owner~=identity then storage.relays[key]=payload end
        local intent = intents[key]
        if intent and ((intent.role == 'leave' and not old.people[identity]) or (intent.role ~= 'leave' and old.people[identity] == intent.role and old.statuses[identity] ~= 'rejected') or old.cancelled) then
            intents[key] = nil; save(); fire()
        end
        return
    end
    if not old and not events[key] and count(events) >= 100 then return end
    if e.owner == identity and old then e.versions = old.versions end
    if not isRelay then e.ownerRev=e.rev end
    events[key] = e
    if not isRelay and e.owner~=identity then
        storage.relays[key]=payload
    end
    local intent = intents[key]
    if intent and (not isRelay or e.cancelled) and ((intent.role == 'leave' and not e.people[identity]) or (intent.role ~= 'leave' and e.people[identity] == intent.role and e.statuses[identity] ~= 'rejected') or e.cancelled) then intents[key] = nil end
    if e.cancelled and e.owner~=identity and e.people[identity] and e.statuses[identity]~='rejected' and not storage.cancelledSeen[key] then
        storage.cancelledSeen[key]=e.when+172800
        OldKraken:Fire('GUILD_EVENTS_CANCELLED',key,e)
    end
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

local function updateSignup(sender, owner, id, role, version)
    local key = eventKey(owner,id)
    local e = events[key]
    if not e or e.owner ~= identity or e.cancelled or not validText(sender,1,128)
        or (role ~= 'leave' and not roles[role]) or not version or version % 1 ~= 0 or version < 1 or version > 9000000000000000 then return end
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
    local f = codec._unpackFields(payload,4)
    if not f or #f ~= 4 or f[1] ~= identity or not validID(f[2]) then return end
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
    local key=eventKey(identity,id); events[key]=e; dirty[key]=true; newDirty[key]=true; save(); fire(); return true
end
function Events:Cancel(key)
    local e=events[key]; if not active or not e or e.owner~=identity or e.cancelled then return false end
    e.cancelled=true; e.rev=e.rev+1; dirty[key]=true; save(); fire(); return true
end
function Events:Signup(key, role)
    local e=events[key]
    if not active or not e or e.cancelled or (role~='leave' and not roles[role]) then return false end
    if role~='leave' and e.owner==identity and e.statuses[identity]~='accepted' and acceptedCount(e)>=e.size then return false end
    sequence=math.max(sequence+1,GetServerTime()*1000)
    local intent={role=role,version=sequence}; intents[key]=intent
    if e.owner==identity then updateSignup(identity,e.owner,e.id,role,intent.version) end
    save(); nextRetry=0; fire(); return true
end
function Events:Decide(key, name, status)
    local e=events[key]
    if not active or not e or e.owner~=identity or e.cancelled or not e.people[name] or name==identity or not statuses[status] or status=='pending' then return false end
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
        active=false; events,dirty,intents,newDirty,relayDirty={}, {}, {}, {}, {}; selected=nil
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
    events,dirty,intents,newDirty,relayDirty={}, {}, {}, {}, {}
    sequence=type(storage.sequence)=='number' and storage.sequence or 0
    if type(storage.owned)=='table' then
        for k,e in pairs(storage.owned) do
            if type(e)=='table' and e.owner==identity and type(e.people)=='table' then
                local ok,payload=pcall(encode,e)
                local valid=ok and decode(identity,payload)
                if valid and k==eventKey(identity,valid.id) then valid.versions=type(e.versions)=='table' and e.versions or {}; events[k]=valid; dirty[k]=true end
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
                    valid.relayed=e.relayed==true
                    valid.ownerRev=valid.relayed and (type(e.ownerRev)=='number' and math.max(0,math.min(valid.rev,e.ownerRev)) or 0) or valid.rev
                    events[k]=valid
                end
            end
        end
    end
    for k,payload in pairs(storage.relays) do
        local e=type(payload)=='string' and decode(nil,payload,true)
        if not e or e.owner==identity or k~=eventKey(e.owner,e.id) then storage.relays[k]=nil end
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
frame:RegisterEvent('PLAYER_LOGIN'); frame:RegisterEvent('GUILD_ROSTER_UPDATE')
frame:SetScript('OnEvent', connect)
if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(3,function()
        if not active then connect(); return end
        local name,guild=character(),type(GetGuildInfo)=='function' and GetGuildInfo('player')
        if name~=identity or not guild or (type(GetRealmName)=='function' and (GetRealmName()..'\001'..guild..'\001'..name)~=profile) then active=false; connect(); return end
        local removed = false
        for key,e in pairs(events) do
            if e.when < GetServerTime()-172800 then events[key],dirty[key],intents[key],newDirty[key],relayDirty[key],storage.relays[key]=nil,nil,nil,nil,nil,nil; removed=true end
        end
        if removed then save(); fire() end
        local now=GetTime()
        if now>=nextRetry then
            if comm:SendProtocol('CEVQUERY','') then nextRetry=now+180 end
            for key in pairs(intents) do
                local e=events[key]; local intent=intents[key]
                if e and e.owner~=identity then comm:SendProtocol('CEVRSVP',codec._pack({e.owner,e.id,intent.role,string.format('%.0f',intent.version)})) end
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
local function action(parent, label, x, y, width, callback)
    local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate'); OldKraken.UIStyle.Button(b)
    b:SetSize(width,24); b:SetPoint('TOPLEFT',parent,'TOPLEFT',x,y); b:SetText(label); b:SetScript('OnClick',callback); return b
end
local function field(parent, label, x, y, width, value)
    local caption=parent:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); caption:SetPoint('TOPLEFT',parent,'TOPLEFT',x,y); caption:SetText(label)
    local box=CreateFrame('EditBox',nil,parent,'InputBoxTemplate'); box:SetPoint('TOPLEFT',parent,'TOPLEFT',x+4,y-18); box:SetSize(width,22); box:SetAutoFocus(false); box:SetText(value or '')
    box:SetScript('OnEscapePressed',function(self) self:ClearFocus() end); return box
end
local function selectMenu(parent,name,x,y,width,values,labels,get,set)
    local f=CreateFrame('Frame',name,parent,'UIDropDownMenuTemplate'); OldKraken.UIStyle.Dropdown(f)
    f:SetPoint('TOPLEFT',parent,'TOPLEFT',x-16,y+3); UIDropDownMenu_SetWidth(f,width-34); UIDropDownMenu_JustifyText(f,'LEFT')
    UIDropDownMenu_Initialize(f,function(_,level)
        for _,v in ipairs(values) do
            local value=v; local item=UIDropDownMenu_CreateInfo(); item.text=labels[value]; item.value=value; item.checked=get()==value
            item.func=function() set(value); UIDropDownMenu_SetText(f,labels[value]) end; UIDropDownMenu_AddButton(item,level)
        end
    end)
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
                item.func=function() set(value); UIDropDownMenu_SetText(f,string.format('%02d',value)) end
                UIDropDownMenu_AddButton(item,level)
            end
        end
    end)
    UIDropDownMenu_SetText(f,string.format('%02d',get())); return f
end
local function datePicker(parent)
    local chosen, month, year
    local caption=parent:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
    caption:SetPoint('TOPLEFT',parent,'TOPLEFT',255,-382); caption:SetText('Дата')
    local button=action(parent,'Обрати дату',255,-400,125,function() end)
    local popup=CreateFrame('Frame',nil,parent,'BackdropTemplate')
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
        end)
        cells[i]=cell
    end
    button:SetScript('OnClick',function()
        if popup:IsShown() then popup:Hide(); return end
        local current=chosen or date('*t'); month,year=current.month,current.year; render(); popup:Show()
    end)
    popup:Hide()
    parent:HookScript('OnHide',function() popup:Hide() end)
    return function() return chosen end
end
local function refresh()
    if not window then return end
    window.alertButton:SetText(Events:AlertsEnabled() and 'Сповіщення: увімк.' or 'Сповіщення: вимк.')
    local list={}
    for key,e in pairs(events) do if not e.cancelled and e.when>=GetServerTime()-172800 then list[#list+1]={key=key,event=e} end end
    table.sort(list,function(a,b) if a.event.when~=b.event.when then return a.event.when<b.event.when end return a.key<b.key end)
    local pageCount=math.max(1,math.ceil(#list/8))
    page=math.max(1,math.min(page,pageCount))
    window.visible=list
    window.pageLabel:SetText(page..' / '..pageCount)
    window.previousPage:SetShown(pageCount>1)
    window.nextPage:SetShown(pageCount>1)
    window.empty:SetShown(#list==0)
    for i,row in ipairs(rows) do
        local entry=list[(page-1)*8+i]
        if entry then
            local e=entry.event
            row:SetText(date('%d.%m.%Y %H:%M',e.when)..'  ·  '..e.title..(e.activity~='' and ' · '..(activityLabels[e.activity] or e.activity) or '')..'  ·  '..acceptedCount(e)..'/'..e.size)
            if selected==entry.key then row:LockHighlight() else row:UnlockHighlight() end
            row:Show()
        else row:UnlockHighlight(); row:Hide() end
    end
    local e=selected and events[selected]
    for _,row in ipairs(window.signupRows) do row:Hide() end
    if e and not e.cancelled then
        local names={}; for name in pairs(e.people) do names[#names+1]=name end; table.sort(names)
        local pending=intents[selected]
        local lines={}
        for _,name in ipairs(names) do
            local role=e.people[name]
            lines[#lines+1]=(catalog.roleIcons[role] or '')..' '..name..' — '..(roles[role] or role)..' · '..statuses[e.statuses[name]]
        end
        local own=e.owner==identity
        window.details:SetText(e.title..'\n'..kinds[e.kind]..(e.activity~='' and ' · '..(activityLabels[e.activity] or e.activity) or '')..' · '..date('%d.%m.%Y %H:%M',e.when)..'\nАвтор: '..e.owner..' · прийнято '..acceptedCount(e)..'/'..e.size..(e.relayed and '\nСтан отримано через гільдію' or '')..'\n'..e.description..'\n\n'..(own and 'Заявки та учасники:' or 'Заявки та учасники:\n'..(#lines>0 and table.concat(lines,'\n') or 'Поки немає'))..(pending and '\n\nОчікується доставка автору' or ''))
        local height=window.details:GetStringHeight()+8
        if own then
            for i,name in ipairs(names) do
                local row=window.signupRows[i]
                if not row then
                    row=CreateFrame('Frame',nil,window.detailsContent); row:SetSize(340,58)
                    row.label=row:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); row.label:SetPoint('TOPLEFT',row,'TOPLEFT',0,0); row.label:SetWidth(335); row.label:SetJustifyH('LEFT')
                    row.accept=action(row,'Прийняти',0,-22,94,function(self) if not Events:Decide(selected,self:GetParent().member,'accepted') then print('Old Kraken: не вдалося прийняти учасника; перевірте вільні місця.') end end)
                    row.reserve=action(row,'Резерв',100,-22,94,function(self) Events:Decide(selected,self:GetParent().member,'reserve') end)
                    row.reject=action(row,'Відхилити',200,-22,104,function(self) Events:Decide(selected,self:GetParent().member,'rejected') end)
                    window.signupRows[i]=row
                end
                row.member=name; row:ClearAllPoints(); row:SetPoint('TOPLEFT',window.detailsContent,'TOPLEFT',0,-height-(i-1)*58)
                local role=e.people[name]
                row.label:SetText((catalog.roleIcons[role] or '')..' '..name..' · '..roles[role]..' · '..statuses[e.statuses[name]])
                row.accept:SetShown(name~=identity); row.reserve:SetShown(name~=identity); row.reject:SetShown(name~=identity); row:Show()
            end
            height=height+#names*58
        end
        window.detailsContent:SetHeight(math.max(250,height+8))
        window.cancel:SetShown(e.owner==identity)
        window.join:SetShown(not pending and (not e.people[identity] or e.statuses[identity]=='rejected'))
        window.leave:SetShown((pending and pending.role~='leave') or (not pending and e.people[identity] ~= nil and e.statuses[identity]~='rejected'))
    else
        window.details:SetText('Оберіть подію зі списку.'); window.cancel:Hide(); window.join:Hide(); window.leave:Hide()
        window.detailsContent:SetHeight(250)
    end
end
local function createWindow(parent)
    local f
    if parent then
        f=CreateFrame('Frame','OldKrakenEventsFrame',parent)
    else
        f=CreateFrame('Frame','OldKrakenEventsFrame',UIParent,'BasicFrameTemplateWithInset')
    end
    if not parent then table.insert(UISpecialFrames,'OldKrakenEventsFrame') end
    f:SetSize(840,560); f:SetPoint('CENTER',parent or UIParent,'CENTER'); f:SetMovable(not parent); f:EnableMouse(true)
    if not parent then
        f:RegisterForDrag('LeftButton'); f:SetScript('OnDragStart',f.StartMoving); f:SetScript('OnDragStop',f.StopMovingOrSizing)
    end
    f:SetClampedToScreen(true)
    if not parent then OldKraken.UIStyle.Window(f) end
    if f.TitleText then f.TitleText:SetText('Old Kraken — Події гільдії') end
    f.alertButton=action(f,'Сповіщення',630,-35,185,function() Events:SetAlertsEnabled(not Events:AlertsEnabled()); refresh() end)
    local note=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); note:SetPoint('TOPLEFT',f,'TOPLEFT',18,-38); note:SetText('Час подій показано за місцевим часом комп’ютера.')
    f.empty=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); f.empty:SetPoint('TOPLEFT',f,'TOPLEFT',25,-72); f.empty:SetText('Найближчих подій немає.')
    for i=1,8 do
        local index=i
        rows[i]=action(f,'',18,-65-(i-1)*30,410,function() local entry=f.visible and f.visible[(page-1)*8+index]; if entry then selected=entry.key; refresh() end end)
    end
    f.previousPage=action(f,'‹',138,-310,45,function() page=page-1; refresh() end)
    f.pageLabel=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    f.pageLabel:SetPoint('TOPLEFT',f,'TOPLEFT',191,-315); f.pageLabel:SetWidth(64); f.pageLabel:SetJustifyH('CENTER')
    f.nextPage=action(f,'›',263,-310,45,function() page=page+1; refresh() end)
    local scroll=CreateFrame('ScrollFrame','OldKrakenEventsDetailsScroll',f,'UIPanelScrollFrameTemplate'); scroll:SetPoint('TOPLEFT',f,'TOPLEFT',450,-66); scroll:SetSize(350,250)
    f.detailsContent=CreateFrame('Frame',nil,scroll); f.detailsContent:SetSize(350,250); scroll:SetScrollChild(f.detailsContent); f.signupRows={}
    f.details=f.detailsContent:CreateFontString(nil,'OVERLAY','GameFontHighlight'); f.details:SetPoint('TOPLEFT'); f.details:SetWidth(350); f.details:SetJustifyH('LEFT'); f.details:SetJustifyV('TOP')
    selectMenu(f,'OldKrakenEventsRole',450,-325,150,{'tank','healer','dps','flex'},roles,function() return currentRole end,function(v) currentRole=v end)
    f.join=action(f,'Записатися',605,-325,100,function() if selected and not Events:Signup(selected,currentRole) then print('Old Kraken: не вдалося записатися; перевірте місця та зв’язок.') end end)
    f.leave=action(f,'Виписатися',605,-325,100,function() if selected then Events:Signup(selected,'leave') end end)
    f.cancel=action(f,'Скасувати',710,-325,105,function() if selected then Events:Cancel(selected) end end)
    local heading=f:CreateFontString(nil,'OVERLAY','GameFontNormal'); heading:SetPoint('TOPLEFT',f,'TOPLEFT',18,-358); heading:SetText('Створити подію')
    f.title=field(f,'Назва',18,-382,220,''); local getDate=datePicker(f)
    local hour,minute=0,0
    local hourValues,hourLabels={},{}
    for value=0,23 do hourValues[#hourValues+1]=value; hourLabels[value]=string.format('%02d',value) end
    local timeLabel=f:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); timeLabel:SetPoint('TOPLEFT',f,'TOPLEFT',390,-382); timeLabel:SetText('Година')
    local minuteLabel=f:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); minuteLabel:SetPoint('TOPLEFT',f,'TOPLEFT',490,-382); minuteLabel:SetText('Хвилина')
    selectMenu(f,'OldKrakenEventsHour',390,-400,90,hourValues,hourLabels,function() return hour end,function(v) hour=v end)
    selectMinutes(f,490,-400,function() return minute end,function(v) minute=v end)
    f.size=field(f,'Місць (2–40)',600,-382,80,'10')
    f.description=field(f,'Опис',18,-435,430,'')
    local activity=''
    local activityLabel=f:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); activityLabel:SetPoint('TOPLEFT',f,'TOPLEFT',18,-485)
    local activityMenu=CreateFrame('Frame','OldKrakenEventsActivity',f,'UIDropDownMenuTemplate'); OldKraken.UIStyle.Dropdown(activityMenu)
    activityMenu:SetPoint('TOPLEFT',f,'TOPLEFT',2,-500); UIDropDownMenu_SetWidth(activityMenu,310); UIDropDownMenu_JustifyText(activityMenu,'LEFT')
    UIDropDownMenu_Initialize(activityMenu,function(_,level)
        for _,entry in ipairs(catalog[currentKind] or {}) do
            local value=entry.value; local item=UIDropDownMenu_CreateInfo(); item.text=entry.label; item.value=value; item.checked=activity==value
            item.func=function() activity=value; UIDropDownMenu_SetText(activityMenu,value~='' and activityLabels[value] or 'Не вибрано') end
            UIDropDownMenu_AddButton(item,level)
        end
    end)
    local function showActivity()
        local enabled=catalog[currentKind]~=nil
        activityLabel:SetText(currentKind=='raid' and 'Рейд' or 'Підземелля'); activityLabel:SetShown(enabled); activityMenu:SetShown(enabled)
        UIDropDownMenu_SetText(activityMenu,activity~='' and activityLabels[activity] or 'Не вибрано')
    end
    selectMenu(f,'OldKrakenEventsKind',465,-453,160,{'raid','dungeon','pvp','guild'},kinds,function() return currentKind end,function(v) currentKind=v; activity=''; showActivity() end)
    showActivity()
    action(f,'Створити',650,-453,150,function()
        local day=getDate()
        local when=day and parseDate(day.day,day.month,day.year,hour,minute)
        if not when then print('Old Kraken: оберіть коректні дату та місцевий час.'); return end
        if Events:Create(f.title:GetText(),f.description:GetText(),when,currentKind,f.size:GetText(),activity) then f.title:SetText(''); f.description:SetText(''); print('Old Kraken: подію збережено; синхронізацію поставлено в чергу.')
        else print('Old Kraken: перевірте назву, дату, кількість місць і належність до гільдії.') end
    end)
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
    if events[key] and not events[key].cancelled then selected=key end
    self:Show()
end
if OldKraken.UIHub then
    OldKraken.UIHub:RegisterPage('events', 'Івенти', '03', function(parent)
        if not window then window=createWindow(parent) end
        return window
    end)
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
