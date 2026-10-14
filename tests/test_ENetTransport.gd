extends GutTest

## The peer-to-peer transport over real sockets on this machine: peers find each other by
## address, a stranger is refused, a dropped connection is dialled again, and two lockstep
## sessions over it apply the same orders on the same ticks.
## gdd/systems/commands/netplay.md §Decisions (transport).

const LOCALHOST: String = "127.0.0.1"
## How long a test waits for packets and connections that take real time. Bounded by the wall
## clock, not by frames: under --fixed-fps a frame budget lasts milliseconds.
const WAIT_SECONDS: float = 5.0
## Long enough for a stranger's dial to open and be refused, on this machine.
const REFUSAL_WAIT_SECONDS: float = 1.0
## The input delay the lockstep test plays at, and how many ticks it runs.
const DELAY_TICKS: int = 2
const MATCH_TICKS: int = 40

var _transports: Array[ENetTransport] = []


func after_each() -> void:
	for transport: ENetTransport in _transports:
		transport.close()
	_transports.clear()


## Peer `a_id` among `a_ids`, listening on a free port, dialling the peers below it at the ports
## in `a_ports` (id -> port).
func _open(a_id: int, a_ids: Array[int], a_ports: Dictionary, a_port: int = 0) -> ENetTransport:
	var dial: Dictionary = {}
	for id: int in a_ports:
		dial[id] = [LOCALHOST, int(a_ports[id])]
	var transport := ENetTransport.new(a_id, a_ids, dial)
	assert_eq(transport.open(a_port, LOCALHOST), OK)
	_transports.append(transport)
	return transport


## Service `a_transports` until `a_done` holds or the wait runs out; what each received is
## appended to `a_received` (transport -> Array). Returns whether `a_done` held.
func _service_until(
	a_transports: Array,
	a_done: Callable,
	a_received: Dictionary = {},
	a_wait_seconds: float = WAIT_SECONDS
) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(a_wait_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		for transport: ENetTransport in a_transports:
			var got: Array = transport.receive()
			if not a_received.has(transport):
				a_received[transport] = []
			a_received[transport].append_array(got)
		if a_done.call():
			return true
		await get_tree().process_frame
	return false


func _all_connected(a_transports: Array) -> bool:
	return a_transports.all(func(t: ENetTransport) -> bool: return t.is_connected_to_all())


func _each_received(a_transports: Array, a_received: Dictionary) -> bool:
	return a_transports.all(
		func(t: ENetTransport) -> bool: return not a_received.get(t, []).is_empty()
	)


func test_two_peers_connect_and_exchange_messages() -> void:
	var a: ENetTransport = _open(1, [1, 2], {})
	var b: ENetTransport = _open(2, [1, 2], {1: a.local_port()})
	assert_true(await _service_until([a, b], _all_connected.bind([a, b])), "connected")
	a.send(2, "to b".to_utf8_buffer())
	b.send(1, "to a".to_utf8_buffer())
	var received: Dictionary = {}
	assert_true(await _service_until([a, b], _each_received.bind([a, b], received), received))
	assert_eq(int(received[b][0][0]), 1, "named by the sender's peer id")
	assert_eq((received[b][0][1] as PackedByteArray).get_string_from_utf8(), "to b")
	assert_eq((received[a][0][1] as PackedByteArray).get_string_from_utf8(), "to a")


func test_three_peers_form_a_full_mesh() -> void:
	var ids: Array[int] = [1, 2, 3]
	var a: ENetTransport = _open(1, ids, {})
	var b: ENetTransport = _open(2, ids, {1: a.local_port()})
	var c: ENetTransport = _open(3, ids, {1: a.local_port(), 2: b.local_port()})
	assert_true(await _service_until([a, b, c], _all_connected.bind([a, b, c])))


func test_a_peer_not_in_the_session_is_refused() -> void:
	var a: ENetTransport = _open(1, [1, 2], {})
	var stranger: ENetTransport = _open(9, [1, 9], {1: a.local_port()})
	# Long enough for a dial to open and be refused; the stranger is then left dialling again.
	await _service_until([a, stranger], func() -> bool: return false, {}, REFUSAL_WAIT_SECONDS)
	assert_false(a.is_connected_to(9))
	assert_eq(a.remote_ids(), [2] as Array[int])


func test_a_dropped_connection_is_dialled_again() -> void:
	var a: ENetTransport = _open(1, [1, 2], {})
	var port: int = a.local_port()
	var b: ENetTransport = _open(2, [1, 2], {1: port})
	assert_true(await _service_until([a, b], _all_connected.bind([a, b])))
	a.close()
	assert_true(
		await _service_until([b], func() -> bool: return not b.is_connected_to(1)), "dropped"
	)
	assert_eq(a.open(port, LOCALHOST), OK)
	assert_true(await _service_until([a, b], _all_connected.bind([a, b])), "dialled again")


func test_two_lockstep_sessions_over_enet_apply_the_same_ticks() -> void:
	var a: ENetTransport = _open(1, [1, 2], {})
	var b: ENetTransport = _open(2, [1, 2], {1: a.local_port()})
	assert_true(await _service_until([a, b], func() -> bool: return b.is_connected_to_all()))
	var delay: float = TimeUtils.seconds_from_ticks(DELAY_TICKS)
	var sessions: Array[Lockstep] = [
		Lockstep.new(a, 1, {2: 2}, delay), Lockstep.new(b, 2, {1: 1}, delay)
	]
	var next_tick: Array[int] = [0, 0]
	var applied: Array[Dictionary] = [{}, {}]
	sessions[0].submit(PlayerOrder.new(PlayerOrder.Kind.HOLD_FIRE, 1, {"actors": [3]}))
	var deadline: int = Time.get_ticks_msec() + int(WAIT_SECONDS * 1000.0)
	while (
		(next_tick[0] < MATCH_TICKS or next_tick[1] < MATCH_TICKS)
		and Time.get_ticks_msec() < deadline
	):
		for i: int in 2:
			if next_tick[i] >= MATCH_TICKS:
				continue
			sessions[i].seal(next_tick[i])
			sessions[i].pump()
			if sessions[i].can_run(next_tick[i]):
				applied[i][next_tick[i]] = sessions[i].take(next_tick[i]).map(
					func(o: PlayerOrder) -> String: return JSON.stringify(o.to_dict())
				)
				next_tick[i] += 1
		await get_tree().process_frame
	assert_eq(next_tick, [MATCH_TICKS, MATCH_TICKS] as Array[int], "both ran the match")
	assert_eq(applied[0], applied[1], "the same orders on the same ticks")
	assert_eq(applied[0][DELAY_TICKS].size(), 1, "the order applied after the input delay")
