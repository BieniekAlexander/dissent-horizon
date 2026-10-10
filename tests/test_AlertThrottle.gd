extends GutTest

## WHICH RAISED ALERTS A COMMANDER IS SHOWN.
##
## Run with:
## godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_AlertThrottle.gd -gexit
##
## The throttle's two rules — spatial holds with transfer and priority break-through, and keyed
## cooldowns — against alerts built by hand. The radii and times come from AlertCatalog, so
## each test reads them rather than pinning numbers that are expected to be retuned.
## Why: gdd/systems/ux/ui/alerts.md §Throttling.

const UNITS := AlertCatalog.Type.UNITS_ATTACKED
const BASE := AlertCatalog.Type.STRUCTURES_ATTACKED
const BUILT := AlertCatalog.Type.SUPERWEAPON_BUILT
const LAUNCHED := AlertCatalog.Type.SUPERWEAPON_LAUNCHED

var _throttle: AlertThrottle


func before_each() -> void:
	_throttle = AlertThrottle.new()


func _at(a_type: AlertCatalog.Type, a_x: float, a_tick: int) -> Alert:
	return Alert.make(a_type, 1, a_tick).located_at(Vector3(a_x, 0.0, 0.0))


func _keyed(a_type: AlertCatalog.Type, a_key: int, a_tick: int) -> Alert:
	var alert := Alert.make(a_type, 1, a_tick)
	alert.key = a_key
	return alert


func test_the_first_attack_is_shown() -> void:
	assert_true(_throttle.admit(_at(UNITS, 0.0, 0)))


func test_a_second_attack_nearby_is_swallowed() -> void:
	_throttle.admit(_at(UNITS, 0.0, 0))
	var near: float = AlertCatalog.suppress_radius(UNITS) * 0.5
	assert_false(_throttle.admit(_at(UNITS, near, 10)))


func test_an_attack_elsewhere_is_shown() -> void:
	_throttle.admit(_at(UNITS, 0.0, 0))
	var far: float = AlertCatalog.suppress_radius(UNITS) + 1.0
	assert_true(_throttle.admit(_at(UNITS, far, 10)))


func test_the_hold_expires() -> void:
	_throttle.admit(_at(UNITS, 0.0, 0))
	assert_true(_throttle.admit(_at(UNITS, 0.0, AlertCatalog.suppress_ticks(UNITS))))


func test_a_fight_that_keeps_going_in_place_stays_one_alert() -> void:
	# Each nearby hit restarts the hold, so an ongoing fight does not re-announce itself before
	# its longest hold.
	var step: int = AlertCatalog.suppress_ticks(UNITS) / 2
	_throttle.admit(_at(UNITS, 0.0, 0))
	for i: int in range(1, 5):
		assert_false(_throttle.admit(_at(UNITS, 0.0, i * step)), "hit %d" % i)


func test_an_unbroken_fight_is_said_again_after_the_longest_hold() -> void:
	var step: int = AlertCatalog.suppress_ticks(UNITS) / 2
	var limit: int = AlertCatalog.max_hold_ticks(UNITS)
	assert_lt(limit, 1 << 40, "precondition: attacks have a longest hold")
	_throttle.admit(_at(UNITS, 0.0, 0))
	var tick: int = step
	while tick < limit:
		assert_false(_throttle.admit(_at(UNITS, 0.0, tick)), "still the same fight at %d" % tick)
		tick += step
	assert_true(_throttle.admit(_at(UNITS, 0.0, limit)), "announced again")


func test_a_drifting_fight_carries_its_hold_with_it() -> void:
	# Steps shorter than the transfer radius MOVE the hold; the fight walks well past where the
	# first hold's suppression radius would have reached, and is still one alert.
	var step: float = AlertCatalog.transfer_radius(UNITS) * 0.9
	_throttle.admit(_at(UNITS, 0.0, 0))
	for i: int in range(1, 6):
		assert_false(_throttle.admit(_at(UNITS, step * i, i)), "step %d" % i)
	assert_gt(step * 5, AlertCatalog.suppress_radius(UNITS), "the walk outran the first hold")


func test_a_far_swallowed_hit_does_not_move_the_hold() -> void:
	# Inside the suppression radius but beyond transfer: swallowed, and the hold stays put, so
	# the next hit further out is a new place.
	var radius: float = AlertCatalog.suppress_radius(UNITS)
	var beyond_transfer: float = (AlertCatalog.transfer_radius(UNITS) + radius) * 0.5
	_throttle.admit(_at(UNITS, 0.0, 0))
	assert_false(_throttle.admit(_at(UNITS, beyond_transfer, 1)))
	assert_true(_throttle.admit(_at(UNITS, radius + 1.0, 2)))


func test_the_base_breaks_through_a_units_hold() -> void:
	_throttle.admit(_at(UNITS, 0.0, 0))
	assert_true(_throttle.admit(_at(BASE, 1.0, 1)), "higher priority is shown")
	assert_false(_throttle.admit(_at(UNITS, 1.0, 2)), "and its hold now covers units")


func test_units_do_not_break_through_a_base_hold() -> void:
	_throttle.admit(_at(BASE, 0.0, 0))
	assert_false(_throttle.admit(_at(UNITS, 1.0, 1)))


func test_a_keyed_alert_is_said_once_per_hold() -> void:
	assert_true(_throttle.admit(_keyed(BUILT, 7, 0)))
	assert_false(_throttle.admit(_keyed(BUILT, 7, 1)), "the same caster again")
	assert_true(_throttle.admit(_keyed(BUILT, 8, 1)), "another caster")
	assert_true(_throttle.admit(_keyed(BUILT, 7, AlertCatalog.suppress_ticks(BUILT))))


func test_a_zero_hold_admits_everything() -> void:
	assert_eq(AlertCatalog.suppress_ticks(LAUNCHED), 0, "precondition: launches are never held")
	assert_true(_throttle.admit(_keyed(LAUNCHED, 7, 0)))
	assert_true(_throttle.admit(_keyed(LAUNCHED, 7, 0)))


func test_clear_forgets_every_hold() -> void:
	_throttle.admit(_at(UNITS, 0.0, 0))
	_throttle.clear()
	assert_true(_throttle.admit(_at(UNITS, 0.0, 1)))
