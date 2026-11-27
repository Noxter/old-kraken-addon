import subprocess
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
CHECKPOINTS = ['v0.4.0', 'v0.5.2', 'v0.5.4', 'v0.5.6', 'v0.5.7']
REMOVED_PROFESSIONS = (186, 182, 393, 185, 129, 356)


def read_git_file(ref, fname):
    if ref is None:
        return (ROOT / fname).read_text(encoding='utf-8')
    return subprocess.check_output(['git', 'show', f'{ref}:{fname}'], cwd=ROOT).decode('utf-8')


def make_comm_client(name, realm, ref, client_ver):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().player = name
    lua.globals().realm = realm
    lua.globals().client_ver = client_ver
    lua.execute('''
        now=1700000000; clock=100; outgoing={}; timers={}; frames={}; notices={}; choices={}
        OldKraken={version=client_ver, DB={settings={}, roster={}, events={guildCalendarV1={}}, groupFinder={}, workshop={guilds={}, recipeCatalog={}}},
            UIStyle={
                Colors={brandGold={0.88,0.69,0.32,1}},
                Button=function(b,v) b.variant=v end, Window=function() end, Dropdown=function() end, Input=function() end,
                Panel=function() end, FontPath=function() return 'Fonts\\\\FRIZQT__.TTF' end, EmblemPath=function() return '' end,
            }}
        OldKraken.listeners={}
        function OldKraken:On(n,fn) self.listeners[n]=self.listeners[n] or {}; table.insert(self.listeners[n],fn) end
        function OldKraken:Fire(n,...) notices[#notices+1]={n,...}; for _,fn in ipairs(self.listeners[n] or {}) do fn(...) end end
        function OldKraken:Print(...) end
        function OldKraken:PrintError(...) end
        function print(...) end
        function UnitName(unit) if unit=='player' or unit==nil then return player, realm end end
        function GetGuildInfo() return 'Guild' end
        function GetRealmName() return realm end
        function GetNumGuildMembers() return 2 end
        function GetGuildRosterInfo(i)
            return i==1 and 'Alice Moon' or 'Bob Other', 'Member', 0, 60, 'Warrior', 'Orgrimmar', nil, nil, true, '', 'WARRIOR'
        end
        function IsInGuild() return true end
        function GetServerTime() return now end
        function GetTime() return clock end
        function date() return '2026-11-27 10:00' end
        function GetProfessions() return 1 end
        function GetProfessionInfo() return 'Alchemy', nil, 50, 300, nil, nil, 171 end
        function GetNumTalentTabs() return 3 end
        function GetTalentTabInfo(i)
            local names={'Arms','Fury','Protection'}
            return names[i], nil, i==1 and 31 or 0, nil, nil, 132355
        end
        C_AddOns={GetAddOnMetadata=function(_,k) if k=='Version' then return client_ver end end}
        C_Timer={NewTicker=function(_,fn) timers[#timers+1]=fn end}
        C_ChatInfo={
            RegisterAddonMessagePrefix=function() return true end,
            SendAddonMessage=function(prefix,message,channel,target)
                outgoing[#outgoing+1]={prefix=prefix,message=message,channel=channel,target=target}; return 0
            end
        }
        Enum={SendAddonMessageResult={Success=0,InvalidPrefix=1,InvalidMessage=2,AddonMessageThrottle=3,InvalidChatType=4,NotInGroup=5,TargetRequired=6,InvalidChannel=7,ChannelThrottle=8,GeneralError=9,NotInGuild=10,AddOnMessageLockdown=11,TargetOffline=12}}
        function strsplit(sep, s)
            local p = {}
            local start = 1
            while true do
                local i = s:find(sep, start, true)
                if not i then p[#p+1] = s:sub(start); break end
                p[#p+1] = s:sub(start, i-1)
                start = i + #sep
            end
            return unpack(p)
        end
        local methods={}
        function methods:SetSize(w,h) self.width=w; self.height=h end
        function methods:SetScript(k,fn) self.scripts[k]=fn end
        function methods:RegisterEvent(e) self.events[e]=true end
        function methods:SetText(t) self.text=t; if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end end
        function methods:GetText() return self.text or '' end
        function methods:GetParent() return self.parent end
        function methods:Show() self.shown=true end
        function methods:Hide() self.shown=false end
        function methods:SetShown(v) self.shown=v end
        function methods:IsShown() return self.shown end
        function methods:CreateFontString() return CreateFrame() end
        function methods:CreateTexture() return CreateFrame() end
        function methods:GetFontString() return CreateFrame() end
        function methods:Enable() self.enabled=true end
        function methods:Disable() self.enabled=false end
        local meta={__index=function(_,k) return methods[k] or function() end end}
        function CreateFrame(_,name,parent)
            local f=setmetatable({scripts={},events={},parent=parent},meta)
            if name then _G[name]=f end
            frames[#frames+1]=f; return f
        end
        UIParent={}; UISpecialFrames={}; StaticPopupDialogs={}
        function UIDropDownMenu_SetWidth() end
        function UIDropDownMenu_SetText(f,text) f.text=text end
        function UIDropDownMenu_Initialize(f,fn) f.dropdown=fn end
        function UIDropDownMenu_CreateInfo() return {} end
        function UIDropDownMenu_AddButton(item,level) item.level=level or 1; choices[#choices+1]=item end
        function CloseDropDownMenus() end
    ''')
    if ref == 'v0.3.3':
        lua.execute(read_git_file(ref, 'Communication.lua'))
        lua.execute('for _,f in ipairs(frames) do if f.events.PLAYER_LOGIN and f.scripts.OnEvent then f.scripts.OnEvent(f,"PLAYER_LOGIN") end end')
        return lua

    for fname in ('Communication.lua', 'ActivityCatalog.lua', 'GroupFinder.lua', 'GroupFinderIntegration.lua', 'GuildEvents.lua', 'Workshop.lua', 'WorkshopRecipes.lua', 'WorkshopSync.lua', 'WorkshopOrders.lua'):
        lua.execute(read_git_file(ref, fname))
    lua.execute('''
        for _,f in ipairs(frames) do
            for _,ev in ipairs({'PLAYER_LOGIN','PLAYER_ENTERING_WORLD','GUILD_ROSTER_UPDATE'}) do
                if f.events[ev] then
                    if f.scripts.OnEvent then f.scripts.OnEvent(f,ev)
                    elseif f.handler then f.handler(f,ev) end
                end
            end
        end
    ''')
    return lua


