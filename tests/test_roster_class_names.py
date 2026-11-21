"""Ensure Guild Roster always displays English class names regardless of WoW/addon locale."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]

EXPECTED = [
    ("DRUID", "Druid", "Друид"),
    ("HUNTER", "Hunter", "Охотник"),
    ("MAGE", "Mage", "Маг"),
    ("PALADIN", "Paladin", "Паладин"),
    ("PRIEST", "Priest", "Жрец"),
    ("ROGUE", "Rogue", "Разбойник"),
    ("SHAMAN", "Shaman", "Шаман"),
    ("WARLOCK", "Warlock", "Чернокнижник"),
    ("WARRIOR", "Warrior", "Воин"),
]


def run_case(client_locale, addon_language):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals()._clientLocale = client_locale
    lua.globals()._addonLanguage = addon_language
    lua.execute(
        """
OldKraken = {
    DB = {settings = {language = _addonLanguage, roster = {search = '', status = 'all', class = 'ALL', sort = 'name', ascending = true}}},
    UIStyle = {
        Colors = {
            brandGold = {0.88, 0.69, 0.32, 1}, mutedText = {0.63, 0.67, 0.73},
            divider = {0.20, 0.23, 0.29, 0.85}, zebra = {1, 1, 1, 0.035},
            success = {0.41, 0.86, 0.55, 1}, warning = {1, 0.76, 0.42, 1},
            info = {0.40, 0.70, 1, 1}, neutral = {0.63, 0.67, 0.73, 1},
        },
        Window = function() end, Button = function() end, Dropdown = function() end,
        Panel = function() end, Input = function() end, Font = function() end,
        Chip = function(parent, text)
            local c = CreateFrame('Button', nil, parent)
            c.label = c:CreateFontString()
            c.SetLabel = function(self, v) self.label:SetText(v or '') end
            c:SetLabel(text)
            return c
        end,
        PillBadge = function(parent, text, kind)
            local p = CreateFrame('Frame', nil, parent)
            p.label = p:CreateFontString()
            p.SetKind = function(self, k) self.kind = k end
            p.SetLabel = function(self, v) self.label:SetText(v or '') end
            p:SetKind(kind)
            p:SetLabel(text)
            return p
        end,
    },
}
function GetLocale() return _clientLocale end
UISpecialFrames = {}
SlashCmdList = {}
UIParent = {}
dropdownTexts = {}
menuItems = {}
function UIDropDownMenu_SetText(frame, text) dropdownTexts[frame] = text end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_JustifyText() end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info) menuItems[#menuItems + 1] = info end
function UIDropDownMenu_Initialize(frame, callback) frame.initialize = callback end
function print() end
function IsInGuild() return true end
function UnitName() return 'Tester' end
local methods = {}
function methods:SetText(value) self.text = value end
function methods:GetText() return self.text or '' end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetEnabled(value) self.enabled = value end
function methods:SetTextColor(...) self.textColor = {...} end
function methods:SetJustifyH(value) self.justifyH = value end
function methods:SetScript(name, callback) self.scripts[name] = callback end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetShown(value) self.shown = value end
function methods:IsShown() return self.shown == true end
function methods:CreateFontString() return CreateFrame() end
function methods:CreateTexture() return CreateFrame() end
local meta = {__index = function(_, key)
    if key == 'TitleText' or key == 'CloseButton' then return nil end
    return methods[key] or function() end
end}
createdFrames = {}
function CreateFrame(kind, name, parent, template)
    local frame = setmetatable({scripts = {}, parent = parent, kind = kind, template = template}, meta)
    if name then _G[name] = frame end
    createdFrames[#createdFrames + 1] = frame
    return frame
end
"""
    )
    lua.execute((ROOT / "Locale.lua").read_text(encoding="utf-8"))
    lua.execute("OldKraken.InitializeLocale(OldKraken.DB)")
    lua.execute((ROOT / "GuildRoster.lua").read_text(encoding="utf-8"))

    # 1. Roster with only 1 member (WARRIOR with Russian className) + unknown/missing tokens.
    lua.execute(
        """
local members = {
    {'Alpha', 'Member', 1, 60, 'Воин', 'Штормград', nil, nil, true, '', 'WARRIOR'},
    {'Beta', 'Member', 1, 60, 'Рыцарь смерти', 'Акерус', nil, nil, true, '', 'DEATHKNIGHT'},
    {'Gamma', 'Member', 1, 60, 'Кастомный', 'Даларан', nil, nil, true, '', nil},
    {'Delta', 'Member', 1, 60, nil, 'Даларан', nil, nil, true, '', 'UNKNOWN_TOKEN'},
    {'Epsilon', 'Member', 1, 60, nil, 'Даларан', nil, nil, true, '', nil},
}
function GetNumGuildMembers() return #members end
function GetGuildRosterInfo(i) return unpack(members[i], 1, 11) end
OldKraken.GuildRoster:Load()
"""
    )

    # 2. Dropdown shows all 9 English class names even though 8 of them are absent from roster.
    lua.execute("menuItems = {}; OldKrakenClassDropdown.initialize(nil, 1)")
    menu = lua.eval("menuItems")
    assert menu[1]["value"] == "ALL"
    for idx, (token, english_name, _) in enumerate(EXPECTED, start=2):
        assert menu[idx]["value"] == token
        assert menu[idx]["text"] == english_name, f"Expected {english_name}, got {menu[idx]['text']}"

    # 3. Rows show English for known token, preserve fallback for unknown/missing, and keep member.class/classFile intact.
    lua.execute(
        """
rows = {}
for _, frame in ipairs(createdFrames) do
    if type(frame.member) == 'table' then rows[frame.member.name] = frame end
end
assert(rows['Alpha'].cells[4].text == 'Warrior')
assert(rows['Alpha'].cellHovers[4].fullText == 'Warrior')
assert(rows['Alpha'].member.class == 'Воин' and rows['Alpha'].member.classFile == 'WARRIOR')

assert(rows['Beta'].cells[4].text == 'Рыцарь смерти')
assert(rows['Beta'].cellHovers[4].fullText == 'Рыцарь смерти')
assert(rows['Gamma'].cells[4].text == 'Кастомный')
assert(rows['Delta'].cells[4].text == 'UNKNOWN_TOKEN')
assert(rows['Epsilon'].cells[4].text == '-')
"""
    )

    # 4. Select WARRIOR filter: button text, active filter summary, and classFile filtering.
    lua.execute(
        """
menuItems[10].func() -- WARRIOR
assert(OldKraken.DB.settings.roster.class == 'WARRIOR')
local btnText = dropdownTexts[OldKrakenClassDropdown]
assert(btnText:find('Warrior', 1, true), 'Button text must contain English Warrior: ' .. tostring(btnText))
assert(not btnText:find('Воин', 1, true))
assert(OldKrakenRosterFrame.summaryText.text:find('Warrior', 1, true))
local shown = 0
for _, frame in ipairs(createdFrames) do
    if type(frame.member) == 'table' and frame:IsShown() then
        shown = shown + 1
        assert(frame.member.name == 'Alpha')
    end
end
assert(shown == 1)
OldKrakenRosterResetButton.scripts.OnClick()
assert(OldKraken.DB.settings.roster.class == 'ALL')
"""
    )

    # 5. All 9 classes render English names even when WoW returns Russian names, and sorting still uses member.class.
    lua.execute("allMembers = {}")
    for i, (token, _, ru_name) in enumerate(EXPECTED, start=1):
        lua.execute(
            f"allMembers[{i}] = {{'M{i}', 'Member', 1, 60, '{ru_name}', 'City', nil, nil, true, '', '{token}'}}"
        )
    lua.execute(
        """
function GetNumGuildMembers() return #allMembers end
function GetGuildRosterInfo(i) return unpack(allMembers[i], 1, 11) end
OldKraken.GuildRoster:Load()
rows = {}
for _, frame in ipairs(createdFrames) do
    if type(frame.member) == 'table' then rows[frame.member.classFile] = frame end
end
"""
    )
    for token, english_name, ru_name in EXPECTED:
        lua.execute(
            f"""
assert(rows['{token}'].cells[4].text == '{english_name}')
assert(rows['{token}'].cellHovers[4].fullText == '{english_name}')
assert(rows['{token}'].member.class == '{ru_name}')
assert(rows['{token}'].member.classFile == '{token}')
"""
        )

    # 6. Sort by class preserves existing sorting behavior (compares member.class).
    lua.execute(
        """
OldKraken.DB.settings.roster.sort = 'class'
OldKraken.DB.settings.roster.ascending = true
OldKraken.GuildRoster:Render()
local visibleOrder = {}
for _, frame in ipairs(createdFrames) do
    if type(frame.member) == 'table' and frame:IsShown() then
        visibleOrder[#visibleOrder + 1] = frame.member
    end
end
for i = 2, #visibleOrder do
    assert((visibleOrder[i - 1].class or '') <= (visibleOrder[i].class or ''))
end
"""
    )


for client_locale in ("ruRU", "enUS"):
    for addon_language in ("ukUA", "enUS"):
        run_case(client_locale, addon_language)

print("GuildRoster English class name checks passed")
