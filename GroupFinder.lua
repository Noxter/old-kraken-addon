-- Experimental model; not loaded by the addon until its integration is complete.
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
        local first, last, size = payload:find('^(%d+):', pos)
        if not first or #size > 4 then return nil end
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
local MAX_GROUPS = 100
local GROUP_TTL = 3600

local function countGroups(groups)
    local count = 0
    for _ in pairs(groups) do count = count + 1 end
    return count
end

function Finder:Initialize(identity, send)
    assert(validText(identity, 1, 128) and type(send) == 'function')
    self.identity, self.send = identity, send
    self.groups, self.requests, self.pending, self.syncPending, self.requestVersions = {}, {}, {}, {}, {}
    self.sequence = 0
    self.requestSequence = GetServerTime() * 1000
end

function Finder:Create(title, category, description, maxSize, minLevel, maxLevel, role)
    maxSize = tonumber(maxSize)
    minLevel, maxLevel, role = tonumber(minLevel or 1), tonumber(maxLevel or 60), role or ''
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
        revision=1, closed=false, members={self.identity}, seenAt=GetTime() }
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
    return pack(fields)
end

function Finder:ReceiveGroup(sender, payload)
    local f = unpackFields(payload, 212)
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
        or not count or count % 1 ~= 0 or count < 1 or count > maxSize or #f ~= 12 + count then return false end
    local members, seen = {}, {}
    for i=1,count do
        local name = f[12+i]
        if not validText(name, 1, 128) or seen[name] then return false end
        members[i], seen[name] = name, true
    end
    if members[1] ~= owner then return false end
    local key = owner .. '\001' .. id
    local existing = self.groups[key]
    if existing and existing.revision >= rev then
        if existing.revision == rev and self:EncodeGroup(existing) == payload then existing.seenAt = GetTime() end
        return false
    end
    if not existing and countGroups(self.groups) >= MAX_GROUPS then return false end
    self.groups[key] = { id=id, owner=owner, revision=rev, closed=closed=='1', title=title,
        category=category, description=description, maxSize=maxSize, minLevel=minLevel,
        maxLevel=maxLevel, role=role, members=members, seenAt=GetTime() }
    if self.pending[key] == 'pending' then
        if seen[self.identity] then self.pending[key] = 'accept'
        elseif closed == '1' then self.pending[key] = 'closed' end
    end
    return true
end

function Finder:Prune()
    local now = GetTime()
    for key, group in pairs(self.groups) do
        if group.owner ~= self.identity and now - group.seenAt > GROUP_TTL then
            self.groups[key], self.pending[key] = nil, nil
        end
    end
end

function Finder:Apply(owner, id, role)
    local key = owner .. '\001' .. id
    local group = self.groups[key]
    if not roles[role] or not group or group.closed or owner == self.identity then return false end
    self.requestSequence = math.max(self.requestSequence + 1, GetServerTime() * 1000)
    if not self.send('JOIN', pack({owner, id, role, 'apply', self.requestSequence})) then return false end
    self.pending[key] = 'pending'
    return true
end

function Finder:Withdraw(owner, id)
    local key = owner .. '\001' .. id
    if self.pending[key] ~= 'pending' then return false end
    self.requestSequence = math.max(self.requestSequence + 1, GetServerTime() * 1000)
    if not self.send('JOIN', pack({owner, id, '', 'withdraw', self.requestSequence})) then return false end
    self.pending[key] = nil
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
        or not version or version % 1 ~= 0 or version < 1 or version > 9000000000000000 then return false end
    local versionKey = id .. '\001' .. sender
    if self.requestVersions[versionKey] and self.requestVersions[versionKey] >= version then return false end
    if not self.requestVersions[versionKey] and countGroups(self.requestVersions) >= 2000 then return false end
    if action == 'apply' and self.requests[id] and self.requests[id][sender] == nil
        and countGroups(self.requests[id]) >= 200 then return false end
    self.requestVersions[versionKey] = version
    self.requests[id] = self.requests[id] or {}
    self.requests[id][sender] = action == 'apply' and role or nil
    return true
end

function Finder:Decide(id, applicant, accept)
    local group = self.groups[self.identity .. '\001' .. id]
    local requests = self.requests[id]
    if not group or not requests or requests[applicant] == nil then return false end
    if accept then
        if #group.members >= group.maxSize then return false end
        for _, member in ipairs(group.members) do if member == applicant then return false end end
        group.members[#group.members + 1] = applicant
        group.revision = group.revision + 1
        if not self.send('UPDATE', self:EncodeGroup(group)) then
            group.members[#group.members] = nil
            group.revision = group.revision - 1
            return false
        end
    end
    -- Membership in the owner's snapshot is authoritative for acceptance.
    -- Rejections still need a response; keep the request when it cannot be queued.
    if not accept and not self.send('RESPONSE', pack({self.identity, id, applicant, 'reject'})) then
        return false
    end
    requests[applicant] = nil
    return true
end

function Finder:ReceiveResponse(sender, payload)
    local f = unpackFields(payload, 4)
    if not f or #f ~= 4 then return false end
    local owner, id, applicant, decision = unpack(f)
    local key = owner .. '\001' .. id
    if sender ~= owner or applicant ~= self.identity or not self.groups[key]
        or self.pending[key] ~= 'pending' or (decision ~= 'accept' and decision ~= 'reject') then return false end
    self.pending[key] = decision
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

function Finder:Edit(id, title, description, maxSize, minLevel, maxLevel, role, category)
    local group = self.groups[self.identity .. '\001' .. id]
    maxSize, minLevel, maxLevel = tonumber(maxSize), tonumber(minLevel), tonumber(maxLevel)
    if not group or group.closed or not validText(title, 1, 100) or not validText(description, 0, 500)
        or not maxSize or maxSize % 1 ~= 0 or maxSize < #group.members or maxSize > 200
        or not minLevel or not maxLevel or minLevel % 1 ~= 0 or maxLevel % 1 ~= 0
        or minLevel < 1 or maxLevel > 255 or minLevel > maxLevel or not roles[role] or not categories[category] then return false end
    local old = {group.title, group.description, group.maxSize, group.minLevel, group.maxLevel, group.role, group.revision, group.category}
    group.title, group.description, group.maxSize, group.minLevel, group.maxLevel, group.role, group.category =
        title, description, maxSize, minLevel, maxLevel, role, category
    group.revision = group.revision + 1
    if not self.send('UPDATE', self:EncodeGroup(group)) then
        group.title, group.description, group.maxSize, group.minLevel, group.maxLevel, group.role, group.revision, group.category = unpack(old)
        return false
    end
    return true
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
            return true
        end
    end
    return false
end

function Finder:OnQuery()
    for key, group in pairs(self.groups) do
        if group.owner == self.identity then self.syncPending[key] = true end
    end
end

-- Drain snapshots incrementally; a saturated transport retains the snapshot for retry.
function Finder:SyncStep()
    local key = next(self.syncPending)
    if not key then return true end
    local group = self.groups[key]
    if not group or group.owner ~= self.identity then
        self.syncPending[key] = nil
        return true
    end
    if not self.send('SYNC', self:EncodeGroup(group)) then return false end
    self.syncPending[key] = nil
    return true
end

Finder._pack, Finder._unpackFields = pack, unpackFields
