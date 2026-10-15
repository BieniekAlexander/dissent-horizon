class_name LobbyLink
extends RefCounted

## The networked skirmish lobby's connection: who is in the lobby, what the host has set, and the
## moment the host presses Play. gdd/systems/commands/netplay.md §Decisions (entry).
##
## The HOST listens; a JOINER dials it by address and port. A joiner says which build it runs,
## and is refused — with the reason — for another, or when no OPEN slot is free; another OS or
## CPU is fine, as every platform computes the same match. Otherwise the host gives it a peer id
## and seats it in the first free open slot (SkirmishSetup.seat_anywhere), and it may move to
## another. The host sends the whole setup to
## every joiner whenever it changes; a joiner sees it and asks only to move.
##
## Each machine opens its MATCH transport (an ENetTransport) as soon as it knows its own peer id
## and tells the host the port, so at Play the host can send every peer the roster of where the
## others listen; each then names its peers (ENetTransport.set_peers) and the match's mesh forms
## while the map generates. The match transport outlives this link: the match takes it over.
##
## Lobby traffic is a handful of messages, each of which must arrive, so it is reliable and
## ordered — unlike the match's turns, which repeat themselves.

## The lobby has changed: the setup, who is in it, or their round trips.
signal changed
## Play: {recipe, seats: peer -> commander, input_delay_seconds, local_id, transport}.
signal started(a_launch: Dictionary)
## This machine is out of the lobby, and why: refused by the host, or the host has gone.
signal refused(a_reason: String)

## Bumped on any change to the lobby's messages; a joiner on another is refused.
const LOBBY_VERSION: int = 2
const _CHANNEL: int = 0
const _CHANNEL_COUNT: int = 1

## What the lobby has set. The host's to edit (then publish()); a joiner's is the host's copy.
var setup: SkirmishSetup = null
## This machine's peer id: SkirmishSetup.HOST_PEER for the host, the host's choice for a joiner,
## 0 until it has been given one.
var local_id: int = 0
## The match's transport, open from the moment this machine has a peer id.
var transport: ENetTransport = null
## Why this machine was refused or dropped, or "".
var refusal: String = ""

var _build: String
var _is_host: bool = false
var _is_started: bool = false
var _connection: ENetConnection = null
# The host's: peer id -> {"peer": ENetPacketPeer, "address": String, "mesh_port": int}.
var _members: Dictionary = {}
var _next_id: int = SkirmishSetup.HOST_PEER + 1
# A joiner's: the connection to the host, and the address it was dialled at.
var _server: ENetPacketPeer = null
var _host_address: String = ""
var _round_trips_ms: Dictionary = {}


## `a_build` defaults to this machine's; tests name others.
func _init(a_build: String = "") -> void:
	_build = a_build if a_build != "" else ReplayFile.current_version()


#region Hosting and joining
## Host a lobby on `a_port` (0: any free port; lobby_port() says which).
func host(a_port: int, a_bind_address: String = "*") -> Error:
	close()
	_connection = ENetConnection.new()
	var error: Error = _connection.create_host_bound(
		a_bind_address, a_port, Commander.NUM_MAX_COMMANDERS * 2, _CHANNEL_COUNT
	)
	if error != OK:
		_connection = null
		return error
	_is_host = true
	setup = SkirmishSetup.new()
	setup.is_networked = true
	return _open_transport(SkirmishSetup.HOST_PEER, a_bind_address)


## Join the lobby hosted at `a_address`:`a_port`. Seated, or refused, once the host answers.
func join(a_address: String, a_port: int) -> Error:
	close()
	_connection = ENetConnection.new()
	var error: Error = _connection.create_host(1, _CHANNEL_COUNT)
	if error != OK:
		_connection = null
		return error
	_server = _connection.connect_to_host(a_address, a_port, _CHANNEL_COUNT)
	if _server == null:
		close()
		return ERR_CANT_CONNECT
	_is_host = false
	_host_address = a_address
	return OK


func is_host() -> bool:
	return _is_host


func lobby_port() -> int:
	return _connection.get_local_port() if _connection != null and _is_host else 0


## Leave the lobby. The match transport is not closed: once Play has handed it on, it is the
## match's; before, close it with close_transport().
func close() -> void:
	if _connection == null:
		return
	# Now, not later: the host is destroyed on the next line, and a goodbye queued for later
	# would never leave. The joiner's own link is named, as get_peers() may not list it yet.
	var peers: Array = _connection.get_peers()
	if _server != null and not peers.has(_server):
		peers.append(_server)
	# A peer already gone (the host closed its side first, as it does at Play) has no ENet peer
	# behind it, and disconnecting it again raises an engine error.
	for peer: ENetPacketPeer in peers:
		if peer.is_active():
			peer.peer_disconnect_now()
	_connection.flush()
	_connection.destroy()
	_connection = null
	_server = null
	_members.clear()


