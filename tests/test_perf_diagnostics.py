import runpy
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
LOCALE = (ROOT / 'Locale.lua').read_text(encoding='utf-8')
CORE = (ROOT / 'Core.lua').read_text(encoding='utf-8')
COMM = (ROOT / 'Communication.lua').read_text(encoding='utf-8')
DB = (ROOT / 'Database.lua').read_text(encoding='utf-8')
GF = (ROOT / 'GroupFinder.lua').read_text(encoding='utf-8')
WORKSHOP = (ROOT / 'Workshop.lua').read_text(encoding='utf-8')
RECIPES = (ROOT / 'WorkshopRecipes.lua').read_text(encoding='utf-8')
SYNC = (ROOT / 'WorkshopSync.lua').read_text(encoding='utf-8')


def test_core_perf_commands_and_metrics():
    for lang in ('ukUA', 'enUS'):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals()._lang = lang
        lua.execute(
            '''
            printed = {}
            function print(...)
                local parts = {}
                for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
                printed[#printed + 1] = table.concat(parts, ' ')
            end
            function CreateFrame()
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            Enum = {
                AddOnProfilerMetric = {
                    RecentAverageTime = 1,
                    SessionAverageTime = 2,
                    PeakTime = 3,
                    CountTimeOver5Ms = 4,
                    CountTimeOver10Ms = 5,
                    CountTimeOver50Ms = 6,
                }
            }
            C_AddOnProfiler = {
                GetAddOnMetric = function(name, metric)
                    local vals = { [1]=1.25, [2]=2.5, [3]=15.0, [4]=10, [5]=3, [6]=1 }
                    return vals[metric]
                end
            }
            OldKraken = {}
            '''
        )
        lua.execute(LOCALE)
        lua.execute('OldKraken.InitializeLocale({ settings = { language = _lang } })')
        lua.execute(CORE)
        lua.execute(
            '''
            assert(OldKraken.perfEnabled == false)
            assert(OldKraken:HandlePerfCommand('other') == false)
            assert(OldKraken:HandlePerfCommand('PERF') == true)
            assert(OldKraken:HandlePerfCommand('  PERF ON  ') == true)
            assert(OldKraken.perfEnabled == true)
            OldKraken:PerfRecord('comm.pump', 12.5)
            OldKraken:PerfRecord('comm.pump', 2.5)
            OldKraken:PerfRecord('wk.sync', 60.0)
            OldKraken:PerfRecord('roster.filter', 1.5, 500)
            assert(OldKraken:HandlePerfCommand('perf') == true)
            local out = table.concat(printed, '\\n')
            assert(out:find('C_AddOnProfiler: recent=1.25ms, session=2.50ms, peak=15.00ms, >5ms=10, >10ms=3, >50ms=1', 1, true))
            assert(out:find('wk.sync: calls=1, total=60.00ms, avg=60.00ms, max=60.00ms (>5:1 >10:1 >50:1)', 1, true))
            assert(out:find('comm.pump: calls=2, total=15.00ms, avg=7.50ms, max=12.50ms (>5:1 >10:1 >50:0)', 1, true))
            assert(out:find('roster.filter: calls=1, total=1.50ms, avg=1.50ms, max=1.50ms (>5:0 >10:0 >50:0), items=500 (avg=500.0)', 1, true))
            assert(OldKraken:HandlePerfCommand('perf reset') == true)
            assert(next(OldKraken.perfStats) == nil)
            assert(OldKraken:HandlePerfCommand('perf off') == true)
            assert(OldKraken.perfEnabled == false)
            '''
        )


def test_comm_hex_codec_and_cache_counters():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(
        '''
        now = 1000
        serverNow = 1700000000
        function GetTime() return now end
        function GetServerTime() return serverNow end
        function AdvanceTime(dt) now = now + dt end
        function IsInGuild() return true end
        function GetGuildInfo() return 'Kraken' end
        function UnitName() return 'Alice' end
        function CreateFrame()
            local f = { scripts = {} }
            function f:RegisterEvent() end
            function f:SetScript(name, fn) self.scripts[name] = fn end
            return f
        end
        sentMessages = {}
        C_ChatInfo = {
            RegisterAddonMessagePrefix = function() return true end,
            SendAddonMessage = function(prefix, msg, chan)
                sentMessages[#sentMessages + 1] = {prefix, msg, chan}
                return 0
            end
        }
        OldKraken = { Print = function() end }
        '''
    )
    lua.execute(COMM)
    lua.execute(
        '''
        local Comm = OldKraken.Communication
        Comm.ready = true
        local received = {}
        assert(Comm:RegisterHandler('QUERY', function(sender, id, payload)
            received[#received + 1] = {sender = sender, id = id, payload = payload}
        end))

        -- Round-trip ASCII, UTF-8, and delimiters via SendProtocol -> Pump -> OnAddonMessage
        local sample = 'Привіт^123|cffa335ee|Hitem:19019|h[Test]|h|r\\001ҐґЄєІіЇї'
        assert(Comm:SendProtocol('QUERY', sample))
        while #Comm.queue > 0 do Comm:Pump() end
        assert(#sentMessages >= 1)
        for _, m in ipairs(sentMessages) do
            Comm:OnAddonMessage(m[1], m[2], m[3], 'Bob')
        end
        assert(#received == 1 and received[1].payload == sample, 'UTF-8/delimiter hex round-trip mismatch')

        -- Assembly cap at 1024 and TTL prune recovery
        for i = 1, 1024 do
            local p = 'GF2^QUERY^1-' .. i .. '-1^1^2^' .. string.rep('41', 80)
            Comm:OnAddonMessage('OLDKRKN', p, 'GUILD', 'Sender' .. i)
        end
        local beforeInvalid = Comm.stats.invalid
        Comm:OnAddonMessage('OLDKRKN', 'GF2^QUERY^1-1025-1^1^2^' .. string.rep('41', 80), 'GUILD', 'Overflow')
        assert(Comm.stats.invalid == beforeInvalid + 1)

        -- Advance past CACHE_TTL (120s) so Prune clears old assemblies and allows new ones
        AdvanceTime(130)
        Comm:OnAddonMessage('OLDKRKN', 'GF2^QUERY^1-1026-1^1^2^' .. string.rep('41', 80), 'GUILD', 'AfterPrune')
        assert(Comm.stats.invalid == beforeInvalid + 1)
        '''
    )


def test_export_snapshot_meta_matches_export_snapshot():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(
        '''
        now = 1000
        serverNow = 1700000000
        function GetTime() return now end
        function GetServerTime() return serverNow end
        function IsInGuild() return true end
        function GetGuildInfo() return 'Kraken' end
        function GetRealmName() return 'Forever' end
        function UnitName() return 'Alice' end
        eventFrames = {}
        function CreateFrame()
            local f = { scripts = {}, shown = false }
            function f:RegisterEvent() end
            function f:SetScript(name, fn)
                self.scripts[name] = fn
                if name == 'OnEvent' then eventFrames[#eventFrames + 1] = self end
            end
            function f:HookScript() end
            function f:Show() self.shown = true end
            function f:Hide() self.shown = false end
            function f:IsShown() return self.shown end
            function f:SetSize() end
            function f:SetPoint() end
            function f:SetMovable() end
            function f:EnableMouse() end
            function f:RegisterForDrag() end
            function f:CreateFontString() return CreateFrame() end
            function f:CreateTexture() return CreateFrame() end
            function f:SetText() end
            function f:SetJustifyH() end
            function f:SetTextColor() end
            function f:SetFont() end
            function f:SetShadowColor() end
            function f:SetShadowOffset() end
            function f:SetSpacing() end
            function f:SetAlpha() end
            function f:SetColorTexture() end
            function f:SetTexture() end
            function f:SetTexCoord() end
            return f
        end
        C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end }
        UISpecialFrames = {}
        OldKrakenDB = {}
        OldKraken = {
            version = '0.5.7-alpha.1',
            _listeners = {},
            On = function(self, name, fn) self._listeners[name] = self._listeners[name] or {}; table.insert(self._listeners[name], fn) end,
            Fire = function(self, name, ...) for _, fn in ipairs(self._listeners[name] or {}) do fn(...) end end,
            Print = function() end,
            PrintError = function() end,
            UIStyle = { Colors = { brandGold = {1,1,1}, mutedText = {1,1,1} }, Window = function() end, Button = function() end, Input = function() end, Panel = function() end, Dropdown = function() end },
        }
        '''
    )
    lua.execute(DB)
    lua.execute('OldKraken.Database.Initialize()')
    lua.execute(COMM)
    lua.execute(GF)
    lua.execute(WORKSHOP)
    lua.execute(RECIPES)
    lua.execute(
        '''
        OldKraken.DB.workshop = OldKraken.DB.workshop or {}
        OldKraken.DB.workshop.guilds = OldKraken.DB.workshop.guilds or {}
        local scope = OldKraken.DB.workshop.guilds['Forever\\001Kraken']
        if not scope then
            OldKraken.DB.workshop.guilds['Forever\\001Kraken'] = {}
            scope = OldKraken.DB.workshop.guilds['Forever\\001Kraken']
        end
        scope.recipes = scope.recipes or {}
        scope.recipes['Alice'] = {
            [101] = {recipe=101, item=201, profession=164, seen=serverNow, name='R1', product='P1'},
            [102] = {recipe=102, item=0, profession=333, seen=serverNow, name='R2', product=''},
        }
        scope.recipeTombstones = scope.recipeTombstones or {}
        scope.recipeTombstones['Alice'] = {
            [103] = {recipe=103, item=203, profession=164, seen=serverNow, name='R3', product='P3'},
        }
        scope.recipeVersions = scope.recipeVersions or {}
        scope.recipeVersions['Alice'] = 42
        for _, f in ipairs(eventFrames) do
            if type(f.scripts.OnEvent) == 'function' then f.scripts.OnEvent(f, 'PLAYER_LOGIN') end
        end
        local rev1, list = OldKraken.WorkshopRecipes:ExportSnapshot()
        local rev2, total = OldKraken.WorkshopRecipes:ExportSnapshotMeta()
        assert(rev1 == 42 and type(list) == 'table' and #list == 3, 'ExportSnapshot failed')
        assert(rev2 == rev1 and total == #list, 'ExportSnapshotMeta mismatch')
        '''
    )


