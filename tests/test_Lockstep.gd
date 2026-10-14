extends GutTest

## The lockstep loop over the loopback network: an order applies on the tick it was given plus the
## input delay, on every peer, and a peer runs a tick only once every peer's turn for it is in.
## Each peer is driven the way OrderStream drives it — seal, pump, then run the tick if it may.
## gdd/systems/commands/netplay.md §The model.

## The input delay every test but the single-machine one plays at, in ticks.
const DELAY_TICKS: int = 3
## Ticks a match is run for; enough for every scheduled order to land with room to spare.
const MATCH_TICKS: int = 60


## One simulated machine: its session, the next tick it will run, and what it applied, by tick.
class Peer:
	var lockstep: Lockstep
	var next_tick: int = 0
	var applied: Dictionary = {}
	var stalled_frames: int = 0
	## Stalls once running: the first tick always waits one one-way latency for the first turns.
	var stalled_frames_running: int = 0
	## Tick -> orders to give just before that tick's frame, as a player would between frames.
	var to_give: Dictionary = {}
	## A silent peer runs nothing and sends nothing, as a machine whose connection has gone.
	var is_silent: bool = false

	func _init(a_lockstep: Lockstep) -> void:
		lockstep = a_lockstep

	func frame() -> void:
		if is_silent:
			return
		for order: PlayerOrder in to_give.get(next_tick, []):
			lockstep.submit(order)
		to_give.erase(next_tick)
		lockstep.seal(next_tick)
		lockstep.pump()
		if not lockstep.can_run(next_tick):
			stalled_frames += 1
			if next_tick > 0:
				stalled_frames_running += 1
			return
		var encoded: Array = []
		for order: PlayerOrder in lockstep.take(next_tick):
			encoded.append(JSON.stringify(order.to_dict()))
		applied[next_tick] = encoded
		next_tick += 1


## Peers 1..`a_count` on one network, peer i commanding commander i, all at DELAY_TICKS.
func _peers(a_network: LoopbackNetwork, a_count: int, a_delay_ticks: int = DELAY_TICKS) -> Array:
	var out: Array = []
	for i: int in range(1, a_count + 1):
		a_network.endpoint(i)
	for i: int in range(1, a_count + 1):
		var others: Dictionary = {}
		for j: int in range(1, a_count + 1):
			if j != i:
				others[j] = j
		var session := Lockstep.new(
			a_network.endpoint(i), i, others, TimeUtils.seconds_from_ticks(a_delay_ticks)
		)
		out.append(Peer.new(session))
	return out


## Run every peer until each has applied MATCH_TICKS ticks, stepping the network once per frame.
## Bounded, so a deadlock fails the test instead of hanging the suite.
func _run(a_network: LoopbackNetwork, a_peers: Array) -> void:
	for frame: int in MATCH_TICKS * 20:
		var done: bool = true
		for peer: Peer in a_peers:
			if peer.next_tick < MATCH_TICKS:
				peer.frame()
				done = false
		a_network.step()
		if done:
			return


func _order(a_commander_id: int, a_tag: float) -> PlayerOrder:
	# A float that a careless encoding would round, so every peer must apply the decoded form.
	return PlayerOrder.new(
		PlayerOrder.Kind.HOLD_FIRE, a_commander_id, {"actors": [7], "tag": a_tag + 0.1 + 0.2}
	)


func _give(a_peer: Peer, a_tick: int, a_order: PlayerOrder) -> void:
	if not a_peer.to_give.has(a_tick):
		a_peer.to_give[a_tick] = []
	a_peer.to_give[a_tick].append(a_order)


func _ticks_holding_orders(a_peer: Peer) -> Array:
	return a_peer.applied.keys().filter(
		func(t: int) -> bool: return not a_peer.applied[t].is_empty()
	)


func test_alone_with_no_delay_an_order_applies_on_the_tick_it_is_given() -> void:
	var network := LoopbackNetwork.new()
	var peer: Peer = _peers(network, 1, 0)[0]
	_give(peer, 5, _order(1, 1.0))
	_run(network, [peer])
	assert_eq(_ticks_holding_orders(peer), [5], "as a single-machine stream applies it")
	assert_eq(peer.stalled_frames, 0)


