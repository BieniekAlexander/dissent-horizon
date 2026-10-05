extends GutTest

## The persistent resource bars' pure per-bar logic: what each one measures, what it scales
## against, and what colour it draws — everything short of the Control tree itself, which
## EconomyBar's own _ready() builds and which these tests never trigger (no add_child, so no
## Fill/labels exist; see gdd/systems/ux/ui/economy-bars.md).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_EconomyBars.gd -gexit


## A minimal EconomyBar for exercising the base class's generic preview maths
## (_preview_regions()) without any of EnergyBar/DominionBar/InfrastructureBar's own
## colour/capacity rules getting in the way — see §Hover previews (generic).
class _StubBar:
	extends EconomyBar
	var stub_value: float = 0.0
	var stub_capacity: float = 100.0
	var stub_cost: float = 0.0

	func _current_value() -> float:
		return stub_value

	func _capacity() -> float:
		return stub_capacity

	func _preview_cost() -> float:
		return stub_cost

	func _fill_color(_a_frac: float) -> Color:
		return Color.WHITE


func before_each() -> void:
	FakePieces.install_families(
		[{"id": _PROVIDER_VARIANT, "footprint": Vector2i(2, 2), "infrastructure": _PROVIDER_GRANT}]
	)
	FakePieces.register_tool(
		FakePieces.tool(_UNIT_TYPE, FakePieces.PLAIN, [], ControlBinding.ControlContext.TRAIN)
	)
	FakePieces.register_tool(
		FakePieces.tool(
			_PROVIDER_TYPE, {"structure": true, "dimensions": Vector2i(2, 2)}, [_PROVIDER_VARIANT]
		)
	)
	FakePieces.register_tool(
		FakePieces.tool(
			_CONSUMER_TYPE,
			{"structure": true, "dimensions": Vector2i(2, 2), "infrastructure": -_CONSUMER_DRAW}
		)
	)


func after_each() -> void:
	FakePieces.restore_families()
	FakePieces.restore_tools()


func _make_commander(a_energy: int = 0, a_dominion: int = 0) -> Commander:
	var commander := autofree(Commander.new()) as Commander
	commander.technology_mapping = {
		_UNIT_TYPE: FakePieces.tech(_IRREGULAR_ENERGY_COST),
		_PROVIDER_TYPE: FakePieces.tech(),
		_PROVIDER_VARIANT: FakePieces.tech(),
		_CONSUMER_TYPE: FakePieces.tech(_CONSUMER_ENERGY_COST)
	}
	commander.energy = a_energy
	commander.dominion = a_dominion
	return commander


## A bare, never-added-to-the-tree RTSController with `command_name` hovered — enough for
## EconomyBar._previewed_tool()/_hovered_spec(), which only ever read hovered_command_button.
## _ready() (and its Map/HUD @onready lookups) never runs, since the node never enters a tree.
func _hovering(a_command_name: String) -> RTSController:
	var controller := autofree(RTSController.new()) as RTSController
	var button := autofree(Control.new()) as Control
	button.name = a_command_name
	controller.hovered_command_button = button
	return controller


## A bare RTSController with `a_command_name`'s tool ARMED (command_message.tool) instead of
## hovered — the fallback source _previewed_tool() reads when nothing is hovered.
## `command_message` is @onready, so it stays null on a controller that never entered a tree;
## setting it directly here stands in for what _ready() would otherwise have built.
func _arming(a_command_name: String) -> RTSController:
	var controller := autofree(RTSController.new()) as RTSController
	controller.command_message = CommandMessage.new(null)
	controller.command_message.tool = Tool.for_name(a_command_name)
	return controller


func _grid_offering(a_commander: Commander, a_costs: Array) -> SanctionGrid:
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
	return SanctionGrid.new(a_commander, unlocks)


# --- Hover previews (generic) ------------------------------------------------------


func test_no_cost_previews_nothing() -> void:
	var bar := autofree(_StubBar.new()) as _StubBar
	bar.commander = _make_commander()
	bar.stub_value = 40.0
	bar.stub_cost = 0.0
	assert_eq(bar._preview_regions().size(), 0)


func test_an_affordable_cost_previews_the_end_of_the_current_fill() -> void:
	var bar := autofree(_StubBar.new()) as _StubBar
	bar.commander = _make_commander()
	bar.stub_capacity = 100.0
	bar.stub_value = 80.0
	bar.stub_cost = 30.0
	var regions: Array[Dictionary] = bar._preview_regions()
	assert_eq(regions.size(), 1)
	assert_almost_eq(regions[0].start_frac, 0.5, 0.001, "(80 - 30) / 100")
	assert_almost_eq(regions[0].end_frac, 0.8, 0.001, "80 / 100")


