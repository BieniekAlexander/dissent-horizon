extends GutTest

## A SOUND THE WORLD MAKES IS HEARD NEAR THE CAMERA ONLY. WorldSound.screen_gain is the pure rule:
## full on screen, fading linearly to nothing over a margin past each edge. The fog half of
## gain_at is Fog.active_sight_test's, tested with the fog. Why: gdd/systems/ux/README.md
## §World sounds.

const VIEWPORT := Vector2(1000.0, 600.0)


func _margin() -> float:
	return minf(VIEWPORT.x, VIEWPORT.y) * WorldSound.MARGIN_FRACTION


func test_on_screen_is_full_volume() -> void:
	for at: Vector2 in [Vector2(500, 300), Vector2(0, 0), Vector2(1000, 600), Vector2(3, 597)]:
		assert_eq(WorldSound.screen_gain(at, VIEWPORT), 1.0, "%s" % at)


func test_it_fades_over_the_margin() -> void:
	var half: float = WorldSound.screen_gain(Vector2(1000.0 + _margin() * 0.5, 300.0), VIEWPORT)
	assert_almost_eq(half, 0.5, 0.001, "halfway across the margin, half the gain")
	var quarter: float = WorldSound.screen_gain(Vector2(500.0, -_margin() * 0.75), VIEWPORT)
	assert_almost_eq(quarter, 0.25, 0.001, "on every side")


func test_past_the_margin_is_silent() -> void:
	assert_eq(WorldSound.screen_gain(Vector2(1000.0 + _margin() + 1.0, 300.0), VIEWPORT), 0.0)
	assert_eq(WorldSound.screen_gain(Vector2(-5000.0, -5000.0), VIEWPORT), 0.0)


func test_a_corner_fades_by_its_distance_not_per_axis() -> void:
	var off: float = _margin() * 0.5 / sqrt(2.0)
	var corner: float = WorldSound.screen_gain(Vector2(1000.0 + off, 600.0 + off), VIEWPORT)
	assert_almost_eq(corner, 0.5, 0.001)


func test_no_camera_hears_nothing() -> void:
	var lonely := SubViewport.new()
	add_child_autofree(lonely)
	assert_eq(WorldSound.gain_at(Vector3.ZERO, 1, lonely), 0.0, "a headless run is silent")
