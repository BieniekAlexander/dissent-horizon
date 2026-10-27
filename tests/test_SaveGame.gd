extends GutTest

## A SAVED GAME (SaveGame): saved between ticks from the replay's record of orders, and loaded by
## re-simulating to the tick it was saved on, where the player plays on. The property it rests on:
## the resumed match is the saved one, digest for digest, and plays on as the original did.
## gdd/systems/commands/saved-games.md. The scenario is a HARNESS; its content does not matter.

const HARNESS: String = "res://scenes/harnesses/human_vs_bot.tscn"
const SEED: int = 11
## Past the opening force's deferred spawn.
const ORDER_TICK: int = 300
const SAVE_TICK: int = 600
## The original runs on past the save; the resumed match must arrive at the same state here.
const COMPARE_TICK: int = 900
## Bounds the wait for a load's re-simulation, in frames (one tick each in the suite).
const RESUME_FRAMES: int = 2000

var _directory: String = ""


func before_each() -> void:
	_directory = "user://test_saves_%d/" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_directory)


func after_each() -> void:
	for file: String in DirAccess.get_files_at(_directory):
		DirAccess.remove_absolute(_directory.path_join(file))
	DirAccess.remove_absolute(_directory)
	EventAutosave.directory = SaveGame.DIRECTORY


func test_a_loaded_save_resumes_the_saved_match_and_plays_on_identically() -> void:
	var scenario: Scenario = await _boot()
	var save: ReplayFile = null
	var digest_at_compare: String = ""
	while scenario.tick < COMPARE_TICK:
		if scenario.tick == ORDER_TICK:
			_give_order(scenario)
		if scenario.tick == SAVE_TICK and save == null:
			save = SaveGame.of(scenario)
		await get_tree().physics_frame
	digest_at_compare = SimulationDigest.of(scenario)
	await _tear_down(scenario)
	assert_not_null(save, "the match could be saved")
	assert_eq(SaveGame.save_tick(save), SAVE_TICK)

	var loaded: ReplayFile = ReplayFile.from_bytes(save.to_bytes())
	var built: Dictionary = ReplayLibrary.build_scenario_for(loaded)
	var resumed: Scenario = built["scenario"]
	resumed.save_to_resume = loaded
	await get_tree().process_frame
	add_child(resumed)
	var matched: Array = []
	(resumed.get_node("SaveResume") as SaveResume).resumed.connect(
		func(m: bool) -> void: matched.append(m)
	)
	for frame: int in RESUME_FRAMES:
		if not matched.is_empty():
			break
		await get_tree().physics_frame
	assert_eq(matched, [true], "re-simulated to the saved state")
	assert_false(resumed.order_stream.is_playback(), "and the player plays on")
	while resumed.tick < COMPARE_TICK:
		await get_tree().physics_frame
	assert_eq(SimulationDigest.of(resumed), digest_at_compare, "the same match from there on")
	await _tear_down(resumed)


func test_no_tick_is_counted_before_the_navmesh_is_first_built() -> void:
	# What arms on navmesh_ready (every scripted trigger, and so a mission's opening dialogs)
	# must land on the same tick in a match and in its re-simulation, however each entered the
	# tree, or a save's recorded dialog answers never meet their dialogs.
	gut.error_tracker.disabled = true
	var scenario := (load(HARNESS) as PackedScene).instantiate() as Scenario
	add_child(scenario)
	var clock: SimulationClock = scenario.trigger_manager().simulation_clock
	var nav: NavManager = scenario.map.nav_manager
	var ticks_at_build: Array = []
	nav.first_built.connect(func() -> void: ticks_at_build.append(scenario.tick))
	assert_true(clock.is_held_by(SimulationClock.REASON_BOOT), "held from the first frame")
	for frame: int in 10:
		if not ticks_at_build.is_empty():
			break
		await get_tree().physics_frame
	assert_eq(ticks_at_build, [0], "the first build lands before tick 0 is counted")
	assert_false(clock.is_held_by(SimulationClock.REASON_BOOT), "and releases the world")
	await _tear_down(scenario)


