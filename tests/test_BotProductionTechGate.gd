extends GutTest
## A UNIT BEHIND A STRUCTURE IS A CANDIDATE AT ITS CHAIN COST (Alex, 2026-10-30), never at its
## own. At its own cost a tech-locked unit scored best, was picked every tick and refused by
## the spend gate, and the caller banked for it rather than falling back — the producer stood
## idle on a unit the bot had no building for (2026-10-04). Priced at the chain, a locked pick
## proposes the chain's first link to the savings goal for the economy to build, and the
## producer trains the best unit it CAN make under that claim meanwhile.

const RECRUIT: StringName = &"test_recruit"
const GUARD: StringName = &"test_guard"  # better gun, behind a tech structure the bot lacks
const TECH: StringName = &"test_tech"


class FakeBot:
	extends Bot
	var owned: Array = []
	var idle_producers: Array = []
	var values: Dictionary = {RECRUIT: 1.0, GUARD: 5.0}

	func can_afford(_a_type: StringName) -> bool:
		return true

	func get_structures_of_type(a_type: StringName) -> Array:
		return [null] if owned.has(a_type) else []

	func builder_may_place(a_type: StringName) -> bool:
		return a_type == TECH

	func enemy_demand_map() -> Dictionary:
		return {&"enemy": {"demand": 1.0, "rep": null}}

	func unit_composition_value(a_unit_type, _a_demand: Dictionary) -> float:
		return float(values.get(a_unit_type, 0.0))

	func unit_can_attack(_a_type) -> bool:
		return true

	func get_idle_production_structures() -> Array:
		return idle_producers


class StubActuator:
	extends BotActuator
	var trains: Array = []

	func train(_a_structure: Actor, a_type: StringName) -> bool:
		trains.append(a_type)
		return true


var _bot: FakeBot
var _act: StubActuator


func before_each() -> void:
	_bot = FakeBot.new()
	_bot.technology_mapping = {
		RECRUIT: TechnologySpec.new(100, 0, 0, 30),
		GUARD: TechnologySpec.new(200, 0, 0, 30, [TECH]),
		TECH: TechnologySpec.new(800, 0, 0, 30),
	}
	_bot.energy = 5000
	_act = StubActuator.new(null)
	var structure := autofree(Actor.new()) as Actor
	structure.production = Production.new()
	structure.production.producible_types = [RECRUIT, GUARD]
	structure.add_child(structure.production)
	_bot.idle_producers = [structure]


func after_each() -> void:
	_bot.free()


func _production() -> BotProduction:
	var production := BotProduction.new(_bot, _act)
	production.reserve = 0
	production.tech_value_margin = 1.3
	return production


func _unlock_guard() -> void:
	_bot.owned = [TECH]
	_bot.technology_mapping[GUARD].unmet_need = TechnologySpec.UnmetNeed.NONE


func test_a_locked_unit_competes_at_its_chain_cost() -> void:
	# The Guard's 5.0 is per energy of a Guard; per energy of the tech structure and a Guard
	# it is 5.0 × 200 / 1000 = 1.0 — no better than the Recruit, so not worth the chain.
	_production().tick()
	assert_eq(_act.trains, [RECRUIT])
	assert_eq(_bot.savings.goal(), &"", "the pick was bought: nothing left to save for")
	var choices: Dictionary = _act.usage.choices()["train"]
	assert_eq(choices[String(GUARD)]["considered"], 1, "a candidate, priced at its chain")
	assert_almost_eq(float(choices[String(GUARD)]["score_sum"]), 1.0, 1e-9)


func test_a_locked_unit_worth_its_chain_is_not_trained_but_its_chain_is_proposed() -> void:
	_bot.values[GUARD] = 10.0  # 2.0 at the chain: 1.3 times the Recruit and more
	_production().tick()
	assert_eq(_act.trains, [RECRUIT], "the producer trains what it can under the claim")
	var proposal: Dictionary = _bot.savings.proposals()[&"production"]
	assert_eq(proposal["type"], TECH, "the chain's first link is what the bank is held for")
	assert_eq(proposal["cost"], 800)
	assert_almost_eq(float(proposal["value"]), 2.0, 1e-9, "at the Guard's chain-priced value")
	assert_eq(_act.usage.choices()["train"][String(GUARD)]["chosen"], 1)


func test_a_locked_unit_must_clear_the_tech_margin_over_the_trainable_best() -> void:
	_bot.values[GUARD] = 6.0  # 1.2 at the chain: better than the Recruit, under 1.3 times it
	_production().tick()
	assert_eq(_act.trains, [RECRUIT])
	assert_eq(_bot.savings.goal(), &"", "the Recruit was bought; the tech is not saved for")


func test_once_unlocked_the_better_unit_wins_at_its_own_cost() -> void:
	_unlock_guard()
	_production().tick()
	assert_eq(_act.trains, [GUARD])


func test_a_chain_no_builder_could_place_leaves_the_unit_out() -> void:
	_bot.values[GUARD] = 10.0
	_bot.technology_mapping[TECH] = TechnologySpec.new(800, 0, 0, 30, [&"test_unplaceable"])
	_bot.technology_mapping[&"test_unplaceable"] = TechnologySpec.new(100, 0, 0, 30)
	_production().tick()
	assert_eq(_act.trains, [RECRUIT])
	assert_false(_act.usage.choices()["train"].has(String(GUARD)), "not even a candidate")


func test_a_unit_waiting_on_a_structure_going_up_is_not_a_candidate_yet() -> void:
	_bot.values[GUARD] = 10.0
	_bot.owned = [TECH]  # going up: owned by the map, locked until it is built
	_production().tick()
	assert_eq(_act.trains, [RECRUIT])
	assert_false(_act.usage.choices()["train"].has(String(GUARD)))
