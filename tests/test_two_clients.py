from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
sources = [(root / name).read_text(encoding='utf-8') for name in
           ['Communication.lua', 'GroupFinder.lua', 'GroupFinderIntegration.lua']]


def client(name, realm):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().player = name
    lua.globals().realm = realm
    lua.execute('''
        OldKraken={DB={groupFinder={}}}; frames={}; timers={}; outgoing={}
        function OldKraken:Fire(...) end
        function print(...) end
        function UnitName() return player, realm end
        function GetGuildInfo() return 'Guild' end
        function GetRealmName() return realm end
        function GetNumGuildMembers() return 2 end
        function GetGuildRosterInfo(i) return i==1 and 'Alice Moon' or 'Bob Other Realm','Member',0,60,'Class','Zone',nil,nil,true,'',i==1 and 'WARRIOR' or 'PALADIN' end
        function IsInGuild() return true end
        function GetServerTime() return 1700000000 end
        clock=100; function GetTime() return clock end
        function CreateFrame()
            local f={events={}}
            function f:RegisterEvent(event) self.events[event]=true end
            function f:SetScript(_, fn) self.handler=fn end
            frames[#frames+1]=f; return f
        end
        C_Timer={NewTicker=function(_, fn) timers[#timers+1]=fn end}
        C_ChatInfo={RegisterAddonMessagePrefix=function() return true end,
            SendAddonMessage=function(prefix,message,channel,target)
                outgoing[#outgoing+1]={message=message,channel=channel,target=target}; return 0
            end}
        Enum={SendAddonMessageResult={Success=0,InvalidPrefix=1,InvalidMessage=2,AddonMessageThrottle=3,InvalidChatType=4,NotInGroup=5,TargetRequired=6,InvalidChannel=7,ChannelThrottle=8,GeneralError=9,NotInGuild=10,AddOnMessageLockdown=11,TargetOffline=12}}
        function strsplit(_, s) return s:match('^([^%^]*)%^([^%^]*)%^([^%^]*)%^([^%^]*)$') end
    ''')
    for source in sources:
        lua.execute(source)
    lua.execute('for _,f in ipairs(frames) do if f.events.PLAYER_LOGIN then f.handler(f,"PLAYER_LOGIN") end end')
    return lua


alice, bob = client('Alice', 'Moon'), client('Bob', 'Other Realm')


def flush(sender, recipients):
    sender.execute('while #OldKraken.Communication.queue > 0 do clock=clock+1; OldKraken.Communication:Pump() end')
    outgoing = sender.globals().outgoing
    packets = [outgoing[i] for i in range(1, len(outgoing) + 1)]
    sender.execute('outgoing={}')
    sender_name = sender.globals().player + ' ' + sender.globals().realm
    for pkt in packets:
        msg, ch, tgt = pkt['message'], pkt['channel'], pkt['target']
        for recipient in recipients:
            r_name = recipient.globals().player + ' ' + recipient.globals().realm
            if ch == 'GUILD' or (ch == 'WHISPER' and tgt == r_name):
                recipient.globals().OldKraken.Communication.OnAddonMessage(
                    recipient.globals().OldKraken.Communication, 'OLDKRKN', msg, ch, sender_name)
    return packets


def reload(client):
    client.execute('savedDB = OldKraken.DB; OldKraken = {DB=savedDB}; frames={}; timers={}; outgoing={}; function OldKraken:Fire(...) end')
    for source in sources:
        client.execute(source)
    client.execute('for _,f in ipairs(frames) do if f.events.PLAYER_LOGIN then f.handler(f,"PLAYER_LOGIN") end end')


