from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
LOCALE = (ROOT / 'Locale.lua').read_text(encoding='utf-8')
ROSTER = (ROOT / 'GuildRoster.lua').read_text(encoding='utf-8')


def setup_env(lang='ukUA', workshop_loaded=True, in_guild=True):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals()._lang = lang
    lua.globals()._workshop_loaded = workshop_loaded
    lua.globals()._in_guild = in_guild
    lua.execute('''
        frames = {}
        listeners = {}
        whispers = {}
        invites = {}
        recipeJumps = {}
        orderShows = 0
        orderCreateOpens = 0
        dropdownItems = {}
        rosterMembers = {
            { 'Alice Tester', 'Officer', 1, 60, 'Маг', 'Stormwind', '', '', true, nil, 'MAGE' },
            { 'Bob Tester', 'Member', 2, 58, 'Воїн', 'Orgrimmar', '', '', false, nil, 'WARRIOR' },
            { 'Alice-OtherRealm', 'Member', 2, 60, 'Маг', 'Dalaran', '', '', true, nil, 'MAGE' },
            { 'Self Player', 'Leader', 0, 60, 'Паладин', 'Ironforge', '', '', true, nil, 'PALADIN' },
        }
        for i = 1, 16 do
            rosterMembers[#rosterMembers + 1] = { 'Member ' .. i, 'Member', 3, 50, 'Воїн', 'Stormwind', '', '', false, nil, 'WARRIOR' }
        end
        specs = {
            ['Alice Tester'] = { name = 'Тайная магия', icon = 135932, points = '31/0/20' },
        }
        versions = { ['Alice Tester'] = '0.5.5-alpha.1' }
        profs = {
            ['Alice Tester'] = {
                { id = 171, rank = 275, maximum = 300, relayed = false },
                { id = 164, native = true },
            },
            ['Bob Tester'] = {},
        }
        function UnitName(unit)
            if unit == 'player' then return 'Self', 'Player' end
            return 'Self'
        end
        function GetRealmName() return 'Evermoon' end
        function IsInGuild() return _in_guild end
        function GetNumGuildMembers() return #rosterMembers end
        function GetGuildRosterInfo(i)
            local m = rosterMembers[i]
            return unpack(m, 1, 11)
        end
        function GetGuildRosterLastOnline() return 0, 0, 2, 3 end
        function GetServerTime() return 1700000000 end
        function ChatFrame_SendTell(name) whispers[#whispers + 1] = name end
        C_GuildInfo = { GuildRoster = function() end }
        RAID_CLASS_COLORS = {
            MAGE = { r = 0.25, g = 0.78, b = 0.92 },
            WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
            PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
        }
        UIDropDownMenu_SetWidth = function() end
        UIDropDownMenu_SetText = function() end
        UIDropDownMenu_JustifyText = function() end
        UIDropDownMenu_Initialize = function(f, fn) f._init = fn end
        UIDropDownMenu_CreateInfo = function() return {} end
        UIDropDownMenu_AddButton = function(item) dropdownItems[#dropdownItems + 1] = item end
        function ToggleDropDownMenu(_, _, f)
            dropdownItems = {}
            if f._init then f._init(f, 1) end
        end
        function CloseDropDownMenus() end
        UISpecialFrames = {}
        SlashCmdList = {}
        local function makeFrame(kind, name, parent)
            local f = setmetatable({
                kind = kind, name = name, parent = parent,
                shown = true, enabled = true, alpha = 1, level = 1,
                scripts = {}, events = {}, children = {}, vscroll = 0,
            }, { __index = function(_, k) if type(k) == 'string' and k:match('^%u') then return function() end end end })
            function f:SetSize(w, h) self.w = w; self.h = h end
            function f:SetWidth(w) self.w = w end
            function f:SetHeight(h) self.h = h end
            function f:GetWidth() return self.w or 800 end
            function f:GetHeight() return self.h or 440 end
            function f:SetPoint() end
            function f:ClearAllPoints() end
            function f:SetAllPoints() end
            function f:SetFrameStrata() end
            function f:SetFrameLevel(l) self.level = l end
            function f:GetFrameLevel() return self.level or 1 end
            function f:EnableMouse() end
            function f:RegisterForClicks(...) self.clicks = {...} end
            function f:RegisterEvent(ev) self.events[ev] = true end
            function f:SetScript(k, fn) self.scripts[k] = fn end
            function f:GetScript(k) return self.scripts[k] end
            function f:SetText(t) self.text = t end
            function f:GetText() return self.text or '' end
            function f:SetTextColor(r, g, b) self.color = {r, g, b} end
            function f:SetJustifyH() end
            function f:SetWordWrap() end
            function f:SetAutoFocus() end
            function f:SetTextInsets() end
            function f:SetMaxLetters() end
            function f:SetScrollChild() end
            function f:Enable() self.enabled = true end
            function f:Disable() self.enabled = false end
            function f:SetAlpha(a) self.alpha = a end
            function f:Show() self.shown = true end
            function f:Hide() self.shown = false end
            function f:SetShown(v) self.shown = v == true end
            function f:IsShown() return self.shown end
            function f:SetVerticalScroll(v) self.vscroll = v end
            function f:GetVerticalScroll() return self.vscroll end
            function f:SetHighlightTexture() end
            function f:SetTexture(tex) self.texture = tex end
            function f:SetColorTexture() end
            function f:CreateTexture() return makeFrame('Texture', nil, self) end
            function f:CreateFontString() return makeFrame('FontString', nil, self) end
            if name then _G[name] = f end
            frames[#frames + 1] = f
            return f
        end
        CreateFrame = makeFrame
        UIParent = makeFrame('Frame', 'UIParent')
        OldKraken = {
            DB = { settings = { language = _lang, roster = { status = 'all', sort = 'level', ascending = true, class = 'ALL', search = '' } } },
            UIStyle = {
                Colors = { window = {0.025, 0.035, 0.055, 1}, brandGold = {0.88, 0.69, 0.32, 1}, mutedText = {0.6, 0.6, 0.6} },
                Button = function() end, Input = function() end, Dropdown = function() end, Panel = function() end,
                Window = function() end, Font = function() end,
            },
            Communication = {
                HasRosterAddon = function(_, n) return versions[n] ~= nil end,
                GetRosterVersion = function(_, n) return versions[n] end,
                CompareVersions = function(_, a, b) return a == b and 0 or -1 end,
                GetRosterSpec = function(_, n) return specs[n] end,
            },
        }
        function OldKraken:InvitePlayer(name) invites[#invites + 1] = name; return true end
        function OldKraken:On(ev, fn) listeners[ev] = listeners[ev] or {}; table.insert(listeners[ev], fn) end
        function OldKraken:Fire(ev, ...) for _, fn in ipairs(listeners[ev] or {}) do fn(...) end end
        if _workshop_loaded then
            _ws_active = true
            OldKraken.Workshop = {
                IsActive = function() return _ws_active end,
                GetMemberProfessions = function(_, n) return _ws_active and (profs[n] or {}) or {} end,
                ProfessionInfo = function(_, id) return id == 171 and 'Алхімія' or 'Ковальство', 136240 end,
                RefreshNativeProfessions = function() end,
            }
            OldKraken.WorkshopRecipes = {
                ShowMemberProfession = function(_, n, id) recipeJumps[#recipeJumps + 1] = { name = n, id = id } end,
            }
            OldKraken.WorkshopOrders = {
                Show = function() orderShows = orderShows + 1 end,
                OpenCreateForm = function(_, prof, onBack)
                    orderCreateOpens = orderCreateOpens + 1
                    orderCreateArgs = orderCreateArgs or {}
                    orderCreateArgs[#orderCreateArgs + 1] = { prof = prof, onBack = onBack }
                    return true
                end,
            }
        end
    ''')
    lua.execute(LOCALE)
    lua.execute('OldKraken.InitializeLocale(OldKraken.DB)')
    lua.execute(ROSTER)
    return lua


