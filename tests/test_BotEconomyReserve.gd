extends GutTest

## Regression tests for THE ECONOMY RESERVE AS A FLOOR, and for the fall-through to income
## that made the extractor rung reachable. Both come out of the measurement written up in
## gdd/systems/ai/bot-economy-diagnosis.md, where the shipped bot finished 145 of 170
## measured slot-trajectories owning ZERO extractors — no income at all — and sat at exactly
## zero energy for 70% of sampled ticks.
##
## Two defects are pinned here, because either one alone reproduces the bankruptcy:
##
##  1. `economy_reserve` was a TRIGGER and not a FLOOR. BotProduction trained on plain
##     affordability and never saw the threshold at all, so the pool it was meant to protect
##     was drained by the path it did not gate.
##  2. BotEconomy's surplus branch RETURNED when it had nothing to add to throughput, so a
##     bot sitting above the reserve never looked at income — and by the time it dropped
##     below the reserve it could no longer afford an extractor.
##
## The fixtures are stubs, not a scene: what is under test is which branch runs and whether
## a purchase is permitted, and both are decided from the balance, the cost and the reserve.

const RESERVE: int = 600
const EXTRACTOR: StringName = &"test_extractor"
const REDOUBT: StringName = &"test_redoubt"
const TROOPER: StringName = &"test_trooper"


## A Bot whose balance and price list the test sets directly. `can_afford` is overridden
## because the real one walks a TechnologySpec against live world state; what these tests
## vary is the balance against the price, which is the whole of the reserve arithmetic.
class FakeBot:
	extends Bot
	var costs: Dictionary = {}
	var idle_producers: Array = []
	var needs_infra: bool = false

	func can_afford(a_type: StringName) -> bool:
		return energy >= int(costs.get(a_type, 0))

	func needs_infrastructure_provider() -> bool:
		return needs_infra

	func get_idle_production_structures() -> Array:
		return idle_producers

	func enemy_demand_map() -> Dictionary:
		return {}

	func unit_can_attack(_a_type) -> bool:
		return true


## Records what was ordered instead of issuing it. BotActuator is the bot's only mutation
## surface, so intercepting it is enough to observe every decision these managers take.
class StubActuator:
	extends BotActuator
	var builds: Array = []
	var trains: Array = []

	func build(_a_builder: Commandable, a_type: StringName, _a_pos: Vector3) -> bool:
		builds.append(a_type)
		return true

	func train(_a_structure: Commandable, a_type: StringName) -> bool:
		trains.append(a_type)
		return true


## BotEconomy with the world-facing helpers stubbed: a builder is always free, a build spot
## always exists, and the caller chooses what each rung offers. What is left un-stubbed is
## tick()'s branching and _has_resource_surplus, which is exactly what is under test.
class StubEconomy:
	extends BotEconomy
	var production_offer: Variant = null
	var income_offer: Variant = null
	var builder: Commandable
	var site_spot: Variant = Vector3.ZERO

	func _construction_job_count() -> int:
		return 0

	func _pick_builder() -> Commandable:
		return builder

	func _dominion_structure_to_build() -> Variant:
		return null

	func _infrastructure_structure_to_build() -> Variant:
		return null

	func _production_structure_to_build() -> Variant:
		return production_offer

	func _income_structure_to_build() -> Variant:
		return income_offer

	func _income_build_spot() -> Variant:
		return site_spot

	func _find_build_spot(_a_type: StringName) -> Variant:
		return Vector3.ZERO

	## Income structures already standing. Stubbed because the real count walks the buildable
	## registry, and what these tests vary is which RUNG runs, not what the map holds.
	var income_owned: int = 0

	func _owned_income_structure_count() -> int:
		return income_owned


var _bot: FakeBot
var _act: StubActuator


func before_each() -> void:
	_bot = FakeBot.new()
	_bot.costs = {EXTRACTOR: 500, REDOUBT: 900, TROOPER: 200}
	_bot.technology_mapping = {
		EXTRACTOR: TechnologySpec.new(500, 0, 0, 30),
		REDOUBT: TechnologySpec.new(900, 0, 0, 30),
		TROOPER: TechnologySpec.new(200, 0, 0, 30),
	}
	_act = StubActuator.new(null)


func after_each() -> void:
	_bot.free()


func _economy() -> StubEconomy:
	var economy := StubEconomy.new(_bot, _act)
	economy.reserve = RESERVE
	economy.builder = autofree(Commandable.new()) as Commandable
	economy.income_offer = EXTRACTOR
	return economy