func test_an_unaffordable_cost_previews_the_gap_past_the_current_fill() -> void:
	var bar := autofree(_StubBar.new()) as _StubBar
	bar.commander = _make_commander()
	bar.stub_capacity = 100.0
	bar.stub_value = 20.0
	bar.stub_cost = 70.0
	var regions: Array[Dictionary] = bar._preview_regions()
	assert_eq(regions.size(), 1)
	assert_almost_eq(regions[0].start_frac, 0.2, 0.001, "the current fill's own edge")
	assert_almost_eq(regions[0].end_frac, 0.7, 0.001, "the total cost, not just the shortfall")


func test_preview_colour_is_opaque_and_muted_toward_the_background() -> void:
	var bar := autofree(_StubBar.new()) as _StubBar
	bar.commander = _make_commander()
	bar.stub_capacity = 100.0
	bar.stub_value = 80.0
	bar.stub_cost = 10.0
	assert_almost_eq(
		bar._preview_regions()[0].color.a,
		1.0,
		0.001,
		"opaque, not alpha-blended — see _dimmed()'s comment for why alpha self-cancels"
	)
	assert_ne(
		bar._preview_regions()[0].color,
		Color.WHITE,
		"_StubBar's real fill is plain white, so a genuinely muted colour must differ from it"
	)


func test_dimming_a_colour_that_matches_the_real_fill_still_changes_something_visible() -> void:
	# The bug this guards: the AFFORDABLE preview region ends exactly where the real fill
	# already ends, in the exact colour _fill_color() gives that position — so if _dimmed()
	# only reduced alpha, compositing it over the identical opaque colour underneath would be
	# a no-op and the preview would be invisible. Assert the RGB itself moves, not just alpha.
	var bar := autofree(_StubBar.new()) as _StubBar
	var real_fill_color := Color(0.2, 0.6, 0.8)
	var dimmed: Color = bar._dimmed(real_fill_color)
	assert_ne(
		Vector3(dimmed.r, dimmed.g, dimmed.b),
		Vector3(real_fill_color.r, real_fill_color.g, real_fill_color.b),
		"the RGB itself must move toward the background, not just the alpha"
	)


# --- RTSController.previewed_tool() (hover vs. armed) ------------------------------
##
## The rule every bar's preview is built on: a hovered purchase wins outright over an armed
## one — never combined, so pointing at a different button's cost while something is armed
## previews only what is under the pointer. An armed tool with nothing hovered still
## previews, since it is exactly as pending a purchase as a hovered one.


func test_nothing_hovered_or_armed_previews_nothing() -> void:
	var controller := autofree(RTSController.new()) as RTSController
	assert_null(controller.previewed_tool())


func test_an_armed_tool_previews_with_nothing_hovered() -> void:
	var controller := _arming(_IRREGULAR_COMMAND)
	assert_eq(controller.previewed_tool().type, _UNIT_TYPE)


func test_a_hovered_tool_previews_with_nothing_armed() -> void:
	var controller := _hovering(_IRREGULAR_COMMAND)
	assert_eq(controller.previewed_tool().type, _UNIT_TYPE)


func test_hovering_a_different_tool_than_the_armed_one_previews_only_the_hover() -> void:
	var controller := _arming(_IRREGULAR_COMMAND)  # armed: Irregular
	var button := autofree(Control.new()) as Control
	button.name = _PROVIDER_COMMAND  # hovered: Safehouse
	controller.hovered_command_button = button
	assert_eq(
		controller.previewed_tool().type,
		_PROVIDER_TYPE,
		"the hover wins outright — never both, never a sum of the two costs"
	)


func test_hovering_a_verb_falls_through_to_the_armed_tool() -> void:
	# A verb button has no Tool — it must not be treated as "hovering something", or arming a
	# structure and then moving the pointer to press Stop would blank out its own preview.
	var controller := _arming(_IRREGULAR_COMMAND)
	var button := autofree(Control.new()) as Control
	button.name = "command_attack"
	controller.hovered_command_button = button
	assert_eq(controller.previewed_tool().type, _UNIT_TYPE)


# --- EnergyBar --------------------------------------------------------------------


func test_energy_bars_value_is_the_commanders_energy() -> void:
	var bar := autofree(EnergyBar.new()) as EnergyBar
	bar.commander = _make_commander(1234)
	assert_eq(bar._current_value(), 1234.0)


func test_energy_bars_capacity_is_the_surplus_threshold() -> void:
	var bar := autofree(EnergyBar.new()) as EnergyBar
	bar.commander = _make_commander()
	assert_eq(bar._capacity(), float(ResourcePressure.ENERGY_SURPLUS_THRESHOLD))


func test_energy_fill_colour_progresses_from_the_low_stop_to_the_high_stop() -> void:
	var bar := autofree(EnergyBar.new()) as EnergyBar
	bar.commander = _make_commander()
	var low: Color = bar._fill_color(0.0)
	var high: Color = bar._fill_color(1.0)
	assert_ne(low, high, "the ramp actually moves across the fill")


