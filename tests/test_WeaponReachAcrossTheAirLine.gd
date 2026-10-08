extends GutTest

## A WEAPON WITH NO REACH AGAINST THAT SIDE IS NOT IN RANGE — it does not crash.
##
## `Weapon.get_range_for_target` returns null when the weapon carries no range shape for the
## side the target is on (a ground-only rifle asked about an air target). That null is an
## answer, and `SU.is_weapon_in_range_at` used to dereference it.
##
## It is reachable despite `Loadout.weapon_for_target` filtering on `can_target`, because the
## two questions read different sources: `can_target` reads the Hurtbox LAYER, latched by
## `Entity.refresh_targetable_altitude` at the end of a tick, while `get_range_for_target`
## reads LIVE altitude. For the one tick a piece spends crossing `AIR_TARGET_ALTITUDE` they
## disagree — which is the state every test below sets up deliberately.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gexit \
##     -gtest=res://tests/test_WeaponReachAcrossTheAirLine.gd

## Loaded INSIDE the tests, never preloaded at file scope — see CLAUDE.md on the Tool
## registry a file-scope preload poisons.
const RECRUIT: Dictionary = {"speed": 2.0, "vision": 8.0, "weapon": {"ground": 6.0}}


func _commander(a_id: int) -> Commander:
	var c := Commander.new()
	c.id = a_id
	add_child_autofree(c)
	return c


func _entity(a_options: Dictionary, a_commander: Commander) -> Actor:
	var e: Actor = FakePieces.unit(a_options)
	add_child_autofree(e)
	e.ownership.commander = a_commander
	return e


## A recruit's rifle: ground-only, so it has no AIR range shape at all.
func _ground_only_weapon(a_shooter: Actor) -> Weapon:
	var weapon: Weapon = a_shooter.weapon_inventory.get_weapons()[0] as Weapon
	assert_eq(
		weapon.target_mask & CollisionLayers.Mask.TARGETABLE_AIR,
		0,
		"fixture: the rifle cannot hit air at all"
	)
	return weapon


## Lift `a_unit` above the air line WITHOUT re-filing its targetable layer — the exact state
## the piece is in for one tick while it crosses, and the state that crashed.
func _lift_without_refiling(a_unit: Actor) -> void:
	a_unit.movement.begin_parachute_descent(Aerial.AERIAL_HEIGHT, Callable())


func test_the_layer_and_the_altitude_disagree_for_a_tick() -> void:
	# The mechanism the other two tests rely on. If this ever stops holding — because the
	# layer is refreshed the moment the height is written — the crash below becomes
	# unreachable and these tests are pinning a state that cannot occur.
	var unit: Actor = _entity(RECRUIT, _commander(1))
	_lift_without_refiling(unit)

	assert_true(unit.is_air_target(), "by altitude it is already an air target")
	assert_true(
		(unit.targetable_layers() & CollisionLayers.Mask.TARGETABLE_GROUND) != 0,
		"but its latched layer still says ground, so a ground-only weapon still accepts it"
	)


func test_a_ground_only_weapon_has_no_reach_against_an_air_target() -> void:
	var cmd: Commander = _commander(1)
	var shooter: Actor = _entity(RECRUIT, cmd)
	var victim: Actor = _entity(RECRUIT, cmd)
	var weapon: Weapon = _ground_only_weapon(shooter)
	assert_not_null(
		weapon.get_range_for_target(victim), "precondition: it reaches it on the ground"
	)

	_lift_without_refiling(victim)

	assert_null(
		weapon.get_range_for_target(victim),
		"lifted over the line there is no shape to reach it with — null is the answer"
	)


func test_asking_that_weapon_for_range_reports_out_of_range_rather_than_erroring() -> void:
	var cmd: Commander = _commander(1)
	var shooter: Actor = _entity(RECRUIT, cmd)
	var victim: Actor = _entity(RECRUIT, cmd)
	victim.global_position = shooter.global_position
	var weapon: Weapon = _ground_only_weapon(shooter)

	_lift_without_refiling(victim)

	# Point-blank: only the missing air shape can make this false, so a passing assert here
	# is the guard working rather than the target merely being far away.
	assert_false(
		SU.is_in_attack_range(weapon, shooter, victim),
		"no reach against that side means not in range"
	)
