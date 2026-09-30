extends GutTest

## Work Detail — the Colonials' POSITIONAL passive: on a sentence completing, a Compound
## takes a percentage off the full cooldown of every ability pool on every structure it
## touches. Replaced the per-occupant passive RATE on 2026-09-17 — see
## gdd/systems/combat/colonial-dominion.md §The positional bonus is an event, not a rate.
##
## Two separable things are pinned here, and they are kept apart on purpose:
##   * WHAT "adjacent" MEANS — SpaceUtils.edge_adjacent_structures, edges only. The
##     definition is expected to change (a radius, a supply line), so it is tested against
##     synthetic footprints rather than through the ability.
##   * WHAT THE BONUS IS WORTH — Garrison._emit_positional_bonus / Abilities.reduce_all_
##     cooldowns, and the three things that switch a supporter off. Sentence timing itself
##     (when a completion fires) is tested in test_Garrison.gd; this file only asks what a
##     completion, once fired, actually does to a neighbour's pool.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_WorkDetail.gd -gexit

const CELLS: int = 24
const DIMS: Vector2i = Vector2i(2, 2)


## A real Map with its terrain/navmesh boot skipped — the same fixture test_OverlayPlacement
## uses, for the same reason: every question here is about cell_grid and footprints.
class TestMap extends Map:
	func _ready() -> void:
		pass


var _world: Node3D
var _map: TestMap
var _commander: Commander
var _other: Commander


func before_each() -> void:
	_world = Node3D.new()
	_map = TestMap.new()
	# Map resolves these @onready paths on tree entry even with its own _ready skipped.
	var region: NavigationRegion3D = NavigationRegion3D.new()
	region.name = "NavigationRegion"
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Body"
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "Shape"
	body.add_child(shape)
	region.add_child(body)
	_map.add_child(region)
	_map.cell_grid = []
	for x: int in CELLS:
		var col: Array = []
		for y: int in CELLS:
			col.append(null)
		_map.cell_grid.append(col)
	_world.add_child(_map)
	_commander = Commander.new()
	_commander.id = 1
	_world.add_child(_commander)
	_other = Commander.new()
	_other.id = 2
	_world.add_child(_other)
	add_child_autofree(_world)
	_commander.set_physics_process(false)
	_other.set_physics_process(false)


## Register `entity` on a DIMS footprint at `origin`, exactly as Map.add_structure would.
func _register(a_entity: Entity, a_origin: Vector2i) -> void:
	var cells: Array[Vector2i] = []
	for w: int in DIMS.x:
		for l: int in DIMS.y:
			var cell: Vector2i = a_origin + Vector2i(w, l)
			cells.append(cell)
			_map.cell_grid[cell.x][cell.y] = a_entity
	_map.structure_cell_map[a_entity] = cells
	a_entity.map = _map


# --- What "adjacent" means ---------------------------------------------------------

## Bare Entities on the grid: this half is about footprints, not about pieces.
func _stub(a_origin: Vector2i) -> Entity:
	var entity: Entity = autofree(Entity.new()) as Entity
	_register(entity, a_origin)
	return entity


func test_edge_contact_counts() -> void:
	var host := _stub(Vector2i(4, 4))
	var neighbor := _stub(Vector2i(6, 4))
	assert_eq(SU.edge_adjacent_structures(_map, host), [neighbor] as Array[Entity])


func test_corner_contact_does_not_count() -> void:
	# Two buildings meeting at a corner share no wall.
	var host := _stub(Vector2i(4, 4))
	_stub(Vector2i(6, 6))
	assert_eq(SU.edge_adjacent_structures(_map, host).size(), 0)


func test_a_gap_of_one_cell_does_not_count() -> void:
	var host := _stub(Vector2i(4, 4))
	_stub(Vector2i(7, 4))
	assert_eq(SU.edge_adjacent_structures(_map, host).size(), 0)


func test_a_structure_is_not_its_own_neighbour() -> void:
	var host := _stub(Vector2i(4, 4))
	assert_false(SU.edge_adjacent_structures(_map, host).has(host))


func test_one_neighbour_touching_along_two_cells_is_listed_once() -> void:
	# The 2×2 host meets the 2×2 neighbour across two cells; the neighbour is one building.
	var host := _stub(Vector2i(4, 4))
	var neighbor := _stub(Vector2i(4, 6))
	assert_eq(SU.edge_adjacent_structures(_map, host), [neighbor] as Array[Entity])


func test_an_unregistered_structure_has_no_neighbours() -> void:
	var loose: Entity = autofree(Entity.new()) as Entity
	assert_eq(SU.edge_adjacent_structures(_map, loose).size(), 0)


# --- What the passive is worth -----------------------------------------------------

## A real Colonial structure (the SAM) placed on the grid and owned by `a_commander`, with
## an Abilities pool bolted on. A shipped scene rather than bare nodes: Commandable's own
## _ready validates the piece — an id, its required children — and a hand-built stand-in
## fails all of it noisily without being any clearer.
func _structure(a_commander: Commander, a_origin: Vector2i, a_grants: Array) -> Commandable:
	var piece: Commandable = load(
		"res://scenes/entities/structures/cl/cl_defense_antiAircraft.tscn"
	).instantiate()
	_world.add_child(piece)
	piece.set_physics_process(false)
	piece.top_level = true
	if not a_grants.is_empty():
		var pool := Abilities.new()
		pool.name = "Abilities"
		pool.groups = [{"max_charges": 1, "cooldown_ticks": 100, "grants": a_grants}]
		piece.add_child(pool)
	piece.commander = a_commander
	_register(piece, a_origin)
	return piece