# 1-5: LKM/PKM on row & cellHovers, prof icon unchanged, SPEC2, professions, online/offline/self actions
lua = setup_env('ukUA', workshop_loaded=True, in_guild=True)
lua.execute('''
    local Roster = OldKraken.GuildRoster
    Roster:Show()
    local rf
    for _, f in ipairs(frames) do if f.profilePanel then rf = f; break end end
    assert(rf ~= nil and not rf.profilePanel:IsShown())
    -- Set non-zero scroll offset before opening profile
    rf.scrollFrame:SetVerticalScroll(80)

    -- Find Alice row and an empty-profession Member row (rendered in contentFrame children)
    local aliceRow, emptyProfRow
    for _, f in ipairs(frames) do
        if f.professions and f.member then
            if f.member.name == 'Alice Tester' then aliceRow = f
            elseif f.member.name == 'Member 1' then emptyProfRow = f end
        end
    end
    assert(aliceRow ~= nil and #aliceRow.professions == 2)
    assert(emptyProfRow ~= nil and emptyProfRow.cells[6]:IsShown() and emptyProfRow.cells[6].text == '—')
    -- Left-click on cellHover[1] opens profile
    aliceRow.cellHovers[1].scripts.OnClick(aliceRow.cellHovers[1], 'LeftButton')
    assert(rf.profilePanel:IsShown() and rf.profilePanel.member.name == 'Alice Tester')
    assert(not rf.scrollFrame:IsShown())
    local p = rf.profilePanel
    assert(p.specName.text ~= '' and p.specPoints.text:find('31/0/20', 1, true))
    assert(p.profRows[1]:IsShown() and p.profRows[1].value:GetText():find('275/300', 1, true))
    assert(p.profRows[2]:IsShown() and p.profRows[2].value:GetText():find('Із ігрового ростера', 1, true))
    assert(p.whisperButton.enabled and p.inviteButton.enabled and p.recipesButton.enabled and p.orderButton.enabled)

    -- Quick actions: whisper, invite, recipes, create order
    p.whisperButton.scripts.OnClick(p.whisperButton)
    p.inviteButton.scripts.OnClick(p.inviteButton)
    p.recipesButton.scripts.OnClick(p.recipesButton)
    p.orderButton.scripts.OnClick(p.orderButton)
    assert(whispers[1] == 'Alice Tester' and invites[1] == 'Alice Tester')
    assert(recipeJumps[1].name == 'Alice Tester' and recipeJumps[1].id == 171)
    assert(orderShows == 1 and orderCreateOpens == 1)
    assert(orderCreateArgs[1].prof == 171 and type(orderCreateArgs[1].onBack) == 'function')

    -- Returning to roster preserves filters/sort and scroll offset
    p.backButton.scripts.OnClick(p.backButton)
    assert(not p:IsShown() and rf.scrollFrame:IsShown() and rf.scrollFrame:GetVerticalScroll() == 80)
    -- External onBack from Create Order returns straight to Alice's profile
    orderCreateArgs[1].onBack()
    assert(rf.profilePanel:IsShown() and rf.profilePanel.member.name == 'Alice Tester')
    p.backButton.scripts.OnClick(p.backButton)
    rf.scrollFrame:SetVerticalScroll(0)

    -- Verify profile does not re-sort crafting professions by numeric ID (171 before 164 follows GetMemberProfessions)
    profs['Alice Tester'] = {
        { id = 171, rank = 300, maximum = 300 },
        { id = 164, rank = 300, maximum = 300 },
    }
    Roster:RenderVisible()
    aliceRow = nil
    for _, f in ipairs(frames) do
        if f.professions and f.member and f.member.name == 'Alice Tester' then aliceRow = f; break end
    end
    assert(aliceRow ~= nil)
    aliceRow.cellHovers[1].scripts.OnClick(aliceRow.cellHovers[1], 'LeftButton')
    assert(p.profRows[1].professionID == aliceRow.professions[1].professionID, 'profile order must match roster row order')
    assert(p.profRows[2].professionID == aliceRow.professions[2].professionID, 'profile order must match roster row order')
    assert(p.profRows[1].professionID == 171 and p.profRows[2].professionID == 164, 'profile must follow GetMemberProfessions order')
    assert(p.firstCraftProfessionID == 171, 'firstCraftProfessionID must match first displayed crafting profession')
    p.backButton.scripts.OnClick(p.backButton)
    Roster:RenderVisible()
    for _, f in ipairs(frames) do
        if f.professions and f.member and f.member.name == 'Alice Tester' then aliceRow = f; break end
    end

    -- Clicking profession icon on row does NOT open profile, keeps ShowMemberProfession
    aliceRow.professions[1].scripts.OnClick(aliceRow.professions[1])
    assert(not p:IsShown() and #recipeJumps == 2)

    -- Right-click opens context menu with 'Відкрити профіль' as first item
    aliceRow.cellHovers[1].scripts.OnClick(aliceRow.cellHovers[1], 'RightButton')
    assert(dropdownItems[2].text == 'Відкрити профіль')
    dropdownItems[2].func()
    assert(p:IsShown() and p.member.name == 'Alice Tester')
''')

