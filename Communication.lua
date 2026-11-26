OldKraken = OldKraken or {}
local T = OldKraken.Translate or function(text) return text end

local Communication = {}
OldKraken.Communication = Communication

Communication.PREFIX = "OLDKRKN"
Communication.queue = {}
Communication.ready = false
Communication.rosterPresence, Communication.rosterVersions, Communication.rosterSpecs = {}, {}, {}
Communication.lastSpecReply, Communication.lastBroadcastSpecID = nil, nil
Communication.pendingSpecBroadcast, Communication.pendingSpecForce = false, false
Communication.lastTestID = nil
Communication.handlers = {}
Communication.part1Filters = {}
Communication.stats = { sent = 0, retried = 0, dropped = 0, received = 0, invalid = 0 }
local MAX_QUEUE = 4096
local ACTION_RESERVE = 256
local MAX_ERROR_ATTEMPTS = 5
Communication.MAX_QUEUE = MAX_QUEUE
Communication.BACKGROUND_LIMIT = MAX_QUEUE - ACTION_RESERVE
Communication.pendingTransmissions = {}
Communication.reservedReplaySlots = 0
Communication.retryAt, Communication.backoff = 0, 0
Communication.stats.deduplicated, Communication.stats.backpressure, Communication.stats.restarted = 0, 0, 0
local PRIORITY = {JOIN=0,RESPONSE=0,CANCEL=0,CEVRSVP=0,CVCANCEL=0,
    WOREQ=0,WOACT=0,WOPAY=0,WOPAYR=0,WORESULT=0,WORESR=0,
    ANNOUNCE=1,UPDATE=1,BUMP=1,WORDER=1,CVNEW=1,CVSTATE=1,CEVENT=1}
local PART_BYTES = 80
local MAX_PARTS = 32
local MAX_ASSEMBLIES = 1024
local CACHE_LIMIT = 4096
local CACHE_TTL = 120
local messageSequence = 0
local sessionID = tostring(GetServerTime()) .. "-" .. tostring(math.random(100000, 999999))
local assemblies, completed, seenSenders = {}, {}, {}
local assemblyCount, completedCount = 0, 0
local nextPrune=0

local function EnsurePresenceGuild(self)
    local guild = GetGuildInfo and GetGuildInfo('player') or ''
    if self.presenceGuild ~= guild or guild == '' then
        self.rosterPresence, self.rosterVersions, self.rosterSpecs = {}, {}, {}
        seenSenders = {}
        self.presenceGuild = guild
        self.lastPresenceQuery, self.lastSpecReply, self.lastBroadcastSpecID, self.lastBroadcastSpecPayload = nil, nil, nil, nil
        self.pendingSpecBroadcast, self.pendingSpecForce = false, false
    end
end
local function Secret(value)
    return type(issecretvalue) == 'function' and issecretvalue(value)
end
local function ValidSpecID(value)
    return not Secret(value) and type(value) == 'number' and value >= 1 and value <= 9999999 and math.floor(value) == value
end

local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function Prune(now)
    if now<nextPrune then return end
    nextPrune=now+1
    if assemblyCount == 0 and completedCount == 0 then return end
    for k, v in pairs(assemblies) do
        if now - v.time > CACHE_TTL then
            assemblies[k] = nil
            assemblyCount = math.max(0, assemblyCount - 1)
        end
    end
    for k, v in pairs(completed) do
        if now - v.time > CACHE_TTL then
            completed[k] = nil
            completedCount = math.max(0, completedCount - 1)
        end
    end
end

-- GF1 payloads are hexadecimal bytes. This preserves UTF-8 and reserves delimiters.
local HEX_ENC, HEX_DEC = {}, {}
for i = 0, 255 do
    local ch = string.char(i)
    local hex = string.format("%02X", i)
    HEX_ENC[ch] = hex
    HEX_DEC[hex] = ch
end

local function Encode(payload)
    return (payload:gsub(".", HEX_ENC))
end

local function Decode(payload)
    if #payload % 2 ~= 0 or payload:find("[^0-9A-F]") then return nil end
    return (payload:gsub("%x%x", HEX_DEC))
end

local VALID_TYPES = { ANNOUNCE = true, CANCEL = true, JOIN = true, RESPONSE = true,
    UPDATE = true, QUERY = true, SYNC = true, BUMP = true,
    CEVENT = true, CVNEW = true, CVSTATE = true, CVCANCEL = true, CEVQUERY = true, CEVRSVP = true,
    WKPROF = true, WKQUERY = true, WKRELAY = true, WRQUERY = true, WRRESULT = true, WRBATCH = true, WRLEARN = true, WRFORGET = true,
    WRQ = true, WRIDX = true, WRGET = true, WRPAGE = true,
    WORDER = true, WORELAY = true, WOREQ = true, WOPAY = true, WOERROR = true, WOQUERY = true,
    WOACT = true, WOPAYR = true, WORESULT = true, WORESR = true }
local GROUP_SNAPSHOTS={ANNOUNCE=true,UPDATE=true,SYNC=true,CANCEL=true,BUMP=true}
local CRITICAL_KINDS={JOIN=true,RESPONSE=true,CANCEL=true,ANNOUNCE=true,UPDATE=true,BUMP=true,
    CEVENT=true,CVNEW=true,CEVRSVP=true,WORDER=true,WOREQ=true,WOPAY=true,WORESULT=true}
-- Group Finder owns these kinds; every other kind belongs to another subsystem and
-- must survive a Group Finder state reset.
local GROUP_FINDER_KINDS={ANNOUNCE=true,CANCEL=true,JOIN=true,RESPONSE=true,
    UPDATE=true,QUERY=true,SYNC=true,BUMP=true}
local function groupRecordKey(kind,payload)
    if not GROUP_SNAPSHOTS[kind] and kind~='RESPONSE' and kind~='JOIN' then return end
    local fields,pos={},1
    for i=1,2 do
        local first,last,size=payload:find('(%d+):',pos)
        if first~=pos or not size or #size>4 then return end
        size=tonumber(size); if last+size>#payload then return end
        fields[i]=payload:sub(last+1,last+size); pos=last+size+1
    end
    if GROUP_SNAPSHOTS[kind] then return fields[2]..'\001'..fields[1] end
    return fields[1]..'\001'..fields[2]
end

function Communication:RegisterHandler(kind, callback)
    if not VALID_TYPES[kind] or type(callback) ~= "function" or self.handlers[kind] then
        return false
    end
    self.handlers[kind] = callback
    return true
end

local function effectiveQueueSize(self)
    return #self.queue+self.reservedReplaySlots
