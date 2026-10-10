extends GutTest

## THE BOT'S COMMAND-CENTRE DROP: the best landable spot seen so far is judged against the
## relaxing threshold EVERY think, whether or not the current ranking — centred on an army
## whose scout may have dragged it into fog — found a landable spot of its own. Until
## 2026-10-10 the drop was only attempted when the current ranking found one, and a bot whose
## held spot sat behind a wandering anchor never dropped at all
## (gdd/systems/ai/bot-architecture.md §Where a building goes).
##
## The map is real grid maths with no navmesh, as in test_Deployment; the ranking and the
## verdict are the test's, so the only thing under test is the decision.

const CELLS: int = 24
const CENTRE_DIMS: Vector2i = Vector2i(4, 4)
## The ranking's cost bounds: the threshold relaxes from IDEAL at the start to WORST at
## BotDeployment.DEADLINE_SECONDS.
const IDEAL: float = 0.0
const WORST: float = 10.0


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


## Sees the whole map, owns the units the test places, and keeps the test's clock.
class FakeBot:
	extends Bot
	var units: Array = []
	var now: float = 0.0

	func has_vision_at(_a_world_pos: Vector3) -> bool:
		return true

	func get_units() -> Array:
		return units

	func seconds_elapsed() -> float:
		return now


## Lands where the test says and records the drop; nothing enters the world.
class FakeDeployment:
	extends Deployment
	## Footprint origins (cells) a command centre may land on.
	var ok_origins: Array[Vector2i] = []
	var dropped: Array[Vector2] = []
	var centre_scene: PackedScene = null

	func command_centre_scene() -> PackedScene:
		return centre_scene

	func is_production(_a_drop: Drop) -> bool:
		return false

	func verdict(a_drop: Drop, a_xz: Vector2) -> Verdict:
		if not has_charge(a_drop):
			return Verdict.NO_CHARGE
		var origin: Vector2i = _commander.map.footprint_origin(a_xz, footprint_dims(a_drop))
		return Verdict.OK if ok_origins.has(origin) else Verdict.BAD_FOOTPRINT

	func drop(a_drop: Drop, a_xz: Vector2) -> Array[Actor]:
		dropped.append(a_xz)
		_charges[a_drop] = 0
		return []


## Hands the deployment whatever ranking the test set, finished at once.
class FakeEconomy:
	extends BotEconomy
	var ranked: PackedInt64Array = PackedInt64Array()

	func start_spot_ranking(
		_a_anchor: Vector2, _a_dims: Vector2i, _a_is_production: bool
	) -> Dictionary:
		return {"done": true, "out": ranked}

	func continue_spot_ranking(_a_ranking: Dictionary, _a_allowance: int) -> int:
		return 0

	func spot_cost_bounds(_a_is_production: bool) -> Vector2:
		return Vector2(IDEAL, WORST)


var _map: TestMap
var _bot: FakeBot
var _deployment: FakeDeployment
var _economy: FakeEconomy
var _module: BotDeployment


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
	_bot = FakeBot.new()
	_bot.id = 2
	_bot.map = _map
	add_child_autofree(_bot)
	_deployment = FakeDeployment.new(_bot, 700, 300)
	_deployment.centre_scene = _centre_scene()
	_bot.deployment = _deployment
	_economy = FakeEconomy.new(_bot, null)
	_module = BotDeployment.new(_bot, _economy)
	# One unit, so the ranking has an anchor; where it stands is not read by a fake ranking.
	var unit: Actor = FakePieces.unit(FakePieces.PLAIN)
	add_child_autofree(unit)
	_bot.units.append(unit)


## A packed stand-in for the command centre: only its footprint is ever read.
func _centre_scene() -> PackedScene:
	var root := Node3D.new()
	var structure := Fixture.new()
	structure.name = "Fixture"
	structure.dimensions = CENTRE_DIMS
	root.add_child(structure)
	structure.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	return scene


