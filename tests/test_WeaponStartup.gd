extends GutTest

## A weapon's attack startup: how long a target must be held before the first shot, and why a
## held lock survives a reload. See gdd/systems/combat/weapon-cadence.md §Attack startup.
##
## Frames are passed explicitly, so no physics runs; the weapon is never put in the tree.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_WeaponStartup.gd \
##       -gdir=res://tests/none -gexit

const STARTUP_TICKS: int = 30

var _weapon: Weapon
var _target: Entity
var _other: Entity


func before_each() -> void:
	_weapon = autofree(Weapon.new())
	_weapon.startup_time_ticks = STARTUP_TICKS
	_target = autofree(Entity.new())
	_other = autofree(Entity.new())


## Hold `a_target` on every frame from `a_first` to `a_last` inclusive.
func _hold(a_target: Variant, a_first: int, a_last: int) -> void:
	for frame: int in range(a_first, a_last + 1):
		_weapon.hold_target(a_target, frame)


func test_a_weapon_with_no_startup_is_always_locked() -> void:
	_weapon.startup_time_ticks = 0
	assert_true(_weapon.is_locked_on(_target, 0))
	assert_eq(_weapon.lock_fraction(_target, 0), 1.0)


func test_the_lock_comes_after_the_startup_is_held() -> void:
	_hold(_target, 1, STARTUP_TICKS - 1)
	assert_false(_weapon.is_locked_on(_target, STARTUP_TICKS - 1), "one tick short")
	_hold(_target, STARTUP_TICKS, STARTUP_TICKS)
	assert_true(_weapon.is_locked_on(_target, STARTUP_TICKS))
	assert_false(_weapon.is_locked_on(_other, STARTUP_TICKS), "the lock is on one target")


func test_holding_twice_in_one_frame_counts_once() -> void:
	for _i: int in STARTUP_TICKS:
		_weapon.hold_target(_target, 5)
	assert_false(_weapon.is_locked_on(_target, 5))
	assert_almost_eq(_weapon.lock_fraction(_target, 5), 1.0 / STARTUP_TICKS, 1e-6)


func test_a_lock_kept_held_survives_any_wait() -> void:
	# The reload: the weapon is not ready, but the command keeps holding the target throughout.
	_hold(_target, 1, STARTUP_TICKS + 300)
	assert_true(_weapon.is_locked_on(_target, STARTUP_TICKS + 300),
		"a target held through the reload is fired on again without re-waiting")


func test_a_skipped_frame_breaks_the_lock() -> void:
	_hold(_target, 1, STARTUP_TICKS)
	assert_false(_weapon.is_locked_on(_target, STARTUP_TICKS + 2), "not held last frame")
	_hold(_target, STARTUP_TICKS + 2, STARTUP_TICKS + 2)
	assert_false(_weapon.is_locked_on(_target, STARTUP_TICKS + 2), "the count starts again")


func test_switching_target_starts_again() -> void:
	_hold(_target, 1, STARTUP_TICKS)
	_hold(_other, STARTUP_TICKS + 1, STARTUP_TICKS + 1)
	assert_false(_weapon.is_locked_on(_other, STARTUP_TICKS + 1))
	assert_false(_weapon.is_locked_on(_target, STARTUP_TICKS + 1),
		"returning to the first target is a new startup")


func test_ground_fire_locks_on_a_point() -> void:
	var point := Vector3(3.0, 0.0, 4.0)
	_hold(point, 1, STARTUP_TICKS)
	assert_true(_weapon.is_locked_on(Vector3(3.0, 0.0, 4.0), STARTUP_TICKS))
	assert_false(_weapon.is_locked_on(Vector3(3.0, 0.0, 5.0), STARTUP_TICKS))
	assert_false(_weapon.is_locked_on(_target, STARTUP_TICKS), "a point is not a piece")


func test_a_freed_target_releases_the_lock() -> void:
	var doomed: Entity = Entity.new()
	_hold(doomed, 1, STARTUP_TICKS)
	doomed.free()
	assert_false(_weapon.is_locked_on(_target, STARTUP_TICKS))
