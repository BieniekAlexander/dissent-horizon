extends GutTest

## REPAIR — a Repairs-equipped unit mending a damaged friendly MECHANICAL thing.
##
## Repair used to be the finish-construction command; that job is Assemble now (its
## coverage is tests/test_CoBuild.gd). What is pinned here is the split's whole point:
## the rule about WHICH targets can be mended, stated once in Repair.repairable_cause,
## and the fact that the right-click ladder reads that same rule rather than a copy.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Repair.gd -gexit

# The only repairer left in the roster. There WAS a second, MECH-framed one (the Kobold,
# cl_mechLight_support) used throughout this file; the piece was deleted, and no MECH-framed
# repairer replaced it — every unit declaring `repairs: true` is BIO. The frame restriction
# under test is on the PATIENT, so nothing here needed a mechanical medic to say it.
## Repairs; BIO frame.
const SAPPER := preload("res://scenes/entities/units/an/an_bioLight_antiStructure.tscn")
## No Repairs; BIO frame.
const RECRUIT := preload("res://scenes/entities/units/cl/cl_bioLight_antiLight.tscn")
const MATILDA := preload("res://scenes/entities/units/cl/cl_mechMedium_antiMech.tscn")      # MECH
## MECH frame; carries a garrison.
const CARAVEL := preload(
	"res://scenes/entities/units/cl/cl_aircraftMedium_transport.tscn"
)
const BUILDING := preload("res://scenes/entities/structures/nt/nt_building_square.tscn")

const PLAYER: int = 1
const ALLY: int = 1
const ENEMY: int = 2
const NEUTRAL: int = 0

func _commanded(a_id: int) -> Commander:
	var c := Commander.new()
	c.id = a_id
	add_child_autofree(c)
	return c

## A live entity owned by [a_commander_id]. Ownership is assigned directly rather than
## through initialize(), so no Map is needed — the same fixture test_MixedSelectionCommands
## and test_Garrison use.
func _entity(a_scene: PackedScene, a_commander_id: int) -> Commandable:
	var e := a_scene.instantiate() as Commandable
	add_child_autofree(e)
	e.ownership.commander = _commanded(a_commander_id)
	return e

## An entity of the given scene, owned by [a_commander_id], with `a_damage` hp knocked off.
func _damaged(a_scene: PackedScene, a_commander_id: int, a_damage: float = 50.0) -> Commandable:
	var e: Commandable = _entity(a_scene, a_commander_id)
	e.defense.apply_damage(a_damage)
	return e

func _message_for(a_target: Entity) -> CommandMessage:
	return CommandMessage.new(null, a_target)

func _cause(a_actor: Commandable, a_target: Variant) -> MoveCommand.PreconditionFailureCause:
	return Repair.repairable_cause(a_actor, a_target)

func _ok(a_actor: Commandable, a_target: Variant) -> bool:
	return _cause(a_actor, a_target) == MoveCommand.PreconditionFailureCause.NONE

## --- Who may repair --------------------------------------------------------
## The actor side of the rule is presence of the Repairs component and nothing else.

func test_a_unit_with_repairs_can_repair() -> void:
	assert_true(_ok(_entity(SAPPER, PLAYER), _damaged(MATILDA, PLAYER)))

func test_a_unit_without_repairs_cannot() -> void:
	assert_false(_ok(_entity(RECRUIT, PLAYER), _damaged(MATILDA, PLAYER)),
		"a rifleman standing next to a burning tank is not a mechanic")

func test_the_repairer_need_not_be_mechanical_itself() -> void:
	# The Sapper is BIO and repairs; the frame restriction is on the PATIENT, not the medic.
	var sapper: Commandable = _entity(SAPPER, PLAYER)
	assert_eq(sapper.defense.frame_type, Defense.FrameType.BIO, "precondition: the sapper is biological")
	assert_true(_ok(sapper, _damaged(MATILDA, PLAYER)))

## --- What may be repaired --------------------------------------------------

func test_a_damaged_friendly_mech_unit_qualifies() -> void:
	assert_true(_ok(_entity(SAPPER, PLAYER), _damaged(MATILDA, ALLY)))

func test_a_damaged_friendly_structure_qualifies() -> void:
	# "Including structures of that type" — a structure is a Commandable like any other,
	# so nothing in the rule distinguishes them; this pins that it stays that way.
	var building: Commandable = _damaged(BUILDING, PLAYER)
	assert_eq(building.defense.frame_type, Defense.FrameType.MECH, "precondition: the building is MECH")
	assert_true(_ok(_entity(SAPPER, PLAYER), building))

