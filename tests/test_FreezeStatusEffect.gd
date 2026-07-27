extends GutTest

## FreezeStatusEffect — the Colonial cryo. A frozen unit can do NOTHING and is one
## armour step tougher while it stands there, and admission is by ARMOUR, not by frame
## (see the effect's own docs for why STRONG and structures are excluded).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_FreezeStatusEffect.gd -gexit

func _unit(a_armour: Defense.ArmourType, a_structure: bool = false) -> Commandable:
	var unit := Commandable.new()
	var defense := Defense.new()
	defense.name = "Defense"
	defense.armour_type = a_armour
	defense.hp_max = 100.0
	unit.add_child(defense)
	unit.defense = defense
	if a_structure:
		unit.add_to_group("structure")
	# Kept OUT of the tree: Commandable._ready wants an Ownership / AvoidanceObstacle rig
	# this test has no use for, and every assertion here is synchronous. StatusEffect's
	# own _physics_process is inert outside the tree, which is exactly what lets
	# apply_to / remove() be driven directly.
	autofree(unit)
	return unit


func _freeze(a_unit: Commandable, a_ticks: int = 450) -> FreezeStatusEffect:
	var effect := FreezeStatusEffect.new()
	effect.duration_ticks = a_ticks
	effect.apply_to(a_unit)
	return effect


# --- Admission ------------------------------------------------------------------

func test_a_light_unit_can_be_frozen() -> void:
	var unit := _unit(Defense.ArmourType.LIGHT)
	var effect := _freeze(unit)
	assert_true(effect.is_active(), "a light unit is a legal target")


func test_a_strong_unit_cannot_be_frozen() -> void:
	# There is no armour step above STRONG, so freezing one would be pure immobilisation
	# with none of the protection — a stun wearing a cryo name.
	var unit := _unit(Defense.ArmourType.STRONG)
	assert_false(FreezeStatusEffect.can_freeze(unit), "STRONG armour is refused")
	var effect := _freeze(unit)
	assert_false(effect.is_active(), "the effect removes itself rather than sitting inert")
	assert_eq(unit.defense.armour_type, Defense.ArmourType.STRONG, "and changes nothing")


func test_a_structure_cannot_be_frozen() -> void:
	# A building has no actions to stop, so a freeze on one would be a pure armour BUFF.
	var structure := _unit(Defense.ArmourType.LIGHT, true)
	assert_false(FreezeStatusEffect.can_freeze(structure))
	assert_false(_freeze(structure).is_active())


func test_can_freeze_is_the_same_question_the_effect_asks() -> void:
	# The sanction filters candidates with the static; the effect re-checks on apply.
	# They must agree, or a click would pick a unit the effect then refuses.
	for armour: Defense.ArmourType in [Defense.ArmourType.LIGHT, Defense.ArmourType.MEDIUM,
			Defense.ArmourType.STRONG]:
		var unit := _unit(armour)
		assert_eq(FreezeStatusEffect.can_freeze(unit), _freeze(unit).is_active(),
			"predicate and apply agree for armour %d" % armour)


# --- Effect ---------------------------------------------------------------------

func test_freezing_raises_armour_one_step() -> void:
	var unit := _unit(Defense.ArmourType.LIGHT)
	_freeze(unit)
	assert_eq(unit.defense.armour_type, Defense.ArmourType.MEDIUM)


func test_medium_becomes_strong() -> void:
	var unit := _unit(Defense.ArmourType.MEDIUM)
	_freeze(unit)
	assert_eq(unit.defense.armour_type, Defense.ArmourType.STRONG,
		"STRONG is the ceiling a freeze can raise something TO, just not FROM")


func test_thawing_restores_the_original_armour() -> void:
	var unit := _unit(Defense.ArmourType.LIGHT)
	var effect := _freeze(unit)
	effect.remove()
	assert_eq(unit.defense.armour_type, Defense.ArmourType.LIGHT)


func test_a_frozen_unit_is_stunned() -> void:
	# The "can take no action" half is not reimplemented here: Freeze extends
	# StunStatusEffect precisely so Commandable.is_stunned() — and the gate at the top of
	# CommandReceiver._process_commands — already covers it.
	var unit := _unit(Defense.ArmourType.LIGHT)
	assert_false(unit.is_stunned(), "not stunned to begin with")
	_freeze(unit)
	assert_true(unit.is_stunned(), "a frozen unit processes no commands")


func test_a_refused_freeze_does_not_stun() -> void:
	var unit := _unit(Defense.ArmourType.STRONG)
	_freeze(unit)
	assert_false(unit.is_stunned(),
		"is_active() must never lie about a unit being frozen — nor must is_stunned()")


func test_refreezing_does_not_stack_armour() -> void:
	# StatusEffect's default REFRESH mode: a second application refreshes the timer and
	# discards itself. Without that, two Freezes would walk a light unit up to STRONG and
	# only give one step back on thaw.
	var unit := _unit(Defense.ArmourType.LIGHT)
	var first := _freeze(unit)
	_freeze(unit)
	assert_eq(unit.defense.armour_type, Defense.ArmourType.MEDIUM, "still one step up")
	first.remove()
	assert_eq(unit.defense.armour_type, Defense.ArmourType.LIGHT, "and one step back down")


func test_the_default_duration_is_fifteen_seconds() -> void:
	# 30 physics ticks per second; the doc specifies 15 seconds.
	assert_eq(FreezeStatusEffect.DEFAULT_FREEZE_TICKS, 450)
	assert_eq(FreezeStatusEffect.new().duration_ticks, 450,
		"a freshly constructed freeze already carries it")
