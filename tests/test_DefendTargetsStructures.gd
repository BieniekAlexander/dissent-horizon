extends GutTest

## A DEFEND ORDER ALSO CONSIDERS EVERY ENEMY STRUCTURE.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##       -gtest=res://tests/test_DefendTargetsStructures.gd -gexit
##
## Aggro drops candidates ranked worse than the order's floor, and every other order stops at
## NON_COMBAT_UNITS, so an unarmed enemy structure is invisible to it. Defend widens its floor
## to NON_COMBAT_STRUCTURES in its constructor. Pinned: the defender takes the structure, still
## prefers a unit when one is there, an idle unit beside the same structure still ignores it,
## and a neutral structure is never taken. Why: gdd/systems/combat/target-acquisition.md
## §A Defend order also considers every enemy structure.
##
## PATHS, not preloads (see CLAUDE.md).

const RECRUIT: Dictionary = {"speed": 2.0, "vision": 8.0, "weapon": {"ground": 6.0}}
const IRREGULAR: Dictionary = {"speed": 2.0, "vision": 8.0}
## The Anarchical Stockpile: a structure with no weapons.
const STOCKPILE: Dictionary = {"structure": true}  # unarmed
const NEUTRAL_BUILDING: Dictionary = {"structure": true}

const DEFENDER: int = 1
const ENEMY: int = 2


func before_each() -> void:
	Fog._fogs_by_commander.clear()


func _commander(a_id: int) -> Commander:
	var c := Commander.new()
	c.id = a_id
	add_child_autofree(c)
	return c


func _piece(a_options: Dictionary, a_commander_id: int, a_at: Vector3) -> Entity:
	var e: Entity = (
		FakePieces.structure(a_options)
		if a_options.has("structure")
		else FakePieces.unit(a_options)
	)
	add_child_autofree(e)
	if a_commander_id != 0:
		e.ownership.commander = _commander(a_commander_id)
	e.global_position = a_at
	return e


func _defend(a_defender: Commandable) -> Defend:
	return Defend.new(CommandMessage.new(null, null, null, a_defender.global_position))


## What a Defend order at the defender's own feet picks up this tick, or null.
func _defend_pick(a_defender: Commandable) -> Entity:
	var next: Variant = _defend(a_defender).get_updated_state(a_defender)
	if next is Attack:
		return (next as Attack).message.target
	return null


func test_the_constructor_widens_the_floor_to_every_structure() -> void:
	var message := CommandMessage.new(null, null, null, Vector3.ZERO)
	assert_eq(
		message.target_priority,
		Entity.TargetPriority.NON_COMBAT_UNITS,
		"guards the fixture: the default floor skips unarmed structures"
	)
	Defend.new(message)
	assert_eq(message.target_priority, Entity.TargetPriority.NON_COMBAT_STRUCTURES)


func test_a_defender_takes_an_unarmed_enemy_structure() -> void:
	var defender := _piece(RECRUIT, DEFENDER, Vector3.ZERO) as Commandable
	var stockpile: Entity = _piece(STOCKPILE, ENEMY, Vector3(3.0, 0.0, 0.0))
	await wait_physics_frames(2)
	assert_eq(
		stockpile.target_priority,
		Entity.TargetPriority.NON_COMBAT_STRUCTURES,
		"guards the fixture: an unarmed, active structure"
	)
	assert_eq(_defend_pick(defender), stockpile)


func test_an_idle_unit_beside_the_same_structure_still_ignores_it() -> void:
	var defender := _piece(RECRUIT, DEFENDER, Vector3.ZERO) as Commandable
	_piece(STOCKPILE, ENEMY, Vector3(3.0, 0.0, 0.0))
	await wait_physics_frames(2)
	assert_null(
		defender.get_aggro_near_position(),
		"only Defend widens the floor; idle aggro stops at NON_COMBAT_UNITS"
	)


func test_a_unit_is_still_taken_before_the_structure() -> void:
	var defender := _piece(RECRUIT, DEFENDER, Vector3.ZERO) as Commandable
	_piece(STOCKPILE, ENEMY, Vector3(3.0, 0.0, 0.0))
	# Farther away than the structure, so rank — not distance — is what picks it.
	var intruder: Entity = _piece(IRREGULAR, ENEMY, Vector3(-5.0, 0.0, 0.0))
	await wait_physics_frames(2)
	assert_eq(_defend_pick(defender), intruder)


func test_a_neutral_structure_is_never_taken() -> void:
	var defender := _piece(RECRUIT, DEFENDER, Vector3.ZERO) as Commandable
	_piece(NEUTRAL_BUILDING, 0, Vector3(3.0, 0.0, 0.0))
	await wait_physics_frames(2)
	assert_null(_defend_pick(defender))
