from pathlib import Path
from lupa.lua51 import LuaRuntime, lua_type

ROOT = Path(__file__).resolve().parents[1]


def clone_to_lua(val, dst_lua):
    if lua_type(val) != 'table':
        return val
    keys = list(val.keys())
    if keys and all(isinstance(k, int) and 1 <= k <= len(keys) for k in keys):
        return dst_lua.table(*[clone_to_lua(val[i], dst_lua) for i in range(1, len(keys) + 1)])
    t = dst_lua.table()
    for k, v in val.items():
        t[k] = clone_to_lua(v, dst_lua)
    return t


def make_runtime(saved_db=None, in_inst=False, inst_type='none'):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
        local listeners = {}
        local guildName = 'TestGuild'
        local nowTime, serverTime = 100, 1700000000
        local inInstanceFlag, instanceType = false, 'none'
        local partyMembers = {}
        local inRaidFlag = false
        sentProtocols = {}
        chatInfos = {}
        chatErrors = {}
        createdFrames = {}
        tickers = {}

        OldKraken = {
            name = 'OldKraken',
            DB = { settings = { language = 'ukUA' }, groupFinder = {} },
            Database = {
                IsValidRealm = function(_, r) return type(r) == 'string' and #r > 0 end,
                GetRealmScope = function() return 'Forever' end,
            },
            Communication = {
                RegisterHandler = function() end,
                SendProtocol = function(_, kind, payload)
                    sentProtocols[#sentProtocols + 1] = { kind = kind, payload = payload }
                    return true
                end,
                RequestSync = function() return true end,
                ClearProtocolState = function() end,
                queue = {},
            },
            Print = function(_, msg) chatInfos[#chatInfos + 1] = msg end,
            PrintError = function(_, msg) chatErrors[#chatErrors + 1] = msg end,
        }
        function OldKraken:On(event, fn)
            listeners[event] = listeners[event] or {}
            listeners[event][#listeners[event] + 1] = fn
        end
        function OldKraken:Fire(event, ...)
            for _, fn in ipairs(listeners[event] or {}) do fn(...) end
        end

        function setInstanceState(inInst, instType)
            inInstanceFlag = inInst
            instanceType = instType
        end
        function setPartyState(members, isRaid)
            partyMembers = members or {}
            inRaidFlag = isRaid == true
        end
        function resetSent()
            sentProtocols = {}
            chatInfos = {}
            chatErrors = {}
        end

        function GetTime() return nowTime end
        function GetServerTime() return serverTime end
        function IsInInstance() return inInstanceFlag, instanceType end
        function GetGuildInfo() return guildName end
        function GetRealmName() return 'Forever' end
        function UnitName(unit)
            if unit == 'player' then return 'Alice', 'Mon' end
            if type(unit) == 'string' then
                local idx = tonumber(unit:match('^party(%d+)$') or unit:match('^raid(%d+)$'))
                if idx and partyMembers[idx] then return partyMembers[idx], nil end
            end
            return nil
        end
        function IsInGroup() return #partyMembers > 0 end
        function IsInRaid() return inRaidFlag end
        function GetNumGroupMembers() return #partyMembers end
        function UnitExists(unit)
            if unit == 'player' then return true end
            local idx = type(unit) == 'string' and tonumber(unit:match('^party(%d+)$') or unit:match('^raid(%d+)$'))
            return idx ~= nil and partyMembers[idx] ~= nil
        end
        function UnitIsConnected() return true end
        function UnitGroupRolesAssigned() return 'NONE' end
        function UnitGetAvailableRoles() return true, true, true end

        DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) chatInfos[#chatInfos + 1] = msg end }
        C_GuildInfo = { GuildRoster = function() end }
        C_Timer = {
            After = function(_, fn) fn() end,
            NewTicker = function(_, fn) tickers[#tickers + 1] = fn end,
        }

        function CreateFrame()
            local frame = { events = {}, scripts = {} }
            function frame:RegisterEvent(event) self.events[event] = true end
            function frame:SetScript(name, fn) self.scripts[name] = fn end
            createdFrames[#createdFrames + 1] = frame
            return frame
        end
    ''')
    for rel in ('Locale.lua', 'ActivityCatalog.lua', 'GroupFinder.lua', 'GroupFinderIntegration.lua'):
        lua.execute((ROOT / rel).read_text(encoding='utf-8'))
    if saved_db is not None:
        lua.globals().OldKraken.DB.groupFinder = clone_to_lua(saved_db, lua)
    lua.globals().setInstanceState(in_inst, inst_type)
    lua.execute('OldKraken:Fire("INITIALIZED")')
    return lua


def test_dungeon_entry_autoclose_and_lifecycle():
    lua = make_runtime()
    lua.execute('''
        local finder = OldKraken.GroupFinder
        local gfFrame = createdFrames[#createdFrames]
        assert(gfFrame and gfFrame.events.PLAYER_ENTERING_WORLD and gfFrame.events.ZONE_CHANGED_NEW_AREA)

        local function fireEvent(ev)
            gfFrame.scripts.OnEvent(gfFrame, ev)
        end
        local function countKind(kind)
            local n = 0
            for _, item in ipairs(sentProtocols) do
                if item.kind == kind then n = n + 1 end
            end
            return n
        end

        -- 4. Normal zone transitions outside dungeon must keep listing open
        assert(finder:Create('Deadmines run', 'dungeon', '', 5, 17, 26, 'dps', 'deadmines'))
        local group
        for _, g in pairs(finder.groups) do if g.owner == finder.identity then group = g end end
        assert(group ~= nil and not group.closed)
        resetSent()
        setInstanceState(false, 'none')
        fireEvent('PLAYER_ENTERING_WORLD')
        fireEvent('ZONE_CHANGED_NEW_AREA')
        assert(not group.closed, 'open world zone change must not close listing')
        assert(countKind('CANCEL') == 0)

        -- 5. Being in a party, raid, or battleground outside a 5-man dungeon must not close listing
        setPartyState({ 'Bob Mon', 'Carol Mon' }, false)
        setInstanceState(false, 'none')
        fireEvent('GROUP_ROSTER_UPDATE')
        fireEvent('PLAYER_ENTERING_WORLD')
        assert(not group.closed, 'party in open world must not close listing')

        setPartyState({ 'Bob Mon', 'Carol Mon' }, true)
        setInstanceState(true, 'raid')
        fireEvent('PLAYER_ENTERING_WORLD')
        assert(not group.closed, 'raid instance must not close listing')

        setInstanceState(true, 'pvp')
        fireEvent('PLAYER_ENTERING_WORLD')
        assert(not group.closed, 'battleground must not close listing')
        assert(countKind('CANCEL') == 0)

        -- 1. Entering a 5-man dungeon ('party') closes active listing via Finder:Cancel()
        resetSent()
        setPartyState({ 'Bob Mon' }, false)
        setInstanceState(true, 'party')
        fireEvent('PLAYER_ENTERING_WORLD')
        assert(group.closed == true, 'entering dungeon must close active listing')
        assert(countKind('CANCEL') == 1, 'must send exactly 1 CANCEL')
        assert(#chatInfos == 1 and chatInfos[1]:find('автоматично закрито після входу в підземелля', 1, true))
        assert(#chatErrors == 0)

        -- 3. Duplicate entry events inside dungeon must NOT send duplicate CANCEL or chat messages
        resetSent()
        fireEvent('PLAYER_ENTERING_WORLD')
        fireEvent('ZONE_CHANGED_NEW_AREA')
        assert(countKind('CANCEL') == 0, 'duplicate entry events must not resend CANCEL')
        assert(#chatInfos == 0)

        -- 6. Member leaving after closure must NOT reopen the listing
        setPartyState({}, false)
        fireEvent('GROUP_ROSTER_UPDATE')
        if tickers[1] then tickers[1]() end
        assert(group.closed == true, 'member leaving must not reopen closed listing')

        -- 7. Manual Reopen() works and allows new applications; stays open while still in same dungeon
        resetSent()
        local okReopen = finder:Reopen(group.id)
        assert(okReopen == true and not group.closed, 'manual Reopen must succeed')
        assert(countKind('UPDATE') == 1)
        fireEvent('ZONE_CHANGED_NEW_AREA')
        assert(not group.closed, 'manual reopen inside same dungeon must not be immediately re-closed')
        local apply = finder._pack({ finder.identity, group.id, 'healer', 'apply', '1700000000001', '111' })
        assert(finder:ReceiveJoin('Dave Mon', apply), 'reopened listing must accept applications')

        -- Exiting dungeon and re-entering closes it again
        resetSent()
        setInstanceState(false, 'none')
        fireEvent('PLAYER_ENTERING_WORLD')
        assert(not group.closed)
        setInstanceState(true, 'party')
        fireEvent('PLAYER_ENTERING_WORLD')
        assert(group.closed == true and countKind('CANCEL') == 1)

        -- 2. Entering dungeon with no open listings produces no errors or CANCEL
        resetSent()
        setInstanceState(false, 'none')
        fireEvent('PLAYER_ENTERING_WORLD')
        setInstanceState(true, 'party')
        fireEvent('PLAYER_ENTERING_WORLD')
        assert(countKind('CANCEL') == 0 and #chatInfos == 0 and #chatErrors == 0)
    ''')


def test_ui_reload_in_dungeon_with_saved_listings():
    # 8a. Reloading UI inside a dungeon when listing was ALREADY closed -> 0 CANCELs
    lua1 = make_runtime()
    lua1.execute('''
        local finder = OldKraken.GroupFinder
        local gfFrame = createdFrames[#createdFrames]
        assert(finder:Create('Reload test', 'dungeon', '', 5, 22, 30, 'tank', 'sfk'))
        setInstanceState(true, 'party')
        gfFrame.scripts.OnEvent(gfFrame, 'PLAYER_ENTERING_WORLD')
        for _, g in pairs(finder.groups) do if g.owner == finder.identity then assert(g.closed) end end
    ''')
    saved_db = lua1.globals().OldKraken.DB.groupFinder

    lua2 = make_runtime(saved_db=saved_db, in_inst=True, inst_type='party')
    lua2.execute('''
        local gfFrame = createdFrames[#createdFrames]
        gfFrame.scripts.OnEvent(gfFrame, 'PLAYER_ENTERING_WORLD')
        assert(#sentProtocols == 0, 'reload in dungeon with already-closed listing must send 0 CANCELs')
        assert(#chatInfos == 0 and #chatErrors == 0)
    ''')

    # 8b. Reloading UI inside a dungeon when listing was still open in SavedVariables -> closes once, no duplicate CANCEL
    lua3 = make_runtime()
    lua3.execute('''
        assert(OldKraken.GroupFinder:Create('Open before reload', 'dungeon', '', 5, 13, 18, 'healer', 'rfc'))
    ''')
    open_db = lua3.globals().OldKraken.DB.groupFinder

    lua4 = make_runtime(saved_db=open_db, in_inst=True, inst_type='party')
    lua4.execute('''
        local gfFrame = createdFrames[#createdFrames]
        gfFrame.scripts.OnEvent(gfFrame, 'PLAYER_ENTERING_WORLD')
        local cancels = 0
        for _, item in ipairs(sentProtocols) do
            if item.kind == 'CANCEL' then cancels = cancels + 1 end
        end
        assert(cancels == 1, 'reload in dungeon with open listing must cancel once, got ' .. cancels)
        for _, g in pairs(OldKraken.GroupFinder.groups) do
            if g.owner == OldKraken.GroupFinder.identity then assert(g.closed == true) end
        end
    ''')


def test_dungeon_autoclose_retry_and_max_revision():
    lua = make_runtime()
    lua.execute('''
        local finder = OldKraken.GroupFinder
        local gfFrame = createdFrames[#createdFrames]
        assert(finder:Create('First run', 'dungeon', '', 5, 17, 26, 'dps', 'deadmines'))
        assert(finder:Create('Second run', 'dungeon', '', 5, 22, 30, 'tank', 'sfk'))

        local g1, g2
        for _, g in pairs(finder.groups) do
            if g.owner == finder.identity then
                if g.dungeon == 'deadmines' then g1 = g
                elseif g.dungeon == 'sfk' then g2 = g end
            end
        end
        assert(g1 and g2)

        -- 1. Transport rejects CANCEL for g1 (e.g. queue saturated), but accepts for g2
        local failFirstCancelForG1 = true
        local origSend = OldKraken.Communication.SendProtocol
        OldKraken.Communication.SendProtocol = function(self, kind, payload)
            if kind == 'CANCEL' and failFirstCancelForG1 and payload:find(g1.id, 1, true) then
                return false
            end
            sentProtocols[#sentProtocols + 1] = { kind = kind, payload = payload }
            return true
        end

        resetSent()
        setInstanceState(true, 'party')
        gfFrame.scripts.OnEvent(gfFrame, 'PLAYER_ENTERING_WORLD')

        -- g2 must be closed immediately even though g1 failed; g1 stays open and pending retry
        assert(g2.closed == true, 'other owned listings must still close when one fails')
        assert(not g1.closed, 'failed Cancel must leave g1 open until retry succeeds')
        assert(#sentProtocols == 1 and sentProtocols[1].kind == 'CANCEL')

        local function countKind(kind)
            local n = 0
            for _, item in ipairs(sentProtocols) do
                if item.kind == kind then n = n + 1 end
            end
            return n
        end
        -- 2. Next 3s integration tick retries g1 and succeeds
        failFirstCancelForG1 = false
        resetSent()
        tickers[1]()
        assert(g1.closed == true, 'retry tick must close g1')
        assert(countKind('CANCEL') == 1, 'retry tick must send exactly 1 CANCEL')
        assert(#chatInfos == 1 and chatInfos[1]:find('автоматично закрито після входу в підземелля', 1, true))

        -- 3. Subsequent ticks must NOT emit duplicate CANCELs
        resetSent()
        tickers[1]()
        tickers[1]()
        assert(countKind('CANCEL') == 0, 'subsequent ticks must not resend CANCEL')

        -- 4. Max revision listing must stay open (NOT closed locally) and show error, while other open listing still closes
        setInstanceState(false, 'none')
        gfFrame.scripts.OnEvent(gfFrame, 'PLAYER_ENTERING_WORLD')
        assert(finder:Reopen(g1.id))
        assert(finder:Reopen(g2.id))
        g1.revision = 2147483647
        resetSent()
        setInstanceState(true, 'party')
        gfFrame.scripts.OnEvent(gfFrame, 'PLAYER_ENTERING_WORLD')
        assert(not g1.closed, 'max revision listing must remain open when sync cannot happen')
        assert(g2.closed == true, 'other open listing must still close alongside max-revision listing')
        assert(#chatErrors == 1 and chatErrors[1]:find('межі ревізії', 1, true))
        local cancels = 0
        for _, item in ipairs(sentProtocols) do if item.kind == 'CANCEL' then cancels = cancels + 1 end end
        assert(cancels == 1, 'only g2 should send CANCEL, not max-revision g1')

        OldKraken.Communication.SendProtocol = origSend
    ''')


if __name__ == '__main__':
    test_dungeon_entry_autoclose_and_lifecycle()
    test_ui_reload_in_dungeon_with_saved_listings()
    test_dungeon_autoclose_retry_and_max_revision()
    print('Group Finder dungeon auto-close checks passed')
