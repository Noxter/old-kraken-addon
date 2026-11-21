from pathlib import Path

from lupa.lua51 import LuaRuntime


root = Path(__file__).resolve().parents[1]


def build_lua_env(language='ukUA', client_locale='ukUA', with_group_finder_ui=False):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals()._testLanguage = language
    lua.globals()._testClientLocale = client_locale
    lua.execute('''
OldKraken = {
    name = 'OldKraken',
    DB = {events = {}, settings = {language = _testLanguage, guildEventNotifications = true, smartNotifications = true}},
    listeners = {},
    _listeners = {},
    UIStyle = {
        Colors = {
            text = {0.93, 0.94, 0.96, 1},
            brandGold = {0.88, 0.69, 0.32, 1},
            mutedText = {0.63, 0.67, 0.73},
            success = {0.41, 0.86, 0.55, 1},
            neutral = {0.63, 0.67, 0.73, 1},
            danger = {1, 0.48, 0.43, 1},
            sel = {0.20, 0.28, 0.62, 0.55},
            selEdge = {0.55, 0.66, 1, 1},
            buttonEdge = {0.20, 0.23, 0.29, 0.85},
        },
        Window=function() end, Button=function() end, Dropdown=function() end,
        Input=function() end, Panel=function() end, Font=function() end,
        EmblemPath=function() return 'Interface\\\\AddOns\\\\OldKraken\\\\Media\\\\OldKrakenEmblem.tga' end,
        PanelFrame=function(parent) return CreateFrame('Frame', nil, parent) end,
        StepIndicator=function(parent, number, title)
            local s = CreateFrame('Frame', nil, parent)
            s.number = s:CreateFontString(); s.number:SetText(tostring(number))
            s.title = s:CreateFontString(); s.title:SetText(title or '')
            function s:SetTitle(v) self.title:SetText(v or '') end
            return s
        end,
        Chip=function(parent, text, options)
            local c = CreateFrame('Button', nil, parent)
            c.label = c:CreateFontString(); c.label:SetText(text or '')
            c.active = options and options.active and true or false
            function c:SetLabel(v) self.label:SetText(v or '') end
            function c:SetActive(a) self.active = a and true or false end
            return c
        end,
        SegmentedTabs=function(parent, items, onSelect, options)
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
        ApplySelection=function(card, selected) card.isSelected = selected and true or false end,
    },
    Communication = {queue = {}},
}
StaticPopupDialogs = {}
lastPopupTitle = nil
function StaticPopup_Show(which, text, _, callback)
    lastPopupTitle = text
    popup = {which = which, text = text, callback = callback, HookScript = function() end, GetFrameStrata = function() return 'DIALOG' end, SetFrameStrata = function() end}
    return popup
end
function OldKraken:On(name, callback)
    self.listeners[name] = callback
    self._listeners[name] = self._listeners[name] or {}
    table.insert(self._listeners[name], callback)
end
function OldKraken:Fire(name, ...)
    for _, callback in ipairs(self._listeners[name] or {}) do callback(...) end
end
sentPayloads = {}
function OldKraken.Communication:RegisterHandler() end
function OldKraken.Communication:SendProtocol(kind, payload)
    table.insert(sentPayloads, {kind = kind, payload = payload})
    return true
end
function OldKraken.Communication:SendGuildMessage() return true end
function OldKraken.Communication:RegisterCommand() end
function GetLocale() return _testClientLocale end
function UnitName() return 'Tester', 'Realm' end
function GetGuildInfo() return 'Guild' end
function GetRealmName() return 'Test Realm' end
function GetServerTime() return 2000000000 end
function GetTime() return 10 end
function date() return '01.01.2033 00:00' end
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
tickers = {}
C_Timer = {
    After = function(_, fn) if fn then fn() end end,
    NewTicker = function(_, fn) if fn then table.insert(tickers, fn) end; return {Cancel = function() end} end,
}

local methods = {}
function methods:RegisterEvent() end
function methods:SetScript(name, callback) self.scripts[name] = callback end
function methods:HookScript(name, callback)
    self.hooks[name] = self.hooks[name] or {}
    table.insert(self.hooks[name], callback)
end
function methods:ClearAllPoints() self.points = {}; self.point = nil end
function methods:SetPoint(...) self.points = self.points or {}; table.insert(self.points, {...}); self.point = {...} end
function methods:SetWidth(value) self.width = value end
function methods:SetHeight(value) self.height = value end
function methods:GetWidth() return self.width or 100 end
function methods:GetHeight() return self.height or 20 end
function methods:GetStringWidth() return 100 end
function methods:GetStringHeight() return 16 end
function methods:SetJustifyH(value) self.justifyH = value end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:GetFrameLevel() return 1 end
function methods:SetMovable() end
function methods:EnableMouse() end
function methods:RegisterForDrag() end
function methods:SetClampedToScreen() end
function methods:SetText(value) self.text = value end
function methods:GetText() return self.text or '' end
function methods:SetAlpha(v) self.alpha = v end
function methods:SetShown(value)
    if value then self:Show() else self:Hide() end
end
function methods:Show()
    if self.shown then return end
    self.shown = true
    if self.scripts.OnShow then self.scripts.OnShow(self) end
    for _, callback in ipairs(self.hooks.OnShow or {}) do callback(self) end
end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown == true end
function methods:CreateFontString() return CreateFrame() end
function methods:CreateTexture() return CreateFrame() end
local meta = {__index = function(_, key)
    if key == 'TitleText' or key == 'CloseButton' then return nil end
    return methods[key] or function() end
end}
createdFrames = {}
UIParent = {}
function CreateFrame(_, name, parent)
    local frame = setmetatable({scripts = {}, hooks = {}, points = {}, parent = parent, shown = false}, meta)
    createdFrames[#createdFrames + 1] = frame
    if name then _G[name] = frame end
    return frame
end
OldKraken.UIHub = {pages = {}}
function OldKraken.UIHub:RegisterPage(key, _, _, create)
    self.pages[key] = create
end
function OldKraken.UIHub:ShowPage(key)
    local create = self.pages[key]
    local f = create(CreateFrame('Frame'))
    f:Show()
    return f
end
''')
    files = ['Locale.lua', 'ActivityCatalog.lua', 'GroupFinder.lua']
    if with_group_finder_ui:
        files.append('GroupFinderUI.lua')
    files.append('GuildEvents.lua')
    for filename in files:
        lua.execute((root / filename).read_text(encoding='utf-8'))
    lua.execute('''
        OldKraken.InitializeLocale(OldKraken.DB)
        for _, frame in ipairs(createdFrames) do
            if frame.scripts.OnEvent then frame.scripts.OnEvent(frame, 'PLAYER_LOGIN') end
        end
    ''')
    return lua


