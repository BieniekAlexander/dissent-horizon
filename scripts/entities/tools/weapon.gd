# Defines the properties of the thing that a unit uses to attack a target,
# e.g. if the weapon can shoot up, the projetile it produces, etc.
class_name Weapon
extends Tool

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
var attack_type: AttackType

func fire(a_owner: Commandable, a_target: Entity) -> void:
	if packed_scene!=null:
		var projectile:  = packed_scene.instantiate()
		projectile.initialize(a_owner.map, a_owner.commander)
		projectile.initialize_projectile(a_owner, a_target)
	else:
		a_target.receive_damage(
			a_owner,
			Pattern.eval(damage_multiplier_patterns[attack_type], a_target)*a_owner.DAMAGE
		)


## NODE
func _init(a_script: Script, a_projectile: PackedScene, an_attack_type: AttackType) -> void:
	super(a_script, a_projectile)
	attack_type = an_attack_type