end

local function releaseReplayReservation(self,job)
    self.reservedReplaySlots=self.reservedReplaySlots-(job.replayReserved or 0)
    job.replayReserved=0
end

function Communication:SendProtocol(kind, payload)
    if not VALID_TYPES[kind] or type(payload) ~= "string" or #payload > PART_BYTES * MAX_PARTS then
        return false, "invalid payload or type"
    end
    if not self.ready or not IsInGuild or not IsInGuild() then
        return false, "transport unavailable"
    end
    local guild=GetGuildInfo and GetGuildInfo('player')
    if type(guild)~='string' or guild=='' then return false,'transport unavailable' end
    if #self.queue==0 then self.pendingTransmissions={} end
    local pendingKey=guild..'\001'..kind..'\001'..payload
    local pending=self.pendingTransmissions[pendingKey]
    if pending then self.stats.deduplicated=self.stats.deduplicated+1; return true,pending.id end
    local priority=PRIORITY[kind] or 2
    messageSequence = (messageSequence + 1) % 1000000
    local id = sessionID .. "-" .. tostring(messageSequence)
    local count = math.max(1, math.ceil(#payload / PART_BYTES))
    local limit=priority==0 and MAX_QUEUE or (MAX_QUEUE-ACTION_RESERVE)
    if effectiveQueueSize(self)+count>limit then self.stats.backpressure=self.stats.backpressure+1; return false,'queue full' end
    local messages = {}
    for part = 1, count do
        local data = payload:sub((part - 1) * PART_BYTES + 1, part * PART_BYTES)
        local message = table.concat({ "GF2", kind, id, part, count, Encode(data) }, "^")
        if #message > 240 then return false, "message too long" end
        messages[part] = message
    end
    local job={key=pendingKey,id=id,kind=kind,messages=messages,remaining=count,priority=priority,
        recordKey=groupRecordKey(kind,payload),snapshot=GROUP_SNAPSHOTS[kind]}
    local originalCount = #self.queue
    for part, message in ipairs(messages) do
        if not self:QueueMessage(message,job,part) then
            while #self.queue > originalCount do table.remove(self.queue) end
            return false, "transport unavailable"
        end
    end
    self.pendingTransmissions[pendingKey]=job
    return true, id
end

function Communication:RequestSync()
    return self:SendProtocol("QUERY", "")
end

function Communication:ClearProtocolState()
    -- Only this subsystem's traffic is discarded: Workshop Sync and Guild Events
    -- share the same transport and must keep their queued pages and assemblies.
    for i = #self.queue, 1, -1 do
        local entry = self.queue[i]
        local kind = entry.message:match("^GF2%^([A-Z]+)%^")
        if kind and GROUP_FINDER_KINDS[kind] then
            local job = entry.job
            if job then
                job.remaining = job.remaining - 1
                if job.remaining == 0 then
                    releaseReplayReservation(self,job)
                    self.pendingTransmissions[job.key] = nil
                end
            end
            table.remove(self.queue, i)
        end
    end
    for key, item in pairs(assemblies) do
        if GROUP_FINDER_KINDS[item.kind] then
            assemblies[key] = nil
            assemblyCount = math.max(0, assemblyCount - 1)
        end
    end
    for key, item in pairs(completed) do
        if GROUP_FINDER_KINDS[item.kind] then
            completed[key] = nil
            completedCount = math.max(0, completedCount - 1)
        end
    end
    if #self.queue==0 then self.retryAt,self.backoff=0,0 end
end

local function PlayerName()
    local name = UnitName and UnitName("player")
    return type(name) == "string" and name or nil
end
local function FullPlayerName()
    if type(UnitName) ~= 'function' then return nil end
    local name, surname = UnitName('player')
    if Secret(name) or type(name) ~= 'string' or name == '' then return nil end
    if not Secret(surname) and type(surname) == 'string' and surname ~= '' then return name .. ' ' .. surname end
    return name
end

local function Print(message)
    if OldKraken.Print then
        OldKraken:Print(message)
    else
        print("|cff2ec4b6Old Kraken|r: " .. tostring(message or ""))
    end
end

local function IsOurMessagePrefix(prefix)
    return prefix == Communication.PREFIX
end

function Communication:GetStatus()
    local chatInfo = C_ChatInfo
    local restricted

    if chatInfo and type(chatInfo.AreOutgoingAddonChatMessagesRestricted) == "function" then
        local ok, value = pcall(chatInfo.AreOutgoingAddonChatMessagesRestricted)
        if ok then
            restricted = value
        end
    end

    return {
        apiAvailable = chatInfo and type(chatInfo.SendAddonMessage) == "function" or false,
        registerAvailable = chatInfo and type(chatInfo.RegisterAddonMessagePrefix) == "function" or false,
        restricted = restricted,
        registered = self.ready,
        queued = #self.queue,
        retryIn=math.max(0,math.ceil(self.retryAt-GetTime())),
        lastSendError=self.lastSendError,
        inGuild = IsInGuild and IsInGuild() or false,
    }
end

function Communication:PrintStatus()
    local status = self:GetStatus()
    Print(T("Діагностика обміну повідомленнями:"))
    Print("  SendAddonMessage: " .. (status.apiAvailable and T("доступний") or T("недоступний")))
    Print("  RegisterAddonMessagePrefix: " .. (status.registerAvailable and T("доступний") or T("недоступний")))
    Print(T("  Префікс OLDKRKN: ") .. (status.registered and T("зареєстрований") or T("не зареєстрований")))
    Print(T("  Обмеження вихідних повідомлень: ") ..
        (status.restricted == nil and T("невідомо") or (status.restricted and T("так") or T("ні"))))
    Print(T("  Гільдія: ") .. (status.inGuild and T("так") or T("ні")) ..
        T("; повідомлень у черзі: ") .. status.queued)
    Print(T('  Очікування повтору: ')..status.retryIn..T(' с.; об’єднано повторів: ')..self.stats.deduplicated..T('; черга зайнята: ')..self.stats.backpressure)
    Print(T("  Надіслано: ") .. self.stats.sent .. T("; повторів: ") .. self.stats.retried ..
        T("; відкинуто: ") .. self.stats.dropped .. T("; некоректних: ") .. self.stats.invalid)
end

function Communication:QueueMessage(message,job,part)
    if type(message) ~= "string" or message == "" then
        return false
    end

    if #message > 240 then
        return false
    end

    if effectiveQueueSize(self) >= MAX_QUEUE then
        self.stats.backpressure=self.stats.backpressure+1
        return false
    end

    local guild
    if message:sub(1, 4) == 'GF2^' or message:sub(1, 9) == 'OKP^SPEC^' or message:sub(1, 10) == 'OKP^SPEC2^' then
        guild = GetGuildInfo and GetGuildInfo('player')
        if type(guild) ~= 'string' or guild == '' then return false end
    end
    self.queue[#self.queue + 1] = { message = message, attempts = 0, guild = guild,job=job,part=part,priority=job and job.priority or 1 }
    return true
end

local function finishEntry(self,index,accepted)
    local entry=table.remove(self.queue,index)
    if entry.job then
        local job=entry.job
        job.remaining=job.remaining-1
        if accepted and not job.startedAt then job.startedAt=GetTime() end
        if job.remaining==0 then
            releaseReplayReservation(self,job)
            self.pendingTransmissions[job.key]=nil
        elseif accepted then
            job.replayReserved=(job.replayReserved or 0)+1
            self.reservedReplaySlots=self.reservedReplaySlots+1
        end
    end
end
local function deferEntry(self,entry,reason)
    entry.attempts=entry.attempts+1
    self.stats.retried=self.stats.retried+1
    self.backoff=math.min(60,self.backoff==0 and 2 or self.backoff*2)
    self.retryAt=GetTime()+self.backoff+math.random()
    self.lastSendError=reason
end
local function dropEntryOrJob(self,index,entry,reason,notifyCritical)
    local job=entry.job
    if not job then
        table.remove(self.queue,index)
    else
        if job.dropped then return end
        job.dropped=true
        for i=#self.queue,1,-1 do
            if self.queue[i].job==job then table.remove(self.queue,i) end
        end
        job.remaining=0
        releaseReplayReservation(self,job)
        if job.key and self.pendingTransmissions[job.key]==job then self.pendingTransmissions[job.key]=nil end
    end
    self.stats.dropped=self.stats.dropped+1
    if job and notifyCritical and CRITICAL_KINDS[job.kind] then
        pcall(Print,'Не вдалося надіслати повідомлення: '..job.kind)
        if type(OldKraken.Fire)=='function' then
            pcall(OldKraken.Fire,OldKraken,'COMMUNICATION_SEND_FAILED',job.kind,job.id,reason)
        end
    end
end
local function entryError(self,index,entry,reason,now)
    entry.errorAttempts=(entry.errorAttempts or 0)+1
    self.stats.retried=self.stats.retried+1
    self.lastSendError=reason
    if entry.errorAttempts>=MAX_ERROR_ATTEMPTS then
        dropEntryOrJob(self,index,entry,reason,true)
    else
        entry.errorBackoff=math.min(60,(entry.errorBackoff or 0)==0 and 2 or entry.errorBackoff*2)
        entry.nextTryAt=now+entry.errorBackoff+math.random()
    end
end
local function runPump(self)
    EnsurePresenceGuild(self)
    if self.pendingSpecBroadcast and self.ready and IsInGuild and IsInGuild()
        and #self.queue<=8 and (not self.lastSpecReply or GetTime()-self.lastSpecReply>=10) then
        self:SendLocalSpec(self.pendingSpecForce)
    end
    if #self.queue==0 or GetTime()<self.retryAt then return end
    if not IsInGuild or not IsInGuild() then return end
    local now=GetTime()
    local snapshots
    for _,entry in ipairs(self.queue) do
        local job=entry.job
        if job and job.snapshot and job.recordKey then
            snapshots=snapshots or {}
            snapshots[(entry.guild or '')..'\001'..job.recordKey]=true
        end
    end
    local index,priority=nil,3
    for i,entry in ipairs(self.queue) do
        local job=entry.job
        local blocked=snapshots and job and not job.snapshot and job.recordKey and snapshots[(entry.guild or '')..'\001'..job.recordKey]
        local value=entry.priority or 1
        if not blocked and (not entry.nextTryAt or now>=entry.nextTryAt) and value<priority then
            index,priority=i,value
        end
    end
    if not index then return end
    local entry=self.queue[index]
    if entry.guild and (not GetGuildInfo or GetGuildInfo('player')~=entry.guild) then
        dropEntryOrJob(self,index,entry,'guild changed',false); return
    end
    -- If a multipart transfer was interrupted long enough to approach the receiver
    -- assembly timeout, replay its complete set rather than leave orphaned fragments.
    local job=entry.job
    if job and job.startedAt and GetTime()-job.startedAt>=90 then
        local errors={}
        for i=#self.queue,1,-1 do
            local old=self.queue[i]
            if old.job==job then
                errors[old.part]={old.errorAttempts,old.errorBackoff,old.nextTryAt}
                table.remove(self.queue,i)
            end
        end
        releaseReplayReservation(self,job)
        job.remaining=#job.messages; job.startedAt=nil
        for part,message in ipairs(job.messages) do
            local state=errors[part]
            self.queue[#self.queue+1]={message=message,attempts=0,guild=entry.guild,job=job,part=part,priority=job.priority,
                errorAttempts=state and state[1],errorBackoff=state and state[2],nextTryAt=state and state[3]}
        end
        self.stats.restarted=self.stats.restarted+1
        return
    end
    local chatInfo=C_ChatInfo
    if not chatInfo or type(chatInfo.SendAddonMessage)~='function' then deferEntry(self,entry,'API unavailable'); return end
    local ok,result=pcall(chatInfo.SendAddonMessage,self.PREFIX,entry.message,'GUILD')
    if not ok then entryError(self,index,entry,tostring(result),now); return end
    local results=Enum and Enum.SendAddonMessageResult
    local success=result==nil or (results and results.Success~=nil and result==results.Success) or (not results and result==0)
    if not success then
        local throttle=results and ((results.AddonMessageThrottle~=nil and result==results.AddonMessageThrottle)
            or (results.ChannelThrottle~=nil and result==results.ChannelThrottle)
            or (results.AddOnMessageLockdown~=nil and result==results.AddOnMessageLockdown))
        if throttle then deferEntry(self,entry,tostring(result)) else entryError(self,index,entry,tostring(result),now) end
        return
    end
    finishEntry(self,index,true)
    self.backoff,self.retryAt,self.lastSendError=0,0,nil
    self.stats.sent=self.stats.sent+1
end
function Communication:Pump()
    local t0 = OldKraken and OldKraken.perfEnabled and type(debugprofilestop) == 'function' and debugprofilestop() or nil
    runPump(self)
    if t0 and OldKraken.PerfRecord then OldKraken:PerfRecord('comm.pump', debugprofilestop() - t0) end
end

function Communication:SendTest()
    if not IsInGuild or not IsInGuild() then
        Print(T("Для тесту персонаж має перебувати в гільдії."))
        return
    end

    if not self.ready then
        Print(T("Префікс ще не зареєстрований. Перевір після входу в гру."))
        return
    end

    local name = PlayerName()
    if not name then
        Print(T("Не вдалося визначити ім'я персонажа."))
        return
    end

    local id = tostring(GetServerTime()) .. "-" .. name
    self.lastTestID = id

    if self:QueueMessage(table.concat({ "TEST", id, name, name }, "^")) then
        Print(T("Тестове повідомлення додано до черги GUILD. Попроси іншого члена гільдії виконати /okr comm status і перевірити отримання."))
    end
end

-- Presence is evidence of installation during this session, never evidence of absence.
function Communication:GetLocalVersion()
    local getter = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    return (getter and getter('OldKraken', 'Version')) or OldKraken.version or 'unknown'
end
local function VersionParts(version)
    if type(version) ~= 'string' then return end
    local major, minor, patch, suffix = version:match('^(%d+)%.(%d+)%.(%d+)(.*)$')
    if not major then return end
    suffix = suffix:match('^([^+]*)')
    local stage, number = 3, 0
    if suffix ~= '' then
        local label, revision = suffix:match('^%-([a-z]+)%.?(%d*)$')
        stage = ({alpha=0, beta=1, rc=2})[label]
        if not stage then return end
        number = tonumber(revision) or 0
    end
    return {tonumber(major), tonumber(minor), tonumber(patch), stage, number}
end
function Communication:CompareVersions(left, right)
    local a, b = VersionParts(left), VersionParts(right)
    if not a or not b then return nil end
    for i=1,#a do
        if a[i] < b[i] then return -1 end
        if a[i] > b[i] then return 1 end
    end
    return 0
end
Communication.UPDATE_URL = 'https://www.curseforge.com/wow/addons/old-kraken'
function Communication:IsStableVersion(version)
    local parts = VersionParts(version)
    return parts ~= nil and parts[4] == 3
end
function Communication:GetNewestKnownVersion()
    EnsurePresenceGuild(self)
    local localVersion = self:GetLocalVersion()
    if not VersionParts(localVersion) then return nil, localVersion end
    local best = nil
    for _, version in pairs(self.rosterVersions or {}) do
        if self:IsStableVersion(version) and self:CompareVersions(version, localVersion) == 1 then
            if not best or self:CompareVersions(version, best) == 1 then
                best = version
            end
        end
    end
    if best then best = best:match('^([^+]+)') or best end
    return best, localVersion
end
function Communication:CheckVersionNotification()
    local settings = OldKraken.DB and OldKraken.DB.settings
    if type(settings) ~= 'table' or settings.versionChatNotifications == false then return false end
    if type(InCombatLockdown) == 'function' and InCombatLockdown() then return false end
    local newest, localVersion = self:GetNewestKnownVersion()
    if not newest then return false end
    if settings.versionSessionNotified == newest then return false end
    settings.versionSessionNotified = newest
    Print(string.format(T('Доступна нова версія %s (у вас %s). Оновіть аддон на CurseForge (/okr).'), newest, tostring(localVersion)))
    return true
end
local function PresenceKey(name)
    if Secret(name) or type(name) ~= 'string' or name == '' then return '' end
    local realm = GetRealmName and GetRealmName() or ''
    if not name:find('-', 1, true) then name = name .. '-' .. realm end
    return (name:gsub('%s+', ''))
end
local function IsSelfPresenceKey(key)
    if key == '' then return false end
    local fullKey, shortKey = PresenceKey(FullPlayerName()), PresenceKey(PlayerName())
    return (fullKey ~= '' and key == fullKey) or (shortKey ~= '' and key == shortKey)
end
function Communication:HasRosterAddon(name)
    EnsurePresenceGuild(self)
    local key = PresenceKey(name)
    return IsSelfPresenceKey(key) or self.rosterPresence[key] == true
end
function Communication:GetRosterVersion(name)
    self:HasRosterAddon(name)
    local key = PresenceKey(name)
    if IsSelfPresenceKey(key) then return self:GetLocalVersion() end
    return self.rosterVersions[key]
end
function Communication:RequestRosterPresence()
    EnsurePresenceGuild(self)
    if not self.ready or not IsInGuild() then return end
    local now = GetTime()
    if self.lastPresenceQuery and now - self.lastPresenceQuery < 30 then return end
    if self:QueueMessage('OKP^QUERY') then self.lastPresenceQuery = now end
end
function Communication:RecordRosterPresence(sender, version)
    EnsurePresenceGuild(self)
    local key = PresenceKey(sender)
    if not self.rosterPresence[key] or (version and self.rosterVersions[key] ~= version) then
        self.rosterPresence[key] = true
        if version then self.rosterVersions[key] = version end
        if OldKraken.Fire then OldKraken:Fire('ROSTER_ADDON_CHANGED') end
        if version then
            if OldKraken.Fire then OldKraken:Fire('VERSION_STATUS_CHANGED') end
            self:CheckVersionNotification()
        end
    end
end

function Communication:GetLocalSpecID()
    local api = C_SpecializationInfo
    if not api or type(api.GetSpecialization) ~= 'function' then return nil end
    local ok, index = pcall(api.GetSpecialization)
    if type(api.GetSpecializationInfo) ~= 'function' then return nil end
    if not ok or Secret(index) or type(index) ~= 'number' or index < 1 or math.floor(index) ~= index then return nil end
    local success, id = pcall(api.GetSpecializationInfo, index)
    if success and ValidSpecID(id) then return id end
end

local function Integer(value, minimum, maximum)
    return not Secret(value) and type(value) == 'number' and value >= minimum
        and (not maximum or value <= maximum) and math.floor(value) == value
end

local function IsValidUTF8(value)
    local i, length = 1, #value
    while i <= length do
        local a = value:byte(i)
        if a < 128 then
            i = i + 1
        else
            local size = a >= 194 and a <= 223 and 2 or a >= 224 and a <= 239 and 3 or a >= 240 and a <= 244 and 4
            if not size or i + size - 1 > length then return false end
            local b = value:byte(i + 1)
            if b < 128 or b > 191 or (a == 224 and b < 160) or (a == 237 and b > 159)
                or (a == 240 and b < 144) or (a == 244 and b > 143) then return false end
            for j = i + 2, i + size - 1 do
                local c = value:byte(j)
                if c < 128 or c > 191 then return false end
            end
            i = i + size
        end
    end
    return true
end

local function ValidSpecName(name)
    return not Secret(name) and type(name) == 'string' and #name >= 1 and #name <= 64
        and not name:find('[%^|%z\1-\31\127]') and IsValidUTF8(name)
end

local function ParsePoints(points)
    if Secret(points) or type(points) ~= 'string' then return nil end
    local a, b, c = points:match('^(%d+)%/(%d+)%/(%d+)$')
    if not a then return nil end
    a, b, c = tonumber(a), tonumber(b), tonumber(c)
    if not Integer(a, 0, 999) or not Integer(b, 0, 999) or not Integer(c, 0, 999) then return nil end
    local maximum = math.max(a, b, c)
    local count = (a == maximum and 1 or 0) + (b == maximum and 1 or 0) + (c == maximum and 1 or 0)
    return a, b, c, maximum > 0 and count == 1
end

local function RosterStorage()
    local db = OldKraken.DB
    if type(db) ~= 'table' then return nil end
    if db.roster == nil then db.roster = {} end
    if type(db.roster) ~= 'table' then return nil end
    local roster = db.roster
    if roster.localSpecs == nil then roster.localSpecs = {} end
    if roster.localSpecSeq == nil then roster.localSpecSeq = {} end
    if roster.specSequences == nil then roster.specSequences = {} end
    if type(roster.localSpecs) ~= 'table' or type(roster.localSpecSeq) ~= 'table' or type(roster.specSequences) ~= 'table' then return nil end
    return roster
end

local function ResolveRealmScope()
    if OldKraken.Database and type(OldKraken.Database.GetRealmScope) == 'function' then
        return OldKraken.Database:GetRealmScope()
    end
    local realm = GetRealmName and GetRealmName()
    if Secret(realm) then return nil end
    if realm == '' then return 'Forever' end
    if type(realm) ~= 'string' or realm == '' then return nil end
    return realm
end

local function LocalSpecKey()
    local name = FullPlayerName()
    local realm = ResolveRealmScope()
    if Secret(realm) or type(realm) ~= 'string' or realm == '' or not name then return nil end
    return realm .. '\001' .. name
end

function Communication:GetLocalTraitSignature()
    local talents, traits = C_ClassTalents, C_Traits
    if type(talents) ~= 'table' or type(traits) ~= 'table' or type(talents.GetActiveConfigID) ~= 'function'
        or type(traits.GetConfigInfo) ~= 'function' or type(traits.GetTreeCurrencyInfo) ~= 'function'
        or type(traits.GetTreeNodes) ~= 'function' or type(traits.GetNodeInfo) ~= 'function' then return nil end
    local ok, cfgID = pcall(talents.GetActiveConfigID)
    if not ok or not Integer(cfgID, 1) then return nil end
    local configOK, cfg = pcall(traits.GetConfigInfo, cfgID)
    if not configOK or Secret(cfg) or type(cfg) ~= 'table' or Secret(cfg.treeIDs) or type(cfg.treeIDs) ~= 'table' then return nil end
    local treeID = cfg.treeIDs[1]
    if not Integer(treeID, 1) then return nil end
    local currencyOK, currency = pcall(traits.GetTreeCurrencyInfo, cfgID, treeID, true)
    if not currencyOK or Secret(currency) or type(currency) ~= 'table' or Secret(currency[1]) or type(currency[1]) ~= 'table' then return nil end
    local spent = currency[1].spent
    if not Integer(spent, 0) then return nil end
    local nodesOK, nodes = pcall(traits.GetTreeNodes, treeID)
    if not nodesOK or Secret(nodes) or type(nodes) ~= 'table' then return nil end
    local purchased = {}
    for _, nodeID in pairs(nodes) do
        if not Integer(nodeID, 1) then return nil end
        local nodeOK, info = pcall(traits.GetNodeInfo, cfgID, nodeID)
        if not nodeOK or Secret(info) or type(info) ~= 'table' or not Integer(info.ranksPurchased, 0) then return nil end
        if info.ranksPurchased > 0 then purchased[#purchased + 1] = {id = nodeID, ranks = info.ranksPurchased} end
    end
    table.sort(purchased, function(a, b) return a.id < b.id end)
    local parts = {}
    for _, node in ipairs(purchased) do parts[#parts + 1] = tostring(node.id) .. ':' .. tostring(node.ranks) end
    return {cfgID = cfgID, treeID = treeID, spent = spent, distSig = tostring(treeID) .. '|' .. table.concat(parts, ',')}
end

local function isInspectingTalentsFrame(tf, expectedCfgID)
    if type(tf.IsInspecting) == 'function' then
        local ok, inspecting = pcall(tf.IsInspecting, tf)
        if ok and inspecting then return true end
    end
    if type(tf.GetInspectUnit) == 'function' then
        local ok, unit = pcall(tf.GetInspectUnit, tf)
        if ok and unit ~= nil then return true end
    end
    if not Secret(tf.inspectUnit) and tf.inspectUnit ~= nil then return true end
    if expectedCfgID and type(tf.GetConfigID) == 'function' then
        local ok, cfgID = pcall(tf.GetConfigID, tf)
        if ok and Integer(cfgID, 1) and cfgID ~= expectedCfgID then return true end
    end
    return false
end

local function ReadTreeHeadersSpec(expectedCfgID)
    local tf = PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
    if Secret(tf) or type(tf) ~= 'table' or isInspectingTalentsFrame(tf, expectedCfgID)
        or Secret(tf.treeHeaders) or type(tf.treeHeaders) ~= 'table' or #tf.treeHeaders ~= 3 then return nil, 'unknown' end
    local headers, values = tf.treeHeaders, {}
    for i = 1, 3 do
        local h = headers[i]
        if Secret(h) or type(h) ~= 'table' or not h.Name or not h.Text or not h.Icon
            or type(h.Name.GetText) ~= 'function' or type(h.Text.GetText) ~= 'function' or type(h.Icon.GetTexture) ~= 'function' then return nil, 'unknown' end
        local okName, name = pcall(h.Name.GetText, h.Name)
        local okText, text = pcall(h.Text.GetText, h.Text)
        local okIcon, icon = pcall(h.Icon.GetTexture, h.Icon)
        if not okName or not okText or not okIcon or Secret(name) or Secret(text) or type(name) ~= 'string' or type(text) ~= 'string' then return nil, 'unknown' end
        name = (name:gsub('^%s+', '')):gsub('%s+$', '')
        local digits = text:match('^%s*(%d+)%s*$')
        local points = digits and tonumber(digits)
        if not ValidSpecName(name) or not Integer(points, 0, 999) then return nil, 'unknown' end
        if not Integer(icon, 1, 999999999) then return nil, 'unknown' end
        values[i] = {name = name, points = points, icon = icon}
    end
    local a, b, c = values[1].points, values[2].points, values[3].points
    local maximum = math.max(a, b, c)
    local count = (a == maximum and 1 or 0) + (b == maximum and 1 or 0) + (c == maximum and 1 or 0)
    if maximum == 0 then return nil, 'reset' end
    if count ~= 1 then return nil, 'unknown' end
    local best = a == maximum and values[1] or b == maximum and values[2] or values[3]
    return {name = best.name, icon = best.icon, points = a .. '/' .. b .. '/' .. c, total = a + b + c}, 'active'
end

function Communication:GetLocalTreeSpec()
    local sig = self:GetLocalTraitSignature()
    if not sig then return 'unknown', nil end
    local roster, key = RosterStorage(), LocalSpecKey()
    if not roster or not key then return 'unknown', nil end
    if sig.spent == 0 then roster.localSpecs[key] = nil; return 'reset', nil end
    local cached = roster.localSpecs[key]
    if type(cached) ~= 'table' then roster.localSpecs[key] = nil; return 'unknown', nil end
    local now = GetServerTime()
    local a, b, c, unique = ParsePoints(cached.points)
    if cached.distSig ~= sig.distSig or not ValidSpecName(cached.name) or not Integer(cached.icon, 0, 999999999) or not unique
        or a + b + c ~= sig.spent or not Integer(cached.updatedAt, 0) or cached.updatedAt > now + 600 or now - cached.updatedAt > 604800 then
        roster.localSpecs[key] = nil
        return 'unknown', nil
    end
    return 'active', {name = cached.name, icon = cached.icon ~= 0 and cached.icon or nil, points = cached.points}
end

function Communication:RefreshLocalTreeSpec()
    local sig = self:GetLocalTraitSignature()
    local roster, key = RosterStorage(), LocalSpecKey()
    if not sig or not roster or not key then return end
    local tf = PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
    if not Secret(tf) and type(tf) == 'table' and isInspectingTalentsFrame(tf, sig.cfgID) then return end
    local previous = roster.localSpecs[key]
    if sig.spent == 0 then
        roster.localSpecs[key] = nil
        if previous ~= nil or self.lastBroadcastSpecPayload ~= '0^0/0/0^' then
            if OldKraken.Fire then OldKraken:Fire('ROSTER_ADDON_CHANGED') end
            self:SendLocalSpec(false)
        end
        return
    end
    local spec, headerState = ReadTreeHeadersSpec(sig.cfgID)
    if headerState ~= 'active' or not spec or spec.total ~= sig.spent then
        roster.localSpecs[key] = nil
        if previous ~= nil and OldKraken.Fire then OldKraken:Fire('ROSTER_ADDON_CHANGED') end
        return
    end
    roster.localSpecs[key] = {name = spec.name, icon = spec.icon, points = spec.points, distSig = sig.distSig, updatedAt = GetServerTime()}
    local changed = type(previous) ~= 'table' or previous.name ~= spec.name or previous.icon ~= spec.icon or previous.points ~= spec.points or previous.distSig ~= sig.distSig
    if changed then
        if OldKraken.Fire then OldKraken:Fire('ROSTER_ADDON_CHANGED') end
        self:SendLocalSpec(false)
    end
end

function Communication:RecordRosterSpec(sender, specID)
    EnsurePresenceGuild(self)
    if self.presenceGuild == '' or not ValidSpecID(specID) then return false end
    local key = PresenceKey(sender)
    if key == '' then return false end
    local prior = self.rosterSpecs[key]
    if prior and prior.source == 'spec2' and GetTime() - prior.receivedAt <= 3600 then return false end
    self.rosterSpecs[key] = {id = specID, source = 'spec1', receivedAt = GetTime()}
    if (not prior or prior.id ~= specID) and OldKraken.Fire then OldKraken:Fire('ROSTER_ADDON_CHANGED') end
    return true
end

function Communication:RecordRosterSpec2(sender, seq, icon, points, name, payload)
    EnsurePresenceGuild(self)
    local key, roster = PresenceKey(sender), RosterStorage()
    local realm = ResolveRealmScope()
    if self.presenceGuild == '' or key == '' or not roster or Secret(realm) or type(realm) ~= 'string' or realm == '' then return false end
    local seqKey = realm .. '\001' .. self.presenceGuild .. '\001' .. key
    local sequences, now = roster.specSequences, GetServerTime()
    local hwm = sequences[seqKey]
    if type(hwm) == 'table' and Integer(hwm.updatedAt, 0) and now - hwm.updatedAt > 2592000 then sequences[seqKey] = nil; hwm = nil end
    if type(hwm) == 'table' and Integer(hwm.seq, 1, 999999999999) then
        if seq < hwm.seq then return false end
        if seq == hwm.seq then
            if payload ~= hwm.payload then return false end
            local current = self.rosterSpecs[key]
            if current and current.source == 'spec2' and current.seq == seq and GetTime() - current.receivedAt <= 3600 then current.receivedAt = GetTime() end
            return true
        end
    end
    if not sequences[seqKey] and Count(sequences) >= 1024 then
        local oldestKey, oldestTime
        for k, entry in pairs(sequences) do
            local updated = type(entry) == 'table' and entry.updatedAt
            if not Integer(updated, 0) or now - updated > 2592000 then sequences[k] = nil
            elseif not oldestTime or updated < oldestTime then oldestKey, oldestTime = k, updated end
        end
        if Count(sequences) >= 1024 and oldestKey then sequences[oldestKey] = nil end
    end
    sequences[seqKey] = {seq = seq, payload = payload, updatedAt = now}
    local old = self.rosterSpecs[key]
    local reset = points == '0/0/0'
    self.rosterSpecs[key] = {source = 'spec2', reset = reset, seq = seq, receivedAt = GetTime(),
        name = not reset and name or nil, icon = icon ~= 0 and icon or nil, points = not reset and points or nil}
    local changed = not old or old.source ~= 'spec2' or old.reset ~= reset or old.name ~= (not reset and name or nil)
        or old.icon ~= (icon ~= 0 and icon or nil) or old.points ~= (not reset and points or nil)
    if changed and OldKraken.Fire then OldKraken:Fire('ROSTER_ADDON_CHANGED') end
    return true
end

function Communication:GetRosterSpec(name)
    EnsurePresenceGuild(self)
    local key = PresenceKey(name)
    if key == '' then return nil end
    if IsSelfPresenceKey(key) then
        local state, spec = self:GetLocalTreeSpec()
        if state ~= 'active' then return nil end
        spec.receivedAt = GetTime()
        return spec
    end
    local entry = self.rosterSpecs[key]
    if not entry then return nil end
    if GetTime() - entry.receivedAt > 3600 then self.rosterSpecs[key] = nil; return nil end
    if entry.source ~= 'spec2' or entry.reset then return nil end
    return {name = entry.name, icon = entry.icon, points = entry.points, receivedAt = entry.receivedAt}
end

function Communication:SendLocalSpec(forceOnQuery)
    EnsurePresenceGuild(self)
    if not self.ready or not IsInGuild or not IsInGuild() then return false end
    local state, spec = self:GetLocalTreeSpec()
    if state == 'unknown' then self.pendingSpecBroadcast, self.pendingSpecForce = false, false; return false end
    local force = forceOnQuery or self.pendingSpecForce
    local payload = state == 'reset' and '0^0/0/0^' or (tostring(spec.icon or 0) .. '^' .. spec.points .. '^' .. spec.name)
    if not force and (payload == self.lastBroadcastSpecPayload or (state == 'reset' and not self.lastBroadcastSpecPayload)) then
        self.pendingSpecBroadcast, self.pendingSpecForce = false, false
        return false
    end
    if self.lastSpecReply and GetTime() - self.lastSpecReply < 10 then
        self.pendingSpecBroadcast = true
        if force then self.pendingSpecForce = true end
        return false
    end
    if #self.queue > 8 then
        self.pendingSpecBroadcast = true
        if force then self.pendingSpecForce = true end
        return false
    end
    local roster, key = RosterStorage(), LocalSpecKey()
    if not roster or not key then return false end
    local savedSeq = roster.localSpecSeq[key]
    if not Integer(savedSeq, 0, 999999999999) then savedSeq = 0 end
    local currentSeq = Integer(self.localSpecSeq, 0, 999999999999) and self.localSpecSeq or 0
    local timeSlot = math.max(0, (GetServerTime() or 0) - 1700000000) * 100
    local seq = math.max(currentSeq + 1, savedSeq + 1, timeSlot)
    if not Integer(seq, 1, 999999999999) then return false end
    if self:QueueMessage('OKP^SPEC2^' .. string.format('%.0f', seq) .. '^' .. payload) then
        self.localSpecSeq, roster.localSpecSeq[key] = seq, seq
        self.lastSpecReply, self.lastBroadcastSpecPayload = GetTime(), payload
        self.pendingSpecBroadcast, self.pendingSpecForce = false, false
        return true
    end
    self.pendingSpecBroadcast = true
    if force then self.pendingSpecForce = true end
    return false
end

local function recordCompleted(key, now, kind)
    if completedCount >= CACHE_LIMIT then
        local oldestKey, oldestTime
        for k, v in pairs(completed) do if not oldestTime or v.time < oldestTime then oldestKey, oldestTime = k, v.time end end
        if oldestKey ~= nil then
            completed[oldestKey] = nil
            completedCount = math.max(0, completedCount - 1)
        end
    end
    if not completed[key] then completedCount = completedCount + 1 end
    completed[key] = { time = now, kind = kind }
end

local function receiveAddonMessage(self, message, sender)
    if type(sender) ~= "string" or sender == "" or #sender > 128 then
        return
    end

    if #message > 240 then
        if message:sub(1, 10) == 'OKP^SPEC2^' then return end
        self.stats.invalid = self.stats.invalid + 1
        return
    end

    EnsurePresenceGuild(self)
    if not seenSenders[sender] then
        self:RecordRosterPresence(sender)
        if self.presenceGuild ~= '' then seenSenders[sender] = true end
    end
    if message == 'OKP^QUERY' then
        self:SendLocalSpec(true)
        local now = GetTime()
        if not self.lastPresenceReply or now - self.lastPresenceReply >= 10 then
            if self:QueueMessage('OKP^HERE^' .. self:GetLocalVersion()) then self.lastPresenceReply = now end
        end
        return
    elseif message == 'OKP^HERE' then return
    elseif message:sub(1, 9) == 'OKP^HERE^' then
        local version = message:sub(10)
        if #version <= 48 and version:match('^[%w%.%+%-]+$') then
            self:RecordRosterPresence(sender, version)
        end
        return
    elseif message:sub(1, 9) == 'OKP^SPEC^' then
        local raw = message:sub(10)
        local idStr = raw:match('^(%d+)$')
        local specID = idStr and tonumber(idStr)
        if specID and specID >= 1 and specID <= 9999999 then self:RecordRosterSpec(sender, specID) end
        return
    elseif message:sub(1, 10) == 'OKP^SPEC2^' then
        local raw = message:sub(11)
        local seqStr, iconStr, pointsStr, nameStr = raw:match('^([^%^]+)%^([^%^]+)%^([^%^]+)%^(.*)$')
        if not seqStr or not iconStr or not pointsStr or not nameStr or nameStr:find('^', 1, true)
            or not seqStr:match('^%d+$') or not iconStr:match('^%d+$') then return end
        local seq, icon = tonumber(seqStr), tonumber(iconStr)
        local a, b, c, unique = ParsePoints(pointsStr)
        if not Integer(seq, 1, 999999999999) or not Integer(icon, 0, 999999999) or not a then return end
        if a + b + c == 0 then
            if pointsStr ~= '0/0/0' or iconStr ~= '0' or nameStr ~= '' then return end
        elseif not unique or not ValidSpecName(nameStr) then return end
        self:RecordRosterSpec2(sender, seq, icon, pointsStr, nameStr, iconStr .. '^' .. pointsStr .. '^' .. nameStr)
        return
    end

    if message:sub(1, 4) == "GF2^" then
        local kind, id, part, count, encoded = message:match("^GF2%^([A-Z]+)%^(%d+%-%d+%-%d+)%^(%d+)%^(%d+)%^([0-9A-F]*)$")
        part, count = tonumber(part), tonumber(count)
        local encLen = encoded and #encoded or -1
        if not kind or not VALID_TYPES[kind] or #id > 32 or not part or not count
            or count < 1 or count > MAX_PARTS or part < 1 or part > count
            or encLen < 0 or encLen % 2 ~= 0 or encLen > PART_BYTES * 2
            or (part < count and encLen ~= PART_BYTES * 2) then
            self.stats.invalid = self.stats.invalid + 1
            return
        end
        local now = GetTime()
        Prune(now)
        local key = sender .. "\001" .. id
        if completed[key] then return end
        local payload = Decode(encoded)
        if not payload then
            self.stats.invalid = self.stats.invalid + 1
            return
        end
        if part == 1 then
            local filter = self.part1Filters and self.part1Filters[kind]
            if type(filter) == 'function' and filter(payload, sender) == false then
                if assemblies[key] then
                    assemblies[key] = nil
                    assemblyCount = math.max(0, assemblyCount - 1)
                end
                recordCompleted(key, now, kind)
                return
            end
        end
        local item = assemblies[key]
        if not item then
            if assemblyCount >= MAX_ASSEMBLIES then self.stats.invalid = self.stats.invalid + 1; return end
            item = { kind = kind, count = count, time = now, parts = {}, received = 0 }
            assemblies[key] = item
            assemblyCount = assemblyCount + 1
        elseif item.kind ~= kind or item.count ~= count then
            assemblies[key] = nil
            assemblyCount = math.max(0, assemblyCount - 1)
            self.stats.invalid = self.stats.invalid + 1
            return
        end
        if item.parts[part] then
            if item.parts[part] ~= payload then
                assemblies[key] = nil
                assemblyCount = math.max(0, assemblyCount - 1)
                self.stats.invalid = self.stats.invalid + 1
            end
            return
        end
        item.parts[part] = payload
        item.received = item.received + 1
        if item.received ~= count then return end
        assemblies[key] = nil
        assemblyCount = math.max(0, assemblyCount - 1)
        payload = table.concat(item.parts)
        local handler = self.handlers[kind]
        if handler then
            local ok, err = pcall(handler, sender, id, payload)
            if not ok then
                self.stats.invalid = self.stats.invalid + 1
                Print(T("Помилка обробника протоколу: ") .. tostring(err))
                return
            end
        end
        recordCompleted(key, now, kind)
        self.stats.received = self.stats.received + 1
        return
    end

    local kind, id, target, origin = strsplit("^", message)
    local me = PlayerName()
    if not me then
        return
    end

    if kind == "TEST" then
        Print(T("Отримано TEST від ") .. sender .. T(". Надсилаю ACK у GUILD."))
        self:QueueMessage(table.concat({ "ACK", id or "", target or "", me }, "^"))
    elseif kind == "ACK" and target == me and id == self.lastTestID then
        Print(T("Отримано ACK від ") .. sender .. T(". Двосторонній обмін працює."))
    end
end

function Communication:OnAddonMessage(prefix, message, channel, sender)
    if not IsOurMessagePrefix(prefix) or channel ~= "GUILD" or type(message) ~= "string" then
        return
    end
    local t0 = OldKraken and OldKraken.perfEnabled and type(debugprofilestop) == 'function' and debugprofilestop() or nil
    receiveAddonMessage(self, message, sender)
    if t0 and OldKraken.PerfRecord then OldKraken:PerfRecord('comm.recv', debugprofilestop() - t0) end
end

function Communication:HandleCommand(command)
    command = command or ""
    local subcommand
    if command == "comm" then
        subcommand = ""
    else
        subcommand = string.match(command, "^comm%s+(.+)$")
    end
    if subcommand == nil then
        return false
    end

    subcommand = string.lower(subcommand)
    if subcommand == "" or subcommand == "status" then
        self:PrintStatus()
    elseif subcommand == "test" then
        self:SendTest()
    else
        Print(T("Використання: /okr comm status або /okr comm test"))
    end

    return true
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("ADDON_LOADED")
pcall(frame.RegisterEvent, frame, 'ACTIVE_TALENT_GROUP_CHANGED')
pcall(frame.RegisterEvent, frame, 'PLAYER_SPECIALIZATION_CHANGED')
pcall(frame.RegisterEvent, frame, 'PLAYER_ENTERING_WORLD')
pcall(frame.RegisterEvent, frame, 'PLAYER_REGEN_ENABLED')

local hookedTalentFrames = {}
local function InstallTalentHooks()
    local tf = PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
    if Secret(tf) or type(tf) ~= 'table' then return end
    local state = hookedTalentFrames[tf] or {}
    hookedTalentFrames[tf] = state
    if not state.refresh and type(hooksecurefunc) == 'function' and type(tf.RefreshTreeHeaders) == 'function' then
        state.refresh = pcall(hooksecurefunc, tf, 'RefreshTreeHeaders', function() Communication:RefreshLocalTreeSpec() end)
    end
    if not state.show and type(tf.HookScript) == 'function' then
        state.show = pcall(tf.HookScript, tf, 'OnShow', function() Communication:RefreshLocalTreeSpec() end)
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        InstallTalentHooks()
        local chatInfo = C_ChatInfo
        if not chatInfo or type(chatInfo.RegisterAddonMessagePrefix) ~= "function" then
            Print(T("RegisterAddonMessagePrefix недоступний у цьому клієнті."))
            return
        end

        local ok, registered = pcall(chatInfo.RegisterAddonMessagePrefix, Communication.PREFIX)
        Communication.ready = ok and registered ~= false
        if Communication.ready then
            Print(T("Префікс OLDKRKN зареєстровано."))
            Communication:RequestRosterPresence()
            Communication:SendLocalSpec(true)
        else
            Print(T("Не вдалося зареєструвати префікс OLDKRKN: ") .. tostring(registered))
        end

        if C_Timer and C_Timer.NewTicker then
            Communication.retryAt=GetTime()+math.random()*3
            Communication.pumpTicker = C_Timer.NewTicker(0.7, function()
                Communication:Pump()
            end)
        end
    elseif event == 'ADDON_LOADED' then
        local addon = ...
        if addon == 'Blizzard_PlayerSpells' or (PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame) then InstallTalentHooks() end
    elseif event == 'ACTIVE_TALENT_GROUP_CHANGED' then
        Communication:SendLocalSpec(false)
    elseif event == 'PLAYER_SPECIALIZATION_CHANGED' then
        local unit = ...
        if unit == 'player' then Communication:SendLocalSpec(false) end
    elseif event == 'PLAYER_ENTERING_WORLD' then
        local isInitialLogin, isReloadingUi = ...
        if isInitialLogin == true and not isReloadingUi and OldKraken.DB and type(OldKraken.DB.settings) == 'table' then
            OldKraken.DB.settings.versionSessionNotified = nil
        end
        Communication:CheckVersionNotification()
    elseif event == 'PLAYER_REGEN_ENABLED' then
        Communication:CheckVersionNotification()
    elseif event == "CHAT_MSG_ADDON" then
        Communication:OnAddonMessage(...)
    end
end)
