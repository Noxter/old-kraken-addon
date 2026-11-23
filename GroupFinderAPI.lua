local T = OldKraken.Translate or function(text) return text end
-- Read-only capability probe for the native WoW Group Finder API.
-- This module deliberately does not start searches or create/update listings.
OldKraken = OldKraken or {}

local API = {}
OldKraken.GroupFinderAPI = API

local METHOD_NAMES = {
    "GetAvailableCategories",
    "GetAvailableActivities",
    "GetActivityInfoTable",
    "Search",
    "GetSearchResults",
    "GetSearchResultInfo",
    "GetSearchResultPlayerInfo",
    "ApplyToGroup",
    "RequestToJoin",
    "CreateListing",
    "UpdateListing",
    "IsPremadeGroupFinderEnabled",
}

local MAX_PREVIEW = 24

local function collectIDs(namespace, methodName)
    local method = namespace and namespace[methodName]
    if type(method) ~= "function" then
        return nil, T("недоступний")
    end

    local ok, result = pcall(method)
    if not ok then
        return nil, tostring(result)
    end
    if type(result) ~= "table" then
        return nil, T("повернув ") .. type(result)
    end

    local ids = {}
    for _, value in pairs(result) do
        if type(value) == "number" and value % 1 == 0 then
            ids[#ids + 1] = value
        end
    end
    table.sort(ids)
    return ids
end

local function previewIDs(ids)
    if not ids then
        return "-"
    end

    local values = {}
    for index = 1, math.min(#ids, MAX_PREVIEW) do
        values[#values + 1] = tostring(ids[index])
    end
    if #ids > MAX_PREVIEW then
        values[#values + 1] = "… +" .. tostring(#ids - MAX_PREVIEW)
    end
    return table.concat(values, ", ")
end

function API:GetStatus()
    local lfg = C_LFGList
    local status = {
        namespace = type(lfg),
        infoNamespace = type(C_LFGInfo),
        frame = type(LFGListFrame),
        methods = {},
    }

    if type(lfg) == "table" then
        for _, methodName in ipairs(METHOD_NAMES) do
            status.methods[methodName] = type(lfg[methodName])
        end
        status.categories, status.categoryError = collectIDs(lfg, "GetAvailableCategories")
        status.activities, status.activityError = collectIDs(lfg, "GetAvailableActivities")
    end

    local chatInfo = C_ChatInfo
    if type(chatInfo) == "table"
        and type(chatInfo.AreOutgoingAddonChatMessagesRestricted) == "function" then
        local ok, restricted = pcall(chatInfo.AreOutgoingAddonChatMessagesRestricted)
        if ok and type(restricted) == "boolean" then
            status.addonMessagesRestricted = restricted
        end
    end

    return status
end

function API:PrintStatus()
    local status = self:GetStatus()

    local function line(message)
        if OldKraken.Print then
            OldKraken:Print(message)
        else
            print("|cff2ec4b6Old Kraken|r: " .. tostring(message or ""))
        end
    end

    line(T("Native Group Finder API — лише діагностика; пошук і створення не запускаються."))
    line("C_LFGList: " .. status.namespace
        .. "; C_LFGInfo: " .. status.infoNamespace
        .. "; LFGListFrame: " .. status.frame)

    if status.namespace == "table" then
        for _, methodName in ipairs(METHOD_NAMES) do
            line(methodName .. ": " .. (status.methods[methodName] or "nil"))
        end

        if status.categories then
            line(T("Категорії: ") .. #status.categories .. " [" .. previewIDs(status.categories) .. "]")
        else
            line(T("Категорії: ") .. (status.categoryError or T("не перевірено")))
        end

        if status.activities then
            line(T("Активності: ") .. #status.activities .. " [" .. previewIDs(status.activities) .. "]")
        else
            line(T("Активності: ") .. (status.activityError or T("не перевірено")))
        end
    end

    local restriction
    if status.addonMessagesRestricted == nil then
        restriction = T("невідомо")
    elseif status.addonMessagesRestricted then
        restriction = T("так")
    else
        restriction = T("ні")
    end
    line("AreOutgoingAddonChatMessagesRestricted: " .. restriction)
    line(T("Search / CreateListing / UpdateListing не викликалися."))
    return status
end

function API:HandleCommand(command)
    if command ~= "group api" then
        return false
    end

    self:PrintStatus()
    return true
end