def test_part1_filters_skip_non_target_multipart():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(
        '''
        now = 1000
        serverNow = 1700000000
        function GetTime() return now end
        function GetServerTime() return serverNow end
        function IsInGuild() return true end
        function GetGuildInfo() return 'Kraken' end
        function UnitName() return 'Bob' end
        function CreateFrame()
            local f = { scripts = {} }
            function f:RegisterEvent() end
            function f:SetScript(name, fn) self.scripts[name] = fn end
            return f
        end
        sentMessages = {}
        C_ChatInfo = {
            RegisterAddonMessagePrefix = function() return true end,
            SendAddonMessage = function(prefix, msg, chan)
                sentMessages[#sentMessages + 1] = {prefix, msg, chan}
                return 0
            end
        }
        OldKraken = { Print = function() end }
        '''
    )
    lua.execute(COMM)
    lua.execute(GF)
    lua.execute(
        '''
        local Comm = OldKraken.Communication
        Comm.ready = true
        local wrpageCalls = 0
        assert(Comm:RegisterHandler('WRPAGE', function() wrpageCalls = wrpageCalls + 1 end))
        Comm.part1Filters.WRPAGE = function(part1)
            local first, last, sz = part1:find('(%d+):', 1)
            if first ~= 1 or not sz then return true end
            sz = tonumber(sz)
            return part1:sub(last + 1, last + sz) == 'Bob'
        end

        -- 2-part payload targeted at 'Alice' (not 'Bob')
        local alicePayload = OldKraken.GroupFinder._pack({'Alice', 'Crafter', '7', '1', '1', string.rep('x', 80)})
        assert(#alicePayload > 80)
        assert(Comm:SendProtocol('WRPAGE', alicePayload))
        while #Comm.queue > 0 do Comm:Pump() end
        assert(#sentMessages >= 2)
        for _, m in ipairs(sentMessages) do
            Comm:OnAddonMessage(m[1], m[2], m[3], 'Alice')
        end
        assert(wrpageCalls == 0, 'non-target WRPAGE must be skipped by part1Filters')
        assert(Comm.stats.received == 0, 'non-target WRPAGE must not increment received')

        -- 2-part payload targeted at 'Bob' succeeds
        sentMessages = {}
        local bobPayload = OldKraken.GroupFinder._pack({'Bob', 'Crafter', '7', '1', '1', string.rep('y', 80)})
        assert(Comm:SendProtocol('WRPAGE', bobPayload))
        while #Comm.queue > 0 do Comm:Pump() end
        assert(#sentMessages >= 2)
        for _, m in ipairs(sentMessages) do
            Comm:OnAddonMessage(m[1], m[2], m[3], 'Alice')
        end
        assert(wrpageCalls == 1 and Comm.stats.received == 1, 'target WRPAGE must be delivered')

        -- Out-of-order 3-part non-target WRPAGE (part 2 -> part 1 -> part 3 -> replay part 2) cleans up assembly
        sentMessages = {}
        local oooPayload = OldKraken.GroupFinder._pack({'Alice', 'Crafter', '8', '1', '1', string.rep('z', 180)})
        assert(Comm:SendProtocol('WRPAGE', oooPayload))
        while #Comm.queue > 0 do Comm:Pump() end
        assert(#sentMessages == 3)
        local beforeInvalid = Comm.stats.invalid
        Comm:OnAddonMessage(sentMessages[2][1], sentMessages[2][2], sentMessages[2][3], 'Alice')
        Comm:OnAddonMessage(sentMessages[1][1], sentMessages[1][2], sentMessages[1][3], 'Alice')
        Comm:OnAddonMessage(sentMessages[3][1], sentMessages[3][2], sentMessages[3][3], 'Alice')
        Comm:OnAddonMessage(sentMessages[2][1], sentMessages[2][2], sentMessages[2][3], 'Alice')
        assert(wrpageCalls == 1 and Comm.stats.received == 1 and Comm.stats.invalid == beforeInvalid)
        -- Advance past CACHE_TTL so no earlier assemblies interfere, then verify all 1024 slots are free
        now = now + 130
        for i = 1, 1024 do
            Comm:OnAddonMessage('OLDKRKN', 'GF2^QUERY^99-' .. i .. '-1^1^2^' .. string.rep('41', 80), 'GUILD', 'FreeSlot' .. i)
        end
        assert(Comm.stats.invalid == beforeInvalid, 'rejected out-of-order assembly leaked a slot')
        '''
    )


def test_seen_senders_guild_reset_and_version_updates():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(
        '''
        now = 1000
        serverNow = 1700000000
        currentGuild = 'Kraken'
        function GetTime() return now end
        function GetServerTime() return serverNow end
        function IsInGuild() return currentGuild ~= '' end
        function GetGuildInfo() return currentGuild ~= '' and currentGuild or nil end
        function GetRealmName() return 'Forever' end
        function UnitName() return 'Alice' end
        function CreateFrame()
            local f = { scripts = {} }
            function f:RegisterEvent() end
            function f:SetScript(name, fn) self.scripts[name] = fn end
            return f
        end
        C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end }
        addonChangedEvents = 0
        OldKraken = {
            Print = function() end,
            Fire = function(_, ev) if ev == 'ROSTER_ADDON_CHANGED' then addonChangedEvents = addonChangedEvents + 1 end end,
        }
        '''
    )
    lua.execute(COMM)
    lua.execute(
        '''
        local Comm = OldKraken.Communication
        Comm.ready = true

        -- First message from Peer1 records presence; repeat messages hit seenSenders without re-firing; OKP^HERE^ updates version
        Comm:OnAddonMessage('OLDKRKN', 'OKP^HERE^0.5.6', 'GUILD', 'Peer1')
        assert(Comm:HasRosterAddon('Peer1') and Comm:GetRosterVersion('Peer1') == '0.5.6')
        local countAfterFirst = addonChangedEvents
        Comm:OnAddonMessage('OLDKRKN', 'OKP^HERE^0.5.7', 'GUILD', 'Peer1')
        assert(Comm:GetRosterVersion('Peer1') == '0.5.7', 'OKP^HERE version update must bypass seenSenders cache')
        assert(addonChangedEvents == countAfterFirst + 1)

        -- Leave guild -> rejoin OtherGuild: seenSenders must clear so Peer1 re-triggers ROSTER_ADDON_CHANGED
        currentGuild = ''
        Comm:OnAddonMessage('OLDKRKN', 'OKP^HERE^0.5.7', 'GUILD', 'Peer1')
        assert(not Comm:HasRosterAddon('Peer1'))
        currentGuild = 'OtherGuild'
        local beforeRejoin = addonChangedEvents
        Comm:OnAddonMessage('OLDKRKN', 'OKP^HERE^0.5.7', 'GUILD', 'Peer1')
        assert(Comm:HasRosterAddon('Peer1') and addonChangedEvents > beforeRejoin, 'seenSenders must reset on guild switch')
        '''
    )


