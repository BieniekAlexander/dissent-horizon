extends GutTest

## THE BOT AND A STACKING DOMINION ROUTE (the Technocratic Lab), and a TRAINED infrastructure
## provider (the Technocratic Surveyor).
##
## A Lab pays a flat rate wherever it stands, so every Lab adds a whole Lab's income — unlike a
## Compound, of which one is enough. The bot builds the first one at the top of its ladder like
## any faction's first dominion source; past that it builds another only while the dominion has
## something to buy (Bot.dominion_demand), because a Lab is a site that earns no energy.
##
## Synthetic ids throughout (CLAUDE.md §A unit test does not assert facts about authored
## content): nothing here names a shipped piece.

const LAB: StringName = &"fake_lab"
const SURVEYOR: StringName = &"fake_surveyor"


class FakeBot:
	extends Bot
	var owned: Array = []
	var demand: int = 0
	var route: DominionRoute = null
	var preview: Entity = null
	var strained: bool = false
	var provider_is_unit: bool = true
	var producers: Array = []

	func can_afford(_a_type: StringName) -> bool:
		return true

	func get_units() -> Array:
		return []

	func get_structures_of_type(_a_type: StringName) -> Array:
		return owned

	func buildable_dominion_structure_types() -> Array:
		return [LAB]

	func dominion_route() -> DominionRoute:
		return route

	func dominion_demand() -> int:
		return demand

	func get_build_preview_instance(_a_tool: Tool) -> Node:
		return preview

	func needs_infrastructure_provider() -> bool:
		return strained

	func infrastructure_source_is_unit() -> bool:
		return provider_is_unit

	func infrastructure_source_type() -> StringName:
		return SURVEYOR

	func has_tech_for(_a_type: StringName) -> bool:
		return true

	func get_production_structures() -> Array:
		return producers


## The economy with its placement and order-issuing stubbed: what is under test is which rung
## asks for a source and how, not where the map lets one stand.
class StubEconomy:
	extends BotEconomy
	var site: Entity = null
	var issued: Array = []
	var surveyed: bool = false

	func _types_under_way() -> Array[StringName]:
		return []

	func _nearest_unclaimed_site() -> Entity:
		return site

	func _dominion_site(_a_type: StringName, _a_min_fraction: float) -> Variant:
		surveyed = true
		return null

	func _issue_build(_a_builder: Actor, a_type: StringName, a_spot: Vector3) -> bool:
		issued.append([a_type, a_spot])
		return true


class RecordingActuator:
	extends BotActuator
	var trained: Array = []

	func train(a_structure: Actor, a_type: StringName) -> bool:
		trained.append([a_structure, a_type])
		return true


func _bot() -> FakeBot:
	var bot: FakeBot = autofree(FakeBot.new())
	bot.energy = 10_000
	return bot


func _economy(a_bot: FakeBot) -> StubEconomy:
	var economy := StubEconomy.new(a_bot, autofree(BotActuator.new(null)))
	economy.reserve = 0
	return autofree(economy)


## A structure piece that OVERLAYS an extraction site and collects no energy — the Lab's shape.
func _overlay_preview() -> Entity:
	var piece: Actor = FakePieces.structure()
	var overlay := Extractor.new()
	overlay.name = "Extractor"
	piece.add_child(overlay)
	return autofree(piece)


func _site_at(a_where: Vector3) -> Entity:
	var site: Entity = FakePieces.feature({"extraction_site": true})
	add_child_autofree(site)
	site.global_position = a_where
	return site


#region Where a Lab goes
func test_an_overlay_source_goes_on_the_nearest_free_site() -> void:
	var bot := _bot()
	bot.route = autofree(TechnocraticDominion.new())
	bot.preview = _overlay_preview()
	var economy := _economy(bot)
	economy.site = _site_at(Vector3(7.0, 0.0, 3.0))
	assert_eq(economy._dominion_build_spot(LAB, 0.0), Vector3(7.0, 0.0, 3.0))


func test_with_no_free_site_an_overlay_source_has_nowhere_to_go() -> void:
	var bot := _bot()
	bot.route = autofree(TechnocraticDominion.new())
	bot.preview = _overlay_preview()
	assert_null(_economy(bot)._dominion_build_spot(LAB, 0.0))
#endregion