func test_energy_past_the_threshold_oscillates() -> void:
	var bar := autofree(EnergyBar.new()) as EnergyBar
	bar.commander = _make_commander(ResourcePressure.ENERGY_SURPLUS_THRESHOLD + 1)
	var resting: Color = BarGradient.with_saturation_ramp(EnergyBar._gradient.sample(1.0), 1.0)
	assert_ne(bar._fill_color(1.0), resting, "past the threshold the fill pulses off its base")


## Irregular (an_bioLight_builder) costs a real, generated 100 energy — see
## resources/generated/technology.json. Exercising the real Tool/TechnologySpec lookup once
## here (rather than only through _StubBar) is what proves _previewed_tool()/_hovered_spec()
## actually resolve a live command name to a real cost, not just that the maths is right once
## a cost is handed to it.
## Three fake purchases, registered as real tools for the duration of each test: a unit (100
## energy), a provider of infrastructure (a structure with one variant), and a consumer that costs
## a lot of energy and draws infrastructure down.
const _UNIT_TYPE: StringName = &"fake_unit"
const _PROVIDER_TYPE: StringName = &"fake_provider"
const _PROVIDER_VARIANT: StringName = &"fake_provider_variant"
const _CONSUMER_TYPE: StringName = &"fake_consumer"
const _IRREGULAR_COMMAND: String = "command_tool_fake_unit"
const _PROVIDER_COMMAND: String = "command_tool_fake_provider"
const _CONSUMER_COMMAND: String = "command_tool_fake_consumer"
const _IRREGULAR_ENERGY_COST: int = 100
const _CONSUMER_ENERGY_COST: int = 1000
const _PROVIDER_GRANT: int = 50
const _CONSUMER_DRAW: int = 40


func test_hovering_an_affordable_unit_previews_its_cost() -> void:
	var bar := autofree(EnergyBar.new()) as EnergyBar
	var commander := _make_commander(500)
	bar.commander = commander
	bar.controller = _hovering(_IRREGULAR_COMMAND)
	var regions: Array[Dictionary] = bar._preview_regions()
	assert_eq(regions.size(), 1)
	assert_almost_eq(
		regions[0].end_frac, 500.0 / float(ResourcePressure.ENERGY_SURPLUS_THRESHOLD), 0.001
	)
	assert_almost_eq(
		regions[0].start_frac,
		(500.0 - _IRREGULAR_ENERGY_COST) / float(ResourcePressure.ENERGY_SURPLUS_THRESHOLD),
		0.001
	)


func test_hovering_an_unaffordable_unit_previews_the_shortfall() -> void:
	var bar := autofree(EnergyBar.new()) as EnergyBar
	var commander := _make_commander(40)
	bar.commander = commander
	bar.controller = _hovering(_IRREGULAR_COMMAND)
	var regions: Array[Dictionary] = bar._preview_regions()
	assert_eq(regions.size(), 1)
	assert_almost_eq(
		regions[0].start_frac, 40.0 / float(ResourcePressure.ENERGY_SURPLUS_THRESHOLD), 0.001
	)
	assert_almost_eq(
		regions[0].end_frac,
		float(_IRREGULAR_ENERGY_COST) / float(ResourcePressure.ENERGY_SURPLUS_THRESHOLD),
		0.001
	)


func test_an_armed_purchase_previews_the_same_as_a_hovered_one() -> void:
	var bar := autofree(EnergyBar.new()) as EnergyBar
	var commander := _make_commander(500)
	bar.commander = commander
	bar.controller = _arming(_IRREGULAR_COMMAND)
	var regions: Array[Dictionary] = bar._preview_regions()
	assert_eq(regions.size(), 1)
	assert_almost_eq(
		regions[0].start_frac,
		(500.0 - _IRREGULAR_ENERGY_COST) / float(ResourcePressure.ENERGY_SURPLUS_THRESHOLD),
		0.001
	)


func test_hovering_a_different_purchase_overrides_an_armed_one_never_sums_them() -> void:
	var bar := autofree(EnergyBar.new()) as EnergyBar
	var commander := _make_commander(500)
	bar.commander = commander
	var controller := _arming(_IRREGULAR_COMMAND)  # armed: 100 energy
	var button := autofree(Control.new()) as Control
	button.name = _CONSUMER_COMMAND  # hovered: 1000 energy — a different cost
	controller.hovered_command_button = button
	bar.controller = controller
	var regions: Array[Dictionary] = bar._preview_regions()
	assert_eq(regions.size(), 1)
	# 500 energy against a 1000 cost: unaffordable, so [value, cost] — never [armed cost
	# consumed] + [hover cost missing] added together.
	assert_almost_eq(
		regions[0].start_frac, 500.0 / float(ResourcePressure.ENERGY_SURPLUS_THRESHOLD), 0.001
	)
	assert_almost_eq(
		regions[0].end_frac,
		float(_CONSUMER_ENERGY_COST) / float(ResourcePressure.ENERGY_SURPLUS_THRESHOLD),
		0.001
	)


