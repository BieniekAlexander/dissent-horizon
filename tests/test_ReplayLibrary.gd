extends GutTest

## The replays on disk as the start screen lists them, and how one is opened: listed newest
## first, autosaves marked, and a replay this build cannot play refused with its reason.
## gdd/systems/commands/recording-and-replay.md §Watching.

const DIR: String = "user://test_replay_library/"
## A cheap scenario to open a recording of: one human slot on a flat map, nothing else.
const HARNESS: String = "res://scenes/scenarios/test/nav_straight_line.tscn"


func before_each() -> void:
	_clear()
	DirAccess.make_dir_recursive_absolute(DIR)


func after_all() -> void:
	_clear()


func _clear() -> void:
	for file: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + file)


func _replay(a_scenario: String = HARNESS, a_version: String = "") -> ReplayFile:
	var replay := ReplayFile.new()
	replay.header = {
		"type": ReplayFile.HEADER_TYPE,
		"scenario": a_scenario,
		"seed": 3,
		"slots": [],
		"version": a_version if not a_version.is_empty() else ReplayFile.current_version(),
	}
	return replay


func _write(a_file: String, a_replay: ReplayFile) -> String:
	a_replay.write(DIR + a_file)
	return DIR + a_file


func test_entries_lists_only_replay_files_newest_first() -> void:
	var a: Dictionary = {"file": "a.jsonl.gz", "modified": 100}
	var b: Dictionary = {"file": "b.jsonl.gz", "modified": 300}
	var c: Dictionary = {"file": "c.jsonl.gz", "modified": 200}
	var ordered: Array[Dictionary] = ReplayLibrary.ordered([a, b, c] as Array[Dictionary])
	assert_eq(
		ordered.map(func(e: Dictionary) -> String: return e["file"]),
		["b.jsonl.gz", "c.jsonl.gz", "a.jsonl.gz"]
	)


func test_a_tie_in_time_is_broken_by_name() -> void:
	var a: Dictionary = {"file": "b.jsonl.gz", "modified": 5}
	var b: Dictionary = {"file": "a.jsonl.gz", "modified": 5}
	var ordered: Array[Dictionary] = ReplayLibrary.ordered([a, b] as Array[Dictionary])
	assert_eq(ordered[0]["file"], "a.jsonl.gz")


func test_entries_reads_the_directory_and_marks_autosaves() -> void:
	_write("mine.jsonl.gz", _replay())
	_write(ReplayNames.autosave_name(1_800_000_000), _replay())
	var stray: FileAccess = FileAccess.open(DIR + "notes.txt", FileAccess.WRITE)
	stray.store_string("not a replay")
	stray.close()
	var entries: Array[Dictionary] = ReplayLibrary.entries(DIR)
	assert_eq(entries.size(), 2, "the stray file is not listed")
	var autosaves: Array = entries.filter(func(e: Dictionary) -> bool: return e["is_autosave"])
	assert_eq(autosaves.size(), 1)
	assert_eq(ReplayLibrary.label_for(autosaves[0]), "Autosave · 2027-01-15 08:00 UTC")


func test_a_label_drops_the_extension() -> void:
	var entry: Dictionary = {"file": "skirmish_win.jsonl.gz", "is_autosave": false}
	assert_eq(ReplayLibrary.label_for(entry), "skirmish_win")


func test_a_file_that_is_not_a_replay_is_refused() -> void:
	var file: FileAccess = FileAccess.open(DIR + "junk.jsonl.gz", FileAccess.WRITE)
	file.store_string("junk")
	file.close()
	var prepared: Dictionary = ReplayLibrary.prepare_playback(DIR + "junk.jsonl.gz")
	assert_false(prepared.has("scenario"))
	assert_string_contains(prepared["refusal"], "not a replay")


func test_a_replay_from_another_version_is_refused() -> void:
	var path: String = _write("old.jsonl.gz", _replay(HARNESS, "some|other|version"))
	var prepared: Dictionary = ReplayLibrary.prepare_playback(path)
	assert_false(prepared.has("scenario"))
	assert_string_contains(prepared["refusal"], "another version")


func test_a_recording_debug_mode_ended_is_refused() -> void:
	var replay: ReplayFile = _replay()
	replay.records.append(
		{"type": ReplayRecorder.INVALID_TYPE, "tick": 40, "reason": "a debug piece"}
	)
	var prepared: Dictionary = ReplayLibrary.prepare_playback(_write("debug.jsonl.gz", replay))
	assert_false(prepared.has("scenario"))
	assert_string_contains(prepared["refusal"], "a debug piece")


func test_a_replay_of_a_scenario_this_build_lacks_is_refused() -> void:
	var path: String = _write("gone.jsonl.gz", _replay("res://scenes/scenarios/no_such.tscn"))
	var prepared: Dictionary = ReplayLibrary.prepare_playback(path)
	assert_string_contains(prepared["refusal"], "no_such.tscn")


func test_a_playable_replay_opens_its_scenario_set_to_play_it_back() -> void:
	var path: String = _write("good.jsonl.gz", _replay())
	var prepared: Dictionary = ReplayLibrary.prepare_playback(path)
	assert_false(prepared.has("refusal"), str(prepared.get("refusal", "")))
	var scenario: Scenario = prepared.get("scenario")
	assert_not_null(scenario)
	assert_true(scenario.is_playback(), "the scenario plays the recording rather than a match")
	assert_eq(scenario.replay_to_play.header.get("seed"), 3.0)
	scenario.free()


func test_the_scene_manager_hands_back_a_refusal_without_leaving() -> void:
	var path: String = _write("old.jsonl.gz", _replay(HARNESS, "x|y|z"))
	assert_string_contains(SceneManager.play_replay(path), "another version")
