extends GutTest

## A unit whose RVO follow partner is freed while it is held (killed, or garrisoned off the
## tree) must be able to drop or replace that partner. The held reference used to be typed, so
## handing the freed partner to a typed parameter raised a runtime error on every tick the
## command state re-drove the exception — 117 times in one self-play match on 2026-10-07.


## A Movement wrapping a real AvoidanceAgent3D, as test_AvoidanceYielding builds it.
func _make_movement() -> Movement:
	var parent := Node3D.new()
	add_child_autofree(parent)
	var agent := AvoidanceAgent3D.new()
	agent.name = "NavigationAgent"
	parent.add_child(agent)
	var movement := Movement.new()
	movement.nav_agent_path = NodePath("../NavigationAgent")
	parent.add_child(movement)
	return movement


func test_a_freed_partner_can_be_dropped() -> void:
	var movement: Movement = _make_movement()
	var partner: Actor = FakePieces.unit()
	add_child(partner)
	movement.set_avoidance_follow_target(partner)
	partner.free()
	movement.set_avoidance_follow_target(null)
	assert_null(movement._avoidance_follow, "the freed partner is let go without an error")


func test_a_freed_partner_can_be_replaced() -> void:
	var movement: Movement = _make_movement()
	var partner: Actor = FakePieces.unit()
	add_child(partner)
	movement.set_avoidance_follow_target(partner)
	partner.free()
	var next: Actor = FakePieces.unit()
	add_child_autofree(next)
	movement.set_avoidance_follow_target(next)
	assert_eq(movement._avoidance_follow, next)
