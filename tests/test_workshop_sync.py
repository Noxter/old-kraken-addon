"""Protocol-level tests for direct and relayed Workshop recipe snapshots."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
CODEC = (ROOT / "GroupFinder.lua").read_text(encoding="utf-8")
SYNC = (ROOT / "WorkshopSync.lua").read_text(encoding="utf-8")


def client(name, records):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().player = name
    lua.globals().seed_records = lua.table_from(records, recursive=True)
    lua.execute("""
        now=100; serverNow=1700000000; outgoing={}; handlers={}; ticker=nil
        imported={}; importedMeta={}
        OldKraken={DB={},Communication={queue={}},WorkshopRecipes={}}
        function UnitName() return player,'Realm' end
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
            return 7,seed_records
        end
        function OldKraken.WorkshopRecipes:ValidateSnapshotRecord(r)
            return type(r)=='table' and type(r.recipe)=='number' and r.recipe>0
                and type(r.item)=='number' and type(r.profession)=='number'
                and type(r.seen)=='number' and type(r.name)=='string' and type(r.product)=='string'
        end
        function OldKraken.WorkshopRecipes:ImportSnapshot(owner,records,relayed,allowOverride)
            imported[owner]=records
            importedMeta[owner]={relayed=relayed,allowOverride=allowOverride}
            return true
        end
        function drain(kind)
            local result={}
            for _,entry in ipairs(outgoing) do
                if not kind or entry.kind==kind then result[#result+1]=entry end
            end
            outgoing={}
            return result
        end
    """)
    lua.execute(CODEC)
    lua.execute(SYNC)
    lua.execute("eventHandler(nil,'PLAYER_LOGIN')")
    return lua


def pack(lua, values):
    return lua.globals().OldKraken.GroupFinder._pack(lua.table_from(values))


def send_packets(sender, receiver, packets):
    if isinstance(packets, list):
        iterable = packets
    else:
        iterable = (packets[index] for index in range(1, len(packets) + 1))
    for packet in iterable:
        handler = receiver.globals().handlers[packet["kind"]]
        if handler:
            handler(sender.globals().player + " Realm", "GUILD", packet["payload"])


def tick(lua, count=1):
    for _ in range(count):
        lua.execute("now=now+4; ticker()")


def test_direct_snapshot_round_trip_and_duplicate_protection():
    record = {
        "recipe": 123, "item": 456, "profession": 171,
        "seen": 1700000000, "name": "Test recipe", "product": "Potion",
    }
    owner = client("Alice", [record])
    requester = client("Bob", [])

    owner.globals().handlers["WRQ"]("Bob Realm", "request", "")
    tick(owner)
    index_packets = owner.globals().drain("WRIDX")
    assert len(index_packets) == 1
    send_packets(owner, requester, index_packets)

    tick(requester)
    get_packets = requester.globals().drain("WRGET")
    assert len(get_packets) == 1
    send_packets(requester, owner, get_packets)

    tick(owner)
    page_packets = owner.globals().drain("WRPAGE")
    assert len(page_packets) == 1
    send_packets(owner, requester, page_packets)

    imported = requester.globals().imported["Alice Realm"]
    assert len(imported) == 1
    assert imported[1]["recipe"] == 123
    assert requester.globals().importedMeta["Alice Realm"]["relayed"] is False

    # A duplicate page cannot cause a second import.
    send_packets(owner, requester, page_packets)
    assert len(requester.globals().imported["Alice Realm"]) == 1


def test_relayed_snapshot_is_not_promoted_to_direct_authority():
    record = {
        "recipe": 321, "item": 654, "profession": 171,
        "seen": 1700000000, "name": "Relayed recipe", "product": "Flask",
    }
    owner = client("Alice", [record])
    relay = client("Bob", [])
    receiver = client("Carol", [])

    # Alice -> Bob: Bob stores Alice's direct snapshot.
    relay.globals().handlers["WRQ"]("Alice Realm", "request", "")
    tick(relay)
    # Bob requests its own index from Alice; the index must be for Bob, so
    # use the owner-initiated query path to advertise Alice's snapshot to Bob.
    owner.globals().handlers["WRQ"]("Bob Realm", "request", "")
    tick(owner)
    send_packets(owner, relay, owner.globals().drain("WRIDX"))
    tick(relay)
    send_packets(relay, owner, relay.globals().drain("WRGET"))
    tick(owner)
    send_packets(owner, relay, owner.globals().drain("WRPAGE"))
    assert relay.globals().imported["Alice Realm"][1]["recipe"] == 321
    assert relay.globals().importedMeta["Alice Realm"]["relayed"] is False

    # Carol asks Bob for indexes. Bob may advertise Alice only because Bob
    # possesses a direct snapshot from Alice.
    relay.globals().handlers["WRQ"]("Carol Realm", "request", "")
    tick(relay, 5)
    relay_indexes = relay.globals().drain("WRIDX")
    alice_indexes = []
    codec = relay.globals().OldKraken.GroupFinder
    for index in range(1, len(relay_indexes) + 1):
        packet = relay_indexes[index]
        fields = codec._unpackFields(packet["payload"], 4)
        if fields and fields[2] == "Alice Realm":
            alice_indexes.append(packet)
    assert alice_indexes, "relay did not advertise the directly received Alice snapshot"
    send_packets(relay, receiver, alice_indexes)
    tick(receiver)
    request_packets = receiver.globals().drain("WRGET")
    assert request_packets
    send_packets(receiver, relay, request_packets)
    tick(relay)
    pages = relay.globals().drain("WRPAGE")
    assert pages
    send_packets(relay, receiver, pages)
    assert receiver.globals().importedMeta["Alice Realm"]["relayed"] is True
    assert receiver.globals().imported["Alice Realm"][1]["recipe"] == 321

    # Carol only has a relayed copy. It must not advertise Alice to Dave.
    receiver.globals().handlers["WRQ"]("Dave Realm", "request", "")
    tick(receiver, 5)
    dave_indexes = receiver.globals().drain("WRIDX")
    advertised = []
    for index in range(1, len(dave_indexes) + 1):
        packet = dave_indexes[index]
        fields = codec._unpackFields(packet["payload"], 4)
        if fields and fields[2] == "Alice Realm":
            advertised.append(packet)
    assert not advertised, "a relayed snapshot was incorrectly promoted and relayed again"


def test_invalid_snapshot_index_and_page_are_ignored():
    lua = client("Bob", [])
    codec = lua.globals().OldKraken.GroupFinder
    invalid_index = pack(lua, ["Mallory", "Alice", "7", "1"])
    lua.globals().handlers["WRIDX"]("Mallory Realm", "bad", invalid_index)
    assert lua.globals().imported["Alice Realm"] is None

    # No index was accepted, so a page from an unrelated sender has no pending
    # transfer to attach to and must not import anything.
    bad_page = pack(lua, ["Bob", "Alice", "7", "1", "1", "123", "456", "171",
                          "1700000000", "Recipe", "Potion", "L"])
    lua.globals().handlers["WRPAGE"]("Mallory Realm", "bad", bad_page)
    assert lua.globals().imported["Alice Realm"] is None


def test_index_count_limit_dedup_dequeue_reset_and_zero_full_scans():
    record = {
        "recipe": 555, "item": 777, "profession": 171,
        "seen": 1700000000, "name": "Perf recipe", "product": "Elixir",
    }
    lua = client("Alice", [record])
    # Seed 499 direct snapshots so each WRQ schedules 500 indexes (own + 499).
    lua.execute("""
        local snapshots = OldKraken.DB.workshop.guilds['TestRealm\\001Guild'].recipeDirectSnapshots
        for i = 1, 499 do
            snapshots['Crafter' .. i .. ' Realm'] = {
                rev = 1,
                records = { { recipe = 555, item = 777, profession = 171, seen = 1700000000, name = 'Perf recipe', product = 'Elixir' } },
            }
        end
        -- Instrument pairs() to fail if WRQ ever iterates over a large table (i.e. indices).
        local real_pairs = pairs
        local large_pairs_calls = 0
        pairs = function(t)
            local k1 = next(t)
            if k1 ~= nil and type(k1) == 'string' and k1:find('\\001', 1, true) then
                large_pairs_calls = large_pairs_calls + 1
            end
            return real_pairs(t)
        end
        -- Exact 1999 -> 2000 -> 2001 boundary check with single-key increments
        for s = 1, 3 do
            handlers['WRQ']('Sender' .. s .. ' Realm', 'request', '')
        end
        -- Add 499 entries from Sender4 (own + 498 snapshots) -> 1999 total
        local removed = snapshots['Crafter499 Realm']
        snapshots['Crafter499 Realm'] = nil
        handlers['WRQ']('Sender4 Realm', 'request', '')
        snapshots['Crafter499 Realm'] = removed
        -- 2000th key (1999 -> 2000) must be accepted; 2001st must be rejected
        local savedSnapshots = OldKraken.DB.workshop.guilds['TestRealm\\001Guild'].recipeDirectSnapshots
        OldKraken.DB.workshop.guilds['TestRealm\\001Guild'].recipeDirectSnapshots = {}
        handlers['WRQ']('Exact2000 Realm', 'request', '')
        handlers['WRQ']('Exact2001 Realm', 'request', '')
        OldKraken.DB.workshop.guilds['TestRealm\\001Guild'].recipeDirectSnapshots = savedSnapshots
        -- Re-adding the same key for an existing sender when at 2000 must not increment or fail
        now = now + 70
        handlers['WRQ']('Sender1 Realm', 'request', '')
        assert(large_pairs_calls == 0, 'WRQ/scheduleIndex must not call pairs(indices), got ' .. large_pairs_calls)
        pairs = real_pairs
    """)
    # Drain all 2000 scheduled WRIDX packets via ticker without exceeding the 1800s TTL
    lua.execute("for _ = 1, 2000 do ticker() end")
    drained = lua.globals().drain("WRIDX")
    assert len(drained) == 2000, f"expected 2000 WRIDX packets, got {len(drained)}"

    # After draining, Sender5 can now schedule again (decremented on removal)
    lua.execute("handlers['WRQ']('Sender5 Realm', 'request', '')")
    lua.execute("for _ = 1, 500 do ticker() end")
    drained_after = lua.globals().drain("WRIDX")
    assert len(drained_after) == 500, f"expected 500 WRIDX packets after dequeue, got {len(drained_after)}"

    # Expired entries removed by ticker also decrement indexCount
    lua.execute("""
        for s = 10, 13 do
            handlers['WRQ']('ExpSender' .. s .. ' Realm', 'request', '')
        end
        now = now + 1801
        for _ = 1, 2000 do ticker() end
        assert(#drain('WRIDX') == 0, 'expired entries must not send WRIDX')
        handlers['WRQ']('AfterExp Realm', 'request', '')
        for _ = 1, 500 do ticker() end
        assert(#drain('WRIDX') == 500, 'indexCount must be 0 after expiry cleanup')
    """)

    # Reset on guild change clears indices and indexCount to 0
    lua.execute("""
        handlers['WRQ']('Sender6 Realm', 'request', '')
        function GetGuildInfo() return 'OtherGuild' end
        eventHandler(nil, 'PLAYER_GUILD_UPDATE')
        drain('WRIDX')
        -- Now 2000 new entries can be scheduled in the new guild
        local snapshots = OldKraken.DB.workshop.guilds['TestRealm\\001OtherGuild'].recipeDirectSnapshots
        for i = 1, 499 do
            snapshots['Other' .. i .. ' Realm'] = {
                rev = 1,
                records = { { recipe = 555, item = 777, profession = 171, seen = 1700000000, name = 'Perf recipe', product = 'Elixir' } },
            }
        end
        for s = 1, 4 do
            handlers['WRQ']('NewSender' .. s .. ' Realm', 'request', '')
        end
    """)
    lua.execute("for _ = 1, 2000 do ticker() end")
    assert len(lua.globals().drain("WRIDX")) == 2000


if __name__ == "__main__":
    test_direct_snapshot_round_trip_and_duplicate_protection()
    test_relayed_snapshot_is_not_promoted_to_direct_authority()
    test_invalid_snapshot_index_and_page_are_ignored()
    test_index_count_limit_dedup_dequeue_reset_and_zero_full_scans()
    print("Workshop sync checks passed")
