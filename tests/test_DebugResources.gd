extends GutTest

## The debug menu's energy and dominion fields: digits only, and a value sets the commander's
## stockpile through its one write-point. See gdd/systems/ux/ui/debug-mode.md §The debug menu.


func _commander() -> Commander:
	var commander := Commander.new()
	add_child_autofree(commander)
	return commander


func test_only_digits_survive() -> void:
	assert_eq(DebugPanel.digits_only("12a3-4.5 "), "12345")
	assert_eq(DebugPanel.digits_only("abc"), "")


func test_a_value_sets_energy() -> void:
	var commander: Commander = _commander()
	commander.energy = 40
	DebugPanel.set_resource(commander, &"energy", "2500")
	assert_eq(commander.energy, 2500)


func test_a_value_sets_dominion_lower_as_well_as_higher() -> void:
	var commander: Commander = _commander()
	commander.dominion = 900
	DebugPanel.set_resource(commander, &"dominion", "150")
	assert_eq(commander.dominion, 150)


## The HUD bars listen for this; a debug write that skipped it would leave them stale.
func test_setting_a_value_is_announced() -> void:
	var commander: Commander = _commander()
	watch_signals(commander)
	DebugPanel.set_resource(commander, &"dominion", "10")
	assert_signal_emitted(commander, "resources_changed")


func test_an_empty_field_changes_nothing() -> void:
	var commander: Commander = _commander()
	commander.energy = 40
	DebugPanel.set_resource(commander, &"energy", "")
	assert_eq(commander.energy, 40)
