class_name ENetTransport
extends NetTransport

## The peer-to-peer transport: one ENet host per machine, connected to every other peer in a full
## mesh, by address and port. gdd/systems/commands/netplay.md §Decisions (transport, peers).
##
## Each pair holds exactly one connection, and the peer with the HIGHER id dials it, naming
## itself in ENet's connect data — so a connection is identified the moment it opens, without a
## message of its own, and a machine needs only the addresses of the peers below it. A dial that
## fails or a connection that drops is dialled again on the next receive(); the peers above dial
## back on their own. One host listens for the peers above, and each dial has a host of its own:
## an ENetConnection dials only while it has no other peer (Godot's own mesh mode is built so).
##
## Unsequenced and unreliable, as NetTransport promises nothing more: TurnPacket repeats every
## unacknowledged turn, so a lost packet costs only the wait for the next one, and an ENet resend
## would arrive later than that packet does anyway.
##
## TODO: NAT traversal and a relay (netplay.md §Decisions, transport); a direct dial needs the
## lower peer's port reachable.

## Turns are the only traffic, and TurnPacket needs no ordering, so one channel carries them.
const _CHANNEL: int = 0
const _CHANNEL_COUNT: int = 1
## Unreliable, and unordered even among themselves; a packet too large for one datagram is split
## unreliably too, and lost whole if a fragment is.
const _SEND_FLAGS: int = ENetPacketPeer.FLAG_UNSEQUENCED | ENetPacketPeer.FLAG_UNRELIABLE_FRAGMENT


## One connection to one peer, and the host it lives on: the listening host for a peer that
## dialled in, a host of its own for a peer this machine dialled.
class Link:
	var host: ENetConnection
	var peer: ENetPacketPeer
	var is_dialled: bool
	var is_open: bool = false

	func _init(a_host: ENetConnection, a_peer: ENetPacketPeer, a_is_dialled: bool) -> void:
		host = a_host
		peer = a_peer
		is_dialled = a_is_dialled


var _local_id: int
var _remote_ids: Array[int] = []
## Peer id -> [address: String, port: int], for each peer below this one: the ones it dials.
var _dial_addresses: Dictionary = {}
## The host the peers above dial into. Null until open() and after close().
var _listener: ENetConnection = null
## Peer id -> its Link, dialling or open.
var _links: Dictionary = {}
var _inbox: Array = []


## A transport for peer `a_local_id` among `a_remote_ids`. `a_dial_addresses` maps each remote id
## BELOW `a_local_id` to [address, port]; the peers above dial this one, and need no entry.
func _init(
	a_local_id: int, a_remote_ids: Array[int] = [], a_dial_addresses: Dictionary = {}
) -> void:
	_local_id = a_local_id
	set_peers(a_remote_ids, a_dial_addresses)


## Name the session's other peers, as set_peers' arguments are _init's. A lobby opens the
## transport before it knows them, so its port can be told to the others, and names them at Play;
## until then every dial in is refused, and the dialler dials again.
func set_peers(a_remote_ids: Array[int], a_dial_addresses: Dictionary = {}) -> void:
	_remote_ids = a_remote_ids.duplicate()
	_remote_ids.erase(_local_id)
	_remote_ids.sort()
	_dial_addresses = a_dial_addresses.duplicate()
	if _listener != null:
		_dial_missing()


## Listen on `a_port` (0: any free port, local_port() says which) and start dialling the peers
## below. An address of "*" listens on every interface.
func open(a_port: int, a_bind_address: String = "*") -> Error:
	close()
	var listener := ENetConnection.new()
	# Two slots a peer: a redial can open while ENet is still tearing the dropped connection down.
	# Sized for the most peers a match can have, since a lobby opens this before it knows them.
	var error: Error = listener.create_host_bound(
		a_bind_address, a_port, Commander.NUM_MAX_COMMANDERS * 2, _CHANNEL_COUNT
	)
	if error != OK:
		return error
	_listener = listener
	_dial_missing()
	return OK


## The port this machine listens on, or 0 when it is not open.
func local_port() -> int:
	return _listener.get_local_port() if _listener != null else 0


func is_open() -> bool:
	return _listener != null


## Whether every other peer is connected — what the ready barrier waits for (PLANNED).
func is_connected_to_all() -> bool:
	return _remote_ids.all(is_connected_to)


