class_name Weapon
extends Node3D

## A weapon that a commandable's Loadout can hold. Lives in the scene tree as
## a child of an Loadout node, with an AttackRange CollisionShape3D child that
## defines its reach. Every weapon has one — short-reach "melee" weapons simply
## use an AttackRange only slightly larger than the wielder's body shape.

#region Constants
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
			Pattern.new(func(c: Commandable): return c.defense != null and c.defense.armor == Defense.Armor.LIGHT, 1),
			Pattern.new(func(c: Commandable): return c.defense != null and c.defense.armor == Defense.Armor.HEAVY, .1)
	],
	AttackType.LAZER: [
			Pattern.new(func(c: Commandable): return c.defense != null and c.defense.armor == Defense.Armor.LIGHT, .25),
			Pattern.new(func(c: Commandable): return c.defense != null and c.defense.armor == Defense.Armor.HEAVY, 1)
	]
}
#endregion

#region Properties
@export var attack_type: AttackType = AttackType.BALLISTIC
@export var damage: float = 10
@export var attack_duration: int = 10
@export var attacks_grounded: bool = true # TODO refactor, make these checks more elegantly
@export var attacks_aerial: bool = false
## Projectile scene to launch on fire; null = instant damage applied directly.
@export var packed_scene: PackedScene
@onready var attack_range_shape: CollisionShape3D = $AttackRange
@onready var _visualizer: Node = _find_visualizer()
#endregion

#region Private helpers
func _find_visualizer() -> Node:
	for c in get_children():
		if c.has_method("show_beam"):
			return c
	return null
#endregion

#region Public API
## Returns true when this weapon can target the given entity.
## By default any Entity is a valid target; override per-weapon for
## type-specific rules (e.g. cannot target flying units).
func can_target(_target: Entity) -> bool:
	# TODO refactor, this is very very hacked
	if _target.movement==null: return true
	return (
		attacks_aerial and _target.movement.mode in [Movement.Mode.FLYING, Movement.Mode.HOVERING]
	) or (
		attacks_grounded and _target.movement.mode == Movement.Mode.GROUNDED_DIRECT
	)

func fire(a_owner: Commandable, a_target: Entity) -> void:
	var vet_level: int = a_owner.veterancy.level if a_owner.veterancy != null else 0
	var effective_damage: float = damage + 0.2 * float(vet_level)
	if packed_scene != null:
		var projectile: = packed_scene.instantiate()
		projectile.initialize(a_owner.map, a_owner.commander)
		projectile.global_position = global_position
		projectile.initialize_projectile(a_owner, a_target, effective_damage)
	else:
		a_target.receive_damage(
			a_owner,
			Pattern.eval(damage_multiplier_patterns[attack_type], a_target) * effective_damage
		)
	if _visualizer:
		_visualizer.show_beam(a_owner, a_target)
#endregion