alice.execute("assert(OldKraken.GroupFinder:Create('Підземелля','dungeon','Тест',5,1,60,'tank')); OldKraken.GroupFinder:Changed()")
flush(alice, [])  # Simulate a lost initial announcement.
bob.execute('assert(OldKraken.Communication:RequestSync())')
flush(bob, [alice])
alice.execute('OldKraken.GroupFinder:SyncStep()')
flush(alice, [bob])
bob.execute('''
    group = nil; for _, value in pairs(OldKraken.GroupFinder.groups) do group=value end
    assert(group and group.title == 'Підземелля')
    assert(OldKraken.GroupFinder:Apply(group.owner, group.id, 'healer'))
''')
flush(bob, [alice])
alice.execute('''
    group = nil; for _, value in pairs(OldKraken.GroupFinder.groups) do group=value end
    assert(OldKraken.GroupFinder.requests[group.id]['Bob Other Realm'] == 'healer')
    assert(OldKraken.GroupFinder:Decide(group.id, 'Bob Other Realm', true))
''')
flush(alice, [bob])
bob.execute("assert(OldKraken.GroupFinder.pending['Alice Moon'..'\\001'..group.id] == nil)")
reload(bob)
bob.execute("assert(OldKraken.GroupFinder.pending['Alice Moon'..'\\001'..group.id] == nil)")
alice.execute('assert(OldKraken.GroupFinder:Cancel(group.id))')
flush(alice, [bob])
bob.execute("assert(OldKraken.GroupFinder.groups['Alice Moon'..'\\001'..group.id].closed)")

# Reject while the applicant is offline, drop the response, restart both peers,
# and recover the versioned decision through a new synchronization request.
alice.execute("assert(OldKraken.GroupFinder:Create('Second','quest','',5,1,60,'dps')); OldKraken.GroupFinder:Changed()")
flush(alice, [bob])
bob.execute('''
  for _, g in pairs(OldKraken.GroupFinder.groups) do if g.title=='Second' then second=g end end
  assert(second and OldKraken.GroupFinder:Apply(second.owner, second.id, 'dps'))
  OldKraken.GroupFinder:Changed()
''')
flush(bob, [alice])
alice.execute('''
  for _, g in pairs(OldKraken.GroupFinder.groups) do if g.title=='Second' then second=g end end
  assert(OldKraken.GroupFinder:Decide(second.id, 'Bob Other Realm', false)); OldKraken.GroupFinder:Changed()
  assert(OldKraken.GroupFinder:SyncStep())
''')
flush(alice, [])
reload(alice)
reload(bob)
bob.execute('assert(OldKraken.Communication:RequestSync())')
flush(bob, [alice])
alice.execute('''
  local f=OldKraken.GroupFinder
  while next(f.syncPending) or next(f.decisionSync) do assert(f:SyncStep()) end
''')
flush(alice, [bob])
bob.execute('''
  local found=false
  for key, state in pairs(OldKraken.GroupFinder.pending) do
    if state == 'reject' then found=true end
  end
  assert(found)
''')
# A repeated old rejection cannot reject a newer application. A dropped JOIN
# can be retried with the same version and is accepted only once by the owner.
bob.execute('''
  for _, g in pairs(OldKraken.GroupFinder.groups) do if g.title=='Second' then second=g end end
  assert(OldKraken.GroupFinder:Apply(second.owner, second.id, 'tank'))
  OldKraken.GroupFinder:Changed()
''')
flush(bob, [])
alice.execute('''
  for _, g in pairs(OldKraken.GroupFinder.groups) do if g.title=='Second' then second=g end end
  OldKraken.GroupFinder:OnQuery()
  while next(OldKraken.GroupFinder.syncPending) or next(OldKraken.GroupFinder.decisionSync) do
    assert(OldKraken.GroupFinder:SyncStep())
  end
''')
flush(alice, [bob])
bob.execute('''
  local f=OldKraken.GroupFinder
  assert(f.pending['Alice Moon'..'\\001'..second.id] == 'pending')
  while not f:RetryPending() do end
''')
flush(bob, [alice])
alice.execute("assert(OldKraken.GroupFinder.requests[second.id]['Bob Other Realm'] == 'tank')")

