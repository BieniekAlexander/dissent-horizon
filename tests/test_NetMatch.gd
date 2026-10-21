extends GutTest

## A networked match in a real scenario: the world is held from its first frame until every peer
## has loaded the same map, a different map is refused, and a match started through the barrier
## plays back, un-networked, digest for digest. The other peer is this test — a NetSession and a
## Lockstep with no scenario, over the loopback network.
## gdd/systems/commands/netplay.md §Rules (tick 0 runs only once every peer reports loaded).

const HARNESS: String = "res://scenes/harnesses/test_kamikaze_cluster.tscn"
const SEED: int = 7
const BUILD: String = "build"
## The test's peer hosts the match and plays commander 1; the scenario's machine plays 2.
const HOST: int = 1
const LOCAL: int = 2
const SEATS: Dictionary = {HOST: 1, LOCAL: 2}
const DELAY_TICKS: int = 2
## Frames the world is watched while it should be held.
const HELD_FRAMES: int = 20
## Ticks the started match is played for, and when the scenario's player gives an order.
const RUN_TICKS: int = 400
const ORDER_TICK: int = 120
## The tick the test's peer claims a different digest for (one the scenario digests: a whole
## second), and the frames it is given to notice.
const DESYNC_TICK: int = 60
## The silent-peer case: when the test's peer goes quiet, how soon it forfeits here, how long the
## test waits in all, and how far the match must run on afterwards.
const SILENT_AFTER_TICK: int = 30
const FORFEIT_TEST_SECONDS: float = 1.5
const SILENCE_WAIT_SECONDS: float = 20.0
const PLAYED_ON_TICKS: int = 60
const DESYNC_FRAMES: int = 400


## The scenario's machine and the test's peer, wired together.
class Wiring:
	var network := LoopbackNetwork.new()
	var match_node: NetMatch
	var host_session: NetSession
	var host_lockstep: Lockstep = null
	var host_turns: NetTransport
	var host_digests: NetTransport
	var host_tick: int = 0
	## The test's peer goes quiet: it runs and sends nothing, as a machine whose connection died.
	var is_silent: bool = false
	## Held, because the channels hold their mux weakly.
	var muxes: Array[TransportMux] = []

	func _init() -> void:
		var local_mux := TransportMux.new(network.endpoint(LOCAL))
		var host_mux := TransportMux.new(network.endpoint(HOST))
		muxes = [local_mux, host_mux]
		match_node = NetMatch.new(
			NetSession.new(local_mux.channel(TransportMux.SESSION), HOST, BUILD),
			local_mux.channel(TransportMux.TURNS),
			null,
			local_mux.channel(TransportMux.DIGESTS)
		)
		host_session = NetSession.new(host_mux.channel(TransportMux.SESSION), HOST, BUILD)
		host_session.offer_match({}, SEATS, TimeUtils.seconds_from_ticks(DELAY_TICKS))
		host_turns = host_mux.channel(TransportMux.TURNS)
		host_digests = host_mux.channel(TransportMux.DIGESTS)

	## One frame of the test's peer: its session, and once both have started, its turns.
	func step() -> void:
		if is_silent:
			network.step()
			return
		host_session.pump()
		if host_lockstep == null and host_session.is_ready():
			host_lockstep = Lockstep.new(
				host_turns, HOST, {LOCAL: LOCAL}, TimeUtils.seconds_from_ticks(DELAY_TICKS)
			)
			host_session.mark_started()
		if host_lockstep != null:
			host_lockstep.seal(host_tick)
			host_lockstep.pump()
			if host_lockstep.can_run(host_tick):
				host_lockstep.take(host_tick)
				host_tick += 1
		network.step()


func test_the_world_is_held_until_every_peer_has_loaded() -> void:
	var wiring := Wiring.new()
	var scenario: Scenario = await _boot(wiring.match_node)
	for frame: int in HELD_FRAMES:
		wiring.step()
		await get_tree().physics_frame
	assert_eq(scenario.tick, 0, "no tick runs while a peer is loading")
	assert_false(wiring.match_node.has_started())
	wiring.host_session.mark_loaded(MapDigest.of(scenario))
	watch_signals(wiring.match_node)
	for frame: int in HELD_FRAMES * 3:
		wiring.step()
		await get_tree().physics_frame
	assert_signal_emitted(wiring.match_node, "started")
	assert_gt(scenario.tick, 0, "the match runs once every peer has loaded")
	await _tear_down(scenario)


func test_a_different_map_is_refused_and_the_world_stays_held() -> void:
	var wiring := Wiring.new()
	var scenario: Scenario = await _boot(wiring.match_node)
	wiring.host_session.mark_loaded("not-this-map")
	watch_signals(wiring.match_node)
	for frame: int in HELD_FRAMES:
		wiring.step()
		await get_tree().physics_frame
	assert_signal_emitted(wiring.match_node, "refused")
	assert_string_contains(
		str(get_signal_parameters(wiring.match_node, "refused")[0]), "different map"
	)
	assert_eq(scenario.tick, 0)
	await _tear_down(scenario)


