extends GutTest

## SceneManager is the one place a scene change happens — the title screen opening a
## scenario, and a scenario returning to the title screen from either the pause menu or a
## victory dialog.
##
## Nothing here performs a SUCCESSFUL swap: change_scene_to_* would replace the tree the test
## is running in. What is covered is everything around it — the guards, the announcement, and
## the pause release, which is the actual reason this module exists.

var _requested: Array[String] = []


func before_each() -> void:
	_requested = []
	SceneManager.scene_change_requested.connect(_record)


func after_each() -> void:
	SceneManager.scene_change_requested.disconnect(_record)
	# Never leave the harness paused for the next test.
	get_tree().paused = false


func _record(a_path: String) -> void:
	_requested.append(a_path)


func test_the_main_menu_scene_exists() -> void:
	assert_true(
		ResourceLoader.exists(SceneManager.MAIN_MENU_SCENE),
		"MAIN_MENU_SCENE points at a real scene: '%s'" % SceneManager.MAIN_MENU_SCENE
	)


func test_a_missing_scene_is_refused_rather_than_blanking_the_screen() -> void:
	var result: Error = SceneManager.go_to_file("res://scenes/menu/does_not_exist.tscn")

	assert_eq(result, ERR_FILE_NOT_FOUND, "a path with nothing behind it is refused")
	assert_eq(_requested, [] as Array[String], "and no change is announced")
	assert_push_error("no scene at", "the bad path is named")


func test_a_null_packed_scene_is_refused() -> void:
	var result: Error = SceneManager.go_to_packed(null)

	assert_eq(result, ERR_INVALID_PARAMETER, "there is nothing to open")
	assert_eq(_requested, [] as Array[String], "and no change is announced")
	assert_push_error("null scene", "the caller is told what it did")


## The reason this module exists rather than three calls to get_tree().change_scene_to_*.
## SceneTree.paused belongs to the tree, not the scene, so it outlives a scene change: return
## to the menu from a paused pause menu and the menu itself would be paused, with its buttons
## inert and nothing left alive to un-pause it.
func test_a_refused_change_still_leaves_the_tree_running() -> void:
	get_tree().paused = true

	SceneManager.go_to_file("res://scenes/menu/does_not_exist.tscn")

	assert_true(get_tree().paused, "a refused change is a no-op — it must not resume anything")
	assert_push_error("no scene at")


func test_the_pause_is_cleared_as_part_of_changing_scene() -> void:
	# Drive the release directly: the public calls would swap the tree out from under the test.
	get_tree().paused = true

	SceneManager._resume()

	assert_false(get_tree().paused, "the outgoing scene's pause does not follow us")
