from pathlib import Path

from lupa.lua51 import LuaRuntime


root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
OldKraken = {UIStyle = {Window=function() end, Panel=function() end, Button=function() end}}
UIParent = {}
UISpecialFrames = {}
local methods = {}
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetPoint(...) self.point = {...} end
function methods:SetText(value) self.text = value end
function methods:SetTextColor(...) self.textColor = {...} end
function methods:SetColorTexture(...) end
function methods:SetShown(value) self.shown = value end
function methods:Show() self.shown = true end
function methods:Hide()
    self.shown = false
    if self.scripts.OnHide then self.scripts.OnHide(self) end
    local hooks = rawget(self, 'hooks')
    for _, callback in ipairs(hooks and hooks.OnHide or {}) do callback(self) end
end
function methods:IsShown() return self.shown == true end
function methods:SetScript(name, callback) self.scripts[name] = callback end
function methods:HookScript(name, callback)
    local hooks = rawget(self, 'hooks') or {}
    hooks[name] = hooks[name] or {}
    table.insert(hooks[name], callback)
    rawset(self, 'hooks', hooks)
end
function methods:CreateFontString() return CreateFrame() end
function methods:CreateTexture() return CreateFrame() end
local meta = {__index=function(_, key)
    if key == 'TitleText' or key == 'CloseButton' then return nil end
    return methods[key] or function() end
end}
function CreateFrame(_, name, parent)
    local frame = setmetatable({scripts = {}, parent = parent}, meta)
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
''')
