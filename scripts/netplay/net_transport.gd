@abstract class_name NetTransport
extends RefCounted

## Everything that knows about other machines sits behind this interface; the simulation, the
## input buffer and the turn packets never do. Peer-to-peer comes first (ENetTransport);
## a relay or a client-server design is a second implementation of this same interface, not a
## change to anything above it. gdd/systems/commands/netplay.md §The model, §Decisions.
##
## Datagram semantics: a message may be lost, delayed, duplicated or reordered, and nothing above
## relies on otherwise — TurnPacket repeats every unacknowledged turn, and InputBuffer accepts a
## copy of a turn it already holds. A transport that happens to be reliable is fine too.
##
## Built: ENetTransport, and LoopbackTransport for tests.
## TODO: NAT traversal and a relay, behind this interface (netplay.md §Decisions, transport).

## This machine's peer id.
@abstract func local_id() -> int

## Every other peer in the session, ascending.
@abstract func remote_ids() -> Array[int]

## Send `a_bytes` to peer `a_to`. Never blocks; delivery is not promised.
@abstract func send(a_to: int, a_bytes: PackedByteArray) -> void

## Every message that has arrived since the last call, oldest first, each as [from: int,
## bytes: PackedByteArray].
@abstract func receive() -> Array


## Let go of whatever the transport holds open. Nothing, unless a transport holds something.
func close() -> void:
	pass