# 5.1. Four locale/title combinations + client locale independence (e.g. ruRU client).
for language, source_title, expected_title in [
    ('ukUA', 'Курганні глибини (BD)', 'Курганні глибини (BD)'),
    ('enUS', 'Курганні глибини (BD)', 'Barrow Deeps (BD)'),
    ('ukUA', 'Barrow Deeps (BD)', 'Курганні глибини (BD)'),
    ('enUS', 'Barrow Deeps (BD)', 'Barrow Deeps (BD)'),
]:
    for client_locale in ('ukUA', 'ruRU'):
        lua = build_lua_env(language=language, client_locale=client_locale)
        lua.globals().sourceTitle = source_title
        lua.globals().expectedTitle = expected_title
        lua.execute('''
            local events = OldKraken.GuildEvents
            local ev = {title = sourceTitle, activity = 'barrowdeeps'}
            assert(events:DisplayTitle(ev) == expectedTitle,
                string.format('expected %s, got %s', expectedTitle, tostring(events:DisplayTitle(ev))))
            assert(ev.title == sourceTitle, 'DisplayTitle must not mutate event.title')
        ''')


# 5.2. Custom titles and invalid/edge inputs.
for language in ('ukUA', 'enUS'):
    lua = build_lua_env(language=language)
    lua.execute('''
        local events = OldKraken.GuildEvents
        assert(events:DisplayTitle(nil) == '')
        assert(events:DisplayTitle(false) == '')
        assert(events:DisplayTitle(42) == '')
        assert(events:DisplayTitle({title = 42}) == '')
        assert(events:DisplayTitle({title = 'Мій кастомний рейд', activity = 'barrowdeeps'}) == 'Мій кастомний рейд')
        assert(events:DisplayTitle({title = 'Вогненна прірва (RFC)', activity = 'barrowdeeps'}) == 'Вогненна прірва (RFC)')
        assert(events:DisplayTitle({title = 'Курганні глибини (BD)', activity = 'unknown_raid'}) == 'Курганні глибини (BD)')
        assert(events:DisplayTitle({title = 'Курганні глибини (BD)', activity = ''}) == 'Курганні глибини (BD)')
        assert(events:DisplayTitle({title = 'Курганні глибини (BD)'}) == 'Курганні глибини (BD)')
    ''')


