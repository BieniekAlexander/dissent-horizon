extends GutTest

## Infrastructure is a property of ANY commandable, not of structures: a unit carrying a
## non-zero `infrastructure` provides or consumes it like a building does. It counts for the
## owner while the piece is built and not merely planned, moves with ownership, and is
## withdrawn however the piece leaves play — a death, or a free that is not one (a consumed
## captive, an expiry).
##
## PATHS, not preloads — a file-scope preload of an entity scene poisons the Tool registry.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gtest=res://tests/test_InfrastructureContribution.gd -gexit

const UNIT_SCENE: String = "res://scenes/entities/units/an/an_bioLight_builder.tscn"
const STRUCTURE_SCENE: String = "res://scenes/entities/structures/an/an_barracks.tscn"
const PROVIDES: int = 40
const CONSUMES: int = -25

var _world: Node3D
var _a: Commander
var _b: Commander


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)
	_a = _commander(1)
	_b = _commander(2)


func _commander(a_id: int) -> Commander:
	var commander := Commander.new()
	commander.id = a_id
	_world.add_child(commander)
	commander.set_physics_process(false)
	return commander


func _unit(a_owner: Commander, a_infrastructure: int) -> Commandable:
	var unit: Commandable = load(UNIT_SCENE).instantiate() as Commandable
	unit.infrastructure = a_infrastructure
	a_owner.add_child(unit)
	unit.ownership.commander = a_owner
	return unit


func test_a_unit_provides_infrastructure() -> void:
	var before: int = _a.infrastructure_provided
	_unit(_a, PROVIDES)
	assert_eq(_a.infrastructure_provided, before + PROVIDES)


func test_a_unit_consumes_infrastructure() -> void:
	var before: int = _a.infrastructure_required
	_unit(_a, CONSUMES)
	assert_eq(_a.infrastructure_required, before - CONSUMES)


func test_the_default_contributes_nothing() -> void:
	var provided: int = _a.infrastructure_provided
	var required: int = _a.infrastructure_required
	_unit(_a, 0)
	assert_eq(_a.infrastructure_provided, provided)
	assert_eq(_a.infrastructure_required, required)


func test_it_moves_with_ownership() -> void:
	var a_before: int = _a.infrastructure_provided
	var b_before: int = _b.infrastructure_provided
	var unit := _unit(_a, PROVIDES)
	unit.ownership.commander = _b
	assert_eq(_a.infrastructure_provided, a_before, "the old owner is debited")
	assert_eq(_b.infrastructure_provided, b_before + PROVIDES, "the new owner is credited")


func test_a_free_that_is_not_a_death_still_withdraws_it() -> void:
	var before: int = _a.infrastructure_provided
	var unit := _unit(_a, PROVIDES)
	unit.free()
	assert_eq(_a.infrastructure_provided, before)


func test_an_unfinished_piece_contributes_only_once_built() -> void:
	var before: int = _a.infrastructure_provided
	var structure: Commandable = load(STRUCTURE_SCENE).instantiate() as Commandable
	structure.infrastructure = PROVIDES
	structure.begin_construction()
	_a.add_child(structure)
	structure.ownership.commander = _a
	for tracked in get_errors():
		if tracked.contains_text("entered the tree with no"):
			tracked.handled = true
	assert_eq(_a.infrastructure_provided, before, "a foundation is not working yet")
	structure.advance_build_progress(1.0)
	assert_eq(_a.infrastructure_provided, before + PROVIDES, "credited on the tick it finishes")