# Stage 2: WHISPER routing for WRGET / WRPAGE with GUILD fallback for old/unknown clients
def load_sync_client(name, realm, version):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().player = name
    lua.globals().realm = realm
    lua.globals().client_ver = version
    lua.execute('''
        OldKraken={DB={workshop={guilds={}}},WorkshopRecipes={},listeners={}}
        function OldKraken:On(n,fn) self.listeners[n]=self.listeners[n] or {}; table.insert(self.listeners[n],fn) end
        function OldKraken:Fire(n,...) for _,fn in ipairs(self.listeners[n] or {}) do fn(...) end end
        frames={}; timers={}; outgoing={}; imported={}; local_records={}
        function print(...) end
        function UnitName() return player, realm end
        function GetGuildInfo() return guild_name or 'Guild' end
        function GetRealmName() return realm end
        function GetServerTime() return 1700000000 end
        clock=100; function GetTime() return clock end
        function IsInGuild() return true end
        function CreateFrame()
            local f={events={}}
            function f:RegisterEvent(event) self.events[event]=true end
            function f:SetScript(_, fn) self.handler=fn end
            frames[#frames+1]=f; return f
        end
        C_AddOns={GetAddOnMetadata=function(_, key) if key=='Version' then return client_ver end end}
        C_Timer={NewTicker=function(_, fn) timers[#timers+1]=fn end}
        send_mode = nil
        C_ChatInfo={RegisterAddonMessagePrefix=function() return true end,
            SendAddonMessage=function(prefix,message,channel,target)
                if send_mode == 'throttle_once' then send_mode = nil; return 3 end
                if send_mode == 'channel_throttle_once' then send_mode = nil; return 8 end
                if send_mode == 'target_offline' then return 12 end
                if send_mode == 'drop_next_only' then send_mode = nil; return 12 end
                outgoing[#outgoing+1]={message=message,channel=channel,target=target}; return 0
            end}
        Enum={SendAddonMessageResult={Success=0,InvalidPrefix=1,InvalidMessage=2,AddonMessageThrottle=3,InvalidChatType=4,NotInGroup=5,TargetRequired=6,InvalidChannel=7,ChannelThrottle=8,GeneralError=9,NotInGuild=10,AddOnMessageLockdown=11,TargetOffline=12}}
        function strsplit(_, s) return s:match('^([^%^]*)%^([^%^]*)%^([^%^]*)%^([^%^]*)$') end
        function OldKraken.WorkshopRecipes:ExportSnapshot() return 1, local_records end
        function OldKraken.WorkshopRecipes:ValidateSnapshotRecord(r) return type(r)=='table' and type(r.recipe)=='number' end
        function OldKraken.WorkshopRecipes:ImportSnapshot(owner, recs) imported[owner]=recs; return true end
    ''')
    for fname in ('Communication.lua', 'GroupFinder.lua', 'WorkshopSync.lua'):
        lua.execute((root / fname).read_text(encoding='utf-8'))
    lua.execute('for _,f in ipairs(frames) do if f.events.PLAYER_LOGIN then f.handler(f,"PLAYER_LOGIN") end end')
    return lua

s_alice = load_sync_client('Alice', 'Moon', '0.5.8-alpha.2')
s_bob = load_sync_client('Bob', 'Other Realm', '0.5.8-alpha.2')
s_carol = load_sync_client('Carol', 'Old', '0.5.7')
s_obs = load_sync_client('Observer', 'Three', '0.5.8-alpha.2')

s_alice.execute("local_records={{recipe=101,item=201,profession=171,seen=1700000000,name='Flask',product='Flask'}}")
# Presence exchange so Alice and Bob know each other's 0.5.8-alpha.2, and Carol is 0.5.7
for peer in (s_alice, s_bob, s_carol):
    peer.execute("OldKraken.Communication:OnAddonMessage('OLDKRKN','OKP^QUERY','GUILD','Observer Three')")
flush(s_alice, [s_bob, s_carol, s_obs])
flush(s_bob, [s_alice, s_carol, s_obs])
flush(s_carol, [s_alice, s_bob, s_obs])

