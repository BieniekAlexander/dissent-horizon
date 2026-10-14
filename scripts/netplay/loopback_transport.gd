class_name LoopbackTransport
extends NetTransport

## One peer's end of a LoopbackNetwork: the NetTransport tests run netplay over, with no socket.
## Made by LoopbackNetwork.endpoint(), never directly.

## Weak, because the network holds its endpoints: two strong references would keep both alive.
var _network: WeakRef
var _id: int
var _inbox: Array = []


func _init(a_network: LoopbackNetwork, a_id: int) -> void:
	_network = weakref(a_network)
	_id = a_id


func local_id() -> int:
	return _id


func remote_ids() -> Array[int]:
	var network: LoopbackNetwork = _network.get_ref()
	if network == null:
		return [] as Array[int]
	var out: Array[int] = network.peer_ids()
	out.erase(_id)
	return out


func send(a_to: int, a_bytes: PackedByteArray) -> void:
	var network: LoopbackNetwork = _network.get_ref()
	if network != null:
		network._send(_id, a_to, a_bytes)


func receive() -> Array:
	var out: Array = _inbox
	_inbox = []
	return out


func _deliver(a_from: int, a_bytes: PackedByteArray) -> void:
	_inbox.append([a_from, a_bytes])