func test_an_autosave_is_written_between_ticks_to_the_one_autosave() -> void:
	EventAutosave.directory = _directory
	var scenario: Scenario = await _boot()
	for frame: int in 60:
		await get_tree().physics_frame
	var event := EventAutosave.new()
	autofree(event)
	event.execute(scenario.trigger_manager())
	var asked_at: int = scenario.tick
	await get_tree().physics_frame
	var written: ReplayFile = ReplayFile.read(SaveGame.autosave_path(_directory))
	assert_not_null(written, "the autosave was written")
	assert_eq(SaveGame.save_tick(written), asked_at, "at the start of the next tick")
	await _tear_down(scenario)


func test_a_replay_cannot_be_loaded_as_a_save() -> void:
	var replay := ReplayFile.new()
	replay.header = {"type": ReplayFile.HEADER_TYPE, "version": ReplayFile.current_version()}
	assert_string_contains(SaveGame.refusal_to_load(replay, "x.sav"), "not a saved game")


func test_a_save_from_another_version_is_refused() -> void:
	var save := ReplayFile.new()
	save.header = {"type": ReplayFile.HEADER_TYPE, "version": "old", SaveGame.SAVE_TICK_KEY: 5}
	assert_string_contains(SaveGame.refusal_to_load(save, "x.sav"), "another version")


func test_a_save_name_is_checked() -> void:
	assert_eq(SaveGame.valid_name("  Before the fork "), "Before the fork")
	assert_eq(SaveGame.valid_name(""), "")
	assert_eq(SaveGame.valid_name(SaveGame.AUTOSAVE_NAME), "", "the autosave's name is its own")
	assert_eq(SaveGame.valid_name("../escape"), "", "no paths")


func test_saves_are_listed_newest_first_with_the_autosave_named() -> void:
	for name: String in ["alpha", SaveGame.AUTOSAVE_NAME]:
		var file := FileAccess.open(SaveGame.path_for(name, _directory), FileAccess.WRITE)
		file.store_string("x")
		file.close()
	var labels: Array = SaveGame.entries(_directory).map(SaveGame.label_for)
	assert_has(labels, "alpha")
	assert_has(labels, "Autosave")


func test_the_panel_saves_under_a_name_and_asks_before_overwriting() -> void:
	var scenario: Scenario = await _boot()
	for frame: int in 30:
		await get_tree().physics_frame
	var panel := SavesPanel.new()
	panel.directory = _directory
	panel.can_save = true
	panel.scenario = scenario
	add_child_autofree(panel)
	panel.save_named("First")
	assert_has(panel.labels(), "First", "saved and listed")
	var first: ReplayFile = ReplayFile.read(SaveGame.path_for("First", _directory))
	for frame: int in 10:
		await get_tree().physics_frame
	panel.save_named("First")
	assert_string_contains(panel.status(), "exists", "asks first")
	assert_eq(
		SaveGame.save_tick(ReplayFile.read(SaveGame.path_for("First", _directory))),
		SaveGame.save_tick(first),
		"and has not written yet"
	)
	panel.save_named("First")
	assert_gt(
		SaveGame.save_tick(ReplayFile.read(SaveGame.path_for("First", _directory))),
		SaveGame.save_tick(first),
		"the second press overwrites"
	)
	panel.save_named("autosave")
	assert_string_contains(panel.status(), "not 'autosave'")
	await _tear_down(scenario)


func test_a_lost_match_offers_restart_the_autosave_and_the_menu() -> void:
	var scenario: Scenario = await _boot()
	var options := DefeatOptions.new()
	options.scenario = scenario
	options.directory = _directory
	add_child_autofree(options)
	assert_false(options.restart_button.disabled, "an authored scenario can be restarted")
	assert_true(options.load_button.disabled, "no autosave yet")
	assert_false(options.menu_button.disabled)
	var file := FileAccess.open(SaveGame.autosave_path(_directory), FileAccess.WRITE)
	file.store_string("x")
	file.close()
	var again := DefeatOptions.new()
	again.scenario = scenario
	again.directory = _directory
	add_child_autofree(again)
	assert_false(again.load_button.disabled, "an autosave to load")
	await _tear_down(scenario)


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