def test_workshop_sync_suppresses_duplicate_relay_wridx():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(
        '''
        now=100; serverNow=1700000000; outgoing={}; handlers={}; ticker=nil
        OldKraken={DB={},Communication={queue={},part1Filters={}},WorkshopRecipes={}}
        function UnitName() return 'Alice','Realm' end
        function GetGuildInfo() return 'Guild' end
        function GetRealmName() return 'TestRealm' end
        function GetServerTime() return serverNow end
        function GetTime() return now end
        function CreateFrame()
            return {RegisterEvent=function() end,SetScript=function(_,_,fn) eventHandler=fn end}
        end
        C_Timer={NewTicker=function(_,fn) ticker=fn end}
        function OldKraken.Communication:RegisterHandler(kind,fn) handlers[kind]=fn end
        function OldKraken.Communication:SendProtocol(kind,payload)
            outgoing[#outgoing+1]={kind=kind,payload=payload}
            return true
        end
        function OldKraken.WorkshopRecipes:ExportSnapshot()
            return 7, {{recipe=1,item=2,profession=171,seen=serverNow,name='R',product='P'}}
        end
        function OldKraken.WorkshopRecipes:ExportSnapshotMeta()
            return 7, 1
        end
        function OldKraken.WorkshopRecipes:ValidateSnapshotRecord(r)
            return type(r)=='table' and type(r.recipe)=='number'
        end
        function OldKraken.WorkshopRecipes:ImportSnapshot() return true end
        '''
    )
    lua.execute(GF)
    lua.execute(SYNC)
    lua.execute(
        '''
        eventHandler()
        local scope = OldKraken.DB.workshop.guilds['TestRealm\\001Guild']
        scope.recipeDirectSnapshots['Crafter1 Realm'] = {
            rev = 10,
            records = {{recipe=1,item=2,profession=171,seen=serverNow,name='R',product='P'}}
        }
        scope.recipeDirectSnapshots['Crafter2 Realm'] = {
            rev = 10,
            records = {{recipe=1,item=2,profession=171,seen=serverNow,name='R',product='P'}}
        }
        handlers.WRQ('Bob Realm', 'req', '')

        -- 1. Stale relay WRIDX (rev=5 < ourRev=10) must NOT suppress
        handlers.WRIDX('Relay1 Realm', 'idx', OldKraken.GroupFinder._pack({'Bob Realm', 'Crafter1 Realm', '5', '1'}))
        -- 2. Single valid relay WRIDX (rev=10) must NOT suppress alone (failover backup preserved)
        handlers.WRIDX('Relay1 Realm', 'idx', OldKraken.GroupFinder._pack({'Bob Realm', 'Crafter1 Realm', '10', '1'}))
        -- 3. Second distinct relayer (rev=10) suppresses queued relay WRIDX for Crafter1 Realm
        handlers.WRIDX('Relay2 Realm', 'idx', OldKraken.GroupFinder._pack({'Bob Realm', 'Crafter1 Realm', '10', '1'}))
        -- 4. Direct owner WRIDX (rev=10) suppresses queued relay WRIDX for Crafter2 Realm immediately
        handlers.WRIDX('Crafter2 Realm', 'idx', OldKraken.GroupFinder._pack({'Bob Realm', 'Crafter2 Realm', '10', '1'}))

        ticker(); ticker(); ticker()
        local sent = {}
        for _, p in ipairs(outgoing) do
            if p.kind == 'WRIDX' then
                local f = OldKraken.GroupFinder._unpackFields(p.payload, 4)
                sent[#sent+1] = f[2]
            end
        end
        assert(#sent == 1 and sent[1] == 'Alice Realm', 'expected only own WRIDX after 2-relay/direct suppression, got ' .. tostring(#sent))

        -- Verify stale + 1-relay alone keeps relay WRIDX alive for failover
        outgoing = {}; now = now + 70
        handlers.WRQ('Carol Realm', 'req', '')
        handlers.WRIDX('Relay1 Realm', 'idx', OldKraken.GroupFinder._pack({'Carol Realm', 'Crafter1 Realm', '10', '1'}))
        ticker(); ticker(); ticker()
        local sent2 = {}
        for _, p in ipairs(outgoing) do
            if p.kind == 'WRIDX' then
                local f = OldKraken.GroupFinder._unpackFields(p.payload, 4)
                sent2[f[2]] = true
            end
        end
        assert(sent2['Alice Realm'] and sent2['Crafter1 Realm'], 'single relayer must not suppress backup WRIDX')
        '''
    )


