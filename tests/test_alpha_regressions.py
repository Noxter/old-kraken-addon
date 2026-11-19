"""Regression tests for event packet boundaries and Workshop sync recovery."""
from pathlib import Path
import subprocess
import sys
import tempfile

from test_events_relay_authority import make_runtime, storage_for
from test_workshop_orders import client as real_workshop_client
from test_workshop_sync import client as sync_client, pack


ROOT = Path(__file__).resolve().parents[1]


def crowded_event():
    lua = make_runtime()
    lua.execute(r'''
        local events=OldKraken.GuildEvents
        assert(events:Create('Event', '', 2000003600, 'raid', 40, ''))
        local store=OldKraken.DB.events.guildCalendarV1['Test Realm\001Guild\001Tester Realm']
        for key,event in pairs(store.owned) do eventKey=key; crowded=event end
        crowded.rev=99
        for i=1,98 do
            local name=string.format('Attendee%03d',i)..string.rep('x',5)
            crowded.people[name]='dps'; crowded.statuses[name]='pending'
        end
        function encodeEvent(e)
            local names={}; for name in pairs(e.people) do names[#names+1]=name end; table.sort(names)
            local f={e.id,e.owner,e.rev,e.when,e.kind,e.size,e.cancelled and '1' or '0',e.title,e.description,#names}
            for _,name in ipairs(names) do f[#f+1]=name; f[#f+1]=e.people[name] end
            f[#f+1]=e.activity or ''; local codes={}
            for _,name in ipairs(names) do codes[#codes+1]=e.statuses[name]=='pending' and 'P' or 'A' end
            f[#f+1]=table.concat(codes); return OldKraken.GroupFinder._pack(f)
        end
        local base=#encodeEvent(crowded); assert(base<=2560 and base>=2158,base)
        crowded.description=string.rep('x',2560-base)
        -- Account for the length prefix growing when the description grows.
        while #encodeEvent(crowded)>2560 do crowded.description=crowded.description:sub(1,-2) end
        assert(#encodeEvent(crowded)==2560,#encodeEvent(crowded))
        function OldKraken.GroupFinder:CanPerformRole() return true end
    ''')
    return lua


def test_event_cancellation_fits_and_survives_reconnect():
    lua = crowded_event()
    lua.execute(r'''
        assert(OldKraken.GuildEvents:Cancel(eventKey))
        assert(crowded.cancelled and crowded.rev==100 and #encodeEvent(crowded)<=2560)
        assert(crowded.people['Attendee001xxxxx']=='dps')
        local guild=GetGuildInfo; GetGuildInfo=function() return nil end
        createdFrames[#createdFrames].scripts.OnEvent(nil,'PLAYER_GUILD_UPDATE')
        GetGuildInfo=guild; createdFrames[#createdFrames].scripts.OnEvent(nil,'PLAYER_LOGIN')
    ''')
    entry = storage_for(lua)["owned"][lua.globals().eventKey]
    assert entry is not None and entry["cancelled"] and entry["rev"] == 100


def test_owner_signup_fails_without_dangling_intent_when_packet_is_full():
    lua = crowded_event()
    lua.execute("assert(not OldKraken.GuildEvents:Signup(eventKey,'dps'))")
    store = storage_for(lua)
    assert store["owned"][lua.globals().eventKey]["people"]["Tester Realm"] is None
    assert store["intents"][lua.globals().eventKey] is None


def test_recovers_oversized_cancellation_saved_by_old_build():
    lua = crowded_event()
    lua.execute(r'''
        crowded.cancelled=true; crowded.rev=100; assert(#encodeEvent(crowded)==2561)
        local guild=GetGuildInfo; GetGuildInfo=function() return nil end
        createdFrames[#createdFrames].scripts.OnEvent(nil,'PLAYER_GUILD_UPDATE')
        GetGuildInfo=guild; createdFrames[#createdFrames].scripts.OnEvent(nil,'PLAYER_LOGIN')
        local store=OldKraken.DB.events.guildCalendarV1['Test Realm\001Guild\001Tester Realm']
        assert(store.owned[eventKey] and #encodeEvent(store.owned[eventKey])<=2560)
    ''')


def test_cancellation_uses_prior_membership_only_when_omitted():
    lua = make_runtime()
    lua.execute(r'''
        alerts=0; OldKraken:On('GUILD_EVENTS_CANCELLED',function() alerts=alerts+1 end)
        local h=OldKraken.Communication.handlers
        h.CEVENT('Owner Realm','1',makePayload(1,false,'dps','A'))
        local p=OldKraken.GroupFinder._pack({'1999999900-123456-1','Owner Realm',2,2000003600,'raid',10,'1','Test event','',0,'',''})
        h.CEVENT('Owner Realm','2',p)
        assert(alerts==1)
    ''')
    lua = make_runtime()
    lua.execute(r'''
        alerts=0; OldKraken:On('GUILD_EVENTS_CANCELLED',function() alerts=alerts+1 end)
        local h=OldKraken.Communication.handlers
        h.CEVENT('Owner Realm','1',makePayload(1,false,'dps','A'))
        h.CEVENT('Owner Realm','2',makePayload(2,true,'dps','D'))
        assert(alerts==0)
    ''')


