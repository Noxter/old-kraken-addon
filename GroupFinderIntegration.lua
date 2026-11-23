local T = OldKraken.Translate or function(text) return text end
local function chatInfo(msg)
    if OldKraken.Print then OldKraken:Print(msg) else print('|cff2ec4b6Old Kraken|r: ' .. tostring(msg or ''):gsub('^|c%x%x%x%x%x%x%x%xOld Kraken|r:%s*', ''):gsub('^Old Kraken:%s*', '')) end
end
local function chatError(msg)
    if OldKraken.PrintError then OldKraken:PrintError(msg) else print('|cffff5555Old Kraken|r: ' .. tostring(msg or ''):gsub('^|c%x%x%x%x%x%x%x%xOld Kraken|r:%s*', ''):gsub('^Old Kraken:%s*', '')) end
end
-- Experimental integration; requires validation against the target client.
local finder = OldKraken.GroupFinder
local comm = OldKraken.Communication
local active, storage, nextQuery, nextBroadcast, nextRetry, lastQuery = false, nil, 0, 0, 0, -60
local currentKey, tickerStarted = nil, false
local partyDirty = true
local nextPartyCheck = 0
local soloSince = nil
local diagnostics = { received = 0, accepted = 0, rejected = 0 }
local REANNOUNCE_DELAY = 300

local function validRealm(realm)
    if OldKraken.Database and type(OldKraken.Database.IsValidRealm) == 'function' then
        return OldKraken.Database:IsValidRealm(realm)
    end
    if type(issecretvalue) == 'function' and issecretvalue(realm) then return false end
    return type(realm) == 'string' and #realm >= 1 and #realm <= 128 and not realm:find('[%z\1-\31\127]')
end

local function profileKey(name, guild)
    if type(name) ~= 'string' or name == '' or type(guild) ~= 'string' or guild == '' then return nil end
    local realm = type(GetRealmName) == 'function' and GetRealmName() or nil
    if not validRealm(realm) then return nil end
    return realm .. '\001' .. guild .. '\001' .. name
end

-- The Forever client returns given name and surname from UnitName; GUILD
-- sender carries both separated by a space. Preserve the entire server sender.
local function normalizeSender(sender)
    if type(sender) ~= 'string' or sender == '' or #sender > 128 then return nil end
    return sender
end

local function playerIdentity()
    if type(UnitName) ~= 'function' then return nil end
    local name, surname = UnitName('player')
    if type(name) ~= 'string' or name == '' then return nil end
    if type(surname) == 'string' and surname ~= '' then return name .. ' ' .. surname, name end
    return name, name
end

local function deactivate()
    if active then comm:ClearProtocolState() end
    finder.onPersist = nil
    active, finder.active, storage, currentKey = false, false, nil, nil
    partyDirty = true
    nextPartyCheck = 0
    soloSince = nil
end

