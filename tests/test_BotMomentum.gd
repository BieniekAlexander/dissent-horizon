extends GutTest

## Unit tests for BotMomentum — the bot's "am I winning or losing" signals, the army-value
## trend and the balance of the front a wave stands on — and for the army-level retreat that is
## their consumer (BotMilitary._should_abort_wave).
##
## A FakeBot supplies the facts momentum reads, because they come from the world: a bare Bot
## reports seconds_elapsed() == 0 with no scenario, a real army cannot be stood up in a unit
## test, and the front is read off the bot's fields, which a FixtureFields over open ground
## stands in for (tests/_fixture_fields.gd). Overriding those senses is the whole fixture.

## The type the fixture's own pieces are, and the believed enemy's.
const OWN_TYPE: StringName = &"fake_recruit"
const ENEMY_TYPE: StringName = &"fake_foe"
## A 9 × 9 open lattice centred on the origin, so a wave with no fielded member (centroid ZERO)
## reads the fixture's middle cell.
const CENTRE := Vector2i(4, 4)


## A Bot whose clock, army value and fields the test drives directly.
class FakeBot:
	extends Bot
	var now: float = 0.0
	var army_value: float = 0.0
	## The fields the front is read off; null is a bot with no fields (the tier has them off).
	var fixture: FixtureFields = null

	func seconds_elapsed() -> float:
		return now

	func army_resource_value() -> float:
		return army_value

	func fields() -> BotFields:
		return fixture


var _bot: FakeBot
var _momentum: BotMomentum


func before_each() -> void:
	_bot = FakeBot.new()
	_momentum = BotMomentum.new(_bot)


func after_each() -> void:
	_bot.free()


## Drive the bot to `a_time` holding `a_value`, and sample it.
func _sample(a_time: float, a_value: float) -> void:
	_bot.now = a_time
	_bot.army_value = a_value
	_momentum.tick()


## A momentum reading a steep, sustained loss — a fight going badly.
func _losing() -> void:
	_sample(0.0, 1000.0)
	_sample(8.0, 700.0)


func test_no_history_is_not_a_trend() -> void:
	assert_eq(_momentum.value_slope_per_second(), 0.0, "one sample spans no time")
	assert_false(_momentum.is_losing())


func test_a_steady_army_is_not_losing() -> void:
	_sample(0.0, 1000.0)
	_sample(8.0, 1000.0)
	assert_eq(_momentum.value_slope_per_second(), 0.0)
	assert_false(_momentum.is_losing())


func test_a_growing_army_is_not_losing() -> void:
	_sample(0.0, 500.0)
	_sample(8.0, 900.0)
	assert_gt(_momentum.value_slope_per_second(), 0.0)
	assert_eq(_momentum.loss_rate(), 0.0, "gaining value is not a loss rate")
	assert_false(_momentum.is_losing())


func test_bleeding_fast_reads_as_losing() -> void:
	_losing()
	assert_almost_eq(_momentum.value_slope_per_second(), -37.5, 0.01)
	assert_true(_momentum.is_losing())


func test_trickling_losses_do_not_read_as_losing() -> void:
	# Ten units' worth of chip damage over the window is a fight being won cheaply, not a
	# rout — the threshold is what separates the two.
	_sample(0.0, 1000.0)
	_sample(8.0, 990.0)
	assert_lt(_momentum.loss_rate(), BotMomentum.LOSING_LOSS_RATE)
	assert_false(_momentum.is_losing())


func test_an_army_that_no_longer_exists_has_no_loss_rate() -> void:
	_sample(0.0, 400.0)
	_sample(8.0, 0.0)
	assert_eq(_momentum.loss_rate(), 0.0, "nothing left to lose — and no div by zero")


func test_the_window_drops_history_older_than_it() -> void:
	_sample(0.0, 1000.0)
	_sample(4.0, 900.0)
	_sample(30.0, 880.0)
	# The 0 s sample is outside an 8 s window, so the slope is read from 4 s onward — a
	# gentle decline, not the steep one the discarded sample would have implied.
	assert_almost_eq(_momentum.value_slope_per_second(), -20.0 / 26.0, 0.01)


# ─── THE FIRST CONSUMER: ARMY RETREAT ────────────────────────────────────────


func _military() -> BotMilitary:
	var military := BotMilitary.new(_bot, null, _momentum)
	military._wave_launch_value = 1000.0
	return military


func test_a_wave_bleeding_badly_is_called_off() -> void:
	_losing()
	assert_true(
		_military()._should_abort_wave(650.0), "a third of the army gone and still bleeding — leave"
	)


