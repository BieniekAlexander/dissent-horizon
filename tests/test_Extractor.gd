extends GutTest

## Unit tests for the Extractor-on-ExtractionSite placement rule (EnergyExtractor.valid_placement).
## The rule used to live on Extractor.valid_placement; it moved to EnergyExtractor (extractors are
## overlay structures, gated on their EnergyExtractor component — see Build.meets_precondition).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Extractor.gd
##
## The map here is a real (orphan) Map with a flat heightmap rather than a stub with
## hand-rolled coordinate math, because the rule IS coordinate math now: an extractor must land
## squarely on its extraction site, which Map.footprint_origin decides. A stub that rounded
## world→grid its own way would pass while the game misplaced every extractor.
##
## The overlay binding at build time (extractor references the extraction site, extraction site
## references the
## extractor, extractor not grid-registered) is exercised by the headless s1.tscn run; here we pin
## down WHEN an extractor may be placed.

## Cells across the test map, and the size of an extraction site / extractor footprint (both 2×2 in
## the
## game — an even footprint, which centres on a grid CORNER rather than on a cell).
const _CELLS: int = 4
const _DIMS: Vector2i = Vector2i(2, 2)


## A real Map with only its terrain/navmesh boot skipped: Map._ready() builds a TerrainGrid
## and a NavManager, which the coordinate helpers under test never touch and which would
## drag the navigation server into a unit test. Everything that decides where a structure
## lands (footprint_origin, footprint_cells, concentric_structure) is the real thing.
class TestMap:
	extends Map

	func _ready() -> void:
		pass


## A flat Map of _CELLS × _CELLS cells, centred on the origin: with map_width W, cell k
## spans world x ∈ [k - (W-1)/2, k+1 - (W-1)/2). Added to the tree because Node3D's
## global_transform — which footprint_origin resolves world XZ through — is only defined
## for a node that is in one; the NavigationRegion/Body/Shape children exist because Map's
## @onready vars resolve them on the way in, whatever _ready() itself does.
func _make_map() -> Map:
	var map: Map = TestMap.new()
	var region: NavigationRegion3D = NavigationRegion3D.new()
	region.name = "NavigationRegion"
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Body"
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "Shape"
	body.add_child(collision)
	region.add_child(body)
	map.add_child(region)
	add_child_autofree(map)
	var shape: HeightMapShape3D = HeightMapShape3D.new()
	shape.map_width = _CELLS + 1
	shape.map_depth = _CELLS + 1
	shape.map_data = PackedFloat32Array()
	shape.map_data.resize((_CELLS + 1) * (_CELLS + 1))
	map.height_map = shape
	map.cell_grid = []
	for x in range(_CELLS):
		var col: Array = []
		for y in range(_CELLS):
			col.append(null)
		map.cell_grid.append(col)
	return map


## Register `structure` on the 2×2 footprint whose min-corner cell is `origin`, exactly as
## Map.add_structure would, and return the world XZ of its centre — the one aim that puts
## a 2×2 extractor squarely on top of it.
func _place(a_map: Map, a_structure: Entity, a_origin: Vector2i) -> Vector2:
	var cells: Array[Vector2i] = []
	for w in range(_DIMS.x):
		for l in range(_DIMS.y):
			var cell: Vector2i = a_origin + Vector2i(w, l)
			cells.append(cell)
			a_map.cell_grid[cell.x][cell.y] = a_structure
	a_map.structure_cell_map[a_structure] = cells
	return VU.in_xz(a_map.footprint_centroid(a_origin, _DIMS))


func _msg(a_map: Map, a_xz: Vector2) -> CommandMessage:
	return CommandMessage.new(a_map, null, null, Vector3(a_xz.x, 0, a_xz.y))


func _extraction_site(a_map: Map, a_origin: Vector2i) -> Array:
	var dep: Entity = autofree(Entity.new()) as Entity
	var site: ExtractionSite = ExtractionSite.new()
	site.name = "ExtractionSite"
	dep.add_child(site)
	return [dep, _place(a_map, dep, a_origin)]


func test_rejects_bare_ground() -> void:
	var map: Map = _make_map()
	assert_false(
		EnergyExtractor.valid_placement(_msg(map, Vector2.ZERO), _DIMS),
		"an extractor may not be built on empty cells"
	)


func test_rejects_non_site_structure() -> void:
	var map: Map = _make_map()
	var other: Commandable = autofree(Commandable.new()) as Commandable
	var centre: Vector2 = _place(map, other, Vector2i(1, 1))
	assert_false(
		EnergyExtractor.valid_placement(_msg(map, centre), _DIMS),
		"an extractor may not be built on a non-site structure"
	)