## A ranked candidate as BotEconomy packs it: the cost in the high bits (quantised to a
## hundredth, offset so negatives pack), the cell index in the low bits.
func _candidate(a_origin: Vector2i, a_cost: float) -> int:
	var quantised: int = roundi(a_cost * 100.0) + 8192
	var index: int = a_origin.y * _map.terrain_grid.grid_width() + a_origin.x
	return (quantised << 44) | index


func _rank(a_candidates: Array) -> void:
	var out := PackedInt64Array()
	for c: Array in a_candidates:
		out.append(_candidate(c[0], c[1]))
	_economy.ranked = out


const GOOD: Vector2i = Vector2i(10, 10)
const FOGGED: Vector2i = Vector2i(2, 2)


func test_the_packed_candidate_round_trips() -> void:
	var packed: int = _candidate(GOOD, 5.0)
	assert_almost_eq(BotEconomy.ranked_cost(packed), 5.0, 0.001)
	assert_eq(BotEconomy.ranked_origin(packed, _map.terrain_grid.grid_width()), GOOD)


func test_a_landable_spot_dearer_than_the_threshold_is_held_not_dropped() -> void:
	_deployment.ok_origins = [GOOD]
	_rank([[GOOD, 5.0]])
	_module.tick()
	assert_eq(_deployment.dropped, [], "5.0 against a threshold of 0.0 at the start")
	assert_eq(_module._best_xz, VU.in_xz(_map.footprint_centroid(GOOD, CENTRE_DIMS)))


func test_a_held_spot_is_dropped_once_the_threshold_relaxes_past_it() -> void:
	# The regression: the anchor wanders into fog, so the ranking from then on finds nothing
	# landable — and the held spot must still be judged, and taken, when it becomes acceptable.
	_deployment.ok_origins = [GOOD]
	_rank([[GOOD, 5.0]])
	_module.tick()
	_rank([[FOGGED, 1.0]])  # cheaper, but nothing lands there
	_bot.now = 10.0  # threshold 1.67: not yet
	_module.tick()
	assert_eq(_deployment.dropped, [], "still too dear")
	_bot.now = 40.0  # threshold 6.67: the held spot clears it
	_module.tick()
	assert_eq(_deployment.dropped.size(), 1, "dropped on the held spot")
	assert_eq(_deployment.dropped[0], VU.in_xz(_map.footprint_centroid(GOOD, CENTRE_DIMS)))


func test_the_deadline_takes_whatever_is_held() -> void:
	_deployment.ok_origins = [GOOD]
	_rank([[GOOD, WORST]])
	_module.tick()
	assert_eq(_deployment.dropped, [])
	_rank([])
	_bot.now = BotDeployment.DEADLINE_SECONDS
	_module.tick()
	assert_eq(_deployment.dropped.size(), 1, "the worst the ranking can give is acceptable now")


func test_a_cheaper_landable_spot_replaces_the_held_one() -> void:
	var better := Vector2i(14, 14)
	_deployment.ok_origins = [GOOD, better]
	_rank([[GOOD, 5.0]])
	_module.tick()
	_rank([[better, 2.0]])
	_bot.now = 20.0  # threshold 3.33: the new spot clears it, the old would not
	_module.tick()
	assert_eq(_deployment.dropped.size(), 1)
	assert_eq(_deployment.dropped[0], VU.in_xz(_map.footprint_centroid(better, CENTRE_DIMS)))


func test_a_held_spot_that_no_longer_lands_is_forgotten() -> void:
	_deployment.ok_origins = [GOOD]
	_rank([[GOOD, 5.0]])
	_module.tick()
	_deployment.ok_origins = []  # something now stands there
	_rank([])
	_bot.now = BotDeployment.DEADLINE_SECONDS
	_module.tick()
	assert_eq(_deployment.dropped, [], "a spot that no longer lands is not dropped on")
	assert_null(_module._best_xz)


func test_nothing_landable_yet_means_nothing_dropped() -> void:
	_deployment.ok_origins = []
	_rank([[FOGGED, 0.0]])
	_bot.now = BotDeployment.DEADLINE_SECONDS
	_module.tick()
	assert_eq(_deployment.dropped, [])