func test_a_wave_that_has_barely_been_scratched_presses_on() -> void:
	_losing()
	assert_false(
		_military()._should_abort_wave(950.0),
		"losing fast but nothing spent yet is not a failed push"
	)


func test_a_costly_wave_that_is_not_bleeding_presses_on() -> void:
	# The anti-dribble half: heavy losses ALREADY TAKEN are not a reason to leave, or the
	# bot goes back to feeding its army in one squad at a time.
	_sample(0.0, 650.0)
	_sample(8.0, 645.0)
	assert_false(_military()._should_abort_wave(650.0))


func test_a_military_with_no_momentum_never_retreats() -> void:
	_losing()
	var military := BotMilitary.new(_bot, null)
	military._wave_launch_value = 1000.0
	assert_false(
		military._should_abort_wave(100.0),
		"unconfigured behaves exactly as it did before retreat existed"
	)


func test_calling_off_a_wave_opens_a_regroup_window() -> void:
	_bot.now = 100.0
	var military := _military()
	military._end_wave()
	assert_almost_eq(military._regroup_until, 100.0 + BotMilitary.REGROUP_SECONDS, 0.01)
	assert_eq(military._stalemate_time, 0.0, "it has just fought; it is not in a stalemate")


# ─── THE FRONT ───────────────────────────────────────────────────────────────


## Give the bot fields over open ground with `a_own` of its own strength and `a_enemy` of the
## believed enemy's standing in the middle cell, under the answerability table `a_damage`
## (attacker type → the types it can damage; a type not listed damages everything).
func _front(a_own: float, a_enemy: float, a_damage: Dictionary = {}) -> FixtureFields:
	var fixture: FixtureFields = FixtureFields.over_open(Rect2(-22.5, -22.5, 45.0, 45.0))
	fixture.add_own(CENTRE, OWN_TYPE, a_own)
	fixture.add_enemy(CENTRE, ENEMY_TYPE, a_enemy)
	fixture.damage = a_damage
	_bot.fixture = fixture
	return fixture


## Re-read the fixture's fields after a change to what stands on them.
func _restamp(a_fixture: FixtureFields, a_own: float, a_enemy: float) -> void:
	a_fixture.own_strength = []
	a_fixture.sources = []
	a_fixture.add_own(CENTRE, OWN_TYPE, a_own)
	a_fixture.add_enemy(CENTRE, ENEMY_TYPE, a_enemy)
	a_fixture.rebuild_now()


func test_the_front_read_is_the_wave_s_share_of_the_answerable_strength_there() -> void:
	_front(400.0, 600.0)
	var front: Dictionary = _momentum.front_balance(Vector3.ZERO)
	assert_almost_eq(front["own"], 400.0, 0.001)
	assert_almost_eq(front["enemy"], 600.0, 0.001)
	assert_almost_eq(front["share"], 0.4, 1e-6)
	assert_eq(front["trend"], 0.0, "one sample spans no time")
	assert_eq(_momentum.last_front(), front)


func test_the_front_s_trend_is_the_share_s_slope_over_the_window() -> void:
	var fixture: FixtureFields = _front(500.0, 500.0)
	_bot.now = 0.0
	assert_almost_eq(_momentum.front_balance(Vector3.ZERO)["share"], 0.5, 1e-6)
	_restamp(fixture, 300.0, 500.0)
	_bot.now = 8.0
	var front: Dictionary = _momentum.front_balance(Vector3.ZERO)
	assert_almost_eq(front["share"], 0.375, 1e-6)
	assert_almost_eq(front["trend"], (0.375 - 0.5) / 8.0, 1e-6)


func test_without_fields_the_front_is_missing() -> void:
	assert_eq(_momentum.front_balance(Vector3.ZERO), {}, "no fields: nothing to read, not zero")
	assert_eq(_momentum.last_front(), {})


func test_forgetting_the_front_drops_its_history() -> void:
	_front(500.0, 500.0)
	_momentum.front_balance(Vector3.ZERO)
	_momentum.forget_front()
	assert_eq(_momentum.last_front(), {})
	_bot.now = 8.0
	assert_eq(_momentum.front_balance(Vector3.ZERO)["trend"], 0.0, "a fresh first sample")