func close_transport() -> void:
	if transport != null:
		transport.close()
		transport = null


#endregion


#region The lobby
## Service the connection: joiners arriving and leaving, the setup changing, Play.
func poll() -> void:
	if _connection == null:
		return
	# Until the connection goes: a refusal handled below closes it.
	while _connection != null:
		var event: Array = _connection.service(0)
		var type: ENetConnection.EventType = event[0]
		if type == ENetConnection.EVENT_NONE or type == ENetConnection.EVENT_ERROR:
			break
		var peer: ENetPacketPeer = event[1]
		match type:
			ENetConnection.EVENT_CONNECT:
				if not _is_host:
					_send(peer, {"t": "hello", "v": LOBBY_VERSION, "build": _build})
			ENetConnection.EVENT_DISCONNECT:
				_on_disconnect(peer)
			ENetConnection.EVENT_RECEIVE:
				var json := JSON.new()
				var text: String = peer.get_packet().get_string_from_utf8()
				if json.parse(text) == OK and json.data is Dictionary:
					if _is_host:
						_host_receive(peer, json.data)
					else:
						_join_receive(json.data)
	# The match transport refuses every dial until Play names its peers; servicing it keeps those
	# refusals prompt. After Play it keeps the mesh's handshakes moving while the map generates,
	# until the match takes the transport over; what it reads meanwhile — another peer's status,
	# turns or digests — is repeated in that peer's later packets, so dropping it costs nothing.
	if transport != null:
		transport.receive()
	_sample_round_trips()


## The peers in the lobby, the host's included, ascending.
func members() -> Array[int]:
	var out: Array[int] = [SkirmishSetup.HOST_PEER]
	if _is_host:
		for id: int in _members:
			out.append(id)
	elif setup != null:
		for slot: int in setup.player_count():
			var peer: int = setup.peer_in(slot)
			if peer != 0 and not out.has(peer):
				out.append(peer)
	out.sort()
	return out


## As a joiner: move to OPEN slot `a_slot`. The host decides; the setup shows where you sit.
func claim(a_slot: int) -> void:
	if not _is_host and _server != null:
		_send(_server, {"t": "claim", "slot": a_slot})


## As the host: send every joiner the setup as it now stands. Call after each edit.
func publish() -> void:
	if not _is_host:
		return
	var message: Dictionary = {"t": "lobby", "setup": setup.to_dict()}
	for id: int in _members:
		_send(_members[id]["peer"], message)
	changed.emit()


## The round trip to peer `a_id` in milliseconds, as last measured by the host; -1 unknown.
func round_trip_ms(a_id: int) -> int:
	return int(_round_trips_ms.get(a_id, -1))


## The input delay the measured round trips call for: the slowest round trip, which covers a
## joiner-to-joiner path through the two halves, plus a tick for the frame a turn waits to be
## sealed. TODO: joiners' round trips to each other are not measured, only to the host.
func measured_delay_seconds() -> float:
	var slowest_ms: int = 0
	for id: int in _round_trips_ms:
		slowest_ms = maxi(slowest_ms, int(_round_trips_ms[id]))
	return float(slowest_ms) / 1000.0 + TimeUtils.seconds_from_ticks(1)


## As the host: whether Play can be pressed — the setup is playable and every joiner's match
## transport is open.
func can_start() -> bool:
	if not _is_host or _is_started or not setup.can_play():
		return false
	return _members.values().all(func(m: Dictionary) -> bool: return int(m["mesh_port"]) > 0)


## As the host: Play. Every peer — this one included — is sent the recipe, the seats, the input
## delay and the roster of match ports, and starts.
func start(a_recipe: Dictionary, a_input_delay_seconds: float) -> void:
	if not can_start():
		return
	var roster: Array = [[SkirmishSetup.HOST_PEER, "", transport.local_port()]]
	for id: int in _members:
		roster.append([id, str(_members[id]["address"]), int(_members[id]["mesh_port"])])
	var seats: Array = []
	var match_seats: Dictionary = setup.match_seats()
	for peer: int in match_seats:
		seats.append([peer, int(match_seats[peer])])
	var message: Dictionary = {
		"t": "start",
		"recipe": a_recipe,
		"seats": seats,
		"delay": a_input_delay_seconds,
		"roster": roster,
	}
	for id: int in _members:
		_send(_members[id]["peer"], message)
	_connection.flush()
	_launch(JSON.parse_string(JSON.stringify(message)))