func test_an_order_applies_after_the_input_delay_on_every_peer() -> void:
	var network := LoopbackNetwork.new()
	var peers: Array = _peers(network, 2)
	_give(peers[0], 10, _order(1, 1.0))
	_give(peers[1], 20, _order(2, 2.0))
	_run(network, peers)
	for peer: Peer in peers:
		assert_eq(_ticks_holding_orders(peer), [10 + DELAY_TICKS, 20 + DELAY_TICKS])
	assert_eq(peers[0].applied, peers[1].applied, "the same orders on the same ticks")


func test_a_link_faster_than_the_delay_never_stalls() -> void:
	var network := LoopbackNetwork.new()
	network.latency_max = DELAY_TICKS - 1
	var peers: Array = _peers(network, 2)
	_give(peers[0], 4, _order(1, 1.0))
	_run(network, peers)
	assert_eq(peers[0].stalled_frames_running + peers[1].stalled_frames_running, 0)


func test_a_slow_lossy_link_stalls_but_every_peer_applies_the_same_ticks() -> void:
	var network := LoopbackNetwork.new(20261014)
	network.latency_min = DELAY_TICKS + 2
	network.latency_max = DELAY_TICKS + 8
	network.loss = 0.3
	network.duplication = 0.2
	var peers: Array = _peers(network, 2)
	for t: int in range(0, 40, 3):
		_give(peers[t % 2], t, _order(1 + t % 2, float(t)))
	_run(network, peers)
	assert_gt(peers[0].stalled_frames_running, 0, "the delay cannot hide this link")
	assert_eq(peers[0].applied.size(), MATCH_TICKS)
	assert_eq(peers[0].applied, peers[1].applied)
	var given: int = range(0, 40, 3).size()
	var applied: int = 0
	for t: int in peers[0].applied:
		applied += peers[0].applied[t].size()
	assert_eq(applied, given, "an order given while stalled is sealed into a later turn, not lost")


func test_three_peers_in_a_mesh_apply_the_same_ticks() -> void:
	var network := LoopbackNetwork.new(7)
	network.latency_max = 6
	network.loss = 0.2
	var peers: Array = _peers(network, 3)
	_give(peers[0], 2, _order(1, 1.0))
	_give(peers[1], 2, _order(2, 2.0))
	_give(peers[2], 9, _order(3, 3.0))
	_run(network, peers)
	assert_eq(peers[0].applied, peers[1].applied)
	assert_eq(peers[1].applied, peers[2].applied)
	var first_tick: Array = peers[0].applied[2 + DELAY_TICKS]
	assert_eq(first_tick.size(), 2)
	assert_string_contains(first_tick[0], '"commander":1', "by commander id, whoever arrived first")


func test_an_order_for_another_commander_is_not_sealed() -> void:
	var network := LoopbackNetwork.new()
	var peer: Peer = _peers(network, 1, 0)[0]
	_give(peer, 2, _order(2, 1.0))
	_run(network, [peer])
	assert_eq(_ticks_holding_orders(peer), [])


func test_a_packet_is_believed_only_from_the_peer_whose_commander_it_claims() -> void:
	var network := LoopbackNetwork.new()
	var peers: Array = _peers(network, 2, 0)
	var forged_turn := Turn.new(0, 1, [_order(1, 9.0)] as Array[PlayerOrder])
	var forged := TurnPacket.new(1, -1, [forged_turn] as Array[Turn])
	network.endpoint(2).send(1, forged.encode())
	network.step()
	var lockstep: Lockstep = peers[0].lockstep
	lockstep.seal(0)
	lockstep.pump()
	assert_false(lockstep.can_run(0), "peer 2 never sent its own turn")
	assert_eq(lockstep.waiting_on(0), [2] as Array[int])


# --- A silent peer forfeits ------------------------------------------------------------------