local function saveOwned()
    if not storage then return end
    storage.lastActivity = {}
    for id, ts in pairs(finder.lastActivity or {}) do
        local group = finder.groups[finder.identity .. '\001' .. id]
        if group and not group.closed and not group.hidden and type(ts) == 'number'
            and ts == ts and ts % 1 == 0 and ts > 0 then
            storage.lastActivity[id] = ts
        end
    end
    local records = {}
    local compactGroupData = {}
    for _, group in pairs(finder.groups) do
        if group.owner == finder.identity then
            local payload = finder:EncodeGroup(group)
            records[#records + 1] = payload
            local fields = finder._unpackFields(payload, 215)
            local count = fields and tonumber(fields[9])
            if group.closed and count and (count ~= #group.members or fields[7] ~= group.description or #fields < 15 + count) then
                local members, roles = {}, {}
                for _, member in ipairs(group.members) do
                    members[#members + 1] = member
                    local role = group.memberRoles and group.memberRoles[member]
                    if role == 'tank' or role == 'healer' or role == 'dps' or role == 'flex' then roles[member] = role end
                end
                compactGroupData[group.id] = {description=group.description, members=members, memberRoles=roles}
            end
        end
    end
    storage.records = records
    storage.compactGroupData = compactGroupData
    storage.observedParty = {}
    for _, group in pairs(finder.groups) do
        if group.owner == finder.identity and group.partyObserved then
            storage.observedParty[group.id] = {}
            for name in pairs(group.partyObserved) do storage.observedParty[group.id][name] = true end
        end
    end
    storage.hiddenGroups = {}
    for _, group in pairs(finder.groups) do
        if group.owner == finder.identity and group.closed and group.hidden then storage.hiddenGroups[group.id] = true end
    end
    storage.pending = {}
    for key, value in pairs(finder.pending) do storage.pending[key] = value end
    storage.pendingVersions, storage.pendingRoles = {}, {}
    for key, value in pairs(finder.pendingVersions) do storage.pendingVersions[key] = value end
    for key, value in pairs(finder.pendingRoles) do storage.pendingRoles[key] = value end
    storage.roleCapabilities={}
    for name,available in pairs(finder.roleCapabilities or {}) do
        storage.roleCapabilities[name]={tank=available.tank==true,healer=available.healer==true,dps=available.dps==true}
    end
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
    if type(storage.lastBump) == 'table' then
        for id in pairs(storage.lastBump) do
            local group = finder.groups[finder.identity .. '\001' .. id]
            if not group or (group.closed and group.hidden) then storage.lastBump[id] = nil end
        end
    end
    storage.deletedGroups = {}
    for id, entry in pairs(finder.deletedGroups or {}) do
        if type(id) == 'string' and type(entry) == 'table' and type(entry.rev) == 'number' then
            storage.deletedGroups[id] = { rev = entry.rev, at = tonumber(entry.at) or 0 }
        end
    end
    storage.reopenFloors = {}
    for id, floors in pairs(finder.reopenFloors or {}) do
        if type(id) == 'string' and type(floors) == 'table' then
            local copy = {}
            for sender, ver in pairs(floors) do
                if type(sender) == 'string' and type(ver) == 'number' then copy[sender] = ver end
            end
            if next(copy) then storage.reopenFloors[id] = copy end
        end
    end
    storage.minRequestVersions = nil
end

function finder:GroupAlertsEnabled()
    local settings = OldKraken.DB and OldKraken.DB.settings
    return type(settings) == 'table' and settings.groupFinderNotifications ~= false
end

function finder:SetGroupAlertsEnabled(enabled)
    local settings = OldKraken.DB and OldKraken.DB.settings
    if type(settings) ~= 'table' then return false end
    settings.groupFinderNotifications = enabled and true or false
    OldKraken:Fire('GROUP_FINDER_ALERT_SETTING')
    return true
end

local function receiveGroup(kind, sender, _, payload)
    if not active then return end
    diagnostics.received = diagnostics.received + 1
    diagnostics.lastSender = sender
    local name = normalizeSender(sender)
    diagnostics.lastNormalized = name
    local fields = finder._unpackFields(payload, 215)
    local key = fields and fields[1] and fields[2] and (fields[2] .. '\001' .. fields[1]) or nil
    local isNew = key and not finder.groups[key]
    if name and finder:ReceiveGroup(name, payload) then
        diagnostics.accepted = diagnostics.accepted + 1
        saveOwned()
        OldKraken:Fire('GROUP_FINDER_CHANGED', key and finder.groups[key])
        if kind == 'ANNOUNCE' and isNew and name ~= finder.identity and finder:GroupAlertsEnabled() then
            local group = finder.groups[key]
            local created = group and tonumber(group.id:match('^(%d+)%-'))
            local age = created and (GetServerTime() - created)
            if group and not group.closed and group.revision == 1 and age and age >= 0 and age <= 60 then
                OldKraken:Fire('GROUP_FINDER_NEW', group)
            end
        end
    else
        diagnostics.rejected = diagnostics.rejected + 1
    end
end

for _, kind in ipairs({'ANNOUNCE', 'UPDATE', 'SYNC', 'CANCEL'}) do
    local messageKind = kind
    comm:RegisterHandler(kind, function(sender, id, payload) receiveGroup(messageKind, sender, id, payload) end)
end
comm:RegisterHandler('BUMP', function(sender, _, payload)
    if not active then return end
    local name = normalizeSender(sender)
    local fields = finder._unpackFields(payload, 215)
    if not name or not fields or not fields[1] or fields[2] ~= name or name == finder.identity then return end
    local key = name .. '\001' .. fields[1]
    local existing = finder.groups[key]
    local current = existing and (existing._receivedPayload == payload or finder:EncodeGroup(existing) == payload)
    if current then existing.seenAt = GetTime() end
    if not current then
        if not finder:ReceiveGroup(name, payload) then return end
        saveOwned()
        OldKraken:Fire('GROUP_FINDER_CHANGED', finder.groups[key])
    end
    local group = finder.groups[key]
    if group and not group.closed and finder:GroupAlertsEnabled() then OldKraken:Fire('GROUP_FINDER_NEW', group) end
end)

function finder:GetReannounceRemaining(id)
    local group = active and self.groups[self.identity .. '\001' .. id]
    if not group or group.closed or group.hidden then return nil end
    local now = GetServerTime()
    if type(storage.lastBump) ~= 'table' then storage.lastBump = {} end
    local function validTimestamp(value)
        return type(value) == 'number' and value == value and value % 1 == 0 and value > 0 and value <= now + 600
    end
    local created = tonumber(id:match('^(%d+)%-'))
    if not validTimestamp(created) then created = now - REANNOUNCE_DELAY end
    local previous = tonumber(storage.lastBump[id])
    if not validTimestamp(previous) then
        storage.lastBump[id] = nil
        previous = created
    end
    return math.max(0, math.ceil(previous + REANNOUNCE_DELAY - now))
end

function finder:Reannounce(id)
    local left = self:GetReannounceRemaining(id)
    if left == nil then return false, 'group' end
    if left > 0 then return false, 'cooldown', math.ceil(left) end
    local group = self.groups[self.identity .. '\001' .. id]
    if not comm:SendProtocol('BUMP', self:EncodeGroup(group)) then return false, 'queue' end
    storage.lastBump[id] = GetServerTime()
    finder.lastActivity[id] = storage.lastBump[id]
    saveOwned()
    return true
end
comm:RegisterHandler('JOIN', function(sender, _, payload)
    local name = active and normalizeSender(sender)
    if not name then return end
    local updated, isNew, id, role = finder:ReceiveJoin(name, payload)
    if updated then
        saveOwned()
        OldKraken:Fire('GROUP_FINDER_CHANGED')
        if isNew then
            local group = finder.groups[finder.identity .. '\001' .. id]
            if group then
                OldKraken:Fire('GROUP_FINDER_NEW_REQUEST', group, name, role)
            end
        end
    end
end)
comm:RegisterHandler('RESPONSE', function(sender, _, payload)
    local name = active and normalizeSender(sender)
    if name and finder:ReceiveResponse(name, payload) then
        local fields = finder._unpackFields(payload, 5)
        local key = fields and fields[1] and fields[2] and (fields[1] .. '\001' .. fields[2])
        saveOwned()
        OldKraken:Fire('GROUP_FINDER_CHANGED')
        local group = key and finder.groups[key]
        if group then OldKraken:Fire('GROUP_FINDER_APPLICATION_STATUS', group, 'reject') end
    end
end)
comm:RegisterHandler('QUERY', function(_, _, payload)
    if active and payload == '' and GetTime() - lastQuery >= 20 then
        lastQuery = GetTime()
        finder:OnQuery()
    end
end)

function finder:Changed()
    partyDirty = true
    saveOwned()
    OldKraken:Fire('GROUP_FINDER_CHANGED')
end

local ROLE_MAP = {TANK = 'tank', HEALER = 'healer', DAMAGER = 'dps'}

local function readAssignedRole(unit)
    if type(UnitGroupRolesAssigned) ~= 'function' then return nil end
    local ok, assigned = pcall(UnitGroupRolesAssigned, unit)
    return ok and ROLE_MAP[assigned] or nil
end

local function readParty()
    if type(IsInGroup) ~= 'function' or type(IsInRaid) ~= 'function'
        or type(GetNumGroupMembers) ~= 'function' or type(UnitName) ~= 'function' then return nil end
    local ok, result, isGrouped, partyRoles = pcall(function()
        local function plain(value)
            if type(issecretvalue) == 'function' and issecretvalue(value) then error('unavailable group data') end
            return value
        end
        local raid, grouped = plain(IsInRaid()), plain(IsInGroup())
        if raid ~= nil and raid ~= true and raid ~= false and raid ~= 1 then return nil end
        if grouped ~= nil and grouped ~= true and grouped ~= false and grouped ~= 1 then return nil end
        if raid and not grouped then return nil end
        local roles = {}
        local playerRole = readAssignedRole('player')
        if playerRole and finder.identity then roles[finder.identity] = playerRole end
        if not grouped then return {}, false, roles end
        local count = plain(GetNumGroupMembers())
        if type(count) ~= 'number' or count % 1 ~= 0 or count < 1 or count > (raid and 40 or 5)
            or (not raid and count < 2) then return nil end
        local names, seen, foundPlayer = {}, {}, not raid
        local limit = raid and count or count - 1
        for i = 1, limit do
            local unit = (raid and 'raid' or 'party') .. i
            local name, surname = UnitName(unit)
            name, surname = plain(name), plain(surname)
            if type(name) ~= 'string' or name == '' then return nil end
            if finder.identity:find(' ', 1, true) and (type(surname) ~= 'string' or surname == '') then return nil end
            local fullName = type(surname) == 'string' and surname ~= '' and (name .. ' ' .. surname) or name
            if seen[fullName] then return nil end
            seen[fullName] = true
            local unitRole = readAssignedRole(unit)
            if unitRole then roles[fullName] = unitRole end
            if raid and fullName == finder.identity then foundPlayer = true
            else names[#names + 1] = fullName end
        end
        if not foundPlayer then return nil end
        return names, true, roles
    end)
    if ok then return result, isGrouped, partyRoles end
    return nil
end

local function reconcileParty(additionsOnly)
    local party, isGrouped, partyRoles = readParty()
    if not party then soloSince = nil; diagnostics.partySyncError = 'unavailable'; return end
    if isGrouped then soloSince = nil end
    if additionsOnly then
        if #party == 0 then return end
        local current = {}; for _, name in ipairs(party) do current[name] = true end
        for _, group in pairs(finder.groups) do
            if group.owner == finder.identity and not group.closed then
                for name in pairs(group.partyObserved or {}) do if not current[name] then return end end
            end
        end
    end
    if isGrouped == false and not additionsOnly then
        local wasGrouped = false
        for _, group in pairs(finder.groups) do
            if group.owner == finder.identity and not group.closed and group.partyObserved and next(group.partyObserved) then wasGrouped = true; break end
        end
        if wasGrouped then
            if not soloSince then soloSince = GetTime() end
            if GetTime() - soloSince < 3 then partyDirty = true; return end
        end
        local complete, changed = finder:DeleteDisbandedGroups()
        if changed then saveOwned(); OldKraken:Fire('GROUP_FINDER_CHANGED') end
        if not complete then partyDirty = true; return end
    end
    local complete, changed, reason = finder:SyncPartyMembers(party, partyRoles)
    partyDirty = not complete
    if reason == 'payload' and diagnostics.partySyncError ~= 'payload' then
        chatError(T('|cffff5555Old Kraken|r: Склад не синхронізовано: оголошення перевищує 2560 байтів. Скоротіть назву або опис.'))
    end
    diagnostics.partySyncError = reason
    if changed then saveOwned(); OldKraken:Fire('GROUP_FINDER_CHANGED') end
end

function finder:SyncPartyNow()
    if not active then return end
    reconcileParty(true)
end

function finder:PrintSyncStatus()
    local total = 0
    for _ in pairs(self.groups or {}) do total = total + 1 end
    local realm = GetRealmName and GetRealmName() or T('невідомо')
    chatInfo('|cff2ec4b6Old Kraken|r: Group Finder: ' .. (active and T('активний') or T('не ініціалізований')) ..
        T('; гравець: ') .. tostring(self.identity or '-') .. '; realm: ' .. tostring(realm) .. T('; груп: ') .. total)
    chatInfo(T('|cff2ec4b6Old Kraken|r: отримано оголошень: ') .. diagnostics.received ..
        T('; додано/оновлено: ') .. diagnostics.accepted .. T('; не додано (включно з повторами): ') .. diagnostics.rejected)
    chatInfo(T('|cff2ec4b6Old Kraken|r: останній sender: ') .. tostring(diagnostics.lastSender or '-') ..
        T('; після перевірки: ') .. tostring(diagnostics.lastNormalized or T('не визначено')))
    if diagnostics.partySyncError == 'payload' then
        chatError(T('|cffff5555Old Kraken|r: Склад не синхронізовано: оголошення перевищує 2560 байтів. Скоротіть назву або опис.'))
    elseif diagnostics.partySyncError == 'unavailable' then
        chatError(T('|cffff5555Old Kraken|r: Гра не повернула повний склад паті або рейду; аддон повторить перевірку.'))
    end
end

function finder:RequestSyncNow()
    if not active then chatError(T('|cffff5555Old Kraken|r: Group Finder не ініціалізований.')); return false end
    if C_GuildInfo and type(C_GuildInfo.GuildRoster) == 'function' then pcall(C_GuildInfo.GuildRoster) end
    if not comm:RequestSync() then chatError(T('|cffff5555Old Kraken|r: не вдалося додати запит синхронізації до черги.')); return false end
    self:OnQuery()
    chatInfo(T('|cff2ec4b6Old Kraken|r: запит синхронізації додано до черги.'))
    return true
end

local frame = CreateFrame('Frame')
frame:RegisterEvent('PLAYER_LOGIN')
frame:RegisterEvent('PLAYER_ENTERING_WORLD')
pcall(frame.RegisterEvent, frame, 'PLAYER_GUILD_UPDATE')
frame:RegisterEvent('GUILD_ROSTER_UPDATE')
frame:RegisterEvent('GROUP_ROSTER_UPDATE')
pcall(frame.RegisterEvent, frame, 'PLAYER_ROLES_ASSIGNED')
pcall(frame.RegisterEvent, frame, 'ROLE_CHANGED_INFORM')

local function connect()
    local identity, name = playerIdentity()
    local guild = GetGuildInfo and GetGuildInfo('player')
    if type(name) ~= 'string' or name == '' or type(guild) ~= 'string' or guild == ''
        or not OldKraken.DB or type(OldKraken.DB.groupFinder) ~= 'table' then
        deactivate()
        return false
    end
    -- Sender identity representation must be verified on the target realm.
    local key = profileKey(name, guild)
    if not key then
        deactivate()
        return false
    end
    if active and currentKey == key then return true end
    deactivate()
    storage = OldKraken.DB.groupFinder[key]
    if type(storage) ~= 'table' then storage = {}; OldKraken.DB.groupFinder[key] = storage end
    finder:Initialize(identity, function(kind, payload) return comm:SendProtocol(kind, payload) end)
    for name,available in pairs(type(storage.roleCapabilities)=='table' and storage.roleCapabilities or {}) do
        if type(name)=='string' and type(available)=='table' and type(available.tank)=='boolean' and type(available.healer)=='boolean' and type(available.dps)=='boolean' then
            finder.roleCapabilities[name]={tank=available.tank,healer=available.healer,dps=available.dps}
        end
    end
    -- Short-name requests and decisions cannot identify a unique character.
    if identity ~= name and storage.identityFormat ~= 2 then
        local migrated = {}
        for _, record in ipairs(type(storage.records) == 'table' and storage.records or {}) do
            local fields = finder._unpackFields(record, 215)
            if fields and fields[2] == name and fields[13] == name then
                fields[2], fields[13] = identity, identity
                local cleaned, members = {}, 1
                for i = 1, 13 do cleaned[i] = fields[i] end
                for i = 14, #fields do
                    -- Short-name members are ambiguous; only retain full names.
                    if fields[i]:find(' ', 1, true) then
                        members = members + 1
                        cleaned[12 + members] = fields[i]
                    end
                end
                cleaned[9] = tostring(members)
                local revision = tonumber(cleaned[3])
                if revision and revision < 2147483647 then
                    cleaned[3] = tostring(revision + 1)
                    migrated[#migrated + 1] = finder._pack(cleaned)
                end
            end
        end
        storage.records, storage.pending, storage.pendingVersions, storage.pendingRoles = migrated, {}, {}, {}
        storage.requests, storage.requestVersions, storage.decisions = {}, {}, {}
        storage.legacyShortNames = nil
        storage.identityFormat = 2
    end
    local hiddenMap = {}
    if type(storage.hiddenGroups) == 'table' then
        for id, hidden in pairs(storage.hiddenGroups) do
            if type(id) == 'string' and hidden == true then hiddenMap[id] = true end
        end
    end
    if type(storage.records) == 'table' then
        local loaded = 0
        for _, record in ipairs(storage.records) do
            if loaded >= 200 then break end
            local fields = type(record) == 'string' and finder._unpackFields(record, 215) or nil
            local isHidden = fields and fields[1] and hiddenMap[fields[1]] == true or false
            if finder:ReceiveGroup(identity, record, isHidden) then loaded = loaded + 1 end
        end
    end
    if type(storage.hiddenGroups) == 'table' then
        for id, hidden in pairs(storage.hiddenGroups) do
            local group = type(id) == 'string' and finder.groups[identity .. '\001' .. id]
            if group and group.closed and hidden == true then group.hidden = true end
        end
    end
    if type(storage.compactGroupData) == 'table' then
        local function validText(value, min, max)
            return type(value) == 'string' and #value >= min and #value <= max and not value:find('[%z\1-\31\127]')
        end
        for _, group in pairs(finder.groups) do
            local backup = storage.compactGroupData[group.id]
            if group.owner == identity and group.closed and type(backup) == 'table'
                and validText(backup.description, 0, 500) and type(backup.members) == 'table'
                and backup.description:sub(1, #group.description) == group.description
                and #backup.members >= #group.members and #backup.members <= group.maxSize and backup.members[1] == identity then
                local members, seen, valid = {}, {}, true
                for _, member in ipairs(backup.members) do
                    if not validText(member, 1, 128) or seen[member] then valid = false; break end
                    members[#members + 1] = member
                    seen[member] = true
                end
                for i, member in ipairs(group.members) do
                    if members[i] ~= member then valid = false; break end
                end
                if valid and #members == #backup.members then
                    local roles = {}
                    local savedRoles = type(backup.memberRoles) == 'table' and backup.memberRoles or {}
                    for _, member in ipairs(members) do
                        local role = savedRoles[member]
                        if role == 'tank' or role == 'healer' or role == 'dps' or role == 'flex' then roles[member] = role end
                    end
                    roles[identity] = group.role
                    group.description, group.members, group.memberRoles = backup.description, members, roles
                end
            end
        end
    end
    if type(storage.deletedGroups) == 'table' then
        local count = 0
        for id, entry in pairs(storage.deletedGroups) do
            if count >= 500 then break end
            if type(id) == 'string' and #id <= 64 and type(entry) == 'table'
                and type(entry.rev) == 'number' and entry.rev >= 1 and entry.rev % 1 == 0 then
                finder.deletedGroups[id] = { rev = entry.rev, at = tonumber(entry.at) or 0 }
                count = count + 1
            end
        end
    end
    if type(storage.reopenFloors) == 'table' then
        local total = 0
        for id, floors in pairs(storage.reopenFloors) do
            if type(id) == 'string' and #id <= 64 and type(floors) == 'table' then
                local copy = {}
                for sender, ver in pairs(floors) do
                    if total >= 2000 then break end
                    if type(sender) == 'string' and #sender <= 128 and type(ver) == 'number'
                        and ver > 0 and ver < 9000000000000000 then
                        copy[sender] = ver
                        total = total + 1
                    end
                end
                if next(copy) then finder.reopenFloors[id] = copy end
            end
        end
    end
    if type(storage.observedParty) == 'table' then
        for id, observed in pairs(storage.observedParty) do
            local group = type(id) == 'string' and finder.groups[identity .. '\001' .. id]
            if group and type(observed) == 'table' then
                group.partyObserved = {}
                for _, member in ipairs(group.members) do
                    if member ~= identity and observed[member] == true then group.partyObserved[member] = true end
                end
            end
        end
    end
    if type(storage.pending) == 'table' then
        local count = 0
        for entry, value in pairs(storage.pending) do
            if count >= 100 then break end
            if type(entry) == 'string' and #entry <= 193 and
                (value == 'pending' or value == 'reject' or value == 'closed' or value == 'retry') then
                finder.pending[entry] = value; count = count + 1
            end
        end
    end
    if type(storage.pendingVersions) == 'table' and type(storage.pendingRoles) == 'table' then
        for entry, version in pairs(storage.pendingVersions) do
            local role = storage.pendingRoles[entry]
            if finder.pending[entry] == 'pending' and type(version) == 'number' and version > 0 and version < 9000000000000000
                and (role == 'tank' or role == 'healer' or role == 'dps' or role == 'flex') then
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
            if type(id) == 'string' and finder.groups[identity .. '\001' .. id] and type(requests) == 'table' then
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
            if type(id) == 'string' and finder.groups[identity .. '\001' .. id] and type(decisions) == 'table' then
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
    -- Restore activity only after every profile table has been loaded.
    local serverNow = GetServerTime()
    local function validActivity(ts)
        return type(ts) == 'number' and ts == ts and ts % 1 == 0 and ts > 0 and ts <= serverNow + 600
    end
    local savedActivity = type(storage.lastActivity) == 'table' and storage.lastActivity or {}
    local savedBumps = type(storage.lastBump) == 'table' and storage.lastBump or {}
    for _, group in pairs(finder.groups) do
        if group.owner == identity and not group.closed and not group.hidden then
            local ts = tonumber(savedActivity[group.id])
            if not validActivity(ts) then
                local bump = tonumber(savedBumps[group.id])
                local created = tonumber(group.id:match('^(%d+)%-'))
                if validActivity(bump) and validActivity(created) then ts = math.max(bump, created)
                elseif validActivity(bump) then ts = bump
                elseif validActivity(created) then ts = created
                else ts = serverNow end
            end
            if serverNow - ts >= finder.IDLE_GROUP_TTL then
                group.closed = true
                -- At the protocol limit the local closure is retained, but peers
                -- holding the same revision cannot accept a newer snapshot.
                if group.revision < 2147483647 then group.revision = group.revision + 1
                else chatError(T('Old Kraken: досягнуто межі ревізії групи; створіть новий набір.')) end
                comm:SendProtocol('CANCEL', finder:EncodeGroup(group))
            else finder.lastActivity[group.id] = ts end
        end
    end
    finder.onPersist = saveOwned
    saveOwned()
    active = true
    partyDirty = true
    finder.active = true
    currentKey = key
    nextQuery, nextBroadcast, nextRetry, lastQuery = 0, 0, 0, -60
    if C_GuildInfo and type(C_GuildInfo.GuildRoster) == 'function' then pcall(C_GuildInfo.GuildRoster) end
    if not tickerStarted and C_Timer and C_Timer.NewTicker then
        tickerStarted = true
        C_Timer.NewTicker(3, function()
            if not active then return end
            local currentGuild = GetGuildInfo and GetGuildInfo('player')
            local currentName = UnitName and UnitName('player')
            local nextKey = profileKey(currentName, currentGuild)
            if not nextKey or nextKey ~= currentKey then
                deactivate()
                return
            end
            local now = GetTime()
            local serverNow = GetServerTime()
            local activityChanged = false
            for _, group in pairs(finder.groups) do
                if group.owner == finder.identity and not group.closed and not group.hidden then
                    local ts = finder.lastActivity[group.id]
                    if type(ts) ~= 'number' or ts ~= ts or ts % 1 ~= 0 or ts <= 0 or ts > serverNow + 600 then
                        finder.lastActivity[group.id] = serverNow
                        activityChanged = true
                    elseif serverNow - ts >= finder.IDLE_GROUP_TTL then
                        if group.revision >= 2147483647 then
                            group.closed = true
                            finder.lastActivity[group.id] = nil
                            activityChanged = true
                            OldKraken:Fire('GROUP_FINDER_CHANGED')
                            chatError(T('Old Kraken: досягнуто межі ревізії групи; створіть новий набір.'))
                        elseif finder:Cancel(group.id) then
                            OldKraken:Fire('GROUP_FINDER_CHANGED')
                            local title = group.title or group.id
                            local catalog = OldKraken.ActivityCatalog
                            if catalog and catalog.IsCanonicalTitle and catalog.IsCanonicalTitle(group.dungeon, title) then
                                for _, list in ipairs({catalog.dungeon or {}, catalog.raid or {}, (catalog.legacy and catalog.legacy.dungeon) or {}}) do
                                    for _, entry in ipairs(list) do
                                        if entry.value == group.dungeon then title = entry.label; break end
                                    end
                                end
                            end
                            chatInfo(string.format(T('|cff2ec4b6Old Kraken|r: набір «%s» автоматично закрито через 60 хв без активності.'), title))
                        end
                    end
                end
            end
            if activityChanged then saveOwned() end
            -- Some clients can miss a roster event or deliver it before the
            -- roster is complete. Reconcile periodically even after success.
            if partyDirty or now >= nextPartyCheck then
                nextPartyCheck = now + 3
                reconcileParty(false)
            end
            if now >= nextQuery and comm:RequestSync() then nextQuery = now + 180 end
            if now >= nextBroadcast then finder:OnQuery(); nextBroadcast = now + 300 end
            if now >= nextRetry and finder:RetryPending() then nextRetry = now + 180 end

            finder:SyncStep()
            if finder:Prune() then saveOwned() end
        end)
    end
    return true
end

function finder:Connect()
    return connect()
end

frame:SetScript('OnEvent', function(_, event)
    if event == 'GROUP_ROSTER_UPDATE' or event == 'PLAYER_ROLES_ASSIGNED' or event == 'ROLE_CHANGED_INFORM' then
        partyDirty = true
        -- Capture a confirmed join or role update; defer removals until the
        -- next tick so transient, incomplete roster updates cannot disband it.
        if active then reconcileParty(event == 'GROUP_ROSTER_UPDATE') end
        return
    end
    connect()
end)

if type(OldKraken.On) == 'function' then
    OldKraken:On('INITIALIZED', function() connect() end)
end