func _production() -> BotProduction:
	var production := BotProduction.new(_bot, _act)
	production.reserve = RESERVE
	# One idle producer that can make the trooper. Out of tree, so the optional component
	# field is ours to assign (the tests/test_BotScout.gd fixture pattern).
	var structure := autofree(Commandable.new()) as Commandable
	structure.production = Production.new()
	structure.production.producible_types = [TROOPER]
	structure.add_child(structure.production)
	_bot.idle_producers = [structure]
	return production


# ─── THE RESERVE IS A FLOOR ─────────────────────────────────────────────────


func test_training_is_refused_when_it_would_breach_the_reserve() -> void:
	# 700 banked, a 200 trooper: affordable, but it would leave 500 — under the reserve.
	_bot.energy = 700
	_production().tick()
	assert_eq(_act.trains, [], "training must not spend the bank the reserve is holding")


func test_training_is_allowed_when_it_leaves_the_reserve_banked() -> void:
	_bot.energy = 800
	_production().tick()
	assert_eq(_act.trains, [TROOPER], "800 - 200 = 600 leaves the reserve intact")


func test_a_zero_reserve_leaves_training_on_plain_affordability() -> void:
	# The knob's bottom end must still mean "spend to zero", which is what it documents.
	_bot.energy = 200
	var production := _production()
	production.reserve = 0
	production.tick()
	assert_eq(_act.trains, [TROOPER])


func test_training_leaves_the_savings_goal_banked_on_top_of_the_reserve() -> void:
	# 900 banked: a trooper would leave 700, above the reserve — but not above the reserve and
	# the 900 a factory the bot is saving for needs. Cheap units no longer starve the dear buy.
	_bot.energy = 900
	_bot.savings.propose(&"economy", REDOUBT, 1.0e9, 900)
	_production().tick()
	assert_eq(_act.trains, [], "the trooper waits for the goal")
	_bot.savings.held = false
	_production().tick()
	assert_eq(_act.trains, [TROOPER], "a threatened base trains whatever is saved for")


func test_capacity_is_not_bought_down_through_the_reserve() -> void:
	_bot.energy = 1400  # affords the 900 redoubt, but only by spending the reserve
	assert_false(_economy().can_afford_above_reserve(REDOUBT))
	_bot.energy = 1500
	assert_true(_economy().can_afford_above_reserve(REDOUBT))


func test_the_floor_is_not_a_second_affordability_check() -> void:
	_bot.energy = 100
	assert_false(_economy().can_afford_above_reserve(TROOPER), "unaffordable is still unaffordable")


# ─── INCOME IS A FALL-THROUGH, NOT ONLY THE ELSE OF SURPLUS ─────────────────


func test_a_surplus_with_nothing_to_add_to_throughput_buys_income() -> void:
	# THE BUG: the bot is above its reserve (so `surplus` is true) and has no production
	# structure it can put up. It used to return here and do nothing, which is how it spent
	# whole matches above the reserve without ever claiming an extraction site.
	_bot.energy = 5000
	var economy := _economy()
	economy._prev_energy = 5000
	economy.production_offer = null
	economy.tick()
	assert_eq(_act.builds, [EXTRACTOR], "a surplus with nowhere else to go grows income")


func test_a_surplus_still_prefers_production_capacity() -> void:
	# ONCE THE INCOME TARGET IS MET. The income rung now runs BEFORE this one while the bot
	# wants more income than it owns (see test_BotIncomeTarget.gd); what this pins is that
	# beyond the target, a surplus goes to throughput exactly as it always did.
	_bot.energy = 5000
	var economy := _economy()
	economy._prev_energy = 5000
	economy.income_owned = 1  # target met
	economy.production_offer = REDOUBT
	economy.tick()
	assert_eq(_act.builds, [REDOUBT], "throughput is still the first call on a surplus")


func test_below_the_reserve_the_bot_grows_income() -> void:
	_bot.energy = 550
	var economy := _economy()
	economy._prev_energy = 550
	economy.production_offer = null
	economy.tick()
	assert_eq(_act.builds, [EXTRACTOR])


func test_no_income_rung_leaves_the_bot_idle_rather_than_erroring() -> void:
	_bot.energy = 5000
	var economy := _economy()
	economy._prev_energy = 5000
	economy.production_offer = null
	economy.income_offer = null
	economy.tick()
	assert_eq(_act.builds, [])
