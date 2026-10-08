extends GutTest

## A BUILD THAT NEVER FINISHES FREEZES THE WHOLE ECONOMY, and this is what stops it.
##
## `BotEconomy.tick()` returns at the very top while `build_concurrency` jobs are in flight.
## That rate limit is deliberate — one builder serialising the work is what keeps two builds
## off the same cells — but it has no way out: a `Build` aimed somewhere the builder can
## never finish is never released, so the bot takes the "already building" exit on every
## subsequent think and stops expanding, training and taking income for the rest of the
## match while its bank fills.
##
## Measured on an instrumented match: one side took that exit on 537 of 539 think passes
## after claiming its second extraction site, with a structure count frozen at 3 for five
## simulated minutes and 8,000 energy banked. Five of twelve slot-trajectories froze for
## 90-270 s; the ladder before the income target reached for a site only when it was too poor
## to do anything else, which is why the hazard was latent rather than new.
##
## Two behaviours are pinned: the job is released, and the SPOT is remembered — without the
## second the same rung re-orders the same doomed build on the next think and the freeze
## becomes a loop, which spends the builder forever instead of merely wasting a slot.

const EXTRACTOR: StringName = &"test_extractor"
const REDOUBT: StringName = &"test_redoubt"


class FakeBot:
	extends Bot
	var units: Array = []
	var clock: float = 0.0

	func can_afford(_a_type: StringName) -> bool:
		return true

	func needs_infrastructure_provider() -> bool:
		return false

	func get_units() -> Array:
		return units

	func seconds_elapsed() -> float:
		return clock

	func is_base_under_threat(_a_threat_radius: float = 30.0) -> bool:
		return false


class StubActuator:
	extends BotActuator
	var builds: Array = []

	func build(
		_a_builder: Commandable, a_type: StringName, a_pos: Vector3, _a_quarter_turns: int = 0
	) -> bool:
		builds.append([a_type, a_pos])
		return true


class StubEconomy:
	extends BotEconomy
	var builder: Commandable
	var income_offer: Variant = EXTRACTOR
	var site_spot: Variant = Vector3.ZERO
	var income_owned: int = 0

	func _pick_builder() -> Commandable:
		return builder

	func _dominion_structure_to_build() -> Variant:
		return null

	func _infrastructure_structure_to_build() -> Variant:
		return null

	func _production_structure_to_build() -> Variant:
		return null

	func _income_structure_to_build() -> Variant:
		return income_offer

	func _income_build_spot() -> Variant:
		return site_spot

	func _owned_income_structure_count() -> int:
		return income_owned


## A builder stuck on a Build it will never complete — which from outside is exactly what a
## builder walking to a legitimate site looks like, and why the guard is a timeout.
class StuckBuilder:
	extends Commandable
	var order: Build

	static func aimed_at(a_map: Map, a_pos: Vector3) -> StuckBuilder:
		var unit := StuckBuilder.new()
		unit.order = Build.new(CommandMessage.new(a_map, null, null, a_pos))
		return unit

	func has_command() -> bool:
		return order != null

	func current_command() -> MoveCommand:
		return order

	func update_commands(
		a_command: Variant, _a_queue: bool = false, _a_notify: bool = false
	) -> void:
		order = a_command as Build


var _bot: FakeBot
var _act: StubActuator
var _economy: StubEconomy
var _builder: StuckBuilder

const STUCK_AT := Vector3(40, 0, 40)


func before_each() -> void:
	_bot = FakeBot.new()
	_bot.energy = 5000
	_bot.technology_mapping = {
		EXTRACTOR: TechnologySpec.new(500, 0, 0, 30),
		REDOUBT: TechnologySpec.new(900, 0, 0, 30),
	}
	_act = StubActuator.new(null)
	_builder = StuckBuilder.aimed_at(null, STUCK_AT)
	_bot.units = [_builder]
	_economy = StubEconomy.new(_bot, _act)
	_economy.builder = _builder
	_economy.site_spot = STUCK_AT


func after_each() -> void:
	_builder.free()
	_bot.free()


func test_a_job_inside_the_timeout_keeps_its_slot() -> void:
	_economy.tick()  # first sighting: the clock starts
	_bot.clock = BotEconomy.CONSTRUCTION_JOB_TIMEOUT_SECONDS - 1.0
	_economy.tick()
	assert_true(_builder.has_command(), "a builder that is merely slow is left alone")


func test_a_job_past_the_timeout_gives_its_slot_back() -> void:
	_economy.tick()
	_bot.clock = BotEconomy.CONSTRUCTION_JOB_TIMEOUT_SECONDS + 1.0
	_economy.tick()
	assert_false(_builder.has_command(), "the order that could never arrive is dropped")


func test_the_frozen_economy_resumes_once_the_slot_is_free() -> void:
	# THE ACTUAL SYMPTOM: not a wasted builder, a bot that stops doing anything at all.
	_economy.income_offer = null  # nothing any rung can act on, so only the slot is in play
	for _i: int in 5:
		_economy.tick()
	assert_eq(_act.builds.size(), 0, "nothing could be ordered while the slot was held")

	_bot.clock = BotEconomy.CONSTRUCTION_JOB_TIMEOUT_SECONDS + 1.0
	_economy.tick()  # releases the slot
	_economy.income_offer = EXTRACTOR
	_economy.site_spot = Vector3(9, 0, 9)  # somewhere the bot has not written off
	_economy.tick()
	assert_eq(_act.builds.size(), 1, "and the ladder runs again once it is released")


func test_the_written_off_spot_is_not_ordered_again() -> void:
	# Without this the rung that chose the bad spot picks it again on the next think, and a
	# permanent freeze becomes a 90-second loop that spends the builder forever.
	_economy.tick()
	_bot.clock = BotEconomy.CONSTRUCTION_JOB_TIMEOUT_SECONDS + 1.0
	_economy.tick()
	assert_true(_economy._is_abandoned_spot(STUCK_AT))
	assert_false(
		_economy._is_abandoned_spot(Vector3(80, 0, 80)), "somewhere else is still fair game"
	)


func test_a_finished_job_is_forgotten_rather_than_accumulating() -> void:
	_economy.tick()
	assert_eq(_economy._job_started.size(), 1)
	_builder.order = null  # the build completed
	_economy.tick()
	assert_eq(_economy._job_started.size(), 0, "the timer is per job, not per builder-lifetime")
