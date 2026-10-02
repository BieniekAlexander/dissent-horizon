extends GutTest

## The pure gradient/segment maths the persistent resource bars draw against — see
## gdd/systems/ux/ui/economy-bars.md and scripts/interface/hud/bar_gradient.gd.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_BarGradient.gd -gexit

# --- with_saturation_ramp --------------------------------------------------------


func test_no_gain_at_frac_zero_leaves_saturation_unchanged() -> void:
	var muted := Color.from_hsv(0.5, 0.4, 0.8)
	var boosted: Color = BarGradient.with_saturation_ramp(muted, 0.0)
	assert_almost_eq(boosted.s, muted.s, 0.001)


func test_saturation_rises_toward_full_frac() -> void:
	var muted := Color.from_hsv(0.5, 0.4, 0.8)
	var at_start: Color = BarGradient.with_saturation_ramp(muted, 0.0)
	var at_end: Color = BarGradient.with_saturation_ramp(muted, 1.0)
	assert_gt(at_end.s, at_start.s, "the far end of the fill reads more saturated")


func test_saturation_never_exceeds_one() -> void:
	var already_saturated := Color.from_hsv(0.5, 0.95, 0.8)
	var boosted: Color = BarGradient.with_saturation_ramp(already_saturated, 1.0)
	assert_lte(boosted.s, 1.0)


# --- segment_fractions ------------------------------------------------------------


func test_capacity_divides_evenly_into_segments() -> void:
	var fractions: PackedFloat32Array = BarGradient.segment_fractions(500.0, 125.0)
	assert_eq(fractions.size(), 4)
	assert_almost_eq(fractions[0], 0.25, 0.001)
	assert_almost_eq(fractions[3], 1.0, 0.001)


func test_a_segment_bigger_than_capacity_divides_nothing() -> void:
	assert_eq(BarGradient.segment_fractions(500.0, 600.0).size(), 0)


func test_no_segment_size_divides_nothing() -> void:
	assert_eq(BarGradient.segment_fractions(500.0, 0.0).size(), 0)


func test_a_segment_equal_to_capacity_divides_nothing() -> void:
	# One provider IS the whole bar — nothing to divide.
	assert_eq(BarGradient.segment_fractions(500.0, 500.0).size(), 0)
