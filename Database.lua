OldKraken = OldKraken or {}

local Database = {}
OldKraken.Database = Database

local SCHEMA_VERSION = 3

local function EnsureTable(parent, key)
    if type(parent[key]) ~= "table" then
        parent[key] = {}
    end
    return parent[key]
end

local function ApplyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            if type(value) == "table" then
                target[key] = {}
                ApplyDefaults(target[key], value)
            else
                target[key] = value
            end
        elseif type(value) == "table" and type(target[key]) == "table" then
            ApplyDefaults(target[key], value)
        end
    end
end

local DEFAULTS = {
    settings = {
        uiScale = 1,
        language = 'ukUA',
        smartNotifications = true,
        showMinimapButton = true,
        roster = {
            status = "all",
            sort = "level",
            ascending = true,
            class = "ALL",
            search = "",
        },
    },
    roster = {},
    events = {},
    groupFinder = {},
    workshop = {},
}

local function NormalizeRosterSettings(settings)
    if settings.status ~= "all"
        and settings.status ~= "online"
        and settings.status ~= "offline" then
        settings.status = "all"
    end

    if settings.sort ~= "name"
        and settings.sort ~= "level"
        and settings.sort ~= "class"
        and settings.sort ~= "rank"
        and settings.sort ~= "zone" then
        settings.sort = "level"
    end

    if type(settings.ascending) ~= "boolean" then
        settings.ascending = true
    end

    if type(settings.class) ~= "string" or settings.class == "" then
        settings.class = "ALL"
    end

    if type(settings.search) ~= "string" then
        settings.search = ""
    end
end

function Database.Initialize()
    if type(OldKrakenDB) ~= "table" then
        OldKrakenDB = {}
    end

    local db = OldKrakenDB
    local schemaVersion = tonumber(db.schemaVersion) or 0

    if schemaVersion > SCHEMA_VERSION then
        OldKraken.DB = db
        return db
    end

    -- Schema migrations must preserve existing SavedVariables wherever possible.
    if schemaVersion < 1 then
        EnsureTable(db, "settings")
        EnsureTable(db, "roster")
        EnsureTable(db, "events")
        db.schemaVersion = 1
    end

    if schemaVersion < 2 then
        EnsureTable(db, "groupFinder")
        db.schemaVersion = 2
    end

    if schemaVersion < 3 then
        EnsureTable(db, "workshop")
        db.schemaVersion = 3
    end

    EnsureTable(db, "settings")
    EnsureTable(db.settings, "roster")
    EnsureTable(db, "roster")
    EnsureTable(db, "events")
    EnsureTable(db, "groupFinder")
    EnsureTable(db, "workshop")
    ApplyDefaults(db, DEFAULTS)
    NormalizeRosterSettings(db.settings.roster)

    db.schemaVersion = SCHEMA_VERSION
    db.version = OldKraken.version

    OldKraken.DB = db
    return db
end

local MAX_MIGRATION_CONFLICTS = 200
local migrationNotices = {}

local function ServerTime()
    return type(GetServerTime) == "function" and GetServerTime() or 0
end

local function IsIntRange(value, low, high)
    return type(value) == "number" and value == value and value % 1 == 0 and value >= low and value <= high
end

local function IsValidText(value, low, high)
    if type(issecretvalue) == "function" and issecretvalue(value) then
        return false
    end
    return type(value) == "string" and #value >= low and #value <= high and not value:find("[%z\1-\31\127]")
end

local function SortedKeys(tbl)
    local keys = {}
    if type(tbl) ~= "table" then
        return keys
    end
    for k in pairs(tbl) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return keys
end

local function CountTable(tbl)
    local n = 0
    if type(tbl) ~= "table" then
        return 0
    end
    for _ in pairs(tbl) do
        n = n + 1
    end
    return n
end

local function DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[DeepCopy(k)] = DeepCopy(v)
    end
    return copy
end

local function DeepEqual(a, b)
    if a == b then
        return true
    end
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end
    for k, v in pairs(a) do
        if not DeepEqual(v, b[k]) then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

local function ExtractPackInt(payload, index)
    if type(payload) ~= "string" then
        return nil
    end
    local pos = 1
    for i = 1, index do
        local lenStr, colonPos = payload:match("^(%d+):()", pos)
        local len = tonumber(lenStr)
        if not len or #lenStr > 4 or pos + #lenStr + 1 + len - 1 > #payload then
            return nil
        end
        local field = payload:sub(colonPos, colonPos + len - 1)
        if i == index then
            return tonumber(field)
        end
        pos = colonPos + len
    end
    return nil