# 6-8: Profile updates on GUILD_ROSTER_UPDATE, ROSTER_ADDON_CHANGED, WORKSHOP_PROFESSIONS_CHANGED even if filtered out, and closes if removed
lua.execute('''
    local Roster = OldKraken.GuildRoster
    local rf
    for _, f in ipairs(frames) do if f.profilePanel then rf = f; break end end
    local p = rf.profilePanel
    -- Apply search filter that hides Alice Tester from filteredData
    OldKraken.DB.settings.roster.search = 'Bob'
    Roster:Render()
    assert(p:IsShown() and p.member.name == 'Alice Tester', 'profile must remain open when filtered out')

    -- ROSTER_ADDON_CHANGED updates SPEC2 (including RESET -> nil)
    specs['Alice Tester'] = nil
    OldKraken:Fire('ROSTER_ADDON_CHANGED')
    for _, f in ipairs(frames) do
        if f.scripts and f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.2) end
    end
    assert(p.specName.text == 'Дані спеціалізації відсутні.')

    -- WORKSHOP_PROFESSIONS_CHANGED updates professions
    profs['Alice Tester'] = {}
    OldKraken:Fire('WORKSHOP_PROFESSIONS_CHANGED')
    for _, f in ipairs(frames) do
        if f.scripts and f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.2) end
    end
    assert(p.profEmpty:IsShown() and p.profEmpty.text == 'Професії ще не зафіксовані.')

    -- GUILD_ROSTER_UPDATE removes Alice -> profile closes
    table.remove(rosterMembers, 1)
    Roster:Load()
    assert(not p:IsShown(), 'profile must close when member leaves guild roster')
''')

