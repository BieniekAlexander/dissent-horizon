extends GutTest

## Tests for the Movement component.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Movement.gd
##
## A live NavigationAgent3D depends on the NavigationServer being warmed up
## (a map, region, baked navmesh), which is far more setup than a unit test
## should pull in. These tests cover the contract Movement exposes:
##   - safe defaults when no nav agent is wired
##   - the nav_agent_path resolves a sibling correctly
##   - velocity_ready forwards from the agent's velocity_computed
##   - set_avoidance_team writes both layers and mask

func _make_movement_without_agent() -> Movement:
	var m := Movement.new()
	add_child_autofree(m)
	return m

func test_default_target_position_is_zero_without_agent():
	var m := _make_movement_without_agent()
	assert_eq(m.target_position, Vector3.ZERO)

func test_set_target_position_is_safe_without_agent():
	# Should not crash — the component is designed to no-op when the agent
	# isn't wired (e.g., a Movement was added to a scene without a nav agent).
	var m := _make_movement_without_agent()
	m.set_target_position(Vector3(1, 0, 1))
	# target_position still reads as ZERO because there's no agent backing it.
	assert_eq(m.target_position, Vector3.ZERO)

func test_is_navigation_finished_defaults_to_true_without_agent():
	# Without an agent, "navigation is done" is the safe interpretation —
	# this prevents callers from spinning on an entity that can't move.
	var m := _make_movement_without_agent()
	assert_true(m.is_navigation_finished())

func test_get_next_path_position_defaults_to_zero_without_agent():
	var m := _make_movement_without_agent()
	assert_eq(m.get_next_path_position(), Vector3.ZERO)

func test_nav_agent_path_resolves_on_ready():
	# Wire a real NavigationAgent3D sibling so we can verify the Movement
	# component finds it via the exported NodePath. We don't activate the
	# nav server, so we only verify the reference plumbing, not pathfinding.
	var parent := Node3D.new()
	add_child_autofree(parent)
	var agent := NavigationAgent3D.new()
	agent.name = "NavigationAgent"
	parent.add_child(agent)
	var m := Movement.new()
	m.nav_agent_path = NodePath("../NavigationAgent")
	parent.add_child(m)  # triggers _ready, resolves the path
	# After _ready, set_target_position should reach the real agent.
	m.set_target_position(Vector3(5, 0, 5))
	# Read it back via the property — confirms _nav_agent is wired up.
	assert_eq(m.target_position, Vector3(5, 0, 5))

func test_enable_avoidance_configures_layers_and_mask():
	var parent := Node3D.new()
	add_child_autofree(parent)
	var agent := AvoidanceAgent3D.new()
	agent.name = "NavigationAgent"
	parent.add_child(agent)
	var m := Movement.new()
	m.nav_agent_path = NodePath("../NavigationAgent")
	parent.add_child(m)
	m.enable_avoidance(2)  # commander id 2 -> team bit 1<<2
	assert_eq(agent.avoidance_layers, AvoidanceAgent3D.team_bit(2), "broadcasts on its team bit")
	# Cross-team avoidance is now one-sided via NavigationObstacle3D, so the mask is
	# own team bit (same-team reciprocal RVO) + every FOREIGN obstacle bit + the
	# exception pool — NOT a blanket avoid-all. See AvoidanceAgent3D._current_mask.
	var mask := agent.avoidance_mask
	assert_ne(mask & AvoidanceAgent3D.team_bit(2), 0, "masks own team bit (same-team reciprocal RVO)")
	assert_ne(mask & AvoidanceAgent3D.obstacle_bit(1), 0, "masks a foreign commander's obstacle bit")
	assert_eq(mask & AvoidanceAgent3D.obstacle_bit(2), 0, "does NOT mask its own obstacle bit")

func test_velocity_ready_forwards_from_agent_velocity_computed():
	var parent := Node3D.new()
	add_child_autofree(parent)
	var agent := NavigationAgent3D.new()
	agent.name = "NavigationAgent"
	parent.add_child(agent)
	var m := Movement.new()
	m.nav_agent_path = NodePath("../NavigationAgent")
	parent.add_child(m)
	watch_signals(m)
	# Manually emit on the underlying agent — the Movement component should
	# forward via its own velocity_ready signal.
	agent.velocity_computed.emit(Vector3(2, 0, 0))
	assert_signal_emitted_with_parameters(m, "velocity_ready", [Vector3(2, 0, 0)])

#region FLYING dive-attack
## Helper: a FLYING Movement under a Node3D parent at `pos`, _ready'd (so its height
## offset is seeded to AERIAL_HEIGHT).
func _make_flying(pos: Vector3) -> Movement:
	var parent := Node3D.new()
	add_child_autofree(parent)
	parent.global_position = pos
	var m := Movement.new()
	m.mode = Movement.Mode.FLYING
	parent.add_child(m)  # triggers _ready
	return m

func test_flying_starts_at_cruise_altitude():
	var m := _make_flying(Vector3(10, 0, 10))
	assert_almost_eq(m.height_offset(), Movement.AERIAL_HEIGHT, 0.001)

func test_flying_dive_descends_proportional_to_distance():
	# Target half a dive_distance away -> settles at half cruise altitude.
	var m := _make_flying(Vector3(10, 0, 10))
	var tgt := Vector2(10.0 + m.dive_distance * 0.5, 10.0)
	for i in 100:
		m.request_dive(tgt)
		m._update_flying_height()
	assert_almost_eq(m.height_offset(), Movement.AERIAL_HEIGHT * 0.5, 0.02)

func test_flying_dive_onto_target_reaches_ground():
	# Diving straight onto the target's XZ (distance 0) drops to ~ground level.
	var m := _make_flying(Vector3(10, 0, 10))
	for i in 100:
		m.request_dive(Vector2(10.0, 10.0))
		m._update_flying_height()
	assert_almost_eq(m.height_offset(), 0.0, 0.02)

func test_flying_climbs_back_when_dive_not_requested():
	# Dive down, then stop requesting -> eases back to cruise altitude.
	var m := _make_flying(Vector3(10, 0, 10))
	for i in 100:
		m.request_dive(Vector2(10.0, 10.0))
		m._update_flying_height()
	assert_lt(m.height_offset(), 0.1, "precondition: dove to the ground")
	for i in 100:
		m._update_flying_height()  # no request this tick
	assert_almost_eq(m.height_offset(), Movement.AERIAL_HEIGHT, 0.02)

func test_flying_stays_at_altitude_for_far_target():
	# A dive request for a target beyond dive_distance keeps the unit at cruise altitude.
	var m := _make_flying(Vector3(10, 0, 10))
	for i in 30:
		m.request_dive(Vector2(10.0 + m.dive_distance * 5.0, 10.0))
		m._update_flying_height()
	assert_almost_eq(m.height_offset(), Movement.AERIAL_HEIGHT, 0.001)

func test_request_dive_is_noop_outside_flying_mode():
	# A GROUNDED_DIRECT unit ignores dive requests and keeps a zero height offset.
	var parent := Node3D.new()
	add_child_autofree(parent)
	var m := Movement.new()
	m.mode = Movement.Mode.GROUNDED_DIRECT
	parent.add_child(m)
	m.request_dive(Vector2(10, 10))
	assert_almost_eq(m.height_offset(), 0.0, 0.001)
#endregion