def flush_comm(sender, recipients):
    sender.execute('''
        while #OldKraken.Communication.queue > 0 do
            clock = clock + 1
            OldKraken.Communication:Pump()
        end
    ''')
    outgoing = sender.globals().outgoing
    packets = [outgoing[i] for i in range(1, len(outgoing) + 1)]
    sender.execute('outgoing={}')
    sender_name = sender.globals().player + ' ' + sender.globals().realm
    for pkt in packets:
        msg, ch, tgt = pkt['message'], pkt['channel'], pkt['target']
        for recipient in recipients:
            r_name = recipient.globals().player + ' ' + recipient.globals().realm
            if ch == 'GUILD' or (ch == 'WHISPER' and tgt == r_name):
                comm = recipient.globals().OldKraken.Communication
                comm.OnAddonMessage(comm, 'OLDKRKN', msg, ch, sender_name)
    return packets


def tick_timers(lua, dt):
    lua.execute(f'clock=clock+{dt}; for _,fn in ipairs(timers) do fn() end')


def test_presence_and_spec_across_checkpoints():
    # Real bidirectional TEST^/ACK^ exchange with v0.3.3 (no version handshake)
    c_033 = make_comm_client('Legacy', 'Moon', 'v0.3.3', '0.3.3')
    c_alpha = make_comm_client('Alice', 'Moon', None, '0.5.8-alpha.2')
    c_alpha.execute("OldKraken.Communication:RequestRosterPresence()")
    flush_comm(c_alpha, [c_033])
    c_033.execute("OldKraken.Communication:SendTest()")
    pkts_033 = flush_comm(c_033, [c_alpha])
    assert any(p['message'].startswith('TEST^') for p in pkts_033)
    assert c_alpha.eval("OldKraken.Communication:HasRosterAddon('Legacy Moon')") is True
    assert c_alpha.eval("OldKraken.Communication:GetRosterVersion('Legacy Moon')") is None
    pkts_ack = flush_comm(c_alpha, [c_033])
    assert any(p['message'].startswith('ACK^') for p in pkts_ack)

    for ref in CHECKPOINTS:
        ver = '0.5.7' if ref == 'origin/main' else ref.lstrip('v')
        old_c = make_comm_client('Bob', 'Other', ref, ver)
        new_c = make_comm_client('Alice', 'Moon', None, '0.5.8-alpha.2')
        new_c.execute("OldKraken.Communication:RequestRosterPresence()")
        flush_comm(new_c, [old_c])
        flush_comm(old_c, [new_c])
        assert new_c.eval("OldKraken.Communication:HasRosterAddon('Bob Other')") is True
        assert new_c.eval("OldKraken.Communication:GetRosterVersion('Bob Other')") == ver

        old_c.execute("OldKraken.Communication:RequestRosterPresence()")
        flush_comm(old_c, [new_c])
        flush_comm(new_c, [old_c])
        assert old_c.eval("OldKraken.Communication:HasRosterAddon('Alice Moon')") is True
        assert old_c.eval("OldKraken.Communication:GetRosterVersion('Alice Moon')") == '0.5.8-alpha.2'

        # OKP^SPEC2^ wire/handler test in both directions:
        # ignored safely on <= v0.5.2 (GetRosterSpec stays nil, stats.invalid == 0), decoded both ways on v0.5.4+
        old_c.execute("OldKraken.Communication:OnAddonMessage('OLDKRKN','OKP^SPEC2^1^132355^31/0/0^Arms','GUILD','Alice Moon')")
        new_c.execute("OldKraken.Communication:OnAddonMessage('OLDKRKN','OKP^SPEC2^1^132355^0/0/31^Protection','GUILD','Bob Other')")
        assert new_c.eval("OldKraken.Communication:GetRosterSpec('Bob Other').name") == 'Protection'
        if ref in ('v0.4.0', 'v0.5.2'):
            assert old_c.eval("OldKraken.Communication.stats.invalid") == 0
        else:
            assert old_c.eval("OldKraken.Communication:GetRosterSpec('Alice Moon').name") == 'Arms'

    # Also verify alpha <-> alpha SPEC2 decoding
    a1 = make_comm_client('Alice', 'Moon', None, '0.5.8-alpha.2')
    a2 = make_comm_client('Bob', 'Other', None, '0.5.8-alpha.2')
    a1.execute("OldKraken.Communication:OnAddonMessage('OLDKRKN','OKP^SPEC2^1^132355^0/0/31^Protection','GUILD','Bob Other')")
    a2.execute("OldKraken.Communication:OnAddonMessage('OLDKRKN','OKP^SPEC2^1^132355^31/0/0^Arms','GUILD','Alice Moon')")
    assert a1.eval("OldKraken.Communication:GetRosterSpec('Bob Other').name") == 'Protection'
    assert a2.eval("OldKraken.Communication:GetRosterSpec('Alice Moon').name") == 'Arms'