# 1. New <-> New: WRGET and WRPAGE use WHISPER; Observer receives 0 WRGET/WRPAGE fragments
s_bob.execute("clock=clock+10; timers[1]()")  # WRQ (GUILD)
wrq_pkts = flush(s_bob, [s_alice, s_obs])
assert all(p['channel'] == 'GUILD' for p in wrq_pkts)
s_alice.execute("clock=clock+10; timers[1]()")  # WRIDX (GUILD)
wridx_pkts = flush(s_alice, [s_bob, s_obs])
assert all(p['channel'] == 'GUILD' for p in wridx_pkts)
s_bob.execute("clock=clock+10; timers[1]()")  # WRGET -> WHISPER Alice Moon
bob_pkts = flush(s_bob, [s_alice, s_obs])
wrget_pkts = [p for p in bob_pkts if p['message'].startswith('GF2^WRGET^')]
assert len(wrget_pkts) == 1 and wrget_pkts[0]['channel'] == 'WHISPER' and wrget_pkts[0]['target'] == 'Alice Moon'
s_alice.execute("clock=clock+10; timers[1]()")  # WRPAGE -> WHISPER Bob Other Realm
alice_pkts = flush(s_alice, [s_bob, s_obs])
wrpage_pkts = [p for p in alice_pkts if p['message'].startswith('GF2^WRPAGE^')]
assert len(wrpage_pkts) >= 1 and all(p['channel'] == 'WHISPER' and p['target'] == 'Bob Other Realm' for p in wrpage_pkts)
assert s_bob.eval("imported['Alice Moon'] ~= nil and #imported['Alice Moon'] == 1")
assert s_obs.eval("OldKraken.Communication.stats.received") == 0 or not s_obs.eval("imported['Alice Moon'] ~= nil")
# Verify Observer never received any WRGET or WRPAGE traffic at all
assert (s_obs.eval("OldKraken.Communication.traffic.byKind.WRGET and OldKraken.Communication.traffic.byKind.WRGET.rxFrags or 0") == 0)
assert (s_obs.eval("OldKraken.Communication.traffic.byKind.WRPAGE and OldKraken.Communication.traffic.byKind.WRPAGE.rxFrags or 0") == 0)

# 2. New <-> Old (0.5.7), Unknown version, and Self ('Alice Moon') -> GUILD
s_alice.execute("assert(OldKraken.Communication:SendProtocol('WRGET', 'payload-old', 'Carol Old'))")
old_pkts = flush(s_alice, [s_carol])
assert len(old_pkts) == 1 and old_pkts[0]['channel'] == 'GUILD' and old_pkts[0]['target'] is None
s_alice.execute("assert(OldKraken.Communication:SendProtocol('WRGET', 'payload-unk', 'Unknown Player'))")
unk_pkts = flush(s_alice, [])
assert len(unk_pkts) == 1 and unk_pkts[0]['channel'] == 'GUILD' and unk_pkts[0]['target'] is None
s_alice.execute("assert(OldKraken.Communication:SendProtocol('WRGET', 'payload-self', 'Alice Moon'))")
self_pkts = flush(s_alice, [])
assert len(self_pkts) == 1 and self_pkts[0]['channel'] == 'GUILD' and self_pkts[0]['target'] is None

# 3. TargetOffline (12) drops WHISPER immediately without GUILD fallback
s_alice.execute("""
    send_mode = 'target_offline'
    assert(OldKraken.Communication:SendProtocol('WRPAGE', 'off-page', 'Bob Other Realm'))
    clock = clock + 1; OldKraken.Communication:Pump()
    assert(#OldKraken.Communication.queue == 0)
    assert(#outgoing == 0)
    send_mode = nil
""")

# 4. Throttle (3 / 8) defers and retries on the SAME WHISPER channel and target
s_alice.execute("""
    send_mode = 'throttle_once'
    assert(OldKraken.Communication:SendProtocol('WRPAGE', 'thr-page', 'Bob Other Realm'))
    clock = clock + 1; OldKraken.Communication:Pump()
    assert(#OldKraken.Communication.queue == 1 and #outgoing == 0)
    clock = clock + 10; OldKraken.Communication:Pump()
    assert(#OldKraken.Communication.queue == 0 and #outgoing == 1)
    assert(outgoing[1].channel == 'WHISPER' and outgoing[1].target == 'Bob Other Realm')
    outgoing = {}
""")

