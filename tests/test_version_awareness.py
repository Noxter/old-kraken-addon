from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def make_runtime(local_version='0.5.4'):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals()._local_version = local_version
    lua.execute('''
        local listeners = {}
        local chatPrints = {}
        local inCombat = false
        local inGuild = true
        frames = {}

        OldKraken = {
            name = 'OldKraken',
            version = _local_version,
            UIStyle = {
                Colors = {
                    brandGold = {0.88, 0.69, 0.32, 1},
                    mutedText = {0.6, 0.6, 0.6},
                    white = {1, 1, 1},
                    window = {0.025, 0.035, 0.055},
                    panel = {0.055, 0.07, 0.095},
                    panelEdge = {0.2, 0.25, 0.3},
                },
                Font = function() end,
                Window = function() end,
                Panel = function() end,
                Button = function(b, text) if text and b.SetText then b:SetText(text) end end,
                Input = function(editBox, options)
                    assert(type(editBox) == 'table' and (options == nil or type(options) == 'table'), 'UIStyle.Input expects (editBox, options)')
                end,
                EmblemPath = function() return 'Interface\\\\AddOns\\\\OldKraken\\\\Media\\\\OldKrakenEmblem.tga' end,
                ApplySelection = function() end,
            },
        }
        function OldKraken:On(event, fn)
            listeners[event] = listeners[event] or {}
            listeners[event][#listeners[event] + 1] = fn
        end
        function OldKraken:Fire(event, ...)
            for _, fn in ipairs(listeners[event] or {}) do fn(...) end
        end
        function OldKraken:Print(msg) chatPrints[#chatPrints + 1] = msg end
        function OldKraken:PrintError(msg) chatPrints[#chatPrints + 1] = msg end
        function OldKraken.GetGuildDisplayName() return 'Old Kraken' end

        function GetChatPrints() return chatPrints end
        function ClearChatPrints() chatPrints = {} end
        function SetCombat(v) inCombat = v end
        function InCombatLockdown() return inCombat end
        function IsInGuild() return inGuild end
        function GetGuildInfo() return 'Old Kraken' end
        function GetRealmName() return 'Forever' end
        function UnitName() return 'Tester', 'Player' end
        function GetServerTime() return 1700000000 end
        function GetTime() return 100 end
        function ReloadUI() end
        function IsControlKeyDown() return false end

        C_AddOns = { GetAddOnMetadata = function() return _local_version end }
        C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end }
        C_Timer = { NewTicker = function() end }
        UIParent = {}
        UISpecialFrames = {}
        StaticPopupDialogs = {}
        OldKrakenDB = {}

        local function makeObj()
            local o = { shown = false, enabled = true, text = '', scripts = {}, events = {} }
            local mt = {
                __index = function(t, k)
                    if k == 'Show' then return function(s) s.shown = true end
                    elseif k == 'Hide' then return function(s) s.shown = false end
                    elseif k == 'SetShown' then return function(s, v) s.shown = v and true or false end
                    elseif k == 'IsShown' then return function(s) return s.shown == true end
                    elseif k == 'SetText' then return function(s, v) s.text = v end
                    elseif k == 'GetText' then return function(s) return s.text end
                    elseif k == 'SetEnabled' then return function(s, v) s.enabled = v and true or false end
                    elseif k == 'RegisterEvent' then return function(s, ev) s.events[ev] = true end
                    elseif k == 'SetScript' then return function(s, name, fn) s.scripts[name] = fn end
                    elseif k == 'HookScript' then return function(s, name, fn) s.scripts[name] = fn end
                    elseif k == 'GetFontString' then return function() return makeObj() end
                    elseif k == 'CreateFontString' then return function() return makeObj() end
                    elseif k == 'CreateTexture' then return function() return makeObj() end
                    elseif k == 'GetFrameLevel' then return function() return 1 end
                    else
                        local fn = function() return makeObj() end
                        t[k] = fn
                        return fn
                    end
                end
            }
            return setmetatable(o, mt)
        end

        function CreateFrame(_, name)
            local f = makeObj()
            if name then _G[name] = f end
            frames[#frames + 1] = f
            return f
        end
    ''')
    for name in ('Database.lua', 'Locale.lua', 'UIHub.lua', 'Communication.lua'):
        lua.execute((ROOT / name).read_text(encoding='utf-8'))
    lua.execute('''
        OldKraken.Database.Initialize()
        OldKraken.InitializeLocale(OldKraken.DB)
        OldKraken:Fire('INITIALIZED', OldKraken.DB)
    ''')
    return lua


