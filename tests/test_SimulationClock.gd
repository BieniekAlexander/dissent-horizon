extends GutTest

## Tests for SimulationClock — the reason-counted pause the tutorial/dialog system uses to
## stop the world while the player reads or acts.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_SimulationClock.gd -gexit
##
## Most of these keep the clock OUT of the scene tree on purpose. An in-tree clock drives
## the real SceneTree.paused, which would also stop GUT itself; orphaned, _apply() skips the
## engine call and only the bookkeeping runs, which is what these assertions are about.
## test_in_tree_clock_drives_the_scene_tree covers the engine half, and unpauses in the same
## call so no frame ever elapses while paused.

var _clock: SimulationClock


func before_each() -> void:
	_clock = SimulationClock.new()


func after_each() -> void:
	# Belt and braces: a hold left standing by a failed assertion must not wedge the suite.
	_clock.clear()
	_clock.free()
	get_tree().paused = false


# --- Hold / release bookkeeping ----------------------------------------------

func test_starts_unpaused() -> void:
	assert_false(_clock.is_paused(), "a fresh clock is running")


func test_hold_pauses_and_release_resumes() -> void:
	_clock.hold(SimulationClock.REASON_DIALOG)
	assert_true(_clock.is_paused(), "a hold pauses")
	_clock.release(SimulationClock.REASON_DIALOG)
	assert_false(_clock.is_paused(), "releasing the only hold resumes")


func test_holds_of_one_reason_are_counted() -> void:
	# Two dialogs queued at once each take their own hold; dismissing one must not resume.
	_clock.hold(SimulationClock.REASON_DIALOG)
	_clock.hold(SimulationClock.REASON_DIALOG)
	assert_eq(_clock.hold_count(SimulationClock.REASON_DIALOG), 2, "counts stack")
	_clock.release(SimulationClock.REASON_DIALOG)
	assert_true(_clock.is_paused(), "still paused with one hold outstanding")
	_clock.release(SimulationClock.REASON_DIALOG)
	assert_false(_clock.is_paused(), "resumes when the last hold goes")


func test_reasons_are_independent() -> void:
	_clock.hold(SimulationClock.REASON_DIALOG)
	_clock.hold(SimulationClock.REASON_TUTORIAL)
	_clock.release(SimulationClock.REASON_DIALOG)
	assert_true(_clock.is_paused(), "another system's hold survives an unrelated release")
	assert_false(_clock.is_held_by(SimulationClock.REASON_DIALOG))
	assert_true(_clock.is_held_by(SimulationClock.REASON_TUTORIAL))


func test_releasing_an_unheld_reason_does_nothing() -> void:
	# A dialog dismissed twice, or a system that lost track of its own hold, must not be
	# able to resume a world another system still wants frozen. (The clock also warns.)
	_clock.hold(SimulationClock.REASON_DIALOG)
	_clock.release(SimulationClock.REASON_TUTORIAL)
	assert_push_warning("no outstanding hold")
	assert_true(_clock.is_paused(), "an unrelated over-release can't resume the world")
	assert_eq(_clock.hold_count(SimulationClock.REASON_DIALOG), 1, "and doesn't steal a hold")


func test_clear_drops_every_hold() -> void:
	_clock.hold(SimulationClock.REASON_DIALOG)
	_clock.hold(SimulationClock.REASON_TUTORIAL)
	_clock.clear()
	assert_false(_clock.is_paused(), "clear resumes regardless of how many holds were out")


# --- Transition signal --------------------------------------------------------

func test_in_tree_clock_drives_the_scene_tree() -> void:
	var clock := SimulationClock.new()
	add_child_autofree(clock)
	watch_signals(clock)

	clock.hold(SimulationClock.REASON_DIALOG)
	assert_true(get_tree().paused, "a hold pauses the SceneTree")
	# Second hold of the same reason is not a transition — the tree was already paused.
	clock.hold(SimulationClock.REASON_DIALOG)
	assert_signal_emit_count(clock, "paused_changed", 1, "only real transitions announce")

	# Resume inside this same call: no frame may elapse while the tree is paused, or GUT
	# stops running too.
	clock.clear()
	assert_false(get_tree().paused, "clear resumes the SceneTree")
	assert_signal_emit_count(clock, "paused_changed", 2, "the resume is announced")


# --- Manager integration ------------------------------------------------------

func test_manager_creates_a_clock() -> void:
	var manager := ScenarioTriggerManager.new()
	add_child_autofree(manager)
	assert_push_warning("expected parent to be Scenario")
	assert_not_null(manager.simulation_clock, "every session gets a clock")
	assert_false(manager.simulation_clock.is_paused(), "and it starts running")


func test_manager_polls_conditions_while_held() -> void:
	# The condition poller must survive a hold: that is how a paused beat notices the
	# player did the thing it was waiting for. PROCESS_MODE_ALWAYS on the manager is what
	# grants that, and it propagates to the poller it creates.
	var manager := ScenarioTriggerManager.new()
	add_child_autofree(manager)
	assert_push_warning("expected parent to be Scenario")
	assert_eq(manager.process_mode, Node.PROCESS_MODE_ALWAYS, "manager ignores pause")
	assert_eq(
		manager.condition_poller.process_mode, Node.PROCESS_MODE_INHERIT,
		"the poller inherits the manager's always-on mode rather than opting out itself"
	)
