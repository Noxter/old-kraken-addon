from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MINIMAP = (ROOT / 'Minimap.lua').read_text(encoding='utf-8')


def run_minimap_env(preloaded_communities=False, use_c_addons=True, show_minimap=True):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals()._preloaded = preloaded_communities
    lua.globals()._use_c_addons = use_c_addons
    lua.globals()._show_minimap = show_minimap
    lua.execute('''
        frames = {}
        events = {}
        listeners = {}
        rosterToggles = 0
        finderToggles = 0
        local function makeFrame(kind, name, parent)
            local f = {
                kind = kind,
                name = name,
                parent = parent,
                shown = true,
                scripts = {},
                registered = {},
                points = {},
            }
            function f:SetSize(w, h) self.w = w; self.h = h end
            function f:SetFrameStrata() end
            function f:SetFrameLevel() end
            function f:GetFrameStrata() return 'MEDIUM' end
            function f:GetFrameLevel() return 1 end
            function f:RegisterForClicks() end
            function f:RegisterForDrag() end
            function f:EnableMouse() end
            function f:SetHighlightTexture() end
            function f:ClearAllPoints() self.points = {} end
            function f:SetPoint(...) self.points[#self.points + 1] = {...} end
            function f:GetPoint() return 'TOPLEFT' end
            function f:GetWidth() return 140 end
            function f:GetHeight() return 140 end
            function f:GetCenter() return 100, 100 end
            function f:GetEffectiveScale() return 1 end
            function f:Show() self.shown = true end
            function f:Hide() self.shown = false end
            function f:IsShown() return self.shown end
            function f:RegisterEvent(ev) self.registered[ev] = true end
            function f:UnregisterEvent(ev) self.registered[ev] = nil end
            function f:SetScript(k, fn) self.scripts[k] = fn end
            function f:CreateTexture()
                return {
                    SetTexture = function() end,
                    SetPoint = function() end,
                    SetSize = function() end,
                    SetWidth = function() end,
                    SetHeight = function() end,
                    SetVertexColor = function() end,
                    SetAllPoints = function() end,
                    SetColorTexture = function() end,
                    Show = function() end,
                    Hide = function() end,
                }
            end
            if name then _G[name] = f end
            frames[#frames + 1] = f
            return f
        end
        CreateFrame = makeFrame
        Minimap = makeFrame('Frame', 'Minimap')
        OldKraken = {
            DB = { settings = { minimapAngle = 225, showMinimapButton = _show_minimap } },
            UIStyle = {
                Colors = { window = {0.025, 0.035, 0.055, 1}, brandGold = {0.88, 0.69, 0.32, 1} },
                EmblemPath = function() return 'Interface\\\\AddOns\\\\OldKraken\\\\Media\\\\OldKrakenEmblem.tga' end,
            },
            GuildRoster = { Toggle = function() rosterToggles = rosterToggles + 1 end },
            GroupFinder = { Toggle = function() finderToggles = finderToggles + 1 end },
        }
        function OldKraken:On(ev, fn)
            listeners[ev] = listeners[ev] or {}
            listeners[ev][#listeners[ev] + 1] = fn
        end
        function OldKraken:Fire(ev, ...)
            for _, fn in ipairs(listeners[ev] or {}) do fn(...) end
        end
        if _preloaded then
            CommunitiesFrame = makeFrame('Frame', 'CommunitiesFrame')
            CommunitiesFrame.GuildInfoTab = makeFrame('Button', nil, CommunitiesFrame)
        end
        if _use_c_addons then
            C_AddOns = { IsAddOnLoaded = function(name) return name == 'Blizzard_Communities' and _preloaded end }
        else
            IsAddOnLoaded = function(name) return name == 'Blizzard_Communities' and _preloaded end
        end
    ''')
    lua.execute(MINIMAP)
    return lua


# 1. Minimap button respects showMinimapButton=false on INITIALIZED and toggles via MINIMAP_BUTTON_SETTING
lua = run_minimap_env(preloaded_communities=False, show_minimap=False)
lua.execute('''
    OldKraken:Fire('INITIALIZED', OldKraken.DB)
    assert(OldKrakenMinimapButton ~= nil)
    assert(OldKrakenMinimapButton:IsShown() == false, 'minimap button must start hidden when showMinimapButton=false')
    OldKraken.DB.settings.showMinimapButton = true
    OldKraken:Fire('MINIMAP_BUTTON_SETTING')
    assert(OldKrakenMinimapButton:IsShown() == true, 'minimap button must show after enabling setting')
    OldKraken.DB.settings.showMinimapButton = false
    OldKraken:Fire('MINIMAP_BUTTON_SETTING')
    assert(OldKrakenMinimapButton:IsShown() == false, 'minimap button must hide after disabling setting')
''')

# 2. Preloaded Blizzard_Communities attaches once next to GuildInfoTab and toggles Roster/Finder
lua_pre = run_minimap_env(preloaded_communities=True, use_c_addons=True)
lua_pre.execute('''
    assert(OldKrakenCommunitiesButton ~= nil, 'button must attach when Blizzard_Communities is already loaded')
    assert(OldKrakenCommunitiesButton.points[1][2] == CommunitiesFrame.GuildInfoTab)
    OldKrakenCommunitiesButton.scripts.OnClick(OldKrakenCommunitiesButton, 'LeftButton')
    OldKrakenCommunitiesButton.scripts.OnClick(OldKrakenCommunitiesButton, 'RightButton')
    assert(rosterToggles == 1 and finderToggles == 1)
''')

# 3. Deferred Blizzard_Communities via ADDON_LOADED (global IsAddOnLoaded fallback), unregisters after attach
lua_def = run_minimap_env(preloaded_communities=False, use_c_addons=False)
lua_def.execute('''
    assert(OldKrakenCommunitiesButton == nil)
    local loader
    for _, f in ipairs(frames) do
        if f.registered['ADDON_LOADED'] then loader = f; break end
    end
    assert(loader ~= nil, 'must register ADDON_LOADED when CommunitiesFrame is not loaded yet')
    loader.scripts.OnEvent(loader, 'ADDON_LOADED', 'SomeOtherAddon')
    assert(OldKrakenCommunitiesButton == nil and loader.registered['ADDON_LOADED'] == true)
    CommunitiesFrame = CreateFrame('Frame', 'CommunitiesFrame')
    loader.scripts.OnEvent(loader, 'ADDON_LOADED', 'Blizzard_Communities')
    assert(OldKrakenCommunitiesButton ~= nil, 'button must attach on Blizzard_Communities ADDON_LOADED')
    assert(loader.registered['ADDON_LOADED'] == nil, 'must unregister ADDON_LOADED after attaching')
    assert(OldKrakenCommunitiesButton.points[1][2] == CommunitiesFrame)
''')

print('Minimap and Communities checks passed')
