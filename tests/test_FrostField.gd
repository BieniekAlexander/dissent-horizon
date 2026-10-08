extends GutTest

## FrostField's exposure rule, driven a tick at a time with the units it would find inside:
## a unit freezes after `exposure_seconds` in the field, exposure drains back at the same rate
## outside it, the field holds a freeze at full time without mending its ice, and a freeze
## broken inside the field starts that unit's exposure over.
## Rules: gdd/systems/combat/shields.md §Frost fields.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_FrostField.gd -gexit

var _field: FrostField


func before_each() -> void:
	_field = autofree(FrostField.new())
	_field.exposure_seconds = 2.0
	var template: PackedScene = PackedScene.new()
	var freeze: FreezeStatusEffect = FreezeStatusEffect.new()
	template.pack(freeze)
	freeze.free()
	_field.freeze_effect = template


func _unit(a_armour: Defense.ArmourType = Defense.ArmourType.LIGHT) -> Actor:
	var unit := Actor.new()
	var defense := Defense.new()
	defense.name = "Defense"
	defense.armour_type = a_armour
	defense.hp_max = 100.0
	defense.hp = 100.0
	unit.add_child(defense)
	unit.defense = defense
	# Out of the tree, as test_FreezeStatusEffect keeps its units: the effects are driven
	# directly and their own clocks stay still.
	autofree(unit)
	return unit


func _ticks(a_inside: Array[Actor], a_count: int) -> void:
	for _i: int in a_count:
		_field.tick_exposure(a_inside)


func _freeze_on(a_unit: Actor) -> FreezeStatusEffect:
	return FrostField._freeze_on(a_unit)


func test_a_unit_freezes_only_after_the_full_exposure() -> void:
	var unit := _unit()
	_ticks([unit], _field.threshold_ticks() - 1)
	assert_null(_freeze_on(unit), "one tick short")
	_ticks([unit], 1)
	assert_not_null(_freeze_on(unit))


func test_exposure_drains_back_outside_the_field() -> void:
	var unit := _unit()
	var half: int = _field.threshold_ticks() / 2
	_ticks([unit], half)
	_ticks([], half / 2)
	assert_eq(_field.exposure_of(unit), half - half / 2, "drained at the rate it built")
	_ticks([], half)
	assert_eq(_field.exposure_of(unit), 0, "and forgotten once empty")


func test_a_frozen_unit_inside_is_held_at_full_time_without_mending_its_ice() -> void:
	var unit := _unit()
	_ticks([unit], _field.threshold_ticks())
	var freeze := _freeze_on(unit)
	freeze._elapsed = 400
	unit.defense.shield_of(Shield.Type.CRYO).hp = 10.0
	_ticks([unit], 1)
	assert_eq(freeze.duration_ticks - freeze._elapsed, FreezeStatusEffect.freeze_ticks())
	assert_eq(unit.defense.shield_of(Shield.Type.CRYO).hp, 10.0, "the ice is not mended")


func test_ice_broken_inside_the_field_starts_the_exposure_over() -> void:
	var unit := _unit()
	_ticks([unit], _field.threshold_ticks())
	unit.defense.take_damage(100000.0, Damage.Type.LEAD)
	assert_null(_freeze_on(unit), "the ice broke")
	_ticks([unit], 1)
	assert_null(_freeze_on(unit), "not refrozen at once")
	_ticks([unit], _field.threshold_ticks())
	assert_not_null(_freeze_on(unit), "but after a full exposure again")


func test_a_strong_unit_is_never_frozen() -> void:
	var heavy := _unit(Defense.ArmourType.STRONG)
	_ticks([heavy], _field.threshold_ticks() * 2)
	assert_null(_freeze_on(heavy))
