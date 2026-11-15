from pathlib import Path
import ast
from lupa.lua51 import LuaRuntime

root=Path(__file__).resolve().parents[1]
tree=ast.parse((root/'tests/test_events_ui.py').read_text(encoding='utf-8'))
setup=next(ast.literal_eval(n.value.args[0]) for n in tree.body if isinstance(n,ast.Expr) and isinstance(n.value,ast.Call) and isinstance(n.value.func,ast.Attribute) and n.value.func.attr=='execute')
lua=LuaRuntime(unpack_returned_tuples=True)
setup=setup.replace('function UIDropDownMenu_Initialize() end','function UIDropDownMenu_Initialize(frame,fn) frame.initialize=fn end')
lua.execute(setup)
lua.execute('''
OldKraken.name='OldKraken'
local originalFrame=CreateFrame
function CreateFrame(...)
    local frame=originalFrame(...)
    function frame:GetStringHeight() return 14 end
    return frame
end
options={}
function UIDropDownMenu_AddButton(info) options[#options+1]=info end
function selectOption(frame,value)
    options={}; frame.initialize(frame,1)
    for _,info in ipairs(options) do if info.value==value then info.func(); return end end
    error('missing option')
end
size=0; inRaid=false; combat=false; lead=true; invites={}; conversions=0
function GetNumGroupMembers() return size end
function IsInRaid() return inRaid end
function InCombatLockdown() return combat end
function UnitIsGroupLeader() return lead end
function UnitIsGroupAssistant() return false end
function UnitInRaid(name) return name=='Already grouped' end
function UnitInParty() return false end
C_PartyInfo={InviteUnit=function(name) invites[#invites+1]=name; return true end,
ConvertToRaid=function() conversions=conversions+1; inRaid=true; return true end}
''')
for name in ['ActivityCatalog.lua','GuildEvents.lua']:
    lua.execute((root/name).read_text(encoding='utf-8'))
lua.execute('''
for _,frame in ipairs(createdFrames) do if frame.scripts.OnEvent then frame.scripts.OnEvent(frame,'PLAYER_LOGIN') end end
OldKraken.UIHub:ShowPage('events')
local events=OldKraken.GuildEvents
local ui=OldKrakenEventsFrame
ui.title:SetText('Old title')
ui:SetCreationMode(true); for _,card in ipairs(ui.activityCards.cards) do if type(card.entry)=='table' and card.entry.value=='onyxia' then card.scripts.OnClick(card) end end
assert(ui.title:GetText()=='Лігво Оніксії (Ony)')
selectOption(ui.kindMenu,'dungeon')
ui:SetCreationMode(true)
assert(ui.activityCards:IsShown() and #ui.activityCards.cards==#OldKraken.ActivityCatalog.dungeon-1)
ui.activityCards.scripts.OnMouseWheel(ui.activityCards,-1)
assert(ui.activityCards.offset==70)
for _,card in ipairs(ui.activityCards.cards) do if type(card.entry)=='table' and card.entry.value=='wc' then card.scripts.OnClick(card) end end
assert(ui.title:GetText()=='Печери Стогонів (WC)' and ui.activityCards:IsShown())
local allocated=#createdFrames
selectOption(ui.kindMenu,'raid')
ui:SetCreationMode(true)
local shown=0
for _,card in ipairs(ui.activityCards.cards) do if card:IsShown() and card.entry then shown=shown+1 end end
assert(shown==#OldKraken.ActivityCatalog.raid-1 and #createdFrames==allocated)
for _,card in ipairs(ui.activityCards.cards) do if type(card.entry)=='table' and card.entry.value=='onyxia' then card.scripts.OnClick(card) end end
assert(events:Create(ui.title:GetText(),'',GetServerTime()+3600,'raid',40,'onyxia'))
local store=OldKraken.DB.events.guildCalendarV1['Test Realm\\001Guild\\001Tester Realm']
local key,e=next(store.owned); assert(e)
for i=1,6 do local name='Accepted '..i; e.people[name]='dps'; e.statuses[name]='accepted' end
e.people['Reserve']='dps'; e.statuses.Reserve='reserve'
e.people['Waiting']='dps'; e.statuses.Waiting='pending'
e.people['Already grouped']='tank'; e.statuses['Already grouped']='accepted'
events:ShowEvent(key)
assert(ui.inviteAll:IsShown())
assert(not ui.activityCards:IsShown() and OldKrakenEventsDetailsScroll:IsShown())
assert(ui.roleColumns[1].text:find('Already grouped',1,true))
assert(ui.roleColumns[3].text:find('Accepted 1',1,true))
assert(not ui.roleColumns[3].text:find('Reserve',1,true))
assert(not ui.roleColumns[3].text:find('Waiting',1,true))
for _,row in ipairs(ui.signupRows) do
    assert(row.height==32 and row.accept.width==24 and row.accept.text=='')
end
assert(events:InviteAll(key))
for i=1,10 do events:PumpRaidInvites() end
assert(#invites==4 and conversions==0,'solo must not exceed four initial invitations')
size=2; events:PumpRaidInvites(); assert(conversions==1)
for i=1,10 do events:PumpRaidInvites() end
assert(#invites==6,'remaining accepted participants must be invited after raid conversion')
local seen={}; for _,name in ipairs(invites) do assert(not seen[name]); seen[name]=true end
assert(not seen.Reserve and not seen.Waiting and not seen['Already grouped'])
assert(not events:InviteMember(key,'Reserve'))
combat=true
assert(events:InviteMember(key,'Accepted 1')); assert(#invites==6)
combat=false; events:PumpRaidInvites(); assert(#invites==7)
for i=1,5 do events:PumpRaidInvites() end
lead=false; assert(not events:InviteAll(key))
lead=true
local owner=e.owner; e.owner='Somebody else'
assert(not events:InviteAll(key)); e.owner=owner
e.cancelled=true; assert(not events:InviteAll(key))
''')
print('PASS: raid selection auto-title, owner controls, accepted-only individual/batch invitations, existing-member skips, solo party limits, raid conversion, combat and permission guards')
