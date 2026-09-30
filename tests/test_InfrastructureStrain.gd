extends GutTest

## What an INFRASTRUCTURE SHORTFALL costs: a commander whose upkeep exceeds its capacity
## has its BUILDINGS switched off — no weapons, and no abilities either, active or passive.
##
## The building is otherwise untouched. It still stands, still holds its grid cells, is
## still a target, and still produces (at the reduced rate strain already imposed). Units
## are not affected at all: strain is a fact about buildings drawing more than the network
## supplies, not about an army in the field.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gtest=res://tests/test_InfrastructureStrain.gd -gexit

const TURRET_SCENE: Dictionary = FakePieces.BUILDING
const UNIT_SCENE: Dictionary = FakePieces.BUILDER
const POOLED_ABILITY: StringName = &"scan"

var _commander: Commander


func before_each() -> void:
	_commander = autofree(Commander.new()) as Commander
	_commander.id = 1
	_commander.set_physics_process(false)
	add_child_autofree(_commander)


## Push the commander into strain by adding upkeep it cannot cover.
func _strain() -> void:
	_commander.add_infrastructure(-(Commander.BASE_INFRASTRUCTURE + 1))
	assert_true(_commander.is_infrastructure_strained(), "the fixture is actually strained")


func _piece(a_options: Dictionary) -> Commandable:
	var piece: Commandable = FakePieces.make(a_options)
	add_child_autofree(piece)
	piece.set_physics_process(false)
	piece.top_level = true
	piece.commander = _commander
	return piece


## `a_piece` with a one-charge pool granting POOLED_ABILITY bolted on.
func _with_pool(a_piece: Commandable) -> Abilities:
	var pool := Abilities.new()
	pool.name = "Abilities"
	pool.groups = [{"max_charges": 1, "cooldown_ticks": 100, "grants": [POOLED_ABILITY]}]
	a_piece.add_child(pool)
	return pool


# --- Who goes dark -----------------------------------------------------------------

func test_a_structure_is_unpowered_while_its_commander_is_strained() -> void:
	var turret := _piece(TURRET_SCENE)
	assert_false(turret.is_unpowered(), "powered while the network covers it")
	_strain()
	assert_true(turret.is_unpowered())


func test_a_unit_is_never_unpowered() -> void:
	var unit := _piece(UNIT_SCENE)
	_strain()
	assert_false(unit.is_unpowered(), "strain is about buildings, not the army")


func test_an_unowned_structure_is_never_unpowered() -> void:
	# Neutral map furniture has no commander to be short of anything.
	var turret: Commandable = FakePieces.make(TURRET_SCENE)
	add_child_autofree(turret)
	turret.set_physics_process(false)
	assert_false(turret.is_unpowered())


# --- Weapons -----------------------------------------------------------------------

func test_an_unpowered_structure_cannot_use_its_weapons() -> void:
	var turret := _piece(TURRET_SCENE)
	assert_true(turret.can_use_weapons(), "armed while powered")
	_strain()
	assert_false(turret.can_use_weapons())


func test_closing_the_shortfall_switches_the_weapons_back_on() -> void:
	var turret := _piece(TURRET_SCENE)
	_strain()
	_commander.add_infrastructure(Commander.BASE_INFRASTRUCTURE + 1)
	assert_false(_commander.is_infrastructure_strained())
	assert_true(turret.can_use_weapons())


# --- Abilities ---------------------------------------------------------------------

func test_an_unpowered_pool_is_not_operational() -> void:
	var pool := _with_pool(_piece(TURRET_SCENE))
	assert_true(pool.is_operational(), "operational while powered")
	_strain()
	assert_false(pool.is_operational())


func test_a_full_pool_on_an_unpowered_structure_is_not_ready() -> void:
	# The distinction the HUD draws: charges are there, and the ability still cannot fire.
	var pool := _with_pool(_piece(TURRET_SCENE))
	_strain()
	assert_eq(pool.charges_of(POOLED_ABILITY), 1, "the charge is still in the pool")
	assert_false(pool.is_ready(POOLED_ABILITY))


func test_an_unpowered_pool_cannot_be_spent() -> void:
	var pool := _with_pool(_piece(TURRET_SCENE))
	_strain()
	assert_false(pool.spend(POOLED_ABILITY), "nothing is half-fired")
	assert_eq(pool.charges_of(POOLED_ABILITY), 1, "and the charge is not consumed")


func test_a_units_pool_is_unaffected() -> void:
	var pool := _with_pool(_piece(UNIT_SCENE))
	_strain()
	assert_true(pool.is_operational())
	assert_true(pool.is_ready(POOLED_ABILITY))


func test_the_refusal_names_the_shortfall_rather_than_a_cooldown() -> void:
	# Its own cause, because the remedies differ: ABILITY_NO_CHARGES clears by waiting and
	# this one never does.
	var turret := _piece(TURRET_SCENE)
	_with_pool(turret)
	_strain()
	var message := CommandMessage.new(null, null, null, Vector3.ZERO)
	message.ability_type = POOLED_ABILITY
	assert_eq(
		Ability.meets_precondition(turret, message),
		MoveCommand.PreconditionFailureCause.UNPOWERED
	)


func test_the_refusal_is_not_deferred_by_the_additive_modifier() -> void:
	# Waiting closes a cooldown; it does not close a shortfall, so the modifier must not
	# queue the cast.
	var turret := _piece(TURRET_SCENE)
	_with_pool(turret)
	_strain()
	var message := CommandMessage.new(null, null, null, Vector3.ZERO)
	message.ability_type = POOLED_ABILITY
	message.defer_if_unaffordable = true
	assert_eq(
		Ability.meets_precondition(turret, message),
		MoveCommand.PreconditionFailureCause.UNPOWERED
	)