## The world is held from the scenario's very first frame, with the navigation server off, while
## the map is still finishing its first navmesh build: the match must still be the one an
## un-networked boot plays.
func test_a_match_started_through_the_barrier_plays_back_identically() -> void:
	var wiring := Wiring.new()
	var scenario: Scenario = await _boot(wiring.match_node)
	var is_loaded_by_host: bool = false
	var has_given_order: bool = false
	for frame: int in RUN_TICKS * 4:
		if scenario.tick >= RUN_TICKS:
			break
		if not is_loaded_by_host and frame >= HELD_FRAMES:
			wiring.host_session.mark_loaded(MapDigest.of(scenario))
			is_loaded_by_host = true
		if scenario.tick == ORDER_TICK and not has_given_order:
			has_given_order = true
			_give_order(scenario)
		wiring.step()
		await get_tree().physics_frame
	var recording := ReplayFile.from_bytes(scenario.recorder.replay.to_bytes())
	var reached: int = scenario.tick
	await _tear_down(scenario)
	assert_gte(reached, RUN_TICKS, "the match ran")
	var orders: Array = recording.records.filter(
		func(r: Dictionary) -> bool: return r.get("type") == ReplayRecorder.ORDER_TYPE
	)
	assert_eq(orders.size(), 1, "the player's order was played and recorded")
	var playback: Scenario = await _boot(null, recording)
	for frame: int in RUN_TICKS:
		await get_tree().physics_frame
	var drift: int = playback.recorder.first_drift_tick
	await _tear_down(playback)
	assert_eq(drift, -1, "the playback never differed from the recording")


## A peer whose simulation reads differently ends the match: the world is held for good, and
## this machine's state for that tick is written out for diffing.
func test_a_differing_digest_ends_the_match_as_a_desync() -> void:
	var wiring := Wiring.new()
	var scenario: Scenario = await _boot(wiring.match_node)
	watch_signals(wiring.match_node)
	var lied: bool = false
	for frame: int in DESYNC_FRAMES:
		if frame == 2:
			wiring.host_session.mark_loaded(MapDigest.of(scenario))
		if not lied and scenario.tick > DESYNC_TICK:
			lied = true
			var packet: PackedByteArray = (
				JSON
				. stringify({"v": DesyncCheck.WIRE_VERSION, "digests": [[DESYNC_TICK, "not-it"]]})
				. to_utf8_buffer()
			)
			wiring.host_digests.send(LOCAL, packet)
		wiring.step()
		await get_tree().physics_frame
		if (
			wiring.match_node.lockstep != null
			and get_signal_emit_count(wiring.match_node, "desynced") > 0
		):
			break
	assert_signal_emitted(wiring.match_node, "desynced")
	var params: Array = get_signal_parameters(wiring.match_node, "desynced")
	assert_eq(params[0], DESYNC_TICK)
	assert_true(FileAccess.file_exists(params[1]), "this machine's state is written")
	var held_at: int = scenario.tick
	for frame: int in HELD_FRAMES:
		wiring.step()
		await get_tree().physics_frame
	assert_eq(scenario.tick, held_at, "the world is held for good")
	DirAccess.remove_absolute(params[1])
	await _tear_down(scenario)


## A peer that goes silent is named in the readout while the match waits, then forfeits — here
## after FORFEIT_TEST_SECONDS rather than the real thirty — and the match plays on without it.
func test_a_silent_peer_is_named_then_forfeits_and_the_match_plays_on() -> void:
	var wiring := Wiring.new()
	wiring.match_node.forfeit_after_seconds = FORFEIT_TEST_SECONDS
	var scenario: Scenario = await _boot(wiring.match_node)
	var deadline: int = Time.get_ticks_msec() + int(SILENCE_WAIT_SECONDS * 1000.0)
	var readout: String = ""
	var forfeited_at: int = -1
	while Time.get_ticks_msec() < deadline:
		if wiring.host_tick == 0 and scenario.tick == 0:
			wiring.host_session.mark_loaded(MapDigest.of(scenario))
		if scenario.tick >= SILENT_AFTER_TICK:
			wiring.is_silent = true
		wiring.step()
		await get_tree().physics_frame
		if wiring.match_node.waiting_readout() != "":
			readout = wiring.match_node.waiting_readout()
		if forfeited_at < 0 and scenario.is_eliminated(HOST):
			forfeited_at = scenario.tick
		if forfeited_at >= 0 and scenario.tick >= forfeited_at + PLAYED_ON_TICKS:
			break
	assert_string_contains(
		readout, "Waiting for Player %d" % HOST, "the readout named who it waited on"
	)
	assert_gte(forfeited_at, 0, "the silent player forfeited")
	assert_gte(scenario.tick, forfeited_at + PLAYED_ON_TICKS, "and the match played on")
	assert_eq(wiring.match_node.waiting_readout(), "", "with nothing left to wait on")
	await _tear_down(scenario)


func _boot(a_match: NetMatch, a_recording: ReplayFile = null) -> Scenario:
	gut.error_tracker.disabled = true
	var scenario := (load(HARNESS) as PackedScene).instantiate() as Scenario
	scenario.rng_seed = SEED
	scenario.replay_to_play = a_recording
	if a_match != null:
		scenario.add_child(a_match)
	await get_tree().process_frame
	add_child(scenario)
	return scenario


func _tear_down(a_scenario: Scenario) -> void:
	a_scenario.trigger_manager().simulation_clock.clear()
	a_scenario.free()
	await get_tree().process_frame
	gut.error_tracker.disabled = false


## Send every mobile piece commander 2 owns somewhere, as its player would.
func _give_order(a_scenario: Scenario) -> void:
	var movers: Array = a_scenario.commanders[LOCAL].get_children().filter(
		func(n: Node) -> bool: return n is Actor and (n as Actor).can_move()
	)
	var message := CommandMessage.new(a_scenario.map, null, null, Vector3(6.0, 0.0, -6.0))
	a_scenario.order_stream.submit(PlayerOrder.command(LOCAL, MoveCommand, movers, message, {}))
