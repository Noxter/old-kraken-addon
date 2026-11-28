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

# 4. LibDataBroker-1.1 + LibDBIcon-1.0: deferred button creation when hide=true, visibility sync, groupIndicator, click/tooltip, angle migration
lua_ldb = LuaRuntime(unpack_returned_tuples=True)
lua_ldb.execute('''
    listeners = {}
    rosterToggles = 0
    finderToggles = 0
    ldbObjects = {}
    libDBIconCalls = {}
    libDBIconShown = true
    createdLdbButton = nil
    local function makeLdbButton()
        return {
            textures = {},
            CreateTexture = function(self)
                local t = {
                    SetTexture = function(s, path) s.texture = path end,
                    SetPoint = function() end,
                    SetSize = function() end,
                    Show = function(s) s.shown = true end,
                    Hide = function(s) s.shown = false end,
                }
                self.textures[#self.textures + 1] = t
                return t
            end,
        }
    end
    local broker = {
        NewDataObject = function(_, name, obj)
            ldbObjects[name] = obj
            return obj
        end,
    }
    local libIcon = {
        Register = function(_, name, obj, dbTable)
            libDBIconCalls[#libDBIconCalls + 1] = { op = 'Register', name = name, obj = obj, db = dbTable }
            libDBIconShown = not dbTable.hide
            if not dbTable.hide then createdLdbButton = makeLdbButton() end
        end,
        Show = function(_, name)
            libDBIconCalls[#libDBIconCalls + 1] = { op = 'Show', name = name }
            libDBIconShown = true
            if not createdLdbButton then createdLdbButton = makeLdbButton() end
        end,
        Hide = function(_, name)
            libDBIconCalls[#libDBIconCalls + 1] = { op = 'Hide', name = name }
            libDBIconShown = false
        end,
        GetMinimapButton = function() return createdLdbButton end,
    }
    LibStub = setmetatable({}, {
        __call = function(_, name)
            if name == 'LibDataBroker-1.1' then return broker end
            if name == 'LibDBIcon-1.0' then return libIcon end
            return nil
        end,
    })
    function CreateFrame() return { RegisterEvent = function() end, SetScript = function() end } end
    function UnitLevel() return 25 end
    Minimap = nil
    OldKraken = {
        DB = { settings = { minimapAngle = 180, showMinimapButton = false } },
        UIStyle = {
            Colors = { window = {0.025, 0.035, 0.055, 1}, brandGold = {0.88, 0.69, 0.32, 1} },
            EmblemPath = function() return 'Interface\\\\AddOns\\\\OldKraken\\\\Media\\\\OldKrakenKraken.tga' end,
        },
        GuildRoster = { Toggle = function() rosterToggles = rosterToggles + 1 end },
        GroupFinder = {
            active = true,
            identity = 'Me',
            groups = {
                g1 = {
                    owner = 'Other', closed = false, hidden = false,
                    members = {'Other'}, maxSize = 5, minLevel = 20, maxLevel = 30,
                },
            },
            CanPerformRole = function() return true end,
            RoleAvailable = function() return true end,
            Toggle = function() finderToggles = finderToggles + 1 end,
        },
    }
    function OldKraken:On(ev, fn)
        listeners[ev] = listeners[ev] or {}
        listeners[ev][#listeners[ev] + 1] = fn
    end
    function OldKraken:Fire(ev, ...)
        for _, fn in ipairs(listeners[ev] or {}) do fn(...) end
    end
''')
lua_ldb.execute(MINIMAP)
lua_ldb.execute('''
    OldKraken:Fire('INITIALIZED', OldKraken.DB)
    assert(OldKrakenMinimapButton == nil, 'must not create fallback button when LibDBIcon is available')
    assert(ldbObjects.OldKraken ~= nil, 'must register LibDataBroker launcher object')
    assert(ldbObjects.OldKraken.type == 'launcher')
    assert(OldKraken.DB.settings.minimap.minimapPos == 180, 'must migrate minimapAngle into minimap.minimapPos')
    assert(OldKraken.DB.settings.minimap.hide == true and libDBIconShown == false)
    assert(createdLdbButton == nil, 'button is deferred while hide=true')

    OldKraken.DB.settings.showMinimapButton = true
    OldKraken:Fire('MINIMAP_BUTTON_SETTING')
    assert(OldKraken.DB.settings.minimap.hide == false and libDBIconShown == true)
    assert(createdLdbButton ~= nil and createdLdbButton.groupIndicator ~= nil, 'must attach groupIndicator after deferred Show')
    assert(createdLdbButton.groupIndicator.shown == true, 'must immediately show groupIndicator when matching groups exist')

    OldKraken.DB.settings.showMinimapButton = false
    OldKraken:Fire('MINIMAP_BUTTON_SETTING')
    assert(OldKraken.DB.settings.minimap.hide == true and libDBIconShown == false)

    ldbObjects.OldKraken.OnClick(nil, 'LeftButton')
    ldbObjects.OldKraken.OnClick(nil, 'RightButton')
    assert(rosterToggles == 1 and finderToggles == 1)

    local tipLines = {}
    local tip = {
        SetText = function(_, text) tipLines[#tipLines + 1] = text end,
        AddLine = function(_, text) tipLines[#tipLines + 1] = text end,
    }
    ldbObjects.OldKraken.OnTooltipShow(tip)
    assert(#tipLines >= 5, 'OnTooltipShow must populate tooltip lines including matching groups')
''')