func test_hovering_nothing_previews_nothing() -> void:
	var bar := autofree(EnergyBar.new()) as EnergyBar
	bar.commander = _make_commander(40)
	bar.controller = autofree(RTSController.new()) as RTSController
	assert_eq(bar._preview_regions().size(), 0)


func test_hovering_a_verb_previews_nothing() -> void:
	# A verb button (Attack, Stop, ...) has no Tool at all — Tool.for_name answers null, which
	# is what _hovered_tool() is meant to fall through on.
	var bar := autofree(EnergyBar.new()) as EnergyBar
	bar.commander = _make_commander(40)
	bar.controller = _hovering("command_attack")
	assert_eq(bar._preview_regions().size(), 0)


## A stubbed cost (no piece in the current content actually crosses the threshold) — see
## §Hover previews (generic) above for why stubbing _preview_cost() directly is the reliable
## way to test this rather than hunting for content that happens to be expensive enough.
class _EnergyBarStubCost:
	extends EnergyBar
	var stub_cost: float = 0.0

	func _preview_cost() -> float:
		return stub_cost


func test_a_purchase_costing_more_than_the_threshold_grows_the_bar_to_fit() -> void:
	var bar := autofree(_EnergyBarStubCost.new()) as _EnergyBarStubCost
	bar.commander = _make_commander(0)
	bar.stub_cost = 12000.0
	assert_gt(bar._capacity(), float(ResourcePressure.ENERGY_SURPLUS_THRESHOLD))
	assert_almost_eq(bar._capacity(), 12000.0, 0.001)


func test_growing_the_bar_for_a_huge_cost_does_not_itself_trigger_oscillation() -> void:
	# _fill_color's oscillation check reads the real threshold constant directly rather than
	# _capacity(), specifically so hovering something expensive can't silently stop a
	# genuinely-over-threshold bar from pulsing (see the comment on _capacity()). Cover the
	# other direction here: it must also not START pulsing a bar that isn't actually over.
	var bar := autofree(_EnergyBarStubCost.new()) as _EnergyBarStubCost
	bar.commander = _make_commander(100)  # well under the real threshold
	bar.stub_cost = 12000.0
	var resting: Color = BarGradient.with_saturation_ramp(
		EnergyBar._gradient.sample(100.0 / bar._capacity()), 100.0 / bar._capacity()
	)
	assert_eq(bar._fill_color(100.0 / bar._capacity()), resting)


# --- InfrastructureBar -------------------------------------------------------------


func test_infrastructure_bars_value_is_upkeep_not_capacity() -> void:
	var bar := autofree(InfrastructureBar.new()) as InfrastructureBar
	var commander := _make_commander()
	commander.add_infrastructure(-40)
	bar.commander = commander
	assert_eq(bar._current_value(), 40.0)


func test_capacity_defaults_to_the_visual_threshold() -> void:
	var bar := autofree(InfrastructureBar.new()) as InfrastructureBar
	bar.commander = _make_commander()
	assert_eq(
		bar._capacity(),
		InfrastructureBar.DEFAULT_VISUAL_THRESHOLD,
		"base infrastructure (100) is well under the 500 default, so the bar stays at scale"
	)


func test_capacity_rescales_to_stay_within_the_bar() -> void:
	var bar := autofree(InfrastructureBar.new()) as InfrastructureBar
	var commander := _make_commander()
	commander.add_infrastructure(1000)
	bar.commander = commander
	assert_eq(
		bar._capacity(),
		float(commander.infrastructure_provided),
		"provided capacity now exceeds the default, so it becomes the new scale"
	)


func test_light_use_draws_a_used_region_and_a_grey_spare_region() -> void:
	var bar := autofree(InfrastructureBar.new()) as InfrastructureBar
	var commander := _make_commander()
	commander.add_infrastructure(-40)  # required = 40
	commander.add_infrastructure(600)  # provided = BASE_INFRASTRUCTURE (100) + 600 = 700
	bar.commander = commander
	var regions: Array[Dictionary] = bar._fill_regions()
	assert_eq(regions.size(), 2)
	assert_eq(regions[0].color, InfrastructureBar.USED_COLOR)
	assert_almost_eq(regions[0].end_frac, 40.0 / 700.0, 0.001)
	assert_eq(regions[1].color, InfrastructureBar.SPARE_COLOR)
	assert_almost_eq(
		regions[1].end_frac,
		1.0,
		0.001,
		"provided alone now sets the scale, so spare runs to the bar's end"
	)


