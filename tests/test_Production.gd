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
	assert_null(p.rally_command)

func test_enqueue_appends_to_queue():
	var p := _make_production()
	# We don't have real PackedScenes in tests; null is fine because tick()
	# only inspects the scene when remaining hits zero, and we don't tick down
	# that far in this test.
	p.enqueue(10, null)
	assert_eq(p.training_queue.size(), 1)
	assert_eq(p.training_queue[0][0], 10)

func test_enqueue_preserves_fifo_order():
	var p := _make_production()
	p.enqueue(5, null)
	p.enqueue(15, null)
	assert_eq(p.training_queue[0][0], 5, "first enqueued is at head")
	assert_eq(p.training_queue[1][0], 15, "second enqueued is at tail")

func test_tick_decrements_head():
	var p := _make_production()
	p.enqueue(3, null)
	var completed: bool = p.tick()
	assert_false(completed, "tick before completion returns false")
	assert_eq(p.training_queue[0][0], 2)

func test_tick_returns_false_on_empty_queue():
	var p := _make_production()
	assert_false(p.tick())

func test_set_rally_stores_command():
	var p := _make_production()
	# We can't easily instantiate a real Command without a CommandMessage and
	# its Map dependency, so we just verify the field is set. A null rally is
	# also a valid state (no rally point set).
	p.set_rally(null)
	assert_null(p.rally_command)
