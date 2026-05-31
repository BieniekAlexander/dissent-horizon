class_name Weapon
extends Node

## A weapon that a commandable's Inventory can hold. Lives in the scene tree as
## a child of an Inventory node, with an optional AttackRange CollisionShape3D
## child that defines its reach.

enum AttackType {
	BALLISTIC,
	TOXIN,
	FIRE,
	ELECTRICITY,
	SIEGE,
	LAZER,
	EXPLOSIVE
}

static var damage_multiplier_patterns: Dictionary = {
	AttackType.BALLISTIC: [
			Pattern.new(func(c: Commandable): return c.armor==Commandable.Armor.LIGHT, 1),
			Pattern.new(func(c: Commandable): return c.armor==Commandable.Armor.HEAVY, .1)
	],
	AttackType.LAZER: [
			Pattern.new(func(c: Commandable): return c.armor==Commandable.Armor.LIGHT, .25),
			Pattern.new(func(c: Commandable): return c.armor==Commandable.Armor.HEAVY, 1)
	]
}

## COMBAT
@export var attack_type: AttackType = AttackType.BALLISTIC
## Projectile scene to launch on fire; null = instant damage applied directly.
@export var packed_scene: PackedScene
## Maximum XZ distance (centre-to-centre) at which this weapon can strike when
## it has no AttackRange child (i.e. it is a melee weapon). Ignored for ranged
## weapons that have an AttackRange child.
@export var melee_range: float = 1.5

@onready var attack_range_shape: CollisionShape3D = get_node_or_null("AttackRange")

## Returns true when this weapon can target the given entity.
## By default any Entity is a valid target; override per-weapon for
## type-specific rules (e.g. cannot target flying units).
func can_target(_target: Entity) -> bool:
	return true

func fire(a_owner: Commandable, a_target: Entity) -> void:
	if packed_scene != null:
		var projectile: = packed_scene.instantiate()
		projectile.initialize(a_owner.map, a_owner.commander)
		projectile.initialize_projectile(a_owner, a_target)
	else:
		a_target.receive_damage(
			a_owner,
			Pattern.eval(damage_multiplier_patterns[attack_type], a_target) * a_owner.DAMAGE
		)