# 5.3, 5.4, 5.5. UI rendering (list, details, delete popup), notifications + fallback, and immutability of e.title & payload.
lua = build_lua_env(language='enUS', client_locale='ruRU', with_group_finder_ui=True)
lua.execute('''
    local events = OldKraken.GuildEvents
    local sourceTitle = 'Курганні глибини (BD)'
    assert(events:Create(sourceTitle, 'Опис рейду', GetServerTime() + 3600, 'raid', 20, 'barrowdeeps'))
    for _, fn in ipairs(tickers) do fn() end
    local payloadBefore
    for _, item in ipairs(sentPayloads) do
        if item.kind == 'CVNEW' then payloadBefore = item.payload end
    end
    assert(payloadBefore, 'Create must transmit CVNEW payload')

    -- Show Events UI and select the created event.
    local frame = OldKraken.UIHub:ShowPage('events')
    assert(#frame.visible == 1)
    assert(frame.eventRows[1].title.text == 'Barrow Deeps (BD)', 'row.title must be localized')
    frame.eventRows[1].scripts.OnClick(frame.eventRows[1])
    assert(frame.detailsTitle.text == 'Barrow Deeps (BD)', 'detailsTitle must be localized')

    -- Trigger delete confirmation popup and verify localized title argument.
    local deleteBtn = frame.eventRows[1].delete
    deleteBtn.scripts.OnClick(deleteBtn)
    assert(lastPopupTitle == 'Barrow Deeps (BD)', 'StaticPopup_Show must receive localized title')

    local entryEvent = frame.visible[1].event
    assert(entryEvent.title == sourceTitle, 'UI rendering must not mutate e.title')

    -- Notifications: GUILD_EVENTS_NEW, GUILD_EVENTS_NEW_SIGNUP, GUILD_EVENTS_CANCELLED.
    OldKraken.listeners.GUILD_EVENTS_NEW('ev1', entryEvent)
    local alert
    for _, f in ipairs(createdFrames) do
        if type(f.alertTitle) == 'table' and type(f.alertSubtitle) == 'table' then alert = f; break end
    end
    assert(alert, 'GroupFinderUI must create alert banner frame')
    assert(alert.alertTitle.text:find('Barrow Deeps (BD)', 1, true), 'GUILD_EVENTS_NEW must localize canonical title')
    assert(entryEvent.title == sourceTitle, 'GUILD_EVENTS_NEW must not mutate e.title')

    OldKraken.listeners.GUILD_EVENTS_NEW_SIGNUP('ev1', entryEvent, 'Player', 'dps')
    assert(alert.alertSubtitle.text:find('Barrow Deeps (BD)', 1, true), 'GUILD_EVENTS_NEW_SIGNUP must localize canonical title')
    assert(entryEvent.title == sourceTitle, 'GUILD_EVENTS_NEW_SIGNUP must not mutate e.title')

    OldKraken.listeners.GUILD_EVENTS_CANCELLED('ev1', entryEvent)
    assert(alert.alertSubtitle.text:find('Barrow Deeps (BD)', 1, true), 'GUILD_EVENTS_CANCELLED must localize canonical title')
    assert(entryEvent.title == sourceTitle, 'GUILD_EVENTS_CANCELLED must not mutate e.title')

    -- Custom title in notification remains unchanged.
    local customEvent = {owner = 'Tester Realm', title = 'Мій рейд', activity = 'barrowdeeps', when = entryEvent.when}
    OldKraken.listeners.GUILD_EVENTS_NEW('ev2', customEvent)
    assert(alert.alertTitle.text:find('Мій рейд', 1, true), 'custom title in notification must not be translated')

    -- Verify payload remains identical in title after all display & notification operations.
    local countBefore = #sentPayloads
    assert(events:Cancel(frame.visible[1].key))
    for _, fn in ipairs(tickers) do fn() end
    assert(#sentPayloads > countBefore)
    local updatedPayload = sentPayloads[#sentPayloads].payload
    assert(entryEvent.title == sourceTitle, 'e.title must remain unchanged')
    assert(payloadBefore:find(sourceTitle, 1, true), 'initial payload must carry original e.title')
    assert(updatedPayload:find(sourceTitle, 1, true), 'subsequent payload must still carry original e.title')
    assert(not payloadBefore:find('Barrow Deeps (BD)', 1, true), 'payload must not contain localized title')
    assert(not updatedPayload:find('Barrow Deeps (BD)', 1, true), 'updated payload must not contain localized title')

    -- Fallback when GuildEvents.DisplayTitle is unavailable.
    local savedDisplayTitle = OldKraken.GuildEvents.DisplayTitle
    OldKraken.GuildEvents.DisplayTitle = nil
    OldKraken.listeners.GUILD_EVENTS_NEW('ev3', entryEvent)
    assert(alert.alertTitle.text:find(sourceTitle, 1, true), 'fallback without DisplayTitle must show original event.title')
    OldKraken.GuildEvents.DisplayTitle = savedDisplayTitle
''')

print('Guild Events title localization checks passed')
