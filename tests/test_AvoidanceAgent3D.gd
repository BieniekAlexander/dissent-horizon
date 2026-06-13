extends GutTest

const _ALL: int = 0xFFFFFFFF

func _agent() -> AvoidanceAgent3D:
	var a := AvoidanceAgent3D.new()
	add_child_autofree(a)
	a.enable_avoidance()
	return a

func test_default_agent_avoids_everyone():
	var a := _agent()
	assert_eq(a.avoidance_layers, 1, "broadcasts on shared NORMAL bit")
	assert_eq(a.avoidance_mask, _ALL, "avoids everyone")

func test_exception_is_mutual_and_isolated():
	var a := _agent()
	var b := _agent()
	var c := _agent()
	a.add_avoidance_exception_with(b)
	# a and b each took a unique bit and cleared the other's bit from their mask.
	assert_ne(a.avoidance_layers, 1, "a took a unique bit")
	assert_ne(b.avoidance_layers, 1, "b took a unique bit")
	assert_eq(a.avoidance_mask & b.avoidance_layers, 0, "a ignores b")
	assert_eq(b.avoidance_mask & a.avoidance_layers, 0, "b ignores a")
	# c (uninvolved) still avoids both, and both still avoid c.
	assert_ne(a.avoidance_mask & c.avoidance_layers, 0, "a still avoids c")
	assert_ne(c.avoidance_mask & a.avoidance_layers, 0, "c still avoids a")
	assert_ne(b.avoidance_mask & c.avoidance_layers, 0, "b still avoids c")

func test_remove_restores_avoidance_and_returns_bit():
	var a := _agent()
	var b := _agent()
	a.add_avoidance_exception_with(b)
	a.remove_avoidance_exception_with(b)
	assert_eq(a.avoidance_layers, 1, "a back on shared bit")
	assert_eq(b.avoidance_layers, 1, "b back on shared bit")
	assert_eq(a.avoidance_mask, _ALL, "a avoids everyone again")
	assert_eq(b.avoidance_mask, _ALL, "b avoids everyone again")

func test_freeing_one_restores_the_other():
	var a := _agent()
	var b := _agent()
	a.add_avoidance_exception_with(b)
	var b_layer: int = b.avoidance_layers
	a.free()  # PREDELETE should restore b
	assert_eq(b.avoidance_mask, _ALL, "b avoids everyone after partner freed")
	assert_eq(b.avoidance_layers, 1, "b returned to shared bit")
	assert_ne(b_layer, 1, "(sanity) b had a unique bit during the exception")
