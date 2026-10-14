extends GutTest

## The loopback network tests run netplay over, and the netplay pieces on top of it: two peers
## exchanging TurnPackets into their InputBuffers over a lossy, reordering, duplicating link
## must end up confirming the same ticks with the same orders in the same order.
## gdd/systems/commands/netplay.md §Decisions (testing).

const A: int = 1
const B: int = 2


func test_a_message_arrives_after_its_latency() -> void:
	var network := LoopbackNetwork.new()
	network.latency_min = 3
	network.latency_max = 3
	var a: LoopbackTransport = network.endpoint(A)
	var b: LoopbackTransport = network.endpoint(B)
	a.send(B, "hello".to_utf8_buffer())
	network.step(2)
	assert_eq(b.receive(), [])
	network.step()
	var got: Array = b.receive()
	assert_eq(got.size(), 1)
	assert_eq(int(got[0][0]), A)
	assert_eq((got[0][1] as PackedByteArray).get_string_from_utf8(), "hello")


func test_every_endpoint_sees_the_others_as_peers() -> void:
	var network := LoopbackNetwork.new()
	var a: LoopbackTransport = network.endpoint(A)
	network.endpoint(B)
	network.endpoint(3)
	assert_eq(a.local_id(), A)
	assert_eq(a.remote_ids(), [B, 3] as Array[int])


func test_full_loss_delivers_nothing() -> void:
	var network := LoopbackNetwork.new()
	network.loss = 1.0
	var a: LoopbackTransport = network.endpoint(A)
	var b: LoopbackTransport = network.endpoint(B)
	a.send(B, PackedByteArray([1]))
	network.step(5)
	assert_eq(b.receive(), [])


func test_the_same_seed_gives_the_same_deliveries() -> void:
	assert_eq(_deliveries(42), _deliveries(42))


func _deliveries(a_seed: int) -> Array:
	var network := LoopbackNetwork.new(a_seed)
	network.latency_min = 0
	network.latency_max = 4
	network.loss = 0.3
	network.duplication = 0.3
	var a: LoopbackTransport = network.endpoint(A)
	var b: LoopbackTransport = network.endpoint(B)
	for i: int in 20:
		a.send(B, PackedByteArray([i]))
	network.step(10)
	var out: Array = []
	for message: Array in b.receive():
		out.append((message[1] as PackedByteArray)[0])
	return out


func test_two_peers_confirm_the_same_ticks_over_a_bad_link() -> void:
	var network := LoopbackNetwork.new(7)
	network.latency_min = 1
	network.latency_max = 5
	network.loss = 0.25
	network.duplication = 0.2
	var ids: Array[int] = [A, B]
	var peers: Dictionary = {}
	for id: int in ids:
		peers[id] = {
			"transport": network.endpoint(id),
			"buffer": InputBuffer.new(ids),
			"acked": -1,  # the newest of this peer's ticks the other has acknowledged
		}
	var last_tick: int = 29
	for t: int in last_tick + 1:
		for id: int in ids:
			# Every third tick carries an order, the rest are explicit empty turns.
			var orders: Array[PlayerOrder] = []
			if t % 3 == 0:
				orders.append(
					PlayerOrder.new(PlayerOrder.Kind.AUTOCAST, id, {"ability": "t%d" % t})
				)
			peers[id]["buffer"].add(Turn.new(t, id, orders))
		_exchange(peers, ids)
		network.step()
	for i: int in 40:
		_exchange(peers, ids)
		network.step()

	var buffer_a: InputBuffer = peers[A]["buffer"]
	var buffer_b: InputBuffer = peers[B]["buffer"]
	assert_eq(buffer_a.confirmed_tick(), last_tick)
	assert_eq(buffer_b.confirmed_tick(), last_tick)
	for t: int in last_tick + 1:
		assert_eq(
			_order_summary(buffer_a.orders_for(t)),
			_order_summary(buffer_b.orders_for(t)),
			"tick %d" % t
		)
	assert_eq(_order_summary(buffer_a.orders_for(3)), ["1:t3", "2:t3"])


## One round of the exchange every peer runs each step: read what arrived, then send each other
## peer every own turn it has not acknowledged, with this peer's acknowledgement of its turns.
func _exchange(a_peers: Dictionary, a_ids: Array[int]) -> void:
	for id: int in a_ids:
		var peer: Dictionary = a_peers[id]
		var buffer: InputBuffer = peer["buffer"]
		for message: Array in (peer["transport"] as LoopbackTransport).receive():
			var packet: TurnPacket = TurnPacket.decode(message[1])
			assert_not_null(packet)
			peer["acked"] = maxi(int(peer["acked"]), packet.ack)
			for t: Turn in packet.turns:
				assert_eq(buffer.add(t), InputBuffer.Refusal.NONE)
	for id: int in a_ids:
		var peer: Dictionary = a_peers[id]
		var buffer: InputBuffer = peer["buffer"]
		for other: int in a_ids:
			if other == id:
				continue
			var unacked: Array[Turn] = []
			for t: int in range(int(peer["acked"]) + 1, buffer.newest_contiguous(id) + 1):
				unacked.append(buffer.turn(t, id))
			var packet := TurnPacket.new(id, buffer.newest_contiguous(other), unacked)
			(peer["transport"] as LoopbackTransport).send(other, packet.encode())


func _order_summary(a_orders: Array[PlayerOrder]) -> Array:
	var out: Array = []
	for order: PlayerOrder in a_orders:
		out.append("%d:%s" % [order.commander_id, order.data["ability"]])
	return out