def test_group_finder_people_party_only_and_index_reuse():
    ui = runpy.run_path(str(ROOT / 'tests/test_ui_smoke.py'))['lua']
    ui.execute(
        '''
        local finder = OldKraken.GroupFinder
        local rosterScans = 0
        local guildCount = 1
        local online = false
        local inGroup = false
        local partyUnits = {}
        GetNumGuildMembers = function()
            rosterScans = rosterScans + 1
            return guildCount
        end
        GetGuildRosterInfo = function()
            if guildCount == 0 then return nil end
            return 'Remote-Realm', nil, nil, 60, nil, nil, nil, nil, online, nil, 'WARRIOR'
        end
        IsInRaid = function() return false end
        IsInGroup = function() return inGroup end
        local origUnitName = UnitName
        UnitName = function(unit)
            if unit == 'player' then return 'Me', 'Realm' end
            if partyUnits[unit] then return partyUnits[unit][1], partyUnits[unit][2] end
            return nil
        end
        UnitClass = function(unit)
            if unit == 'player' then return 'Priest', 'PRIEST' end
            if partyUnits[unit] then return 'Mage', 'MAGE' end
            return nil
        end
        UnitLevel = function(unit)
            if unit == 'player' or partyUnits[unit] then return 60 end
            return 0
        end
        UnitIsConnected = function(unit)
            if unit == 'player' or partyUnits[unit] then return true end
            return false
        end

        local key = 'Remote Realm\\001g1'
        finder.groups[key] = {
            id='g1', owner='Remote Realm', title='Test', category='quest', dungeon='',
            role='dps', maxSize=5, minLevel=1, maxLevel=60, description='',
            members={'Remote Realm'}, closed=false, seenAt=GetTime()
        }
        finder:Show()
        assert(rosterScans >= 1, 'initial Show must scan guild roster')
        local afterShow = rosterScans
        assert(not finder:IsGroupHiddenByOfflineOwner(key, finder.groups[key]))
        OldKrakenGroupFinderFrame:Hide()

        local peopleFrame
        for _, f in ipairs(createdFrames or {}) do
            if rawget(f, 'events') and f.events.GUILD_ROSTER_UPDATE and f.events.GROUP_ROSTER_UPDATE and f.scripts and f.scripts.OnEvent then
                peopleFrame = f
                break
            end
        end
        assert(peopleFrame, 'peopleEvents frame not found')

        -- 1. Join Party A with Remote-Realm (offline in guild, connected in party) + GuestA Realm -> party-only update (no full guild rescan)
        inGroup = true
        partyUnits = { party1 = {'Remote', 'Realm'}, party2 = {'GuestA', 'Realm'} }
        peopleFrame.scripts.OnEvent(peopleFrame, 'GROUP_ROSTER_UPDATE')
        assert(rosterScans == afterShow, 'GROUP_ROSTER_UPDATE must not rescan full guild roster')
        local savedNow = GetTime()
        GetTime = function() return savedNow + 305 end
        assert(not finder:IsGroupHiddenByOfflineOwner(key, finder.groups[key]), 'connected party member must override offline guild status')

        -- 2. Leave Party A -> partyPeople cleared, Remote-Realm falls back to guild offline status cleanly
        inGroup = false
        partyUnits = {}
        peopleFrame.scripts.OnEvent(peopleFrame, 'GROUP_ROSTER_UPDATE')
        assert(rosterScans == afterShow)
        GetTime = function() return savedNow + 620 end
        assert(finder:IsGroupHiddenByOfflineOwner(key, finder.groups[key]), 'stale partyPeople must be cleared on group leave')

        -- 3. Switch to Party B -> GuestB replaces GuestA without guild rescan
        inGroup = true
        partyUnits = { party1 = {'GuestB', 'Realm'} }
        peopleFrame.scripts.OnEvent(peopleFrame, 'GROUP_ROSTER_UPDATE')
        assert(rosterScans == afterShow)

        -- 4. Leave guild -> GUILD_ROSTER_UPDATE with 0 members resets guildRosterLoaded so Remote Realm is no longer considered confirmed offline
        guildCount = 0
        peopleFrame.scripts.OnEvent(peopleFrame, 'GUILD_ROSTER_UPDATE')
        assert(rosterScans == afterShow + 1)
        assert(not finder:IsGroupHiddenByOfflineOwner(key, finder.groups[key]), 'leaving guild must clear confirmed offline guild state')

        -- 5. Rapid burst of GUILD_ROSTER_UPDATE / GROUP_ROSTER_UPDATE with C_Timer.After coalesces scans without losing final leave state
        local origAfter = C_Timer and C_Timer.After
        local queuedTimers = {}
        C_Timer = C_Timer or {}
        C_Timer.After = function(delay, fn) queuedTimers[#queuedTimers + 1] = {delay = delay, fn = fn} end
        guildCount = 1
        local burstNow = savedNow + 700
        GetTime = function() return burstNow end
        peopleFrame.scripts.OnEvent(peopleFrame, 'GUILD_ROSTER_UPDATE')
        local baseScans = rosterScans
        for _ = 1, 10 do
            burstNow = burstNow + 0.05
            peopleFrame.scripts.OnEvent(peopleFrame, 'GUILD_ROSTER_UPDATE')
        end
        assert(rosterScans == baseScans, 'rapid GUILD_ROSTER_UPDATE burst must coalesce')
        local batch = queuedTimers; queuedTimers = {}
        for _, item in ipairs(batch) do item.fn() end
        assert(rosterScans == baseScans + 1, 'deferred GUILD_ROSTER_UPDATE must run once after burst')

        inGroup = true
        partyUnits = { party1 = {'Remote', 'Realm'} }
        burstNow = burstNow + 5
        peopleFrame.scripts.OnEvent(peopleFrame, 'GROUP_ROSTER_UPDATE')
        assert(not finder:IsGroupHiddenByOfflineOwner(key, finder.groups[key]))
        inGroup = false
        partyUnits = {}
        for _ = 1, 10 do
            burstNow = burstNow + 0.02
            peopleFrame.scripts.OnEvent(peopleFrame, 'GROUP_ROSTER_UPDATE')
        end
        burstNow = burstNow + 1
        local batch2 = queuedTimers; queuedTimers = {}
        for _, item in ipairs(batch2) do item.fn() end
        GetTime = function() return savedNow + 1050 end
        assert(finder:IsGroupHiddenByOfflineOwner(key, finder.groups[key]), 'final party leave in burst must be applied by deferred timer')

        -- 6. Overlapping party + full timers: if full runs first, stale party timer skips redundant scan
        local perfCounts = {}
        local origPerfEnabled = OldKraken.perfEnabled
        local origDebugProfilestop = debugprofilestop
        local origPerfRecord = OldKraken.PerfRecord
        OldKraken.perfEnabled = true
        debugprofilestop = function() return 0 end
        OldKraken.PerfRecord = function(_, label) perfCounts[label] = (perfCounts[label] or 0) + 1 end
        burstNow = savedNow + 1060
        GetTime = function() return burstNow end
        peopleFrame.scripts.OnEvent(peopleFrame, 'GUILD_ROSTER_UPDATE')
        queuedTimers = {}
        local fullBefore = perfCounts['gf.people.full'] or 0
        local partyBefore = perfCounts['gf.people.party'] or 0
        burstNow = burstNow + 0.1
        peopleFrame.scripts.OnEvent(peopleFrame, 'GROUP_ROSTER_UPDATE') -- queues party timer
        peopleFrame.scripts.OnEvent(peopleFrame, 'GUILD_ROSTER_UPDATE') -- queues full timer
        assert(#queuedTimers == 2, 'expected 2 timers, got ' .. tostring(#queuedTimers))
        local partyTimerFn, fullTimerFn = queuedTimers[1].fn, queuedTimers[2].fn
        queuedTimers = {}
        fullTimerFn()
        assert((perfCounts['gf.people.full'] or 0) == fullBefore + 1, 'full timer must record gf.people.full')
        partyTimerFn()
        assert((perfCounts['gf.people.party'] or 0) == partyBefore, 'stale party timer must skip after newer full scan')
        OldKraken.perfEnabled = origPerfEnabled
        debugprofilestop = origDebugProfilestop
        OldKraken.PerfRecord = origPerfRecord
        C_Timer.After = origAfter
        '''
    )


