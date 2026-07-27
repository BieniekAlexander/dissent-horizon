extends GutTest

## THE INCOME TARGET, AND THE SIGNAL THAT BENDS IT.
##
## `BotDifficulty.income_structure_target` is a searchable number — how many extractors the
## bot wants standing before it adds production capacity — and `BotEconomy.safety()` is what
## makes it a decision rather than a build order: greed when safe, capacity when threatened.
## Both halves are pinned here, because either alone is the wrong thing. A bare constant is
## the hardcoded opening the question was asked about; a modulation with no parameter under
## it is not searchable and cannot be documented with a bound.
##
## Fixtures are stubs on the tests/test_BotEconomyReserve.gd pattern: what is under test is
## which rung of `tick()` runs and what number the target resolves to, and both are decided
## from counts and balances rather than from a live map.

const RESERVE: int = 600
const EXTRACTOR: StringName = &"test_extractor"
const REDOUBT: StringName = &"test_redoubt"


class FakeBot:
	extends Bot
	var costs: Dictionary = {}
	var own_army_value: float = 1000.0
	var believed_value: float = 0.0
	var under_threat: bool = false
	var threat_radius_seen: float = -1.0

	func can_afford(a_type: StringName) -> bool:
		return energy >= int(costs.get(a_type, 0))

	func needs_infrastructure_provider() -> bool:
		return false

	func army_resource_value() -> float:
		return own_army_value

	func believed_enemy_army_value() -> float:
		return believed_value

	func is_base_under_threat(a_threat_radius: float = 30.0) -> bool:
		threat_radius_seen = a_threat_radius
		return under_threat


class StubActuator:
	extends BotActuator
	var builds: Array = []

	func build(_a_builder: Commandable, a_type: StringName, _a_pos: Vector3) -> bool:
		builds.append(a_type)
		return true


class StubEconomy:
	extends BotEconomy
	var production_offer: Variant = null
	var income_offer: Variant = null
	var income_owned: int = 0
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

	func _owned_income_structure_count() -> int:
		return income_owned

	func _find_build_spot(_a_type: StringName) -> Variant:
		return Vector3.ZERO


## A momentum whose loss rate the test sets outright — the trend itself is
## tests/test_BotMomentum.gd's subject, not this one's.
class StubMomentum:
	extends BotMomentum
	var rate: float = 0.0

	func loss_rate() -> float:
		return rate


var _bot: FakeBot
var _act: StubActuator


func before_each() -> void:
	_bot = FakeBot.new()
	_bot.costs = {EXTRACTOR: 500, REDOUBT: 900}
	_bot.technology_mapping = {
		EXTRACTOR: TechnologySpec.new(500, 0, 0, 30),
		REDOUBT: TechnologySpec.new(900, 0, 0, 30),
	}
	_bot.energy = 5000
	_act = StubActuator.new(null)


func after_each() -> void:
	_bot.free()


func _economy(a_momentum: BotMomentum = null) -> StubEconomy:
	var economy := StubEconomy.new(_bot, _act, a_momentum)
	economy.reserve = RESERVE
	economy.builder = autofree(Commandable.new()) as Commandable
	economy.income_offer = EXTRACTOR
	economy.production_offer = REDOUBT
	economy._prev_energy = _bot.energy  # in surplus, so the capacity rung is live
	return economy


# ─── THE TARGET IS A NUMBER, AND IT OUTRANKS THROUGHPUT ─────────────────────

func test_income_is_bought_before_production_capacity_while_below_the_target() -> void:
	# THE OPENING QUESTION. Both rungs are affordable and both have somewhere to go; the bot
	# used to take the redoubt every time and finish its first extractor at a mean of 125 s.
	var economy := _economy()
	economy.income_structure_target = 1
	economy.tick()
	assert_eq(_act.builds, [EXTRACTOR], "the first extractor comes before the first barracks")


func test_throughput_resumes_once_the_target_is_met() -> void:
	var economy := _economy()
	economy.income_structure_target = 1
	economy.income_owned = 1
	economy.tick()
	assert_eq(_act.builds, [REDOUBT], "the target is a target, not a permanent income-first rule")


func test_a_target_of_zero_reproduces_the_old_opening() -> void:
	# The bound's bottom end has to mean something, and what it means is the pre-2026-09-05
	# ladder — throughput first, income only through the fall-through.
	var economy := _economy()
	economy.income_structure_target = 0
	economy.tick()
	assert_eq(_act.builds, [REDOUBT])


func test_a_higher_target_keeps_taking_sites() -> void:
	var economy := _economy()
	economy.income_structure_target = 3
	economy.income_owned = 2
	economy.tick()
	assert_eq(_act.builds, [EXTRACTOR], "a target of 3 is not satisfied by 2")


func test_an_unclaimable_site_falls_through_to_throughput() -> void:
	# No free extraction site left. Banking here would stall the bot on a map it has already
	# taken, so the rung is a fall-through like the income rung below it.
	var economy := _economy()
	economy.income_structure_target = 1
	economy.site_spot = null
	economy.tick()
	assert_eq(_act.builds, [REDOUBT])


