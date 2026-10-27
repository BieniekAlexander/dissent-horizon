extends GutTest

## A SAVED GAME restores EXACTLY (SimulationSnapshot): the match after a load is the match that
## would have been played. Two checks, the first finding what a restore missed and the second what
## a snapshot never held:
##   * the restored world, captured again at once, is the snapshot it was restored from;
##   * from there it plays the same match as the original, digest for digest, and is the same
##     world again, field for field, some ticks on.
## gdd/systems/commands/saved-games.md §The snapshot. The scenario is a HARNESS; a long bot match
## saved and loaded many times is tools/snapshot/save_load_probe.tscn.

const HARNESS: String = "res://scenes/harnesses/human_vs_bot.tscn"
const SEED: int = 11
## Past the opening force's deferred spawn, so the order moves units the save then holds mid-path.
const ORDER_TICK: int = 300
const SAVE_TICK: int = 600
## How long the two matches are compared after the save, and how often.
const COMPARE_UNTIL_TICK: int = 900
const COMPARE_EVERY_TICKS: int = 30
## When, after the save, the two worlds are compared whole again.
const RECAPTURE_TICK: int = 630
## Bounds the wait for the restore, in frames.
const RESUME_FRAMES: int = 600
## How many differing fields a failure lists.
const DIFFS_SHOWN: int = 25

var _directory: String = ""


func before_each() -> void:
	_directory = "user://test_snapshot_%d/" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_directory)


func after_each() -> void:
	for file: String in DirAccess.get_files_at(_directory):
		DirAccess.remove_absolute(_directory.path_join(file))
	DirAccess.remove_absolute(_directory)


func test_a_restored_match_is_the_saved_match_and_plays_on_identically() -> void:
	var path: String = _directory.path_join("round_trip.sav")
	var original: Scenario = await _boot()
	var digests: Dictionary = {}
	var recaptured: Dictionary = {}
	var is_ordered: bool = false
	while original.tick < COMPARE_UNTIL_TICK:
		await get_tree().physics_frame
		if original.tick == ORDER_TICK and not is_ordered:
			is_ordered = true
			_give_order(original)
		if original.tick == SAVE_TICK and not FileAccess.file_exists(path):
			original.request_save(path)
		if original.tick >= SAVE_TICK and original.tick % COMPARE_EVERY_TICKS == 0:
			digests[original.tick] = SimulationDigest.state_string(original)
		if original.tick == RECAPTURE_TICK and recaptured.is_empty():
			recaptured = SnapshotDiff.normalised(SimulationSnapshot.capture(original))
	await _tear_down(original)
	assert_true(FileAccess.file_exists(path), "the match was saved")

	var save: ReplayFile = ReplayFile.read(path)
	assert_eq(SaveGame.refusal_to_load(save, path), "", "the save loads")
	var built: Dictionary = SaveGame.prepare_resume(path)
	var resumed: Scenario = built["scenario"]
	await get_tree().process_frame
	add_child(resumed)
	# Captured in the hand-over itself, before the frame runs the next tick.
	var matched: Array = []
	var at_restore: Array = []
	(resumed.get_node("SaveResume") as SaveResume).resumed.connect(
		func(m: bool) -> void:
			matched.append(m)
			at_restore.append([resumed.tick, SimulationSnapshot.capture(resumed)])
	)
	for frame: int in RESUME_FRAMES:
		if not matched.is_empty():
			break
		await get_tree().physics_frame
	assert_eq(at_restore.size(), 1, "the save was restored")
	if at_restore.is_empty():
		await _tear_down(resumed)
		return
	assert_eq(at_restore[0][0], SAVE_TICK, "to the tick it was saved on")
	_assert_same(
		SnapshotDiff.normalised(at_restore[0][1]),
		SnapshotDiff.normalised(SaveGame.snapshot_of(save)),
		"the restored world is the saved one",
		SnapshotDiff.SERVER_READS
	)
	assert_eq(matched, [true], "and its digest is the saved one")

	while resumed.tick < COMPARE_UNTIL_TICK:
		if digests.has(resumed.tick):
			var drift: String = SnapshotDiff.first_state_difference(
				SimulationDigest.state_string(resumed), digests[resumed.tick]
			)
			if not drift.is_empty():
				fail_test("drifted at tick %d: %s" % [resumed.tick, drift])
				break
		if resumed.tick == RECAPTURE_TICK:
			_assert_same(
				SnapshotDiff.normalised(SimulationSnapshot.capture(resumed)),
				recaptured,
				"the same world %d ticks after the load" % (RECAPTURE_TICK - SAVE_TICK)
			)
		await get_tree().physics_frame
	await _tear_down(resumed)


func _boot() -> Scenario:
	gut.error_tracker.disabled = true
	var scenario := (load(HARNESS) as PackedScene).instantiate() as Scenario
	scenario.rng_seed = SEED
	await get_tree().process_frame
	add_child(scenario)
	return scenario


func _tear_down(scenario: Scenario) -> void:
	scenario.free()
	await get_tree().process_frame
	gut.error_tracker.disabled = false


func _give_order(scenario: Scenario) -> void:
	var player: int = scenario.local_player().id
	var movers: Array = scenario.commanders[player].get_children().filter(
		func(n: Node) -> bool: return n is Actor and (n as Actor).can_move()
	)
	var message := CommandMessage.new(scenario.map, null, null, Vector3(6.0, 0.0, -6.0))
	scenario.order_stream.submit(PlayerOrder.command(player, MoveCommand, movers, message, {}))


func _assert_same(
	a_actual: Dictionary, a_expected: Dictionary, a_what: String, a_ignored: Array[String] = []
) -> void:
	var found: Array[String] = SnapshotDiff.differences(a_actual, a_expected, a_ignored)
	assert_eq(
		found.size(),
		0,
		(
			"%s; %d fields differ, first:\n  %s"
			% [a_what, found.size(), "\n  ".join(found.slice(0, DIFFS_SHOWN))]
		)
	)