func test_accepts_free_site_aimed_dead_centre() -> void:
	var map: Map = _make_map()
	var centre: Vector2 = _extraction_site(map, Vector2i(1, 1))[1]
	assert_true(
		EnergyExtractor.valid_placement(_msg(map, centre), _DIMS),
		"an extractor may be built on a free extraction site when aimed at its centre"
	)


## The rule this file exists for: overlapping the extraction site is NOT enough. An aim half a
## cell off resolves to a footprint that still covers two of the extraction site's four cells, and
## is refused — otherwise the extractor would be accepted here and then snap onto the extraction
## site at
## placement, moving out from under the player's cursor.
func test_rejects_partial_overlap() -> void:
	var map: Map = _make_map()
	var centre: Vector2 = _extraction_site(map, Vector2i(1, 1))[1]
	for offset: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var aim: Vector2 = centre + offset * Map.CELL_SIZE
		assert_false(
			EnergyExtractor.valid_placement(_msg(map, aim), _DIMS),
			"an extractor offset by %s only partly covers the extraction site" % offset
		)


## Half a cell either way still resolves to the extraction site's own footprint (footprint_origin
## rounds to the nearest corner), so the player has a cell's worth of aim, not four.
func test_accepts_aim_within_half_a_cell() -> void:
	var map: Map = _make_map()
	var centre: Vector2 = _extraction_site(map, Vector2i(1, 1))[1]
	for offset: Vector2 in [Vector2(0.4, 0), Vector2(-0.4, 0), Vector2(0, 0.4), Vector2(0, -0.4)]:
		var aim: Vector2 = centre + offset * Map.CELL_SIZE
		assert_true(
			EnergyExtractor.valid_placement(_msg(map, aim), _DIMS),
			"an aim %s off still resolves to the extraction site's own footprint" % offset
		)


func test_rejects_already_worked_site() -> void:
	var map: Map = _make_map()
	var placed: Array = _extraction_site(map, Vector2i(1, 1))
	ExtractionSite.of(placed[0]).extractor = autofree(Commandable.new()) as Commandable
	assert_false(
		EnergyExtractor.valid_placement(_msg(map, placed[1] as Vector2), _DIMS),
		"no second extractor on an extraction site that already has one"
	)


func test_rejects_out_of_bounds() -> void:
	var map: Map = _make_map()
	assert_false(
		EnergyExtractor.valid_placement(_msg(map, Vector2(99, 99)), _DIMS),
		"an extractor may not be built off the grid"
	)


#region Site-only overlay pieces
## An overlay piece that draws no energy (the Technocratic Lab, whose DominionGenerator pays
## dominion) may stand on an extraction site but not in a lithium pond: `a_allow_pond` false
## shuts only the pond route, so the site rule must be exactly what it is for an extractor.
func test_a_site_only_piece_takes_a_free_site() -> void:
	var map: Map = _make_map()
	var centre: Vector2 = _extraction_site(map, Vector2i(1, 1))[1]
	assert_true(
		EnergyExtractor.valid_placement(_msg(map, centre), _DIMS, false, false, false),
		"the site route is unchanged when ponds are shut"
	)


func test_a_site_only_piece_is_refused_a_worked_site() -> void:
	var map: Map = _make_map()
	var placed: Array = _extraction_site(map, Vector2i(1, 1))
	(placed[0] as Entity).get_node("ExtractionSite").extractor = autofree(Commandable.new())
	assert_false(
		EnergyExtractor.valid_placement(_msg(map, placed[1] as Vector2), _DIMS, false, false, false),
		"one overlay per site, whatever the overlay collects"
	)


func test_a_site_only_piece_is_refused_bare_ground() -> void:
	var map: Map = _make_map()
	assert_false(
		EnergyExtractor.valid_placement(_msg(map, Vector2.ZERO), _DIMS, false, false, false)
	)


func test_only_a_piece_that_collects_energy_works_ponds() -> void:
	var energy_piece: Node = autofree(Node.new())
	var collector: EnergyExtractor = EnergyExtractor.new()
	collector.name = "EnergyExtractor"
	energy_piece.add_child(collector)
	var dominion_piece: Node = autofree(Node.new())
	var generator: DominionGenerator = DominionGenerator.new()
	generator.name = "DominionGenerator"
	dominion_piece.add_child(generator)
	assert_true(Extractor.works_ponds(energy_piece), "a pond is an energy reservoir")
	assert_false(Extractor.works_ponds(dominion_piece), "nothing to draw from one")
	assert_false(Extractor.works_ponds(null))
#endregion
