extends GutTest

## The pause menu holds the simulation while it is up and releases on close, through a
## SimulationClock hold rather than a direct write to SceneTree.paused — so it composes with
## the holds a scripted dialog or the help book may already have out.
##
## Nothing here presses "Return to Main Menu": that calls SceneManager, which would swap the
## tree the test runs in. The navigation is covered in test_SceneManager.gd.

const SCENE := "res://scenes/menu/pause_menu.tscn"

var _menu: PauseMenu
var _clock: SimulationClock


func before_each() -> void:
	_menu = load(SCENE).instantiate() as PauseMenu
	add_child_autofree(_menu)
	# An ORPHAN clock: SimulationClock skips the engine call when it is not in the tree, so it
	# does its full bookkeeping without pausing GUT itself. (An in-tree clock would freeze the
	# whole test run — see the class comment on SimulationClock.)
	_clock = SimulationClock.new()
	_menu._clock = _clock


func after_each() -> void:
	_clock.clear()
	_clock.free()


## The contract Scenario relies on: it binds by group rather than by path, so a rig can put
## the menu wherever it likes. If this stops holding, the clock is silently never supplied
## and the pause menu stops pausing.
func test_it_joins_the_group_scenario_binds_by() -> void:
	assert_true(
		_menu.is_in_group(PauseMenu.GROUP), "Scenario can find it without knowing where it is"
	)


func test_it_starts_closed_and_hidden() -> void:
	assert_false(_menu.is_open(), "a scenario does not begin paused")
	assert_false(_menu.visible, "and nothing is drawn")
	assert_false(_clock.is_paused(), "no hold is taken until it opens")


func test_opening_holds_the_simulation() -> void:
	_menu.open()

	assert_true(_menu.is_open(), "the menu is up")
	assert_true(_menu.visible, "and drawn")
	assert_true(_clock.is_held_by(SimulationClock.REASON_PAUSE_MENU), "the world is held")


func test_closing_releases_the_hold() -> void:
	_menu.open()
	_menu.close()

	assert_false(_menu.is_open(), "the menu is down")
	assert_false(_menu.visible, "and hidden")
	assert_false(_clock.is_paused(), "the world resumes")


func test_toggle_alternates() -> void:
	_menu.toggle()
	assert_true(_menu.is_open(), "first toggle opens")
	_menu.toggle()
	assert_false(_menu.is_open(), "second toggle closes")


func test_opening_twice_takes_only_one_hold() -> void:
	_menu.open()
	_menu.open()
	_menu.close()

	assert_false(_clock.is_paused(), "a repeated open must not need two closes to resume")


func test_closing_when_already_closed_does_not_release_someone_elses_hold() -> void:
	_clock.hold(SimulationClock.REASON_DIALOG)

	_menu.close()

	assert_true(
		_clock.is_held_by(SimulationClock.REASON_DIALOG),
		"a no-op close leaves a scripted dialog's hold alone"
	)


## The reason the menu takes a REASON-keyed hold rather than writing SceneTree.paused.
func test_it_does_not_resume_a_world_a_dialog_still_wants_stopped() -> void:
	_clock.hold(SimulationClock.REASON_DIALOG)
	_menu.open()
	_menu.close()

	assert_true(_clock.is_paused(), "the dialog's hold survives the pause menu closing")
	assert_false(
		_clock.is_held_by(SimulationClock.REASON_PAUSE_MENU),
		"and the pause menu's own hold is gone"
	)


func test_leaving_the_tree_while_open_does_not_strand_the_hold() -> void:
	_menu.open()

	_menu.get_parent().remove_child(_menu)

	assert_false(_clock.is_paused(), "a scene torn down mid-pause still resumes")
	_menu.free()


func test_it_works_without_a_clock() -> void:
	_menu._clock = null

	_menu.open()
	assert_true(_menu.is_open(), "a rig with no trigger manager can still open the menu")
	_menu.close()
	assert_false(
		_menu.is_open(), "and close it — being unable to pause is not being unable to quit"
	)


## The arrow keys pan the camera, which keeps working behind this menu, and a slider holding
## keyboard focus takes each press as a step: panning used to nudge the playback speed a tick at
## a time. Neither slider may take focus; the mouse still drags them.
func test_no_slider_takes_keyboard_focus() -> void:
	var menu: PauseMenu = (load("res://scenes/menu/pause_menu.tscn") as PackedScene).instantiate()
	add_child_autofree(menu)
	var speed: Slider = menu.get_node("%PlaybackControls").get_node("%SpeedSlider") as Slider
	var volume: Slider = menu.get_node("%VolumeSlider") as Slider
	assert_eq(speed.focus_mode, Control.FOCUS_NONE, "the speed slider takes no focus")
	assert_eq(volume.focus_mode, Control.FOCUS_NONE, "nor the volume slider")