func test_the_front_rule() -> void:
	assert_true(BotMomentum.is_losing_front({"share": 0.4, "trend": 0.0}), "outgunned 3:2")
	assert_false(BotMomentum.is_losing_front({"share": 0.45, "trend": 0.0}), "behind but holding")
	assert_true(BotMomentum.is_losing_front({"share": 0.45, "trend": -0.02}), "behind and slipping")
	assert_false(
		BotMomentum.is_losing_front({"share": 0.6, "trend": -0.1}), "ahead, whatever the slope"
	)
	assert_false(
		BotMomentum.is_losing_front({"share": 0.5, "trend": -0.1}), "even is not under even"
	)
	assert_almost_eq(BotMomentum.share_of(0.0, 0.0), 0.5, 1e-6, "nothing on either side is even")
	assert_almost_eq(BotMomentum.share_of(300.0, 0.0), 1.0, 1e-6)
	assert_almost_eq(BotMomentum.share_of(0.0, 300.0), 0.0, 1e-6)


# ─── THE RETREAT READS THE FRONT ─────────────────────────────────────────────


func test_a_wave_outmatched_at_the_front_is_called_off_while_the_army_grows_at_home() -> void:
	# Home production is raising the army's value through the fight, so the global trend
	# reads "winning"; the wave itself stands against two and a half times its strength.
	_sample(0.0, 500.0)
	_sample(8.0, 900.0)
	assert_false(_momentum.is_losing(), "the army as a whole is growing")
	_front(400.0, 1000.0)
	var military: BotMilitary = _military()
	_bot.now = 8.0
	assert_false(military._should_abort_wave(950.0), "barely scratched: the loss gate holds it")
	_bot.now = 9.0
	assert_true(
		military._should_abort_wave(650.0), "a third gone and outgunned at the front — leave"
	)


func test_a_wave_winning_its_front_presses_on_through_a_raid_at_home() -> void:
	# A raid is killing units at home: the army bleeds fast globally. The wave is beating what
	# stands in front of it, and that is the only front the retreat reads.
	_losing()
	assert_true(_momentum.is_losing(), "the army as a whole is bleeding")
	_front(1000.0, 300.0)
	assert_false(_military()._should_abort_wave(650.0))


func test_an_even_front_that_slips_away_is_left_and_one_that_holds_is_not() -> void:
	_sample(0.0, 1000.0)
	_sample(8.0, 1000.0)
	var fixture: FixtureFields = _front(500.0, 500.0)
	var military: BotMilitary = _military()
	_bot.now = 0.0
	assert_false(military._should_abort_wave(650.0), "even and not yet moving")
	_bot.now = 8.0
	assert_false(military._should_abort_wave(650.0), "even and holding")
	_restamp(fixture, 350.0, 500.0)
	_bot.now = 16.0
	assert_true(
		military._should_abort_wave(650.0), "under even and slipping a tenth over the window"
	)


func test_strength_the_other_side_cannot_answer_counts_for_nothing() -> void:
	# Infantry under aircraft it cannot shoot: the wave's own strength at the front is nothing,
	# the enemy's is everything, and the wave leaves at once.
	_front(800.0, 300.0, {OWN_TYPE: [], ENEMY_TYPE: [OWN_TYPE]})
	var under_air: Dictionary = _momentum.front_balance(Vector3.ZERO)
	assert_almost_eq(under_air["own"], 0.0, 0.001)
	assert_almost_eq(under_air["enemy"], 300.0, 0.001)
	assert_true(_military()._should_abort_wave(650.0))
	# A SAM site that cannot touch a ground wave weighs nothing against it, however much it
	# cost; the wave can hurt it, so the wave's own strength stands.
	_momentum.forget_front()
	_front(800.0, 1000.0, {OWN_TYPE: [ENEMY_TYPE], ENEMY_TYPE: []})
	var over_sam: Dictionary = _momentum.front_balance(Vector3.ZERO)
	assert_almost_eq(over_sam["own"], 800.0, 0.001)
	assert_almost_eq(over_sam["enemy"], 0.0, 0.001)
	assert_false(_military()._should_abort_wave(650.0))


func test_without_fields_the_retreat_reads_the_global_trend() -> void:
	# The tier has fields off: the wave behaves as it did before the front existed — the
	# cases above this section are that rule, and this one names the fallback for what it is.
	_losing()
	assert_eq(_bot.fields(), null)
	assert_true(_military()._should_abort_wave(650.0))


func test_launching_and_ending_a_wave_forget_the_last_front() -> void:
	_front(500.0, 500.0)
	var military: BotMilitary = _military()
	military._should_abort_wave(900.0)
	assert_false(_momentum.last_front().is_empty(), "the front is sampled whatever the losses")
	military._end_wave()
	assert_true(_momentum.last_front().is_empty())