# 5. Mixed channels (WHISPER + GUILD) deduplicate identical GF2 message ID
s_bob.execute("""
    local before = OldKraken.Communication.stats.received
    OldKraken.Communication:OnAddonMessage('OLDKRKN', 'GF2^WRPAGE^1700000000-999999-1^1^1^504159', 'WHISPER', 'Alice Moon')
    local mid = OldKraken.Communication.stats.received
    OldKraken.Communication:OnAddonMessage('OLDKRKN', 'GF2^WRPAGE^1700000000-999999-1^1^1^504159', 'GUILD', 'Alice Moon')
    assert(mid == before + 1 and OldKraken.Communication.stats.received == mid)
""")

# 6. 90-second multipart replay preserves WHISPER channel and target
s_alice.execute("""
    local big = string.rep('A', 200)
    assert(OldKraken.Communication:SendProtocol('WRPAGE', big, 'Bob Other Realm'))
    assert(#OldKraken.Communication.queue == 3)
    clock = clock + 1; OldKraken.Communication:Pump()  -- sends part 1
    assert(#OldKraken.Communication.queue == 2 and #outgoing == 1)
    assert(outgoing[1].channel == 'WHISPER' and outgoing[1].target == 'Bob Other Realm')
    outgoing = {}
    clock = clock + 95; OldKraken.Communication:Pump()  -- triggers 90s replay
    assert(#OldKraken.Communication.queue == 3)
    for _, e in ipairs(OldKraken.Communication.queue) do
        assert(e.channel == 'WHISPER' and e.target == 'Bob Other Realm')
    end
    while #OldKraken.Communication.queue > 0 do clock = clock + 1; OldKraken.Communication:Pump() end
    outgoing = {}
""")

# 7. Guild change drops queued WHISPER GF2 jobs
s_alice.execute("""
    assert(OldKraken.Communication:SendProtocol('WRPAGE', 'guild-drop', 'Bob Other Realm'))
    assert(#OldKraken.Communication.queue == 1 and OldKraken.Communication.queue[1].channel == 'WHISPER')
    guild_name = 'OtherGuild'
    clock = clock + 1; OldKraken.Communication:Pump()
    assert(#OldKraken.Communication.queue == 0 and #outgoing == 0)
    guild_name = 'Guild'
""")

