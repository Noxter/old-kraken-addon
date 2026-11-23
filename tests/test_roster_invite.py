from pathlib import Path
import sys
from lupa.lua51 import LuaRuntime
p=Path(__file__).resolve().parents[1]
lua=LuaRuntime(unpack_returned_tuples=True)
for f in p.glob('*.lua'):
    lua.execute('assert(loadstring(...))',f.read_text(encoding='utf-8'))
setup="\nOldKraken = {\n    DB = {settings = {roster = {search='', status='all', class='ALL', sort='name', ascending=true}}},\n    UIStyle = {\n        Colors = {brandGold={0.88,0.69,0.32,1}, mutedText={0.63,0.67,0.73}, divider={0.20,0.23,0.29,0.85}, zebra={1,1,1,0.035}, success={0.41,0.86,0.55,1}, warning={1,0.76,0.42,1}, info={0.40,0.70,1,1}, neutral={0.63,0.67,0.73,1}},\n        Window=function() end, Button=function() end, Dropdown=function() end, Panel=function() end, Input=function() end, Font=function() end,\n        Chip=function(parent, text) local c=CreateFrame('Button', nil, parent); c.label=c:CreateFontString(); c.SetLabel=function(self,v) self.label:SetText(v or '') end; c:SetLabel(text); return c end,\n        PillBadge=function(parent, text, kind) local p=CreateFrame('Frame', nil, parent); p.label=p:CreateFontString(); p.SetKind=function(self,k) self.kind=k end; p.SetLabel=function(self,v) self.label:SetText(v or '') end; p:SetKind(kind); p:SetLabel(text); return p end,\n    },\n}\nUISpecialFrames = {}\nSlashCmdList = {}\nUIParent = {}\nfunction UIDropDownMenu_SetText() end\nfunction UIDropDownMenu_SetWidth() end\nfunction UIDropDownMenu_JustifyText() end\nfunction UIDropDownMenu_Initialize() end\nfunction print() end\nfunction IsInGuild() return true end\nfunction GetNumGuildMembers() return 2 end\nfunction GetGuildRosterInfo(index)\n    if index == 1 then return 'Online Member', 'Member', 1, 60, 'Warrior', 'Dun Morogh', nil, nil, true, '', 'WARRIOR' end\n    return 'Offline Member', 'Member', 1, 60, 'Mage', 'Stormwind', nil, nil, false, '', 'MAGE'\nend\ninviteCalls = {}\nC_PartyInfo = {InviteUnit=function(name) inviteCalls[#inviteCalls + 1] = name; return true end}\n\nlocal methods = {}\nfunction methods:SetText(value) self.text = value end\nfunction methods:GetText() return self.text or '' end\nfunction methods:SetSize(width, height) self.width, self.height = width, height end\nfunction methods:SetEnabled(value) self.enabled = value end\nfunction methods:SetTextColor(...) self.textColor = {...} end\nfunction methods:SetJustifyH(value) self.justifyH = value end\nfunction methods:SetScript(name, callback) self.scripts[name] = callback end\nfunction methods:Show() self.shown = true end\nfunction methods:Hide() self.shown = false end\nfunction methods:SetShown(value) self.shown = value end\nfunction methods:IsShown() return self.shown == true end\nfunction methods:CreateFontString() return CreateFrame() end\nfunction methods:CreateTexture() return CreateFrame() end\nlocal meta = {__index=function(_, key)\n    if key == 'TitleText' or key == 'CloseButton' then return nil end\n    return methods[key] or function() end\nend}\ncreatedFrames = {}\nfunction CreateFrame(kind, name, parent, template)\n    local frame = setmetatable({scripts = {}, parent = parent, kind = kind, template = template}, meta)\n    if name then _G[name] = frame end\n    createdFrames[#createdFrames + 1] = frame\n    return frame\nend\n"
lua.execute(setup)
lua.execute("local probe=CreateFrame(); getmetatable(probe).__index(probe,'SetScript'); function probe:SetTexture(value) self.texture=value end; local meta=getmetatable(probe); local old=meta.__index; meta.__index=function(self,key) if key=='SetTexture' then return probe.SetTexture end; return old(self,key) end")
lua.execute('''
menuItems={}
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info) menuItems[#menuItems+1]=info end
function UIDropDownMenu_Initialize(frame, callback) frame.initialize=callback end
function ToggleDropDownMenu(_,_,menu) menuItems={}; menu.initialize(menu,1) end
function CloseDropDownMenus() end
function ChatFrame_SendTell(name) whispered=name end
function UnitName() return 'Online Member' end
OldKraken.Communication={RequestRosterPresence=function() end, HasRosterAddon=function(_,name) return name=='Online Member' end}
function OldKraken.Communication:GetLocalVersion() return '0.4.0' end
function OldKraken.Communication:GetRosterVersion(name) if name=='Online Member' then return '0.4.0-alpha.2' end end
function OldKraken.Communication:CompareVersions() return -1 end
function OldKraken:InvitePlayer(name) C_PartyInfo.InviteUnit(name) end
GameTooltip={SetOwner=function() end,SetText=function(_,text,...) assert(select('#',...)==0); tooltipText=text end,Show=function() end,Hide=function() end}
''')
lua.execute((p/'GuildRoster.lua').read_text(encoding='utf-8'))
lua.execute('''
OldKraken.GuildRoster:Load()
local rows={}
for _, frame in ipairs(createdFrames) do
    assert(frame.text~='Інвайт')
    if type(frame.member)=='table' and frame.professions then rows[frame.member.name]=frame end
end
local row=assert(rows['Online Member'])
assert(row.onlineDot.texture:find('StatusOnline.tga',1,true))
assert(rows['Offline Member'].onlineDot.texture:find('StatusOffline.tga',1,true))
for _,frame in ipairs(createdFrames) do assert(frame.text~='СТАТУС') end
row.scripts.OnClick(row,'RightButton')
assert(#menuItems==5 and menuItems[2].text=='Відкрити профіль' and not menuItems[3].disabled)
menuItems[3].func(); assert(inviteCalls[1]=='Online Member')
menuItems[4].func(); assert(whispered=='Online Member')
menuItems[5].func(); assert(OldKrakenCopyNameFrame.edit.text=='Online Member')
row.scripts.OnClick(row,'RightButton'); assert(#menuItems==5)
row.cellHovers[2].scripts.OnEnter(row.cellHovers[2]); assert(tooltipText=='Member')
local offline=assert(rows['Offline Member'])
offline.cellHovers[1].scripts.OnClick(); assert(menuItems[3].disabled and menuItems[4].disabled and not menuItems[5].disabled)
for _,frame in ipairs(createdFrames) do assert(frame.text~='Учасники' and frame.text~='Аддон') end
assert(row.cells[7].shown and row.cellHovers[7].shown)
assert(row.addonDot.texture:find('StatusOnline.tga',1,true) and offline.addonDot.texture:find('StatusOffline.tga',1,true))
assert(row.cells[7].text == '0.4.0-alpha.2' and row.cells[7].textColor[2]==0.55)
assert(row.versionBadge:IsShown() and row.versionBadge.kind == 'warning')
assert(offline.cells[7].text == '—' and offline.cells[7].textColor[1] == 0.63)
assert(not offline.versionBadge:IsShown())
assert(row.cellHovers[7].fullText:find('Застаріла',1,true))
assert(OldKrakenRosterFrame.totalChip.label.text == 'Учасників 2')
assert(OldKrakenRosterFrame.onlineChip.label.text:find('1', 1, true))
assert(OldKrakenRosterFrame.shownChip.label.text == 'Показано 2')
assert(OldKrakenRosterFrame.summaryText.text == 'Показано 2 з 2')
menuItems={}; OldKrakenRosterAddonFilter.initialize(nil,1)
menuItems[2].func(); assert(row:IsShown() and not offline:IsShown())
assert(OldKrakenRosterFrame.summaryText.text:find('фільтр «аддон: є» увімкнено', 1, true))
menuItems[3].func(); assert(row.member.name=='Offline Member' and row:IsShown())
row.scripts.OnClick(row,'RightButton'); assert(menuItems[1].text=='Offline Member')
OldKrakenRosterResetButton.scripts.OnClick()
assert(row:IsShown() and offline:IsShown() and OldKrakenRosterFrame.summaryText.text == 'Показано 2 з 2')
local origGetVersion = OldKraken.Communication.GetRosterVersion
local origCompare = OldKraken.Communication.CompareVersions
-- State 2: addon detected without version -> green dot and green '?' without badge border.
function OldKraken.Communication:GetRosterVersion() return nil end
OldKraken.GuildRoster:Render()
assert(row.addonDot.texture:find('StatusOnline.tga', 1, true))
assert(not row.versionBadge:IsShown() and row.cells[7].text == '—')
assert(row.cells[7].textColor[1] == 0.25 and row.cells[7].textColor[2] == 1 and row.cells[7].textColor[3] == 0.25)
-- State 3: version received with success / info / neutral comparisons.
function OldKraken.Communication:GetRosterVersion(name) if name == 'Online Member' then return '0.4.0' end end
function OldKraken.Communication:CompareVersions() return 0 end
OldKraken.GuildRoster:Render()
assert(row.versionBadge:IsShown() and row.versionBadge.kind == 'success' and row.cells[7].textColor[2] == 1)
function OldKraken.Communication:GetLocalVersion() return '0.4.0+g111111111111' end
function OldKraken.Communication:GetRosterVersion(name) if name == 'Online Member' then return '0.4.0+g222222222222' end end
OldKraken.GuildRoster:Render()
assert(row.versionBadge.kind == 'warning' and row.cellHovers[7].fullText:find('різні Git-збірки',1,true))
function OldKraken.Communication:GetRosterVersion(name) if name == 'Online Member' then return '0.4.0' end end
OldKraken.GuildRoster:Render()
assert(row.versionBadge.kind == 'neutral' and row.cellHovers[7].fullText:find('немає ідентифікатора',1,true))
function OldKraken.Communication:GetLocalVersion() return '0.4.0' end
function OldKraken.Communication:GetRosterVersion(name) if name == 'Online Member' then return '0.4.0' end end
function OldKraken.Communication:CompareVersions() return 1 end
OldKraken.GuildRoster:Render()
assert(row.versionBadge:IsShown() and row.versionBadge.kind == 'info' and row.cells[7].textColor[3] == 1)
function OldKraken.Communication:CompareVersions() return nil end
OldKraken.GuildRoster:Render()
assert(row.versionBadge:IsShown() and row.versionBadge.kind == 'neutral' and row.cells[7].textColor[1] == 0.7)
assert(row.cellHovers[7].fullText:find('Не вдалося порівняти', 1, true))
OldKraken.Communication.GetRosterVersion = origGetVersion
OldKraken.Communication.CompareVersions = origCompare
OldKraken.GuildRoster:Render()
''')
lua2=LuaRuntime(unpack_returned_tuples=True)
lua2.execute('''
OldKraken={Fire=function() end}; C_Timer={}; function GetServerTime() return 1700000000 end
function GetTime() return 100 end
function UnitName() return 'Me' end
function GetRealmName() return 'Realm' end
function IsInGuild() return true end
function GetGuildInfo() return 'Guild' end
function CreateFrame() return {RegisterEvent=function() end,SetScript=function() end} end
''')
lua2.execute((p/'Communication.lua').read_text(encoding='utf-8'))
lua2.execute('''
local c=OldKraken.Communication
OldKraken.version='0.4.0'
c.ready=true
assert(c:GetRosterVersion('Me')=='0.4.0')
assert(c:CompareVersions('0.4.0-alpha.2','0.4.0')==-1)
assert(c:CompareVersions('0.4.0-alpha.10','0.4.0')==-1)
assert(c:CompareVersions('0.4.1','0.4.0')==1)
assert(c:CompareVersions('0.4.0','0.4.0-rc.1')==1)
assert(c:CompareVersions('0.4.0-beta.1','0.4.0-alpha.10')==1)
assert(c:CompareVersions('0.4.0+build.2','0.4.0')==0)
assert(c:CompareVersions('0.5.4-alpha.1+g111111111111','0.5.4-alpha.1+g222222222222')==0)
assert(c:CompareVersions('unknown','0.4.0')==nil)
assert(c:HasRosterAddon('Me-Realm'))
assert(not c:HasRosterAddon('Other-Realm'))
c:RequestRosterPresence(); c:RequestRosterPresence(); assert(#c.queue==1)
c:OnAddonMessage(c.PREFIX,'OKP^QUERY','GUILD','Other-Realm')
assert(c:HasRosterAddon('Other') and #c.queue==2)
c:OnAddonMessage(c.PREFIX,'OKP^QUERY','GUILD','Other-Realm'); assert(#c.queue==2)
c:OnAddonMessage('wrong','OKP^HERE','GUILD','Wrong'); assert(not c:HasRosterAddon('Wrong'))
c:OnAddonMessage(c.PREFIX,'OKP^HERE','WHISPER','Wrong'); assert(not c:HasRosterAddon('Wrong'))
c:OnAddonMessage(c.PREFIX,'OKP^HERE^0.4.0-alpha.2','GUILD','Other-Realm')
assert(c:GetRosterVersion('Other')=='0.4.0-alpha.2')
c:OnAddonMessage(c.PREFIX,'OKP^HERE^0.5.4-alpha.1+g0123456789ab','GUILD','Other-Realm')
assert(c:GetRosterVersion('Other')=='0.5.4-alpha.1+g0123456789ab')
c:OnAddonMessage(c.PREFIX,'OKP^HERE^0.4.0-alpha.2','GUILD','Other-Realm')
c:OnAddonMessage(c.PREFIX,'OKP^HERE','GUILD','Other-Realm')
assert(c:GetRosterVersion('Other')=='0.4.0-alpha.2')
c:OnAddonMessage(c.PREFIX,'OKP^HERE^bad|color','GUILD','Other-Realm')
assert(c:GetRosterVersion('Other')=='0.4.0-alpha.2')
function GetAddOnMetadata() return '0.4.1' end
assert(c:GetLocalVersion()=='0.4.1')
function GetGuildInfo() return 'New Guild' end
assert(c:GetRosterVersion('Other')==nil)
''')
print('PASS: Lua 5.1 syntax, both clicks, actions, offline restrictions, row reuse, tooltip signature, addon filters, presence exchange and throttling')
