-- Group Finder model and owner-authoritative state.
local Finder = {}
OldKraken.GroupFinder = Finder

local function pack(fields)
    local out = {}
    for _, value in ipairs(fields) do
        value = tostring(value)
        out[#out + 1] = #value .. ':' .. value
    end
    return table.concat(out)
end

local function unpackFields(payload, maxFields)
    if type(payload) ~= 'string' or #payload > 2560 then return nil end
    local fields, pos = {}, 1
    while pos <= #payload do
        if #fields >= maxFields then return nil end
        local first, last, size = payload:find('(%d+):', pos)
        if first ~= pos or not last or #size > 4 then return nil end
        size = tonumber(size)
        pos = last + 1
        if size > #payload - pos + 1 then return nil end
        fields[#fields + 1] = payload:sub(pos, pos + size - 1)
        pos = pos + size
    end
    return fields
end

local function validText(value, min, max)
    return type(value) == 'string' and #value >= min and #value <= max
        and not value:find('[%z\1-\31\127]')
end

local function validID(value)
    return validText(value, 1, 64) and value:match('^[%w%-]+$') ~= nil
end

local categories = { dungeon=true, quest=true, world=true, raid=true, pvp=true, other=true }
local roles = { ['']=true, tank=true, healer=true, dps=true, flex=true }
local dungeonRoles = {'tank', 'healer', 'dps', 'dps', 'dps'}
local roleCode = { ['']='U', tank='T', healer='H', dps='D', flex='F' }
local codeRole = { U='', T='tank', H='healer', D='dps', F='flex' }
local MAX_GROUPS = 100
local GROUP_TTL = 3600

local function countGroups(groups)
    local count = 0
    for _ in pairs(groups) do count = count + 1 end
    return count
end

-- Preserve unknown or externally joined players without guessing their role.
function Finder:DungeonSlots(group, exclude)
    local slots, unassigned = {}, {}
    for i, role in ipairs(dungeonRoles) do slots[i] = {role=role} end
    for i, member in ipairs(group.members) do
        if member ~= exclude then
            local memberRole = i == 1 and group.role or (group.memberRoles and group.memberRoles[member]) or ''
            local placed = false
            for _, slot in ipairs(slots) do
                if not slot.member and slot.role == memberRole then
                    slot.member, slot.memberRole, placed = member, memberRole, true; break
                end
            end
            if not placed then unassigned[#unassigned + 1] = {name=member, role=memberRole} end
        end
    end
    for _, entry in ipairs(unassigned) do
        for i = #slots, 1, -1 do
            if not slots[i].member then slots[i].member, slots[i].memberRole = entry.name, entry.role; break end
        end
    end
    return slots
end

function Finder:RoleAvailable(group, role, exclude)
    if role ~= 'tank' and role ~= 'healer' and role ~= 'dps' and role ~= 'flex' then return false end
    if group.category ~= 'dungeon' or group.maxSize ~= 5 then return true end
    if role ~= 'tank' and role ~= 'healer' and role ~= 'dps' then return false end
    for _, slot in ipairs(self:DungeonSlots(group, exclude)) do
        if slot.role == role and not slot.member then return true end
    end
    return false
end

function Finder:Initialize(identity, send)
    assert(validText(identity, 1, 128) and type(send) == 'function')
    self.identity, self.send = identity, send
    self.groups, self.requests, self.pending, self.syncPending, self.requestVersions = {}, {}, {}, {}, {}
    self.pendingVersions, self.pendingRoles, self.decisions, self.decisionSync = {}, {}, {}, {}
    self.retryKeys, self.retryIndex = nil, nil
    self.sequence = 0
    self.requestSequence = GetServerTime() * 1000
end

function Finder:Create(title, category, description, maxSize, minLevel, maxLevel, role, dungeon)
    maxSize = tonumber(maxSize)
    minLevel, maxLevel, role = tonumber(minLevel or 1), tonumber(maxLevel or 60), role or ''
    dungeon = dungeon or ''
    if role == '' then return false, 'role' end
    if category == 'dungeon' and (maxSize ~= 5 or (role ~= 'tank' and role ~= 'healer' and role ~= 'dps')) then return false, 'roles' end
    if type(dungeon) ~= 'string' or #dungeon > 32 or (dungeon ~= '' and not validID(dungeon)) or (category ~= 'dungeon' and category ~= 'raid' and dungeon ~= '') then return false, 'invalid' end
    if not validText(title, 1, 100) or not categories[category]
        or not validText(description, 0, 500) or not maxSize or maxSize % 1 ~= 0
        or maxSize < 1 or maxSize > 200 or not minLevel or not maxLevel
        or minLevel % 1 ~= 0 or maxLevel % 1 ~= 0 or minLevel < 1 or maxLevel > 255
        or minLevel > maxLevel or not roles[role] then return false, 'invalid' end
    if countGroups(self.groups) >= MAX_GROUPS then return false, 'capacity' end
    self.sequence = self.sequence + 1
    local id = tostring(GetServerTime()) .. '-' .. tostring(math.random(100000, 999999)) .. '-' .. self.sequence
    local group = { id=id, owner=self.identity, title=title, category=category,
        description=description, maxSize=maxSize, minLevel=minLevel, maxLevel=maxLevel, role=role,
        revision=1, closed=false, members={self.identity}, dungeon=dungeon, seenAt=GetTime() }
    local payload = self:EncodeGroup(group)
    if not self.send('ANNOUNCE', payload) then return false, 'queue' end
    self.groups[self.identity .. '\001' .. id] = group
    return true, id
end

function Finder:EncodeGroup(group)
    local fields = {group.id, group.owner, group.revision, group.closed and '1' or '0',
        group.title, group.category, group.description, group.maxSize, #group.members,
        group.minLevel, group.maxLevel, group.role}
    for _, member in ipairs(group.members) do fields[#fields + 1] = member end
    if group.partyObserved then
        local states = {'A'}
        for i = 2, #group.members do
            states[i] = group.partyObserved[group.members[i]] and 'P' or 'R'
        end
        fields[#fields + 1] = table.concat(states)
    else
        fields[#fields + 1] = '?'
    end
    fields[#fields + 1] = group.dungeon or ''
    local memberRoles = {}
    for i, member in ipairs(group.members) do
        local memberRole = i == 1 and group.role or (group.memberRoles and group.memberRoles[member]) or ''
        memberRoles[i] = roleCode[memberRole] or 'U'
    end
    fields[#fields + 1] = table.concat(memberRoles)
    return pack(fields)
end

-- Combine actual party or raid members with accepted reservations that have
-- not joined yet. An observed member frees their place on leaving.
function Finder:SyncPartyMembers(party)
    if type(party) ~= 'table' or #party > 39 then return false, false end
    local current, partyNames = {}, {}
    for _, name in ipairs(party) do
        if not validText(name, 1, 128) or name == self.identity or current[name] then return false, false end
        current[name] = true
        partyNames[#partyNames + 1] = name
    end
    table.sort(partyNames)
    local changed = false
    for _, group in pairs(self.groups) do
        if group.owner == self.identity and not group.closed then
            local previous = group.partyObserved or {}
            local members, included = {self.identity}, {[self.identity] = true}
            for i = 2, #group.members do
                local name = group.members[i]
                if (not previous[name] or current[name]) and not included[name] then
                    members[#members + 1] = name
                    included[name] = true
                end
            end
            for _, name in ipairs(partyNames) do
                if not included[name] then members[#members + 1] = name; included[name] = true end
            end
            if #members > 200 then return false, changed end
            local differs = #members ~= #group.members
            if not differs then
                for i, name in ipairs(members) do if group.members[i] ~= name then differs = true; break end end
            end
            local observedChanged = group.partyObserved == nil
            for name in pairs(previous) do if not current[name] then observedChanged = true; break end end
            if not observedChanged then
                for name in pairs(current) do if not previous[name] then observedChanged = true; break end end
            end
            if differs or observedChanged then
                local oldMembers, oldMax, oldRevision, oldObserved = group.members, group.maxSize, group.revision, group.partyObserved
                group.members = members
                group.maxSize = math.max(group.maxSize, #members)
                group.revision = group.revision + 1
                group.partyObserved = current
                local payload = self:EncodeGroup(group)
                local sent = #payload <= 2560 and self.send('UPDATE', payload)
                if not sent then
                    group.members, group.maxSize, group.revision, group.partyObserved = oldMembers, oldMax, oldRevision, oldObserved
                    return false, changed, #payload > 2560 and 'payload' or 'queue'
                end
                if group.memberRoles then
                    for name in pairs(group.memberRoles) do if not included[name] then group.memberRoles[name] = nil end end
                end
                changed = true
            end
        end
    end
    return true, changed
end

function Finder:ReceiveGroup(sender, payload)
    local f = unpackFields(payload, 215)
    if not f or #f < 12 then return false end
    local id, owner, rev, closed, title, category, description, maxSize, count = unpack(f, 1, 9)
    rev, maxSize, count = tonumber(rev), tonumber(maxSize), tonumber(count)
    local minLevel, maxLevel, role = tonumber(f[10]), tonumber(f[11]), f[12]
    if not validID(id) or sender ~= owner or not validText(owner, 1, 128)
        or not rev or rev % 1 ~= 0 or rev < 1 or rev > 2147483647
        or (closed ~= '0' and closed ~= '1') or not validText(title, 1, 100)
        or not categories[category] or not validText(description, 0, 500)
        or not maxSize or maxSize % 1 ~= 0 or maxSize < 1 or maxSize > 200
        or not minLevel or not maxLevel or minLevel % 1 ~= 0 or maxLevel % 1 ~= 0
        or minLevel < 1 or maxLevel > 255 or minLevel > maxLevel or not roles[role]
        or not count or count % 1 ~= 0 or count < 1 or count > maxSize
        or (#f ~= 12 + count and #f ~= 13 + count and #f ~= 14 + count and #f ~= 15 + count) then return false end
    local members, seen = {}, {}
    for i=1,count do
        local name = f[12+i]
        if not validText(name, 1, 128) or seen[name] then return false end
        members[i], seen[name] = name, true
    end
    if members[1] ~= owner then return false end
    local states = f[13 + count]
    local dungeon = f[14 + count] or ''
    if #dungeon > 32 or (dungeon ~= '' and (not validID(dungeon) or (category ~= 'dungeon' and category ~= 'raid'))) then return false end
    local encodedRoles, memberRoles = f[15 + count], {}
    if encodedRoles then
        if #encodedRoles ~= count or encodedRoles:find('[^UTHDF]') then return false end
        for i = 1, count do memberRoles[members[i]] = codeRole[encodedRoles:sub(i, i)] end
        if memberRoles[owner] ~= role then return false end
    else memberRoles[owner] = role end
    local observed
    if states and states ~= '?' then
        if #states ~= count or states:sub(1, 1) ~= 'A' or states:sub(2):find('[^PR]') then return false end
        observed = {}
        for i = 2, count do if states:sub(i, i) == 'P' then observed[members[i]] = true end end
    end
    local key = owner .. '\001' .. id
    local existing = self.groups[key]
    if existing and existing.revision >= rev then
        if existing.revision == rev and self:EncodeGroup(existing) == payload then existing.seenAt = GetTime() end
        return false
    end
    if not existing and countGroups(self.groups) >= MAX_GROUPS then return false end
    self.groups[key] = { id=id, owner=owner, revision=rev, closed=closed=='1', title=title,
        category=category, description=description, maxSize=maxSize, minLevel=minLevel,
        maxLevel=maxLevel, role=role, members=members, partyObserved=observed, memberRoles=memberRoles, dungeon=dungeon, seenAt=GetTime() }
    if self.pending[key] == 'pending' then
        if seen[self.identity] then
            self.pending[key], self.pendingVersions[key], self.pendingRoles[key] = nil, nil, nil
        elseif closed == '1' then
            self.pending[key], self.pendingVersions[key], self.pendingRoles[key] = 'closed', nil, nil
        end
    end
    return true
end

function Finder:Prune()
    local now, changed = GetTime(), false
    for key, group in pairs(self.groups) do
        if group.owner ~= self.identity and now - group.seenAt > GROUP_TTL then
            self.groups[key] = nil
        end
    end

    -- Keep replay fences for every live owner listing. Once its tombstone is
    -- closed (or the listing no longer exists), old JOIN packets cannot be
    -- applied because ReceiveJoin also requires an existing open group.
    for versionKey in pairs(self.requestVersions) do
        local id = versionKey:match('^([^\\001]+)\\001')
        local group = id and self.groups[self.identity .. '\\001' .. id]
        if not group or group.closed then
            self.requestVersions[versionKey] = nil
            changed = true
        end
    end
    for id in pairs(self.requests) do
        local group = self.groups[self.identity .. '\\001' .. id]
        if not group or group.closed then self.requests[id] = nil; changed = true end
    end
    for id in pairs(self.decisions) do
        local group = self.groups[self.identity .. '\\001' .. id]
        if not group or group.closed then self.decisions[id] = nil; changed = true end
    end
    for decisionKey in pairs(self.decisionSync) do
        local id = decisionKey:match('^([^\\001]+)\\001')
        local group = id and self.groups[self.identity .. '\\001' .. id]
        if not group or group.closed then self.decisionSync[decisionKey] = nil; changed = true end
    end
    return changed
end

function Finder:Apply(owner, id, role)
    local key = owner .. '\001' .. id
    local group = self.groups[key]
    if not roles[role] or role == '' or not group or group.closed or owner == self.identity or #group.members >= group.maxSize
        or not self:RoleAvailable(group, role) then return false end
    for _, member in ipairs(group.members) do if member == self.identity then return false end end
    self.requestSequence = math.max(self.requestSequence + 1, GetServerTime() * 1000)
    if not self.send('JOIN', pack({owner, id, role, 'apply', string.format('%.0f', self.requestSequence)})) then return false end
    self.pending[key] = 'pending'
    self.pendingVersions[key], self.pendingRoles[key] = self.requestSequence, role
    return true
end

function Finder:DismissApplication(owner, id)
    local key = owner .. '\001' .. id
    if self.pending[key] == 'pending' then return self:Withdraw(owner, id) end
    if not self.pending[key] then return false end
    self.pending[key], self.pendingVersions[key], self.pendingRoles[key] = nil, nil, nil
    return true
end

function Finder:Withdraw(owner, id)
    local key = owner .. '\001' .. id
    if self.pending[key] ~= 'pending' then return false end
    self.requestSequence = math.max(self.requestSequence + 1, GetServerTime() * 1000)
    if not self.send('JOIN', pack({owner, id, '', 'withdraw', string.format('%.0f', self.requestSequence)})) then return false end
    self.pending[key] = nil
    self.pendingVersions[key], self.pendingRoles[key] = nil, nil
    return true
end

function Finder:ReceiveJoin(sender, payload)
    local f = unpackFields(payload, 5)
    if not f or #f ~= 5 then return false end
    local owner, id, role, action, version = unpack(f)
    version = tonumber(version)
    local group = self.groups[owner .. '\001' .. id]
    if owner ~= self.identity or not group or group.closed or sender == owner
        or not validText(sender, 1, 128) or not roles[role]
        or (action ~= 'apply' and action ~= 'withdraw')
        or (action == 'apply' and role == '')
        or not version or version % 1 ~= 0 or version < 1 or version > 9000000000000000 then return false end
    local versionKey = id .. '\001' .. sender
    if self.requestVersions[versionKey] and self.requestVersions[versionKey] >= version then return false end
    if not self.requestVersions[versionKey] and countGroups(self.requestVersions) >= 2000 then return false end
    if action == 'apply' and self.requests[id] and self.requests[id][sender] == nil
        and countGroups(self.requests[id]) >= 200 then return false end
    local isNew = action == 'apply' and (not self.requests[id] or self.requests[id][sender] == nil)
    self.requestVersions[versionKey] = version
    self.requests[id] = self.requests[id] or {}
    self.requests[id][sender] = action == 'apply' and role or nil
    if self.decisions[id] then self.decisions[id][sender] = nil end
    return true, isNew, id, role
end

function Finder:Decide(id, applicant, accept)
    local group = self.groups[self.identity .. '\001' .. id]
    local requests = self.requests[id]
    if not group or not requests or requests[applicant] == nil then return false end
    if accept then
        if #group.members >= group.maxSize then return false end
        if not self:RoleAvailable(group, requests[applicant]) then return false end
        for _, member in ipairs(group.members) do if member == applicant then return false end end
        group.memberRoles = group.memberRoles or {}
        local oldRole = group.memberRoles[applicant]
        group.memberRoles[applicant] = requests[applicant]
        group.members[#group.members + 1] = applicant
        group.revision = group.revision + 1
        if not self.send('UPDATE', self:EncodeGroup(group)) then
            group.members[#group.members] = nil
            group.memberRoles[applicant] = oldRole
            group.revision = group.revision - 1
            return false
        end
    end
    -- Retain a versioned rejection for later anti-entropy, even if the peer is offline.
    if not accept then
        local version = self.requestVersions[id .. '\001' .. applicant]
        if not version then return false end
        self.decisions[id] = self.decisions[id] or {}
        self.decisions[id][applicant] = version
        self.decisionSync[id .. '\001' .. applicant] = true
    end
    requests[applicant] = nil
    return true
end

function Finder:ReceiveResponse(sender, payload)
    local f = unpackFields(payload, 5)
    if not f or #f ~= 5 then return false end
    local owner, id, applicant, decision, version = unpack(f)
    version = tonumber(version)
    local key = owner .. '\001' .. id
    if sender ~= owner or applicant ~= self.identity or not self.groups[key]
        or self.pending[key] ~= 'pending' or decision ~= 'reject'
        or not version or version ~= self.pendingVersions[key] then return false end
    self.pending[key], self.pendingVersions[key], self.pendingRoles[key] = decision, nil, nil
    return true
end

function Finder:Cancel(id)
    local group = self.groups[self.identity .. '\001' .. id]
    if not group or group.closed then return false end
    group.closed, group.revision = true, group.revision + 1
    if not self.send('CANCEL', self:EncodeGroup(group)) then
        group.closed, group.revision = false, group.revision - 1
        return false
    end
    return true
end

function Finder:Delete(id)
    local group = self.groups[self.identity .. '\001' .. id]
    if not group then return false end
    if not group.closed and not self:Cancel(id) then return false end
    -- Keep the closed record as a synchronization tombstone, but hide it locally.
    group.hidden = true
    return true
end

-- Delete only listings whose owner actually observed another party/raid member.
-- A solo author can still create a listing and wait for accepted reservations.
function Finder:DeleteDisbandedGroups()
    local changed = false
    for _, group in pairs(self.groups) do
        if group.owner == self.identity and not group.closed and group.partyObserved and next(group.partyObserved) then
            if not self:Delete(group.id) then return false, changed end
            changed = true
        end
    end
    return true, changed
end

function Finder:RemoveMember(id, member)
    local group = self.groups[self.identity .. '\001' .. id]
    if not group or group.closed then return false end
    for i=2,#group.members do
        if group.members[i] == member then
            table.remove(group.members, i)
            group.revision = group.revision + 1
            if not self.send('UPDATE', self:EncodeGroup(group)) then
                table.insert(group.members, i, member)
                group.revision = group.revision - 1
                return false
            end
            if group.memberRoles then group.memberRoles[member] = nil end
            return true
        end
    end
    return false
end

function Finder:OnQuery()
    for key, group in pairs(self.groups) do
        if group.owner == self.identity then self.syncPending[key] = true end
    end
    for id, entries in pairs(self.decisions) do
        for applicant in pairs(entries) do self.decisionSync[id .. '\001' .. applicant] = true end
    end
end

-- Drain snapshots incrementally; a saturated transport retains the snapshot for retry.
function Finder:SyncStep()
    local key = next(self.syncPending)
    if not key then
        local decisionKey = next(self.decisionSync)
        if not decisionKey then return true end
        local id, applicant = decisionKey:match('^([^\001]+)\001(.+)$')
        local version = id and self.decisions[id] and self.decisions[id][applicant]
        if not version then self.decisionSync[decisionKey] = nil; return true end
        if not self.send('RESPONSE', pack({self.identity, id, applicant, 'reject', string.format('%.0f', version)})) then return false end
        self.decisionSync[decisionKey] = nil
        return true
    end
    local group = self.groups[key]
    if not group or group.owner ~= self.identity then
        self.syncPending[key] = nil
        return true
    end
    if not self.send('SYNC', self:EncodeGroup(group)) then return false end
    self.syncPending[key] = nil
    return true
end

-- A lost JOIN is retried with the original version; owner-side deduplication makes this safe.
function Finder:RetryPending()
    if not self.retryKeys then
        self.retryKeys = {}
        for key, state in pairs(self.pending) do
            if state == 'pending' then self.retryKeys[#self.retryKeys + 1] = key end
        end
        table.sort(self.retryKeys)
        self.retryIndex = 1
    end
    local key = self.retryKeys[self.retryIndex]
    if not key then self.retryKeys = nil; return true end
    local owner, id = key:match('^([^\001]+)\001(.+)$')
    local version, role = self.pendingVersions[key], self.pendingRoles[key]
    if self.pending[key] == 'pending' and owner and id and version and role
        and not self.send('JOIN', pack({owner, id, role, 'apply', string.format('%.0f', version)})) then return false end
    self.retryIndex = self.retryIndex + 1
    return false
end

Finder._pack, Finder._unpackFields = pack, unpackFields