# 8. WHISPER sender validation: reject unknown/stale-guild/invalid, accept confirmed GUILD presence
s_alice.execute("""
    -- Re-establish Bob's GUILD presence after test #7's guild switch
    OldKraken.Communication:OnAddonMessage('OLDKRKN', 'OKP^HERE^0.5.8-alpha.2', 'GUILD', 'Bob Other Realm')
    assert(OldKraken.Communication:HasRosterAddon('Bob Other Realm'))
    local wrgetPayload = OldKraken.GroupFinder._pack({'Alice Moon', 'Alice Moon', '1'})
    local hex = wrgetPayload:gsub('.', function(c) return string.format('%02X', string.byte(c)) end)

    -- 8a. Unknown sender is rejected before RecordRosterPresence and triggers no WRPAGE
    local beforeRx = OldKraken.Communication.stats.received
    local beforeFrags = (OldKraken.Communication.traffic.byKind.WRGET and OldKraken.Communication.traffic.byKind.WRGET.rxFrags) or 0
    OldKraken.Communication:OnAddonMessage('OLDKRKN', 'GF2^WRGET^1700000000-888888-1^1^1^' .. hex, 'WHISPER', 'Stranger Other')
    assert(not OldKraken.Communication:HasRosterAddon('Stranger Other'))
    assert(OldKraken.Communication.stats.received == beforeRx)
    local afterFrags = (OldKraken.Communication.traffic.byKind.WRGET and OldKraken.Communication.traffic.byKind.WRGET.rxFrags) or 0
    assert(afterFrags == beforeFrags)
    clock = clock + 10; timers[1]()
    while #OldKraken.Communication.queue > 0 do clock = clock + 1; OldKraken.Communication:Pump() end
    for _, p in ipairs(outgoing) do assert(not p.message:match('^GF2%^WRPAGE%^')) end
    outgoing = {}

    -- 8b. Known sender with confirmed GUILD presence is accepted and receives WHISPER WRPAGE
    beforeRx = OldKraken.Communication.stats.received
    OldKraken.Communication:OnAddonMessage('OLDKRKN', 'GF2^WRGET^1700000000-888890-1^1^1^' .. hex, 'WHISPER', 'Bob Other Realm')
    assert(OldKraken.Communication.stats.received == beforeRx + 1)
    clock = clock + 10; timers[1]()
    while #OldKraken.Communication.queue > 0 do clock = clock + 1; OldKraken.Communication:Pump() end
    local sentWrpage = false
    for _, p in ipairs(outgoing) do
        if p.message:match('^GF2%^WRPAGE%^') then
            assert(p.channel == 'WHISPER' and p.target == 'Bob Other Realm')
            sentWrpage = true
        end
    end
    assert(sentWrpage)
    outgoing = {}

    -- 8c. Guild change clears presence; stale sender is rejected on WHISPER until re-seen on GUILD
    guild_name = 'OtherGuild'
    assert(not OldKraken.Communication:HasRosterAddon('Bob Other Realm'))
    guild_name = 'Guild'
    beforeRx = OldKraken.Communication.stats.received
    OldKraken.Communication:OnAddonMessage('OLDKRKN', 'GF2^WRGET^1700000000-888891-1^1^1^' .. hex, 'WHISPER', 'Bob Other Realm')
    assert(OldKraken.Communication.stats.received == beforeRx)

    -- 8d. Invalid/empty/oversized sender names and self without guild are rejected
    OldKraken.Communication:OnAddonMessage('OLDKRKN', 'GF2^WRGET^1700000000-888892-1^1^1^' .. hex, 'WHISPER', '')
    OldKraken.Communication:OnAddonMessage('OLDKRKN', 'GF2^WRGET^1700000000-888893-1^1^1^' .. hex, 'WHISPER', string.rep('A', 129))
    OldKraken.Communication:OnAddonMessage('OLDKRKN', 'GF2^WRGET^1700000000-888894-1^1^1^' .. hex, 'WHISPER', 123)
    guild_name = ''
    OldKraken.Communication:OnAddonMessage('OLDKRKN', 'GF2^WRGET^1700000000-888895-1^1^1^' .. hex, 'WHISPER', 'Alice Moon')
    guild_name = 'Guild'
    assert(OldKraken.Communication.stats.received == beforeRx)

    -- 8e. GUILD messages continue to work and record presence
    OldKraken.Communication:OnAddonMessage('OLDKRKN', 'OKP^HERE^0.5.8-alpha.2', 'GUILD', 'Bob Other Realm')
    assert(OldKraken.Communication:HasRosterAddon('Bob Other Realm'))
    OldKraken.Communication:OnAddonMessage('OLDKRKN', 'GF2^WRGET^1700000000-888896-1^1^1^' .. hex, 'WHISPER', 'Bob Other Realm')
    assert(OldKraken.Communication.stats.received == beforeRx + 1)
    outgoing = {}

    -- 8f. PruneRosterPresence invalidates a member who left the guild and blocks subsequent WHISPER
    assert(OldKraken.Communication:PruneRosterPresence({{name = 'Alice Moon'}}))
    assert(not OldKraken.Communication:HasRosterAddon('Bob Other Realm'))
    beforeRx = OldKraken.Communication.stats.received
    OldKraken.Communication:OnAddonMessage('OLDKRKN', 'GF2^WRGET^1700000000-888897-1^1^1^' .. hex, 'WHISPER', 'Bob Other Realm')
    assert(OldKraken.Communication.stats.received == beforeRx)
""")
s_bob.execute("""
    local beforeRx = OldKraken.Communication.stats.received
    OldKraken.Communication:OnAddonMessage('OLDKRKN', 'GF2^WRPAGE^1700000000-888889-1^1^1^504159', 'WHISPER', 'Stranger Other')
    assert(not OldKraken.Communication:HasRosterAddon('Stranger Other'))
    assert(OldKraken.Communication.stats.received == beforeRx)
""")

