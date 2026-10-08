extends GutTest
## A producer trains what the bot CAN train. A tech-locked unit that scores best was picked
## every tick and then refused by the spend gate, and the caller banked for it rather than
## falling back — so the producer stood idle on a unit the bot had no building for.

const RECRUIT: StringName = &"test_recruit"
const GUARD: StringName = &"test_guard"  # better gun, behind a tech structure the bot lacks


class FakeBot:
	extends Bot
	var unlocked: Dictionary = {RECRUIT: true, GUARD: false}
	var idle_producers: Array = []

	func can_afford(a_type: StringName) -> bool:
		return bool(unlocked.get(a_type, false))

	func has_tech_for(a_type: StringName) -> bool:
		return bool(unlocked.get(a_type, false))

	func enemy_demand_map() -> Dictionary:
		return {&"enemy": {"demand": 1.0, "rep": null}}

	func unit_composition_value(a_unit_type, _a_demand: Dictionary) -> float:
		return 5.0 if a_unit_type == GUARD else 1.0

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
	return production


func test_a_tech_locked_unit_is_not_picked_over_one_the_bot_can_train() -> void:
	_production().tick()
	assert_eq(_act.trains, [RECRUIT], "the best unit the bot CAN train, not the best unit")


func test_once_unlocked_the_better_unit_wins() -> void:
	_bot.unlocked[GUARD] = true
	_production().tick()
	assert_eq(_act.trains, [GUARD])


func test_the_locked_unit_is_not_even_a_candidate_in_the_ledger() -> void:
	_production().tick()
	var choices: Dictionary = _act.usage.choices()["train"]
	assert_false(choices.has(String(GUARD)), "a unit the bot cannot train is not a choice")
	assert_eq(choices[String(RECRUIT)]["chosen"], 1)