end

local function IsEmptyDraft(draft)
    if type(draft) ~= "table" then
        return true
    end
    return (draft.item or "") == ""
        and (draft.note or "") == ""
        and draft.recipe == nil
        and (draft.quantity == nil or draft.quantity == "" or draft.quantity == "1")
        and (draft.reward == nil or draft.reward == "" or draft.reward == "0")
        and (draft.rewardSilver == nil or draft.rewardSilver == "" or draft.rewardSilver == "0")
        and (draft.profession == nil or draft.profession == 0)
        and (draft.materials == nil or draft.materials == "customer")
        and (draft.deadline == nil or draft.deadline == 86400)
end

local function OrderQuantityIn(scope, identity, orderKey)
    if type(scope) ~= "table" then
        return nil
    end
    local owners = scope.orderOwners
    local ord = type(owners) == "table" and type(owners[identity]) == "table" and owners[identity][orderKey] or nil
    if type(ord) == "table" and IsIntRange(ord.quantity, 1, 200) then
        return ord.quantity
    end
    ord = type(scope.orderObserved) == "table" and scope.orderObserved[orderKey] or nil
    if type(ord) == "table" and IsIntRange(ord.quantity, 1, 200) then
        return ord.quantity
    end
    return nil
end

-- Each scope is checked separately: a missing canonical order must not hide the legacy one.
-- Without any known order the code-level cap of 200 items per order applies.
local function FindOrderQuantity(target, source, identity, orderKey)
    return OrderQuantityIn(target, identity, orderKey) or OrderQuantityIn(source, identity, orderKey) or 200
end

local function IsValidTally(tally, maxItems)
    if type(tally) ~= "table" then
        return false
    end
    if tally.worker ~= nil and not IsValidText(tally.worker, 1, 128) then
        return false
    end
    if not IsIntRange(tally.assignment, 0, 2147483647) then
        return false
    end
    if not IsIntRange(tally.items, 0, maxItems or 200) then
        return false
    end
    if not IsIntRange(tally.money, 0, 1000000000) then
        return false
    end
    if type(tally.materials) ~= "table" then
        return false
    end
    for itemId, cnt in pairs(tally.materials) do
        if not IsIntRange(itemId, 1, 100000000) or not IsIntRange(cnt, 0, 10000000) then
            return false
        end
    end
    return true
end

local function RecordConflict(target, section, recordKey, canonicalVal, legacyVal)
    local conflicts = EnsureTable(target, "migrationConflicts")
    local conflictKey = section .. "\001" .. tostring(recordKey)
    local existing = conflicts[conflictKey]
    if type(existing) == "table" then
        -- A resumed run sees the already merged canonical value; the first recorded
        -- canonical is the pre-migration original and must never be replaced.
        if not DeepEqual(existing.legacy, legacyVal) then
            existing.legacy = DeepCopy(legacyVal)
            existing.detectedAt = ServerTime()
        end
        return false
    end
    if CountTable(conflicts) >= MAX_MIGRATION_CONFLICTS then
        target.migrationConflictsOverflow = true
        return true
    end
    conflicts[conflictKey] = {
        section = section,
        key = tostring(recordKey),
        canonical = DeepCopy(canonicalVal),
        legacy = DeepCopy(legacyVal),
        detectedAt = ServerTime(),
        resolved = false,
    }
    return false
end

local function MergeRecords(target, source)
    if type(source.records) ~= "table" then
        return false
    end
    local dst = EnsureTable(target, "records")
    local overflow = false
    for _, owner in ipairs(SortedKeys(source.records)) do
        local src = source.records[owner]
        local tgt = dst[owner]
        if tgt == nil then
            dst[owner] = DeepCopy(src)
        elseif type(tgt) == "table" and type(src) == "table" then
            local sTs, tTs = tonumber(src.timestamp) or 0, tonumber(tgt.timestamp) or 0
            local sDir = tonumber(src.directTimestamp) or (not src.relayed and sTs or 0)
            local tDir = tonumber(tgt.directTimestamp) or (not tgt.relayed and tTs or 0)
            local maxDir = math.max(sDir, tDir)
            if sTs > tTs then
                local copy = DeepCopy(src)
                copy.directTimestamp = maxDir
                dst[owner] = copy
            elseif tTs > sTs then
                tgt.directTimestamp = maxDir
            elseif (src.relayed == true) ~= (tgt.relayed == true) then
                if not src.relayed then
                    local copy = DeepCopy(src)
                    copy.directTimestamp = maxDir
                    dst[owner] = copy
                else
                    tgt.directTimestamp = maxDir
                end
            else
                tgt.directTimestamp = maxDir
                if not DeepEqual(tgt.list, src.list) then
                    if RecordConflict(target, "records", owner, tgt, src) then
                        overflow = true
                    end
                end
            end
        elseif not DeepEqual(tgt, src) then
            if RecordConflict(target, "records", owner, tgt, src) then
                overflow = true
            end
        end
    end
    return overflow