func test_a_biological_target_is_refused() -> void:
	assert_false(_ok(_entity(SAPPER, PLAYER), _damaged(RECRUIT, ALLY)),
		"infantry are mended by HealAOE, not by a repair vehicle")

func test_an_enemy_target_is_refused() -> void:
	assert_false(_ok(_entity(SAPPER, PLAYER), _damaged(MATILDA, ENEMY)))

func test_a_neutral_target_is_refused() -> void:
	# Same-commander, not merely non-hostile: a derelict neutral building is nobody's to mend.
	assert_false(_ok(_entity(SAPPER, PLAYER), _damaged(BUILDING, NEUTRAL)))

func test_an_undamaged_target_is_refused() -> void:
	# So a right-click on an intact friendly falls through the ladder to a move (or, for a
	# transport, to Occupy) instead of issuing an order with nothing to do.
	assert_false(_ok(_entity(SAPPER, PLAYER), _entity(MATILDA, ALLY)))

func test_a_null_target_is_refused() -> void:
	assert_false(_ok(_entity(SAPPER, PLAYER), null), "right-clicking empty ground is still a move")

func test_an_unfinished_structure_is_refused() -> void:
	# An unfinished structure reads as "hp below max" and would otherwise be silently
	# repaired to completion, bypassing Assemble (and its builder registration and XP).
	var site: Commandable = _entity(BUILDING, PLAYER)
	site.begin_construction()
	assert_false(site.is_built, "precondition: the site is under construction")
	assert_false(_ok(_entity(SAPPER, PLAYER), site), "finishing a building is Assemble's job")

## --- Hp actually moves -----------------------------------------------------

func test_restore_raises_hp_and_clamps_at_full() -> void:
	var tank: Commandable = _damaged(MATILDA, PLAYER, 60.0)
	var before: float = tank.defense.hp
	assert_false(tank.defense.restore(10.0), "not full yet")
	assert_almost_eq(tank.defense.hp, before + 10.0, 0.001)
	assert_true(tank.defense.restore(10_000.0), "reports full once it clamps")
	assert_almost_eq(tank.defense.hp, tank.defense.hp_max, 0.001, "never overshoots hp_max")

func test_repair_rate_is_per_second() -> void:
	var sapper: Commandable = _entity(SAPPER, PLAYER)
	var repairs := sapper.get_node("Repairs") as Repairs
	assert_almost_eq(repairs.repair_amount(1.0), repairs.repair_rate, 0.001)
	assert_almost_eq(repairs.repair_amount(0.5), repairs.repair_rate * 0.5, 0.001)

## --- The right-click ladder reads the same rule ----------------------------

func _resolve(a_selection: Array, a_target: Entity) -> Variant:
	return RTSController.resolve_command_class_for_selection("", a_selection, _message_for(a_target))

func test_right_clicking_a_damaged_friendly_mech_resolves_repair() -> void:
	assert_eq(_resolve([_entity(SAPPER, PLAYER)], _damaged(MATILDA, ALLY)), Repair)

func test_right_clicking_an_intact_friendly_mech_is_a_move() -> void:
	assert_eq(_resolve([_entity(SAPPER, PLAYER)], _entity(MATILDA, ALLY)), MoveCommand)

## Repair sits ABOVE Occupy in the ladder, and the damage gate is what makes that safe:
## an intact transport still loads on a right-click, a burning one gets mended. Both
## halves are asserted, because either alone would pass under the wrong ordering.
func test_a_transport_loads_when_intact_and_is_mended_when_hurt() -> void:
	var sapper: Commandable = _entity(SAPPER, PLAYER)
	assert_eq(_resolve([sapper], _entity(CARAVEL, ALLY)), Occupy,
		"right-clicking an intact transport still boards it")
	assert_eq(_resolve([sapper], _damaged(CARAVEL, ALLY)), Repair,
		"a damaged transport is repaired instead")

func test_a_non_repairer_right_clicking_a_damaged_friendly_is_a_move() -> void:
	assert_eq(_resolve([_entity(RECRUIT, PLAYER)], _damaged(MATILDA, ALLY)), MoveCommand)

## --- The command is offered in the HUD command set -------------------------

func test_the_parser_offers_repair_to_a_repairer_only() -> void:
	assert_has(CommandContextParser.commands_for(_entity(SAPPER, PLAYER)), "command_repair")
	assert_does_not_have(CommandContextParser.commands_for(_entity(RECRUIT, PLAYER)), "command_repair")
