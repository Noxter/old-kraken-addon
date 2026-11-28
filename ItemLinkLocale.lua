OldKraken = OldKraken or {}

local Module = {}
OldKraken.ItemLinkLocale = Module

local MAX_CACHE = 1024
local MAX_PENDING = 200
local PENDING_TTL = 30
local MAX_LATE = 200
local LATE_TTL = 120

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

local lateItems = {}
local lateOrderId = {}
local lateOrderTs = {}
local lateOrderSeq = {}
local lateHead = 1
local lateTail = 0
local lateCount = 0
local lateSeq = 0
local lateTimer = false

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

local function compactTokenQueue(items, orderId, orderTs, orderSeq, head, tail)
    local newTail = 0
    for i = head, tail do
        local id = orderId[i]
        local ts = orderTs[i]
        local seq = orderSeq[i]
        orderId[i] = nil
        orderTs[i] = nil
        orderSeq[i] = nil
        if id ~= nil and items[id] == seq then
            newTail = newTail + 1
            orderId[newTail] = id
            orderTs[newTail] = ts
            orderSeq[newTail] = seq
        end
    end
    return 1, newTail
end

local function purgeTokenQueue(items, orderId, orderTs, orderSeq, head, tail, count, maxCount, ttl, currentTime)
    while head <= tail do
        local id = orderId[head]
        local entryTs = orderTs[head]
        local entrySeq = orderSeq[head]
        if id == nil or items[id] ~= entrySeq then
            orderId[head] = nil
            orderTs[head] = nil
            orderSeq[head] = nil
            head = head + 1
        elseif currentTime > 0 and entryTs > 0 and (currentTime - entryTs) >= ttl then
            orderId[head] = nil
            orderTs[head] = nil
            orderSeq[head] = nil
            head = head + 1
            items[id] = nil
            count = count > 0 and (count - 1) or 0
        else
            break
        end
    end
    if count == 0 then
        head = 1
        tail = 0
    elseif head > maxCount * 4 then
        head, tail = compactTokenQueue(items, orderId, orderTs, orderSeq, head, tail)
    end
    return head, tail, count
end

local function purgeExpiredPending(currentTime)
    pendingHead, pendingTail, pendingCount = purgeTokenQueue(
        pendingItems, pendingOrderId, pendingOrderTs, pendingOrderSeq,
        pendingHead, pendingTail, pendingCount, MAX_PENDING, PENDING_TTL, currentTime
    )
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
    if pendingItems[id] ~= nil then return true end
    if pendingCount >= MAX_PENDING then return false end
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

local function purgeExpiredLate(currentTime)
    lateHead, lateTail, lateCount = purgeTokenQueue(
        lateItems, lateOrderId, lateOrderTs, lateOrderSeq,
        lateHead, lateTail, lateCount, MAX_LATE, LATE_TTL, currentTime
    )
end

local function clearLate(id)
    if lateItems[id] == nil then return end
    lateItems[id] = nil
    lateCount = lateCount > 0 and (lateCount - 1) or 0
end

local function markLate(id)
    local currentTime = now()
    purgeExpiredLate(currentTime)
    if lateItems[id] ~= nil or lateCount >= MAX_LATE then return false end
    lateSeq = lateSeq + 1
    local seq = lateSeq
    lateItems[id] = seq
    lateTail = lateTail + 1
    lateOrderId[lateTail] = id
    lateOrderTs[lateTail] = currentTime
    lateOrderSeq[lateTail] = seq
    lateCount = lateCount + 1
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

local function resolveItemName(id, noRequest)
    local fn = getItemInfoFn()
    if not fn then return nil end
    local ok, name = pcall(fn, id)
    if ok and isAccessibleString(name) and name ~= '' then
        return name
    end
    if not noRequest and requestItemLoad(id) then
        markLate(id)
    end
    return nil
end

function Module:LocalizeMessage(message, noRequest)
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
                name = resolveItemName(id, noRequest)
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

local function fixShown()
    lateTimer = false
    if not isEnabled() or lateCount == 0 then return end
    purgeExpiredLate(now())
    if lateCount == 0 then return end
    local doneIds = {}
    local doneSet = {}
    for id in pairs(lateItems) do
        local name = cache[id] or resolveItemName(id, true)
        if name then
            cachePut(id, name)
            doneIds[#doneIds + 1] = id
            doneSet[id] = true
        end
    end
    for _, id in ipairs(doneIds) do
        clearLate(id)
    end
    if #doneIds == 0 then return end

    local function has(entry)
        if type(entry) ~= 'table' or not isAccessibleString(entry.message) then return false end
        if not entry.message:find('|Hitem:', 1, true) then return false end
        for idStr in entry.message:gmatch('|Hitem:(%d+):') do
            local id = tonumber(idStr)
            if id and doneSet[id] then return true end
        end
        return false
    end

    local function fix(entry)
        if type(entry) ~= 'table' or not isAccessibleString(entry.message) then return end
        local localized = Module:LocalizeMessage(entry.message, true)
        if localized then
            entry.message = localized
        end
    end

    local numWindows = tonumber(NUM_CHAT_WINDOWS) or 10
    for i = 1, numWindows do
        local chatFrame = _G and _G['ChatFrame' .. i]
        if type(chatFrame) == 'table' and type(chatFrame.TransformMessages) == 'function' then
            pcall(chatFrame.TransformMessages, chatFrame, has, fix)
        end
    end
end

local function scheduleFix()
    if lateTimer or lateCount == 0 then return end
    if type(C_Timer) ~= 'table' or type(C_Timer.After) ~= 'function' then return end
    lateTimer = true
    C_Timer.After(0.25, fixShown)
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
frame:SetScript('OnEvent', function(_, event, id, success)
    if event == 'PLAYER_LOGIN' then
        registerFilter()
    elseif event == 'GET_ITEM_INFO_RECEIVED' or event == 'ITEM_DATA_LOAD_RESULT' then
        clearPending(id)
        if success == false then
            clearLate(id)
        elseif lateItems[id] ~= nil and isEnabled() then
            scheduleFix()
        end
    end
end)
