extends GutTest

## A PICKUP is a coin: the first ground unit of a commander with a purse to reach it collects
## it — energy, or ordnance charges into the depot — and the token leaves play. Aircraft and
## the world's own units collect nothing. Rules: gdd/systems/combat/environmental-pieces.md
## §Pickups.
##
## The reach query is the physics world's (no simulation stepper runs here), so the pieces
## stand in the tree and the hurtboxes settle over two physics frames before each check. The
## token's own physics process is OFF: an Entity steps its components itself, and a token that
## collected itself during the settle would be freed before the test asked it anything.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Pickup.gd -gexit

const NEUTRAL: int = 0
const OWN: int = 1

const GROUND: Dictionary = {"speed": 2.0, "vision": 8.0}
const FLYING: Dictionary = {"aerial": true, "flying": true, "vision": 8.0}
const ENERGY: int = 500
const ORDNANCE: StringName = &"scan"

var _commanders: Dictionary = {}


func before_each() -> void:
	_commanders = {}


func _commander(a_id: int) -> Commander:
	if not _commanders.has(a_id):
		var commander := Commander.new()
		commander.id = a_id
		add_child_autofree(commander)
		_commanders[a_id] = commander
	return _commanders[a_id]


func _unit(a_options: Dictionary, a_commander_id: int, a_at: Vector3) -> Actor:
	var unit := FakePieces.make(a_options) as Actor
	add_child_autofree(unit)
	unit.set_physics_process(false)
	unit.ownership.commander = _commander(a_commander_id)
	unit.global_position = a_at
	return unit


## A neutral token at `a_at` granting `a_energy`, or charges of `a_ability`.
func _token(a_at: Vector3, a_energy: int = ENERGY, a_ability: StringName = &"") -> Pickup:
	var piece: Entity = FakePieces.feature({"hp": 10.0})
	var pickup := Pickup.new()
	pickup.name = "Pickup"
	pickup.energy = a_energy
	pickup.ability = a_ability
	piece.add_child(pickup)
	add_child_autofree(piece)
	piece.set_physics_process(false)
	piece.ownership.commander = _commander(NEUTRAL)
	piece.global_position = a_at
	return pickup


func _settle() -> void:
	await wait_physics_frames(2)


func test_a_ground_unit_over_the_token_collects_its_energy() -> void:
	var pickup: Pickup = _token(Vector3.ZERO)
	_unit(GROUND, OWN, Vector3.ZERO)
	var before: int = _commander(OWN).energy
	# Watched BEFORE the await: GUT's signal watcher crashes when armed after one.
	watch_signals(pickup)
	await _settle()
	pickup.simulation_step(0.0)
	assert_eq(_commander(OWN).energy, before + ENERGY)
	assert_signal_emitted(pickup, "collected")
	assert_true(pickup.host().is_queued_for_deletion(), "the token leaves play")


func test_a_unit_out_of_reach_collects_nothing() -> void:
	var pickup: Pickup = _token(Vector3.ZERO)
	_unit(GROUND, OWN, Vector3(5.0, 0.0, 0.0))
	var before: int = _commander(OWN).energy
	await _settle()
	pickup.simulation_step(0.0)
	assert_eq(_commander(OWN).energy, before)
	assert_false(pickup.host().is_queued_for_deletion())


func test_an_aircraft_collects_nothing() -> void:
	var pickup: Pickup = _token(Vector3.ZERO)
	_unit(FLYING, OWN, Vector3.ZERO)
	var before: int = _commander(OWN).energy
	await _settle()
	pickup.simulation_step(0.0)
	assert_eq(_commander(OWN).energy, before)


func test_the_worlds_own_unit_collects_nothing() -> void:
	var pickup: Pickup = _token(Vector3.ZERO)
	_unit(GROUND, NEUTRAL, Vector3.ZERO)
	await _settle()
	pickup.simulation_step(0.0)
	assert_false(pickup.host().is_queued_for_deletion(), "the world has no purse")


func test_a_token_is_collected_once() -> void:
	var pickup: Pickup = _token(Vector3.ZERO)
	_unit(GROUND, OWN, Vector3.ZERO)
	var before: int = _commander(OWN).energy
	await _settle()
	pickup.simulation_step(0.0)
	pickup.simulation_step(0.0)
	assert_eq(_commander(OWN).energy, before + ENERGY, "the second tick grants nothing")


func test_an_ordnance_token_fills_the_depot() -> void:
	var pickup: Pickup = _token(Vector3.ZERO, 0, ORDNANCE)
	pickup.charges = 2
	_unit(GROUND, OWN, Vector3.ZERO)
	var before: int = _commander(OWN).energy
	await _settle()
	pickup.simulation_step(0.0)
	assert_eq(_commander(OWN).ordnance_depot.charges_of(ORDNANCE), 2)
	assert_eq(_commander(OWN).energy, before, "an ordnance token hands over no energy")
