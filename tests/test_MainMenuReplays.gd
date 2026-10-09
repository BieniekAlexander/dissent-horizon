extends GutTest

## The start screen's replay panel: every replay on disk, newest first, and a replay this build
## cannot play refused with its reason when chosen.
## gdd/systems/commands/recording-and-replay.md §Watching.
##
## Nothing here opens a PLAYABLE replay: that swaps the whole tree out from under the test. The
## opening itself is covered by test_ReplayLibrary's prepare_playback.

const SCENE := "res://scenes/menu/main_menu.tscn"
const DIR: String = "user://test_main_menu_replays/"


func before_each() -> void:
	_clear()
	DirAccess.make_dir_recursive_absolute(DIR)


func after_all() -> void:
	_clear()


func _clear() -> void:
	for file: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + file)


func _menu() -> MainMenu:
	var menu: MainMenu = load(SCENE).instantiate() as MainMenu
	menu.scenarios = [] as Array[ScenarioEntry]
	menu.replay_directory = DIR
	add_child_autofree(menu)
	return menu


func _write(a_file: String, a_version: String) -> void:
	var replay := ReplayFile.new()
	replay.header = {
		"type": ReplayFile.HEADER_TYPE, "scenario": "", "seed": 1, "version": a_version
	}
	replay.write(DIR + a_file)


func test_with_no_replays_the_panel_says_so() -> void:
	var menu: MainMenu = _menu()
	assert_eq(menu.replay_labels(), [] as Array[String])


func test_every_replay_is_listed_autosaves_and_kept_alike() -> void:
	_write("kept_one.jsonl.gz", "v")
	_write(ReplayNames.autosave_name(1_800_000_000), "v")
	var labels: Array[String] = _menu().replay_labels()
	assert_eq(labels.size(), 2)
	assert_true(labels.has("kept_one"))
	assert_eq(labels.filter(func(l: String) -> bool: return l.begins_with("Autosave")).size(), 1)


func test_a_replay_from_another_version_is_listed_and_refused_when_chosen() -> void:
	_write("old.jsonl.gz", "not|this|version")
	var menu: MainMenu = _menu()
	assert_eq(menu.replay_labels(), ["old"] as Array[String], "listed all the same")
	menu.open_replay(DIR + "old.jsonl.gz")
	assert_string_contains(menu.replay_refusal(), "another version")