## The frame peer 3 goes silent on, and the frames after it peers 1 and 2 each vote it out — at
## different moments, as two machines' timeouts do.
const SILENT_FRAME: int = 20
const VOTE_FRAMES: Dictionary = {1: 40, 2: 55}


func _forfeits(a_peer: Peer, a_commander: int) -> Array:
	var out: Array = []
	for tick: int in a_peer.applied:
		for encoded: String in a_peer.applied[tick]:
			var order: Dictionary = JSON.parse_string(encoded)
			if order["kind"] == "FORFEIT" and int(order["commander"]) == a_commander:
				out.append(tick)
	return out


## Run until the remaining peers finish, peer `a_silent` going silent at SILENT_FRAME and each other
## peer voting it out at its VOTE_FRAMES frame (or at once, after SILENT_FRAME, if not listed).
func _run_with_silent(
	a_network: LoopbackNetwork, a_peers: Array, a_silent: int, a_returns_at: int = -1
) -> void:
	for frame: int in MATCH_TICKS * 40:
		var done: bool = true
		for i: int in a_peers.size():
			var peer: Peer = a_peers[i]
			var id: int = i + 1
			if id == a_silent:
				peer.is_silent = (
					frame >= SILENT_FRAME and (a_returns_at < 0 or frame < a_returns_at)
				)
				peer.frame()
				continue
			if frame == int(VOTE_FRAMES.get(id, SILENT_FRAME + 1)):
				peer.lockstep.vote_out(a_silent)
			if peer.next_tick < MATCH_TICKS:
				peer.frame()
				done = false
		a_network.step()
		if done:
			return


func test_a_silent_peer_forfeits_on_one_tick_for_everyone_left() -> void:
	var network := LoopbackNetwork.new(5)
	network.latency_max = 2
	var peers: Array = _peers(network, 3)
	_run_with_silent(network, peers, 3)
	for id: int in [1, 2]:
		assert_eq(peers[id - 1].next_tick, MATCH_TICKS, "peer %d plays on" % id)
	assert_eq(peers[0].applied, peers[1].applied, "the same match, forfeit included")
	var forfeits: Array = _forfeits(peers[0], 3)
	assert_eq(forfeits.size(), 1, "commander 3 forfeits once")
	assert_eq(peers[0].lockstep.forfeit_tick(3), forfeits[0])
	assert_eq(peers[1].lockstep.forfeit_tick(3), forfeits[0])


func test_a_lossy_link_still_fences_on_one_tick() -> void:
	var network := LoopbackNetwork.new(17)
	network.latency_max = 5
	network.loss = 0.3
	var peers: Array = _peers(network, 3)
	_run_with_silent(network, peers, 3)
	assert_eq(peers[0].applied, peers[1].applied)
	assert_eq(_forfeits(peers[0], 3).size(), 1)


func test_alone_with_a_silent_opponent_the_forfeit_is_at_once() -> void:
	var network := LoopbackNetwork.new()
	var peers: Array = _peers(network, 2)
	_run_with_silent(network, peers, 2)
	assert_eq(peers[0].next_tick, MATCH_TICKS)
	assert_eq(_forfeits(peers[0], 2).size(), 1)


## The frame the voted-out peer comes back on, its orders with it.
const RETURN_FRAME: int = 120


func test_a_peer_voted_out_is_not_heard_from_again() -> void:
	var network := LoopbackNetwork.new()
	var peers: Array = _peers(network, 2)
	for tick: int in range(0, MATCH_TICKS):
		_give(peers[1], tick, _order(2, float(tick)))
	_run_with_silent(network, peers, 2, RETURN_FRAME)
	assert_gt(peers[1].stalled_frames, 0, "it came back, and found nobody playing with it")
	var fence: int = peers[0].lockstep.forfeit_tick(2)
	var heard_after: int = 0
	for tick: int in peers[0].applied:
		if tick > fence:
			for encoded: String in peers[0].applied[tick]:
				if '"commander":2' in encoded:
					heard_after += 1
	assert_gte(fence, 0)
	assert_eq(heard_after, 0, "nothing it sent after its fence applied")
