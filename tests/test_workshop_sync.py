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


if __name__ == "__main__":
    test_direct_snapshot_round_trip_and_duplicate_protection()
    test_relayed_snapshot_is_not_promoted_to_direct_authority()
    test_invalid_snapshot_index_and_page_are_ignored()
    print("Workshop sync checks passed")
