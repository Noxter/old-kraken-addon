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