# 5. LibDBIcon:Register error safely falls back to standalone button
lua_err = run_minimap_env(preloaded_communities=False, show_minimap=True)
lua_err.execute('''
    LibStub = setmetatable({}, {
        __call = function(_, name)
            if name == 'LibDataBroker-1.1' then
                return { NewDataObject = function(_, _, obj) return obj end }
            end
            if name == 'LibDBIcon-1.0' then
                return { Register = function() error('duplicate registration') end }
            end
            return nil
        end,
    })
    OldKraken:Fire('INITIALIZED', OldKraken.DB)
    assert(OldKrakenMinimapButton ~= nil, 'must fall back to own button when LibDBIcon:Register errors')
''')

# 6. Legacy profile migration when minimapPos and minimapAngle differ
# 6a. Fallback mode (no LibDBIcon): legacy minimapAngle wins once and syncs minimap.minimapPos
lua_legacy_fb = run_minimap_env(preloaded_communities=False, show_minimap=True)
lua_legacy_fb.execute('''
    OldKraken.DB.settings.minimapAngle = 120
    OldKraken.DB.settings.minimap = { minimapPos = 45 }
    OldKraken:Fire('INITIALIZED', OldKraken.DB)
    assert(OldKraken.DB.settings.minimap.minimapPos == 120, 'legacy fallback profile must sync minimapAngle -> minimapPos')
    assert(OldKraken.DB.settings.minimapPositionSynced == true)
    local pt = OldKrakenMinimapButton.points[1]
    local expectedX = math.cos(math.rad(120)) * (140 / 2 + 5)
    local expectedY = math.sin(math.rad(120)) * (140 / 2 + 5)
    assert(math.abs(pt[4] - expectedX) < 1e-6 and math.abs(pt[5] - expectedY) < 1e-6)
''')

# 6b. Already-synced profile (e.g. LibDBIcon updated minimapPos after migration): fallback must NOT overwrite minimapPos
lua_synced_fb = run_minimap_env(preloaded_communities=False, show_minimap=True)
lua_synced_fb.execute('''
    OldKraken.DB.settings.minimapPositionSynced = true
    OldKraken.DB.settings.minimapAngle = 120
    OldKraken.DB.settings.minimap = { minimapPos = 200 }
    OldKraken:Fire('INITIALIZED', OldKraken.DB)
    assert(OldKraken.DB.settings.minimap.minimapPos == 200, 'already-synced profile must preserve minimapPos')
    local pt = OldKrakenMinimapButton.points[1]
    local expectedX = math.cos(math.rad(200)) * (140 / 2 + 5)
    local expectedY = math.sin(math.rad(200)) * (140 / 2 + 5)
    assert(math.abs(pt[4] - expectedX) < 1e-6 and math.abs(pt[5] - expectedY) < 1e-6)
''')

# 6c. Legacy LibDBIcon mode: minimapPos wins once and syncs minimapAngle
lua_legacy_ldb = run_minimap_env(preloaded_communities=False, show_minimap=True)
lua_legacy_ldb.execute('''
    local registeredDb
    LibStub = setmetatable({}, {
        __call = function(_, name)
            if name == 'LibDataBroker-1.1' then
                return { NewDataObject = function(_, _, obj) return obj end }
            end
            if name == 'LibDBIcon-1.0' then
                return {
                    Register = function(_, _, _, dbTable) registeredDb = dbTable end,
                    GetMinimapButton = function() return nil end,
                }
            end
            return nil
        end,
    })
    OldKraken.DB.settings.minimapAngle = 120
    OldKraken.DB.settings.minimap = { minimapPos = 45 }
    OldKraken:Fire('INITIALIZED', OldKraken.DB)
    assert(registeredDb ~= nil and registeredDb.minimapPos == 45, 'legacy LibDBIcon profile must preserve minimapPos')
    assert(OldKraken.DB.settings.minimapAngle == 45, 'legacy LibDBIcon profile must sync minimapPos -> minimapAngle')
    assert(OldKraken.DB.settings.minimapPositionSynced == true)
''')

