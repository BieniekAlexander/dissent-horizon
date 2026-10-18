extends GutTest

## A unit performing an action is PLANTED (Movement.set_planted, Alex 2026-10-18): out of RVO
## both ways, and broadcast as a standing obstacle every team's agents steer round. And a unit
## avoidance keeps refusing its way is BLOCKED (Movement.BLOCKED_TICKS): near its goal it takes
## the goal as reached, elsewhere it steps aside. The trajectories were measured with a live
## scenario (navigation-and-pathing.md §A blocked unit); what is pinned here is the state that
## produces them.

const COMMANDER: int = 3

var _agent: AvoidanceAgent3D
var _movement: Movement
var _obstacle: NavigationObstacle3D


func before_each() -> void:
	var parent := Node3D.new()
	add_child_autofree(parent)
	_agent = AvoidanceAgent3D.new()
	_agent.name = "NavigationAgent"
	parent.add_child(_agent)
	_movement = Movement.new()
	_movement.nav_agent_path = NodePath("../NavigationAgent")
	parent.add_child(_movement)
	_obstacle = NavigationObstacle3D.new()
	parent.add_child(_obstacle)
	_obstacle.avoidance_layers = AvoidanceAgent3D.obstacle_bit(COMMANDER)
	_movement.avoidance_obstacle = _obstacle
	_movement.is_active = true
	_agent.enable_avoidance(COMMANDER)


func test_a_planted_agent_is_out_of_rvo_both_ways() -> void:
	_movement.set_planted(true)
	assert_eq(_agent.avoidance_layers, 0, "nobody does reciprocal RVO with it")
	assert_eq(_agent.avoidance_mask, 0, "and it steers round nothing, so nothing pushes it")


func test_a_planted_unit_stands_as_an_obstacle_to_every_team() -> void:
	_movement.set_planted(true)
	assert_eq(_obstacle.avoidance_layers, AvoidanceAgent3D.STANDING_OBSTACLE_BIT)
	var teammate := AvoidanceAgent3D.new()
	autofree(teammate)
	teammate.enable_avoidance(COMMANDER)
	assert_ne(
		teammate.avoidance_mask & AvoidanceAgent3D.STANDING_OBSTACLE_BIT, 0, "its own side too"
	)


func test_unplanting_puts_it_back() -> void:
	var layers: int = _agent.avoidance_layers
	var mask: int = _agent.avoidance_mask
	_movement.set_planted(true)
	_movement.set_planted(false)
	assert_eq(_agent.avoidance_layers, layers)
	assert_eq(_agent.avoidance_mask, mask)
	assert_eq(_obstacle.avoidance_layers, AvoidanceAgent3D.obstacle_bit(0), "its owner's channel")


func test_a_switched_off_unit_is_never_planted() -> void:
	_movement.is_active = false
	_movement.set_planted(true)
	assert_false(_movement.is_planted(), "a deployed piece stands on its own terms")


func test_a_unit_silenced_for_an_occupy_is_not_planted() -> void:
	_movement.suppress_avoidance_layers()
	_movement.set_planted(true)
	assert_false(_movement.is_planted())


func test_a_planted_unit_unplants_when_silenced() -> void:
	_movement.set_planted(true)
	_movement.suppress_avoidance_layers()
	assert_false(_movement.is_planted())
	assert_eq(_obstacle.avoidance_layers, 0, "silenced, not standing")


# --- Blocked ------------------------------------------------------------------------------


func _refuse(a_ticks: int) -> void:
	_movement._is_target_submitted = true
	_movement._requested_speed = _movement.effective_max_speed()
	for i: int in a_ticks:
		_movement._count_blocked(Vector3.ZERO)


func test_refused_ticks_count_and_a_granted_one_resets() -> void:
	_movement.speed = 2.0
	_refuse(4)
	assert_eq(_movement._blocked_ticks, 4)
	_movement._count_blocked(Vector3(2.0, 0.0, 0.0))
	assert_eq(_movement._blocked_ticks, 0, "moving again")


func test_a_slow_request_is_never_blocked() -> void:
	# Accelerating from a standstill asks for little, and gets little: not a refusal.
	_movement.speed = 2.0
	_movement._is_target_submitted = true
	_movement._requested_speed = 0.1
	_movement._count_blocked(Vector3.ZERO)
	assert_eq(_movement._blocked_ticks, 0)


func test_a_new_goal_forgets_the_block() -> void:
	_movement.speed = 2.0
	_refuse(Movement.BLOCKED_TICKS)
	_movement._submit_target(Vector3(10, 0, 0))
	assert_eq(_movement._blocked_ticks, 0)
