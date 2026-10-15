class_name NetSession
extends RefCounted

## The handshake before a networked match, and its ready barrier. Every peer sends every other
## its whole STATUS each pump — which build it runs, whether it has loaded the map and what that
## map hashed to, whether it has started — and keeps the newest status it has heard from each.
## Nothing is acknowledged: a lost status is replaced by the next one.
## gdd/systems/commands/netplay.md §What lockstep builds that rollback keeps (session setup).
##
## The HOST's status also carries the match: the skirmish recipe every peer builds the map from,
## which commander each peer plays (its seat), and the input delay. A peer loads once it has
## heard the match; the match may start once every peer has loaded the same map.
##
## Refused, for good, when a peer runs another build, the host's match leaves a peer without a
## seat, or a peer's map hashed differently. Another OS or CPU is not a reason: the simulation
## computes the same match on every platform (authoring/native-code.md §Maths that rounds the
## same everywhere).
##
## TODO: the input delay is the host's to give; measuring it from the round trip in the lobby is
## the lobby's work (netplay.md §Decisions, input delay).

## Bumped on any change to the status's encoding; a status of another version reads as another
## build, which it is.
const WIRE_VERSION: int = 2

var host_id: int

var _transport: NetTransport
## This machine's status, as sent.
var _local: Dictionary
## Peer id -> the newest status heard from it.
var _heard: Dictionary = {}
var _refusal: String = ""


## A session over `a_transport` (its session channel) whose match `a_host_id` sets. `a_build`
## defaults to this machine's; tests name others.
func _init(a_transport: NetTransport, a_host_id: int, a_build: String = "") -> void:
	_transport = a_transport
	host_id = a_host_id
	_local = {
		"session": WIRE_VERSION,
		"build": a_build if a_build != "" else ReplayFile.current_version(),
		"loaded": false,
		"map": "",
		"started": false,
	}


func is_host() -> bool:
	return _transport.local_id() == host_id


## As the host: the match every peer plays. `a_seats` maps each peer id to the commander it plays.
## Ignored on any other peer, whose match is the host's.
func offer_match(a_recipe: Dictionary, a_seats: Dictionary, a_input_delay_seconds: float) -> void:
	if not is_host():
		return
	var seats: Array = []
	for peer: int in a_seats:
		seats.append([peer, int(a_seats[peer])])
	# Kept as the wire decodes it (numbers as floats), so the host builds the match from exactly
	# what every other peer builds it from.
	var offered: Dictionary = {"recipe": a_recipe, "seats": seats, "delay": a_input_delay_seconds}
	_local["match"] = JSON.parse_string(JSON.stringify(offered))


## The host's match as heard — {recipe, seats: peer -> commander, input_delay_seconds} — or empty
## until it has been.
func match_settings() -> Dictionary:
	var status: Dictionary = _local if is_host() else _heard.get(host_id, {})
	var offered: Variant = status.get("match", null)
	if not offered is Dictionary:
		return {}
	var seats: Dictionary = {}
	for pair: Variant in offered.get("seats", []):
		seats[int(pair[0])] = int(pair[1])
	return {
		"recipe": offered.get("recipe", {}),
		"seats": seats,
		"input_delay_seconds": float(offered.get("delay", 0.0)),
	}


## This machine has loaded the match's map, which hashed to `a_map_digest` (MapDigest).
func mark_loaded(a_map_digest: String) -> void:
	_local["loaded"] = true
	_local["map"] = a_map_digest


func is_loaded() -> bool:
	return bool(_local["loaded"])


func mark_started() -> void:
	_local["started"] = true


## Take in every status that has arrived, then send this machine's to every peer — until every
## peer has started, when nobody is listening for it any more.
func pump() -> void:
	for message: Array in _transport.receive():
		_take(int(message[0]), message[1])
	_check()
	if bool(_local["started"]) and _remote_ids().all(_has_started):
		return
	var bytes: PackedByteArray = JSON.stringify(_local).to_utf8_buffer()
	for peer: int in _remote_ids():
		_transport.send(peer, bytes)


## Why the match cannot be played, or "" while nothing has ruled it out.
func refusal() -> String:
	return _refusal


## Whether the match may start: the host's match heard, a seat for every peer, and every peer
## loaded with the same map as this one.
func is_ready() -> bool:
	return (
		_refusal == ""
		and not match_settings().is_empty()
		and bool(_local["loaded"])
		and waiting_on().is_empty()
	)


## The peers not yet heard to have loaded — what a loading screen waits on.
func waiting_on() -> Array[int]:
	var out: Array[int] = []
	for peer: int in _remote_ids():
		if not bool(_heard.get(peer, {}).get("loaded", false)):
			out.append(peer)
	return out


func _remote_ids() -> Array[int]:
	return _transport.remote_ids()


func _has_started(a_peer: int) -> bool:
	return bool(_heard.get(a_peer, {}).get("started", false))


func _take(a_from: int, a_bytes: PackedByteArray) -> void:
	if not a_from in _remote_ids():
		return
	var json := JSON.new()
	if json.parse(a_bytes.get_string_from_utf8()) != OK or not json.data is Dictionary:
		return
	_heard[a_from] = json.data


## Rule the match out, once, on the first reason found.
func _check() -> void:
	if _refusal != "":
		return
	for peer: int in _remote_ids():
		var status: Dictionary = _heard.get(peer, {})
		if status.is_empty():
			continue
		if int(status.get("session", -1)) != WIRE_VERSION or status.get("build") != _local["build"]:
			_refusal = "Peer %d runs another version of the game." % peer
		elif (
			bool(status.get("loaded", false))
			and bool(_local["loaded"])
			and status.get("map") != _local["map"]
		):
			_refusal = "Peer %d generated a different map." % peer
		if _refusal != "":
			return
	var seats: Dictionary = match_settings().get("seats", {})
	if match_settings().is_empty():
		return
	for peer: int in [_transport.local_id()] + _remote_ids():
		if not seats.has(peer):
			_refusal = "The host's match has no seat for peer %d." % peer
			return