# 6d. Legacy profile when LibDBIcon:Register() errors: fallback must choose minimapAngle and set minimapPositionSynced
lua_legacy_err = run_minimap_env(preloaded_communities=False, show_minimap=True)
lua_legacy_err.execute('''
    LibStub = setmetatable({}, {
        __call = function(_, name)
            if name == 'LibDataBroker-1.1' then
                return { NewDataObject = function(_, _, obj) return obj end }
            end
            if name == 'LibDBIcon-1.0' then
                return { Register = function() error('duplicate registration') end }
            end
            return nil
        end,
    })
    OldKraken.DB.settings.minimapAngle = 120
    OldKraken.DB.settings.minimap = { minimapPos = 45 }
    OldKraken:Fire('INITIALIZED', OldKraken.DB)
    assert(OldKrakenMinimapButton ~= nil, 'must fall back to own button when LibDBIcon:Register errors')
    assert(OldKraken.DB.settings.minimapAngle == 120, 'fallback after LibDBIcon error must keep minimapAngle')
    assert(OldKraken.DB.settings.minimap.minimapPos == 120, 'fallback after LibDBIcon error must sync minimapAngle -> minimapPos')
    assert(OldKraken.DB.settings.minimapPositionSynced == true)
    local pt = OldKrakenMinimapButton.points[1]
    local expectedX = math.cos(math.rad(120)) * (140 / 2 + 5)
    local expectedY = math.sin(math.rad(120)) * (140 / 2 + 5)
    assert(math.abs(pt[4] - expectedX) < 1e-6 and math.abs(pt[5] - expectedY) < 1e-6)
''')

