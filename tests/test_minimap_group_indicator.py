from pathlib import Path

from lupa.lua51 import LuaRuntime


root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
OldKraken={listeners={}, UIStyle={Colors={window={0,0,0,1}, brandGold={1,1,0,1}},
    EmblemPath=function() return 'emblem' end}}
function OldKraken:On(name,fn)
    self.listeners[name]=self.listeners[name] or {}; table.insert(self.listeners[name],fn)
end
function OldKraken:Fire(name,...) for _,fn in ipairs(self.listeners[name] or {}) do fn(...) end end
function GetTime() return now end
function GetServerTime() return 100000 end
now=0; level=20; tank=false; healer=false; dps=false
function UnitLevel() return level end
function UnitGetAvailableRoles() return tank,healer,dps end
function UnitName() return 'Me' end
function InCombatLockdown() return true end
Minimap={GetFrameLevel=function() return 1 end,GetWidth=function() return 100 end,GetHeight=function() return 100 end}
GameTooltip={lines={}}
function GameTooltip:SetOwner() self.lines={} end
function GameTooltip:SetText(text) self.title=text end
function GameTooltip:AddLine(text) self.lines[#self.lines+1]=text end
function GameTooltip:Show() end
function GameTooltip:Hide() end
local methods={}
function methods:SetScript(k,v) self.scripts[k]=v end
function methods:RegisterEvent(k) self.events[k]=true end
function methods:CreateTexture() return CreateFrame() end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false end
function methods:SetTexture(t) self.texture=t end
local meta={__index=function(_,k) return methods[k] or function() end end}
frames={}
function CreateFrame(_,name)
    local f=setmetatable({scripts={},events={}},meta)
    if name then _G[name]=f end
    frames[#frames+1]=f
    return f
end
C_Timer={NewTicker=function(seconds,fn) assert(seconds==10); indicatorTick=fn end}
''')
for name in ('GroupFinder.lua', 'Minimap.lua'):
    lua.execute((root / name).read_text(encoding='utf-8'))

lua.execute('''
local f=OldKraken.GroupFinder
f:Initialize('Me',function() return true end)
f.active=true
OldKraken:Fire('INITIALIZED',{settings={minimapAngle=225,groupFinderNotifications=false}})
local button=OldKrakenMinimapButton
local indicator=button.groupIndicator
assert(not indicator.shown and indicator.texture:find('StatusOnline.tga',1,true))
assert(type(indicatorTick)=='function')
local dungeon={owner='Other',id='1',category='dungeon',maxSize=5,minLevel=20,maxLevel=30,
    role='tank',members={'Other'},memberRoles={},seenAt=now}
f.groups.one=dungeon
tank=true; OldKraken:Fire('GROUP_FINDER_CHANGED')
assert(not indicator.shown, 'a tank cannot fill a second tank slot')
healer=true; OldKraken:Fire('GROUP_FINDER_CHANGED')
assert(indicator.shown, 'a matching free healer slot is indicated even in combat with alerts disabled')
button.scripts.OnEnter(button)
assert(GameTooltip.lines[1]:find('1',1,true))

level=30; indicatorTick(); assert(indicator.shown, 'upper level bound is inclusive')
level=31; indicatorTick(); assert(not indicator.shown)
level=19; indicatorTick(); assert(not indicator.shown)
level=20; indicatorTick(); assert(indicator.shown, 'lower level bound is inclusive')
dungeon.members={'Other','Heal','Dps1','Dps2','Dps3'}
dungeon.memberRoles={Heal='healer',Dps1='dps',Dps2='dps',Dps3='dps'}
OldKraken:Fire('GROUP_FINDER_CHANGED'); assert(not indicator.shown, 'full groups are excluded')
dungeon.members={'Other','Me'}; dungeon.memberRoles={Me='healer'}
OldKraken:Fire('GROUP_FINDER_CHANGED'); assert(not indicator.shown, 'already joined groups are excluded')
dungeon.members={'Other'}; dungeon.memberRoles={}; dungeon.closed=true
OldKraken:Fire('GROUP_FINDER_CHANGED'); assert(not indicator.shown)
dungeon.closed=false; dungeon.hidden=true
OldKraken:Fire('GROUP_FINDER_CHANGED'); assert(not indicator.shown)
dungeon.hidden=false; dungeon.owner='Me'; dungeon.members={'Me'}
OldKraken:Fire('GROUP_FINDER_CHANGED'); assert(not indicator.shown, 'own groups are excluded')

local quest={owner='Another',id='2',category='quest',maxSize=5,minLevel=1,maxLevel=60,
    role='dps',members={'Another'},memberRoles={},seenAt=now}
f.groups.two=quest
OldKraken:Fire('GROUP_FINDER_CHANGED'); assert(indicator.shown, 'non-dungeon vacancy accepts an available role')
tank=false; healer=false; dps=false
indicatorTick(); assert(not indicator.shown, 'no available roles means no match')
dps=true; indicatorTick(); assert(indicator.shown)
f.active=false; indicatorTick(); assert(not indicator.shown, 'inactive finder has no indicator')
f.active=true; indicatorTick(); assert(indicator.shown)
now=3601; f:Prune(); indicatorTick(); assert(not indicator.shown, 'expired listings stop matching')

quest.seenAt=now; f.groups.two=quest; OldKraken:Fire('GROUP_FINDER_CHANGED'); assert(indicator.shown)
level=61
for _,frame in ipairs(frames) do if frame.events.PLAYER_LEVEL_UP then frame.scripts.OnEvent(frame,'PLAYER_LEVEL_UP') end end
assert(not indicator.shown, 'level change updates the indicator immediately')
button.scripts.OnEnter(button)
for _,line in ipairs(GameTooltip.lines) do assert(not line:find('Підходящих груп',1,true)) end
''')


def test_offline_owner_hides_minimap_indicator():
    ui_lua = LuaRuntime(unpack_returned_tuples=True)
    ui_lua.execute('''
        OldKraken = {
            name = 'OldKraken',
            _listeners = {},
            UIStyle = {
                Colors = {
                    window = {0, 0, 0, 1}, brandGold = {1, 1, 0, 1}, text = {1, 1, 1, 1},
                    mutedText = {0.6, 0.6, 0.6}, success = {0, 1, 0, 1}, neutral = {0.6, 0.6, 0.6, 1},
                    danger = {1, 0, 0, 1}, sel = {0.2, 0.3, 0.6, 0.5}, selEdge = {0.5, 0.6, 1, 1},
                    buttonEdge = {0.2, 0.2, 0.3, 0.8},
                },
                Window = function() end, Button = function() end, Dropdown = function() end,
                Input = function() end, Panel = function() end, Font = function() end,
                EmblemPath = function() return 'emblem' end,
                PanelFrame = function(p) return CreateFrame('Frame', nil, p) end,
                ApplySelection = function() end,
            },
        }
        function OldKraken:On(name, fn)
            self._listeners[name] = self._listeners[name] or {}
            table.insert(self._listeners[name], fn)
        end
        eventsFired = {}
        function OldKraken:Fire(name, ...)
            eventsFired[name] = (eventsFired[name] or 0) + 1
            for _, fn in ipairs(self._listeners[name] or {}) do fn(...) end
        end
        now = 100
        ownerOnline = true
        function GetTime() return now end
        function GetServerTime() return 1700000000 end
        function UnitLevel() return 25 end
        function UnitGetAvailableRoles() return false, true, false end
        function UnitName() return 'Me', 'Realm' end
        function GetRealmName() return 'Realm' end
        function GetGuildInfo() return 'Guild' end
        function IsInGuild() return true end
        function IsInInstance() return false, 'none' end
        function InCombatLockdown() return false end
        function PlaySound() end
        function GetNumGuildMembers() return 1 end
        function GetGuildRosterInfo() return 'Other-Realm', 'Member', 1, 25, 'Warrior', 'City', '', '', ownerOnline, '', 'WARRIOR' end
        function UIDropDownMenu_SetWidth() end
        function UIDropDownMenu_JustifyText() end
        function UIDropDownMenu_Initialize() end
        function UIDropDownMenu_SetText() end
        function UIDropDownMenu_CreateInfo() return {} end
        function print() end
        StaticPopupDialogs = {}
        UISpecialFrames = {}
        UIParent = {}
        scheduledTimers = {}
        C_Timer = {
            After = function(delay, fn)
                table.insert(scheduledTimers, {runAt = now + (tonumber(delay) or 0), fn = fn})
            end,
            NewTicker = function(_, fn) indicatorTick = fn end,
        }
        Minimap = {GetFrameLevel = function() return 1 end, GetWidth = function() return 100 end, GetHeight = function() return 100 end}
        GameTooltip = {lines = {}, SetOwner = function(self) self.lines = {} end, SetText = function(self, t) self.title = t end, AddLine = function(self, t) self.lines[#self.lines + 1] = t end, Show = function() end, Hide = function() end}
        local methods = {}
        function methods:SetScript(k, v) self.scripts[k] = v end
        function methods:HookScript(k, v) local o = self.scripts[k]; self.scripts[k] = function(...) if o then o(...) end; v(...) end end
        function methods:RegisterEvent(k) self.events[k] = true end
        function methods:CreateTexture() return CreateFrame() end
        function methods:CreateFontString() return CreateFrame() end
        function methods:Show() self.shown = true end
        function methods:Hide() self.shown = false end
        function methods:SetShown(v) self.shown = v and true or false end
        function methods:IsShown() return self.shown == true end
        function methods:SetTexture(t) self.texture = t end
        function methods:GetHeight() return 400 end
        function methods:GetVerticalScroll() return 0 end
        local meta = {__index = function(_, k) return methods[k] or function() end end}
        frames = {}
        function CreateFrame(_, name)
            local f = setmetatable({scripts = {}, events = {}}, meta)
            if name then _G[name] = f end
            frames[#frames + 1] = f
            return f
        end
    ''')
    for name in ('Locale.lua', 'ActivityCatalog.lua', 'GroupFinder.lua', 'GroupFinderUI.lua', 'Minimap.lua'):
        ui_lua.execute((root / name).read_text(encoding='utf-8'))
    ui_lua.execute('''
        local db = {settings = {minimapAngle = 225, groupFinderNotifications = false}}
        OldKraken.InitializeLocale(db)
        OldKraken.DB = db
        local f = OldKraken.GroupFinder
        f:Initialize('Me Realm', function() return true end)
        f.active = true
        OldKraken:Fire('INITIALIZED', db)

        local indicator = OldKrakenMinimapButton.groupIndicator
        f.groups['Other Realm\0011'] = {
            owner = 'Other Realm', id = '1', category = 'dungeon', maxSize = 5,
            minLevel = 20, maxLevel = 30, role = 'tank', members = {'Other Realm'}, memberRoles = {}, seenAt = now,
        }
        local function flushAfter()
            local pending = {}
            local toRun = {}
            for _, item in ipairs(scheduledTimers) do
                if now >= item.runAt then
                    table.insert(toRun, item.fn)
                else
                    table.insert(pending, item)
                end
            end
            scheduledTimers = pending
            for _, fn in ipairs(toRun) do fn() end
        end
        local function fireRosterUpdate()
            for _, fr in ipairs(frames) do
                if fr.events and fr.events.GUILD_ROSTER_UPDATE and fr.scripts.OnEvent then
                    fr.scripts.OnEvent(fr, 'GUILD_ROSTER_UPDATE')
                end
            end
        end
        OldKraken:Fire('GROUP_FINDER_CHANGED', f.groups['Other Realm\0011'])
        fireRosterUpdate()
        flushAfter()
        assert(indicator.shown, 'online owner group should trigger indicator')

        -- Owner goes offline: still shown before 300s grace expires.
        ownerOnline = false
        now = 200
        fireRosterUpdate()
        flushAfter()
        assert(indicator.shown, 'indicator stays visible during 300s offline grace')

        now = 499
        indicatorTick()
        assert(indicator.shown, 'indicator stays visible at 299s offline')
        assert(not eventsFired['GROUP_FINDER_OFFLINE_CHANGED'], 'offline event must not fire before 300s TTL expires')

        -- At 300s offline, GroupFinderUI timer callback runs, hides the group, and indicator turns off.
        now = 500
        flushAfter()
        assert(not indicator.shown, 'indicator must hide when offline owner exceeds 300s')
        assert(eventsFired['GROUP_FINDER_OFFLINE_CHANGED'] == 1, 'timer TTL callback must fire GROUP_FINDER_OFFLINE_CHANGED exactly once on expiration')

        -- Owner comes back online and roster updates -> indicator reappears.
        ownerOnline = true
        now = 505
        fireRosterUpdate()
        flushAfter()
        assert(indicator.shown, 'indicator reappears when owner returns online')

        -- Unknown owner status (not in guild roster): group is kept and indicator remains shown.
        ownerOnline = false
        now = 600
        fireRosterUpdate()
        flushAfter()
        now = 1000
        flushAfter()
        assert(not indicator.shown, 'known offline owner group is hidden after 300s')
        assert(f:IsGroupHiddenByOfflineOwner('Other Realm\0011', f.groups['Other Realm\0011']) == true)

        f.groups['Foreign Realm\0012'] = {
            owner = 'Foreign Realm', id = '2', category = 'dungeon', maxSize = 5,
            minLevel = 20, maxLevel = 30, role = 'tank', members = {'Foreign Realm'}, memberRoles = {}, seenAt = now,
        }
        fireRosterUpdate()
        flushAfter()
        assert(not f:IsGroupHiddenByOfflineOwner('Foreign Realm\0012', f.groups['Foreign Realm\0012']), 'unknown owner must not be hidden')
        assert(indicator.shown, 'group with unknown owner status keeps minimap indicator visible')

        -- Missing or corrupt author data: safely treated as not hidden.
        assert(not f:IsGroupHiddenByOfflineOwner('bad', {owner = nil, closed = false}))
        assert(not f:IsGroupHiddenByOfflineOwner('bad', {owner = '', closed = false}))
        assert(not f:IsGroupHiddenByOfflineOwner('bad', nil))

        -- Event-driven update: GROUP_FINDER_OFFLINE_CHANGED immediately updates indicator.
        f.groups['Foreign Realm\0012'] = nil
        OldKraken:Fire('GROUP_FINDER_OFFLINE_CHANGED')
        assert(not indicator.shown, 'GROUP_FINDER_OFFLINE_CHANGED updates indicator without UI reload')
    ''')


test_offline_owner_hides_minimap_indicator()
print('Minimap group indicator checks passed')