def test_workshop_sync_multi_provider_backup_failover():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(
        '''
        now=100; serverNow=1700000000; outgoing={}; handlers={}; ticker=nil
        imports = {}
        OldKraken={DB={},Communication={queue={},part1Filters={}},WorkshopRecipes={}}
        function UnitName() return 'ClientA','Realm' end
        function GetGuildInfo() return 'Guild' end
        function GetRealmName() return 'TestRealm' end
        function GetServerTime() return serverNow end
        function GetTime() return now end
        function CreateFrame()
            return {RegisterEvent=function() end,SetScript=function(_,_,fn) eventHandler=fn end}
        end
        C_Timer={NewTicker=function(_,fn) ticker=fn end}
        function OldKraken.Communication:RegisterHandler(kind,fn) handlers[kind]=fn end
        function OldKraken.Communication:SendProtocol(kind,payload)
            outgoing[#outgoing+1]={kind=kind,payload=payload}
            return true
        end
        function OldKraken.WorkshopRecipes:ExportSnapshot() return 1, {} end
        function OldKraken.WorkshopRecipes:ExportSnapshotMeta() return 1, 0 end
        function OldKraken.WorkshopRecipes:ValidateSnapshotRecord(r)
            return type(r)=='table' and type(r.recipe)=='number'
        end
        function OldKraken.WorkshopRecipes:ImportSnapshot(owner, recs)
            imports[#imports+1] = {owner=owner, count=#recs, first=recs[1] and recs[1].name}
            return true
        end
        '''
    )
    lua.execute(GF)
    lua.execute(SYNC)
    lua.execute(
        '''
        eventHandler()
        local function drainGets()
            local res = {}
            for _, p in ipairs(outgoing) do
                if p.kind == 'WRGET' then
                    local f = OldKraken.GroupFinder._unpackFields(p.payload, 3)
                    res[#res+1] = {target=f[1], owner=f[2], rev=f[3]}
                end
            end
            outgoing = {}
            return res
        end

        -- Scenario 1: B and D both announce WRIDX for C; B sends page 1 of 2 and then stalls.
        -- A retries B once at +45s, then switches to D automatically without waiting 180s or 600s WRQ.
        handlers.WRIDX('RelayB Realm', 'idx', OldKraken.GroupFinder._pack({'ClientA Realm', 'OwnerC Realm', '10', '2'}))
        handlers.WRIDX('RelayD Realm', 'idx', OldKraken.GroupFinder._pack({'ClientA Realm', 'OwnerC Realm', '11', '2'}))
        ticker()
        local gets = drainGets()
        assert(#gets == 1 and gets[1].target == 'RelayB Realm' and gets[1].rev == '10')

        -- B delivers page 1 of 2 (resets stalledAttempts to 0), then stops responding
        local bPage1 = OldKraken.GroupFinder._pack({'ClientA Realm', 'OwnerC Realm', '10', '1', '2', '1', '2', '171', serverNow, 'FromB1', 'Prod', 'L'})
        handlers.WRPAGE('RelayB Realm', 'p', bPage1)
        now = now + 45
        ticker()
        gets = drainGets()
        assert(#gets == 1 and gets[1].target == 'RelayB Realm', 'first stalled retry must target RelayB')

        now = now + 45
        ticker()
        gets = drainGets()
        assert(#gets == 1 and gets[1].target == 'RelayB Realm', 'second stalled retry after progress reset must target RelayB')

        -- After MAX_STALL_ATTEMPTS (2) without progress from B, A switches to D (rev=11) immediately
        now = now + 45
        ticker()
        gets = drainGets()
        assert(#gets == 1 and gets[1].target == 'RelayD Realm' and gets[1].rev == '11', 'must fail over to stored backup RelayD')

        -- B recovers late and sends page 2 for rev=10 -> must be ignored without corrupting D's transfer
        local bPage2 = OldKraken.GroupFinder._pack({'ClientA Realm', 'OwnerC Realm', '10', '2', '2', '2', '3', '171', serverNow, 'FromB2', 'Prod', 'L'})
        handlers.WRPAGE('RelayB Realm', 'p', bPage2)
        assert(#imports == 0)

        -- D completes transfer -> single clean import, and late WRPAGE from B/D causes no duplicate import
        local dPage1 = OldKraken.GroupFinder._pack({'ClientA Realm', 'OwnerC Realm', '11', '1', '2', '1', '2', '171', serverNow, 'FromD1', 'Prod', 'L'})
        local dPage2 = OldKraken.GroupFinder._pack({'ClientA Realm', 'OwnerC Realm', '11', '2', '2', '2', '3', '171', serverNow, 'FromD2', 'Prod', 'L'})
        handlers.WRPAGE('RelayD Realm', 'p', dPage1)
        handlers.WRPAGE('RelayD Realm', 'p', dPage2)
        assert(#imports == 1 and imports[1].count == 2 and imports[1].first == 'FromD1')
        handlers.WRPAGE('RelayB Realm', 'p', bPage2)
        handlers.WRPAGE('RelayD Realm', 'p', dPage2)
        assert(#imports == 1, 'late pages must not trigger duplicate import')

        -- Scenario 2: Both B and D are unavailable -> controlled cleanup allows fresh retry when D returns
        imports = {}
        handlers.WRIDX('RelayB Realm', 'idx', OldKraken.GroupFinder._pack({'ClientA Realm', 'OwnerE Realm', '12', '1'}))
        handlers.WRIDX('RelayD Realm', 'idx', OldKraken.GroupFinder._pack({'ClientA Realm', 'OwnerE Realm', '12', '1'}))
        ticker(); assert(drainGets()[1].target == 'RelayB Realm')
        now = now + 45; ticker(); assert(drainGets()[1].target == 'RelayB Realm')
        now = now + 45; ticker(); assert(drainGets()[1].target == 'RelayD Realm')
        now = now + 45; ticker(); assert(drainGets()[1].target == 'RelayD Realm')
        now = now + 45; ticker(); assert(#drainGets() == 0, 'exhausted providers must clear incoming cleanly')

        -- Exhausting all backups schedules a bounded recovery WRQ (60s instead of waiting 600s)
        local function countWRQ()
            local n = 0
            for _, p in ipairs(outgoing) do if p.kind == 'WRQ' then n = n + 1 end end
            outgoing = {}
            return n
        end
        assert(countWRQ() == 0)
        now = now + 59; ticker(); assert(countWRQ() == 0, 'recovery WRQ must respect 60s cooldown')
        now = now + 1; ticker(); assert(countWRQ() == 1, 'recovery WRQ must fire after 60s')

        -- Fresh WRIDX from RelayD after recovery succeeds cleanly
        handlers.WRIDX('RelayD Realm', 'idx', OldKraken.GroupFinder._pack({'ClientA Realm', 'OwnerE Realm', '12', '1'}))
        ticker()
        gets = drainGets()
        assert(#gets == 1 and gets[1].target == 'RelayD Realm')
        handlers.WRPAGE('RelayD Realm', 'p', OldKraken.GroupFinder._pack({'ClientA Realm', 'OwnerE Realm', '12', '1', '1', '5', '6', '171', serverNow, 'FromE', 'Prod', 'L'}))
        assert(#imports == 1 and imports[1].owner == 'OwnerE Realm')

        -- Scenario 3: Duplicate replay of already-received part must NOT postpone failover when backup D is available
        imports = {}
        handlers.WRIDX('RelayB Realm', 'idx', OldKraken.GroupFinder._pack({'ClientA Realm', 'OwnerF Realm', '20', '2'}))
        handlers.WRIDX('RelayD Realm', 'idx', OldKraken.GroupFinder._pack({'ClientA Realm', 'OwnerF Realm', '20', '2'}))
        ticker(); assert(drainGets()[1].target == 'RelayB Realm')
        local fB1 = OldKraken.GroupFinder._pack({'ClientA Realm', 'OwnerF Realm', '20', '1', '2', '1', '2', '171', serverNow, 'DupB1', 'Prod', 'L'})
        handlers.WRPAGE('RelayB Realm', 'p', fB1)
        -- Replay part 1 repeatedly while retries time out -> must not reset stalledAttempts or block failover
        now = now + 20; handlers.WRPAGE('RelayB Realm', 'p', fB1)
        now = now + 25; ticker(); assert(drainGets()[1].target == 'RelayB Realm')
        now = now + 20; handlers.WRPAGE('RelayB Realm', 'p', fB1)
        now = now + 25; ticker(); assert(drainGets()[1].target == 'RelayB Realm')
        now = now + 20; handlers.WRPAGE('RelayB Realm', 'p', fB1)
        now = now + 25; ticker()
        gets = drainGets()
        assert(#gets == 1 and gets[1].target == 'RelayD Realm', 'duplicate replay must not postpone failover to RelayD')
        local fD1 = OldKraken.GroupFinder._pack({'ClientA Realm', 'OwnerF Realm', '20', '1', '2', '1', '2', '171', serverNow, 'CleanD1', 'Prod', 'L'})
        local fD2 = OldKraken.GroupFinder._pack({'ClientA Realm', 'OwnerF Realm', '20', '2', '2', '2', '3', '171', serverNow, 'CleanD2', 'Prod', 'L'})
        handlers.WRPAGE('RelayD Realm', 'p', fD1)
        handlers.WRPAGE('RelayD Realm', 'p', fD2)
        assert(#imports == 1 and imports[1].owner == 'OwnerF Realm' and imports[1].count == 2 and imports[1].first == 'CleanD1')
        '''
    )


