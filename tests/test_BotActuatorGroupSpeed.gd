extends GutTest

## A COMPUTER COMMANDER'S GROUP ORDER MOVES TOGETHER, AS THE PLAYER'S DOES. BotActuator caps
## every mobile unit an order reached to the slowest one's speed (OrderDispatcher's rule), so a
## mixed wave arrives as one rather than its fast members running ahead (Alex, 2026-10-18).

var _us: Commander
var _act: BotActuator


func before_each() -> void:
	_us = Commander.new()
	_us.id = 1
	add_child_autofree(_us)
	_act = BotActuator.new(autofree(Map.new()) as Map)


func _mover(a_speed: float) -> Actor:
	var unit := FakePieces.unit({"speed": a_speed, "weapon": {"ground": 6.0}}) as Actor
	_us.add_child(unit)
	unit.ownership.commander = _us
	return unit


func test_a_group_move_caps_every_member_to_the_slowest() -> void:
	var slow: Actor = _mover(1.5)
	var fast: Actor = _mover(4.0)
	_act.move([slow, fast], Vector3(10.0, 0.0, 0.0))
	assert_almost_eq(fast.movement.speed_cap, 1.5, 0.001, "the fast one waits for the slow one")
	assert_almost_eq(slow.movement.speed_cap, 1.5, 0.001, "and the slow one goes at its own pace")


func test_a_group_attack_move_caps_every_member_to_the_slowest() -> void:
	var slow: Actor = _mover(1.5)
	var fast: Actor = _mover(4.0)
	_act.attack_move([slow, fast], Vector3(10.0, 0.0, 0.0))
	assert_almost_eq(fast.movement.speed_cap, 1.5, 0.001)


func test_a_lone_unit_is_not_capped() -> void:
	var fast: Actor = _mover(4.0)
	_act.move([fast], Vector3(10.0, 0.0, 0.0))
	assert_eq(fast.movement.speed_cap, 0.0, "nobody to wait for")