def test_group_finder_and_guild_events_bidirectional():
    for ref in CHECKPOINTS:
        ver = '0.5.7' if ref == 'origin/main' else ref.lstrip('v')
        old_c = make_comm_client('Bob', 'Other', ref, ver)
        new_c = make_comm_client('Alice', 'Moon', None, '0.5.8-alpha.2')

        # GroupFinder: new -> old ANNOUNCE, old -> new JOIN
        new_c.execute("assert(OldKraken.GroupFinder:Create('TestGF','dungeon','',5,1,60,'tank')); OldKraken.GroupFinder:Changed()")
        flush_comm(new_c, [old_c])
        old_c.execute("""
            local found
            for _, g in pairs(OldKraken.GroupFinder.groups) do if g.title=='TestGF' then found=g end end
            assert(found, 'old client did not receive GroupFinder ANNOUNCE')
            assert(OldKraken.GroupFinder:Apply(found.owner, found.id, 'healer'))
        """)
        flush_comm(old_c, [new_c])
        assert new_c.eval("next(OldKraken.GroupFinder.requests) ~= nil") is True

        # GroupFinder: old -> new ANNOUNCE
        old_c.execute("assert(OldKraken.GroupFinder:Create('OldGF','quest','',5,1,60,'dps')); OldKraken.GroupFinder:Changed()")
        flush_comm(old_c, [new_c])
        assert new_c.eval("""
            (function()
                for _, g in pairs(OldKraken.GroupFinder.groups) do if g.title=='OldGF' then return true end end
                return false
            end)()
        """) is True

        # GuildEvents: new -> old CEVENT, old -> new CEVRSVP, old -> new CEVENT
        new_c.execute("assert(OldKraken.GuildEvents:Create('RaidNight','desc',now+7200,'guild',40,''))")
        tick_timers(new_c, 10)
        flush_comm(new_c, [old_c])
        old_c.execute("""
            local key
            local store = OldKraken.DB.events.guildCalendarV1['Other\\001Guild\\001Bob Other']
            for k, e in pairs(store.observed) do if e.title=='RaidNight' then key=k end end
            assert(key, 'old client did not receive GuildEvents CEVENT')
            assert(OldKraken.GuildEvents:Signup(key, 'flex'))
        """)
        tick_timers(old_c, 10)
        flush_comm(old_c, [new_c])
        assert new_c.eval("""
            (function()
                local store = OldKraken.DB.events.guildCalendarV1['Moon\\001Guild\\001Alice Moon']
                for _, e in pairs(store.owned) do
                    if e.title=='RaidNight' and e.people['Bob Other']=='flex' then return true end
                end
                return false
            end)()
        """) is True

        old_c.execute("assert(OldKraken.GuildEvents:Create('OldEvent','desc',now+10800,'guild',5,''))")
        tick_timers(old_c, 10)
        flush_comm(old_c, [new_c])
        assert new_c.eval("""
            (function()
                local store = OldKraken.DB.events.guildCalendarV1['Moon\\001Guild\\001Alice Moon']
                for _, e in pairs(store.observed) do if e.title=='OldEvent' then return true end end
                return false
            end)()
        """) is True


