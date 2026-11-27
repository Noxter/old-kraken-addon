-- Highlight and format Old Kraken group announcements in the local guild chat.
local T = OldKraken and OldKraken.Translate or function(text) return text end
local GOLD = '|cffe0b052'
local MUTED = '|cff9aa4b2'
local CREAM = '|cfff3ebd3'
local TEAL = '|cff2ec4b6'

local function stripTrailingTag(text)
    local trimmed = text:gsub('^%s*{rt8}%s*', ''):gsub('^%s*|TInterface/TargetingFrame/UI%-RaidTargetingIcon_8:0|t%s*', '')
    for _, tag in ipairs({
        ' — Old Kraken',
        ' »»» Old Kraken · Групи {rt8}',
        ' »»» Old Kraken · Groups {rt8}',
        ' »»» Old Kraken · Групи',
        ' »»» Old Kraken · Groups',
    }) do
        if trimmed:sub(-#tag) == tag then
            return trimmed:sub(1, #trimmed - #tag)
        end
    end
    return nil
end

local function splitMiddleDot(text)
    local parts = {}
    local sep = ' · '
    local pos = 1
    while true do
        local startIdx, endIdx = text:find(sep, pos, true)
        if not startIdx then
            parts[#parts + 1] = text:sub(pos)
            break
        end
        parts[#parts + 1] = text:sub(pos, startIdx - 1)
        pos = endIdx + 1
    end
    return parts
end

local EVENT_PREFIXES = {
    '[Old Kraken] Івент: ',
    '[Old Kraken] Event: ',
    '[Old Kraken] Новий івент: ',
    '[Old Kraken] New event: ',
}
local EVENT_TAILS = {
    ' — /okr',
    ' — запис у вкладці «Івенти» (/okr).',
    ' — sign up under Events (/okr).',
}

local function formatEventAnnouncement(message)
    local body
    for _, prefix in ipairs(EVENT_PREFIXES) do
        if message:sub(1, #prefix) == prefix then
            body = message:sub(#prefix + 1)
            break
        end
    end
    if not body or body == '' then return nil end
    for _, tail in ipairs(EVENT_TAILS) do
        if body:sub(-#tail) == tail then
            body = body:sub(1, #body - #tail)
            break
        end
    end
    if body == '' then return nil end
    local parts = splitMiddleDot(body)
    local out = { TEAL .. '[Old Kraken] ' .. MUTED .. T('Івент:') .. ' |r' .. GOLD .. parts[1] .. '|r' }
    for i = 2, #parts do
        out[#out + 1] = MUTED .. ' · |r' .. CREAM .. parts[i] .. '|r'
    end
    local link = TEAL .. '|Holdkraken:events|h' .. T('[Відкрити івенти]') .. '|h|r'
    return table.concat(out) .. ' ' .. link
end

local function formatAnnouncement(message)
    local link = TEAL .. '|Holdkraken:groups|h' .. T('[Відкрити групи]') .. '|h|r'
    if message:find('LFG ', 1, true) then
        local body = stripTrailingTag(message)
        if body and body:sub(1, 4) == 'LFG ' then
            local parts = splitMiddleDot(body)
            local out = { GOLD .. parts[1] .. '|r' }
            for i = 2, #parts do
                local part = parts[i]
                local color = (part:sub(1, 4) == 'lvl ') and MUTED or CREAM
                out[#out + 1] = MUTED .. ' · |r' .. color .. part .. '|r'
            end
            return table.concat(out) .. ' ' .. link
        end
    end
    local ukrainian = '[Old Kraken] Збір групи: '
    local english = '[Old Kraken] Forming a group: '
    if message:sub(1, #ukrainian) == ukrainian or message:sub(1, #english) == english then
        return GOLD .. message .. '|r ' .. link
    end
    return formatEventAnnouncement(message)
end

local function highlightGroupChat(_, event, message, ...)
    if event ~= 'CHAT_MSG_GUILD'
        or (type(issecretvalue) == 'function' and issecretvalue(message))
        or (type(canaccessvalue) == 'function' and not canaccessvalue(message))
        or type(message) ~= 'string' then return false end
    local formatted = formatAnnouncement(message)
    if not formatted then return false end
    return false, formatted, ...
end

local linkHooked = false
local function registerLinkHook()
    if linkHooked then return end
    if type(hooksecurefunc) == 'function' and type(SetItemRef) == 'function' then
        linkHooked = pcall(hooksecurefunc, 'SetItemRef', function(link)
            if link == 'oldkraken:groups' and OldKraken and OldKraken.GroupFinder
                and type(OldKraken.GroupFinder.Show) == 'function' then
                OldKraken.GroupFinder:Show('all')
            elseif link == 'oldkraken:events' and OldKraken and OldKraken.GuildEvents
                and type(OldKraken.GuildEvents.Show) == 'function' then
                OldKraken.GuildEvents:Show()
            end
        end)
    end
end

local registered = false
local function registerFilter()
    registerLinkHook()
    if registered then return end
    local modern = type(ChatFrameUtil) == 'table' and ChatFrameUtil.AddMessageEventFilter
    if type(modern) == 'function' then registered = pcall(modern, 'CHAT_MSG_GUILD', highlightGroupChat) end
    if not registered and type(ChatFrame_AddMessageEventFilter) == 'function' then
        registered = pcall(ChatFrame_AddMessageEventFilter, 'CHAT_MSG_GUILD', highlightGroupChat)
    end
end

registerFilter()
local frame = CreateFrame('Frame')
frame:RegisterEvent('PLAYER_LOGIN')
frame:SetScript('OnEvent', registerFilter)