#endregion


#region Internal
func _open_transport(a_id: int, a_bind_address: String = "*") -> Error:
	local_id = a_id
	transport = ENetTransport.new(a_id)
	return transport.open(0, a_bind_address)


func _host_receive(a_peer: ENetPacketPeer, a_message: Dictionary) -> void:
	var id: int = _id_of(a_peer)
	match str(a_message.get("t", "")):
		"hello":
			var reason: String = _refusal_for(a_message)
			if reason == "" and _is_started:
				reason = "The match has already started."
			var seat: int = -1
			if reason == "":
				seat = setup.seat_anywhere(_next_id)
				if seat < 0:
					reason = "No open slot is free in this lobby."
			if reason != "":
				_send(a_peer, {"t": "refuse", "reason": reason})
				a_peer.peer_disconnect_later()
				return
			id = _next_id
			_next_id += 1
			_members[id] = {"peer": a_peer, "address": a_peer.get_remote_address(), "mesh_port": 0}
			_send(a_peer, {"t": "welcome", "id": id})
			publish()
		"mesh":
			if id >= 0:
				_members[id]["mesh_port"] = int(a_message.get("port", 0))
				changed.emit()
		"claim":
			if id >= 0 and setup.seat(id, int(a_message.get("slot", -1))):
				publish()


func _join_receive(a_message: Dictionary) -> void:
	match str(a_message.get("t", "")):
		"welcome":
			if _open_transport(int(a_message.get("id", 0))) == OK:
				_send(_server, {"t": "mesh", "port": transport.local_port()})
		"lobby":
			setup = SkirmishSetup.from_dict(a_message.get("setup", {}))
			changed.emit()
		"refuse":
			_drop(str(a_message.get("reason", "The host refused this machine.")))
		"start":
			_launch(a_message)


## Why a joiner saying `a_hello` is refused, or "".
func _refusal_for(a_hello: Dictionary) -> String:
	if int(a_hello.get("v", -1)) != LOBBY_VERSION or a_hello.get("build") != _build:
		return "This lobby runs another version of the game."
	return ""


func _on_disconnect(a_peer: ENetPacketPeer) -> void:
	if not _is_host:
		if not _is_started:
			_drop("The host has left the lobby." if refusal == "" else refusal)
		return
	var id: int = _id_of(a_peer)
	if id < 0:
		return
	_members.erase(id)
	_round_trips_ms.erase(id)
	setup.unseat(id)
	publish()


func _drop(a_reason: String) -> void:
	if refusal != "":
		return
	refusal = a_reason
	close()
	close_transport()
	refused.emit(a_reason)


## Play, on this machine: name the match transport's peers from the roster and hand everything
## the match is built from to whoever listens.
func _launch(a_message: Dictionary) -> void:
	if _is_started or transport == null:
		return
	_is_started = true
	var ids: Array[int] = []
	var dial: Dictionary = {}
	for entry: Variant in a_message.get("roster", []):
		var id: int = int(entry[0])
		ids.append(id)
		if id < local_id:
			var address: String = str(entry[1]) if str(entry[1]) != "" else _host_address
			dial[id] = [address, int(entry[2])]
	transport.set_peers(ids, dial)
	var seats: Dictionary = {}
	for pair: Variant in a_message.get("seats", []):
		seats[int(pair[0])] = int(pair[1])
	(
		started
		. emit(
			{
				"recipe": a_message.get("recipe", {}),
				"seats": seats,
				"input_delay_seconds": float(a_message.get("delay", 0.0)),
				"local_id": local_id,
				"transport": transport,
			}
		)
	)


func _sample_round_trips() -> void:
	if not _is_host:
		return
	for id: int in _members:
		var peer: ENetPacketPeer = _members[id]["peer"]
		_round_trips_ms[id] = int(peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))


func _id_of(a_peer: ENetPacketPeer) -> int:
	for id: int in _members:
		if _members[id]["peer"] == a_peer:
			return id
	return -1


func _send(a_peer: ENetPacketPeer, a_message: Dictionary) -> void:
	if a_peer == null:
		return
	a_peer.send(_CHANNEL, JSON.stringify(a_message).to_utf8_buffer(), ENetPacketPeer.FLAG_RELIABLE)
#endregion