end

local function MergePackedPayloads(target, source, section, fieldIndex)
    if type(source[section]) ~= "table" then
        return false
    end
    local dst = EnsureTable(target, section)
    local overflow = false
    for _, key in ipairs(SortedKeys(source[section])) do
        local src = source[section][key]
        local tgt = dst[key]
        if tgt == nil then
            dst[key] = src
        elseif tgt ~= src then
            local tVer = ExtractPackInt(tgt, fieldIndex)
            local sVer = ExtractPackInt(src, fieldIndex)
            if sVer and tVer and sVer > tVer then
                dst[key] = src
            elseif not (sVer and tVer and tVer > sVer) then
                if RecordConflict(target, section, key, tgt, src) then
                    overflow = true
                end
            end
        end
    end
    return overflow
end

local function MergeUnionByIdentity(target, source, section, skipTable)
    if type(source[section]) ~= "table" then
        return
    end
    local dst = EnsureTable(target, section)
    for _, identity in ipairs(SortedKeys(source[section])) do
        local srcSet = source[section][identity]
        if type(srcSet) == "table" then
            local dstSet = EnsureTable(dst, identity)
            local skip = type(skipTable) == "table" and skipTable[identity] or nil
            for _, itemKey in ipairs(SortedKeys(srcSet)) do
                if srcSet[itemKey] and not (type(skip) == "table" and skip[itemKey] ~= nil) then
                    dstSet[itemKey] = true
                end
            end
        end
    end
end

