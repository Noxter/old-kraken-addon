from pathlib import Path

from lupa.lua51 import LuaRuntime


root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
OldKraken = {
    DB = {settings = {roster = {search='', status='all', class='ALL', sort='name', ascending=true}}},
    UIStyle = {Window=function() end, Button=function() end, Dropdown=function() end, Panel=function() end, Input=function() end},
}
UISpecialFrames = {}
SlashCmdList = {}
UIParent = {}
function UIDropDownMenu_SetText() end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_JustifyText() end
function UIDropDownMenu_Initialize() end
function print() end
function IsInGuild() return true end
function GetNumGuildMembers() return 2 end
function GetGuildRosterInfo(index)
    if index == 1 then return 'Online Member', 'Member', 1, 60, 'Warrior', 'Dun Morogh', nil, nil, true, '', 'WARRIOR' end
    return 'Offline Member', 'Member', 1, 60, 'Mage', 'Stormwind', nil, nil, false, '', 'MAGE'
end
inviteCalls = {}
C_PartyInfo = {InviteUnit=function(name) inviteCalls[#inviteCalls + 1] = name; return true end}

local methods = {}
function methods:SetText(value) self.text = value end
function methods:GetText() return self.text or '' end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetEnabled(value) self.enabled = value end
function methods:SetScript(name, callback) self.scripts[name] = callback end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetShown(value) self.shown = value end
function methods:IsShown() return self.shown == true end
function methods:CreateFontString() return CreateFrame() end
function methods:CreateTexture() return CreateFrame() end
local meta = {__index=function(_, key)
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
''')
lua.execute((root / 'Core.lua').read_text(encoding='utf-8'))
lua.execute('''
OldKraken.UIStyle = {Window=function() end, Button=function() end, Dropdown=function() end, Panel=function() end, Input=function() end}
''')
lua.execute((root / 'GuildRoster.lua').read_text(encoding='utf-8'))
lua.execute('''
OldKraken.GuildRoster:Load()
local inviteButtons = {}
for _, frame in ipairs(createdFrames) do
    if frame.kind == 'Button' then
        assert(frame.text ~= 'Події' and frame.text ~= 'Майстерня')
    end
    if frame.kind == 'Button' and frame.template == 'UIPanelButtonTemplate'
        and (frame.text == 'Інвайт' or frame.text == 'Офлайн') then
        inviteButtons[frame.memberName] = frame
    end
end

local online = inviteButtons['Online Member']
local offline = inviteButtons['Offline Member']
assert(online and online.online and online.enabled)
assert(offline and not offline.online and not offline.enabled)
online.scripts.OnClick(online)
assert(#inviteCalls == 1 and inviteCalls[1] == 'Online Member')
offline.scripts.OnClick(offline)
assert(#inviteCalls == 1, 'offline members must not be invited')
''')
