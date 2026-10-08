extends GutTest

## A turret holds its attack target through a movement order: it keeps shooting it on the move
## until the target leaves range or sight, or hold fire, another Attack or a Stop drops it.
## gdd/systems/combat/turrets.md §Attacking while moving. Every piece is a fake.

const TURRET_GUN: Dictionary = {"ground": 6.0, "damage": 5.0, "turret": true}

var _shooter: Actor
var _target: Actor


func _commander(a_id: int) -> Commander:
	var c := Commander.new()
	c.id = a_id
	add_child_autofree(c)
	return c


func _setup(a_weapon: Dictionary) -> void:
	_shooter = FakePieces.unit({"speed": 2.0, "weapon": a_weapon})
	_target = FakePieces.unit({"hp": 100.0})
	add_child_autofree(_shooter)
	add_child_autofree(_target)
	_shooter.set_physics_process(false)
	_target.set_physics_process(false)
	_shooter.ownership.commander = _commander(1)
	_target.ownership.commander = _commander(2)
	_target.global_position = Vector3(3.0, 0.0, 0.0)


func _attack_then_move() -> void:
	_shooter.update_commands(Attack.new(CommandMessage.new(null, _target, null, Vector3.ZERO)))
	_shooter.update_commands(
		MoveCommand.new(CommandMessage.new(null, null, null, Vector3(0, 0, 5)))
	)


func _ticks(a_count: int) -> void:
	for _i: int in a_count:
		_shooter.orders._tick_held_attack_target()


func test_a_turret_keeps_shooting_its_target_on_the_move() -> void:
	_setup(TURRET_GUN)
	_attack_then_move()
	assert_same(_shooter.orders.held_attack_target, _target, "the target is held")
	_ticks(30)
	assert_lt(_target.defense.hp, 100.0, "and the turret fires at it while the move runs")


func test_a_body_aimed_weapon_holds_nothing() -> void:
	_setup({"ground": 6.0, "damage": 5.0})
	_attack_then_move()
	assert_null(_shooter.orders.held_attack_target, "it faces where it goes, so it stops to fire")


func test_hold_fire_drops_the_held_target() -> void:
	_setup(TURRET_GUN)
	_attack_then_move()
	_shooter.is_holding_fire = true
	_ticks(1)
	assert_null(_shooter.orders.held_attack_target)


func test_leaving_range_drops_the_held_target() -> void:
	_setup(TURRET_GUN)
	_attack_then_move()
	_target.global_position = Vector3(30.0, 0.0, 0.0)
	_ticks(1)
	assert_null(_shooter.orders.held_attack_target)


func test_a_stop_drops_the_held_target() -> void:
	_setup(TURRET_GUN)
	_attack_then_move()
	_shooter.update_commands(Stop.new(CommandMessage.new(null, null, null, Vector3.ZERO)))
	assert_null(_shooter.orders.held_attack_target)
