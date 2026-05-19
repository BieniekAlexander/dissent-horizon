class_name WeaponPatternsRegistry

## Maps Entity.Type → the weapon to be used by that entity tpe
static var _by_type: Dictionary[Entity.Type, Array] = {}

## Returns the context for a_type, falling back to the base commandable context
## for any type that isn't specially mapped (generic units, UNDEFINED, etc.).
static func for_type(a_type: Entity.Type) -> Array:
	if _by_type.is_empty():
		_by_type = get_init()
	return _by_type.get(a_type, [])

## Lazy initializer of the registry, because Godot doesn't let you set a Dictionary to constant
static func get_init() -> Dictionary[Entity.Type, Array]:
	return {
		Entity.Type.UNIT_SENTRY: [Pattern.new(func(_e): return true, Weapon.new(null, null, Weapon.AttackType.BALLISTIC))],
		Entity.Type.UNIT_VANGUARD: [Pattern.new(func(_e): return true, Weapon.new(null, null, Weapon.AttackType.LAZER))],
		Entity.Type.STRUCTURE_TURRET: [Pattern.new(func(_e): return true, Weapon.new(null, preload("res://scenes/projectiles/projectile.tscn"), Weapon.AttackType.BALLISTIC))]
	}
