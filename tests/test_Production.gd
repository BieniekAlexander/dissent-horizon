extends GutTest

## Tests for the Production component.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Production.gd
##
## Note: _spawn_unit is intentionally not covered here — it instantiates a Unit
## scene and queries NavigationServer3D for a closest point, both of which need
## a live nav map. That path is exercised in-game and via integration testing.


func _make_production() -> Production:
	var p := Production.new()
	add_child_autofree(p)
	return p


func test_default_queue_is_empty():
	var p := _make_production()
	assert_eq(p.training_queue.size(), 0)


func test_enqueue_appends_to_queue():
	var p := _make_production()
	# We don't have real PackedScenes in tests; null is fine because tick()
	# only inspects the scene when remaining hits zero, and we don't tick down
	# that far in this test.
	p.enqueue(10, null)
	assert_eq(p.training_queue.size(), 1)
	assert_eq(p.training_queue[0][0], 10)


## A structure builds ONE unit at a time: everything else waits in the commander's global
## queue, which is what lets two producers share a burden. A second enqueue is refused
## rather than stacking.
func test_a_second_enqueue_is_refused_while_busy():
	var p := _make_production()
	assert_true(p.enqueue(5, null), "the first job is accepted")
	assert_false(p.enqueue(15, null), "the second is refused")
	assert_eq(p.training_queue.size(), 1)
	assert_eq(p.training_queue[0][0], 5, "and the job in progress is untouched")


func test_tick_decrements_head():
	var p := _make_production()
	p.enqueue(3, null)
	var completed: bool = p.tick()
	assert_false(completed, "tick before completion returns false")
	assert_eq(p.training_queue[0][0], 2)


func test_tick_returns_false_on_empty_queue():
	var p := _make_production()
	assert_false(p.tick())


## --- cancel ----------------------------------------------------------------
## cancel() removes a queued job (and, when the producer has a commander, refunds
## its cost — the refund path is exercised in-game since it needs a live commander).


func test_enqueue_stores_type_for_refund():
	var p := _make_production()
	p.enqueue(10, null, &"fake_builder_a")
	assert_eq(p.job_type(0), &"fake_builder_a")


func test_cancel_removes_the_job():
	var p := _make_production()
	p.enqueue(5, null, &"fake_builder_a")
	assert_true(p.cancel(0), "cancel returns true when a job is removed")
	assert_eq(p.job_count(), 0, "the job is gone")
	assert_true(p.is_free(), "and the producer can take another")


func test_cancel_out_of_range_is_a_noop():
	var p := _make_production()
	p.enqueue(5, null)
	assert_false(p.cancel(3), "index past the end returns false")
	assert_false(p.cancel(-1), "negative index returns false")
	assert_eq(p.job_count(), 1, "queue is untouched")


## --- job_commands ------------------------------------------------------------
## The pre-issued chain a queued job will hand its unit at spawn (JOB_COMMANDS).


func test_job_commands_defaults_to_empty():
	var p := _make_production()
	p.enqueue(10, null)
	assert_eq(p.job_commands(0), [])


func test_job_commands_returns_the_enqueued_chain():
	var p := _make_production()
	var move := MoveCommand.new(CommandMessage.new(null, null, null, Vector3(5, 0, 5)))
	p.enqueue(10, null, &"fake_builder_a", [move])
	assert_eq(p.job_commands(0), [move])


## --- producible_types / can_produce ---------------------------------------
## The component owns the "what can this build" capability (moved off the Train
## command). Configured per structure scene via the producible_types export.


func test_default_producible_types_is_empty():
	var p := _make_production()
	assert_eq(p.producible_types.size(), 0)
	assert_false(p.can_produce(&"fake_builder_b"))


func test_can_produce_reflects_configured_types():
	var p := _make_production()
	p.producible_types.assign([&"fake_builder_a", &"fake_soldier"])
	assert_true(p.can_produce(&"fake_builder_a"))
	assert_true(p.can_produce(&"fake_soldier"))
	assert_false(p.can_produce(&"fake_builder_b"), "type not in the list is not producible")
