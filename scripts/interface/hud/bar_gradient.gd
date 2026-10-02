class_name BarGradient
extends RefCounted

## Pure maths for a persistent resource bar's fill BEYOND the colour ramp itself — a
## saturation boost layered on top of a gradient sample, and where a segmented fill's divider
## lines fall. No Control here — every function is a value in, a value out, so the bar's look
## can be asserted without a live engine (see tests/test_BarGradient.gd).
##
## The ramp itself is a plain `Gradient` resource held by the bar that needs one (EnergyBar),
## the same idiom HealthBarGradient already uses for HP-bar fill — a second hand-rolled
## interpolator here would be the sibling §1.3 warns against rather than a second instance of
## the one Godot already gives a colour ramp.


## `a_color` with its HSV saturation raised toward 1.0 as `a_frac` (already the fraction used
## to pick `a_color` off the gradient) rises from 0 to 1 — the "generally increase in
## saturation" half of the lithium-pond idiom, layered on top of the hue lerp above rather
## than folded into it, so the two can be reasoned about (and tested) separately.
static func with_saturation_ramp(
	a_color: Color, a_frac: float, a_min_gain: float = 0.0, a_max_gain: float = 0.35
) -> Color:
	var frac: float = clampf(a_frac, 0.0, 1.0)
	var gain: float = lerpf(a_min_gain, a_max_gain, frac)
	var boosted := Color.from_hsv(
		a_color.h, clampf(a_color.s + gain, 0.0, 1.0), a_color.v, a_color.a
	)
	return boosted


## The fractions (0, 1] of `a_capacity` at which a segmented fill's divider lines fall, for a
## fill made of chunks of `a_segment_size` — e.g. capacity 500, segment 125 → [0.25, 0.5,
## 0.75, 1.0]. Empty when `a_segment_size` is not a positive number smaller than the capacity
## — a bar with one provider (or none) has nothing to divide.
static func segment_fractions(a_capacity: float, a_segment_size: float) -> PackedFloat32Array:
	var fractions := PackedFloat32Array()
	if a_capacity <= 0.0 or a_segment_size <= 0.0 or a_segment_size >= a_capacity:
		return fractions
	var boundary: float = a_segment_size
	while boundary < a_capacity - 0.0001:
		fractions.append(boundary / a_capacity)
		boundary += a_segment_size
	fractions.append(1.0)
	return fractions
