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

func test_set_avoidance_team_configures_both_layers_and_mask():
	var parent := Node3D.new()
	add_child_autofree(parent)
	var agent := NavigationAgent3D.new()
	agent.name = "NavigationAgent"
	parent.add_child(agent)
	var m := Movement.new()
	m.nav_agent_path = NodePath("../NavigationAgent")
	parent.add_child(m)
	m.set_avoidance_team(3)
	var expected: int = 1 << 3
	assert_eq(agent.avoidance_layers, expected, "avoidance_layers set")
	assert_eq(agent.avoidance_mask, expected, "avoidance_mask set")

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