def test_comm_traffic_counters_and_commands():
    for lang in ('ukUA', 'enUS'):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals()._lang = lang
        lua.execute(
            '''
            now = 1000
            serverNow = 1700000000
            printed = {}
            function print(...)
                local parts = {}
                for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
                printed[#printed + 1] = table.concat(parts, ' ')
            end
            function GetTime() return now end
            function GetServerTime() return serverNow end
            function IsInGuild() return true end
            function GetGuildInfo() return 'Kraken' end
            function UnitName() return 'Alice' end
            function CreateFrame()
                local f = { scripts = {} }
                function f:RegisterEvent() end
                function f:SetScript(name, fn) self.scripts[name] = fn end
                return f
            end
            sendResult = 0
            sentMessages = {}
            Enum = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3 } }
            C_ChatInfo = {
                RegisterAddonMessagePrefix = function() return true end,
                SendAddonMessage = function(prefix, msg, chan)
                    if sendResult == 0 then sentMessages[#sentMessages + 1] = {prefix, msg, chan} end
                    return sendResult
                end
            }
            OldKraken = {}
            '''
        )
        lua.execute(LOCALE)
        lua.execute('OldKraken.InitializeLocale({ settings = { language = _lang } })')
        lua.execute(COMM)
        lua.execute(
            '''
            local Comm = OldKraken.Communication
            Comm.ready = true
            assert(Comm:RegisterHandler('WKPROF', function() end))
            Comm.part1Filters.WRPAGE = function() return false end

            -- 1. Multi-fragment TX (WKPROF): 1 logical, 2 fragments, 1 dedup, 1 throttle retry
            local payload = string.rep('A', 100)
            assert(Comm:SendProtocol('WKPROF', payload))
            assert(Comm:SendProtocol('WKPROF', payload)) -- deduplicated before queue
            sendResult = 3
            Comm:Pump() -- throttle retry
            sendResult = 0
            now = now + 65
            while #Comm.queue > 0 do Comm:Pump() end

            local txBucket = Comm.traffic.byKind.WKPROF
            assert(txBucket.txLogical == 1, 'expected 1 logical WKPROF')
            assert(txBucket.txDedup == 1, 'expected 1 dedup WKPROF')
            assert(txBucket.txRetries == 1, 'expected 1 retry WKPROF')
            assert(txBucket.txFrags == 2, 'expected 2 fragments WKPROF')
            assert(txBucket.txBytes == #sentMessages[1][2] + #sentMessages[2][2])

            -- 2. RX: deliver both WKPROF fragments + replay fragment 1 (rxDedup)
            Comm:OnAddonMessage(sentMessages[1][1], sentMessages[1][2], sentMessages[1][3], 'Peer1')
            Comm:OnAddonMessage(sentMessages[2][1], sentMessages[2][2], sentMessages[2][3], 'Peer1')
            Comm:OnAddonMessage(sentMessages[1][1], sentMessages[1][2], sentMessages[1][3], 'Peer1')
            assert(txBucket.rxFrags == 3 and txBucket.rxLogical == 1 and txBucket.rxDedup == 1)

            -- 3. Filtered RX (WRPAGE part1Filter=false) -> part 1 is rxFiltered, replayed part 1 is rxDedup, part 2 is rxFilteredTail
            local wrPart1 = 'GF2^WRPAGE^1-1-1^1^2^' .. string.rep('41', 80)
            local wrPart2 = 'GF2^WRPAGE^1-1-1^2^2^' .. string.rep('41', 10)
            Comm:OnAddonMessage('OLDKRKN', wrPart1, 'GUILD', 'Peer2')
            Comm:OnAddonMessage('OLDKRKN', wrPart1, 'GUILD', 'Peer2')
            Comm:OnAddonMessage('OLDKRKN', wrPart2, 'GUILD', 'Peer2')
            assert(Comm.traffic.byKind.WRPAGE.rxFiltered == 1 and Comm.traffic.byKind.WRPAGE.rxDedup == 1 and Comm.traffic.byKind.WRPAGE.rxFilteredTail == 1)
            Comm:OnAddonMessage('OLDKRKN', 'GF2^BADKIND^1-1-1^1^1^41', 'GUILD', 'Peer2')
            assert(Comm.traffic.byKind.INVALID.rxDropped == 1)

            -- 4. OKP control messages and /okr comm traffic [reset]
            Comm:OnAddonMessage('OLDKRKN', 'OKP^HERE^0.5.7', 'GUILD', 'Peer3')
            assert(Comm.traffic.byKind.OKP_HERE.rxLogical == 1 and Comm.traffic.byKind.OKP_HERE.rxFrags == 1)
            assert(Comm:HandleCommand('comm traffic') == true)
            local out = table.concat(printed, '\\n')
            assert(out:find('TX: queued=', 1, true) and out:find('RX: handled=', 1, true) and out:find('tail=1', 1, true))
            assert(out:find('WKPROF: txQ=1 txFrag=2', 1, true))
            assert(Comm:HandleCommand('comm traffic reset') == true)
            assert(next(Comm.traffic.byKind) == nil)

            -- 5. txDropReasons breakdown (targetOffline, overflow, noGuild, guildChanged, sendError)
            printed = {}
            -- 5a. WRPAGE WHISPER TargetOffline
            Comm:OnAddonMessage('OLDKRKN', 'OKP^HERE^0.5.8-alpha.2', 'GUILD', 'PeerOff')
            local origSend = C_ChatInfo.SendAddonMessage
            C_ChatInfo.SendAddonMessage = function(_, _, ch)
                if ch == 'WHISPER' then return 12 end
                return 0
            end
            assert(Comm:SendProtocol('WRPAGE', 'page-data', 'PeerOff', nil, 'PeerOff') == true)
            now = now + 2; Comm:Pump()
            assert(Comm.traffic.byKind.WRPAGE.txDrops == 1)
            assert(Comm.traffic.byKind.WRPAGE.txDropReasons.targetOffline == 1)

            -- 5a-enum. Explicit Enum.SendAddonMessageResult.TargetOffline takes precedence over numeric 12
            Enum.SendAddonMessageResult.TargetOffline = 42
            C_ChatInfo.SendAddonMessage = function(_, _, ch)
                if ch == 'WHISPER' then return 42 end
                return 0
            end
            assert(Comm:SendProtocol('WRPAGE', 'page-data-2', 'PeerOff', nil, 'PeerOff') == true)
            now = now + 2; Comm:Pump()
            assert(Comm.traffic.byKind.WRPAGE.txDrops == 2)
            assert(Comm.traffic.byKind.WRPAGE.txDropReasons.targetOffline == 2)
            Enum.SendAddonMessageResult.TargetOffline = nil

            -- 5b. noGuild via QueueMessage
            local origGuild = GetGuildInfo
            GetGuildInfo = function() return nil end
            assert(Comm:QueueMessage('GF2^QUERY^1-1-2^1^1^41') == false)
            assert(Comm.traffic.byKind.QUERY.txDrops == 1)
            assert(Comm.traffic.byKind.QUERY.txDropReasons.noGuild == 1)
            GetGuildInfo = origGuild

            -- 5c. guildChanged while queued
            assert(Comm:SendProtocol('WRGET', 'req-data', 'PeerOff', nil, 'PeerOff') == true)
            GetGuildInfo = function() return 'OtherGuild' end
            now = now + 2; Comm:Pump()
            assert(Comm.traffic.byKind.WRGET.txDrops == 1)
            assert(Comm.traffic.byKind.WRGET.txDropReasons.guildChanged == 1)
            GetGuildInfo = origGuild

            -- 5d. sendError after MAX_ERROR_ATTEMPTS (5)
            C_ChatInfo.SendAddonMessage = function() return 9 end
            assert(Comm:SendProtocol('WKQUERY', '') == true)
            for _ = 1, 5 do now = now + 100; Comm:Pump() end
            assert(Comm.traffic.byKind.WKQUERY.txDrops == 1)
            assert(Comm.traffic.byKind.WKQUERY.txDropReasons.sendError == 1)
            C_ChatInfo.SendAddonMessage = origSend

            -- 5e. overflow via queue full
            for i = 1, 4096 do Comm.queue[i] = { message = 'x', attempts = 0 } end
            local okOverflow, errOverflow = Comm:SendProtocol('WRIDX', 'idx')
            assert(not okOverflow and errOverflow == 'queue full')
            assert(Comm.traffic.byKind.WRIDX.txDrops == 1)
            assert(Comm.traffic.byKind.WRIDX.txDropReasons.overflow == 1)
            for i = #Comm.queue, 1, -1 do Comm.queue[i] = nil end

            -- 5f. targetError (non-offline WHISPER error, e.g. TargetRequired = 6) and tooLong
            Comm:OnAddonMessage('OLDKRKN', 'OKP^HERE^0.5.8-alpha.2', 'GUILD', 'PeerOff')
            C_ChatInfo.SendAddonMessage = function(_, _, ch)
                if ch == 'WHISPER' then return 6 end
                return 0
            end
            assert(Comm:SendProtocol('WRGET', 'req-2', 'PeerOff', nil, 'PeerOff') == true)
            now = now + 2; Comm:Pump()
            assert(Comm.traffic.byKind.WRGET.txDrops == 2)
            assert(Comm.traffic.byKind.WRGET.txDropReasons.targetError == 1)
            C_ChatInfo.SendAddonMessage = origSend

            local longMsg = 'GF2^SYNC^1-1-3^1^1^' .. string.rep('A', 230)
            local okLong, errLong = Comm:QueueMessage(longMsg)
            assert(not okLong and errLong == 'tooLong')
            assert(Comm.traffic.byKind.SYNC.txDrops == 1)
            assert(Comm.traffic.byKind.SYNC.txDropReasons.tooLong == 1)

            -- Invariant: txDrops == sum(txDropReasons) for every kind
            for kind, b in pairs(Comm.traffic.byKind) do
                local sumReasons = 0
                for _, cnt in pairs(b.txDropReasons or {}) do sumReasons = sumReasons + cnt end
                assert(b.txDrops == sumReasons, 'txDrops must equal sum of txDropReasons for ' .. tostring(kind))
            end

            assert(Comm:HandleCommand('comm traffic') == true)
            local dropOut = table.concat(printed, '\\n')
            assert(dropOut:find('TX drops:', 1, true), 'must print TX drops summary line')
            assert(dropOut:find('targetOffline=2', 1, true))
            assert(dropOut:find('targetError=1', 1, true))
            assert(dropOut:find('tooLong=1', 1, true))
            assert(dropOut:find('overflow=1', 1, true))
            assert(dropOut:find('noGuild=1', 1, true))
            assert(dropOut:find('guildChanged=1', 1, true))
            assert(dropOut:find('sendError=1', 1, true))
            assert(Comm:HandleCommand('comm traffic reset') == true)
            assert(next(Comm.traffic.byKind) == nil)
            '''
        )


