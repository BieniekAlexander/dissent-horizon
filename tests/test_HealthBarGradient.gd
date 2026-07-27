extends GutTest

## HealthBarGradient: the green -> yellow -> red ramp Commandable._on_hp_changed
## applies to the HP bar's fill (as `modulate`, over a white texture).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_HealthBarGradient.gd

## Preloaded (not via class_name) so the test runs even when the global class
## cache hasn't rescanned new files (headless runs don't refresh it).
const HealthBarGradient := preload("res://scripts/rendering/health_bar_gradient.gd")


## Assertions go through HUE, not raw channels: a red -> yellow -> green ramp has
## MORE red at its yellow stop (0.93) than at its red one (0.85), so "red decreases
## with health" is not an invariant of this ramp — the hue sweep is. Hue is 0.0 at
## red, 1/6 at yellow, 1/3 at green.
const _RED_HUE: float = 0.0
const _YELLOW_HUE: float = 1.0 / 6.0
const _GREEN_HUE: float = 1.0 / 3.0


func test_full_health_is_green() -> void:
	assert_almost_eq(HealthBarGradient.color_for(1.0).h, _GREEN_HUE, 0.04)


func test_half_health_is_yellow() -> void:
	assert_almost_eq(HealthBarGradient.color_for(0.5).h, _YELLOW_HUE, 0.04)


func test_empty_is_red() -> void:
	assert_almost_eq(HealthBarGradient.color_for(0.0).h, _RED_HUE, 0.04)


func test_hue_sweeps_monotonically_from_red_to_green() -> void:
	# The bar must never read healthier as it takes damage: hue only ever moves
	# toward green as the fraction rises, with no reversal mid-ramp.
	var previous: float = HealthBarGradient.color_for(0.0).h
	for step in range(1, 21):
		var current: float = HealthBarGradient.color_for(step / 20.0).h
		assert_true(current >= previous - 0.001,
			"hue at %.2f (%.3f) is no redder than the step below it (%.3f)"
				% [step / 20.0, current, previous])
		previous = current
	assert_almost_eq(previous, _GREEN_HUE, 0.04, "ends on green")


func test_stays_saturated_across_the_ramp() -> void:
	# A washed-out midpoint would read as "no color" rather than a warning state.
	for step in range(0, 21):
		assert_gt(HealthBarGradient.color_for(step / 20.0).s, 0.5,
			"fraction %.2f stays saturated" % (step / 20.0))


func test_out_of_range_fractions_clamp() -> void:
	# hp goes negative for a tick before _on_death runs, and nothing guarantees a
	# heal cannot exceed hp_max; both must stay on the ramp rather than sample black.
	assert_eq(HealthBarGradient.color_for(-5.0), HealthBarGradient.color_for(0.0))
	assert_eq(HealthBarGradient.color_for(99.0), HealthBarGradient.color_for(1.0))


func test_colors_are_opaque() -> void:
	# The fill sprite has no alpha of its own; a translucent stop would show the
	# black HPBarBack through the bar.
	for step in range(0, 11):
		assert_almost_eq(HealthBarGradient.color_for(step / 10.0).a, 1.0, 0.001)
