class_name TransportMux
extends RefCounted

## Several conversations over one NetTransport: each channel is a NetTransport of its own, and a
## message reaches only the channel it was sent on. The session handshake and the turns share
## one connection for the whole match, and neither reads the other's messages.
## gdd/systems/commands/netplay.md §What lockstep builds that rollback keeps.
##
## A message is its channel's tag, one byte, then its bytes. A message for a channel nobody asked
## for, or too short to carry a tag, is dropped — a datagram may be lost anyway.

## The channels a networked match uses.
const TURNS: int = 1
const SESSION: int = 2
const DIGESTS: int = 3


## One channel: sends tagged, receives only what was tagged for it.
class Channel:
	extends NetTransport

	var _mux: TransportMux
	var _tag: int
	var _inbox: Array = []

	func _init(a_mux: TransportMux, a_tag: int) -> void:
		_mux = a_mux
		_tag = a_tag

	func local_id() -> int:
		return _mux._base.local_id()

	func remote_ids() -> Array[int]:
		return _mux._base.remote_ids()

	func send(a_to: int, a_bytes: PackedByteArray) -> void:
		var tagged := PackedByteArray([_tag])
		tagged.append_array(a_bytes)
		_mux._base.send(a_to, tagged)

	func receive() -> Array:
		_mux._sort_arrivals()
		var out: Array = _inbox
		_inbox = []
		return out


var _base: NetTransport
## Tag -> WeakRef of its Channel. Weak, because a channel holds its mux: whoever holds a channel
## keeps the mux alive, and a cycle would keep both alive forever.
var _channels: Dictionary = {}


func _init(a_base: NetTransport) -> void:
	_base = a_base


## The channel tagged `a_tag` (0–255), made on first ask.
func channel(a_tag: int) -> NetTransport:
	var held: Channel = _channel(a_tag)
	if held != null:
		return held
	var made: Channel = Channel.new(self, a_tag)
	_channels[a_tag] = weakref(made)
	return made


## Take everything the base transport has received and hand each message to its channel.
func _sort_arrivals() -> void:
	for message: Array in _base.receive():
		var bytes: PackedByteArray = message[1]
		var to: Channel = _channel(int(bytes[0])) if not bytes.is_empty() else null
		if to != null:
			to._inbox.append([int(message[0]), bytes.slice(1)])


func _channel(a_tag: int) -> Channel:
	var ref: WeakRef = _channels.get(a_tag, null)
	return ref.get_ref() as Channel if ref != null else null
