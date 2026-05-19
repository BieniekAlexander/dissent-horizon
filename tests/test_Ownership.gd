extends GutTest

## Tests for the Ownership component.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Ownership.gd

func _make_ownership() -> Ownership:
	var o := Ownership.new()
	add_child_autofree(o)
	return o

## A fake Commander so we don't have to instantiate the real Commander node
## tree (which pulls in technology trees, resources, etc.) just to verify
## Ownership's contract. Ownership only reads `id` off the commander.

func test_default_commander_is_null():
	var o := _make_ownership()
	assert_null(o.commander)

func test_commander_id_is_zero_when_unowned():
	var o := _make_ownership()
	assert_eq(o.commander_id, 0)

func test_setting_commander_updates_commander_id():
	var o := _make_ownership()
	var c := Commander.new()
	c.id = 3
	o.commander = c
	assert_eq(o.commander, c)
	assert_eq(o.commander_id, 3)
	c.queue_free()

func test_commander_changed_emits_with_old_and_new():
	var o := _make_ownership()
	var c := Commander.new()
	c.id = 1
	watch_signals(o)
	o.commander = c
	assert_signal_emitted_with_parameters(o, "commander_changed", [null, c])
	c.queue_free()

func test_setting_same_commander_is_a_noop():
	var o := _make_ownership()
	var c := Commander.new()
	c.id = 2
	o.commander = c
	watch_signals(o)
	o.commander = c  # same instance
	assert_signal_not_emitted(o, "commander_changed")
	c.queue_free()

func test_changing_commander_emits_with_previous_value_as_old():
	var o := _make_ownership()
	var c1 := Commander.new()
	c1.id = 1
	var c2 := Commander.new()
	c2.id = 2
	o.commander = c1
	watch_signals(o)
	o.commander = c2
	assert_signal_emitted_with_parameters(o, "commander_changed", [c1, c2])
	c1.queue_free()
	c2.queue_free()

func test_clearing_commander_emits_signal():
	var o := _make_ownership()
	var c := Commander.new()
	c.id = 4
	o.commander = c
	watch_signals(o)
	o.commander = null
	assert_signal_emitted_with_parameters(o, "commander_changed", [c, null])
	assert_eq(o.commander_id, 0, "commander_id falls back to 0 after clear")
	c.queue_free()