# 1. Absent roster versions -> nil newest, hidden header indicator, no chat prints
lua = make_runtime('0.5.4')
lua.execute('''
    local comm = OldKraken.Communication
    local hub = OldKraken.UIHub
    hub:ShowPage('settings')
    assert(comm:GetNewestKnownVersion() == nil)
    assert(not hub.versionButton:IsShown(), 'Header indicator must be hidden when no versions are known')
    assert(#GetChatPrints() == 0)
''')

# 2. Stable ignores prerelease (alpha/beta/rc) and unknown/invalid versions
lua.execute('''
    local comm = OldKraken.Communication
    comm:OnAddonMessage(comm.PREFIX, 'OKP^HERE^0.5.5-alpha.1', 'GUILD', 'Alpha-Player')
    comm:OnAddonMessage(comm.PREFIX, 'OKP^HERE^0.5.5-beta.2', 'GUILD', 'Beta-Player')
    comm:OnAddonMessage(comm.PREFIX, 'OKP^HERE^0.5.5-rc.1', 'GUILD', 'Rc-Player')
    comm:OnAddonMessage(comm.PREFIX, 'OKP^HERE^unknown', 'GUILD', 'Bad-Player')
    assert(comm:GetNewestKnownVersion() == nil, 'Stable local version must ignore prereleases and invalid versions')
    assert(not OldKraken.UIHub.versionButton:IsShown())
    assert(#GetChatPrints() == 0)
''')

# 3. Newer stable (including numeric 0.5.10 > 0.5.5) triggers 1 chat print and shows indicator
lua.execute('''
    local comm = OldKraken.Communication
    local hub = OldKraken.UIHub
    comm:OnAddonMessage(comm.PREFIX, 'OKP^HERE^0.5.5', 'GUILD', 'PeerA')
    assert(comm:GetNewestKnownVersion() == '0.5.5')
    assert(#GetChatPrints() == 1, 'First newer version in session must notify once')
    assert(hub.versionButton:IsShown(), 'Header indicator must show when newer stable version is known')

    -- Repeated presence for same version does not duplicate chat print
    comm:OnAddonMessage(comm.PREFIX, 'OKP^HERE^0.5.5', 'GUILD', 'PeerB')
    assert(#GetChatPrints() == 1)

    -- Numeric comparison: 0.5.10 > 0.5.5
    comm:OnAddonMessage(comm.PREFIX, 'OKP^HERE^0.5.10', 'GUILD', 'PeerC')
    assert(comm:GetNewestKnownVersion() == '0.5.10')
    assert(#GetChatPrints() == 2, 'Higher version in same session may notify once')
''')

# 4. /reload (isInitialLogin=false, isReloadingUi=true) does NOT re-notify;
#    new login (isInitialLogin=true, isReloadingUi=false) DOES notify again!
lua.execute('''
    ClearChatPrints()
    for _, f in ipairs(frames) do
        if f.events.PLAYER_ENTERING_WORLD and f.scripts.OnEvent then
            f.scripts.OnEvent(f, 'PLAYER_ENTERING_WORLD', false, true)
        end
    end
    assert(#GetChatPrints() == 0, '/reload must NOT repeat version chat notification')

    for _, f in ipairs(frames) do
        if f.events.PLAYER_ENTERING_WORLD and f.scripts.OnEvent then
            f.scripts.OnEvent(f, 'PLAYER_ENTERING_WORLD', true, false)
        end
    end
    assert(#GetChatPrints() == 1, 'New login session must notify again until updated')
''')

