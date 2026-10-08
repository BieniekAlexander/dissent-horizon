extends GutTest

## The narrow modifier on the command side: which single actor an Alt-modified order goes
## to (OrderDispatcher.narrowed_index).
##
## The rule is the NEAREST IDLE actor to the target, falling back to the nearest outright
## when none is idle. Holding broaden (Ctrl) as well drops the idle preference — the same
## axis broaden means on the selector side, so the two compose rather than cancelling.
##
## Exercised through the static, node-free form: `narrowed_index` takes
## `[xz_position, is_idle]` pairs, which are the only things the choice depends on. Its
## wrapper `_narrowed_actors` reads those off live Commandables and additionally decides
## that Train is never narrowed and that a lone actor is returned untouched; both need a
## live entity (an out-of-tree Node3D has no usable global_position, and an in-tree bare
## Commandable push_errors its way through _ready) and are not covered here.
##
## Run with:
## godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_NarrowedAssignment.gd -gexit

const IDLE: bool = true
const BUSY: bool = false

const PREFER_IDLE: bool = true
const NEAREST_ONLY: bool = false

const ORIGIN: Vector2 = Vector2.ZERO


func _at(a_x: float, a_z: float, a_idle: bool) -> Array:
	return [Vector2(a_x, a_z), a_idle]


# --- nearest idle (narrow alone) ----------------------------------------------


func test_the_nearest_idle_actor_takes_the_order() -> void:
	var far := _at(20, 20, IDLE)
	var near := _at(1, 1, IDLE)
	assert_eq(OrderDispatcher.narrowed_index([far, near], ORIGIN, PREFER_IDLE), 1)


func test_an_idle_actor_beats_a_nearer_busy_one() -> void:
	# The case narrowing exists to serve: leave the unit that is already working on
	# something, and send the one with nothing to do.
	var busy_and_near := _at(1, 1, BUSY)
	var idle_but_far := _at(20, 20, IDLE)
	assert_eq(OrderDispatcher.narrowed_index([busy_and_near, idle_but_far], ORIGIN, PREFER_IDLE), 1)


func test_it_falls_back_to_the_nearest_when_nothing_is_idle() -> void:
	# Never a refusal: with every candidate busy, the order still goes somewhere.
	var far := _at(20, 20, BUSY)
	var near := _at(1, 1, BUSY)
	assert_eq(OrderDispatcher.narrowed_index([far, near], ORIGIN, PREFER_IDLE), 1)


func test_distance_is_measured_to_the_order_not_to_the_group() -> void:
	# The actor closest to where the player clicked, not the one closest to the others.
	var candidates: Array = [_at(0, 0, IDLE), _at(9, 9, IDLE)]
	assert_eq(OrderDispatcher.narrowed_index(candidates, Vector2(10, 10), PREFER_IDLE), 1)


func test_ties_go_to_the_earlier_candidate() -> void:
	# Equal distance and equal idleness: the strict `<` keeps the first, so a repeated
	# narrowed order lands on the same actor rather than oscillating between two.
	var candidates: Array = [_at(5, 0, IDLE), _at(-5, 0, IDLE)]
	assert_eq(OrderDispatcher.narrowed_index(candidates, ORIGIN, PREFER_IDLE), 0)


# --- narrow + broaden ---------------------------------------------------------


func test_dropping_the_idle_preference_takes_the_nearest_outright() -> void:
	var busy_and_near := _at(1, 1, BUSY)
	var idle_but_far := _at(20, 20, IDLE)
	assert_eq(
		OrderDispatcher.narrowed_index([busy_and_near, idle_but_far], ORIGIN, NEAREST_ONLY),
		0,
		"the nearest actor, whether or not it is idle"
	)


func test_dropping_the_idle_preference_changes_nothing_when_all_are_idle() -> void:
	var candidates: Array = [_at(20, 20, IDLE), _at(1, 1, IDLE)]
	assert_eq(OrderDispatcher.narrowed_index(candidates, ORIGIN, NEAREST_ONLY), 1)


# --- degenerate sets ----------------------------------------------------------


func test_a_single_candidate_is_chosen_whatever_it_is_doing() -> void:
	assert_eq(OrderDispatcher.narrowed_index([_at(500, 500, BUSY)], ORIGIN, PREFER_IDLE), 0)


func test_an_empty_set_chooses_nothing() -> void:
	assert_eq(
		OrderDispatcher.narrowed_index([], ORIGIN, PREFER_IDLE),
		-1,
		"-1 is what makes the caller hand back the original selection untouched"
	)