def test_wrq_cadence_across_checkpoints():
    for ref in list(CHECKPOINTS) + [None]:
        ver = '0.5.8-alpha.2' if ref is None else ('0.5.7' if ref == 'origin/main' else ref.lstrip('v'))
        c = make_comm_client('Bob', 'Other', ref, ver)

        # Initial tick (nextQuery starts at 0) emits WRQ
        tick_timers(c, 0)
        pkts0 = flush_comm(c, [])
        assert any(p['message'].startswith('GF2^WRQ^') for p in pkts0), f'{ver}: expected initial WRQ'

        # At +165s (< 180s), no checkpoint emits WRQ
        tick_timers(c, 165)
        pkts165 = flush_comm(c, [])
        assert not any(p['message'].startswith('GF2^WRQ^') for p in pkts165), f'{ver}: unexpected WRQ at +165s'

        # At +185s (total >= 180s since initial WRQ): v0.4.0..v0.5.6 emit WRQ, v0.5.7+ do not
        tick_timers(c, 20)
        pkts185 = flush_comm(c, [])
        has_wrq_185 = any(p['message'].startswith('GF2^WRQ^') for p in pkts185)
        if ref in ('v0.4.0', 'v0.5.2', 'v0.5.4', 'v0.5.6'):
            assert has_wrq_185, f'{ver}: expected WRQ at +185s (180s cadence)'
        else:
            assert not has_wrq_185, f'{ver}: unexpected WRQ at +185s (600s cadence)'

            # At +585s (still < 600s): v0.5.7+ still do not emit WRQ
            tick_timers(c, 400)
            pkts585 = flush_comm(c, [])
            assert not any(p['message'].startswith('GF2^WRQ^') for p in pkts585), f'{ver}: unexpected WRQ at +585s'

            # At +605s (> 600s): v0.5.7+ emit WRQ
            tick_timers(c, 20)
            pkts605 = flush_comm(c, [])
            assert any(p['message'].startswith('GF2^WRQ^') for p in pkts605), f'{ver}: expected WRQ at +605s'