#region How many Labs
func test_a_stacking_route_builds_another_source_while_dominion_has_a_use() -> void:
	var bot := _bot()
	bot.route = autofree(TechnocraticDominion.new())
	bot.preview = _overlay_preview()
	bot.owned = [autofree(Node.new())]  # the first Lab stands
	bot.demand = 500
	var economy := _economy(bot)
	economy.site = _site_at(Vector3(4.0, 0.0, 4.0))
	assert_true(economy._extend_dominion(null))
	assert_eq(economy.issued, [[LAB, Vector3(4.0, 0.0, 4.0)]])
	assert_false(economy.surveyed, "a flat-rate source has no site to price")


func test_a_stacking_route_stops_once_dominion_buys_nothing() -> void:
	var bot := _bot()
	bot.route = autofree(TechnocraticDominion.new())
	bot.preview = _overlay_preview()
	bot.owned = [autofree(Node.new())]
	bot.demand = 0  # bought out, or a faction with no sanctions
	var economy := _economy(bot)
	economy.site = _site_at(Vector3(4.0, 0.0, 4.0))
	assert_false(economy._extend_dominion(null))
	assert_eq(economy.issued, [], "a Lab whose dominion buys nothing is a site thrown away")


func test_the_base_route_still_prices_its_next_source_by_site() -> void:
	# The control: the stacking branch must not leak into the routes that existed before it.
	var bot := _bot()
	bot.route = autofree(DominionRoute.new())
	bot.owned = [autofree(Node.new())]
	bot.demand = 500
	var economy := _economy(bot)
	assert_false(economy._extend_dominion(null))
	assert_true(economy.surveyed)


func test_only_the_technocratic_route_stacks() -> void:
	assert_false(autofree(DominionRoute.new()).another_source_adds_income())
	assert_true(autofree(TechnocraticDominion.new()).another_source_adds_income())
#endregion


#region Dominion demand
func test_dominion_demand_is_what_the_grid_still_costs_less_the_bank() -> void:
	var bot: Bot = autofree(Bot.new())
	var unlock := SanctionUnlock.new()
	unlock.sanction = Sanction.new()
	unlock.sanction.ability_id = &"fake_sanction"
	unlock.dominion_cost = 300
	bot.sanction_grid = SanctionGrid.new(bot, [unlock])
	bot.dominion = 100
	assert_eq(bot.dominion_demand(), 200)
	bot.dominion = 400
	assert_eq(bot.dominion_demand(), 0, "a bank that covers the grid wants no more")


func test_a_commander_with_no_sanctions_wants_no_dominion() -> void:
	var bot: Bot = autofree(Bot.new())
	assert_eq(bot.dominion_demand(), 0)
	bot.sanction_grid = SanctionGrid.new(bot, [])
	assert_eq(bot.dominion_demand(), 0)
#endregion


#region A trained infrastructure provider
func _producer() -> Actor:
	var producer: Actor = FakePieces.structure({"produces": [SURVEYOR]})
	add_child_autofree(producer)
	return producer


func _production(a_bot: FakeBot) -> Array:
	var actuator := RecordingActuator.new(null)
	var production := BotProduction.new(a_bot, actuator)
	return [autofree(production), autofree(actuator)]


func test_a_strained_bot_trains_its_infrastructure_unit_first() -> void:
	var bot := _bot()
	bot.strained = true
	var producer := _producer()
	var made: Array = _production(bot)
	assert_eq((made[0] as BotProduction)._train_infrastructure_unit([producer]), producer)
	assert_eq((made[1] as RecordingActuator).trained, [[producer, SURVEYOR]])


func test_an_unstrained_bot_trains_no_infrastructure_unit() -> void:
	var bot := _bot()
	var made: Array = _production(bot)
	assert_null((made[0] as BotProduction)._train_infrastructure_unit([_producer()]))
	assert_eq((made[1] as RecordingActuator).trained, [])


func test_a_structure_provider_is_left_to_the_economy() -> void:
	var bot := _bot()
	bot.strained = true
	bot.provider_is_unit = false
	var made: Array = _production(bot)
	assert_null((made[0] as BotProduction)._train_infrastructure_unit([_producer()]))


func test_the_economy_banks_for_a_trainable_unit_and_falls_back_without_one() -> void:
	var bot := _bot()
	var economy := _economy(bot)
	assert_false(economy._infrastructure_unit_trainable(), "nothing can train it")
	bot.producers = [_producer()]
	assert_true(economy._infrastructure_unit_trainable())
#endregion
