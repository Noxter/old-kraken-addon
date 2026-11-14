OldKraken = OldKraken or {}

local Communication = {}
OldKraken.Communication = Communication

Communication.PREFIX = "OLDKRKN"
Communication.queue = {}
Communication.ready = false
Communication.lastTestID = nil
Communication.handlers = {}
Communication.stats = { sent = 0, retried = 0, dropped = 0, received = 0, invalid = 0 }
local MAX_ATTEMPTS = 5
local MAX_QUEUE = 50
local PART_BYTES = 80
local MAX_PARTS = 32
local MAX_ASSEMBLIES = 20
local CACHE_LIMIT = 256
local CACHE_TTL = 120
local messageSequence = 0
local sessionID = tostring(GetServerTime()) .. "-" .. tostring(math.random(100000, 999999))
local assemblies, completed = {}, {}

local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function Prune(now)
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
    WKPROF = true, WKQUERY = true, WRQUERY = true, WRRESULT = true, WRBATCH = true, WRLEARN = true,
    WRQ = true, WRIDX = true, WRGET = true, WRPAGE = true,
    WORDER = true, WORELAY = true, WOREQ = true, WOPAY = true, WOERROR = true, WOQUERY = true }

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
    messageSequence = (messageSequence + 1) % 1000000
    local id = sessionID .. "-" .. tostring(messageSequence)
    local count = math.max(1, math.ceil(#payload / PART_BYTES))
    if #self.queue + count > MAX_QUEUE then return false, "queue full" end
    local messages = {}
    for part = 1, count do
        local data = payload:sub((part - 1) * PART_BYTES + 1, part * PART_BYTES)
        local message = table.concat({ "GF2", kind, id, part, count, Encode(data) }, "^")
        if #message > 240 then return false, "message too long" end
        messages[part] = message
    end
    local originalCount = #self.queue
    for _, message in ipairs(messages) do
        if not self:QueueMessage(message) then
            while #self.queue > originalCount do table.remove(self.queue) end
            return false, "transport unavailable"
        end
    end
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
    Print("  Надіслано: " .. self.stats.sent .. "; повторів: " .. self.stats.retried ..
        "; відкинуто: " .. self.stats.dropped .. "; некоректних: " .. self.stats.invalid)
end

function Communication:QueueMessage(message)
    if type(message) ~= "string" or message == "" then
        return false
    end

    if #message > 240 then
        Print("Тестове повідомлення завелике, його не додано до черги.")
        return false
    end

    if #self.queue >= MAX_QUEUE then
        Print("Черга обміну переповнена; повідомлення не додано.")
        return false
    end

    local guild
    if message:sub(1, 4) == 'GF2^' then
        guild = GetGuildInfo and GetGuildInfo('player')
        if type(guild) ~= 'string' or guild == '' then return false end
    end
    self.queue[#self.queue + 1] = { message = message, attempts = 0, guild = guild }
    return true
end

function Communication:Pump()
    local entry = self.queue[1]
    if not entry then
        return
    end

    if not IsInGuild or not IsInGuild() then
        return
    end

    if entry.guild and (not GetGuildInfo or GetGuildInfo('player') ~= entry.guild) then
        table.remove(self.queue, 1)
        self.stats.dropped = self.stats.dropped + 1
        return
    end

    local chatInfo = C_ChatInfo
    if not chatInfo or type(chatInfo.SendAddonMessage) ~= "function" then
        table.remove(self.queue, 1)
        self.stats.dropped = self.stats.dropped + 1
        Print("SendAddonMessage недоступний; повідомлення відкинуто.")
        return
    end

    local ok, result = pcall(chatInfo.SendAddonMessage, self.PREFIX, entry.message, "GUILD")
    if not ok then
        table.remove(self.queue, 1)
        self.stats.dropped = self.stats.dropped + 1
        Print("Помилка SendAddonMessage: " .. tostring(result))
        return
    end

    local results = Enum and Enum.SendAddonMessageResult
    if results and result ~= nil and (
        (results.AddonMessageThrottle ~= nil and result == results.AddonMessageThrottle)
        or (results.ChannelThrottle ~= nil and result == results.ChannelThrottle)
        or (results.AddOnMessageLockdown ~= nil and result == results.AddOnMessageLockdown)
    ) then
        entry.attempts = entry.attempts + 1
        self.stats.retried = self.stats.retried + 1
        if entry.attempts >= MAX_ATTEMPTS then
            table.remove(self.queue, 1)
            self.stats.dropped = self.stats.dropped + 1
            Print("Повідомлення відкинуто після повторних спроб; оновіть дані.")
        end
        return
    end

    table.remove(self.queue, 1)
    -- A successful API call is not an acknowledgement of delivery.
    if results and results.Success ~= nil and result ~= nil and result ~= results.Success then
        self.stats.dropped = self.stats.dropped + 1
        Print("Повідомлення не надіслано: " .. tostring(result))
    else
        self.stats.sent = self.stats.sent + 1
    end
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
        else
            Print("Не вдалося зареєструвати префікс OLDKRKN: " .. tostring(registered))
        end

        if C_Timer and C_Timer.NewTicker then
            Communication.pumpTicker = C_Timer.NewTicker(0.7, function()
                Communication:Pump()
            end)
        end
    elseif event == "CHAT_MSG_ADDON" then
        Communication:OnAddonMessage(...)
    end
end)
