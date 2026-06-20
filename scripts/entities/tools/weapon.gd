@tool
class_name Weapon
extends Node3D

## A weapon that a commandable's Loadout can hold. Lives in the scene tree as
## a child of an Loadout node, with an AttackRange CollisionShape3D child that
## defines its reach. Every weapon has one — short-reach "melee" weapons simply
## use an AttackRange only slightly larger than the wielder's body shape.

#region Properties
#region ammo
@export var split_time: int = 10	## time between attacks
@export var reload_time: int = 10	## time between full reload
var _split_timer: int = 0			## time until next attack ready
var _reload_timer: int = 0			## time until reload ammo
@export var clip_size: int = 1		## amount of ammo between reloads
var _ammo: int = 1					## current amount of ammo left, before reload timer finishes
#endregion

#region projectile evaluation
@onready var attack_range_shape: CollisionShape3D = $AttackRange
@export var projectile_scene: PackedScene		## projectile produced when firing (which may have its own damage evaluation)
@export var melee_damage: float = 10
@export var melee_damage_type: Damage.Type = Damage.Type.LEAD
#endregion

#region attack conditions
@export_flags_3d_physics var target_mask: int = CollisionLayers.Mask.TARGETABLE_GROUND ## Indicates which collision-layer-based targeting the weapon can hit
#endregion

#endregion

#region tool
func _validate_property(property: Dictionary) -> void:
	match property.name:
		"projectile": property.usage |= PROPERTY_USAGE_UPDATE_ALL_IF_MODIFIED
		"clip_size": property.usage |= PROPERTY_USAGE_UPDATE_ALL_IF_MODIFIED
		"melee_damage":
			if projectile_scene!=null:
				melee_damage = 0.
				property.usage = property.usage | PROPERTY_USAGE_READ_ONLY
			else:
				property.usage = property.usage & ~PROPERTY_USAGE_READ_ONLY
		"melee_damage_type":
			melee_damage_type = Damage.Type.LEAD
			property.usage = (
				property.usage & ~PROPERTY_USAGE_READ_ONLY
				if projectile_scene==null
				else property.usage | PROPERTY_USAGE_READ_ONLY
			)
		"reload_time":
			if clip_size==1:
				reload_time = split_time
				property.usage = property.usage | PROPERTY_USAGE_READ_ONLY
			else:
				property.usage = property.usage & ~PROPERTY_USAGE_READ_ONLY
#endregion

#region lifecycle
func _ready() -> void:
	assert(
		(target_mask & CollisionLayers.TARGETABLE_ANY) != 0,
		"Weapon '%s': must set something as targetable" % name
	)
	assert(
		(target_mask & ~CollisionLayers.TARGETABLE_ANY) == 0,
		"Weapon '%s': target_mask may only set TARGETABLE_GROUND / TARGETABLE_AIR" % name
	)

func _physics_process(_delta: float) -> void:
	_split_timer -= 1
	_reload_timer -= 1
	
	if _reload_timer <= 0:
		_split_timer = 0
		_ammo = clip_size
#endregion

#region Public API
## Returns true when this weapon can target the given entity: i.e. the target
## exposes a targetable layer (ground/air) that this weapon's target_mask covers.
## Entities with no targetable layer (targetable_layers() == 0) can't be attacked.
func can_target(a_target: Entity) -> bool:
	return (target_mask & a_target.targetable_layers()) != 0

func is_ready() -> bool:
	return _ammo>0 and _split_timer==0
	

func fire(a_owner: Commandable, a_target: Entity) -> void:
	var vet_level: int = a_owner.veterancy.level if a_owner.veterancy != null else 0
	var effective_damage: float = melee_damage + 0.2 * float(vet_level)
	if projectile_scene != null:
		var projectile: Projectile = projectile_scene.instantiate()
		projectile.initialize(a_owner.map, a_owner.commander)
		projectile.global_position = global_position
		projectile.initialize_projectile(a_owner, a_target, effective_damage)
	else:
		a_target.receive_damage(
			a_owner,
			Pattern.eval(Damage.multiplier_patterns[melee_damage_type], a_target) * melee_damage
		)
	
	_ammo -= 1
	_split_timer = split_time
	_reload_timer = reload_time
#endregion
