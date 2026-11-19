from pathlib import Path

from lupa.lua51 import LuaRuntime


root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
ui_mocks = '''
OldKraken = {name = 'OldKraken', UIStyle = {
    Colors = {
        brandGold = {0.88, 0.69, 0.32, 1},
        panelEdge = {0.33, 0.26, 0.14, 0.68},
        button = {0.08, 0.095, 0.125, 1},
        buttonEdge = {0.20, 0.23, 0.29, 0.85},
        sel = {0.102, 0.141, 0.302, 1},
        selEdge = {0.478, 0.541, 0.980, 1},
        white = {1, 1, 1, 1},
        text = {0.93, 0.94, 0.96},
        mutedText = {0.63, 0.67, 0.73},
    },
    EmblemPath=function() return 'OldKrakenEmblem.tga' end,
    Window=function() end, Panel=function() end, Button=function() end, Dropdown=function() end, Input=function() end,
}}
UIParent = {}
UISpecialFrames = {}
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetText() end
function UIDropDownMenu_Initialize() end
local methods = {}
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetPoint(...) self.point = {...} end
function methods:SetWidth(value) self.width = value end
function methods:SetJustifyH(value) self.justifyH = value end
function methods:ClearAllPoints() self.point = nil end
function methods:SetText(value) self.text = value end
function methods:SetEnabled(value) self.enabled = value end
function methods:RegisterEvent(name) self.events[name] = true end
function methods:UnregisterEvent(name) self.events[name] = nil end
function methods:SetTextColor(...) self.textColor = {...} end
function methods:SetColorTexture(...) self.color = {...} end
function methods:SetTexture(value) self.texture = value end
function methods:SetShown(value) if value then self:Show() else self:Hide() end end
function methods:Show()
    if self.shown then return end
    self.shown = true
    if self.scripts.OnShow then self.scripts.OnShow(self) end
    for _, callback in ipairs(self.hooks and self.hooks.OnShow or {}) do callback(self) end
end
function methods:Hide()
    self.shown = false
    if self.scripts.OnHide then self.scripts.OnHide(self) end
    local hooks = rawget(self, 'hooks')
    for _, callback in ipairs(hooks and hooks.OnHide or {}) do callback(self) end
end
function methods:IsShown() return self.shown == true end
function methods:SetScript(name, callback) self.scripts[name] = callback end
function methods:HookScript(name, callback)
    self.hooks[name] = self.hooks[name] or {}
    table.insert(self.hooks[name], callback)
end
function methods:CreateFontString() return CreateFrame() end
function methods:CreateTexture() return CreateFrame() end
local meta = {__index=function(_, key)
    if key == 'TitleText' or key == 'CloseButton' then return nil end
    return methods[key] or function() end
end}
createdFrames = {}
function CreateFrame(_, name, parent)
    local frame = setmetatable({scripts = {}, hooks = {}, events = {}, parent = parent, shown = false}, meta)
    createdFrames[#createdFrames + 1] = frame
    if name then _G[name] = frame end
    if name == 'OldKrakenHubFrame' then frame.TitleText = CreateFrame() end
    return frame
end
'''
lua.execute(ui_mocks)
lua.execute((root / 'UIHub.lua').read_text(encoding='utf-8'))
lua.execute('''
local built = {}
for _, page in ipairs({
    {'roster', 'Ростер', '01'},
    {'groups', 'Групи', '02'},
    {'events', 'Івенти', '03'},
}) do
    local key, title, shortcut = page[1], page[2], page[3]
    OldKraken.UIHub:RegisterPage(key, title, shortcut, function(parent)
        built[key] = CreateFrame('Frame', nil, parent)
        built[key]:Hide()
        return built[key]
    end)
end

local hub = OldKraken.UIHub
hub:ShowPage('roster')
assert(built.roster and built.roster.parent == hub.content)
assert(built.roster:IsShown() and hub.frame:IsShown())
assert(not built.groups and not built.events)
assert(hub.buttons.roster.activeFill:IsShown() and not hub.buttons.roster.activeBar:IsShown())
assert(hub.buttons.roster.activeBorder:IsShown())
assert(hub.buttons.roster.activeFill.color[1] == 0.102 and hub.buttons.roster.activeBorder.color[1] == 0.478)
assert(hub.buttons.roster.label.textColor[1] == OldKraken.UIStyle.Colors.white[1])
assert(hub.buttons.roster.shortcut.textColor[1] == OldKraken.UIStyle.Colors.brandGold[1])
assert(not hub.buttons.groups.activeFill:IsShown() and not hub.buttons.groups.activeBorder:IsShown())
assert(hub.buttons.groups.label.textColor[1] == OldKraken.UIStyle.Colors.mutedText[1])
assert(hub.buttons.groups.shortcut.textColor[1] == OldKraken.UIStyle.Colors.mutedText[1])
assert(hub.brandMark.texture.texture == OldKraken.UIStyle.EmblemPath())
assert(hub.brandMark.width == 40 and hub.brandMark.height == 40)
assert(hub.frame.width == 1140 and hub.frame.height == 680)
assert(hub.content.width == 948 and hub.content.height == 648)
assert(hub.contentTitle.text == 'Ростер' and hub.contentTitle.textColor[1] == OldKraken.UIStyle.Colors.brandGold[1])
assert(hub.contentRule.width == 900 and hub.contentRule.color[1] == OldKraken.UIStyle.Colors.panelEdge[1])
assert(hub.buttons.roster.point[5] ~= hub.buttons.groups.point[5])
assert(hub.buttons.groups.point[5] ~= hub.buttons.events.point[5])

hub.buttons.groups.scripts.OnClick()
assert(built.groups:IsShown() and not built.roster:IsShown())
assert(hub.currentPage == 'groups' and hub.buttons.groups.activeFill:IsShown() and hub.buttons.groups.activeBorder:IsShown() and not hub.buttons.roster.activeFill:IsShown())

hub:Toggle('groups')
assert(not hub.frame:IsShown() and not built.groups:IsShown())
hub:Toggle('events')
assert(built.events:IsShown() and hub.frame:IsShown())
assert(not built.groups:IsShown() and hub.currentPage == 'events')
assert(hub.contentTitle.text == 'Івенти')
''')
lua.execute('''
OldKraken.Communication = {RegisterHandler=function() end}
function OldKraken.Communication:SendProtocol() return true end
OldKraken.GroupFinder = {_pack=function() return '' end, _unpackFields=function() return nil end}
OldKraken.WorkshopRecipes = {
    GetProfessionSummaries=function() return {[171]={recipes=3,members=2}} end,
    ShowProfession=function(_, id) selectedProfession=id end,
}
function OldKraken:On() end
''')
lua.execute((root / 'Workshop.lua').read_text(encoding='utf-8'))
lua.execute('''
local workshop = OldKraken.UIHub.pages.workshop
assert(workshop and workshop.title == 'Майстерня' and workshop.shortcut == '04')
assert(OldKraken.UIHub.buttons.workshop and OldKraken.UIHub.buttons.workshop.point[5] == -250)

function UnitName() return 'Tester', 'Realm' end
function GetGuildInfo() return 'Guild' end
function GetRealmName() return 'Test Realm' end
function GetServerTime() return 2000000000 end
function date() return '01.01.2033 00:00' end
OldKraken.DB = {workshop={guilds={}}}
local scope = {records={['Tester Realm']={timestamp=GetServerTime(),list={{id=171,rank=1,maximum=75}}}}}
OldKraken.DB.workshop.guilds['Test Realm\\001Guild'] = scope
OldKraken.Workshop:Show()
local workshopFrame = OldKraken.UIHub.pages.workshop.frame
assert(workshopFrame.width == 900 and workshopFrame.height == 608)
assert(rawget(workshopFrame, 'page') == nil and rawget(workshopFrame, 'previousPage') == nil and rawget(workshopFrame, 'nextPage') == nil)
assert(#workshopFrame.professionCards == 6)
local alchemy = workshopFrame.professionCards[1]
assert(alchemy.profession == 171 and alchemy.detail.text == '3 рецепти · 2 майстри')
alchemy.scripts.OnClick(alchemy)
assert(selectedProfession == 171, 'profession card did not open its profession')

for i=2,13 do scope.records['Tester Realm'].list[i] = {id=171,rank=i,maximum=75} end
OldKraken.Workshop:Show()
assert(#workshopFrame.professionCards == 6 and rawget(workshopFrame, 'page') == nil)
local enchanting = workshopFrame.professionCards[6]
enchanting.scripts.OnClick(enchanting)
assert(selectedProfession == 333, 'profession cards changed when saved records increased')

OldKraken.DB.settings = OldKraken.DB.settings or {}
local ctrlHeld = false
function IsControlKeyDown() return ctrlHeld end
OldKraken.DB.settings.uiScale = 1.0
assert(OldKraken.UIHub:HandleScaleWheel(1) == false, 'scale wheel should ignore scroll without Ctrl')
assert(OldKraken.DB.settings.uiScale == 1.0)
ctrlHeld = true
assert(OldKraken.UIHub:HandleScaleWheel(1) == true)
assert(OldKraken.DB.settings.uiScale == 1.15)
assert(OldKraken.UIHub:HandleScaleWheel(1) == true)
assert(OldKraken.UIHub:HandleScaleWheel(1) == true)
assert(OldKraken.UIHub:HandleScaleWheel(1) == true)
assert(OldKraken.DB.settings.uiScale == 1.4, 'scale wheel should clamp at 1.4')
for _ = 1, 6 do OldKraken.UIHub:HandleScaleWheel(-1) end
assert(OldKraken.DB.settings.uiScale == 0.85, 'scale wheel should clamp at 0.85')
''')


