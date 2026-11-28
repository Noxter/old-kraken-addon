OldKraken = OldKraken or {}

local Module = {}
OldKraken.ItemLinkLocale = Module

local MAX_CACHE = 1024
local MAX_PENDING = 200
local PENDING_TTL = 30

local cache = {}
local cacheOrder = {}
local cacheHead = 1
local cacheTail = 0
local cacheCount = 0

local pendingItems = {}
local pendingOrderId = {}
local pendingOrderTs = {}
local pendingOrderSeq = {}
local pendingHead = 1
local pendingTail = 0
local pendingCount = 0
local pendingSeq = 0

local CHAT_EVENTS = {
    'CHAT_MSG_GUILD',
    'CHAT_MSG_OFFICER',
    'CHAT_MSG_PARTY',
    'CHAT_MSG_PARTY_LEADER',
    'CHAT_MSG_RAID',
    'CHAT_MSG_RAID_LEADER',
    'CHAT_MSG_RAID_WARNING',
    'CHAT_MSG_INSTANCE_CHAT',
    'CHAT_MSG_INSTANCE_CHAT_LEADER',
    'CHAT_MSG_WHISPER',
    'CHAT_MSG_WHISPER_INFORM',
    'CHAT_MSG_SAY',
    'CHAT_MSG_YELL',
    'CHAT_MSG_EMOTE',
    'CHAT_MSG_CHANNEL',
    'CHAT_MSG_BN_WHISPER',
    'CHAT_MSG_BN_WHISPER_INFORM',
    'CHAT_MSG_COMMUNITIES_CHANNEL',
    'CHAT_MSG_LOOT',
}

local function now()
    if type(GetTime) == 'function' then
        return GetTime()
    end
    return 0
end

local function isAccessibleString(value)
    if type(value) ~= 'string' then return false end
    if type(issecretvalue) == 'function' and issecretvalue(value) then return false end
    if type(canaccessvalue) == 'function' and not canaccessvalue(value) then return false end
    return true
end

local function isEnabled()
    local db = OldKraken and OldKraken.DB
    local settings = type(db) == 'table' and db.settings
    return type(settings) == 'table' and settings.localizeItemLinks == true
end

local function getItemInfoFn()
    if type(C_Item) == 'table' and type(C_Item.GetItemInfo) == 'function' then
        return C_Item.GetItemInfo
    end
    if type(GetItemInfo) == 'function' then
        return GetItemInfo
    end
    return nil
end

local function compactQueue(order, head, tail)
    local newTail = 0
    for i = head, tail do
        local v = order[i]
        order[i] = nil
        if v ~= nil then
            newTail = newTail + 1
            order[newTail] = v
        end
    end
    return 1, newTail
end

local function cachePut(key, name)
    if cache[key] ~= nil then
        cache[key] = name
        return
    end
    if cacheCount >= MAX_CACHE then
        local oldest = cacheOrder[cacheHead]
        cacheOrder[cacheHead] = nil
        cacheHead = cacheHead + 1
        if oldest ~= nil and cache[oldest] ~= nil then
            cache[oldest] = nil
            cacheCount = cacheCount - 1
        end
        if cacheCount == 0 then
            cacheHead = 1
            cacheTail = 0
        elseif cacheHead > MAX_CACHE * 4 then
            cacheHead, cacheTail = compactQueue(cacheOrder, cacheHead, cacheTail)
        end
    end
    cache[key] = name
    cacheTail = cacheTail + 1
    cacheOrder[cacheTail] = key
    cacheCount = cacheCount + 1
end

local function compactPendingQueue()
    local newTail = 0
    for i = pendingHead, pendingTail do
        local id = pendingOrderId[i]
        local ts = pendingOrderTs[i]
        local seq = pendingOrderSeq[i]
        pendingOrderId[i] = nil
        pendingOrderTs[i] = nil
        pendingOrderSeq[i] = nil
        if id ~= nil and pendingItems[id] == seq then
            newTail = newTail + 1
            pendingOrderId[newTail] = id
            pendingOrderTs[newTail] = ts
            pendingOrderSeq[newTail] = seq
        end
    end
    return 1, newTail
end

local function purgeExpiredPending(currentTime)
    while pendingHead <= pendingTail do
        local id = pendingOrderId[pendingHead]
        local entryTs = pendingOrderTs[pendingHead]
        local entrySeq = pendingOrderSeq[pendingHead]
        if id == nil or pendingItems[id] ~= entrySeq then
            pendingOrderId[pendingHead] = nil
            pendingOrderTs[pendingHead] = nil
            pendingOrderSeq[pendingHead] = nil
            pendingHead = pendingHead + 1
        elseif currentTime > 0 and entryTs > 0 and (currentTime - entryTs) >= PENDING_TTL then
            pendingOrderId[pendingHead] = nil
            pendingOrderTs[pendingHead] = nil
            pendingOrderSeq[pendingHead] = nil
            pendingHead = pendingHead + 1
            pendingItems[id] = nil
            pendingCount = pendingCount > 0 and (pendingCount - 1) or 0
        else
            break
        end
    end
    if pendingCount == 0 then
        pendingHead = 1
        pendingTail = 0
    elseif pendingHead > MAX_PENDING * 4 then
        pendingHead, pendingTail = compactPendingQueue()
    end