# 6. GameMenuFrame integration: deferred boot when MainMenuFrameMixin is missing, InitButtons idempotency (with/without pool reset), missing AddOns guard, repeated OnShow, click behavior
lua_gm = LuaRuntime(unpack_returned_tuples=True)
lua_gm.execute('''
    function hooksecurefunc(tbl, name, fn)
        local orig = tbl[name]
        tbl[name] = function(...) orig(...); fn(...) end
    end
    frames = {}
    gmListeners = {}
    rosterToggles = 0
    hiddenPanel = nil
    addedButtons = {}
    markedDirty = 0
    function HideUIPanel(p) hiddenPanel = p end
    addonsChild = {
        layoutIndex = 3,
        topPadding = 20,
        IsShown = function() return true end,
        GetText = function() return 'AddOns' end,
    }
    local poolReleased = false
    GameMenuFrame = {
        InitButtons = function(self)
            if poolReleased then
                -- Simulate Blizzard FramePool reusing the previous frame for 'Return to Game'
                addedButtons[1].label = 'Return to Game'
                addedButtons[1].layoutIndex = 9
                addedButtons[1].shown = true
                poolReleased = false
            end
        end,
        ReleaseButtonsForTest = function() poolReleased = true end,
        HookScript = function(self, ev, fn) self.hooks = self.hooks or {}; self.hooks[ev] = fn end,
        GetChildren = function()
            local out = {}
            if addonsChild then out[#out + 1] = addonsChild end
            for _, b in ipairs(addedButtons) do out[#out + 1] = b end
            return unpack(out)
        end,
        MarkDirty = function() markedDirty = markedDirty + 1 end,
    }
    MainMenuFrameMixin = nil
    OldKraken = {
        UIStyle = { Colors = { panel = {0,0,0}, panelEdge = {1,1,1}, brandGold = {1,1,0} }, EmblemPath = function() return 'e' end },
        GuildRoster = { Toggle = function() rosterToggles = rosterToggles + 1 end },
        GroupFinder = { Toggle = function() end },
        On = function(_, ev, fn) gmListeners[ev] = fn end,
    }
    function CreateFrame()
        local f = {
            registered = {},
            SetSize=function() end, SetFrameStrata=function() end, SetFrameLevel=function() end,
            SetPoint=function() end, RegisterForClicks=function() end, EnableMouse=function() end,
            SetHighlightTexture=function() end, SetScript=function(self, ev, fn) self.scripts = self.scripts or {}; self.scripts[ev] = fn end,
            RegisterEvent=function(self, ev) self.registered[ev] = true end,
            UnregisterAllEvents=function(self) self.registered = {} end,
            CreateTexture=function() return {SetAllPoints=function() end, SetColorTexture=function() end, SetPoint=function() end, SetSize=function() end, SetTexture=function() end, SetWidth=function() end, SetHeight=function() end} end,
            Hide=function() end, Show=function() end,
        }
        frames[#frames + 1] = f
        return f
    end
''')
lua_gm.execute((Path(__file__).resolve().parents[1] / 'Minimap.lua').read_text(encoding='utf-8'))
lua_gm.execute('''
    -- 6a. Deferred registration when MainMenuFrameMixin is initially missing, then succeeds on PLAYER_LOGIN
    local gmLoader
    for _, f in ipairs(frames) do
        if f.registered['PLAYER_LOGIN'] then gmLoader = f; break end
    end
    assert(gmLoader ~= nil, 'must register PLAYER_LOGIN/ADDON_LOADED when MainMenuFrameMixin is missing')
    MainMenuFrameMixin = {
        AddButton = function(menu, label, callback)
            local btn = {
                menu = menu, label = label, callback = callback, layoutIndex = 10, shown = true,
                IsShown = function(self) return self.shown end,
                Hide = function(self) self.shown = false end,
                GetText = function(self) return self.label end,
                GetParent = function(self) return self.menu end,
            }
            addedButtons[#addedButtons + 1] = btn
            return btn
        end
    }
    gmLoader.scripts.OnEvent(gmLoader, 'PLAYER_LOGIN')
    assert(gmLoader.registered['PLAYER_LOGIN'] == nil, 'must unregister events after hooking GameMenuFrame')

    -- 6b. Repeated InitButtons without pool reset must NOT create duplicate buttons
    GameMenuFrame:InitButtons()
    GameMenuFrame:InitButtons()
    assert(#addedButtons == 1, 'repeated InitButtons while button is still shown must not duplicate')
    assert(addedButtons[1].menu == GameMenuFrame)
    assert(addedButtons[1].label:find('Old Kraken', 1, true) ~= nil)

    -- 6c. Repeated OnShow places button before AddOns and keeps section gap
    GameMenuFrame.hooks.OnShow(GameMenuFrame)
    GameMenuFrame.hooks.OnShow(GameMenuFrame)
    assert(addedButtons[1].layoutIndex < addonsChild.layoutIndex, 'button must be placed before AddOns')
    assert(addedButtons[1].topPadding == nil and addonsChild.topPadding == 20, 'must keep section gap above AddOns')
    assert(markedDirty == 2)

    -- 6d. Pool reset + frame reuse for 'Return to Game' before InitButtons re-acquires Old Kraken cleanly without moving Return to Game
    GameMenuFrame:ReleaseButtonsForTest()
    GameMenuFrame:InitButtons()
    assert(#addedButtons == 2 and addedButtons[1]:GetText() == 'Return to Game' and addedButtons[2]:GetText():find('Old Kraken', 1, true) ~= nil)
    GameMenuFrame.hooks.OnShow(GameMenuFrame)
    assert(addedButtons[1].layoutIndex == 9, 'reused Return to Game frame must keep its layoutIndex')
    assert(addedButtons[2].layoutIndex < addonsChild.layoutIndex)

    -- 6e. Missing AddOns button does not error or modify MarkDirty
    local savedAddons = addonsChild
    addonsChild = nil
    local dirtyBefore = markedDirty
    GameMenuFrame.hooks.OnShow(GameMenuFrame)
    assert(markedDirty == dirtyBefore)
    addonsChild = savedAddons

    -- 6f. Click hides GameMenuFrame and toggles GuildRoster
    addedButtons[2].callback()
    assert(hiddenPanel == GameMenuFrame, 'clicking GameMenu button must hide GameMenuFrame')
    assert(rosterToggles == 1, 'clicking GameMenu button must toggle GuildRoster')

    -- 6g. Disabling showGameMenuButton hides already-created button via GAME_MENU_BUTTON_SETTING and skips AddButton on InitButtons
    assert(addedButtons[2]:IsShown() == true)
    OldKraken.DB = { settings = { showGameMenuButton = false } }
    gmListeners['GAME_MENU_BUTTON_SETTING']()
    assert(addedButtons[2]:IsShown() == false, 'GAME_MENU_BUTTON_SETTING must hide existing GameMenu button')
    GameMenuFrame:InitButtons()
    assert(#addedButtons == 2, 'InitButtons while disabled must not add duplicate button')
    GameMenuFrame:ReleaseButtonsForTest()
    GameMenuFrame:InitButtons()
    assert(#addedButtons == 2, 'must not add GameMenu button when showGameMenuButton is false')
''')

print('Minimap and Communities checks passed')