# 9. Job-correlated COMM_WHISPER_DROPPED: only the dropped WRGET fails over; second pending from same provider is untouched
s_bob.execute("""
    clock = clock + 700; timers[1]()
    while #OldKraken.Communication.queue > 0 do clock = clock + 1; OldKraken.Communication:Pump() end
    outgoing = {}

    OldKraken.Communication:OnAddonMessage('OLDKRKN', 'OKP^HERE^0.5.8-alpha.2', 'GUILD', 'Shared Provider')
    OldKraken.Communication:OnAddonMessage('OLDKRKN', 'OKP^HERE^0.5.8-alpha.2', 'GUILD', 'Backup Provider')
    local function sendWRIDX(id, owner, provider)
        local raw = OldKraken.GroupFinder._pack({'Bob Other Realm', owner, '2', '1'})
        local h = raw:gsub('.', function(c) return string.format('%02X', string.byte(c)) end)
        OldKraken.Communication:OnAddonMessage('OLDKRKN', 'GF2^WRIDX^' .. id .. '^1^1^' .. h, 'GUILD', provider)
    end
    sendWRIDX('1700000000-777771-1', 'Crafter A', 'Shared Provider')
    sendWRIDX('1700000000-777772-1', 'Crafter A', 'Backup Provider')
    sendWRIDX('1700000000-777773-1', 'Crafter B', 'Shared Provider')
    sendWRIDX('1700000000-777774-1', 'Crafter B', 'Backup Provider')

    local droppedID
    OldKraken:On('COMM_WHISPER_DROPPED', function(kind, target, _, jobID)
        if kind == 'WRGET' and not droppedID then droppedID = jobID end
    end)

    -- First WRGET in queue fails with TargetOffline (12); second WRGET succeeds (0)
    send_mode = 'drop_next_only'
    clock = clock + 1; timers[1]()
    while #OldKraken.Communication.queue > 0 do clock = clock + 1; OldKraken.Communication:Pump() end
    assert(droppedID ~= nil)
    assert(#outgoing == 1)
    local keptOwner = OldKraken.GroupFinder._unpackFields((outgoing[1].message:match('%^([0-9A-F]+)$'):gsub('%x%x', function(p) return string.char(tonumber(p, 16)) end)), 3)[2]
    local droppedOwner = (keptOwner == 'Crafter A') and 'Crafter B' or 'Crafter A'
    assert(outgoing[1].channel == 'WHISPER' and outgoing[1].target == 'Shared Provider')
    outgoing = {}

    -- Next tick (+1s): ONLY droppedOwner switches to Backup Provider; keptOwner stays pending on Shared Provider
    clock = clock + 1; timers[1]()
    while #OldKraken.Communication.queue > 0 do clock = clock + 1; OldKraken.Communication:Pump() end
    assert(#outgoing == 1)
    assert(outgoing[1].channel == 'WHISPER' and outgoing[1].target == 'Backup Provider')
    local switchedOwner = OldKraken.GroupFinder._unpackFields((outgoing[1].message:match('%^([0-9A-F]+)$'):gsub('%x%x', function(p) return string.char(tonumber(p, 16)) end)), 3)[2]
    assert(switchedOwner == droppedOwner)
    outgoing = {}

    -- Re-firing the already-handled droppedID must not cause a second/infinite failover
    OldKraken:Fire('COMM_WHISPER_DROPPED', 'WRGET', 'Shared Provider', '12', droppedID)
    clock = clock + 1; timers[1]()
    while #OldKraken.Communication.queue > 0 do clock = clock + 1; OldKraken.Communication:Pump() end
    assert(#outgoing == 0)
""")

print('Two simulated clients passed')
