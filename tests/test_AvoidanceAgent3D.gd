extends GutTest

## Default mask: every team bit (0..TEAM_BITS-1) + every exception-pool bit
## (TEAM_BITS..31) = all 32 bits, so a unit avoids every other unit; the per-pair
## exception system then clears specific partner bits.
const _FULL_MASK: int = 0xFFFFFFFF


func _agent(commander_id: int = 1) -> AvoidanceAgent3D:
	var a := AvoidanceAgent3D.new()
	add_child_autofree(a)
	a.enable_avoidance(commander_id)
	return a


func test_agent_broadcasts_team_bit_and_avoids_all_teams():
	var a := _agent(1)
	assert_eq(a.avoidance_layers, AvoidanceAgent3D.team_bit(1), "broadcasts on its team bit")
	assert_eq(a.avoidance_mask, _FULL_MASK, "avoids every team + any agent in an exception")


func test_same_team_agents_avoid_each_other():
	var a := _agent(1)
	var b := _agent(1)
	assert_ne(a.avoidance_mask & b.avoidance_layers, 0, "a avoids same-team b")
	assert_ne(b.avoidance_mask & a.avoidance_layers, 0, "b avoids same-team a")


func test_different_teams_also_avoid_each_other():
	# Cross-team units must NOT walk through each other.
	var a := _agent(1)
	var d := _agent(2)
	assert_ne(a.avoidance_mask & d.avoidance_layers, 0, "a avoids other-team d")
	assert_ne(d.avoidance_mask & a.avoidance_layers, 0, "d avoids other-team a")


func test_exception_is_mutual_and_isolated():
	var a := _agent(1)
	var b := _agent(2)  # exceptions work across teams too
	var c := _agent(1)
	a.add_avoidance_exception_with(b)
	# a and b each took a unique pool bit and cleared the other's bit from their mask.
	assert_ne(a.avoidance_layers, AvoidanceAgent3D.team_bit(1), "a took a unique pool bit")
	assert_ne(b.avoidance_layers, AvoidanceAgent3D.team_bit(2), "b took a unique pool bit")
	assert_eq(a.avoidance_mask & b.avoidance_layers, 0, "a ignores b")
	assert_eq(b.avoidance_mask & a.avoidance_layers, 0, "b ignores a")
	# c (uninvolved) still avoids both, and both still avoid c.
	assert_ne(a.avoidance_mask & c.avoidance_layers, 0, "a still avoids c")
	assert_ne(c.avoidance_mask & a.avoidance_layers, 0, "c still avoids a")
	assert_ne(b.avoidance_mask & c.avoidance_layers, 0, "b still avoids c")


func test_remove_restores_avoidance_and_returns_bit():
	var a := _agent(1)
	var b := _agent(1)
	a.add_avoidance_exception_with(b)
	a.remove_avoidance_exception_with(b)
	assert_eq(a.avoidance_layers, AvoidanceAgent3D.team_bit(1), "a back on its team bit")
	assert_eq(b.avoidance_layers, AvoidanceAgent3D.team_bit(1), "b back on its team bit")
	assert_eq(a.avoidance_mask, _FULL_MASK, "a avoids everyone again")
	assert_eq(b.avoidance_mask, _FULL_MASK, "b avoids everyone again")


func test_freeing_one_restores_the_other():
	var a := _agent(1)
	var b := _agent(1)
	a.add_avoidance_exception_with(b)
	var b_layer: int = b.avoidance_layers
	a.free()  # PREDELETE should restore b
	assert_eq(b.avoidance_mask, _FULL_MASK, "b avoids everyone after partner freed")
	assert_eq(b.avoidance_layers, AvoidanceAgent3D.team_bit(1), "b returned to its team bit")
	assert_ne(b_layer, AvoidanceAgent3D.team_bit(1), "(sanity) b had a unique bit during the exception")
