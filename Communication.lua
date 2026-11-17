OldKraken = OldKraken or {}

local Communication = {}
OldKraken.Communication = Communication

Communication.PREFIX = "OLDKRKN"
Communication.queue = {}
Communication.ready = false
Communication.lastTestID = nil
Communication.handlers = {}
Communication.stats = { sent = 0, retried = 0, dropped = 0, received = 0, invalid = 0 }
local MAX_QUEUE = 4096
local ACTION_RESERVE = 256
Communication.MAX_QUEUE = MAX_QUEUE
Communication.BACKGROUND_LIMIT = MAX_QUEUE - ACTION_RESERVE
Communication.pendingTransmissions = {}
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
local assemblies, completed = {}, {}
local nextPrune=0

local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function Prune(now)
    if now<nextPrune then return end
    nextPrune=now+1
    for k, v in pairs(assemblies) do
        if now - v.time > CACHE_TTL then assemblies[k] = nil end
    end
    for k, v in pairs(completed) do
        if now - v > CACHE_TTL then completed[k] = nil end
    end
end

-- GF1 payloads are hexadecimal bytes. This preserves UTF-8 and reserves delimiters.
local function Encode(payload)
    return (payload:gsub(".", function(c) return string.format("%02X", string.byte(c)) end))
end

local function Decode(payload)
    if #payload % 2 ~= 0 or payload:find("[^0-9A-F]") then return nil end
    return (payload:gsub("%x%x", function(pair) return string.char(tonumber(pair, 16)) end))
end

local VALID_TYPES = { ANNOUNCE = true, CANCEL = true, JOIN = true, RESPONSE = true,
    UPDATE = true, QUERY = true, SYNC = true, BUMP = true,
    CEVENT = true, CVNEW = true, CVSTATE = true, CVCANCEL = true, CEVQUERY = true, CEVRSVP = true,
    WKPROF = true, WKQUERY = true, WKRELAY = true, WRQUERY = true, WRRESULT = true, WRBATCH = true, WRLEARN = true, WRFORGET = true,
    WRQ = true, WRIDX = true, WRGET = true, WRPAGE = true,
    WORDER = true, WORELAY = true, WOREQ = true, WOPAY = true, WOERROR = true, WOQUERY = true,
    WOACT = true, WOPAYR = true, WORESULT = true, WORESR = true }