def test_direct_owner_replaces_newer_relay_in_real_recipe_store():
    lua = real_workshop_client('Carol')
    lua.execute((ROOT / 'WorkshopSync.lua').read_text(encoding='utf-8'))
    lua.execute(r'''
        for _,f in ipairs(frames) do if f.events.PLAYER_LOGIN then f.scripts.OnEvent(f,'PLAYER_LOGIN') end end
        local c=OldKraken.GroupFinder
        local function snapshot(sender,rev,seen,name,flag,id)
            handlers.WRIDX(sender,'GUILD',c._pack({'Carol Mon','Alice Mon',rev,1}))
            handlers.WRPAGE(sender,'GUILD',c._pack({'Carol Mon','Alice Mon',rev,1,1,id or 123,456,171,seen,name,'Potion',flag}))
        end
        snapshot('Relay Mon',200,now,'Relay record','L')
        snapshot('Alice Mon',100,now-1,'Owner record','L')
        local s=OldKraken.DB.workshop.guilds['Realm\001Guild']
        assert(s.recipes['Alice Mon'][123].name=='Owner record')
        assert(s.recipeSnapshotViews['Alice Mon'].relayed==false)
        assert(s.recipeSources['Alice Mon'][123]==false)
        -- Relay tombstones cannot overwrite an already direct recipe.
        snapshot('Relay Mon',400,now,'Relay tombstone','D')
        assert(s.recipes['Alice Mon'][123].name=='Owner record')
        -- A direct record also replaces a newer relayed tombstone.
        snapshot('Relay Mon',500,now,'Relay tombstone','D',124)
        snapshot('Alice Mon',300,now-2,'Still known','L',124)
        assert(s.recipes['Alice Mon'][124].name=='Still known')
    ''')


def test_stalled_relay_fails_over_and_owner_preempts():
    lua = sync_client('Bob', [])
    g = lua.globals()
    index = pack(lua, ['Bob Realm', 'Alice Realm', 7, 1])
    g.handlers['WRIDX']('Relay1 Realm', 'GUILD', index)
    lua.execute('now=104; ticker(); drain()')
    # Healthy transfers retain their provider.
    g.handlers['WRIDX']('Relay2 Realm', 'GUILD', index)
    lua.execute('now=149; ticker()')
    fields = g.OldKraken.GroupFinder._unpackFields(g.drain('WRGET')[1]['payload'], 3)
    assert fields[1] == 'Relay1 Realm'
    lua.execute('now=150')
    g.handlers['WRIDX']('Relay2 Realm', 'GUILD', index)
    lua.execute('ticker()')
    fields = g.OldKraken.GroupFinder._unpackFields(g.drain('WRGET')[1]['payload'], 3)
    assert fields[1] == 'Relay2 Realm'
    g.handlers['WRIDX']('Alice Realm', 'GUILD', index)
    lua.execute('now=151; ticker()')
    fields = g.OldKraken.GroupFinder._unpackFields(g.drain('WRGET')[1]['payload'], 3)
    assert fields[1] == 'Alice Realm'
    # A newer direct revision replaces an unfinished older direct transfer.
    g.handlers['WRIDX']('Alice Realm', 'GUILD', pack(lua, ['Bob Realm','Alice Realm',8,1]))
    lua.execute('now=152; ticker()')
    fields = g.OldKraken.GroupFinder._unpackFields(g.drain('WRGET')[1]['payload'], 3)
    assert fields[1] == 'Alice Realm' and fields[3] == '8'
    # No-progress timeout releases even a direct transfer for a later relay.
    lua.execute('now=333; ticker(); drain()')
    g.handlers['WRIDX']('Relay2 Realm', 'GUILD', index)
    lua.execute('now=334; ticker()')
    fields = g.OldKraken.GroupFinder._unpackFields(g.drain('WRGET')[1]['payload'], 3)
    assert fields[1] == 'Relay2 Realm'


def test_packaged_version_identifies_actual_commit():
    with tempfile.TemporaryDirectory() as folder:
        toc = Path(folder) / 'OldKraken.toc'
        toc.write_bytes(b'## Interface: 16001\r\n## Version: 0.5.4-alpha.1\r\nCore.lua\r\n')
        script = ROOT / 'scripts/stamp-version.py'
        commit = '0123456789abcdef0123456789abcdef01234567'
        subprocess.run([sys.executable, str(script), str(toc), commit], check=True)
        assert toc.read_bytes() == b'## Interface: 16001\r\n## Version: 0.5.4-alpha.1+g0123456789ab\r\nCore.lua\r\n'
        subprocess.run([sys.executable, str(script), str(toc), 'f' * 40], check=True)
        assert b'0.5.4-alpha.1+gffffffffffff' in toc.read_bytes()
        before = toc.read_bytes()
        result = subprocess.run([sys.executable, str(script), str(toc), 'bad'], capture_output=True)
        assert result.returncode != 0 and toc.read_bytes() == before


if __name__ == '__main__':
    test_event_cancellation_fits_and_survives_reconnect()
    test_owner_signup_fails_without_dangling_intent_when_packet_is_full()
    test_recovers_oversized_cancellation_saved_by_old_build()
    test_cancellation_uses_prior_membership_only_when_omitted()
    test_direct_owner_replaces_newer_relay_in_real_recipe_store()
    test_stalled_relay_fails_over_and_owner_preempts()
    test_packaged_version_identifies_actual_commit()
    print('Alpha regression checks passed')
