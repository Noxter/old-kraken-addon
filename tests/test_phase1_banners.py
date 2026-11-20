from pathlib import Path
import runpy

root = Path(__file__).resolve().parents[1]
lua = runpy.run_path(str(root / 'tests/test_ui_smoke.py'))['lua']
lua.execute(r'''
local finder=OldKraken.GroupFinder
OldKraken.DB={settings={smartNotifications=false,groupFinderNotifications=true,guildEventNotifications=true,workshopOrderAlerts=true}}
function finder:GroupAlertsEnabled() return OldKraken.DB.settings.groupFinderNotifications~=false end
function OldKraken.GuildEvents:AlertsEnabled() return OldKraken.DB.settings.guildEventNotifications~=false end
local function alert()
    for _,frame in ipairs(createdFrames) do if rawget(frame,'alertCaption') then return frame end end
end
local settings=OldKraken.DB.settings
settings.groupFinderNotifications=false; settings.guildEventNotifications=false; settings.workshopOrderAlerts=false
for _,kind in ipairs({'group','request','event','workshop'}) do
    finder:PreviewAlert(kind); assert(alert() and alert():IsShown() and alert().kind==kind)
end
settings.groupFinderNotifications=true; settings.guildEventNotifications=true; settings.workshopOrderAlerts=true
-- Changing an unrelated module must not dismiss a preview of a disabled one.
settings.groupFinderNotifications=false; finder:PreviewAlert('group'); assert(alert():IsShown())
settings.workshopOrderAlerts=false; OldKraken.listeners.WORKSHOP_ALERT_SETTING(); assert(alert():IsShown())
settings.groupFinderNotifications=true; settings.workshopOrderAlerts=true
settings.guildEventNotifications=false; finder:PreviewAlert('event'); assert(alert():IsShown())
settings.groupFinderNotifications=false; OldKraken.listeners.GROUP_FINDER_ALERT_SETTING(); assert(alert():IsShown())
settings.groupFinderNotifications=true; settings.guildEventNotifications=true
for _,item in ipairs({{'group','groupFinderNotifications'},{'request','groupFinderNotifications'},
                      {'event','guildEventNotifications'},{'workshop','workshopOrderAlerts'}}) do
    settings[item[2]]=false
    finder:PreviewAlert(item[1]); assert(alert() and alert():IsShown() and alert().kind==item[1])
    finder:SyncAlertVisibility(); assert(not alert():IsShown())
    settings[item[2]]=true
end
local own
local banner=alert()
for _,group in pairs(finder.groups) do if group.owner==finder.identity and not group.closed then own=group; break end end
assert(own)
finder.requests[own.id]={Applicant='dps'}
settings.groupFinderNotifications=false; banner:Hide()
OldKraken.listeners.GROUP_FINDER_NEW_REQUEST(own,'Applicant','dps')
assert(not banner:IsShown() and finder.requests[own.id].Applicant=='dps')
local foreign={owner='Remote Realm',id='remote',title='Remote',category='quest',members={'Remote Realm'},maxSize=5,description='',minLevel=1,maxLevel=60,role='dps'}
OldKraken.listeners.GROUP_FINDER_NEW(foreign); assert(not banner:IsShown())
settings.groupFinderNotifications=true
finder:PreviewAlert('group'); banner=alert(); banner.kind='decision'
settings.groupFinderNotifications=false; finder:SyncAlertVisibility(); assert(not banner:IsShown())
settings.groupFinderNotifications=true
finder:PreviewAlert('event'); banner.kind='event_signup'
settings.guildEventNotifications=false; finder:SyncAlertVisibility(); assert(not banner:IsShown())
settings.guildEventNotifications=true
settings.alertPositions={group={x=25,y=30}}
finder:PreviewAlert('group'); assert(finder:ResetAlertPositions()==true)
assert(type(settings.alertPositions)=='table' and next(settings.alertPositions)==nil and banner:IsShown())
for _,item in ipairs({{'WORKSHOP_ORDER_NOTICE','workshopOrderAlerts'},
                      {'GUILD_EVENTS_NEW','guildEventNotifications'},
                      {'GUILD_EVENTS_NEW_SIGNUP','guildEventNotifications'},
                      {'GUILD_EVENTS_CANCELLED','guildEventNotifications'},
                      {'GROUP_FINDER_APPLICATION_STATUS','groupFinderNotifications'}}) do
    settings[item[2]]=false; banner:Hide()
    if item[1]=='WORKSHOP_ORDER_NOTICE' then OldKraken.listeners[item[1]]('title','body','id')
    elseif item[1]=='GUILD_EVENTS_NEW_SIGNUP' then OldKraken.listeners[item[1]]('id',{owner='Owner',title='event',when=1},'Person','dps')
    elseif item[1]=='GROUP_FINDER_APPLICATION_STATUS' then OldKraken.listeners[item[1]]({owner='Owner Realm',id='g',title='x'},'reject')
    else OldKraken.listeners[item[1]]('id',{owner='Owner',title='event',when=1}) end
    assert(not banner:IsShown(),item[1]..' must not show when disabled')
    settings[item[2]]=true
end
''')
print('Phase 1 banner checks passed')