func test_no_usage_draws_only_the_spare_region() -> void:
	var bar := autofree(InfrastructureBar.new()) as InfrastructureBar
	bar.commander = _make_commander()
	var regions: Array[Dictionary] = bar._fill_regions()
	assert_eq(regions.size(), 1, "an empty used region is not drawn at all")
	assert_eq(regions[0].color, InfrastructureBar.SPARE_COLOR)


func test_approaching_capacity_warns_steadily_in_the_spare_region() -> void:
	var bar := autofree(InfrastructureBar.new()) as InfrastructureBar
	var commander := _make_commander()
	commander.add_infrastructure(
		-int(Commander.BASE_INFRASTRUCTURE * ResourcePressure.INFRASTRUCTURE_PRESSURE_FRACTION)
	)
	bar.commander = commander
	assert_false(commander.is_infrastructure_strained(), "the fixture is not yet over capacity")
	assert_eq(bar._fill_regions()[1].color, ResourcePressure.INFRASTRUCTURE_PRESSURE_COLOR)


func test_strained_infrastructure_oscillates_the_excess_region() -> void:
	var bar := autofree(InfrastructureBar.new()) as InfrastructureBar
	var commander := _make_commander()
	# Past the default 500 visual threshold too, so required alone sets the bar's scale —
	# the case where the excess region's own end_frac reaches the bar's right edge.
	commander.add_infrastructure(-600)
	bar.commander = commander
	assert_true(commander.is_infrastructure_strained(), "the fixture is actually strained")
	var regions: Array[Dictionary] = bar._fill_regions()
	assert_almost_eq(
		regions[1].end_frac,
		1.0,
		0.001,
		"required alone now sets the scale, so the excess region runs to the bar's end"
	)
	var excess_color: Color = regions[1].color
	assert_ne(
		excess_color,
		ResourcePressure.INFRASTRUCTURE_OVER_COLOR,
		"pulsing, not the steady over-colour"
	)
	assert_ne(excess_color, ResourcePressure.INFRASTRUCTURE_PRESSURE_COLOR)
	assert_ne(excess_color, InfrastructureBar.SPARE_COLOR)


func test_segment_size_is_the_commanders_provider_grant() -> void:
	var bar := autofree(InfrastructureBar.new()) as InfrastructureBar
	var commander := _make_commander()
	var faction := autofree(Faction.new()) as Faction
	faction.infrastructure_source = &"lb_infrastructure"
	commander.faction = faction
	bar.commander = commander
	assert_gt(bar._segment_size(), 0.0, "guards the fixture")
	assert_eq(bar._segment_size(), float(commander.infrastructure_provider_grant()))


# --- Pending pieces --------------------------------------------------------------


## Upkeep a planned building will add eats into today's spare capacity: that stretch changes
## from spare to used, and nothing else does.
func test_pending_upkeep_within_spare_capacity_turns_spare_to_used() -> void:
	var changes: Array = InfrastructureBar.projected_changes(100.0, 500.0, 180.0, 500.0)
	assert_eq(changes, [[100.0, 180.0, InfrastructureBar.Band.USED]])


func test_pending_capacity_extends_the_bar() -> void:
	var changes: Array = InfrastructureBar.projected_changes(100.0, 500.0, 100.0, 1000.0)
	assert_eq(changes, [[500.0, 1000.0, InfrastructureBar.Band.SPARE]])


func test_pending_upkeep_past_capacity_shows_the_coming_deficit() -> void:
	var changes: Array = InfrastructureBar.projected_changes(400.0, 500.0, 600.0, 500.0)
	assert_eq(
		changes,
		[[400.0, 500.0, InfrastructureBar.Band.USED], [500.0, 600.0, InfrastructureBar.Band.OVER]]
	)


func test_pending_capacity_closing_a_deficit_turns_it_used() -> void:
	var changes: Array = InfrastructureBar.projected_changes(600.0, 500.0, 600.0, 700.0)
	assert_eq(
		changes,
		[[500.0, 600.0, InfrastructureBar.Band.USED], [600.0, 700.0, InfrastructureBar.Band.SPARE]]
	)


func test_nothing_pending_draws_nothing() -> void:
	assert_eq(InfrastructureBar.projected_changes(100.0, 500.0, 100.0, 500.0), [])


## The Safehouse (an_infrastructure) provides a real, generated +50 infrastructure once
## built — see gdd/factions/anarchical/structures/an_infrastructure.md. The Redoubt
## (an_barracks) consumes -40. Real pieces, so the same Tool/get_build_preview_instance
## wiring EnergyBar's hover tests exercise is proven for infrastructure's very different
## delta lookup too.


