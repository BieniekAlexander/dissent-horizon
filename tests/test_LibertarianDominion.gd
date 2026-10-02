extends GutTest

## The Opticon's tile claim, as pure geometry: which cells a vision radius reaches, and how
## several claims combine. Synthetic grids only — no shipped content.

const GRID: Vector2i = Vector2i(40, 40)


func test_a_cell_counts_when_its_centre_is_within_the_radius() -> void:
	var cells: Array[Vector2i] = LibertarianDominion.cells_within(Vector2(10.5, 10.5), 1.0, GRID)
	cells.sort()
	# The centre cell and its four edge neighbours are exactly 0 or 1 away; diagonals are ~1.41.
	assert_eq(
		cells,
		[Vector2i(9, 10), Vector2i(10, 9), Vector2i(10, 10), Vector2i(10, 11), Vector2i(11, 10)]
	)


func test_the_claim_approximates_the_circle_area() -> void:
	var radius: float = 10.0
	var count: int = LibertarianDominion.cells_within(Vector2(20.5, 20.5), radius, GRID).size()
	assert_almost_eq(float(count), PI * radius * radius, 0.05 * PI * radius * radius)


func test_a_claim_is_clipped_to_the_map() -> void:
	var cells: Array[Vector2i] = LibertarianDominion.cells_within(Vector2(0.5, 0.5), 3.0, GRID)
	assert_false(cells.is_empty())
	for cell: Vector2i in cells:
		assert_true(cell.x >= 0 and cell.y >= 0, "%s is on the map" % cell)


func test_overlapping_claims_pay_a_shared_tile_once() -> void:
	var a: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var b: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0)]
	assert_eq(LibertarianDominion.union_excluding([a, b], {}).size(), 3)


func test_an_excluded_tile_pays_nothing() -> void:
	var a: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var paying: Dictionary = LibertarianDominion.union_excluding([a], {Vector2i(1, 0): true})
	assert_eq(paying.keys(), [Vector2i(0, 0)])


func test_the_base_route_prices_no_site() -> void:
	# A Compound earns the same wherever it stands, so the bot builds one and never surveys.
	var route: DominionRoute = autofree(DominionRoute.new())
	assert_eq(route.full_site_gain(null), DominionRoute.NOT_SITE_DEPENDENT)
	assert_null(route.site_survey(null))
	assert_eq(route.site_claim(null, Vector2.ZERO), {})


func test_a_pending_opticon_claims_as_a_pending_gain() -> void:
	var states: Dictionary = LibertarianDominion.claim_states(
		[[Vector2i(0, 0)]], [[Vector2i(0, 0), Vector2i(1, 0)]], {}, {}
	)
	assert_eq(states["layer"][Vector2i(0, 0)], DominionRoute.ClaimState.ACTIVE)
	assert_eq(states["layer"][Vector2i(1, 0)], DominionRoute.ClaimState.PENDING_GAIN)
	assert_false(states["paying"].has(Vector2i(1, 0)), "a pending claim pays nothing yet")


func test_a_planned_building_on_a_paying_tile_is_a_pending_loss() -> void:
	var states: Dictionary = LibertarianDominion.claim_states(
		[[Vector2i(0, 0), Vector2i(1, 0)]], [], {}, {Vector2i(1, 0): true}
	)
	assert_eq(states["layer"][Vector2i(1, 0)], DominionRoute.ClaimState.PENDING_LOSS)
	assert_true(states["paying"].has(Vector2i(1, 0)), "it still pays until the building is laid")
	assert_true(states["shielded"].has(Vector2i(1, 0)), "a new Opticon cannot count on it")


func test_a_standing_building_shields_its_tile_outright() -> void:
	var states: Dictionary = LibertarianDominion.claim_states(
		[[Vector2i(0, 0), Vector2i(1, 0)]], [], {Vector2i(1, 0): true}, {}
	)
	assert_false(states["layer"].has(Vector2i(1, 0)))