func is_connected_to(a_id: int) -> bool:
	var link: Link = _links.get(a_id, null)
	return link != null and link.is_open


## Drop every connection and stop listening.
func close() -> void:
	for id: int in _links.keys():
		_drop(id, true)
	if _listener != null:
		# Every peer, linked or not, so none waits out ENet's timeout to learn this machine has
		# gone. get_peers() lists a peer only once its connect event is serviced, so service first;
		# a handshake still in flight is left to that timeout.
		_service(_listener, -1)
		for peer: ENetPacketPeer in _listener.get_peers():
			peer.peer_disconnect_now()
		_listener.flush()
		_listener.destroy()
		_listener = null


func local_id() -> int:
	return _local_id


func remote_ids() -> Array[int]:
	return _remote_ids.duplicate()


## Sent at once (flushed), or dropped when `a_to` is not connected: a datagram may be lost.
func send(a_to: int, a_bytes: PackedByteArray) -> void:
	var link: Link = _links.get(a_to, null)
	if link == null or not link.is_open:
		return
	link.peer.send(_CHANNEL, a_bytes, _SEND_FLAGS)
	link.host.flush()


## Service every host — connections opening and closing, packets arriving — and return what has
## arrived since the last call. Dials again any peer below whose connection is missing.
func receive() -> Array:
	if _listener == null:
		return []
	_service(_listener, -1)
	for id: int in _links.keys():
		var link: Link = _links.get(id, null)
		if link != null and link.is_dialled:
			_service(link.host, id)
	_dial_missing()
	var out: Array = _inbox
	_inbox = []
	return out


## Drain `a_host`'s events. `a_dialled_id` is the peer a dial host belongs to, or -1 for the
## listener, whose peers are named by their connect data.
func _service(a_host: ENetConnection, a_dialled_id: int) -> void:
	while true:
		var event: Array = a_host.service(0)
		var type: ENetConnection.EventType = event[0]
		if type == ENetConnection.EVENT_NONE:
			return
		if type == ENetConnection.EVENT_ERROR:
			push_error("ENetTransport: a host reported an error while servicing")
			return
		var peer: ENetPacketPeer = event[1]
		var id: int = a_dialled_id if a_dialled_id >= 0 else _id_of(peer)
		match type:
			ENetConnection.EVENT_CONNECT:
				if a_dialled_id >= 0:
					(_links[a_dialled_id] as Link).is_open = true
				else:
					_accept(peer, int(event[2]))
			ENetConnection.EVENT_DISCONNECT:
				if id >= 0:
					_drop(id, false)
					if a_dialled_id >= 0:
						return
			ENetConnection.EVENT_RECEIVE:
				var bytes: PackedByteArray = peer.get_packet()
				if id >= 0:
					_inbox.append([id, bytes])


## A peer above dialled in, naming itself in its connect data. Anything else — a stranger, a peer
## below (it never dials), a second connection from a peer already linked — is refused.
func _accept(a_peer: ENetPacketPeer, a_id: int) -> void:
	if a_id in _remote_ids and a_id > _local_id and not _links.has(a_id):
		var link := Link.new(_listener, a_peer, false)
		link.is_open = true
		_links[a_id] = link
	else:
		a_peer.peer_disconnect_now()


func _dial_missing() -> void:
	for id: int in _dial_addresses:
		if id >= _local_id or _links.has(id):
			continue
		var host := ENetConnection.new()
		if host.create_host(1, _CHANNEL_COUNT) != OK:
			continue
		var address: Array = _dial_addresses[id]
		var peer: ENetPacketPeer = host.connect_to_host(
			str(address[0]), int(address[1]), _CHANNEL_COUNT, _local_id
		)
		if peer == null:
			host.destroy()
			continue
		_links[id] = Link.new(host, peer, true)


## Forget the link to `a_id`; a dial host goes with it. `a_say_goodbye` tells the peer first.
func _drop(a_id: int, a_say_goodbye: bool) -> void:
	var link: Link = _links.get(a_id, null)
	if link == null:
		return
	_links.erase(a_id)
	if a_say_goodbye:
		link.peer.peer_disconnect_now()
		link.host.flush()
	if link.is_dialled:
		link.host.destroy()


func _id_of(a_peer: ENetPacketPeer) -> int:
	for id: int in _links:
		if (_links[id] as Link).peer == a_peer:
			return id
	return -1