func test_hovering_a_provider_previews_added_spare_capacity() -> void:
	var bar := autofree(InfrastructureBar.new()) as InfrastructureBar
	var commander := _make_commander()  # required 0, provided BASE_INFRASTRUCTURE (100)
	bar.commander = commander
	bar.controller = _hovering(_PROVIDER_COMMAND)
	# The provider's grant is its DEFAULT variant's (variants:), so read it there rather than
	# pinning a number the owner retunes.
	var grant: int = (
		PieceFamilies.template(Tool.for_name(_PROVIDER_COMMAND).variants[0]).infrastructure
	)
	assert_gt(grant, 0)
	assert_eq(bar._hovered_infrastructure_delta(), grant)
	var regions: Array[Dictionary] = bar._preview_regions()
	assert_eq(regions.size(), 1)
	assert_eq(regions[0].color, bar._dimmed(InfrastructureBar.SPARE_COLOR))
	var capacity: float = bar._capacity()
	assert_almost_eq(regions[0].start_frac, 100.0 / capacity, 0.001, "the current provided edge")
	assert_almost_eq(regions[0].end_frac, (100.0 + grant) / capacity, 0.001, "provided + the grant")


func test_hovering_a_consumer_previews_drawdown_within_spare_capacity() -> void:
	var bar := autofree(InfrastructureBar.new()) as InfrastructureBar
	var commander := _make_commander()  # required 0, provided 100 — the draw must fit
	bar.commander = commander
	bar.controller = _hovering(_CONSUMER_COMMAND)
	# The draw is the piece's own, read rather than pinned: it is a number the owner retunes.
	var draw: int = -bar._hovered_infrastructure_delta()
	assert_gt(draw, 0, "a consumer draws infrastructure down")
	assert_lt(draw, 100, "guards the fixture: it fits inside the spare capacity")
	var regions: Array[Dictionary] = bar._preview_regions()
	assert_eq(regions.size(), 1, "the whole increment still fits inside existing spare capacity")
	assert_eq(regions[0].color, bar._dimmed(InfrastructureBar.USED_COLOR))
	var capacity: float = bar._capacity()
	assert_almost_eq(regions[0].start_frac, 0.0, 0.001)
	assert_almost_eq(regions[0].end_frac, float(draw) / capacity, 0.001)


func test_hovering_a_consumer_that_would_cause_a_deficit_previews_it_steadily() -> void:
	var bar := autofree(InfrastructureBar.new()) as InfrastructureBar
	var commander := _make_commander()
	commander.add_infrastructure(-90)  # required 90, provided 100 — only 10 spare left
	bar.commander = commander
	bar.controller = _hovering(_CONSUMER_COMMAND)  # -40, more than the 10 left
	var regions: Array[Dictionary] = bar._preview_regions()
	assert_eq(regions.size(), 2, "part still fits in spare, part is a genuine preview deficit")
	assert_eq(regions[0].color, bar._dimmed(InfrastructureBar.USED_COLOR))
	assert_eq(
		regions[1].color,
		bar._dimmed(ResourcePressure.INFRASTRUCTURE_OVER_COLOR),
		(
			"the deficit idiom, dimmed and STEADY — a plain constant rather than a pulse_between\n"
			+ "call, so this equality holds regardless of the wall clock"
		)
	)


func test_no_infrastructure_change_previews_nothing() -> void:
	var bar := autofree(InfrastructureBar.new()) as InfrastructureBar
	bar.commander = _make_commander()
	bar.controller = _hovering(_IRREGULAR_COMMAND)  # a unit — no infrastructure export at all
	assert_eq(bar._preview_regions().size(), 0)


# --- DominionBar --------------------------------------------------------------------


func test_dominion_bars_value_is_the_commanders_dominion() -> void:
	var bar := autofree(DominionBar.new()) as DominionBar
	bar.commander = _make_commander(0, 777)
	assert_eq(bar._current_value(), 777.0)


func test_capacity_falls_back_to_a_default_with_no_grid() -> void:
	var bar := autofree(DominionBar.new()) as DominionBar
	bar.commander = _make_commander()
	assert_eq(bar._capacity(), DominionBar.DEFAULT_VISUAL_SCALE)


func test_capacity_tracks_the_dearest_available_sanction() -> void:
	var bar := autofree(DominionBar.new()) as DominionBar
	var commander := _make_commander()
	commander.sanction_grid = _grid_offering(commander, [300, 900])
	bar.commander = commander
	assert_eq(bar._capacity(), 900.0)


func test_pale_yellow_below_the_cheapest_option() -> void:
	var bar := autofree(DominionBar.new()) as DominionBar
	var commander := _make_commander(0, 100)
	commander.sanction_grid = _grid_offering(commander, [300, 900])
	bar.commander = commander
	assert_eq(bar._fill_color(0.0), DominionBar.PALE_YELLOW)


func test_saturated_orange_once_the_cheapest_option_is_affordable() -> void:
	var bar := autofree(DominionBar.new()) as DominionBar
	var commander := _make_commander(0, 300)
	commander.sanction_grid = _grid_offering(commander, [300, 900])
	bar.commander = commander
	assert_eq(bar._fill_color(0.0), DominionBar.SATURATED_ORANGE)