local function MergeRecipes(target, source)
    local overflow = false
    local ownersSeen, owners = {}, {}
    for _, tbl in ipairs({ source.recipes or false, source.recipeTombstones or false, source.recipeSources or false }) do
        if type(tbl) == "table" then
            for owner in pairs(tbl) do
                if not ownersSeen[owner] then
                    ownersSeen[owner] = true
                    owners[#owners + 1] = owner
                end
            end
        end
    end
    table.sort(owners, function(a, b) return tostring(a) < tostring(b) end)
    local tRecipes = EnsureTable(target, "recipes")
    local tTombs = EnsureTable(target, "recipeTombstones")
    local tSources = EnsureTable(target, "recipeSources")
    for _, owner in ipairs(owners) do
        local sLiveTbl = type(source.recipes) == "table" and source.recipes[owner] or nil
        local sTombTbl = type(source.recipeTombstones) == "table" and source.recipeTombstones[owner] or nil
        local sSrcTbl = type(source.recipeSources) == "table" and source.recipeSources[owner] or nil
        local ridsSeen, rids = {}, {}
        for _, tbl in ipairs({ sLiveTbl or false, sTombTbl or false }) do
            if type(tbl) == "table" then
                for rid in pairs(tbl) do
                    if not ridsSeen[rid] then
                        ridsSeen[rid] = true
                        rids[#rids + 1] = rid
                    end
                end
            end
        end
        table.sort(rids, function(a, b) return tostring(a) < tostring(b) end)
        local dLive = EnsureTable(tRecipes, owner)
        local dTomb = EnsureTable(tTombs, owner)
        local dSrc = EnsureTable(tSources, owner)
        for _, rid in ipairs(rids) do
            local sLive = type(sLiveTbl) == "table" and sLiveTbl[rid] or nil
            local sTomb = type(sTombTbl) == "table" and sTombTbl[rid] or nil
            local sIsTomb = sTomb ~= nil
            local sEntry = sIsTomb and sTomb or sLive
            local sRelayed = type(sSrcTbl) == "table" and sSrcTbl[rid] == true or false

            local tLive = dLive[rid]
            local tTomb = dTomb[rid]
            local tIsTomb = tTomb ~= nil
            local tEntry = tIsTomb and tTomb or tLive
            local tRelayed = dSrc[rid] == true

            if tEntry == nil and sEntry ~= nil then
                if sIsTomb then
                    dTomb[rid] = DeepCopy(sEntry)
                    dLive[rid] = nil
                else
                    dLive[rid] = DeepCopy(sEntry)
                    dTomb[rid] = nil
                end
                dSrc[rid] = sRelayed
            elseif sEntry ~= nil and type(tEntry) == "table" and type(sEntry) == "table" then
                local tSeen, sSeen = tonumber(tEntry.seen) or 0, tonumber(sEntry.seen) or 0
                local takeSource = (not sRelayed and tRelayed)
                    or (sRelayed == tRelayed and (sSeen > tSeen
                    or (sSeen == tSeen and sIsTomb and not tIsTomb)))
                if takeSource then
                    if sIsTomb then
                        dTomb[rid] = DeepCopy(sEntry)
                        dLive[rid] = nil
                    else
                        dLive[rid] = DeepCopy(sEntry)
                        dTomb[rid] = nil
                    end
                    dSrc[rid] = sRelayed
                elseif sSeen == tSeen and sRelayed == tRelayed and sIsTomb == tIsTomb and not DeepEqual(tEntry, sEntry) then
                    if RecordConflict(target, "recipes", tostring(owner) .. "\001" .. tostring(rid), tEntry, sEntry) then
                        overflow = true
                    end
                end
            end
        end
    end
    return overflow
end

local function MergeMaxNumbers(target, source, section)
    if type(source[section]) ~= "table" then
        return
    end
    local dst = EnsureTable(target, section)
    for _, key in ipairs(SortedKeys(source[section])) do
        local srcVal = tonumber(source[section][key])
        if srcVal then
            local tgtVal = tonumber(dst[key]) or 0
            if srcVal > tgtVal then
                dst[key] = srcVal
            end
        end
    end
end

local function MergeSnapshots(target, source)
    local overflow = false
    if type(source.recipeDirectSnapshots) == "table" then
        local dst = EnsureTable(target, "recipeDirectSnapshots")
        for _, owner in ipairs(SortedKeys(source.recipeDirectSnapshots)) do
            local src, tgt = source.recipeDirectSnapshots[owner], dst[owner]
            if tgt == nil then
                dst[owner] = DeepCopy(src)
            elseif type(tgt) == "table" and type(src) == "table" then
                local tRev, sRev = tonumber(tgt.rev) or 0, tonumber(src.rev) or 0
                if sRev > tRev then
                    dst[owner] = DeepCopy(src)
                elseif sRev == tRev and not DeepEqual(tgt.records, src.records) then
                    if RecordConflict(target, "recipeDirectSnapshots", owner, tgt, src) then
                        overflow = true
                    end
                end
            end
        end
    end
    if type(source.recipeSnapshotViews) == "table" then
        local dst = EnsureTable(target, "recipeSnapshotViews")
        local directDst = EnsureTable(target, "recipeDirectSnapshots")
        for _, owner in ipairs(SortedKeys(source.recipeSnapshotViews)) do
            local src, tgt = source.recipeSnapshotViews[owner], dst[owner]
            if tgt == nil then
                dst[owner] = DeepCopy(src)
            elseif type(tgt) == "table" and type(src) == "table" then
                local tRev, sRev = tonumber(tgt.rev) or 0, tonumber(src.rev) or 0
                if sRev > tRev then
                    local maxDir = math.max(tonumber(tgt.directRev) or 0, tonumber(src.directRev) or 0)
                    local copy = DeepCopy(src)
                    copy.directRev = (copy.relayed == false) and sRev or math.min(sRev, maxDir)
                    dst[owner] = copy
                elseif sRev == tRev then
                    local isDirect = (tgt.relayed == false) or (src.relayed == false)
                    local maxDir = math.max(tonumber(tgt.directRev) or 0, tonumber(src.directRev) or 0)
                    dst[owner] = {
                        rev = tRev,
                        directRev = isDirect and tRev or math.min(tRev, maxDir),
                        relayed = not isDirect,
                    }
                end
            end
            local view = dst[owner]
            local direct = directDst[owner]
            if type(view) == "table" and view.relayed == true and type(direct) == "table" and (tonumber(direct.rev) or 0) < (tonumber(view.rev) or 0) then
                directDst[owner] = nil
            end
        end
    end
    return overflow
end

local function MergeOrderOwners(target, source)
    if type(source.orderOwners) ~= "table" then
        return false
    end
    local dst = EnsureTable(target, "orderOwners")
    local overflow = false
    for _, identity in ipairs(SortedKeys(source.orderOwners)) do
        local srcOrders = source.orderOwners[identity]
        if type(srcOrders) == "table" then
            local dstOrders = EnsureTable(dst, identity)
            for _, orderKey in ipairs(SortedKeys(srcOrders)) do
                local src, tgt = srcOrders[orderKey], dstOrders[orderKey]
                local normalized = OldKraken.WorkshopOrders:NormalizeMigrationOrder(orderKey, src, identity)
                if not normalized then
                    if RecordConflict(target, "orderOwners", tostring(identity) .. "\001" .. tostring(orderKey), tgt, src) then overflow = true end
                elseif tgt == nil then
                    dstOrders[orderKey] = normalized
                elseif type(tgt) == "table" and type(src) == "table" then
                    local tRev, sRev = tonumber(tgt.rev) or 0, tonumber(src.rev) or 0
                    if sRev > tRev then
                        dstOrders[orderKey] = normalized
                    elseif sRev == tRev and not DeepEqual(tgt, src) then
                        if RecordConflict(target, "orderOwners", tostring(identity) .. "\001" .. tostring(orderKey), tgt, src) then
                            overflow = true
                        end
                    end
                elseif not DeepEqual(tgt, src) then
                    if RecordConflict(target, "orderOwners", tostring(identity) .. "\001" .. tostring(orderKey), tgt, src) then
                        overflow = true
                    end
                end
            end
        end
    end
    return overflow
end

local function MergeOrderObserved(target, source)
    if type(source.orderObserved) ~= "table" then
        return false
    end
    local dst = EnsureTable(target, "orderObserved")
    local overflow = false
    for _, orderKey in ipairs(SortedKeys(source.orderObserved)) do
        local src, tgt = source.orderObserved[orderKey], dst[orderKey]
        local normalized = OldKraken.WorkshopOrders:NormalizeMigrationOrder(orderKey, src)
        if not normalized then
            if RecordConflict(target, "orderObserved", orderKey, tgt, src) then overflow = true end
        elseif tgt == nil then
            dst[orderKey] = normalized
        elseif type(tgt) == "table" and type(src) == "table" then
            local tOwnerRev = tonumber(tgt.ownerRev) or (not tgt.relayed and tonumber(tgt.rev) or 0)
            local sOwnerRev = tonumber(src.ownerRev) or (not src.relayed and tonumber(src.rev) or 0)
            local tRev, sRev = tonumber(tgt.rev) or 0, tonumber(src.rev) or 0
            local takeSource = sOwnerRev > tOwnerRev
                or (sOwnerRev == tOwnerRev and sRev > tRev)
                or (sOwnerRev == tOwnerRev and sRev == tRev and not src.relayed and tgt.relayed == true)
            if takeSource then
                dst[orderKey] = normalized
            elseif sOwnerRev == tOwnerRev and sRev == tRev and (src.relayed == true) == (tgt.relayed == true) and not DeepEqual(tgt, src) then
                if RecordConflict(target, "orderObserved", orderKey, tgt, src) then
                    overflow = true
                end
            end
        end
    end
    return overflow
end

local function MergeVersionedByIdentity(target, source, section)
    if type(source[section]) ~= "table" then
        return false
    end
    local dst = EnsureTable(target, section)
    local overflow = false
    for _, identity in ipairs(SortedKeys(source[section])) do
        local srcMap = source[section][identity]
        if type(srcMap) == "table" then
            local dstMap = EnsureTable(dst, identity)
            for _, key in ipairs(SortedKeys(srcMap)) do
                local src, tgt = srcMap[key], dstMap[key]
                if tgt == nil then
                    dstMap[key] = DeepCopy(src)
                elseif type(tgt) == "table" and type(src) == "table" then
                    local tVer, sVer = tonumber(tgt.version) or 0, tonumber(src.version) or 0
                    if sVer > tVer then
                        dstMap[key] = DeepCopy(src)
                    elseif sVer == tVer and not DeepEqual(tgt, src) then
                        if RecordConflict(target, section, tostring(identity) .. "\001" .. tostring(key), tgt, src) then
                            overflow = true
                        end
                    end
                end
            end
        end
    end
    return overflow
end

local function MergeOrderResults(target, source, section)
    if type(source[section]) ~= "table" then
        return false
    end
    local dst = EnsureTable(target, section)
    local overflow = false
    for _, key in ipairs(SortedKeys(source[section])) do
        local src, tgt = source[section][key], dst[key]
        if tgt == nil then
            dst[key] = DeepCopy(src)
        elseif type(tgt) == "table" and type(src) == "table" then
            local tVer, sVer = tonumber(tgt.version) or 0, tonumber(src.version) or 0
            if sVer > tVer then
                dst[key] = DeepCopy(src)
            elseif sVer == tVer and not DeepEqual(tgt, src) then
                if RecordConflict(target, section, key, tgt, src) then
                    overflow = true
                end
            end
        end
    end
    return overflow
end

local function MaxTally(tgt, src)
    local mergedMats = {}
    for itemId, cnt in pairs(tgt.materials) do
        mergedMats[itemId] = cnt
    end
    for itemId, cnt in pairs(src.materials) do
        mergedMats[itemId] = math.max(mergedMats[itemId] or 0, cnt)
    end
    return {
        worker = tgt.worker,
        assignment = tgt.assignment,
        materials = mergedMats,
        items = math.max(tgt.items, src.items),
        money = math.max(tgt.money, src.money),
    }
end

-- Tally counters are cumulative and carry no operation IDs, so they are never summed.
-- The active canonical value is replaced or removed only after its original has been
-- stored in migrationConflicts; on overflow the canonical value stays as it was and the
-- legacy scope remains the recovery source.
-- Validity matrix (legacy / canonical):
--   valid / valid     -> merge rules (higher assignment, else component max for same worker, else keep canonical)
--   valid / invalid   -> legacy becomes active
--   invalid / valid   -> canonical stays active
--   invalid / invalid -> no active tally
local function MergeDeliveryTallies(target, source)
    if type(source.orderDeliveryTallies) ~= "table" then
        return false
    end
    local dst = EnsureTable(target, "orderDeliveryTallies")
    local overflow = false
    for _, identity in ipairs(SortedKeys(source.orderDeliveryTallies)) do
        local srcMap = source.orderDeliveryTallies[identity]
        if type(srcMap) == "table" then
            local dstMap = EnsureTable(dst, identity)
            for _, orderKey in ipairs(SortedKeys(srcMap)) do
                local maxItems = FindOrderQuantity(target, source, identity, orderKey)
                local pendingRoot=target.migrationPendingTallies
                local pending=type(pendingRoot)=='table' and pendingRoot[identity]
                local wasPending=type(pending)=='table' and pending[orderKey] or nil
                local src, tgt = srcMap[orderKey], dstMap[orderKey] or wasPending
                local result = tgt
                local srcValid = IsValidTally(src, maxItems)
                local tgtValid = IsValidTally(tgt, maxItems)
                local conflictKey = tostring(identity) .. "\001" .. tostring(orderKey)
                if srcValid and tgt == nil then
                    result = DeepCopy(src)
                elseif srcValid and tgtValid and DeepEqual(tgt, src) then
                    -- identical duplicate
                else
                    local preserved = not RecordConflict(target, "orderDeliveryTallies", conflictKey, tgt, src)
                    if not preserved then
                        overflow = true
                    elseif srcValid and not tgtValid then
                        result = DeepCopy(src)
                    elseif not srcValid and not tgtValid then
                        result = nil
                    elseif srcValid and tgtValid then
                        if src.assignment > tgt.assignment then
                            result = DeepCopy(src)
                        elseif src.assignment == tgt.assignment and src.worker == tgt.worker then
                            result = MaxTally(tgt, src)
                        end
                    end
                end
                -- An unmatched tally stays separate until the live module can
                -- validate it against the actual order and assignment.
                if result and (wasPending or not OrderQuantityIn(target, identity, orderKey)) then
                    pending=EnsureTable(EnsureTable(target, 'migrationPendingTallies'), identity)
                    pending[orderKey]=DeepCopy(result)
                    dstMap[orderKey]=nil
                else
                    dstMap[orderKey]=result
                end
            end
        end
    end
    return overflow
end

local function MergeOrderDrafts(target, source)
    if type(source.orderDrafts) ~= "table" then
        return false
    end
    local dst = EnsureTable(target, "orderDrafts")
    local overflow = false
    for _, identity in ipairs(SortedKeys(source.orderDrafts)) do
        local src, tgt = source.orderDrafts[identity], dst[identity]
        local srcEmpty, tgtEmpty = IsEmptyDraft(src), IsEmptyDraft(tgt)
        if tgtEmpty and not srcEmpty then
            dst[identity] = DeepCopy(src)
        elseif not tgtEmpty and not srcEmpty and not DeepEqual(tgt, src) then
            if RecordConflict(target, "orderDrafts", identity, tgt, src) then
                overflow = true
            end
        end
    end
    return overflow
end

function Database.IsValidRealm(selfOrRealm, maybeRealm)
    local realm = selfOrRealm == Database and maybeRealm or selfOrRealm
    return IsValidText(realm, 1, 128)
end

function Database.GetRealmScope()
    local realm = type(GetRealmName) == "function" and GetRealmName() or nil
    if Database.IsValidRealm(realm) then
        return realm
    end
    if type(issecretvalue) == "function" and issecretvalue(realm) then
        return nil
    end
    if realm == "" then
        local norm = type(GetNormalizedRealmName) == "function" and GetNormalizedRealmName() or nil
        if Database.IsValidRealm(norm) then
            return norm
        end
        local cvar = type(GetCVar) == "function" and GetCVar("realmName") or nil
        if Database.IsValidRealm(cvar) then
            return cvar
        end
        return "Forever"
    end
    return nil
end

function Database.IsValidWorkshopTally(tally, quantity)
    return IsValidTally(tally, quantity)
end

function Database.MigrateWorkshopScope(selfOrRealm, realmOrGuild, guildOrConfirmed, maybeConfirmed)
    local realm, guild, confirmed
    if selfOrRealm == Database then
        realm, guild, confirmed = realmOrGuild, guildOrConfirmed, maybeConfirmed
    else
        realm, guild, confirmed = selfOrRealm, realmOrGuild, guildOrConfirmed
    end
    if not IsValidText(realm, 1, 128) or not IsValidText(guild, 1, 128) then
        return false, "invalid"
    end
    local db = OldKraken.DB
    if type(db) ~= "table" or type(db.workshop) ~= "table" or type(db.workshop.guilds) ~= "table" then
        return false, "none"
    end
    local legacyKey = "\001" .. guild
    local source = db.workshop.guilds[legacyKey]
    if type(source) ~= "table" then
        return false, "none"
    end

    local canonicalKey = realm .. "\001" .. guild
    local migrations = EnsureTable(db.workshop, "legacyMigrations")
    local meta = EnsureTable(migrations, legacyKey)
    local statusMap = EnsureTable(meta, "status")
    local pendingMap = EnsureTable(meta, "pendingConfirmation")
    local inProgressMap = EnsureTable(meta, "inProgress")

    local status = statusMap[canonicalKey]
    if status == "completed" or status == "completedWithOverflow" then
        pendingMap[canonicalKey] = nil
        return true, status
    end

    -- A confirmed run that was interrupted resumes on the next call; the user already
    -- agreed to this exact realm and guild. Otherwise confirmation is valid only for a
    -- canonical key that was previously offered through pendingConfirmation.
    local resume = inProgressMap[canonicalKey] == true
    if not resume then
        if confirmed ~= true then
            pendingMap[canonicalKey] = true
            if not migrationNotices[canonicalKey] and type(OldKraken.Print) == 'function' then
                local text = 'Знайдено старі дані Майстерні без назви світу. Перевірте світ і гільдію та введіть /okr workshop migrate для перенесення.'
                if type(OldKraken.Translate) == 'function' then text = OldKraken.Translate(text) end
                pcall(OldKraken.Print, OldKraken, text)
                migrationNotices[canonicalKey] = true
            end
            return false, "pending"
        end
        if pendingMap[canonicalKey] ~= true then
            return false, "unconfirmed"
        end
    end

    if (type(source.orderOwners) == 'table' and next(source.orderOwners))
        or (type(source.orderObserved) == 'table' and next(source.orderObserved)) then
        if not OldKraken.WorkshopOrders or type(OldKraken.WorkshopOrders.NormalizeMigrationOrder) ~= 'function' then
            return false, 'unavailable'
        end
    end

    inProgressMap[canonicalKey] = true

    local target = EnsureTable(db.workshop.guilds, canonicalKey)
    local overflow = false
    if MergeRecords(target, source) then overflow = true end
    if MergePackedPayloads(target, source, "professionRelays", 1) then overflow = true end
    MergeUnionByIdentity(target, source, "pendingProfessionRemovals")
    if MergeRecipes(target, source) then overflow = true end
    MergeMaxNumbers(target, source, "recipeVersions")
    MergeMaxNumbers(target, source, "recipeVersionSeen")
    MergeUnionByIdentity(target, source, "pendingRecipes", target.recipes)
    if MergeSnapshots(target, source) then overflow = true end
    if MergeOrderOwners(target, source) then overflow = true end
    if MergeOrderObserved(target, source) then overflow = true end
    if MergeVersionedByIdentity(target, source, "orderIntents") then overflow = true end
    MergeMaxNumbers(target, source, "orderSequences")
    if MergePackedPayloads(target, source, "orderRelays", 3) then overflow = true end
    if MergeOrderResults(target, source, "orderResults") then overflow = true end
    if MergeOrderResults(target, source, "orderResultRelays") then overflow = true end
    if MergeDeliveryTallies(target, source) then overflow = true end
    if MergeOrderDrafts(target, source) then overflow = true end

    inProgressMap[canonicalKey] = nil
    pendingMap[canonicalKey] = nil
    if overflow or target.migrationConflictsOverflow then
        statusMap[canonicalKey] = "completedWithOverflow"
    else
        statusMap[canonicalKey] = "completed"
    end
    if type(OldKraken.Fire) == 'function' then OldKraken:Fire('WORKSHOP_SCOPE_MIGRATED', canonicalKey) end
    return true, statusMap[canonicalKey]
end

function Database.ConfirmWorkshopMigration()
    local realm = Database.GetRealmScope()
    local guild = type(GetGuildInfo) == "function" and GetGuildInfo("player") or nil
    if not IsValidText(realm, 1, 128) or not IsValidText(guild, 1, 128) then
        return false, "invalid"
    end
    local db = OldKraken.DB
    local legacyKey = "\001" .. guild
    local canonicalKey = realm .. "\001" .. guild
    local migrations = type(db) == "table" and type(db.workshop) == "table" and db.workshop.legacyMigrations
    local meta = type(migrations) == "table" and migrations[legacyKey]
    if type(meta) ~= "table" or type(meta.pendingConfirmation) ~= "table" or not meta.pendingConfirmation[canonicalKey] then
        return false, "none"
    end
    return Database.MigrateWorkshopScope(realm, guild, true)
end

local function CurrentWorkshopScope()
    local realm = Database.GetRealmScope()
    local guild = type(GetGuildInfo) == 'function' and GetGuildInfo('player') or nil
    if not IsValidText(realm,1,128) or not IsValidText(guild,1,128) then return nil end
    local db = OldKraken.DB
    local guilds = type(db)=='table' and type(db.workshop)=='table' and db.workshop.guilds
    local profile = realm .. '\001' .. guild
    return type(guilds)=='table' and guilds[profile] or nil, profile
end

function Database.WorkshopMigrationConflicts()
    local scope = CurrentWorkshopScope()
    local conflicts = type(scope)=='table' and scope.migrationConflicts
    local count,sections = 0,{}
    if type(conflicts)=='table' then
        for _, entry in pairs(conflicts) do
            if type(entry)=='table' and entry.resolved~=true then
                count=count+1
                local section=type(entry.section)=='string' and entry.section or 'unknown'
                sections[section]=(sections[section] or 0)+1
            end
        end
    end
    local pending=type(scope)=='table' and scope.migrationPendingTallies
    if type(pending)=='table' then
        for _, tallies in pairs(pending) do
            if type(tallies)=='table' then
                for _ in pairs(tallies) do
                    count=count+1
                    sections.pendingDeliveryTallies=(sections.pendingDeliveryTallies or 0)+1
                end
            end
        end
    end
    return count,sections,type(scope)=='table' and scope.migrationConflictsOverflow==true
end

function Database.ChooseWorkshopDraft(choice)
    if choice~='legacy' and choice~='canonical' then return false,'invalid' end
    local scope,profile = CurrentWorkshopScope()
    if type(scope)~='table' or type(scope.migrationConflicts)~='table' or type(UnitName)~='function' then return false,'none' end
    local first,last=UnitName('player')
    if not IsValidText(first,1,128) then return false,'invalid' end
    local identity=first
    if IsValidText(last,1,128) then identity=first..' '..last end
    if not IsValidText(identity,1,128) then return false,'invalid' end
    local conflict=scope.migrationConflicts['orderDrafts\001'..identity]
    local selected=type(conflict)=='table' and conflict[choice]
    if type(selected)~='table' then return false,'none' end
    local drafts=EnsureTable(scope,'orderDrafts')
    conflict.beforeDraftChoice=DeepCopy(drafts[identity])
    drafts[identity]=DeepCopy(selected)
    conflict.resolved=true; conflict.selected=choice
    if type(OldKraken.Fire)=='function' then OldKraken:Fire('WORKSHOP_SCOPE_DRAFT_RESTORED',profile) end
    return true
end