def load_localized_addon(saved_language=None):
    runtime = LuaRuntime(unpack_returned_tuples=True)
    runtime.execute(ui_mocks)
    runtime.execute('''
        local language = ...
        OldKrakenDB = {settings = {language = language}}
        StaticPopupDialogs = {}
        SlashCmdList = {}
        mockStyle = OldKraken.UIStyle
        reloads = 0
        function ReloadUI() reloads = reloads + 1 end
        function GetServerTime() return 2000000000 end
        function GetTime() return 1 end
        function GetGuildInfo(unit)
            assert(unit == 'player')
            return guildName
        end
    ''', saved_language)
    for entry in (root / 'OldKraken.toc').read_text(encoding='utf-8').splitlines():
        if entry.endswith('.lua'):
            runtime.execute((root / entry).read_text(encoding='utf-8'), 'OldKraken')
            if entry == 'Core.lua':
                runtime.execute('OldKraken.UIStyle = mockStyle')
    runtime.execute('''
        for _, frame in ipairs(createdFrames) do
            if frame.events.ADDON_LOADED and frame.events.PLAYER_GUILD_UPDATE then
                addonEvents = frame
                break
            end
        end
        assert(addonEvents)
        addonEvents.scripts.OnEvent(addonEvents, 'ADDON_LOADED', 'OldKraken')
        function settingsControl(text)
            local page = OldKraken.UIHub.pages.settings.frame
            for _, frame in ipairs(createdFrames) do
                if frame.parent == page and frame.text == text then return frame end
            end
            error('Settings control not found: ' .. text)
        end
    ''')
    return runtime


