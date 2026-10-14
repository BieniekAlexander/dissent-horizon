class_name DesyncCheck
extends RefCounted

## Whether every peer is still playing the same match: each takes a SimulationDigest once a
## simulated second, at the start of the tick, and sends the others its recent ones; a peer whose
## digest for a tick differs from this machine's has desynced. gdd/systems/commands/netplay.md
## §Decisions (on a desync).
##
## Topology-free and pure: NetMatch feeds it digests and packets. Every packet repeats the last
## KEPT_DIGESTS digests, so a lost one costs nothing and no acknowledgement is needed — one is
## taken a second, so that is several seconds of loss covered.

## How many of this machine's latest digests are kept, and repeated in every packet.
const KEPT_DIGESTS: int = 8
## Bumped on any change to the packet; one of another version is ignored.
const WIRE_VERSION: int = 1

## The first tick found to differ, or -1 while every digest has agreed.
var desync_tick: int = -1
## The peer whose digest differed, or -1.
var desync_peer: int = -1

## Tick -> this machine's digest, and its state string, for the last KEPT_DIGESTS ticks.
var _local: Dictionary = {}
var _local_states: Dictionary = {}
## Peer -> {tick -> digest} heard and not yet compared.
var _remote: Dictionary = {}


## This machine's digest of `a_tick`, and the state string it hashes (kept to be written out if
## this tick turns out to differ).
func record(a_tick: int, a_digest: String, a_state: String) -> void:
	_local[a_tick] = a_digest
	_local_states[a_tick] = a_state
	var ticks: Array = _local.keys()
	ticks.sort()
	while ticks.size() > KEPT_DIGESTS:
		var oldest: int = ticks.pop_front()
		_local.erase(oldest)
		_local_states.erase(oldest)
	for peer: int in _remote:
		_compare(peer)


## Take a peer's packet (encode()) in, comparing what it carries against this machine's.
func take(a_peer: int, a_bytes: PackedByteArray) -> void:
	var json := JSON.new()
	if json.parse(a_bytes.get_string_from_utf8()) != OK or not json.data is Dictionary:
		return
	var body: Dictionary = json.data
	if int(body.get("v", -1)) != WIRE_VERSION:
		return
	if not _remote.has(a_peer):
		_remote[a_peer] = {}
	for pair: Variant in body.get("digests", []):
		if pair is Array and (pair as Array).size() == 2:
			_remote[a_peer][int(pair[0])] = str(pair[1])
	_compare(a_peer)


## What this machine sends every peer: its recent digests.
func encode() -> PackedByteArray:
	var digests: Array = []
	for tick: int in _local:
		digests.append([tick, _local[tick]])
	return JSON.stringify({"v": WIRE_VERSION, "digests": digests}).to_utf8_buffer()


func has_desynced() -> bool:
	return desync_tick >= 0


## This machine's state string for the tick that differed, or "" while none has.
func desync_state() -> String:
	return str(_local_states.get(desync_tick, ""))


## Declare a desync found some other way (a peer that sent two different turns for one tick).
func declare(a_tick: int, a_peer: int) -> void:
	if not has_desynced():
		desync_tick = a_tick
		desync_peer = a_peer


## Compare `a_peer`'s digests with this machine's for every tick both hold. A tick only the peer
## holds waits for this machine to reach it; one too old for this machine to hold any more is
## dropped, since it can no longer be compared.
func _compare(a_peer: int) -> void:
	var theirs: Dictionary = _remote[a_peer]
	var oldest_kept: int = _local.keys().min() if not _local.is_empty() else 0
	for tick: int in theirs.keys():
		if _local.has(tick):
			if _local[tick] != theirs[tick] and (not has_desynced() or tick < desync_tick):
				desync_tick = tick
				desync_peer = a_peer
			theirs.erase(tick)
		elif tick < oldest_kept:
			theirs.erase(tick)