# 5. Clicking header indicator opens non-modal CurseForge box with exact URL
lua.execute('''
    local hub = OldKraken.UIHub
    hub.versionButton.scripts.OnClick(hub.versionButton)
    assert(hub.updateBox and hub.updateBox:IsShown(), 'Update link box must open on click')
    assert(hub.updateBox.input:GetText() == 'https://www.curseforge.com/wow/addons/old-kraken')
''')

# 6. Independent settings toggles disable indicator and chat notifications separately
lua.execute('''
    local settings = OldKraken.DB.settings
    settings.versionIndicator = false
    OldKraken:Fire('VERSION_SETTING_CHANGED')
    assert(not OldKraken.UIHub.versionButton:IsShown(), 'Disabling indicator must hide header button')

    settings.versionChatNotifications = false
    ClearChatPrints()
    for _, f in ipairs(frames) do
        if f.events.PLAYER_ENTERING_WORLD and f.scripts.OnEvent then
            f.scripts.OnEvent(f, 'PLAYER_ENTERING_WORLD', true, false)
        end
    end
    assert(#GetChatPrints() == 0, 'Disabling chat notifications must suppress login notice')
''')

# 7. Local prerelease version ignores older stable (0.5.4) and notifies on newer stable (0.5.5)
lua_pre = make_runtime('0.5.5-alpha.1')
lua_pre.execute('''
    local comm = OldKraken.Communication
    comm:OnAddonMessage(comm.PREFIX, 'OKP^HERE^0.5.4', 'GUILD', 'OlderStable')
    assert(comm:GetNewestKnownVersion() == nil, 'Prerelease 0.5.5-alpha.1 must not treat 0.5.4 as newer')
    comm:OnAddonMessage(comm.PREFIX, 'OKP^HERE^0.5.5', 'GUILD', 'NewStable')
    assert(comm:GetNewestKnownVersion() == '0.5.5', '0.5.5 stable is newer than 0.5.5-alpha.1')
''')

# 8. Combat lockdown defers chat notification until PLAYER_REGEN_ENABLED
lua_combat = make_runtime('0.5.4')
lua_combat.execute('''
    SetCombat(true)
    local comm = OldKraken.Communication
    comm:OnAddonMessage(comm.PREFIX, 'OKP^HERE^0.5.5', 'GUILD', 'PeerA')
    assert(#GetChatPrints() == 0, 'Must not print chat notice during combat')
    SetCombat(false)
    for _, f in ipairs(frames) do
        if f.events.PLAYER_REGEN_ENABLED and f.scripts.OnEvent then
            f.scripts.OnEvent(f, 'PLAYER_REGEN_ENABLED')
        end
    end
    assert(#GetChatPrints() == 1, 'Deferred chat notice must fire after leaving combat')
''')