func test_the_dearest_option_oscillates_orange_red() -> void:
	var bar := autofree(DominionBar.new()) as DominionBar
	var commander := _make_commander(0, 900)
	commander.sanction_grid = _grid_offering(commander, [300, 900])
	bar.commander = commander
	assert_ne(
		bar._fill_color(0.0),
		DominionBar.SATURATED_ORANGE_RED,
		"pulsing, not the steady saturated colour"
	)
	assert_ne(bar._fill_color(0.0), DominionBar.PALE_YELLOW)
	assert_ne(bar._fill_color(0.0), DominionBar.SATURATED_ORANGE)


## No piece in the current content costs dominion to train/build (dominion is spent through
## the sanction grid instead), so hovering a real, zero-dominion-cost purchase should still
## resolve cleanly to "nothing to preview" rather than erroring.
func test_hovering_a_zero_dominion_cost_purchase_previews_nothing() -> void:
	var bar := autofree(DominionBar.new()) as DominionBar
	bar.commander = _make_commander(0, 100)
	bar.controller = _hovering(_IRREGULAR_COMMAND)
	assert_eq(bar._preview_regions().size(), 0)


## Sanction UNLOCK buttons are the real dominion sink (§the class comment above) — a
## different button-building path from the command grid's, tracked on its own controller
## field rather than hovered_command_button.


func test_hovering_a_sanction_unlock_previews_its_dominion_cost() -> void:
	var bar := autofree(DominionBar.new()) as DominionBar
	var commander := _make_commander(0, 200)
	var grid: SanctionGrid = _grid_offering(commander, [300, 900])
	commander.sanction_grid = grid
	bar.commander = commander
	var controller := autofree(RTSController.new()) as RTSController
	controller.hovered_sanction_unlock = grid.entries[0]  # the 300-cost cell
	bar.controller = controller
	var regions: Array[Dictionary] = bar._preview_regions()
	assert_eq(regions.size(), 1)
	var capacity: float = bar._capacity()
	assert_almost_eq(regions[0].start_frac, 200.0 / capacity, 0.001)
	assert_almost_eq(regions[0].end_frac, 300.0 / capacity, 0.001)


func test_a_hovered_sanction_unlock_grows_the_bar_to_fit_its_cost() -> void:
	var bar := autofree(DominionBar.new()) as DominionBar
	var commander := _make_commander(0, 0)
	var grid: SanctionGrid = _grid_offering(commander, [300, 900])
	commander.sanction_grid = grid
	bar.commander = commander
	var controller := autofree(RTSController.new()) as RTSController
	controller.hovered_sanction_unlock = grid.entries[1]  # the 900-cost cell
	bar.controller = controller
	# The grid's own dearest_available_cost() is already 900 here, so this mainly proves
	# _preview_cost() reads the HOVERED entry's cost rather than always reading the grid's.
	assert_almost_eq(bar._capacity(), 900.0, 0.001)


## _preview_cost() itself is stubbed here for the same reason EnergyBar's is above: nothing
## in the current content actually costs dominion to prove the "grows to fit" rule against.
class _DominionBarStubCost:
	extends DominionBar
	var stub_cost: float = 0.0

	func _preview_cost() -> float:
		return stub_cost


func test_a_purchase_costing_more_dominion_than_the_scale_grows_the_bar_to_fit() -> void:
	var bar := autofree(_DominionBarStubCost.new()) as _DominionBarStubCost
	bar.commander = _make_commander(0, 0)
	bar.stub_cost = 5000.0
	assert_almost_eq(bar._capacity(), 5000.0, 0.001)


## The income-rate PROJECTION drawn inside the bar itself — PROJECTION_SECONDS of
## `Commander.projected_dominion_rate()`, picking up where the real fill ends, at
## RATE_BAR_ALPHA — see gdd/systems/ux/ui/economy-bars.md §Rate projection. Persistent (no
## hover involved), unlike §Hover previews above.
##
## `projected_dominion_rate()` reads a TASKED truck's `command_receiver`, an `@onready`
## field that only resolves once `_ready()` fires — which the off-tree fixtures elsewhere in
## this file skip deliberately (see the file's own docstring). This section's fixture is the
## one exception: `_make_tasked_commander()` builds a real, live-tree Shelter/Compound/truck
## triple, added under an autofreed root so `_ready()` runs normally. Shelter and Compound
## sit at the SAME position, so transport never binds and the projected rate reduces to
## `dominion_per_unit * min(shelter_rate * sentence_length, SENTENCES_AT_ONCE)` — see
## test_ProjectedDominionRate.gd for the formula itself, including the transport-bound case;
## this file only needs SOME known positive rate to exercise the bar's own math.

