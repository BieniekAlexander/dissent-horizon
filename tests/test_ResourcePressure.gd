extends GutTest

## ResourcePressure's pure resource-state predicates and pulse maths — the shared vocabulary
## the persistent bars (EnergyBar/InfrastructureBar/DominionBar) read so none of them can
## invent its own idea of "over capacity". See gdd/systems/ux/ui/economy-bars.md.
##
## What is pinned is the DECISION each predicate reports, not an exact pulsing colour — a
## pulse depends on the wall clock, and asserting one would be asserting the time.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gtest=res://tests/test_ResourcePressure.gd -gexit

var _commander: Commander


func before_each() -> void:
	_commander = autofree(Commander.new()) as Commander
	_commander.set_physics_process(false)
	add_child_autofree(_commander)


# --- pulse_between ----------------------------------------------------------------


func test_pulse_between_never_leaves_the_two_colours_it_blends() -> void:
	var a := Color(0.2, 0.3, 0.4)
	var b := Color(0.8, 0.1, 0.6)
	var pulsed: Color = ResourcePressure.pulse_between(a, b)
	for channel: String in ["r", "g", "b"]:
		var lo: float = minf(a[channel], b[channel])
		var hi: float = maxf(a[channel], b[channel])
		assert_between(pulsed[channel], lo - 0.001, hi + 0.001)


# --- Sanction affordability ---------------------------------------------------------


func _grid_offering(a_costs: Array) -> SanctionGrid:
	var unlocks: Array = []
	for i: int in a_costs.size():
		var sanction := Sanction.new()
		sanction.sanction_name = "Sanction %d" % i
		var unlock := SanctionUnlock.new()
		unlock.sanction = sanction
		unlock.tier = 0
		unlock.column = i
		unlock.dominion_cost = int(a_costs[i])
		unlocks.append(unlock)
	return SanctionGrid.new(_commander, unlocks)


func test_the_dearest_available_cost_is_the_priciest_open_cell() -> void:
	var grid: SanctionGrid = _grid_offering([300, 900, 500])
	assert_eq(grid.dearest_available_cost(), 900)


func test_a_grid_offering_nothing_reports_minus_one() -> void:
	assert_eq(
		_grid_offering([]).dearest_available_cost(),
		-1,
		"so 'can afford everything' is never vacuously true"
	)


func test_the_cheapest_available_cost_is_the_least_priced_open_cell() -> void:
	var grid: SanctionGrid = _grid_offering([300, 900, 500])
	assert_eq(grid.cheapest_available_cost(), 300)


func test_a_grid_offering_nothing_has_no_cheapest_either() -> void:
	assert_eq(_grid_offering([]).cheapest_available_cost(), -1)


func test_no_grid_can_afford_nothing() -> void:
	_commander.dominion = 100_000
	assert_false(ResourcePressure.can_afford_dearest_sanction(_commander))
	assert_false(ResourcePressure.can_afford_cheapest_sanction(_commander))


func test_short_of_the_cheapest_option_affords_neither() -> void:
	_commander.sanction_grid = _grid_offering([300, 900])
	_commander.dominion = 299
	assert_false(ResourcePressure.can_afford_cheapest_sanction(_commander))
	assert_false(ResourcePressure.can_afford_dearest_sanction(_commander))


func test_covering_the_cheapest_but_not_the_dearest() -> void:
	_commander.sanction_grid = _grid_offering([300, 900])
	_commander.dominion = 300
	assert_true(ResourcePressure.can_afford_cheapest_sanction(_commander))
	assert_false(ResourcePressure.can_afford_dearest_sanction(_commander))


func test_covering_the_dearest_option_too() -> void:
	_commander.sanction_grid = _grid_offering([300, 900])
	_commander.dominion = 900
	assert_true(ResourcePressure.can_afford_cheapest_sanction(_commander))
	assert_true(ResourcePressure.can_afford_dearest_sanction(_commander))