# Self vs other-realm vs offline checks
lua.execute('''
    local Roster = OldKraken.GuildRoster
    OldKraken.DB.settings.roster.search = ''
    OldKraken.DB.settings.roster.ascending = false
    Roster:Render()
    local rf
    for _, f in ipairs(frames) do if f.profilePanel then rf = f; break end end
    local p = rf.profilePanel

    local selfRow, otherRow, bobRow
    for _, f in ipairs(frames) do
        if f.professions and f.member and f.member.name == 'Self Player' then selfRow = f end
        if f.professions and f.member and f.member.name == 'Alice-OtherRealm' then otherRow = f end
        if f.professions and f.member and f.member.name == 'Bob Tester' then bobRow = f end
    end
    selfRow.scripts.OnClick(selfRow, 'LeftButton')
    assert(not p.whisperButton.enabled and not p.inviteButton.enabled and not p.orderButton.enabled, 'self actions must be disabled')
    p.backButton.scripts.OnClick(p.backButton)

    bobRow.scripts.OnClick(bobRow, 'LeftButton')
    assert(not p.whisperButton.enabled and not p.inviteButton.enabled, 'offline whisper/invite must be disabled')
    p.backButton.scripts.OnClick(p.backButton)

    otherRow.scripts.OnClick(otherRow, 'LeftButton')
    assert(p.whisperButton.enabled and p.inviteButton.enabled, 'other-realm Alice must not match self')
''')

