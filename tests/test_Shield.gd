extends GutTest

## Shields over a Defense: damage meets each shield before hit points, each layer resists on
## its own armour and frame, and what a shield cannot hold passes on as unabsorbed BASE
## damage. Multipliers are authored content, so they are read from DamageTable, never pinned.
## Rules: gdd/systems/combat/shields.md §Shields.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Shield.gd -gexit

const HP: float = 1000.0
const TYPE: Damage.Type = Damage.Type.LEAD


func _defense(
	a_armour: Defense.ArmourType = Defense.ArmourType.LIGHT,
	a_frame: Defense.FrameType = Defense.FrameType.BIO
) -> Defense:
	var defense: Defense = autofree(Defense.new())
	defense.armour_type = a_armour
	defense.frame_type = a_frame
	defense.hp_max = HP
	defense.hp = HP
	return defense


func _strong_ice(a_hp: float) -> Shield:
	return Shield.new(Shield.Type.CRYO, a_hp, Defense.ArmourType.STRONG)


func _factor(a_armour: Defense.ArmourType, a_frame: Defense.FrameType) -> float:
	return DamageTable.multiplier(TYPE, a_armour, a_frame)


func test_without_a_shield_damage_meets_hit_points() -> void:
	var defense := _defense()
	var dealt: float = defense.take_damage(10.0, TYPE)
	var expected: float = 10.0 * _factor(Defense.ArmourType.LIGHT, Defense.FrameType.BIO)
	assert_almost_eq(dealt, expected, 0.001)
	assert_almost_eq(defense.hp, HP - expected, 0.001)


func test_a_shield_takes_damage_first_at_its_own_armour() -> void:
	var defense := _defense()
	defense.apply_shield(_strong_ice(150.0))
	defense.take_damage(10.0, TYPE)
	var ice_factor: float = _factor(Defense.ArmourType.STRONG, Defense.FrameType.BIO)
	assert_eq(defense.hp, HP, "hit points untouched while the shield holds")
	assert_almost_eq(defense.shield_of(Shield.Type.CRYO).hp, 150.0 - 10.0 * ice_factor, 0.001)


func test_overflow_passes_on_as_the_unabsorbed_base() -> void:
	var defense := _defense()
	defense.apply_shield(_strong_ice(5.0))
	var ice_factor: float = _factor(Defense.ArmourType.STRONG, Defense.FrameType.BIO)
	var host_factor: float = _factor(Defense.ArmourType.LIGHT, Defense.FrameType.BIO)
	var base: float = 100.0
	var dealt: float = defense.take_damage(base, TYPE)
	var leftover_base: float = base - 5.0 / ice_factor
	assert_almost_eq(defense.hp, HP - leftover_base * host_factor, 0.001)
	assert_almost_eq(dealt, 5.0 + leftover_base * host_factor, 0.001)
	assert_null(defense.shield_of(Shield.Type.CRYO), "a broken shield leaves")


func test_breaking_a_shield_is_announced() -> void:
	var defense := _defense()
	defense.apply_shield(_strong_ice(1.0))
	watch_signals(defense)
	defense.take_damage(1000.0, TYPE)
	assert_signal_emitted_with_parameters(defense, "shield_broken", [Shield.Type.CRYO])


func test_a_shield_without_its_own_classes_falls_through_to_the_host() -> void:
	var defense := _defense(Defense.ArmourType.MEDIUM, Defense.FrameType.MECH)
	var shield := Shield.new(Shield.Type.CRYO, 10.0)
	assert_eq(shield.armour_over(defense), Defense.ArmourType.MEDIUM)
	assert_eq(shield.frame_over(defense), Defense.FrameType.MECH)


func test_one_shield_per_type_keeping_the_larger_hit_points() -> void:
	var defense := _defense()
	defense.apply_shield(_strong_ice(100.0))
	defense.apply_shield(_strong_ice(150.0))
	assert_eq(defense.shield_of(Shield.Type.CRYO).hp, 150.0)
	defense.apply_shield(_strong_ice(20.0))
	assert_eq(defense.shield_of(Shield.Type.CRYO).hp, 150.0, "a weaker one never lowers it")
	assert_eq(defense.shield_hp(), 150.0, "still one shield, not two")
