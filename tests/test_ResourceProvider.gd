extends GutTest

## Tests for the ResourceProvider component.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ResourceProvider.gd

func _make_provider(provided: int = 0, required: int = 0) -> ResourceProvider:
	var r := ResourceProvider.new()
	r.population_provided = provided
	r.population_required = required
	add_child_autofree(r)
	return r

func test_apply_to_increments_both_pools():
	var r := _make_provider(50, 10)
	var c := Commander.new()
	r.apply_to(c)
	assert_eq(c.population_max, 50)
	assert_eq(c.population_used, 10)
	c.queue_free()

func test_remove_from_undoes_apply_to():
	var r := _make_provider(50, 10)
	var c := Commander.new()
	r.apply_to(c)
	r.remove_from(c)
	assert_eq(c.population_max, 0, "apply/remove is symmetric on max")
	assert_eq(c.population_used, 0, "apply/remove is symmetric on used")
	c.queue_free()

func test_null_commander_is_safe_on_both_paths():
	var r := _make_provider(50, 10)
	# Should not crash.
	r.apply_to(null)
	r.remove_from(null)
	pass_test("null commander is handled safely on both paths")

func test_default_values_are_zero():
	var r := ResourceProvider.new()
	add_child_autofree(r)
	assert_eq(r.population_provided, 0)
	assert_eq(r.population_required, 0)
