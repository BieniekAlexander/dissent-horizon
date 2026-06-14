extends GutTest

## Bit layout: bits 0..7 = agent team channels, bits 8..15 = obstacle channels,
## bits 16..31 = exception pool. See AvoidanceAgent3D for the full design.

## Compute the expected default avoidance_mask for a given commander.
## = own team bit + all FOREIGN obstacle bits (not own) + exception pool
func _expected_mask(commander_id: int) -> int:
	var team: int = AvoidanceAgent3D.team_bit(commander_id)
	var own_obs: int = AvoidanceAgent3D.obstacle_bit(commander_id)
	var all_obs: int = (AvoidanceAgent3D._ALL_TEAMS) << AvoidanceAgent3D._TEAM_BITS  # 0xFF00
	var pool: int = AvoidanceAgent3D._POOL_MASK  # bits 16..31
	return team | (all_obs & ~own_obs) | pool


func _agent(commander_id: int = 1) -> AvoidanceAgent3D:
	var a := AvoidanceAgent3D.new()
	add_child_autofree(a)
	a.enable_avoidance(commander_id)
	return a


func test_agent_broadcasts_on_team_bit():
	var a := _agent(1)
	assert_eq(a.avoidance_layers, AvoidanceAgent3D.team_bit(1), "broadcasts on its team bit")


func test_agent_mask_is_own_team_plus_foreign_obstacles_plus_pool():
	# The mask must: see own-team agents (reciprocal RVO), see all foreign
	# obstacles (one-sided cross-team avoidance), NOT see enemy agent bits
	# (no reciprocal RVO with enemies), NOT see own obstacle (co-located,
	# degenerate avoidance).
	var a := _agent(1)
	assert_eq(a.avoidance_mask, _expected_mask(1), "mask = own team + foreign obstacles + pool")


func test_same_team_agents_do_reciprocal_rvo():
	var a := _agent(1)
	var b := _agent(1)
	assert_ne(a.avoidance_mask & b.avoidance_layers, 0, "a sees same-team b")
	assert_ne(b.avoidance_mask & a.avoidance_layers, 0, "b sees same-team a")


func test_different_team_agents_do_not_reciprocal_rvo():
	# Cross-team agents must NOT do reciprocal RVO with each other (both adjusting).
	# Cross-team avoidance is one-sided via NavigationObstacle3D (see Commandable).
	var a := _agent(1)
	var d := _agent(2)
	assert_eq(a.avoidance_mask & d.avoidance_layers, 0, "a does not see enemy d as an agent")
	assert_eq(d.avoidance_mask & a.avoidance_layers, 0, "d does not see enemy a as an agent")


func test_agent_sees_all_foreign_obstacle_bits():
	# An agent's mask must cover every foreign commander's obstacle bit so it
	# one-sidedly steers around enemy NavigationObstacle3D nodes.
	var a := _agent(1)
	for id: int in range(Commander.NUM_MAX_COMMANDERS):
		if id == 1:
			continue  # own commander — obstacle excluded to avoid self-avoidance
		assert_ne(a.avoidance_mask & AvoidanceAgent3D.obstacle_bit(id), 0,
			"a sees obstacle from commander %d" % id)


func test_agent_does_not_see_own_obstacle_bit():
	# Own obstacle is co-located with the agent; including it in the mask would
	# produce degenerate (zero-distance) avoidance.
	var a := _agent(1)
	assert_eq(a.avoidance_mask & AvoidanceAgent3D.obstacle_bit(1), 0,
		"a does not see its own obstacle bit")


func test_exception_is_mutual_and_isolated():
	var a := _agent(1)
	var b := _agent(2)  # exceptions work across teams
	var c := _agent(1)
	a.add_avoidance_exception_with(b)
	# Each took a unique pool bit; each cleared the other's bit from its mask.
	assert_ne(a.avoidance_layers, AvoidanceAgent3D.team_bit(1), "a took a unique pool bit")
	assert_ne(b.avoidance_layers, AvoidanceAgent3D.team_bit(2), "b took a unique pool bit")
	assert_eq(a.avoidance_mask & b.avoidance_layers, 0, "a ignores b")
	assert_eq(b.avoidance_mask & a.avoidance_layers, 0, "b ignores a")
	# c (same team as a) — a still sees c reciprocally via team bit.
	assert_ne(a.avoidance_mask & c.avoidance_layers, 0, "a still avoids c (same team)")
	# c still avoids a via a's unique pool bit (all pool bits stay in c's mask).
	assert_ne(c.avoidance_mask & a.avoidance_layers, 0, "c still avoids a via pool bit")
	# b (enemy) — cross-team agents never do reciprocal RVO regardless of exceptions.
	assert_eq(b.avoidance_mask & c.avoidance_layers, 0, "b does not reciprocal-rvo c (cross-team)")


func test_remove_restores_avoidance_and_returns_bit():
	var a := _agent(1)
	var b := _agent(1)
	a.add_avoidance_exception_with(b)
	a.remove_avoidance_exception_with(b)
	assert_eq(a.avoidance_layers, AvoidanceAgent3D.team_bit(1), "a back on its team bit")
	assert_eq(b.avoidance_layers, AvoidanceAgent3D.team_bit(1), "b back on its team bit")
	assert_eq(a.avoidance_mask, _expected_mask(1), "a mask restored")
	assert_eq(b.avoidance_mask, _expected_mask(1), "b mask restored")


func test_freeing_one_restores_the_other():
	var a := _agent(1)
	var b := _agent(1)
	a.add_avoidance_exception_with(b)
	var b_layer: int = b.avoidance_layers
	a.free()  # PREDELETE should restore b
	assert_eq(b.avoidance_mask, _expected_mask(1), "b mask restored after partner freed")
	assert_eq(b.avoidance_layers, AvoidanceAgent3D.team_bit(1), "b returned to its team bit")
	assert_ne(b_layer, AvoidanceAgent3D.team_bit(1), "(sanity) b had a unique bit during the exception")
