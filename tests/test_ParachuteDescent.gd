extends GutTest

## A unit released in mid-air by an air transport floats down under a canopy and resumes
## ordinary grounded movement where it lands
## (gdd/systems/macroeconomics/sanctions/off-map-abilities.md).
##
## Modelled as a STATE on GROUNDED rather than a fourth Movement.Mode, so the two
## things worth asserting are that the descent behaves (accelerates, caps, lands, calls
## back exactly once) and that it leaves the mode alone — every consumer of Movement.mode
## outside movement.gd already gives the right answer for a soldier under a canopy, and
## would have had to be taught a fourth one otherwise.
##
## The Movement is driven by calling _physics_process directly rather than by running the
## scene tree: the descent branch touches nothing but its own state, so a real tree would
## only make the test slower and its failures less legible.

const DROP_ALTITUDE: float = 6.0
## Generous ceiling on how long a 6-unit descent may take, in physics ticks. At terminal
## speed it is ~90; anything approaching this means the fall has stalled.
const TICK_BUDGET: int = 600
const EPSILON: float = 0.0001


class LandingWatcher:
	var count: int = 0

	func on_landed() -> void:
		count += 1


## A piece's Movement — a ground unit's, or an aircraft's with an Aerial in `a_mode` beside it.
func _movement(a_mode: Movement.Mode = Movement.Mode.GROUNDED) -> Movement:
	# Parented to a Node3D because Movement resolves its owner through get_parent(), even
	# though the descent branch never asks it for anything.
	var host: Node3D = autofree(Node3D.new())
	if a_mode != Movement.Mode.GROUNDED:
		var aerial := Aerial.new()
		aerial.name = "Aerial"
		aerial.mode = a_mode
		host.add_child(aerial)
	var movement: Movement = Movement.new()
	host.add_child(movement)
	return movement


func _tick(a_movement: Movement, a_ticks: int) -> void:
	for _i: int in a_ticks:
		a_movement._physics_process(1.0 / Engine.physics_ticks_per_second)


## Ticks until the descent ends, or TICK_BUDGET if it never does.
func _fall(a_movement: Movement) -> int:
	for elapsed: int in TICK_BUDGET:
		if not a_movement.is_parachuting():
			return elapsed
		a_movement._physics_process(1.0 / Engine.physics_ticks_per_second)
	return TICK_BUDGET


#region The descent
func test_a_released_unit_hangs_at_its_release_altitude() -> void:
	var movement: Movement = _movement()
	movement.begin_parachute_descent(DROP_ALTITUDE, Callable())
	assert_true(movement.is_parachuting(), "should be on its way down")
	assert_almost_eq(movement.descent_altitude(), DROP_ALTITUDE, EPSILON,
		"the height still to fall is what the piece stands above the terrain, so it IS the altitude")


func test_the_descent_starts_from_rest_and_accelerates() -> void:
	var movement: Movement = _movement()
	movement.begin_parachute_descent(DROP_ALTITUDE, Callable())
	var start: float = movement.descent_altitude()
	_tick(movement, 1)
	var first_step: float = start - movement.descent_altitude()
	var before: float = movement.descent_altitude()
	_tick(movement, 1)
	var second_step: float = before - movement.descent_altitude()
	assert_gt(first_step, 0.0, "it should be falling")
	assert_gt(second_step, first_step, "and still picking up speed")


func test_the_descent_never_exceeds_terminal_speed() -> void:
	var movement: Movement = _movement()
	movement.begin_parachute_descent(DROP_ALTITUDE, Callable())
	var cap: float = Movement.PARACHUTE_TERMINAL_SPEED / Engine.physics_ticks_per_second
	var previous: float = movement.descent_altitude()
	while movement.is_parachuting():
		_tick(movement, 1)
		var step: float = previous - movement.descent_altitude()
		assert_lte(step, cap + EPSILON, "a canopy descent is capped, not a free fall")
		previous = movement.descent_altitude()


func test_the_unit_lands_and_stops_parachuting() -> void:
	var movement: Movement = _movement()
	movement.begin_parachute_descent(DROP_ALTITUDE, Callable())
	var elapsed: int = _fall(movement)
	assert_lt(elapsed, TICK_BUDGET, "the descent must terminate")
	assert_false(movement.is_parachuting())
	assert_eq(movement.descent_altitude(), 0.0, "and end flush with the ground, never below it")


func test_the_landing_callback_fires_exactly_once() -> void:
	# It is what takes the canopy away, so a second call would free an already-freed prop
	# and a missing one would leave a parachute hanging over a walking soldier.
	var movement: Movement = _movement()
	var watcher := LandingWatcher.new()
	movement.begin_parachute_descent(DROP_ALTITUDE, watcher.on_landed)
	_fall(movement)
	assert_eq(watcher.count, 1, "one touchdown, one callback")
	_tick(movement, 30)
	assert_eq(watcher.count, 1, "and it does not keep firing once it is down")
#endregion


#region What it does not change
func test_the_mode_is_untouched_throughout() -> void:
	var movement: Movement = _movement()
	movement.begin_parachute_descent(DROP_ALTITUDE, Callable())
	assert_eq(movement.mode, Movement.Mode.GROUNDED, "still grounded on the way down")
	assert_false(movement.is_aerial_mode(),
		"and never aerial — that model would put it on the wrong altitude and target layer")
	_fall(movement)
	assert_eq(movement.mode, Movement.Mode.GROUNDED, "and still grounded once landed")


func test_a_grounded_unit_that_is_not_falling_reports_no_height() -> void:
	var movement: Movement = _movement()
	assert_false(movement.is_parachuting())
	assert_eq(movement.descent_altitude(), 0.0)
#endregion


#region Refusals
func test_an_aerial_unit_is_not_given_a_canopy() -> void:
	# An aircraft tipped out of a transport flies away rather than falling, and a canopy
	# would fight its own altitude model.
	for mode: Movement.Mode in [Movement.Mode.HOVERING, Movement.Mode.FLYING]:
		var movement: Movement = _movement(mode)
		var watcher := LandingWatcher.new()
		movement.begin_parachute_descent(DROP_ALTITUDE, watcher.on_landed)
		assert_false(movement.is_parachuting(), "mode %s should refuse the descent" % mode)
		assert_eq(watcher.count, 1,
			"the callback still fires, so a caller's cleanup is unconditional")


func test_a_zero_altitude_release_lands_immediately() -> void:
	# A transport that somehow releases at ground level: handle the degenerate case rather
	# than forbidding it, and fire the callback so the canopy is still cleaned up.
	var movement: Movement = _movement()
	var watcher := LandingWatcher.new()
	movement.begin_parachute_descent(0.0, watcher.on_landed)
	assert_false(movement.is_parachuting())
	assert_eq(watcher.count, 1)
#endregion
