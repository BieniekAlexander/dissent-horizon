extends GutTest

## Deferred deployment: the drops a slot holds, where each may land, and what landing one does.
## See gdd/systems/scenario-scripting/starting-formations.md §Deferred deployment.
##
## The map is real grid maths with no navmesh, and nothing is put in the tree: landing a
## structure and its neutral site are stubbed (TestDeployment), because what is under test is the
## rule and the bookkeeping, not Map.add_entities. Vision is a rectangle of cells the test sets.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Deployment.gd \
##       -gdir=res://tests/none -gexit

## 24 x 24 cells centred on the world origin.
const CELLS: int = 24
## The stand-in command centre's footprint.
const CENTRE_DIMS: Vector2i = Vector2i(4, 4)
const BANK_ENERGY: int = 700
const BANK_DOMINION: int = 300


class TestMap:
	extends Map

	func _ready() -> void:
		var shape := HeightMapShape3D.new()
		shape.map_width = CELLS + 1
		shape.map_depth = CELLS + 1
		var data := PackedFloat32Array()
		data.resize((CELLS + 1) * (CELLS + 1))
		shape.map_data = data
		height_map = shape
		terrain_grid = TerrainGrid.new()
		terrain_grid.height_map = shape
		terrain_grid.terrain_body = terrain_body
		add_child(terrain_grid)
		cell_grid = []
		for _x: int in CELLS:
			var column: Array = []
			for _z: int in CELLS:
				column.append(null)
			cell_grid.append(column)


## A commander whose vision is exactly the cells of `seen`.
class SightedCommander:
	extends Commander
	var seen: Rect2i = Rect2i(0, 0, CELLS, CELLS)

	func has_vision_at(a_world_pos: Vector3) -> bool:
		return seen.has_point(map.world_to_grid(VU.in_xz(a_world_pos)))


## Lands nothing in the world: records what it was asked to put down. `foreign_at` stands in for
## the units of other commanders, as world XZ positions; the slot's own are never in the way.
class TestDeployment:
	extends Deployment
	const UNIT_RADIUS: float = 0.4
	var foreign_at: Array[Vector2] = []
	var landed_at: Array[Vector2] = []
	var sites_at: Array[Vector2] = []

	## The stand-in command centre; the faction table is not consulted.
	var centre_scene: PackedScene = null

	func command_centre_scene() -> PackedScene:
		return centre_scene

	func _has_foreign_units_on(a_area: Rect2) -> bool:
		return foreign_at.any(
			func(a_xz: Vector2) -> bool: return Deployment.overlaps(a_xz, UNIT_RADIUS, a_area)
		)

	func units_on(_a_area: Rect2) -> Array:
		return []

	func _land(_a_scene: PackedScene, a_centre: Vector2) -> Actor:
		landed_at.append(a_centre)
		return Actor.new()

	func _land_site(a_centre: Vector2) -> void:
		sites_at.append(a_centre)


var _map: TestMap
var _commander: SightedCommander
var _deployment: TestDeployment


func before_each() -> void:
	_map = TestMap.new()
	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion"
	var body := StaticBody3D.new()
	body.name = "Body"
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	body.add_child(shape)
	region.add_child(body)
	_map.add_child(region)
	add_child_autofree(_map)
	_commander = autofree(SightedCommander.new())
	_commander.id = 1
	_commander.map = _map
	_deployment = TestDeployment.new(_commander, BANK_ENERGY, BANK_DOMINION)
	_deployment.centre_scene = _centre_scene()


## A packed stand-in for the faction's command centre: only its footprint is ever read.
func _centre_scene() -> PackedScene:
	var root := Node3D.new()
	var structure := Structure.new()
	structure.name = "Structure"
	structure.dimensions = CENTRE_DIMS
	root.add_child(structure)
	structure.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	return scene


## The world XZ centre of the `a_dims` footprint anchored at cell `a_origin`.
func _aim(a_origin: Vector2i, a_dims: Vector2i = CENTRE_DIMS) -> Vector2:
	return VU.in_xz(_map.footprint_centroid(a_origin, a_dims))


# ─── CHARGES ───────────────────────────────────────────────────────────────────


func test_a_slot_starts_with_one_command_centre_drop_and_no_extractor_drops() -> void:
	assert_eq(_deployment.charges(Deployment.Drop.COMMAND_CENTRE), 1)
	assert_eq(
		_deployment.charges(Deployment.Drop.EXTRACTOR),
		0,
		"the extractor drops wait for the command centre"
	)
	assert_false(_deployment.has_landed_command_centre())
	assert_false(_deployment.is_spent())


func test_the_extractor_drop_is_refused_before_the_command_centre() -> void:
	assert_eq(
		_deployment.verdict(Deployment.Drop.EXTRACTOR, _aim(Vector2i(4, 4), Vector2i(2, 2))),
		Deployment.Verdict.NO_CHARGE
	)


# ─── WHERE A DROP MAY LAND ─────────────────────────────────────────────────────


func test_open_ground_in_full_vision_is_accepted() -> void:
	assert_eq(
		_deployment.verdict(Deployment.Drop.COMMAND_CENTRE, _aim(Vector2i(8, 8))),
		Deployment.Verdict.OK
	)


func test_every_footprint_cell_must_be_in_vision() -> void:
	# Vision stops one cell short of the footprint's far edge: the centre is seen, a corner is not.
	_commander.seen = Rect2i(0, 0, 11, CELLS)
	assert_eq(
		_deployment.verdict(Deployment.Drop.COMMAND_CENTRE, _aim(Vector2i(8, 8))),
		Deployment.Verdict.OUT_OF_VISION
	)


