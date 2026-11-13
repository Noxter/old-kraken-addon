from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
sources = [(root / name).read_text(encoding='utf-8') for name in
           ['Communication.lua', 'GroupFinder.lua', 'GroupFinderIntegration.lua']]


def client(name):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().player = name
    lua.execute('''
        OldKraken={DB={groupFinder={}}}; frames={}; timers={}; outgoing={}
        function OldKraken:Fire(...) end
        function print(...) end
        function UnitName() return player end
        function GetGuildInfo() return 'Guild' end
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


alice, bob = client('Alice'), client('Bob')


def flush(sender, recipients):
    sender.execute('while #OldKraken.Communication.queue > 0 do OldKraken.Communication:Pump() end')
    outgoing = sender.globals().outgoing
    packets = [outgoing[i] for i in range(1, len(outgoing) + 1)]
    sender.execute('outgoing={}')
    for packet in packets:
        for recipient in recipients:
            recipient.globals().OldKraken.Communication.OnAddonMessage(
                recipient.globals().OldKraken.Communication, 'OLDKRKN', packet, 'GUILD', sender.globals().player)


alice.execute("assert(OldKraken.GroupFinder:Create('Підземелля','dungeon','Тест',5)); OldKraken.GroupFinder:Changed()")
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
    assert(OldKraken.GroupFinder.requests[group.id].Bob == 'healer')
    assert(OldKraken.GroupFinder:Decide(group.id, 'Bob', true))
''')
flush(alice, [bob])
bob.execute("assert(OldKraken.GroupFinder.pending['Alice'..'\\001'..group.id] == 'accept')")
alice.execute('assert(OldKraken.GroupFinder:Cancel(group.id))')
flush(alice, [bob])
bob.execute("assert(OldKraken.GroupFinder.groups['Alice'..'\\001'..group.id].closed)")
print('Two simulated clients passed')
