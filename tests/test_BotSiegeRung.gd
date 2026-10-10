extends GutTest

## THE SIEGE RUNG (Alex, 2026-10-10 — gdd/tasks.md T-002, option 1): a siege gun is bought on
## DEMAND, like a builder or a carrier, because no fight prices it. It is wanted while the bot
## believes an enemy structure stands and owns a mobile spotter to carry a solution to it; a gun
## locked behind a tech structure buys that structure first; and a wanted gun is proposed to
## the savings goal so the bank is held for it (gdd/systems/ai/bot-architecture.md §The siege
## rung). The fixture answers the Bot's reads directly, as test_BotTechRung does.

const GUN: StringName = &"test_gun"
const TECH: StringName = &"test_tech"
const BARRACKS: StringName = &"test_barracks"
const RECRUIT: StringName = &"test_recruit"
const RESERVE: int = 200


class FakeBot:
	extends Bot
	var owned: Dictionary = {}  # structure type -> count
	var wants: bool = true
	var guns: Array = [GUN]
	var buildable: Array = [TECH, BARRACKS, GUN]

	func can_afford(_a_type: StringName) -> bool:
		return true

	func needs_infrastructure_provider() -> bool:
		return false

	func wants_siege_gun() -> bool:
		return wants

	func siege_gun_types() -> Array:
		return guns

	func buildable_structure_types() -> Array:
		return buildable.filter(func(t: StringName) -> bool: return has_tech_for(t))

	func buildable_defence_structure_types() -> Array:
		return []

	func buildable_production_structure_types() -> Array:
		return []

	func get_structures_of_type(a_type: StringName) -> Array:
		var out: Array = []
		for i: int in int(owned.get(a_type, 0)):
			out.append(null)
		return out

	func enemy_demand_map() -> Dictionary:
		return {&"enemy": {"demand": 1.0, "rep": null}}

	func purchase_values_per_energy(a_types: Array, _a_demand: Dictionary = {}) -> Dictionary:
		var values: Dictionary = {}
		for t: StringName in a_types:
			values[t] = 0.5
		return {"values": values, "learned": false}

	func producible_types_of(_a_structure_type: StringName) -> Array:
		return [RECRUIT]

	func unit_can_attack(_a_type) -> bool:
		return true

	var _producer: Actor = null

	func get_production_structures() -> Array:
		if _producer == null:
			_producer = Actor.new()
			_producer.production = Production.new()
			_producer.add_child(_producer.production)
		_producer.production.producible_types.assign([RECRUIT])
		return [_producer]

	func release() -> void:
		if _producer != null:
			_producer.free()
			_producer = null


class StubActuator:
	extends BotActuator
	var builds: Array = []

	func build(
		_a_builder: Actor, a_type: StringName, _a_pos: Vector3, _a_quarter_turns: int = 0
	) -> bool:
		builds.append(a_type)
		return true


class StubEconomy:
	extends BotEconomy
	var builder: Actor

	func _construction_job_count() -> int:
		return 0

	func _release_stalled_construction() -> void:
		pass

	func _pick_builder() -> Actor:
		return builder

	func _dominion_structure_to_build() -> Variant:
		return null

	func _infrastructure_structure_to_build() -> Variant:
		return null

	func _extend_dominion(_a_builder: Actor) -> bool:
		return false

	func _income_structure_to_build() -> Variant:
		return null

	func _defence_rung(_a_builder: Actor) -> bool:
		return false

	func _tech_rung(_a_builder: Actor) -> bool:
		return false

	func _types_under_way() -> Array[StringName]:
		return []

	func _find_build_spot(_a_type: StringName) -> Variant:
		return Vector3.ZERO


var _bot: FakeBot
var _act: StubActuator


func before_each() -> void:
	_bot = FakeBot.new()
	# The gun needs the tech structure; the tech structure needs the barracks, which stands.
	_bot.technology_mapping = {
		GUN: TechnologySpec.new(1000, 0, 0, 30, [TECH]),
		TECH: TechnologySpec.new(800, 0, 0, 30, [BARRACKS]),
		BARRACKS: TechnologySpec.new(300, 0, 0, 30),
		RECRUIT: TechnologySpec.new(100, 0, 0, 30),
	}
	_bot.owned = {BARRACKS: 1}
	_bot.energy = 5000
	_act = StubActuator.new(null)
	_resolve_tech()


func after_each() -> void:
	_bot.release()
	_bot.free()


## TechnologySpec reads its needs off what is owned: say so for each spec.
func _resolve_tech() -> void:
	for t: StringName in _bot.technology_mapping:
		var spec: TechnologySpec = _bot.technology_mapping[t]
		var met: bool = spec.required_structures.all(
			func(r: StringName) -> bool: return int(_bot.owned.get(r, 0)) > 0
		)
		spec.unmet_need = (
			TechnologySpec.UnmetNeed.NONE if met else TechnologySpec.UnmetNeed.MISSING_STRUCTURE
		)


func _economy() -> StubEconomy:
	var economy := StubEconomy.new(_bot, _act)
	economy.reserve = RESERVE
	economy.income_structure_target = 0
	economy.builder = autofree(Actor.new()) as Actor
	economy._prev_energy = _bot.energy
	return economy


func test_a_wanted_gun_behind_tech_buys_the_tech_structure_first() -> void:
	_economy().tick()
	assert_eq(_act.builds, [TECH], "the structure that unlocks the gun")


func test_with_the_tech_standing_the_gun_itself_is_bought() -> void:
	_bot.owned = {BARRACKS: 1, TECH: 1}
	_resolve_tech()
	_economy().tick()
	assert_eq(_act.builds, [GUN])


func test_a_gun_that_stands_is_not_bought_again() -> void:
	_bot.owned = {BARRACKS: 1, TECH: 1, GUN: 1}
	_resolve_tech()
	_economy().tick()
	assert_eq(_act.builds, [], "SIEGE_GUNS_WANTED is one")


func test_no_want_means_no_gun_and_no_tech_for_it() -> void:
	_bot.wants = false
	_economy().tick()
	assert_eq(_act.builds, [])


func test_a_gun_too_dear_for_the_reserve_waits() -> void:
	_bot.owned = {BARRACKS: 1, TECH: 1}
	_resolve_tech()
	_bot.energy = 1100  # 1000 for the gun would breach the 200 reserve
	_economy().tick()
	assert_eq(_act.builds, [])


func test_the_wanted_purchase_is_proposed_to_the_savings_goal() -> void:
	var economy: StubEconomy = _economy()
	economy._propose_savings()
	var proposals: Dictionary = _bot.savings.proposals()
	assert_true(proposals.has(&"siege"), "proposed under its own source")
	assert_eq(proposals[&"siege"]["type"], TECH, "what the rung would buy now")
	assert_eq(proposals[&"siege"]["cost"], 800)
	assert_almost_eq(float(proposals[&"siege"]["value"]), 0.5, 0.001, "the best trainable unit's")


func test_the_demanded_purchase_outranks_a_valued_one_of_equal_value() -> void:
	# A producer priced at the same best-unit value, and dearer: without the demand flag it won
	# the goal on cost and the gun's tech was never saved for (Alex, 2026-10-10, option 1).
	var economy: StubEconomy = _economy()
	economy._propose_savings()
	_bot.savings.propose(&"economy", &"test_factory", 0.5, 1200)
	_bot.savings.propose(&"production", RECRUIT, 0.5, 100)
	assert_eq(_bot.savings.goal(), TECH, "demanded beats valued at equal value, whatever the cost")
	assert_true(bool(_bot.savings.proposals()[&"siege"]["demanded"]))
