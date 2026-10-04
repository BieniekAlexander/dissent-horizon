extends GutTest

## PlaybackSpeed: the engine rate a multiplier maps to, and the invariant the whole design
## rests on — whatever the speed, one engine step is still one base tick of game time.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_PlaybackSpeed.gd -gexit

const BASE: int = 30


func after_each() -> void:
	PlaybackSpeed.reset()


func test_the_range_ends_round_inward_to_whole_engine_rates() -> void:
	assert_eq(PlaybackSpeed.min_engine_ticks(BASE), 8, "0.25 × 30 = 7.5, rounded up")
	assert_eq(PlaybackSpeed.max_engine_ticks(BASE), 120)


func test_a_multiplier_maps_to_the_nearest_engine_rate_within_range() -> void:
	assert_eq(PlaybackSpeed.engine_ticks_for(1.0, BASE), 30)
	assert_eq(PlaybackSpeed.engine_ticks_for(2.0, BASE), 60)
	assert_eq(PlaybackSpeed.engine_ticks_for(0.1, BASE), 8, "clamped to the floor")
	assert_eq(PlaybackSpeed.engine_ticks_for(10.0, BASE), 120, "clamped to the ceiling")


func test_every_speed_keeps_one_engine_step_at_one_game_tick() -> void:
	var game_tick: float = 1.0 / TimeUtils.ticks_per_second()
	for multiplier: float in [0.25, 0.5, 1.0, 3.0, 4.0]:
		PlaybackSpeed.set_multiplier(multiplier)
		assert_almost_eq(
			Engine.time_scale / Engine.physics_ticks_per_second, game_tick, 1e-9, str(multiplier)
		)
	PlaybackSpeed.set_uncapped()
	assert_almost_eq(Engine.time_scale / Engine.physics_ticks_per_second, game_tick, 1e-9, "max")


func test_a_speed_change_leaves_the_game_tick_rate_alone() -> void:
	var before: int = TimeUtils.ticks_per_second()
	PlaybackSpeed.set_multiplier(4.0)
	assert_eq(TimeUtils.ticks_per_second(), before)
	assert_eq(TimeUtils.ticks_from_seconds(1.0), before, "a game second is still base ticks")


func test_uncapped_reads_as_uncapped_and_reset_restores_real_time() -> void:
	PlaybackSpeed.set_uncapped()
	assert_true(PlaybackSpeed.is_uncapped())
	assert_eq(Engine.max_physics_steps_per_frame, PlaybackSpeed.UNCAPPED_STEPS_PER_FRAME)
	PlaybackSpeed.reset()
	assert_false(PlaybackSpeed.is_uncapped())
	assert_eq(PlaybackSpeed.multiplier(), PlaybackSpeed.NORMAL_MULTIPLIER)
	assert_eq(Engine.physics_ticks_per_second, TimeUtils.ticks_per_second())


func test_real_seconds_undoes_the_scale() -> void:
	PlaybackSpeed.set_multiplier(2.0)
	assert_almost_eq(PlaybackSpeed.real_seconds(0.5), 0.25, 1e-9)
