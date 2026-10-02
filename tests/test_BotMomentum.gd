extends GutTest

## Unit tests for BotMomentum — the bot's "am I winning or losing" signal — and for the
## army-level retreat that is its first consumer (BotMilitary._should_abort_wave).
##
## A FakeBot supplies the two facts momentum reads, because both come from the world: a
## bare Bot reports seconds_elapsed() == 0 with no scenario, and a real army cannot be
## stood up in a unit test. Overriding the two senses is the whole fixture.


## A Bot whose clock and army value the test drives directly.
class FakeBot:
	extends Bot
	var now: float = 0.0
	var army_value: float = 0.0

	func seconds_elapsed() -> float:
		return now

	func army_resource_value() -> float:
		return army_value


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
