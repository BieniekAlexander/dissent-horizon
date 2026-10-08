extends GutTest

## FreezeStatusEffect — the Colonial cryo. A frozen piece can do NOTHING, and a CRYO shield
## of ice takes damage before it does; breaking the ice ends the freeze. STRONG pieces cannot
## be frozen. Rules: gdd/systems/combat/shields.md §Freeze.
##
## Run with:
## godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_FreezeStatusEffect.gd -gexit


func _unit(a_armour: Defense.ArmourType, a_structure: bool = false) -> Actor:
	var unit := Actor.new()
	var defense := Defense.new()
	defense.name = "Defense"
	defense.armour_type = a_armour
	defense.hp_max = 100.0
	unit.add_child(defense)
	unit.defense = defense
	if a_structure:
		unit.add_to_group("structure")
	# Kept OUT of the tree: Actor._ready wants an Ownership / AvoidanceObstacle rig
	# this test has no use for, and every assertion here is synchronous. StatusEffect's
	# own _physics_process is inert outside the tree, which is exactly what lets
	# apply_to / remove() be driven directly.
	autofree(unit)
	return unit


func _freeze(a_unit: Actor, a_ticks: int = 450) -> FreezeStatusEffect:
	var effect := FreezeStatusEffect.new()
	effect.duration_ticks = a_ticks
	effect.apply_to(a_unit)
	return effect


# --- Admission ------------------------------------------------------------------


func test_light_and_medium_units_can_be_frozen() -> void:
	for armour: Defense.ArmourType in [Defense.ArmourType.LIGHT, Defense.ArmourType.MEDIUM]:
		assert_true(_freeze(_unit(armour)).is_active(), "armour %d is a legal target" % armour)


func test_a_strong_unit_cannot_be_frozen() -> void:
	var unit := _unit(Defense.ArmourType.STRONG)
	assert_false(FreezeStatusEffect.can_freeze(unit), "STRONG armour is refused")
	var effect := _freeze(unit)
	assert_false(effect.is_active(), "the effect removes itself rather than sitting inert")
	assert_null(unit.defense.shield_of(Shield.Type.CRYO), "and leaves no ice behind")


func test_a_structure_can_be_frozen() -> void:
	var structure := _unit(Defense.ArmourType.MEDIUM, true)
	assert_true(FreezeStatusEffect.can_freeze(structure))
	assert_true(_freeze(structure).is_active())


func test_can_freeze_is_the_same_question_the_effect_asks() -> void:
	# The sanction filters candidates with the static; the effect re-checks on apply.
	# They must agree, or a click would pick a unit the effect then refuses.
	for armour: Defense.ArmourType in [
		Defense.ArmourType.LIGHT, Defense.ArmourType.MEDIUM, Defense.ArmourType.STRONG
	]:
		var unit := _unit(armour)
		assert_eq(
			FreezeStatusEffect.can_freeze(unit),
			_freeze(unit).is_active(),
			"predicate and apply agree for armour %d" % armour
		)


# --- The ice --------------------------------------------------------------------


func test_freezing_stands_a_strong_cryo_shield_over_the_host() -> void:
	var unit := _unit(Defense.ArmourType.LIGHT)
	var effect := _freeze(unit)
	var ice: Shield = unit.defense.shield_of(Shield.Type.CRYO)
	assert_not_null(ice)
	assert_eq(ice.hp, effect.shield_hp)
	assert_eq(ice.armour_over(unit.defense), Defense.ArmourType.STRONG, "the ice is STRONG")
	assert_eq(ice.frame_over(unit.defense), unit.defense.frame_type, "its frame falls through")
	assert_eq(
		unit.defense.armour_type, Defense.ArmourType.LIGHT, "the host's own armour is untouched"
	)


func test_thawing_takes_the_ice_away() -> void:
	var unit := _unit(Defense.ArmourType.LIGHT)
	_freeze(unit).remove()
	assert_null(unit.defense.shield_of(Shield.Type.CRYO))


func test_breaking_the_ice_ends_the_freeze() -> void:
	var unit := _unit(Defense.ArmourType.LIGHT)
	var effect := _freeze(unit)
	unit.defense.take_damage(100000.0, Damage.Type.LEAD)
	assert_false(effect.is_active(), "the freeze ends with its shield")
	assert_false(unit.is_stunned(), "and the unit can act again")


func test_a_frozen_unit_is_stunned() -> void:
	# The "can take no action" half is not reimplemented here: Freeze extends
	# StunStatusEffect precisely so Actor.is_stunned() — and the gate at the top of
	# CommandReceiver._process_commands — already covers it.
	var unit := _unit(Defense.ArmourType.LIGHT)
	assert_false(unit.is_stunned(), "not stunned to begin with")
	_freeze(unit)
	assert_true(unit.is_stunned(), "a frozen unit processes no commands")


func test_a_refused_freeze_does_not_stun() -> void:
	var unit := _unit(Defense.ArmourType.STRONG)
	_freeze(unit)
	assert_false(
		unit.is_stunned(),
		"is_active() must never lie about a unit being frozen — nor must is_stunned()"
	)


# --- Reapplying -----------------------------------------------------------------


func test_refreezing_takes_the_larger_ice_and_the_longer_time() -> void:
	var unit := _unit(Defense.ArmourType.LIGHT)
	var first := _freeze(unit, 36)  # 1.2 s
	unit.defense.shield_of(Shield.Type.CRYO).hp = 100.0
	var second := FreezeStatusEffect.new()
	second.duration_ticks = 30  # 1.0 s
	second.shield_hp = 150.0
	second.apply_to(unit)
	assert_eq(unit.defense.shield_of(Shield.Type.CRYO).hp, 150.0, "the larger hit points")
	assert_eq(first.duration_ticks - first._elapsed, 36, "the longer remaining time")


func test_refreezing_never_shrinks_the_ice() -> void:
	var unit := _unit(Defense.ArmourType.LIGHT)
	_freeze(unit)
	var weak := FreezeStatusEffect.new()
	weak.shield_hp = 10.0
	weak.apply_to(unit)
	assert_eq(unit.defense.shield_of(Shield.Type.CRYO).hp, 150.0)


func test_holding_a_freeze_extends_its_time_but_not_its_ice() -> void:
	var unit := _unit(Defense.ArmourType.LIGHT)
	var effect := _freeze(unit, 30)
	unit.defense.shield_of(Shield.Type.CRYO).hp = 40.0
	effect.hold_for(450)
	assert_eq(effect.duration_ticks - effect._elapsed, 450)
	assert_eq(unit.defense.shield_of(Shield.Type.CRYO).hp, 40.0, "a hold mends nothing")


func test_every_freeze_lasts_the_one_constant() -> void:
	assert_eq(FreezeStatusEffect.freeze_ticks(), TimeUtils.ticks_from_seconds(10.0))
	assert_eq(
		FreezeStatusEffect.new().duration_ticks,
		FreezeStatusEffect.freeze_ticks(),
		"a freshly constructed freeze already carries it"
	)