ukrainian = load_localized_addon()
ukrainian.execute('''
    assert(OldKraken.GetLanguage() == 'ukUA')
    local hub = OldKraken.UIHub
    local sidebarBrand
    local origBind = OldKraken.BindGuildTitle
    OldKraken.BindGuildTitle = function(win, suffix, sidebar)
        if not suffix and sidebar then sidebarBrand = sidebar end
        return origBind(win, suffix, sidebar)
    end
    hub:ShowPage('settings')
    assert(hub.contentTitle.text == 'Налаштування')
    assert(hub.frame.TitleText.text == 'Old Kraken')
    assert(sidebarBrand and sidebarBrand.text == 'Old Kraken', 'sidebar brand FontString must exist')
    local modWin = CreateFrame('Frame')
    modWin.TitleText = modWin:CreateFontString()
    OldKraken.BindGuildTitle(modWin, 'Майстерня')
    assert(modWin.TitleText.text == 'Old Kraken — Майстерня')

    guildName = 'Морські вовки'
    addonEvents.scripts.OnEvent(addonEvents, 'PLAYER_GUILD_UPDATE', 'player')
    assert(hub.frame.TitleText.text == 'Old Kraken')
    assert(sidebarBrand.text == 'Морські вовки')
    assert(modWin.TitleText.text == 'Old Kraken — Майстерня')

    guildName = nil
    addonEvents.scripts.OnEvent(addonEvents, 'PLAYER_GUILD_UPDATE', 'player')
    assert(hub.frame.TitleText.text == 'Old Kraken')
    assert(sidebarBrand.text == 'Old Kraken')
    assert(modWin.TitleText.text == 'Old Kraken — Майстерня')

    guildName = 'Нова гільдія'
    addonEvents.scripts.OnEvent(addonEvents, 'PLAYER_GUILD_UPDATE', 'player')
    assert(hub.frame.TitleText.text == 'Old Kraken')
    assert(sidebarBrand.text == 'Нова гільдія')
    assert(modWin.TitleText.text == 'Old Kraken — Майстерня')
    local apply = settingsControl('Застосувати й перезавантажити')
    assert(not apply.enabled and not settingsControl('Українська').enabled)
    settingsControl('English').scripts.OnClick()
    assert(apply.enabled and OldKrakenDB.settings.language == 'ukUA')
    apply.scripts.OnClick()
    assert(reloads == 1 and OldKrakenDB.settings.language == 'enUS')
''')

