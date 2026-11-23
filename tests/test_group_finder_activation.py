from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def make_runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
        local listeners = {}
        local guildName = nil
        local printedErrors = {}
        local shownPage = nil
        createdFrames = {}

        OldKraken = {
            name = 'OldKraken',
            DB = { settings = { language = 'ukUA' }, groupFinder = {} },
            Database = { IsValidRealm = function(_, r) return type(r) == 'string' and #r > 0 end },
            Communication = {
                RegisterHandler = function() end,
                SendProtocol = function() return true end,
                RequestSync = function() return true end,
                ClearProtocolState = function() end,
                queue = {},
            },
            UIStyle = {
                Colors = {
                    brandGold = {0.88, 0.69, 0.32, 1},
                    mutedText = {0.6, 0.6, 0.6},
                    window = {0.025, 0.035, 0.055},
                    panel = {0.055, 0.07, 0.095},
                    panelEdge = {0.2, 0.25, 0.3},
                },
                Font = function() end,
                EmblemPath = function() return 'Interface\\\\AddOns\\\\OldKraken\\\\Media\\\\OldKrakenEmblem.tga' end,
            },
            UIHub = {
                frame = { IsShown = function() return false end },
                RegisterPage = function() end,
                ShowPage = function(_, page) shownPage = page end,
            },
            PrintError = function(_, msg) printedErrors[#printedErrors + 1] = msg end,
        }
        function OldKraken:On(event, fn)
            listeners[event] = listeners[event] or {}
            listeners[event][#listeners[event] + 1] = fn
        end
        function OldKraken:Fire(event, ...)
            for _, fn in ipairs(listeners[event] or {}) do fn(...) end
        end

        function SetGuildName(v) guildName = v end
        function GetPrintedErrors() return printedErrors end
        function GetShownPage() return shownPage end

        function GetServerTime() return 1700000000 end
        function GetTime() return 100 end
        function UnitName() return 'Leader', 'Tester' end
        function GetGuildInfo() return guildName end
        function GetRealmName() return 'Realm' end
        function UnitClass() return 'Warrior', 'WARRIOR' end
        function UnitLevel() return 60 end
        function IsInRaid() return false end
        function GetNumGroupMembers() return 0 end
        function GetNumPartyMembers() return 0 end
        C_GuildInfo = { GuildRoster = function() end }
        C_Timer = { NewTicker = function() end }
        StaticPopupDialogs = {}
        UIParent = {}

        local function dummyObj()
            local o = {}
            local mt = { __index = function(t, k)
                local fn = function() return dummyObj() end
                t[k] = fn
                return fn
            end }
            return setmetatable(o, mt)
        end

        function CreateFrame()
            local frame = {
                events = {},
                scripts = {},
                RegisterEvent = function(self, ev) self.events[ev] = true end,
                SetScript = function(self, name, fn) self.scripts[name] = fn end,
                HookScript = function() end,
                Hide = function() end,
                Show = function() end,
                IsShown = function() return false end,
                CreateTexture = function() return dummyObj() end,
                CreateFontString = function() return dummyObj() end,
            }
            createdFrames[#createdFrames + 1] = frame
            return frame
        end
    ''')
    for name in ('Locale.lua', 'ActivityCatalog.lua', 'GroupFinder.lua', 'GroupFinderIntegration.lua', 'GroupFinderUI.lua'):
        lua.execute((ROOT / name).read_text(encoding='utf-8'))
    return lua


# 1. Delayed guild info after PLAYER_LOGIN activates via PLAYER_ENTERING_WORLD / PLAYER_GUILD_UPDATE
lua1 = make_runtime()
lua1.execute('''
    for _, f in ipairs(createdFrames) do
        if f.scripts.OnEvent then f.scripts.OnEvent(f, 'PLAYER_LOGIN') end
    end
    assert(OldKraken.GroupFinder.active == false, 'Should stay inactive without guild')

    SetGuildName('Guild')
    for _, f in ipairs(createdFrames) do
        if f.events.PLAYER_ENTERING_WORLD and f.scripts.OnEvent then
            f.scripts.OnEvent(f, 'PLAYER_ENTERING_WORLD')
        end
    end
    assert(OldKraken.GroupFinder.active == true, 'Should activate on PLAYER_ENTERING_WORLD once guild is available')
''')

# 2. Clicking Communities/GroupFinder toggle before events fire connects on demand
lua2 = make_runtime()
lua2.execute('''
    SetGuildName('Guild')
    assert(not OldKraken.GroupFinder.active)
    OldKraken.GroupFinder:Toggle()
    assert(OldKraken.GroupFinder.active == true, 'Toggle/Show should connect on demand when guild is available')
    assert(GetShownPage() == 'groups', 'Should open groups page')
    assert(#GetPrintedErrors() == 0, 'Should not print uninitialized error when guild is available')
''')

# 3. Without a guild, Toggle still refuses cleanly with the uninitialized error
lua3 = make_runtime()
lua3.execute('''
    SetGuildName(nil)
    OldKraken.GroupFinder:Toggle()
    assert(not OldKraken.GroupFinder.active)
    assert(#GetPrintedErrors() == 1)
''')

print('GroupFinder activation checks passed')