def test_workshop_orders_worelay_suppression():
    mod = runpy.run_path(str(ROOT / 'tests/test_workshop_orders.py'))
    make_client = mod['client']
    tick = mod['tick']
    owner = make_client('Alice')
    relay = make_client('Bob')
    tick(owner); tick(relay)
    owner.execute('''
        OldKraken.WorkshopOrders:Show()
        pickOrderRecipe(OldKrakenWorkshopOrdersFrame.orderForm, 'Relay potion', 171, 0, 9004)
        click('Опублікувати')
        for k in pairs(OldKraken.DB.workshop.guilds['Realm\\001Guild'].orderOwners['Alice Mon']) do orderKey = k end
    ''')
    tick(owner)
    owner.execute('''
        for _, p in ipairs(outgoing) do
            if p[1] == 'WORDER' then worder_v1 = p[2] end
        end
    ''')
    worder_v1 = owner.globals().worder_v1
    assert worder_v1

    # Cancel order on owner to produce rev=2
    owner.execute('''
        outgoing = {}
        OldKraken.WorkshopOrders:Show(orderKey)
        local b = OldKrakenWorkshopOrdersFrame.cancel
        b.scripts.OnClick(b)
    ''')
    tick(owner)
    owner.execute('''
        for _, p in ipairs(outgoing) do
            if p[1] == 'WORDER' then worder_v2 = p[2] end
        end
    ''')
    worder_v2 = owner.globals().worder_v2
    assert worder_v2

    relay.globals().worder_v1 = worder_v1
    relay.globals().worder_v2 = worder_v2
    relay.execute('''
        -- Bob receives direct rev=2 from Alice (cached in scope.orderRelays)
        handlers.WORDER('Alice Mon', 'GUILD', worder_v2)
        outgoing = {}

        -- 1. WOQUERY schedules relayDirty; stale WORELAY (rev=1 < cachedRev=2) must NOT suppress
        handlers.WOQUERY('Carol Mon', 'GUILD', '')
        handlers.WORELAY('Relay1 Mon', 'GUILD', worder_v1)
        handlers.WORELAY('Relay2 Mon', 'GUILD', worder_v1)
        clock = clock + 4; for _, f in ipairs(timers) do f() end
        local sent = 0
        for _, p in ipairs(outgoing) do if p[1] == 'WORELAY' then sent = sent + 1 end end
        assert(sent == 1, 'stale WORELAY must not suppress backup WORELAY')

        -- 2. Next WOQUERY cycle: 1 current WORELAY preserves backup; 2nd distinct WORELAY suppresses
        clock = clock + 35
        outgoing = {}
        handlers.WOQUERY('Dave Mon', 'GUILD', '')
        handlers.WORELAY('Relay1 Mon', 'GUILD', worder_v2)
        clock = clock + 4; for _, f in ipairs(timers) do f() end
        sent = 0
        for _, p in ipairs(outgoing) do if p[1] == 'WORELAY' then sent = sent + 1 end end
        assert(sent == 1, 'single current WORELAY must keep backup alive')

        clock = clock + 35
        outgoing = {}
        handlers.WOQUERY('Eve Mon', 'GUILD', '')
        handlers.WORELAY('Relay1 Mon', 'GUILD', worder_v2)
        handlers.WORELAY('Relay2 Mon', 'GUILD', worder_v2)
        clock = clock + 4; for _, f in ipairs(timers) do f() end
        sent = 0
        for _, p in ipairs(outgoing) do if p[1] == 'WORELAY' then sent = sent + 1 end end
        assert(sent == 0, 'two distinct current WORELAYs must suppress relayDirty')

        -- 3. Next WOQUERY cycle: Relay1 from previous cycle must NOT leak (relaySeen reset), and stale direct WORDER must NOT suppress
        clock = clock + 35
        outgoing = {}
        handlers.WOQUERY('Frank Mon', 'GUILD', '')
        handlers.WORDER('Alice Mon', 'GUILD', worder_v1)
        clock = clock + 4; for _, f in ipairs(timers) do f() end
        sent = 0
        for _, p in ipairs(outgoing) do if p[1] == 'WORELAY' then sent = sent + 1 end end
        assert(sent == 1, 'stale direct WORDER must NOT suppress relayDirty')

        -- 4. Current direct WORDER cancels immediately
        clock = clock + 35
        outgoing = {}
        handlers.WOQUERY('Frank2 Mon', 'GUILD', '')
        handlers.WORDER('Alice Mon', 'GUILD', worder_v2)
        clock = clock + 4; for _, f in ipairs(timers) do f() end
        sent = 0
        for _, p in ipairs(outgoing) do if p[1] == 'WORELAY' then sent = sent + 1 end end
        assert(sent == 0, 'direct WORDER must suppress relayDirty immediately')

        -- 5. cached.rev=1, observed.rev=2 (via newer WORELAY): two relays with rev=1 must NOT suppress cached rev=1
        handlers.WORDER('Alice Mon', 'GUILD', worder_v1) -- ensure cached is rev=1? Need fresh order where cached=1, observed=2
    ''')
    # Fresh order: cached=1 (direct v1), observed=2 (relayed v2) -> two rev=1 relays must NOT suppress
    alice3 = make_client('AliceThree')
    tick(alice3)
    alice3.execute('''
        OldKraken.WorkshopOrders:Show()
        pickOrderRecipe(OldKrakenWorkshopOrdersFrame.orderForm, 'Relay potion', 171, 0, 9004)
        click('Опублікувати')
        for k in pairs(OldKraken.DB.workshop.guilds['Realm\\001Guild'].orderOwners['AliceThree Mon']) do orderKey = k end
    ''')
    tick(alice3)
    alice3.execute("for _, p in ipairs(outgoing) do if p[1] == 'WORDER' then a3_v1 = p[2] end end")
    a3_v1 = alice3.globals().a3_v1
    alice3.execute('''
        outgoing = {}
        OldKraken.WorkshopOrders:Show(orderKey)
        local b = OldKrakenWorkshopOrdersFrame.cancel
        b.scripts.OnClick(b)
    ''')
    tick(alice3)
    alice3.execute("for _, p in ipairs(outgoing) do if p[1] == 'WORDER' then a3_v2 = p[2] end end")
    a3_v2 = alice3.globals().a3_v2

    relay_split = make_client('BobSplit')
    tick(relay_split)
    relay_split.globals().a3_v1 = a3_v1
    relay_split.globals().a3_v2 = a3_v2
    relay_split.execute('''
        handlers.WORDER('AliceThree Mon', 'GUILD', a3_v1) -- cached.rev = 1
        handlers.WORELAY('RelayX Mon', 'GUILD', a3_v2)   -- observed.rev = 2
        clock = clock + 35
        outgoing = {}
        handlers.WOQUERY('Ivan Mon', 'GUILD', '')
        handlers.WORELAY('Relay1 Mon', 'GUILD', a3_v1)
        handlers.WORELAY('Relay2 Mon', 'GUILD', a3_v1)
        clock = clock + 4; for _, f in ipairs(timers) do f() end
        local sent = 0
        for _, p in ipairs(outgoing) do if p[1] == 'WORELAY' then sent = sent + 1 end end
        assert(sent == 1, 'rev=1 relays must not suppress when observed.rev=2 even if cached.rev=1')
    ''')
    # 4. Newer WORELAY still updates observed even when relayDirty is active
    alice2 = make_client('AliceTwo')
    tick(alice2)
    alice2.execute('''
        OldKraken.WorkshopOrders:Show()
        pickOrderRecipe(OldKrakenWorkshopOrdersFrame.orderForm, 'Relay potion', 171, 0, 9004)
        click('Опублікувати')
        for k in pairs(OldKraken.DB.workshop.guilds['Realm\\001Guild'].orderOwners['AliceTwo Mon']) do orderKey = k end
    ''')
    tick(alice2)
    alice2.execute('''
        for _, p in ipairs(outgoing) do if p[1] == 'WORDER' then a2_v1 = p[2] end end
    ''')
    a2_v1 = alice2.globals().a2_v1
    alice2.execute('''
        outgoing = {}
        OldKraken.WorkshopOrders:Show(orderKey)
        local b = OldKrakenWorkshopOrdersFrame.cancel
        b.scripts.OnClick(b)
    ''')
    tick(alice2)
    alice2.execute('''
        for _, p in ipairs(outgoing) do if p[1] == 'WORDER' then a2_v2 = p[2] end end
    ''')
    a2_v2 = alice2.globals().a2_v2
    relay.globals().a2_v1 = a2_v1
    relay.globals().a2_v2 = a2_v2
    relay.execute('''
        handlers.WORDER('AliceTwo Mon', 'GUILD', a2_v1)
        clock = clock + 35
        handlers.WOQUERY('Hank Mon', 'GUILD', '')
        handlers.WORELAY('Relay1 Mon', 'GUILD', a2_v2)
        local s = OldKraken.DB.workshop.guilds['Realm\\001Guild'].orderObserved
        local updated = false
        for _, o in pairs(s) do
            if o.owner == 'AliceTwo Mon' and o.status == 'cancelled' and o.rev == 2 then updated = true end
        end
        assert(updated, 'newer WORELAY must still update observed')
    ''')