func test_an_unaffordable_extractor_falls_through_rather_than_banking() -> void:
	var economy := _economy()
	economy.income_structure_target = 1
	economy.income_offer = null  # nothing affordable in the income set
	economy.tick()
	assert_eq(_act.builds, [REDOUBT])


# ─── SAFETY IS WHAT BENDS IT ────────────────────────────────────────────────

func test_an_unseen_opponent_reads_as_safe() -> void:
	# Deliberate, and the same argument the fog-limited ATTACK objective rests on: believing
	# in no enemy means expanding, and being wrong about that is what makes scouting pay.
	_bot.believed_value = 0.0
	assert_almost_eq(_economy().safety(), 1.0, 0.001)


func test_an_attack_on_the_base_collapses_safety_to_zero() -> void:
	_bot.under_threat = true
	assert_eq(_economy().safety(), 0.0, "an enemy in the base is not a matter of degree")


func test_safety_reads_the_threat_radius_it_was_configured_with() -> void:
	# The economy is the third consumer of defend_threat_radius; a copy of the number here
	# would be exactly the drift the field was created to stop.
	var economy := _economy()
	economy.defend_threat_radius = 17.0
	economy.safety()
	assert_eq(_bot.threat_radius_seen, 17.0)


func test_a_believed_army_twice_our_size_halves_safety_and_more() -> void:
	_bot.own_army_value = 1000.0
	_bot.believed_value = 2000.0
	assert_almost_eq(_economy().safety(), 1.0 / 3.0, 0.001)


func test_bleeding_army_value_reduces_safety() -> void:
	var momentum := StubMomentum.new(_bot)
	momentum.rate = BotMomentum.LOSING_LOSS_RATE * 0.5
	assert_almost_eq(_economy(momentum).safety(), 0.5, 0.001)


func test_losing_outright_collapses_safety() -> void:
	var momentum := StubMomentum.new(_bot)
	momentum.rate = BotMomentum.LOSING_LOSS_RATE * 2.0
	assert_eq(_economy(momentum).safety(), 0.0, "the term is clamped, not unbounded")


func test_a_missing_momentum_simply_drops_that_term() -> void:
	assert_almost_eq(_economy(null).safety(), 1.0, 0.001)


# ─── THE TWO HALVES TOGETHER ────────────────────────────────────────────────

func test_the_effective_target_is_the_parameter_scaled_by_safety() -> void:
	_bot.own_army_value = 1000.0
	_bot.believed_value = 1000.0  # safety 0.5
	var economy := _economy()
	economy.income_structure_target = 4
	assert_eq(economy.effective_income_target(), 2, "greed is halved, not abolished")


func test_safety_never_raises_the_target_above_the_parameter() -> void:
	var economy := _economy()
	economy.income_structure_target = 2
	assert_eq(economy.safety(), 1.0)
	assert_eq(economy.effective_income_target(), 2, "1.0 is the ceiling on the multiplier")


func test_a_threatened_bot_builds_capacity_instead_of_income() -> void:
	# THE RIDER ON THE ANSWER, end to end: the same bot, the same balance, the same two
	# affordable options — and the only thing that changed is that it is under attack.
	_bot.under_threat = true
	var economy := _economy()
	economy.income_structure_target = 3
	assert_eq(economy.effective_income_target(), 0)
	economy.tick()
	assert_eq(_act.builds, [REDOUBT], "committing to defence is not wasteful right now")


func test_the_same_bot_takes_the_extractor_when_the_attack_stops() -> void:
	var economy := _economy()
	economy.income_structure_target = 3
	_bot.under_threat = false
	economy.tick()
	assert_eq(_act.builds, [EXTRACTOR], "and greedy again the moment nothing is pressing")


# ─── THE KNOB HAS TO REACH THE MANAGER ──────────────────────────────────────

## A SILENT KNOB is the failure mode a passing suite cannot otherwise catch
## (gdd/systems/ai/bot-parameter-space.md §Proving the defaults): a field the harness can
## inject and set, which no manager ever reads, reports a result for an experiment that did
## not run. Every default here also equals the manager's own, so a missing push would look
## exactly like a working one.
##
## Detected in `BotBrain`'s source rather than declared in a table, the same discipline
## tests/test_BotCommandCoverage.gd uses — a table would only be recording my word for it.
func test_the_new_parameters_are_pushed_into_their_managers() -> void:
	var source: String = FileAccess.get_file_as_string(
		"res://scripts/interface/commander/bot_brain.gd"
	)
	assert_ne(source, "", "the brain's source is readable")
	for field: String in [
		"config.income_structure_target",  # → BotEconomy, the target itself
		"config.defend_threat_radius",     # → BotEconomy.safety, its third consumer
		"config.build_concurrency",        # → BotProduction, the builder demand
		"config.scout_unit_budget",        # → BotProduction, the scouting term
	]:
		assert_true(source.contains(field), "%s is read by _apply_config" % field)


func test_the_economy_is_handed_the_momentum_signal() -> void:
	# Half of safety() is "am I bleeding right now", and a null momentum silently drops it —
	# which would leave the bot expanding through a fight it is losing.
	var source: String = FileAccess.get_file_as_string(
		"res://scripts/interface/commander/bot_brain.gd"
	)
	assert_true(source.contains("BotEconomy.new(bot, _actuator, _momentum)"))