def test_workshop_recipes_and_sync_bidirectional():
    for ref in CHECKPOINTS:
        ver = '0.5.7' if ref == 'origin/main' else ref.lstrip('v')
        old_c = make_comm_client('Bob', 'Other', ref, ver)
        new_c = make_comm_client('Alice', 'Moon', None, '0.5.8-alpha.2')

        # Presence exchange first so new_c knows old_c's version
        new_c.execute("OldKraken.Communication:RequestRosterPresence()")
        flush_comm(new_c, [old_c]); flush_comm(old_c, [new_c])

        # Seed Alchemy 9101 on new_c and Alchemy 9201 on old_c
        new_c.execute("""
            local s = OldKraken.DB.workshop.guilds['Moon\\001Guild']
            s.recipes['Alice Moon'] = {[9101]={recipe=9101, item=2101, profession=171, seen=now, name='Flask A', product='Flask A'}}
        """)
        old_c.execute("""
            local s = OldKraken.DB.workshop.guilds['Other\\001Guild']
            s.recipes['Bob Other'] = {[9201]={recipe=9201, item=2201, profession=171, seen=now, name='Potion B', product='Potion B'}}
        """)

        # WRLEARN wire/handler test (payload built via GroupFinder._pack, not WorkshopRecipes scanner/encoder):
        # new -> old accepts Alchemy 9101; old -> new accepts Alchemy 9201 and rejects all 6 removed professions
        new_c.execute("assert(OldKraken.Communication:SendProtocol('WRLEARN', OldKraken.GroupFinder._pack({9101, 2101, 171, now, 'Flask A', 'Flask A'})))")
        flush_comm(new_c, [old_c])
        assert old_c.eval("OldKraken.DB.workshop.guilds['Other\\001Guild'].recipes['Alice Moon'] ~= nil and OldKraken.DB.workshop.guilds['Other\\001Guild'].recipes['Alice Moon'][9101] ~= nil") is True

        old_c.execute("assert(OldKraken.Communication:SendProtocol('WRLEARN', OldKraken.GroupFinder._pack({9201, 2201, 171, now, 'Potion B', 'Potion B'})))")
        for idx, prof_id in enumerate(REMOVED_PROFESSIONS):
            rid = 9300 + idx
            old_c.execute(f"assert(OldKraken.Communication:SendProtocol('WRLEARN', OldKraken.GroupFinder._pack({{{rid}, {2300+idx}, {prof_id}, now, 'Removed {prof_id}', 'Removed {prof_id}'}})))")
        flush_comm(old_c, [new_c])
        assert new_c.eval("OldKraken.DB.workshop.guilds['Moon\\001Guild'].recipes['Bob Other'][9201] ~= nil") is True
        for idx in range(len(REMOVED_PROFESSIONS)):
            assert new_c.eval(f"OldKraken.DB.workshop.guilds['Moon\\001Guild'].recipes['Bob Other'][{9300+idx}] == nil") is True

        # Clear old_c's cached Alice Moon recipe, then run full WorkshopSync cycle:
        # WRQ -> WRIDX (verify owner/target/count) -> WRGET (verify GUILD & target) -> WRPAGE (verify GUILD & import into old_c)
        old_c.execute("OldKraken.DB.workshop.guilds['Other\\001Guild'].recipes['Alice Moon'] = nil")
        tick_timers(old_c, 700)
        wrq_pkts = flush_comm(old_c, [new_c])
        assert any(p['message'].startswith('GF2^WRQ^') for p in wrq_pkts)

        tick_timers(new_c, 10)
        idx_pkts = flush_comm(new_c, [old_c])
        idx_hex = next((p['message'].split('^')[-1] for p in idx_pkts if p['message'].startswith('GF2^WRIDX^')), None)
        assert idx_hex is not None
        idx_raw = bytes.fromhex(idx_hex).decode('utf-8')
        assert new_c.eval(f"OldKraken.GroupFinder._unpackFields({idx_raw!r}, 4)[1] == 'Bob Other'") is True
        assert new_c.eval(f"OldKraken.GroupFinder._unpackFields({idx_raw!r}, 4)[2] == 'Alice Moon'") is True
        assert new_c.eval(f"OldKraken.GroupFinder._unpackFields({idx_raw!r}, 4)[4] == '1'") is True

        tick_timers(old_c, 10)
        get_pkts = flush_comm(old_c, [new_c])
        get_hex = next((p['message'].split('^')[-1] for p in get_pkts if p['message'].startswith('GF2^WRGET^') and p['channel'] == 'GUILD'), None)
        assert get_hex is not None
        get_raw = bytes.fromhex(get_hex).decode('utf-8')
        assert new_c.eval(f"OldKraken.GroupFinder._unpackFields({get_raw!r}, 3)[1] == 'Alice Moon'") is True
        assert new_c.eval(f"OldKraken.GroupFinder._unpackFields({get_raw!r}, 3)[2] == 'Alice Moon'") is True

        tick_timers(new_c, 10)
        page_pkts = flush_comm(new_c, [old_c])
        assert any(p['message'].startswith('GF2^WRPAGE^') and p['channel'] == 'GUILD' for p in page_pkts)
        assert old_c.eval("OldKraken.DB.workshop.guilds['Other\\001Guild'].recipes['Alice Moon'] ~= nil and OldKraken.DB.workshop.guilds['Other\\001Guild'].recipes['Alice Moon'][9101].name == 'Flask A'") is True


