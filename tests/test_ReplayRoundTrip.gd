extends GutTest

## Record a short scripted match, play it back, and require every state digest to match: the
## property replay rests on. gdd/systems/commands/recording-and-replay.md §Testing.
##
## The scenario is a HARNESS: what it contains does not matter, only that a recording of it
## plays back the same. Its bots are left live — they re-derive their orders from the seed, as
## they will in a real replay — and the "player" is this test, feeding orders into the stream.
##
## Each boot enters the tree at idle time, as the game's scene loader adds a scenario: one added
## during the physics step plays the whole match a tick out of phase (selfplay-harness.md
## §Determinism).

const HARNESS: String = "res://scenes/scenarios/test/test_kamikaze_cluster.tscn"
const SEED: int = 7
## About a minute of play.
const RUN_TICKS: int = 1800
## When the scripted orders are given, and by whom: the cluster's owner is told to walk away.
const ORDER_TICKS: Array[int] = [90, 600]
const ORDER_COMMANDER: int = 2


func test_a_recorded_match_plays_back_identically() -> void:
	var recording: ReplayFile = await _record()
	var orders: Array = recording.records.filter(
		func(r: Dictionary) -> bool: return r.get("type") == ReplayRecorder.ORDER_TYPE
	)
	var digests: Array = recording.records.filter(
		func(r: Dictionary) -> bool: return r.get("type") == ReplayRecorder.DIGEST_TYPE
	)
	assert_eq(orders.size(), ORDER_TICKS.size(), "every scripted order was recorded")
	assert_gt(digests.size(), RUN_TICKS / 60, "a digest every second")
	# Through the file format, as a real replay arrives.
	var from_disk: ReplayFile = ReplayFile.from_bytes(recording.to_bytes())
	var drift: int = await _play_back(from_disk)
	assert_eq(drift, -1, "the playback never differed from the recording")


## The check above can fail: a playback missing one of the player's orders plays a different
## match, and says where.
func test_a_playback_missing_an_order_reports_drift() -> void:
	var recording: ReplayFile = await _record()
	var tampered := ReplayFile.new()
	tampered.header = recording.header
	var dropped: bool = false
	for record: Dictionary in recording.records:
		if not dropped and record.get("type") == ReplayRecorder.ORDER_TYPE:
			dropped = true
			continue
		tampered.records.append(record)
	var drift: int = await _play_back(tampered)
	assert_gt(drift, ORDER_TICKS[0], "drift is reported after the missing order, not before")


func _record() -> ReplayFile:
	var scenario: Scenario = await _boot(null)
	for tick: int in RUN_TICKS:
		if ORDER_TICKS.has(scenario.tick):
			_give_order(scenario)
		await get_tree().physics_frame
	var recording: ReplayFile = scenario.recorder.replay
	await _tear_down(scenario)
	return recording


func _play_back(recording: ReplayFile) -> int:
	var scenario: Scenario = await _boot(recording)
	for tick: int in RUN_TICKS:
		await get_tree().physics_frame
	var drift: int = scenario.recorder.first_drift_tick
	await _tear_down(scenario)
	return drift


func _boot(recording: ReplayFile) -> Scenario:
	gut.error_tracker.disabled = true
	var scenario := (load(HARNESS) as PackedScene).instantiate() as Scenario
	scenario.rng_seed = SEED
	scenario.replay_to_play = recording
	await get_tree().process_frame
	add_child(scenario)
	return scenario


func _tear_down(scenario: Scenario) -> void:
	scenario.free()
	await get_tree().process_frame
	gut.error_tracker.disabled = false


## Send every builder the commander owns somewhere away from the cluster, as a player would.
func _give_order(scenario: Scenario) -> void:
	var builders: Array = scenario.commanders[ORDER_COMMANDER].get_children().filter(
		func(n: Node) -> bool: return n is Commandable and (n as Commandable).can_move()
	)
	var message := CommandMessage.new(scenario.map, null, null, Vector3(6.0, 0.0, -6.0))
	scenario.order_stream.submit(
		PlayerOrder.command(ORDER_COMMANDER, MoveCommand, builders, message, {})
	)
