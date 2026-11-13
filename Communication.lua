OldKraken = OldKraken or {}

local Communication = {}
OldKraken.Communication = Communication

Communication.PREFIX = "OLDKRKN"
Communication.queue = {}
Communication.ready = false
Communication.lastTestID = nil

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
end

function Communication:QueueMessage(message)
    if type(message) ~= "string" or message == "" then
        return false
    end

    if #message > 240 then
        Print("Тестове повідомлення завелике, його не додано до черги.")
        return false
    end

    if #self.queue >= 50 then
        Print("Черга обміну переповнена; повідомлення не додано.")
        return false
    end

    self.queue[#self.queue + 1] = message
    return true
end

function Communication:Pump()
    local message = self.queue[1]
    if not message then
        return
    end

    if not IsInGuild or not IsInGuild() then
        return
    end

    local chatInfo = C_ChatInfo
    if not chatInfo or type(chatInfo.SendAddonMessage) ~= "function" then
        table.remove(self.queue, 1)
        Print("SendAddonMessage недоступний; повідомлення відкинуто.")
        return
    end

    local ok, result = pcall(chatInfo.SendAddonMessage, self.PREFIX, message, "GUILD")
    if not ok then
        table.remove(self.queue, 1)
        Print("Помилка SendAddonMessage: " .. tostring(result))
        return
    end

    local results = Enum and Enum.SendAddonMessageResult
    if results and (
        result == results.AddonMessageThrottle
        or result == results.ChannelThrottle
        or result == results.AddOnMessageLockdown
    ) then
        return
    end

    table.remove(self.queue, 1)
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

    if not sender or sender == "" then
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
    elseif kind == "ACK" and target == me then
        Print("Отримано ACK від " .. sender .. ". Двосторонній обмін працює.")
    end
end

function Communication:HandleCommand(command)
    local subcommand = string.match(command or "", "^comm%s*(.*)$")
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
