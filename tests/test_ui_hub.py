from pathlib import Path

from lupa.lua51 import LuaRuntime


root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
OldKraken = {name = 'OldKraken', UIStyle = {
    Colors = {
        brandGold = {0.88, 0.69, 0.32, 1},
        panelEdge = {0.33, 0.26, 0.14, 0.68},
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
function CreateFrame(_, name, parent)
    local frame = setmetatable({scripts = {}, hooks = {}, parent = parent, shown = false}, meta)
    if name then _G[name] = frame end
    return frame
end
''')
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
assert(hub.buttons.roster.activeBar:IsShown())
assert(not hub.buttons.groups.activeBar:IsShown())
assert(hub.buttons.roster.activeBar.color[1] == OldKraken.UIStyle.Colors.brandGold[1])
assert(hub.buttons.roster.label.textColor[1] == OldKraken.UIStyle.Colors.brandGold[1])
assert(hub.buttons.groups.label.textColor[1] == OldKraken.UIStyle.Colors.text[1])
assert(hub.brandMark.texture.texture == OldKraken.UIStyle.EmblemPath())
assert(hub.brandMark.width == 52 and hub.brandMark.height == 52)
assert(hub.contentTitle.text == 'Ростер' and hub.contentTitle.textColor[1] == OldKraken.UIStyle.Colors.brandGold[1])
assert(hub.contentRule.width == 884 and hub.contentRule.color[1] == OldKraken.UIStyle.Colors.panelEdge[1])
assert(hub.buttons.roster.point[5] ~= hub.buttons.groups.point[5])
assert(hub.buttons.groups.point[5] ~= hub.buttons.events.point[5])

hub.buttons.groups.scripts.OnClick()
assert(built.groups:IsShown() and not built.roster:IsShown())
assert(hub.currentPage == 'groups' and hub.buttons.groups.activeBar:IsShown())

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
function OldKraken:On() end
''')
lua.execute((root / 'Workshop.lua').read_text(encoding='utf-8'))
lua.execute('''
local workshop = OldKraken.UIHub.pages.workshop
assert(workshop and workshop.title == 'Майстерня' and workshop.shortcut == '04')
assert(OldKraken.UIHub.buttons.workshop and OldKraken.UIHub.buttons.workshop.point[5] == -286)

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
assert(workshopFrame.page.text == '1 / 1')
assert(workshopFrame.width == 900 and workshopFrame.height == 590)
assert(not workshopFrame.previousPage:IsShown() and not workshopFrame.nextPage:IsShown())
assert(workshopFrame.page.point[4] == 418 and workshopFrame.page.width == 64)

for i=2,13 do scope.records['Tester Realm'].list[i] = {id=171,rank=i,maximum=75} end
OldKraken.Workshop:Show()
assert(workshopFrame.page.text == '1 / 2')
assert(workshopFrame.previousPage:IsShown() and workshopFrame.nextPage:IsShown())
assert(workshopFrame.previousPage.point[4] == 362 and workshopFrame.nextPage.point[4] == 494)
workshopFrame.nextPage.scripts.OnClick()
assert(workshopFrame.page.text == '2 / 2', 'next page did not advance: '..tostring(workshopFrame.page.text))
''')
