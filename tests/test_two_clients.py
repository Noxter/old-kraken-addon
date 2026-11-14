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
        function GetGuildRosterInfo(i) if i == 1 then return 'Alice Moon' else return 'Bob Other Realm' end end
        function IsInGuild() return true end
        function GetServerTime() return 1700000000 end
        function GetTime() return 100 end
        function CreateFrame()
            local f={events={}}
            function f:RegisterEvent(event) self.events[event]=true end
            function f:SetScript(_, fn) self.handler=fn end
            frames[#frames+1]=f; return f
        end
        C_Timer={NewTicker=function(_, fn) timers[#timers+1]=fn end}
        C_ChatInfo={RegisterAddonMessagePrefix=function() return true end,
            SendAddonMessage=function(prefix,message,channel)
                outgoing[#outgoing+1]=message; return 0
            end}
        Enum={SendAddonMessageResult={Success=0,AddonMessageThrottle=1,ChannelThrottle=2,AddOnMessageLockdown=3}}
        function strsplit(_, s) return s:match('^([^%^]*)%^([^%^]*)%^([^%^]*)%^([^%^]*)$') end
    ''')
    for source in sources:
        lua.execute(source)
    lua.execute('for _,f in ipairs(frames) do if f.events.PLAYER_LOGIN then f.handler(f,"PLAYER_LOGIN") end end')
    return lua


alice, bob = client('Alice', 'Moon'), client('Bob', 'Other Realm')


def flush(sender, recipients):
    sender.execute('while #OldKraken.Communication.queue > 0 do OldKraken.Communication:Pump() end')
    outgoing = sender.globals().outgoing
    packets = [outgoing[i] for i in range(1, len(outgoing) + 1)]
    sender.execute('outgoing={}')
    for packet in packets:
        for recipient in recipients:
            recipient.globals().OldKraken.Communication.OnAddonMessage(
                recipient.globals().OldKraken.Communication, 'OLDKRKN', packet, 'GUILD', sender.globals().player + ' ' + sender.globals().realm)


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
print('Two simulated clients passed')