## A real Compound placed on the grid and owned by `a_commander`. No occupants needed: the
## bonus is a flat per-completion event now, not scaled by how many are held.
func _compound(a_commander: Commander, a_origin: Vector2i) -> Commandable:
	var piece: Commandable = load(
		"res://scenes/entities/structures/cl/cl_infrastructure.tscn"
	).instantiate()
	_world.add_child(piece)
	piece.set_physics_process(false)
	piece.top_level = true
	piece.commander = a_commander
	_register(piece, a_origin)
	return piece


func _pool_of(a_piece: Commandable) -> Abilities:
	return a_piece.get_node("Abilities") as Abilities


## Spends the beneficiary's one charge (starting its 100-tick cooldown) and returns its
## pool, ready for a completion event to act on.
func _spent_pool(a_beneficiary: Commandable) -> Abilities:
	var pool := _pool_of(a_beneficiary)
	pool._rebuild()
	pool.spend(&"scan")
	return pool


func test_an_unsupported_pool_is_untouched_by_no_completion() -> void:
	var beneficiary := _structure(_commander, Vector2i(4, 4), [&"scan"])
	var pool := _spent_pool(beneficiary)
	assert_almost_eq(pool._timers[0], 100.0, 0.0001)


func test_a_completion_takes_the_stated_percentage_off_the_full_cooldown() -> void:
	var beneficiary := _structure(_commander, Vector2i(4, 4), [&"scan"])
	var compound := _compound(_commander, Vector2i(6, 4))
	var pool := _spent_pool(beneficiary)
	compound.garrison._emit_positional_bonus()
	assert_almost_eq(pool._timers[0], 100.0 * (1.0 - Garrison.SENTENCE_COOLDOWN_BONUS), 0.0001)


func test_two_adjacent_compounds_each_apply_their_own_completion() -> void:
	var beneficiary := _structure(_commander, Vector2i(4, 4), [&"scan"])
	var north := _compound(_commander, Vector2i(4, 6))
	var east := _compound(_commander, Vector2i(6, 4))
	var pool := _spent_pool(beneficiary)
	north.garrison._emit_positional_bonus()
	east.garrison._emit_positional_bonus()
	assert_almost_eq(pool._timers[0], 100.0 * (1.0 - 2.0 * Garrison.SENTENCE_COOLDOWN_BONUS), 0.0001)


func test_nothing_is_banked_once_the_pool_is_already_charged() -> void:
	var beneficiary := _structure(_commander, Vector2i(4, 4), [&"scan"])
	var compound := _compound(_commander, Vector2i(6, 4))
	var pool := _pool_of(beneficiary)
	pool._rebuild()  # starts fully charged; nothing spent
	compound.garrison._emit_positional_bonus()
	assert_eq(pool.charges_of(&"scan"), 1, "already at capacity — the completion buys nothing")


func test_a_completion_can_finish_a_cooldown_outright() -> void:
	var beneficiary := _structure(_commander, Vector2i(4, 4), [&"scan"])
	var compound := _compound(_commander, Vector2i(6, 4))
	var pool := _spent_pool(beneficiary)
	pool._timers[0] = 5.0  # nearly recharged already
	compound.garrison._emit_positional_bonus()
	assert_true(pool.is_ready(&"scan"), "8% of 100 clears the last 5 ticks")


func test_a_corner_compound_lends_nothing() -> void:
	var beneficiary := _structure(_commander, Vector2i(4, 4), [&"scan"])
	var compound := _compound(_commander, Vector2i(6, 6))
	var pool := _spent_pool(beneficiary)
	compound.garrison._emit_positional_bonus()
	assert_almost_eq(pool._timers[0], 100.0, 0.0001, "corner contact shares no wall")


func test_an_enemy_compound_lends_nothing() -> void:
	var beneficiary := _structure(_commander, Vector2i(4, 4), [&"scan"])
	var compound := _compound(_other, Vector2i(6, 4))
	var pool := _spent_pool(beneficiary)
	compound.garrison._emit_positional_bonus()
	assert_almost_eq(pool._timers[0], 100.0, 0.0001)


func test_an_unfinished_compound_lends_nothing() -> void:
	var beneficiary := _structure(_commander, Vector2i(4, 4), [&"scan"])
	var compound := _compound(_commander, Vector2i(6, 4))
	compound.build_progress = Commandable.INITIAL_BUILD_PROGRESS
	var pool := _spent_pool(beneficiary)
	compound.garrison._emit_positional_bonus()
	assert_almost_eq(pool._timers[0], 100.0, 0.0001)


func test_an_unpowered_compound_lends_nothing() -> void:
	var beneficiary := _structure(_commander, Vector2i(4, 4), [&"scan"])
	var compound := _compound(_commander, Vector2i(6, 4))
	_commander.add_infrastructure(-500)
	assert_true(_commander.is_infrastructure_strained(), "the fixture is actually strained")
	var pool := _spent_pool(beneficiary)
	compound.garrison._emit_positional_bonus()
	assert_almost_eq(pool._timers[0], 100.0, 0.0001)


func test_a_piece_that_does_not_grant_work_detail_lends_nothing() -> void:
	# A structure with a Garrison but no Work Detail grant — a plain shelter, say — must not
	# start handing out the bonus just because something in it got consumed.
	var beneficiary := _structure(_commander, Vector2i(4, 4), [&"scan"])
	var plain := load("res://scenes/entities/structures/nt/nt_building_square.tscn").instantiate() \
		as Commandable
	_world.add_child(plain)
	plain.set_physics_process(false)
	plain.top_level = true
	plain.commander = _commander
	_register(plain, Vector2i(6, 4))
	var pool := _spent_pool(beneficiary)
	plain.garrison._emit_positional_bonus()
	assert_almost_eq(pool._timers[0], 100.0, 0.0001)