def test_workshop_recipes_first_open_perf_labels():
    mod = runpy.run_path(str(ROOT / 'tests/test_workshop_orders.py'))
    make_client = mod['client']
    c1 = make_client('Alice')
    c1.execute('''
        local profCalls = 0
        debugprofilestop = function() profCalls = profCalls + 1; return profCalls * 2.5 end
        OldKraken.perfEnabled = false
        OldKraken.perfStats = {}
        function OldKraken:PerfRecord(label) self.perfStats[label] = (self.perfStats[label] or 0) + 1 end
        OldKraken.WorkshopRecipes:Show()
        assert(profCalls == 0, 'debugprofilestop must not be called when perfEnabled is false')
        assert(OldKraken.perfStats['wk.recipes.show'] == nil)
    ''')
    c2 = make_client('Bob', embedded=True)
    c2.execute('''
        local profCalls = 0
        debugprofilestop = function() profCalls = profCalls + 1; return profCalls * 2.5 end
        OldKraken.perfEnabled = true
        OldKraken.perfStats = {}
        function OldKraken:PerfRecord(label, elapsedMs, itemCount)
            local s = self.perfStats[label] or { calls = 0, total = 0 }
            s.calls = s.calls + 1
            s.total = s.total + (elapsedMs or 0)
            self.perfStats[label] = s
        end
        OldKraken.WorkshopRecipes:Show()
        local s = OldKraken.perfStats
        assert(s['wk.ui.create'] and s['wk.ui.create'].calls == 1, 'must record wk.ui.create on first open')
        assert(s['wk.recipes.create'] and s['wk.recipes.create'].calls == 1, 'must record wk.recipes.create on first open')
        assert(s['wk.recipes.show'] and s['wk.recipes.show'].calls == 1, 'must record wk.recipes.show')
        assert(s['wk.recipes.render'] and s['wk.recipes.render'].calls >= 1, 'must record wk.recipes.render')
        assert(s['wk.recipes.scan'] and s['wk.recipes.scan'].calls >= 1, 'must record wk.recipes.scan')
    ''')


def test_workshop_recipes_render_name_cache_and_sort_keys():
    mod = runpy.run_path(str(ROOT / 'tests/test_workshop_orders.py'))
    make_client = mod['client']
    c = make_client('Alice', embedded=True)
    c.execute('''
        local itemCalls, spellCalls = 0, 0
        GetItemInfo = function(id)
            itemCalls = itemCalls + 1
            return 'Item ' .. string.format('%03d', 200 - id), nil, 1, 1, 1, 'Trade Goods', 'Parts', 20, nil, 134400, 0, 7, 0, 0, 0
        end
        GetSpellInfo = function(id)
            spellCalls = spellCalls + 1
            return 'Spell ' .. string.format('%03d', 200 - id), nil, 134400
        end
        C_Item = { GetItemInfo = GetItemInfo }
        C_Spell = nil

        local store = OldKraken.DB.workshop.guilds['Realm\\001Guild'].recipes
        for ownerIdx = 1, 20 do
            local owner = string.format('Crafter%02d Mon', ownerIdx)
            store[owner] = {}
            for rIdx = 1, 15 do
                local recipeID = 5000 + rIdx
                local itemID = (rIdx <= 10) and (8000 + rIdx) or 0
                store[owner][recipeID] = {
                    recipe = recipeID, item = itemID, profession = 171,
                    seen = 1700000000, name = 'Fallback ' .. rIdx, product = '',
                }
            end
        end

        OldKraken.perfEnabled = true
        OldKraken.perfStats = {}
        function OldKraken:PerfRecord(label, elapsedMs, itemCount)
            local s = self.perfStats[label] or { calls = 0, items = 0 }
            s.calls = s.calls + 1
            s.items = s.items + (itemCount or 0)
            self.perfStats[label] = s
        end
        debugprofilestop = function() return 10 end

        OldKraken.WorkshopRecipes:Show()
        -- Flush deferred scanCachedRecords timers
        for _, fn in ipairs(timers) do fn() end

        itemCalls, spellCalls = 0, 0
        OldKraken.perfStats = {}
        OldKraken.WorkshopRecipes:RefreshPanel()
        -- 10 unique items (20 owners each -> 200 records) + 5 unique spells (20 owners each -> 100 records):
        -- all 300 records pass filtering, while byRecipe grouping leaves 15 rows for sorting.
        -- Each unique item/spell must be queried at most once during renderBody().
        assert(itemCalls <= 10, 'GetItemInfo must be called at most once per unique item, got ' .. itemCalls)
        assert(spellCalls <= 5, 'GetSpellInfo must be called at most once per unique spell, got ' .. spellCalls)
        assert(OldKraken.perfStats['wk.recipes.render'].items == itemCalls + spellCalls)

        -- Verify sort order (name ascending, deterministic across repeat renders)
        local function visibleNames()
            local out = {}
            for _, row in ipairs(frames) do
                if type(row.entry) == 'table' and row.name and row:IsShown() then
                    out[#out + 1] = row.name:GetText() .. '|' .. row.entry.owner
                end
            end
            return out
        end
        local firstOrder = visibleNames()
        assert(#firstOrder == 10, 'page 1 must show 10 sorted rows')
        for i = 2, #firstOrder do
            local prevName = firstOrder[i - 1]:match('^([^|]+)')
            local curName = firstOrder[i]:match('^([^|]+)')
            assert(prevName <= curName, 'rows must be sorted ascending by display name')
        end
        OldKraken.WorkshopRecipes:RefreshPanel()
        local secondOrder = visibleNames()
        for i = 1, #firstOrder do
            assert(firstOrder[i] == secondOrder[i], 'repeat render must keep identical order')
        end

        -- Verify owner tie-break when two distinct recipes resolve to the same display name
        local origSpell = GetSpellInfo
        GetSpellInfo = function(id)
            if id == 5011 or id == 5012 then return 'AAA Tie Spell', nil, 134400 end
            return origSpell(id)
        end
        store['Crafter20 Mon'][5011] = { recipe = 5011, item = 0, profession = 171, seen = 1700000001, name = 'T1', product = '' }
        store['Crafter01 Mon'][5012] = { recipe = 5012, item = 0, profession = 171, seen = 1700000001, name = 'T2', product = '' }
        -- Force non-grouped view via owner filter or check grouped tie-break when only one owner per recipe
        for ownerIdx = 1, 19 do store[string.format('Crafter%02d Mon', ownerIdx)][5011] = nil end
        for ownerIdx = 2, 20 do store[string.format('Crafter%02d Mon', ownerIdx)][5012] = nil end
        OldKraken.WorkshopRecipes:Show(true)
        for _, fn in ipairs(timers) do fn() end
        OldKraken.WorkshopRecipes:RefreshPanel()
        local tieOrder = visibleNames()
        assert(tieOrder[1] == 'AAA Tie Spell|Crafter01 Mon' and tieOrder[2] == 'AAA Tie Spell|Crafter20 Mon',
            'identical display names must tie-break by owner ascending')
        GetSpellInfo = origSpell

        -- Filter path (matchesFilter) also reuses per-render name cache
        local f = OldKraken.UIHub.pages.workshop.frame.recipesView
        f.query:SetText('Spell')
        f.query.scripts.OnTextChanged(f.query, true)
        itemCalls, spellCalls = 0, 0
        OldKraken.WorkshopRecipes:RefreshPanel()
        assert(itemCalls <= 10 and spellCalls <= 5, 'filtered render must also cache name API calls')
    ''')


if __name__ == '__main__':
    test_core_perf_commands_and_metrics()
    test_comm_hex_codec_and_cache_counters()
    test_export_snapshot_meta_matches_export_snapshot()
    test_part1_filters_skip_non_target_multipart()
    test_seen_senders_guild_reset_and_version_updates()
    test_workshop_sync_suppresses_duplicate_relay_wridx()
    test_workshop_sync_multi_provider_backup_failover()
    test_group_finder_people_party_only_and_index_reuse()
    test_comm_traffic_counters_and_commands()
    test_workshop_orders_worelay_suppression()
    test_workshop_recipes_first_open_perf_labels()
    test_workshop_recipes_render_name_cache_and_sort_keys()
    print('Perf diagnostics and codec/cache checks passed')