# Unavailable Workshop state
lua_no_ws = setup_env('enUS', workshop_loaded=False, in_guild=True)
lua_no_ws.execute('''
    local Roster = OldKraken.GuildRoster
    Roster:Show()
    local rf, aliceRow
    for _, f in ipairs(frames) do
        if f.profilePanel then rf = f end
        if f.professions and f.member and f.member.name == 'Alice Tester' then aliceRow = f end
    end
    aliceRow.scripts.OnClick(aliceRow, 'LeftButton')
    local p = rf.profilePanel
    assert(p.profEmpty:IsShown() and p.profEmpty.text == 'Profession data unavailable.')
    assert(p.backButton.text == '‹ Back to roster')
    assert(p.whisperButton.text == 'Whisper' and p.inviteButton.text == 'Invite to group')
    assert(p.recipesButton.text == 'View recipes' and p.orderButton.text == 'Create order')
    assert(p.specName.text == 'Talent split: ' or p.specPoints.text:find('Talent split:', 1, true))
''')

# Workshop loaded, in guild, DB exists, but Workshop:IsActive() == false -> unavailable, then activates live
lua_inactive = setup_env('ukUA', workshop_loaded=True, in_guild=True)
lua_inactive.execute('''
    _ws_active = false
    local Roster = OldKraken.GuildRoster
    Roster:Show()
    local rf, aliceRow
    for _, f in ipairs(frames) do
        if f.profilePanel then rf = f end
        if f.professions and f.member and f.member.name == 'Alice Tester' then aliceRow = f end
    end
    aliceRow.scripts.OnClick(aliceRow, 'LeftButton')
    local p = rf.profilePanel
    assert(p:IsShown() and p.profEmpty:IsShown() and p.profEmpty.text == 'Дані про професії недоступні.')
    assert(not p.profRows[1]:IsShown())
    -- Activate Workshop and fire WORKSHOP_PROFESSIONS_CHANGED without reopening profile
    _ws_active = true
    OldKraken:Fire('WORKSHOP_PROFESSIONS_CHANGED')
    for _, f in ipairs(frames) do
        if f.scripts and f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.2) end
    end
    assert(not p.profEmpty:IsShown() and p.profRows[1]:IsShown() and p.profRows[1].value:GetText():find('275/300', 1, true))
''')

# Real Communication.lua: UnitName('player') -> ("Alice", "Tester") must match roster row "Alice Tester"
lua_real_comm = setup_env('ukUA', workshop_loaded=True, in_guild=True)
lua_real_comm.execute('''
    function UnitName(unit)
        if unit == 'player' then return 'Alice', 'Tester' end
        return 'Alice'
    end
    function GetGuildInfo() return 'Kraken' end
    function GetTime() return 100 end
    function GetAddOnMetadata() return '0.5.5-alpha.1' end
    OldKraken.version = '0.5.5-alpha.1'
    OldKraken.DB = { settings = { roster = {}, language = 'ukUA' }, roster = {} }
    C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        SendAddonMessage = function() return true end,
    }
    C_Timer = { NewTicker = function() return {} end, After = function(_, fn) fn() end }
''')
lua_real_comm.execute((ROOT / 'Communication.lua').read_text(encoding='utf-8'))
lua_real_comm.execute(ROSTER)
lua_real_comm.execute('''
    local comm = OldKraken.Communication
    assert(comm:HasRosterAddon('Alice Tester') == true, 'full roster name must match self')
    assert(comm:HasRosterAddon('Alice') == true, 'short player name must match self')
    assert(comm:GetRosterVersion('Alice Tester') == '0.5.5-alpha.1', 'self version must resolve for full roster name')
    assert(comm:GetRosterVersion('Alice') == '0.5.5-alpha.1', 'self version must resolve for short name')
    assert(not comm:HasRosterAddon('Alice-OtherRealm'), 'other-realm Alice must not match self')
    assert(comm:GetRosterVersion('Alice-OtherRealm') == nil, 'other-realm Alice must have no version')

    local Roster = OldKraken.GuildRoster
    Roster:Show()
    local rf, aliceRow
    for _, f in ipairs(frames) do
        if f.profilePanel then rf = f end
        if f.professions and f.member and f.member.name == 'Alice Tester' then aliceRow = f end
    end
    assert(aliceRow, 'Alice Tester row must exist')
    aliceRow.scripts.OnClick(aliceRow, 'LeftButton')
    local p = rf.profilePanel
    assert(p:IsShown(), 'profile panel must open')
    assert(p.addonText.text:find('0.5.5-alpha.1', 1, true), 'self profile must show local addon version, got: ' .. tostring(p.addonText.text))
''')

print('Inline player profile checks passed')