## A commander with one truck tasked on a Shelter that feeds an adjacent Compound —
## `EXPECTED_PROJECTED_RATE` dominion/s, by construction (8 dominion/occupant * min(0.1
## captives/s * 5s term, 1 serving) = 8 * 0.5 = 4). Deliberately small enough that its
## 60-second projection does not itself hit the bar's own clamp (see
## test_an_enormous_income_rate_fills_the_rest_of_the_bar_without_growing_it for that case).
const EXPECTED_PROJECTED_RATE: float = 4.0


func _make_tasked_commander() -> Commander:
	var world := Node3D.new()
	add_child_autofree(world)
	var commander := Commander.new()
	commander.id = 1
	world.add_child(commander)
	commander.set_physics_process(false)

	var shelter: Entity = FakePieces.make(FakePieces.SHELTER)
	world.add_child(shelter)
	shelter.set_physics_process(false)
	shelter.top_level = true
	(shelter.get_node("Shelter") as Shelter).spawn_interval = 10.0

	var compound: Commandable = FakePieces.make(FakePieces.COMPOUND) as Commandable
	world.add_child(compound)
	compound.set_physics_process(false)
	compound.top_level = true
	compound.commander = commander
	compound.garrison.sentence_length = 5.0
	compound.garrison.capacity = 100
	(compound.get_node("DominionGenerator") as OccupantDominionGenerator).dominion_per_unit = 8

	var truck: Commandable = FakePieces.make(FakePieces.TRUCK) as Commandable
	world.add_child(truck)
	truck.set_physics_process(false)
	truck.top_level = true
	truck.commander = commander
	truck.command_receiver.update_commands(TaskShelter.new(CommandMessage.new(null, shelter)))

	return commander


func test_no_income_projects_nothing() -> void:
	var bar := autofree(DominionBar.new()) as DominionBar
	bar.commander = _make_commander(0, 100)
	assert_eq(bar._rate_regions().size(), 0)


func test_income_projects_sixty_seconds_ahead_of_the_current_fill() -> void:
	var bar := autofree(DominionBar.new()) as DominionBar
	var commander := _make_tasked_commander()
	commander.dominion = 100
	bar.commander = commander
	assert_almost_eq(
		commander.projected_dominion_rate(),
		EXPECTED_PROJECTED_RATE,
		0.001,
		"the fixture actually has a projected rate"
	)
	var capacity: float = bar._capacity()
	var regions: Array[Dictionary] = bar._rate_regions()
	assert_eq(regions.size(), 1)
	assert_almost_eq(
		regions[0].start_frac, 100.0 / capacity, 0.001, "picks up exactly where the real fill ends"
	)
	var projected: float = commander.projected_dominion_rate() * DominionBar.PROJECTION_SECONDS
	assert_almost_eq(regions[0].end_frac, (100.0 + projected) / capacity, 0.001)


func test_the_projection_is_the_fill_colour_at_reduced_alpha() -> void:
	var bar := autofree(DominionBar.new()) as DominionBar
	var commander := _make_tasked_commander()
	commander.dominion = 100
	bar.commander = commander
	var region_color: Color = bar._rate_regions()[0].color
	var fill_color: Color = bar._fill_color(0.0)
	assert_eq(
		Vector3(region_color.r, region_color.g, region_color.b),
		Vector3(fill_color.r, fill_color.g, fill_color.b),
		"same colour as the real fill"
	)
	assert_almost_eq(region_color.a, EconomyBar.RATE_BAR_ALPHA, 0.001)


func test_an_enormous_income_rate_fills_the_rest_of_the_bar_without_growing_it() -> void:
	var bar := autofree(DominionBar.new()) as DominionBar
	var commander := _make_tasked_commander()
	commander.dominion = 100
	# Blow the projected rate up without touching the transport/regeneration math above —
	# only the per-occupant payout needs to be enormous for this test's purpose.
	for c: Commandable in commander.get_deposit_structures():
		(c.get_node("DominionGenerator") as OccupantDominionGenerator).dominion_per_unit = 100_000
	bar.commander = commander
	var capacity_before: float = bar._capacity()
	var regions: Array[Dictionary] = bar._rate_regions()
	assert_eq(regions.size(), 1)
	assert_almost_eq(regions[0].end_frac, 1.0, 0.001, "clipped to the bar's own edge")
	assert_almost_eq(
		bar._capacity(),
		capacity_before,
		0.001,
		"a big rate does not rescale the bar the way an expensive hover preview does"
	)


func test_a_rate_that_would_start_past_the_bar_projects_nothing() -> void:
	# Capacity can itself be small (DominionBar.DEFAULT_VISUAL_SCALE) relative to a large
	# banked amount from a prior tier opening; the region must not invert.
	var bar := autofree(DominionBar.new()) as DominionBar
	var commander := _make_tasked_commander()
	commander.dominion = 10_000
	bar.commander = commander
	assert_eq(bar._rate_regions().size(), 0)