local GROUP_SNAPSHOTS={ANNOUNCE=true,UPDATE=true,SYNC=true,CANCEL=true,BUMP=true}
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
    if #self.queue+count>limit then self.stats.backpressure=self.stats.backpressure+1; return false,'queue full' end
    local messages = {}
    for part = 1, count do
        local data = payload:sub((part - 1) * PART_BYTES + 1, part * PART_BYTES)
        local message = table.concat({ "GF2", kind, id, part, count, Encode(data) }, "^")
        if #message > 240 then return false, "message too long" end
        messages[part] = message
    end
    local job={key=pendingKey,id=id,messages=messages,remaining=count,priority=priority,
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
    for i = #self.queue, 1, -1 do
        if self.queue[i].message:sub(1, 4) == 'GF2^' then table.remove(self.queue, i) end
    end
    assemblies, completed = {}, {}
    self.pendingTransmissions={}
    self.retryAt,self.backoff=0,0
end

local function PlayerName()
    local name = UnitName and UnitName("player")
    return type(name) == "string" and name or nil
end

local function Print(message)
    print("|cff2ec4b6Old Kraken|r: " .. message)
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
    Print("Діагностика обміну повідомленнями:")
    Print("  SendAddonMessage: " .. (status.apiAvailable and "доступний" or "недоступний"))
    Print("  RegisterAddonMessagePrefix: " .. (status.registerAvailable and "доступний" or "недоступний"))
    Print("  Префікс OLDKRKN: " .. (status.registered and "зареєстрований" or "не зареєстрований"))
    Print("  Обмеження вихідних повідомлень: " ..
        (status.restricted == nil and "невідомо" or (status.restricted and "так" or "ні")))
    Print("  Гільдія: " .. (status.inGuild and "так" or "ні") ..
        "; повідомлень у черзі: " .. status.queued)
    Print('  Очікування повтору: '..status.retryIn..' с.; об’єднано повторів: '..self.stats.deduplicated..'; черга зайнята: '..self.stats.backpressure)
    Print("  Надіслано: " .. self.stats.sent .. "; повторів: " .. self.stats.retried ..
        "; відкинуто: " .. self.stats.dropped .. "; некоректних: " .. self.stats.invalid)
end

function Communication:QueueMessage(message,job,part)
    if type(message) ~= "string" or message == "" then
        return false
    end

    if #message > 240 then
        return false
    end

    if #self.queue >= MAX_QUEUE then
        self.stats.backpressure=self.stats.backpressure+1
        return false
    end

    local guild
    if message:sub(1, 4) == 'GF2^' then
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
        if job.remaining==0 then self.pendingTransmissions[job.key]=nil end
    end
end
local function deferEntry(self,entry,reason)
    entry.attempts=entry.attempts+1
    self.stats.retried=self.stats.retried+1
    self.backoff=math.min(60,self.backoff==0 and 2 or self.backoff*2)
    self.retryAt=GetTime()+self.backoff+math.random()
    self.lastSendError=reason
end
function Communication:Pump()
    if #self.queue==0 or GetTime()<self.retryAt then return end
    if not IsInGuild or not IsInGuild() then return end
    local index,priority=1,3
    for i,entry in ipairs(self.queue) do
        local value=entry.priority or 1
        if value<priority then index,priority=i,value; if value==0 then break end end
    end
    -- A decision must never overtake the snapshot it refers to: a receiver may
    -- have just reloaded and cannot apply the decision until it knows the group.
    local selected=self.queue[index].job
    if selected and selected.recordKey then
        for i=1,index-1 do
            local prior=self.queue[i].job
            if prior and prior.snapshot and prior.recordKey==selected.recordKey then index=i; break end
        end
    end
    local entry=self.queue[index]
    if entry.guild and (not GetGuildInfo or GetGuildInfo('player')~=entry.guild) then
        finishEntry(self,index,false); self.stats.dropped=self.stats.dropped+1; return
    end
    -- If a multipart transfer was interrupted long enough to approach the receiver
    -- assembly timeout, replay its complete set rather than leave orphaned fragments.
    local job=entry.job
    if job and job.startedAt and GetTime()-job.startedAt>=90 then
        for i=#self.queue,1,-1 do if self.queue[i].job==job then table.remove(self.queue,i) end end
        job.remaining=#job.messages; job.startedAt=nil
        for part,message in ipairs(job.messages) do
            self.queue[#self.queue+1]={message=message,attempts=0,guild=entry.guild,job=job,part=part,priority=job.priority}
        end
        self.stats.restarted=self.stats.restarted+1
        return
    end
    local chatInfo=C_ChatInfo
    if not chatInfo or type(chatInfo.SendAddonMessage)~='function' then deferEntry(self,entry,'API unavailable'); return end
    local ok,result=pcall(chatInfo.SendAddonMessage,self.PREFIX,entry.message,'GUILD')
    if not ok then deferEntry(self,entry,tostring(result)); return end
    local results=Enum and Enum.SendAddonMessageResult
    local success=result==nil or (results and results.Success~=nil and result==results.Success) or (not results and result==0)
    if not success then deferEntry(self,entry,tostring(result)); return end
    finishEntry(self,index,true)
    self.backoff,self.retryAt,self.lastSendError=0,0,nil
    self.stats.sent=self.stats.sent+1
end

function Communication:SendTest()
    if not IsInGuild or not IsInGuild() then
        Print("Для тесту персонаж має перебувати в гільдії.")
        return
    end

    if not self.ready then
        Print("Префікс ще не зареєстрований. Перевір після входу в гру.")
        return
    end

    local name = PlayerName()
    if not name then
        Print("Не вдалося визначити ім'я персонажа.")
        return
    end

    local id = tostring(GetServerTime()) .. "-" .. name
    self.lastTestID = id

    if self:QueueMessage(table.concat({ "TEST", id, name, name }, "^")) then
        Print("Тестове повідомлення додано до черги GUILD. Попроси іншого члена гільдії виконати /okr comm status і перевірити отримання.")
    end
end

-- Presence is evidence of installation during this session, never evidence of absence.
Communication.rosterPresence = {}
Communication.rosterVersions = {}
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
local function PresenceKey(name)
    if type(name) ~= 'string' then return '' end
    local realm = GetRealmName and GetRealmName() or ''
    if not name:find('-', 1, true) then name = name .. '-' .. realm end
    return (name:gsub('%s+', ''))
end
function Communication:HasRosterAddon(name)
    local guild = GetGuildInfo and GetGuildInfo('player') or ''
    if self.presenceGuild ~= guild then
        self.rosterPresence = {}
        self.rosterVersions = {}
        self.presenceGuild = guild
        self.lastPresenceQuery = nil
    end
    return PresenceKey(name) == PresenceKey(PlayerName()) or self.rosterPresence[PresenceKey(name)] == true
end
function Communication:GetRosterVersion(name)
    self:HasRosterAddon(name)
    if PresenceKey(name) == PresenceKey(PlayerName()) then return self:GetLocalVersion() end
    return self.rosterVersions[PresenceKey(name)]
end
function Communication:RequestRosterPresence()
    if not self.ready or not IsInGuild() then return end
    local now = GetTime()
    if self.lastPresenceQuery and now - self.lastPresenceQuery < 30 then return end
    if self:QueueMessage('OKP^QUERY') then self.lastPresenceQuery = now end
end
function Communication:RecordRosterPresence(sender, version)
    self:HasRosterAddon(sender) -- Reset evidence when the player's guild changes.
    local key = PresenceKey(sender)
    if not self.rosterPresence[key] or (version and self.rosterVersions[key] ~= version) then
        self.rosterPresence[key] = true
        if version then self.rosterVersions[key] = version end
        if OldKraken.Fire then OldKraken:Fire('ROSTER_ADDON_CHANGED') end
    end
end

function Communication:OnAddonMessage(prefix, message, channel, sender)
    if not IsOurMessagePrefix(prefix) or channel ~= "GUILD" or type(message) ~= "string" then
        return
    end

    if type(sender) ~= "string" or sender == "" or #sender > 128 then
        return
    end

    if #message > 240 then
        self.stats.invalid = self.stats.invalid + 1
        return
    end

    self:RecordRosterPresence(sender)
    if message == 'OKP^QUERY' then
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
    end

    if message:sub(1, 4) == "GF2^" then
        local kind, id, part, count, encoded = message:match("^GF2%^([A-Z]+)%^(%d+%-%d+%-%d+)%^(%d+)%^(%d+)%^([0-9A-F]*)$")
        part, count = tonumber(part), tonumber(count)
        local payload = encoded and Decode(encoded)
        if not kind or not VALID_TYPES[kind] or #id > 32 or not part or not count
            or count < 1 or count > MAX_PARTS or part < 1 or part > count
            or not payload or #payload > PART_BYTES
            or (part < count and #payload ~= PART_BYTES) then
            self.stats.invalid = self.stats.invalid + 1
            return
        end
        local now = GetTime()
        Prune(now)
        local key = sender .. "\001" .. id
        if completed[key] then return end
        local item = assemblies[key]
        if not item then
            if Count(assemblies) >= MAX_ASSEMBLIES then self.stats.invalid = self.stats.invalid + 1; return end
            item = { kind = kind, count = count, time = now, parts = {}, received = 0 }
            assemblies[key] = item
        elseif item.kind ~= kind or item.count ~= count then
            assemblies[key] = nil
            self.stats.invalid = self.stats.invalid + 1
            return
        end
        if item.parts[part] then
            if item.parts[part] ~= payload then assemblies[key] = nil; self.stats.invalid = self.stats.invalid + 1 end
            return
        end
        item.parts[part] = payload
        item.received = item.received + 1
        if item.received ~= count then return end
        assemblies[key] = nil
        if Count(completed) >= CACHE_LIMIT then
            local oldestKey, oldestTime
            for k, v in pairs(completed) do if not oldestTime or v < oldestTime then oldestKey, oldestTime = k, v end end
            completed[oldestKey] = nil
        end
        payload = table.concat(item.parts)
        local handler = self.handlers[kind]
        if handler then
            local ok, err = pcall(handler, sender, id, payload)
            if not ok then
                self.stats.invalid = self.stats.invalid + 1
                Print("Помилка обробника протоколу: " .. tostring(err))
                return
            end
        end
        completed[key] = now
        self.stats.received = self.stats.received + 1
        return
    end

    local kind, id, target, origin = strsplit("^", message)
    local me = PlayerName()
    if not me then
        return
    end

    if kind == "TEST" then
        Print("Отримано TEST від " .. sender .. ". Надсилаю ACK у GUILD.")
        self:QueueMessage(table.concat({ "ACK", id or "", target or "", me }, "^"))
    elseif kind == "ACK" and target == me and id == self.lastTestID then
        Print("Отримано ACK від " .. sender .. ". Двосторонній обмін працює.")
    end
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
        Print("Використання: /okr comm status або /okr comm test")
    end

    return true
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_ADDON")

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        local chatInfo = C_ChatInfo
        if not chatInfo or type(chatInfo.RegisterAddonMessagePrefix) ~= "function" then
            Print("RegisterAddonMessagePrefix недоступний у цьому клієнті.")
            return
        end

        local ok, registered = pcall(chatInfo.RegisterAddonMessagePrefix, Communication.PREFIX)
        Communication.ready = ok and registered ~= false
        if Communication.ready then
            Print("Префікс OLDKRKN зареєстровано.")
            Communication:RequestRosterPresence()
        else
            Print("Не вдалося зареєструвати префікс OLDKRKN: " .. tostring(registered))
        end

        if C_Timer and C_Timer.NewTicker then
            Communication.retryAt=GetTime()+math.random()*3
            Communication.pumpTicker = C_Timer.NewTicker(0.7, function()
                Communication:Pump()
            end)
        end
    elseif event == "CHAT_MSG_ADDON" then
        Communication:OnAddonMessage(...)
    end
end)
