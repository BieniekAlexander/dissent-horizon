extends GutTest

## Unit tests for Loadout.total_damage() / Weapon.per_shot_damage().
##
## Regression: total_damage() used to sum a removed Weapon.damage field and crashed
## with "Invalid access to property 'damage'". It now sums per_shot_damage() —
## melee_damage for melee weapons, the projectile's base_damage for ranged ones.
##
## Run: godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Loadout.gd
##
## Nodes are built out of tree (never add the Loadout to the SceneTree) so Weapon._ready
## (which asserts on target_mask and needs an AttackRange child) never fires — total_damage
## doesn't depend on either.


func _melee_weapon(dmg: float) -> Weapon:
	var w := Weapon.new()
	w.melee_damage = dmg
	return w


func test_empty_loadout_is_zero() -> void:
	var lo := Loadout.new()
	assert_eq(lo.total_damage(), 0.0)
	lo.free()


func test_single_melee_weapon() -> void:
	var lo := Loadout.new()
	lo.add_child(_melee_weapon(10.0))
	assert_eq(lo.total_damage(), 10.0)
	lo.free()


func test_sums_multiple_weapons() -> void:
	var lo := Loadout.new()
	lo.add_child(_melee_weapon(10.0))
	lo.add_child(_melee_weapon(7.0))
	assert_eq(lo.total_damage(), 17.0, "total_damage sums each weapon's per-shot damage")
	lo.free()


func test_ranged_uses_projectile_base_damage() -> void:
	var scene: PackedScene = load("res://scenes/entities/projectiles/bullet.tscn")
	var probe: Node = scene.instantiate()
	var expected: float = (probe as Projectile).base_damage
	probe.free()

	var w := Weapon.new()
	w.projectile_scene = scene  # ranged: per_shot_damage reads the projectile, not melee_damage
	var lo := Loadout.new()
	lo.add_child(w)
	assert_eq(lo.total_damage(), expected, "ranged weapon contributes its projectile's base_damage")
	lo.free()
