-- Experimental integration; requires validation against the target client.
local finder = OldKraken.GroupFinder
local comm = OldKraken.Communication
local active, storage, nextQuery, nextBroadcast, nextRetry, lastQuery = false, nil, 0, 0, 0, -60
local currentKey, tickerStarted = nil, false

local function profileKey(name, guild)
    local realm = GetRealmName and GetRealmName() or ''
    if type(realm) ~= 'string' then realm = '' end
    return realm .. '\001' .. guild .. '\001' .. name
end

-- CHAT_MSG_ADDON sender may include the local realm ("Name Realm" or
-- "Name-Realm"), while UnitName("player") and group owners use "Name".
-- Only strip a suffix that exactly matches this client's realm.
local function normalizeSender(sender)
    if type(sender) ~= 'string' or sender == '' or #sender > 128 then return nil end
    if sender == finder.identity then return sender end
    -- Some client builds provide only the character name.
    if not sender:find('[ %-]') then return sender end
    local realm = GetRealmName and GetRealmName() or ''
    if type(realm) ~= 'string' or realm == '' then return nil end
    for _, separator in ipairs({' ', '-'}) do
        local suffix = separator .. realm
        if #sender > #suffix and sender:sub(-#suffix) == suffix then
            local name = sender:sub(1, #sender - #suffix)
            if name ~= '' then return name end
        end
    end
    return nil
end

local function deactivate()
    if active then comm:ClearProtocolState() end
    active, finder.active, storage, currentKey = false, false, nil, nil
end

local function saveOwned()
    if not storage then return end
    local records = {}
    for _, group in pairs(finder.groups) do
        if group.owner == finder.identity then records[#records + 1] = finder:EncodeGroup(group) end
    end
    storage.records = records
    storage.pending = {}
    for key, value in pairs(finder.pending) do storage.pending[key] = value end
    storage.pendingVersions, storage.pendingRoles = {}, {}
    for key, value in pairs(finder.pendingVersions) do storage.pendingVersions[key] = value end
    for key, value in pairs(finder.pendingRoles) do storage.pendingRoles[key] = value end
    storage.requests = {}
    for id, requests in pairs(finder.requests) do
        local owned = finder.groups[finder.identity .. '\001' .. id]
        if owned then
            storage.requests[id] = {}
            for name, role in pairs(requests) do storage.requests[id][name] = role end
        end
    end
    storage.requestVersions = {}
    for key, value in pairs(finder.requestVersions) do storage.requestVersions[key] = value end
    storage.requestSequence = finder.requestSequence
    storage.decisions = {}
    for id, decisions in pairs(finder.decisions) do
        if finder.groups[finder.identity .. '\001' .. id] then
            storage.decisions[id] = {}
            for applicant, version in pairs(decisions) do storage.decisions[id][applicant] = version end
        end
    end
end

local function receiveGroup(sender, _, payload)
    if not active then return end
    local name = normalizeSender(sender)
    if name and finder:ReceiveGroup(name, payload) then
        saveOwned()
        OldKraken:Fire('GROUP_FINDER_CHANGED')
    end
end

for _, kind in ipairs({'ANNOUNCE', 'UPDATE', 'SYNC', 'CANCEL'}) do
    comm:RegisterHandler(kind, receiveGroup)
end
comm:RegisterHandler('JOIN', function(sender, _, payload)
    local name = active and normalizeSender(sender)
    if name and finder:ReceiveJoin(name, payload) then
        saveOwned()
        OldKraken:Fire('GROUP_FINDER_CHANGED')
    end
end)
comm:RegisterHandler('RESPONSE', function(sender, _, payload)
    local name = active and normalizeSender(sender)
    if name and finder:ReceiveResponse(name, payload) then
        saveOwned()
        OldKraken:Fire('GROUP_FINDER_CHANGED')
    end
end)
comm:RegisterHandler('QUERY', function(_, _, payload)
    if active and payload == '' and GetTime() - lastQuery >= 20 then
        lastQuery = GetTime()
        finder:OnQuery()
    end
end)

function finder:Changed()
    saveOwned()
    OldKraken:Fire('GROUP_FINDER_CHANGED')
end

local frame = CreateFrame('Frame')
frame:RegisterEvent('PLAYER_LOGIN')
frame:RegisterEvent('GUILD_ROSTER_UPDATE')
frame:SetScript('OnEvent', function()
    local name = UnitName and UnitName('player')
    local guild = GetGuildInfo and GetGuildInfo('player')
    if type(name) ~= 'string' or name == '' or type(guild) ~= 'string' or guild == ''
        or not OldKraken.DB or type(OldKraken.DB.groupFinder) ~= 'table' then
        deactivate()
        return
    end
    -- Sender identity representation must be verified on the target realm.
    local key = profileKey(name, guild)
    if active and currentKey == key then return end
    deactivate()
    storage = OldKraken.DB.groupFinder[key]
    if type(storage) ~= 'table' then storage = {}; OldKraken.DB.groupFinder[key] = storage end
    finder:Initialize(name, function(kind, payload) return comm:SendProtocol(kind, payload) end)
    if type(storage.records) == 'table' then
        for _, record in ipairs(storage.records) do finder:ReceiveGroup(name, record) end
    end
    if type(storage.pending) == 'table' then
        local count = 0
        for entry, value in pairs(storage.pending) do
            if count >= 100 then break end
            if type(entry) == 'string' and #entry <= 193 and
                (value == 'pending' or value == 'accept' or value == 'reject' or value == 'closed' or value == 'retry') then
                finder.pending[entry] = value; count = count + 1
            end
        end
    end
    if type(storage.pendingVersions) == 'table' and type(storage.pendingRoles) == 'table' then
        for entry, version in pairs(storage.pendingVersions) do
            local role = storage.pendingRoles[entry]
            if finder.pending[entry] == 'pending' and type(version) == 'number' and version > 0 and version < 9000000000000000
                and (role == '' or role == 'tank' or role == 'healer' or role == 'dps' or role == 'flex') then
                finder.pendingVersions[entry], finder.pendingRoles[entry] = version, role
            end
        end
    end
    -- Pre-versioned pending requests cannot be correlated safely with a decision.
    for entry, value in pairs(finder.pending) do
        if value == 'pending' and not finder.pendingVersions[entry] then finder.pending[entry] = 'retry' end
    end
    if type(storage.requests) == 'table' then
        for id, requests in pairs(storage.requests) do
            if type(id) == 'string' and finder.groups[name .. '\001' .. id] and type(requests) == 'table' then
                finder.requests[id] = {}
                local count = 0
                for applicant, role in pairs(requests) do
                    if count >= 200 then break end
                    if type(applicant) == 'string' and #applicant > 0 and #applicant <= 128 and
                        (role == '' or role == 'tank' or role == 'healer' or role == 'dps' or role == 'flex') then
                        finder.requests[id][applicant] = role; count = count + 1
                    end
                end
            end
        end
    end
    if type(storage.requestVersions) == 'table' then
        local count = 0
        for entry, value in pairs(storage.requestVersions) do
            if count >= 2000 then break end
            if type(entry) == 'string' and #entry <= 193 and type(value) == 'number' and value > 0 and value < 9000000000000000 then
                finder.requestVersions[entry] = value; count = count + 1
            end
        end
    end
    if type(storage.requestSequence) == 'number' and storage.requestSequence > finder.requestSequence
        and storage.requestSequence < 9000000000000000 then finder.requestSequence = storage.requestSequence end
    if type(storage.decisions) == 'table' then
        local count = 0
        for id, decisions in pairs(storage.decisions) do
            if type(id) == 'string' and finder.groups[name .. '\001' .. id] and type(decisions) == 'table' then
                for applicant, version in pairs(decisions) do
                    if count >= 2000 then break end
                    if type(applicant) == 'string' and #applicant > 0 and #applicant <= 128
                        and type(version) == 'number' and version > 0 and version < 9000000000000000 then
                        finder.decisions[id] = finder.decisions[id] or {}
                        finder.decisions[id][applicant] = version
                        count = count + 1
                    end
                end
            end
        end
    end
    active = true
    finder.active = true
    currentKey = key
    nextQuery, nextBroadcast, nextRetry, lastQuery = 0, 0, 0, -60
    if not tickerStarted and C_Timer and C_Timer.NewTicker then
        tickerStarted = true
        C_Timer.NewTicker(3, function()
            if not active then return end
            local currentGuild = GetGuildInfo and GetGuildInfo('player')
            local currentName = UnitName and UnitName('player')
            if not currentGuild or not currentName or profileKey(currentName, currentGuild) ~= currentKey then
                deactivate()
                return
            end
            local now = GetTime()
            if now >= nextQuery and comm:RequestSync() then nextQuery = now + 180 end
            if now >= nextBroadcast then finder:OnQuery(); nextBroadcast = now + 300 end
            if now >= nextRetry and finder:RetryPending() then nextRetry = now + 180 end
            finder:SyncStep()
            finder:Prune()
        end)
    end
end)