end

local function clearPending(id)
    if pendingItems[id] == nil then return end
    pendingItems[id] = nil
    pendingCount = pendingCount > 0 and (pendingCount - 1) or 0
end

local function requestItemLoad(id)
    if type(C_Item) ~= 'table' or type(C_Item.RequestLoadItemDataByID) ~= 'function' then return false end
    local currentTime = now()
    purgeExpiredPending(currentTime)
    if pendingItems[id] ~= nil or pendingCount >= MAX_PENDING then return false end
    pendingSeq = pendingSeq + 1
    local seq = pendingSeq
    pendingItems[id] = seq
    pendingTail = pendingTail + 1
    pendingOrderId[pendingTail] = id
    pendingOrderTs[pendingTail] = currentTime
    pendingOrderSeq[pendingTail] = seq
    pendingCount = pendingCount + 1
    local ok = pcall(C_Item.RequestLoadItemDataByID, id)
    if not ok then
        clearPending(id)
        return false
    end
    return true
end

local function parseItemPayload(data)
    if not isAccessibleString(data) or data == '' then return nil, nil end
    local _, colonCount = data:gsub(':', ':')
    if colonCount < 7 then return nil, nil end
    if not data:match('^[%d:%-]+$') then return nil, nil end
    local fieldIndex = 0
    local id = nil
    local f7 = 0
    for part in (data .. ':'):gmatch('([^:]*):') do
        fieldIndex = fieldIndex + 1
        if part ~= '' and not part:match('^%-?%d+$') then
            return nil, nil
        end
        if fieldIndex == 1 then
            id = tonumber(part)
            if not id or id <= 0 or id % 1 ~= 0 then
                return nil, nil
            end
        elseif fieldIndex == 7 then
            f7 = tonumber(part) or 0
        end
    end
    return id, f7
end

local function resolveItemName(id)
    local fn = getItemInfoFn()
    if not fn then return nil end
    local ok, name = pcall(fn, id)
    if ok and isAccessibleString(name) and name ~= '' then
        return name
    end
    requestItemLoad(id)
    return nil
end

function Module:LocalizeMessage(message)
    if not isAccessibleString(message) or not message:find('|Hitem:', 1, true) then
        return nil
    end
    local seen = {}
    local changed = false
    local out = message:gsub('(|Hitem:([^|]*)|h%[)(.-)(%]|h)', function(head, data, oldName, tail)
        if not isAccessibleString(oldName) then return nil end
        local id, f7 = parseItemPayload(data)
        if not id or f7 ~= 0 then return nil end
        local name = seen[id]
        if name == nil then
            name = cache[id]
            if name == nil then
                name = resolveItemName(id)
                if name then
                    cachePut(id, name)
                else
                    seen[id] = false
                    return nil
                end
            end
            seen[id] = name
        elseif name == false then
            return nil
        end
        if name == oldName then return nil end
        changed = true
        return head .. name .. tail
    end)
    return changed and out or nil
end

local function filterChat(_, _, message, ...)
    if not isEnabled() then return false end
    if not isAccessibleString(message) or not message:find('|Hitem:', 1, true) then
        return false
    end
    local localized = Module:LocalizeMessage(message)
    if localized then
        return false, localized, ...
    end
    return false
end

local registeredEvents = {}
local function registerFilter()
    local modern = type(ChatFrameUtil) == 'table' and ChatFrameUtil.AddMessageEventFilter
    local legacy = type(ChatFrame_AddMessageEventFilter) == 'function' and ChatFrame_AddMessageEventFilter or nil
    for _, event in ipairs(CHAT_EVENTS) do
        if not registeredEvents[event] then
            local ok = false
            if type(modern) == 'function' then
                ok = pcall(modern, event, filterChat)
            end
            if not ok and legacy then
                ok = pcall(legacy, event, filterChat)
            end
            if ok then
                registeredEvents[event] = true
            end
        end
    end
end

registerFilter()

local frame = CreateFrame('Frame')
frame:RegisterEvent('PLAYER_LOGIN')
pcall(frame.RegisterEvent, frame, 'GET_ITEM_INFO_RECEIVED')
pcall(frame.RegisterEvent, frame, 'ITEM_DATA_LOAD_RESULT')
frame:SetScript('OnEvent', function(_, event, id)
    if event == 'PLAYER_LOGIN' then
        registerFilter()
    elseif event == 'GET_ITEM_INFO_RECEIVED' or event == 'ITEM_DATA_LOAD_RESULT' then
        clearPending(id)
    end
end)
