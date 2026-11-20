from pathlib import Path
import runpy

root = Path(__file__).resolve().parents[1]
fixture = runpy.run_path(str(root / 'tests/test_ui_hub.py'))
lua = fixture['load_localized_addon']()
lua.execute(r'''
local finder=OldKraken.GroupFinder
local settings=OldKraken.DB.settings
OldKraken.UIHub:ShowPage('settings')
local page=OldKraken.UIHub.pages.settings.frame
local function button(prefix)
    for _,frame in ipairs(createdFrames) do
        if frame.parent==page and type(frame.text)=='string' and frame.text:find(prefix,1,true)==1 then return frame end
    end
    error('missing button '..prefix)
end
local group=button('Пошук груп: ')
local event=button('Події гільдії: ')
local workshop=button('Замовлення Майстерні: ')
local preview=button('Тест банера: ')
local reset=button('Скинути позиції банерів')
local orders=OldKraken.WorkshopOrders:CreatePanel(CreateFrame('Frame'))
orders:Show()
group.scripts.OnClick(); event.scripts.OnClick(); workshop.scripts.OnClick()
assert(settings.groupFinderNotifications==false and settings.guildEventNotifications==false and settings.workshopOrderAlerts==false)
assert(group.text:find('вимк.',1,true) and event.text:find('вимк.',1,true) and workshop.text:find('вимк.',1,true))
assert(orders.alerts.text== 'Нові: вимк.')
local seen={}; local originalPreview=finder.PreviewAlert
finder.PreviewAlert=function(_,kind) seen[#seen+1]=kind end
for i=1,4 do preview.scripts.OnClick() end
assert(table.concat(seen,',')=='group,request,event,workshop')
finder.PreviewAlert=originalPreview
settings.alertPositions={group={x=9,y=7},workshop={x=1,y=2}}
reset.scripts.OnClick(); assert(type(settings.alertPositions)=='table' and next(settings.alertPositions)==nil)
workshop.scripts.OnClick(); assert(settings.workshopOrderAlerts==true and workshop.text:find('увімк.',1,true))
assert(orders.alerts.text=='Нові: увімк.')
orders.alerts.scripts.OnClick()
assert(settings.workshopOrderAlerts==false and orders.alerts.text=='Нові: вимк.')
assert(workshop.text:find('вимк.',1,true))
group.scripts.OnClick(); event.scripts.OnClick()
assert(settings.groupFinderNotifications==true and settings.guildEventNotifications==true)
-- Missing module APIs and event bus still leave usable settings controls.
local savedFinder,savedEvents,savedFire=OldKraken.GroupFinder,OldKraken.GuildEvents,OldKraken.Fire
OldKraken.GroupFinder=nil; OldKraken.GuildEvents=nil; OldKraken.Fire=nil
settings.groupFinderNotifications=false; settings.guildEventNotifications=false; settings.workshopOrderAlerts=false
group.scripts.OnClick(); event.scripts.OnClick(); workshop.scripts.OnClick()
assert(settings.groupFinderNotifications and settings.guildEventNotifications and settings.workshopOrderAlerts)
assert(group.text:find('увімк.',1,true) and event.text:find('увімк.',1,true) and workshop.text:find('увімк.',1,true))
settings.alertPositions={group={x=8,y=9}}; reset.scripts.OnClick()
assert(type(settings.alertPositions)=='table' and next(settings.alertPositions)==nil)
local fired={}; OldKraken.Fire=function(_,name) fired[name]=(fired[name] or 0)+1 end
settings.groupFinderNotifications=false; settings.guildEventNotifications=false; settings.workshopOrderAlerts=false
group.scripts.OnClick(); event.scripts.OnClick(); workshop.scripts.OnClick()
assert(fired.GROUP_FINDER_ALERT_SETTING==1 and fired.GUILD_EVENTS_ALERT_SETTING==1 and fired.WORKSHOP_ALERT_SETTING==1)
OldKraken.GroupFinder,OldKraken.GuildEvents,OldKraken.Fire=savedFinder,savedEvents,savedFire
settings.smartNotifications=false; OldKraken:Fire('GROUP_FINDER_ALERT_SETTING')
assert(button('Розумні сповіщення: ').text:find('вимк.',1,true))
''')
print('Phase 1 notification settings checks passed')
