"""Tests for Guild Events segmented role selector and single-role badge."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def build_env():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(
        """
        OldKraken = {
            name = 'OldKraken',
            DB = {events = {}, settings = {language = 'ukUA', guildEventNotifications = false}},
            _listeners = {},
            UIStyle = {
                Colors = {
                    text = {0.93, 0.94, 0.96, 1}, brandGold = {0.88, 0.69, 0.32, 1},
                    mutedText = {0.63, 0.67, 0.73}, success = {0.41, 0.86, 0.55, 1},
                    neutral = {0.63, 0.67, 0.73, 1}, danger = {1, 0.48, 0.43, 1},
                    primaryButton = {0.30, 0.37, 0.83, 1}, primaryButtonEdge = {0.45, 0.52, 0.96, 1},
                    button = {0.10, 0.12, 0.16, 1}, buttonEdge = {0.20, 0.23, 0.29, 0.85},
                },
                Window = function() end,
                Button = function(b) b.fillParts = {{SetVertexColor=function() end}}; b.ringParts = {{SetVertexColor=function() end}} end,
                Dropdown = function() end, Input = function() end, Panel = function() end, Font = function() end,
                PanelFrame = function(parent) return CreateFrame('Frame', nil, parent) end,
                StepIndicator = function(parent, number, title)
                    local s = CreateFrame('Frame', nil, parent)
                    s.number = s:CreateFontString(); s.number:SetText(tostring(number))
                    s.title = s:CreateFontString(); s.title:SetText(title or '')
                    function s:SetTitle(v) self.title:SetText(v or '') end
                    return s
                end,
                Chip = function(parent, text, options)
                    local c = CreateFrame('Button', nil, parent)
                    c.label = c:CreateFontString(); c.label:SetText(text or '')
                    c.active = options and options.active and true or false
                    function c:SetLabel(v) self.label:SetText(v or '') end
                    function c:SetActive(a) self.active = a and true or false end
                    return c
                end,
                SegmentedTabs = function(parent, items, onSelect, options)
                    local box = CreateFrame('Frame', nil, parent)
                    box.tabs = {}
                    for _, item in ipairs(items) do
                        local tab = CreateFrame('Button', nil, box)
                        tab.label = tab:CreateFontString(); tab.label:SetText(item.label)
                        tab:SetScript('OnClick', function() if onSelect then onSelect(item.key) end end)
                        box.tabs[item.key] = tab
                    end
                    function box:SetActive(key)
                        self.activeKey = key
                        for k, t in pairs(self.tabs) do t.selected = (k == key) end
                    end
                    box:SetActive(options and options.active or (items[1] and items[1].key))
                    return box
                end,
                ApplySelection = function(card, selected) card.isSelected = selected and true or false end,
            },
            Communication = {queue = {}},
        }
        function OldKraken:On(name, cb)
            self._listeners[name] = self._listeners[name] or {}
            table.insert(self._listeners[name], cb)
        end
        function OldKraken:Fire(name, ...)
            for _, cb in ipairs(self._listeners[name] or {}) do cb(...) end
        end
        function OldKraken.Communication:RegisterHandler() end
        function OldKraken.Communication:SendProtocol() return true end
        function OldKraken.Communication:RegisterCommand() end
        function UnitName() return 'Tester', 'Realm' end
        function GetGuildInfo() return 'Guild' end
        function GetRealmName() return 'Test Realm' end
        function GetServerTime() return 2000000000 end
        function GetTime() return 10 end
        function date(fmt, ts) return os.date(fmt, ts) end
        time = os.time
        function IsInGuild() return true end
        function IsInInstance() return false, 'none' end
        function InCombatLockdown() return false end
        function PlaySound() end
        function UIDropDownMenu_SetWidth() end
        function UIDropDownMenu_JustifyText() end
        function UIDropDownMenu_Initialize() end
        function UIDropDownMenu_SetText() end
        function UIDropDownMenu_CreateInfo() return {} end
        function print() end
        StaticPopupDialogs = {}
        UISpecialFrames = {}
        UIParent = {}
        C_Timer = {
            After = function(_, fn) if fn then fn() end end,
            NewTicker = function() return {Cancel = function() end} end,
        }
        gameRoles = {tank = true, healer = true, dps = true}
        function UnitGetAvailableRoles(unit)
            if unit == 'player' then return gameRoles.tank, gameRoles.healer, gameRoles.dps end
        end
        local methods = {}
        function methods:RegisterEvent() end
        function methods:SetScript(name, cb) self.scripts[name] = cb end
        function methods:HookScript(name, cb)
            local old = self.scripts[name]
            self.scripts[name] = function(...) if old then old(...) end; cb(...) end
        end
        function methods:SetSize(w, h) self.width, self.height = w, h end
        function methods:SetWidth(w) self.width = w end
        function methods:SetHeight(h) self.height = h end
        function methods:SetText(v) self.text = v end
        function methods:GetText() return self.text or '' end
        function methods:Show() self.shown = true end
        function methods:Hide() self.shown = false end
        function methods:SetShown(v) self.shown = v and true or false end
        function methods:IsShown() return self.shown == true end
        function methods:Enable() self.enabled = true end
        function methods:Disable() self.enabled = false end
        function methods:IsEnabled() return self.enabled ~= false end
        function methods:GetHeight() return 250 end
        function methods:GetFrameLevel() return 1 end
        function methods:GetStringHeight() return 40 end
        function methods:GetVerticalScroll() return 0 end
        function methods:CreateFontString() return CreateFrame('FontString') end
        function methods:CreateTexture() return CreateFrame('Texture') end
        local mt = {__index = function(_, k) return methods[k] or function() end end}
        function CreateFrame(kind, name, parent, template)
            local fr = setmetatable({kind = kind, name = name, parent = parent, template = template, scripts = {}, shown = true, enabled = true}, mt)
            if name then _G[name] = fr end
            return fr
        end
        pages = {}
        OldKraken.UIHub = {
            RegisterPage = function(_, key, _, _, create) pages[key] = create(CreateFrame('Frame')) end,
            ShowPage = function(_, key) if pages[key] then pages[key]:Show() end end,
        }
        """
    )
    for fname in ("Locale.lua", "ActivityCatalog.lua", "GroupFinder.lua", "GuildEvents.lua"):
        lua.execute((ROOT / fname).read_text(encoding="utf-8"))
    lua.execute("OldKraken.InitializeLocale(OldKraken.DB); OldKraken.GroupFinder:Initialize('Tester Realm', function() return true end); OldKraken:Fire('INITIALIZED', OldKraken.DB)")
    return lua


def test_role_selector_scenarios():
    lua = build_env()
    lua.execute(
        """
        local events = OldKraken.GuildEvents
        local ui = pages.events
        events:Show()
        assert(events:Create('Test Event', 'Desc', GetServerTime() + 7200, 'raid', 20, ''))
        local _, store = next(OldKraken.DB.events.guildCalendarV1)
        assert(store)
        local key, e = next(store.owned)
        assert(key and e)
        -- Make event non-owned so Tester can sign up.
        e.owner = 'Leader Realm'
        e.people['Tester Realm'] = nil
        e.statuses['Tester Realm'] = nil

        -- 1. tank/healer/dps available -> 3-button segmented selector.
        gameRoles = {tank = true, healer = true, dps = true}
        events:ShowEvent(key)
        assert(ui.roleSelector:IsShown() and ui.join:IsShown())
        assert(ui.roleSelector.mode == 'buttons')
        assert(ui.roleSelector.buttons[1]:IsShown() and ui.roleSelector.buttons[1].role == 'tank')
        assert(ui.roleSelector.buttons[2]:IsShown() and ui.roleSelector.buttons[2].role == 'healer')
        assert(ui.roleSelector.buttons[3]:IsShown() and ui.roleSelector.buttons[3].role == 'dps')
        assert(not ui.roleSelector.badge:IsShown())

        -- 2. tank/healer available -> 2-button selector; initial unavailable 'dps' normalizes to 'tank'.
        gameRoles = {tank = true, healer = true, dps = false}
        events:ShowEvent(key)
        assert(ui.roleSelector.mode == 'buttons')
        assert(ui.roleSelector.buttons[1]:IsShown() and ui.roleSelector.buttons[1].role == 'tank')
        assert(ui.roleSelector.buttons[2]:IsShown() and ui.roleSelector.buttons[2].role == 'healer')
        assert(not ui.roleSelector.buttons[3]:IsShown())
        assert(ui.roleSelector.selectedRole == 'tank')
        assert(ui.roleSelector.buttons[1].active and not ui.roleSelector.buttons[2].active)

        -- 3. Switching role updates currentRole and signup sends the newly selected role.
        local origSignup = events.Signup
        local sentRoles = {}
        function events:Signup(k, r)
            sentRoles[#sentRoles + 1] = r
            return origSignup(self, k, r)
        end
        ui.roleSelector.buttons[2].scripts.OnClick(ui.roleSelector.buttons[2])
        assert(ui.roleSelector.selectedRole == 'healer')
        assert(ui.roleSelector.buttons[2].active and not ui.roleSelector.buttons[1].active)
        ui.join.scripts.OnClick(ui.join)
        assert(sentRoles[#sentRoles] == 'healer' and store.intents[key] and store.intents[key].role == 'healer')

        -- 4. When pending signup exists (canJoin == false), roleSelector and join are hidden.
        events:ShowEvent(key)
        assert(not ui.join:IsShown() and not ui.roleSelector:IsShown())

        -- 5. On a fresh event with only 1 role available -> badge without interactive switcher.
        assert(events:Create('Test Event 2', 'Desc', GetServerTime() + 7200, 'raid', 20, ''))
        local key2, e2
        for k, v in pairs(store.owned) do
            if k ~= key then key2, e2 = k, v; break end
        end
        assert(key2 and e2)
        e2.owner = 'Leader Realm'; e2.people['Tester Realm'] = nil; e2.statuses['Tester Realm'] = nil
        gameRoles = {tank = false, healer = false, dps = true}
        events:ShowEvent(key2)
        assert(ui.roleSelector:IsShown() and ui.roleSelector.mode == 'badge')
        assert(ui.roleSelector.badge:IsShown() and ui.roleSelector.badge.text.text:find('DPS', 1, true))
        for i = 1, 3 do assert(not ui.roleSelector.buttons[i]:IsShown()) end
        assert(ui.roleSelector.selectedRole == 'dps')

        -- 6. Initial 'flex' / unavailable role is normalized to available role.
        gameRoles = {tank = false, healer = true, dps = false}
        events:ShowEvent(key2)
        assert(ui.roleSelector.selectedRole == 'healer')
        ui.join.scripts.OnClick(ui.join)
        assert(sentRoles[#sentRoles] == 'healer' and store.intents[key2] and store.intents[key2].role == 'healer')

        -- 7. No available roles on a fresh event -> mode == 'none', join disabled, invalid signup blocked.
        assert(events:Create('Test Event 3', 'Desc', GetServerTime() + 7200, 'raid', 20, ''))
        local key3, e3
        for k, v in pairs(store.owned) do
            if k ~= key and k ~= key2 then key3, e3 = k, v; break end
        end
        assert(key3 and e3)
        e3.owner = 'Leader Realm'; e3.people['Tester Realm'] = nil; e3.statuses['Tester Realm'] = nil
        gameRoles = {tank = false, healer = false, dps = false}
        events:ShowEvent(key3)
        assert(ui.roleSelector.mode == 'none')
        assert(not ui.join:IsEnabled())
        local beforeCount = #sentRoles
        ui.join.scripts.OnClick(ui.join)
        assert(#sentRoles == beforeCount and store.intents[key3] == nil)
        """
    )


test_role_selector_scenarios()
print("Guild Events segmented role selector tests passed")