func test_a_footprint_off_the_map_is_refused() -> void:
	assert_eq(
		_deployment.verdict(Deployment.Drop.COMMAND_CENTRE, _aim(Vector2i(CELLS - 2, 8))),
		Deployment.Verdict.BAD_FOOTPRINT
	)


func test_a_footprint_on_an_occupied_cell_is_refused() -> void:
	# An extraction site occupies its cells like any structure, so neither drop may land on one.
	_map.cell_grid[9][9] = autofree(Entity.new())
	assert_eq(
		_deployment.verdict(Deployment.Drop.COMMAND_CENTRE, _aim(Vector2i(8, 8))),
		Deployment.Verdict.BAD_FOOTPRINT
	)


func test_another_commanders_unit_on_the_footprint_refuses_the_drop() -> void:
	_deployment.foreign_at = [_aim(Vector2i(8, 8))]
	assert_eq(
		_deployment.verdict(Deployment.Drop.COMMAND_CENTRE, _aim(Vector2i(8, 8))),
		Deployment.Verdict.UNITS_IN_THE_WAY
	)


func test_a_unit_is_on_the_footprint_when_its_body_reaches_over_the_edge() -> void:
	var area: Rect2 = Deployment.footprint_area(_map, Vector2i(8, 8), CENTRE_DIMS)
	assert_true(Deployment.overlaps(area.get_center(), 0.4, area), "standing inside")
	assert_true(
		Deployment.overlaps(area.position - Vector2(0.3, 0.0), 0.4, area),
		"standing outside, body reaching in"
	)
	assert_false(
		Deployment.overlaps(area.position - Vector2(0.5, 0.0), 0.4, area),
		"standing clear of the edge"
	)


func test_the_footprint_area_covers_exactly_its_cells() -> void:
	var area: Rect2 = Deployment.footprint_area(_map, Vector2i(8, 8), CENTRE_DIMS)
	assert_almost_eq(area.size, Vector2(CENTRE_DIMS) * Map.CELL_SIZE, Vector2.ONE * 1e-4)
	assert_almost_eq(area.get_center(), _aim(Vector2i(8, 8)), Vector2.ONE * 1e-4)


# ─── LANDING ───────────────────────────────────────────────────────────────────


func test_the_command_centre_landing_credits_the_bank_and_grants_two_extractor_drops() -> void:
	watch_signals(_deployment)
	var landed: Array[Actor] = _deployment.drop(
		Deployment.Drop.COMMAND_CENTRE, _aim(Vector2i(8, 8))
	)
	for actor: Actor in landed:
		autofree(actor)
	assert_eq(landed.size(), 1, "the command centre is what it put in play")
	assert_almost_eq(_deployment.landed_at[0], _aim(Vector2i(8, 8)), Vector2.ONE * 1e-4)
	assert_eq(_commander.energy, BANK_ENERGY, "the starting energy arrives with the command centre")
	assert_eq(_commander.dominion, BANK_DOMINION, "and the starting dominion")
	assert_true(_deployment.has_landed_command_centre())
	assert_eq(_deployment.charges(Deployment.Drop.EXTRACTOR), Deployment.EXTRACTOR_DROP_CHARGES)
	assert_false(_deployment.is_spent())
	assert_signal_emitted(_deployment, "changed")


func test_a_refused_drop_changes_nothing() -> void:
	_commander.seen = Rect2i()
	var landed: Array[Actor] = _deployment.drop(
		Deployment.Drop.COMMAND_CENTRE, _aim(Vector2i(8, 8))
	)
	assert_true(landed.is_empty())
	assert_eq(_commander.energy, 0, "no bank for a drop that did not land")
	assert_eq(_deployment.charges(Deployment.Drop.COMMAND_CENTRE), 1)


func test_each_extractor_drop_lands_on_a_new_site_and_the_last_spends_the_deployment() -> void:
	autofree(_deployment.drop(Deployment.Drop.COMMAND_CENTRE, _aim(Vector2i(2, 2)))[0])
	for origin: Vector2i in [Vector2i(12, 12), Vector2i(16, 16)]:
		var aim: Vector2 = _aim(origin, Vector2i(2, 2))
		assert_eq(_deployment.verdict(Deployment.Drop.EXTRACTOR, aim), Deployment.Verdict.OK)
		autofree(_deployment.drop(Deployment.Drop.EXTRACTOR, aim)[0])
		assert_almost_eq(
			_deployment.sites_at.back(),
			aim,
			Vector2.ONE * 1e-4,
			"the site goes down where the extractor does"
		)
	assert_eq(_deployment.landed_at.size(), 3, "a command centre and two extractors")
	assert_true(_deployment.is_spent(), "the last charge spends the deployment")
	assert_eq(
		_deployment.verdict(Deployment.Drop.EXTRACTOR, _aim(Vector2i(20, 4), Vector2i(2, 2))),
		Deployment.Verdict.NO_CHARGE
	)


# ─── THE BOT'S DEADLINE ────────────────────────────────────────────────────────


func test_the_bot_wants_the_ideal_spot_at_the_start_and_takes_any_by_the_deadline() -> void:
	var bounds := Vector2(-4.0, 20.0)
	assert_eq(BotDeployment.acceptable_cost(0.0, bounds), bounds.x)
	assert_eq(BotDeployment.acceptable_cost(BotDeployment.DEADLINE_SECONDS * 0.5, bounds), 8.0)
	assert_eq(BotDeployment.acceptable_cost(BotDeployment.DEADLINE_SECONDS, bounds), bounds.y)
	assert_eq(
		BotDeployment.acceptable_cost(BotDeployment.DEADLINE_SECONDS * 3.0, bounds),
		bounds.y,
		"past the deadline it stays at the worst, never beyond it"
	)
