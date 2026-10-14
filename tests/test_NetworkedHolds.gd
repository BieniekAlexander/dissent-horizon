extends GutTest

## In a networked match nothing may stop or speed up one machine's simulation alone: only the
## network wait holds the world, and debug mode — which also carries playback speed — is never
## permitted. Built out of the tree, so a hold that did land would only be bookkeeping.
## gdd/systems/commands/netplay.md §Rules.

var _scenario: Scenario
var _clock: SimulationClock


func before_each() -> void:
	_scenario = Scenario.new()
	var manager := ScenarioTriggerManager.new()
	manager.name = "ScenarioTriggerManager"
	_clock = SimulationClock.new()
	manager.add_child(_clock)
	manager.simulation_clock = _clock
	_scenario.add_child(manager)


func after_each() -> void:
	_scenario.free()


func _network() -> void:
	_scenario.add_child(NetMatch.new())


func test_a_local_hold_is_refused_in_a_networked_match() -> void:
	_network()
	for reason: StringName in [
		SimulationClock.REASON_PAUSE_MENU,
		SimulationClock.REASON_HELP,
		SimulationClock.REASON_PLAYBACK_PAUSE,
		SimulationClock.REASON_DIALOG,
	]:
		_clock.hold(reason)
		assert_false(_clock.is_paused(), "%s would stop this machine alone" % reason)
		_clock.release(reason)


func test_the_network_wait_still_holds_a_networked_match() -> void:
	_network()
	_clock.hold(SimulationClock.REASON_NETWORK_WAIT)
	assert_true(_clock.is_paused())
	_clock.release(SimulationClock.REASON_NETWORK_WAIT)
	assert_false(_clock.is_paused())


func test_a_single_machine_session_holds_as_before() -> void:
	_clock.hold(SimulationClock.REASON_PAUSE_MENU)
	assert_true(_clock.is_paused())
	_clock.release(SimulationClock.REASON_PAUSE_MENU)


func test_debug_mode_is_never_permitted_in_a_networked_match() -> void:
	_scenario.debug_allowed = true
	assert_true(_scenario.is_debug_permitted(), "a single-machine session that allows it")
	_network()
	assert_true(_scenario.is_networked())
	assert_false(_scenario.is_debug_permitted())
