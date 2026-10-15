extends GutTest

## The determinism digest covers everything a physics tick governs, and is keyed by spawn
## serial rather than tree order. gdd/systems/commands/netplay.md §Decisions. Every piece is a
## fake; the scenario is a bare instance holding one commander.

var _scenario: Scenario
var _world: Node3D
var _commander: Commander
var _rng_state: int


func before_each() -> void:
	_rng_state = SU.rng.state
	_scenario = Scenario.new()
	_world = Node3D.new()
	add_child_autofree(_world)
	_commander = _new_commander(1)
	_scenario.commanders = [_commander]


func after_each() -> void:
	SU.rng.state = _rng_state
	_scenario.free()


func _new_commander(a_id: int) -> Commander:
	var commander := Commander.new()
	commander.id = a_id
	_world.add_child(commander)
	commander.set_physics_process(false)
	return commander


## A fake unit under `a_commander`, registered with the scenario so it carries a serial, at
## `a_at`, with its own ticking switched off so nothing moves between digests.
func _unit(a_commander: Commander, a_at: Vector3, a_options: Dictionary = {}) -> Actor:
	var piece := FakePieces.unit(a_options) as Actor
	a_commander.add_child(piece)
	piece.set_physics_process(false)
	piece.global_position = a_at
	piece.spawn_serial = _scenario.register_piece(piece)
	return piece


func test_the_same_state_gives_the_same_digest() -> void:
	_unit(_commander, Vector3(1, 0, 2))
	_unit(_commander, Vector3(3, 0, 4))
	assert_eq(SimulationDigest.of(_scenario), SimulationDigest.of(_scenario))


func test_tree_order_does_not_change_the_digest() -> void:
	var first: Actor = _unit(_commander, Vector3(1, 0, 2))
	_unit(_commander, Vector3(3, 0, 4))
	var before: String = SimulationDigest.state_string(_scenario)
	_commander.move_child(first, -1)
	assert_eq(SimulationDigest.state_string(_scenario), before)


func test_each_piece_line_leads_with_its_serial() -> void:
	var piece: Actor = _unit(_commander, Vector3(1, 0, 2))
	assert_string_contains(SimulationDigest.state_string(_scenario), "#%d " % piece.spawn_serial)


func test_two_pieces_that_swap_places_change_the_digest() -> void:
	# Sorting by position alone would see the same pair; keying by serial does not.
	var a: Actor = _unit(_commander, Vector3(1, 0, 2))
	var b: Actor = _unit(_commander, Vector3(3, 0, 4))
	var before: String = SimulationDigest.of(_scenario)
	a.global_position = Vector3(3, 0, 4)
	b.global_position = Vector3(1, 0, 2)
	assert_ne(SimulationDigest.of(_scenario), before)


func test_a_queued_order_changes_the_digest() -> void:
	var piece: Actor = _unit(_commander, Vector3(1, 0, 2), {"speed": 4.0})
	var before: String = SimulationDigest.of(_scenario)
	var message := CommandMessage.new(null)
	message.world_position = Vector3(9, 0, 9)
	piece.command_receiver.update_commands(MoveCommand.new(message), false)
	assert_ne(SimulationDigest.of(_scenario), before)


func test_a_weapon_cooldown_changes_the_digest() -> void:
	var piece: Actor = _unit(_commander, Vector3(1, 0, 2), {"weapon": {"ground": 4.0}})
	var before: String = SimulationDigest.of(_scenario)
	var weapon: Weapon = piece.weapon_inventory.get_weapons()[0]
	weapon._split_timer_ticks += 3
	assert_ne(SimulationDigest.of(_scenario), before)


func test_a_random_draw_changes_the_digest() -> void:
	_unit(_commander, Vector3(1, 0, 2))
	var before: String = SimulationDigest.of(_scenario)
	SU.rng.randi()
	assert_ne(SimulationDigest.of(_scenario), before)


func test_a_resource_change_changes_the_digest() -> void:
	var before: String = SimulationDigest.of(_scenario)
	_commander.energy += 5
	assert_ne(SimulationDigest.of(_scenario), before)


## Numbers are written by arithmetic, not by the platform's "%.3f", which rounds an exact tie to
## even on one platform and away from zero on another.
func test_a_number_on_an_exact_tie_rounds_away_from_zero_everywhere() -> void:
	assert_eq(SimulationDigest.fixed(-39.5625, 3), "-39.563")
	assert_eq(SimulationDigest.fixed(39.5625, 3), "39.563")


func test_numbers_keep_their_places_and_sign() -> void:
	assert_eq(SimulationDigest.fixed(0.05, 2), "0.05")
	assert_eq(SimulationDigest.fixed(-0.25, 1), "-0.3")
	assert_eq(SimulationDigest.fixed(-0.0001, 3), "0.000", "a value that rounds to nothing")
	assert_eq(SimulationDigest.fixed(12.0, 0), "12")
	assert_eq(SimulationDigest.fixed_vector(Vector3(1.0, -2.5, 0.125), 2), "1.00,-2.50,0.13")