# 9. Dormant Compatibility Gate: disabled by default, enabled < / == / > threshold, invalid local, ShowPage/Toggle, ShowUpdateLink, OKP^
lua_gate = make_runtime('0.5.4')
lua_gate.execute('''
    local comm, hub = OldKraken.Communication, OldKraken.UIHub
    assert(comm.COMPATIBILITY_GATE_ENABLED == false, 'Gate must be disabled by default')
    assert(comm.MIN_SUPPORTED_VERSION == nil, 'MIN_SUPPORTED_VERSION must be nil by default')
    local state0 = comm:GetCompatibilityGateState()
    assert(state0.blocked == false and state0.localVersion == '0.5.4' and state0.minVersion == nil)

    local settingsFrame = hub:ShowPage('settings')
    assert(settingsFrame and settingsFrame:IsShown(), 'Settings page must show when gate is disabled')
    assert(hub.gateOverlay and not hub.gateOverlay:IsShown(), 'Gate overlay must stay hidden when disabled')

    -- Enable gate with minVersion = '0.6.0' -> 0.5.4 < 0.6.0 must block UI
    comm.COMPATIBILITY_GATE_ENABLED = true
    comm.MIN_SUPPORTED_VERSION = '0.6.0'
    local stateBlocked = comm:GetCompatibilityGateState()
    assert(stateBlocked.blocked == true and stateBlocked.minVersion == '0.6.0')

    -- Repeat ShowPage('settings') after blocking must hide previously opened page and show gateOverlay
    hub:ShowPage('settings')
    assert(not settingsFrame:IsShown(), 'Previously shown page must be hidden when blocked')
    assert(hub.gateOverlay:IsShown(), 'Gate overlay must be shown when blocked')
    assert(hub.gateOverlay.versionsText:GetText():find('0.5.4', 1, true), 'Versions text must include local version')
    assert(hub.gateOverlay.versionsText:GetText():find('0.6.0', 1, true), 'Versions text must include min version')

    -- Register a second page and ensure ShowPage & Toggle cannot bypass gate
    local customPageCreated = false
    hub:RegisterPage('custom', 'Custom', '06', function()
        customPageCreated = true
        return CreateFrame('Frame')
    end)
    hub:ShowPage('custom')
    assert(not customPageCreated and hub.gateOverlay:IsShown(), 'Blocked ShowPage must not create/show new page')
    hub:Toggle('custom')
    assert(not hub.frame:IsShown(), 'Toggle on shown blocked frame hides frame')
    hub:Toggle('settings')
    assert(hub.frame:IsShown() and not settingsFrame:IsShown() and hub.gateOverlay:IsShown(), 'Toggle reopen must stay blocked')

    -- Update button opens existing ShowUpdateLink with CurseForge URL
    hub.gateOverlay.updateButton.scripts.OnClick(hub.gateOverlay.updateButton)
    assert(hub.updateBox and hub.updateBox:IsShown(), 'Gate update button must open updateBox')
    assert(hub.updateBox.input:GetText() == 'https://www.curseforge.com/wow/addons/old-kraken')

    -- OKP^ presence/version exchange still works while UI gate is active
    comm:OnAddonMessage(comm.PREFIX, 'OKP^HERE^0.6.0', 'GUILD', 'NewPeer')
    assert(comm:HasRosterAddon('NewPeer') and comm:GetRosterVersion('NewPeer') == '0.6.0', 'OKP^HERE^ must still work when gate is blocked')

    -- Dynamic re-check when gate is disabled again -> ShowPage hides overlay and restores UI
    comm.COMPATIBILITY_GATE_ENABLED = false
    hub:ShowPage('settings')
    assert(not hub.gateOverlay:IsShown() and settingsFrame:IsShown(), 'Re-disabling gate must restore normal UI')
''')

for local_ver, expected_blocked in (('0.6.0', False), ('0.6.1', False), ('unknown', False), ('invalid-ver', False)):
    lua_case = make_runtime(local_ver)
    lua_case.globals()._expected_blocked = expected_blocked
    lua_case.execute('''
        local comm, hub = OldKraken.Communication, OldKraken.UIHub
        comm.COMPATIBILITY_GATE_ENABLED = true
        comm.MIN_SUPPORTED_VERSION = '0.6.0'
        local st = comm:GetCompatibilityGateState()
        assert(st.blocked == _expected_blocked, 'Unexpected gate state for ' .. tostring(_local_version))
        local page = hub:ShowPage('settings')
        assert(page and page:IsShown() and not hub.gateOverlay:IsShown(), 'Allowed/invalid version must open settings without overlay')
    ''')

print('Version awareness checks passed')
