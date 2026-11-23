-- Highlight the text of Old Kraken group announcements in the local guild chat.
local GOLD = '|cffffd34d'

local function groupAnnouncement(message)
    if message:find('LFG ', 1, true) then
        if message:find(' »»» Old Kraken · Групи', 1, true)
            or message:find(' »»» Old Kraken · Groups', 1, true) then return true end
    end
    local ukrainian = '[Old Kraken] Збір групи: '
    local english = '[Old Kraken] Forming a group: '
    return message:sub(1, #ukrainian) == ukrainian or message:sub(1, #english) == english
end

local function highlightGroupChat(_, event, message, ...)
    if event ~= 'CHAT_MSG_GUILD'
        or (type(issecretvalue) == 'function' and issecretvalue(message))
        or (type(canaccessvalue) == 'function' and not canaccessvalue(message))
        or type(message) ~= 'string' or not groupAnnouncement(message) then return false end
    return false, GOLD .. message .. '|r', ...
end

local registered = false
local function registerFilter()
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