english = load_localized_addon(ukrainian.eval('OldKrakenDB.settings.language'))
english.execute('''
    assert(OldKraken.GetLanguage() == 'enUS')
    local hub = OldKraken.UIHub
    local enSidebarBrand
    local origBind = OldKraken.BindGuildTitle
    OldKraken.BindGuildTitle = function(win, suffix, sidebar)
        if not suffix and sidebar then enSidebarBrand = sidebar end
        return origBind(win, suffix, sidebar)
    end
    guildName = 'Sea Wolves'
    hub:ShowPage('settings')
    addonEvents.scripts.OnEvent(addonEvents, 'PLAYER_GUILD_UPDATE', 'player')
    assert(hub.contentTitle.text == 'Settings')
    assert(hub.buttons.roster.label.text == 'Roster')
    assert(hub.buttons.groups.label.text == 'Groups')
    assert(hub.buttons.events.label.text == 'Events')
    assert(hub.buttons.workshop.label.text == 'Workshop')
    assert(hub.frame.TitleText.text == 'Old Kraken')
    assert(enSidebarBrand and enSidebarBrand.text == 'Sea Wolves', 'English hub sidebar must display guild name Sea Wolves')
    assert(OldKraken.ActivityCatalog.dungeon[2].label == 'Ragefire Chasm (RFC)')
    assert(OldKraken.Workshop:ProfessionInfo(171) == 'Alchemy')
    assert(StaticPopupDialogs.OLDKRAKEN_REMOVE_MEMBER.button1 == 'Delete')
    assert(StaticPopupDialogs.OLDKRAKEN_EVENT_DELETE.button2 == 'Back')
    assert(StaticPopupDialogs.OLDKRAKEN_ORDER_CARD_CANCEL.button1 == 'Cancel')
    settingsControl('Українська').scripts.OnClick()
    settingsControl('Apply and reload').scripts.OnClick()
    assert(reloads == 1 and OldKrakenDB.settings.language == 'ukUA')
''')