def test_alpha_whisper_sync():
    a1 = make_comm_client('Alice', 'Moon', None, '0.5.8-alpha.2')
    a2 = make_comm_client('Bob', 'Other', None, '0.5.8-alpha.2')
    a1.execute("OldKraken.Communication:RequestRosterPresence()")
    flush_comm(a1, [a2]); flush_comm(a2, [a1])
    a2.execute("OldKraken.Communication:RequestRosterPresence()")
    flush_comm(a2, [a1]); flush_comm(a1, [a2])

    a1.execute("""
        local s = OldKraken.DB.workshop.guilds['Moon\\001Guild']
        s.recipes['Alice Moon'] = {[9501]={recipe=9501, item=2501, profession=171, seen=now, name='Alpha Flask', product='Alpha Flask'}}
    """)
    tick_timers(a2, 700)
    wrq_pkts = flush_comm(a2, [a1])
    assert any(p['message'].startswith('GF2^WRQ^') and p['channel'] == 'GUILD' for p in wrq_pkts)

    tick_timers(a1, 10)
    idx_pkts = flush_comm(a1, [a2])
    assert any(p['message'].startswith('GF2^WRIDX^') and p['channel'] == 'GUILD' for p in idx_pkts)

    tick_timers(a2, 10)
    get_pkts = flush_comm(a2, [a1])
    assert any(p['message'].startswith('GF2^WRGET^') and p['channel'] == 'WHISPER' and p['target'] == 'Alice Moon' for p in get_pkts)

    tick_timers(a1, 10)
    page_pkts = flush_comm(a1, [a2])
    assert any(p['message'].startswith('GF2^WRPAGE^') and p['channel'] == 'WHISPER' and p['target'] == 'Bob Other' for p in page_pkts)
    assert a2.eval("OldKraken.DB.workshop.guilds['Other\\001Guild'].recipes['Alice Moon'] ~= nil and OldKraken.DB.workshop.guilds['Other\\001Guild'].recipes['Alice Moon'][9501].name == 'Alpha Flask'") is True


if __name__ == '__main__':
    test_presence_and_spec_across_checkpoints()
    test_group_finder_and_guild_events_bidirectional()
    test_wrq_cadence_across_checkpoints()
    test_workshop_recipes_and_sync_bidirectional()
    test_alpha_whisper_sync()
    print('Protocol compatibility matrix checks passed')
