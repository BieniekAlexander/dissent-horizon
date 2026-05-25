class_name Projectile
extends Entity

### PROPERTIES
var attack_type: Weapon.AttackType = Weapon.AttackType.BALLISTIC

### ORIGIN
var source: Commandable
var target: Commandable

### MOVEMENT
const gravity: float = -.01
const speed: float = .35
var origin: Vector3
var damage: float = 5

@onready var hit_shape: CollisionShape3D = get_node_or_null("HitShape")


### NODE
func _physics_process(_delta: float) -> void:
	if velocity.y < 0 and global_position.y <= origin.y:
		_apply_hit()
		_on_death()
		return

	global_position += velocity
	velocity += Vector3.UP * gravity

func _apply_hit() -> void:
	if hit_shape == null or not is_instance_valid(target):
		return
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = hit_shape.shape
	params.transform = hit_shape.global_transform
	params.collision_mask = CollisionLayers.Layer.BODY
	var hits: Array = get_world_3d().direct_space_state.intersect_shape(params, 10)
	for hit in hits:
		if hit["collider"] == target:
			if not is_instance_valid(source):
				source = null
			if source != null:
				target.receive_damage(
					source,
					Pattern.eval(Weapon.damage_multiplier_patterns[attack_type], target) * source.DAMAGE
				)
			target.receive_damage(source, damage)
			break


func initialize_projectile(a_source: Variant, a_target: Variant) -> void:
	source = a_source if a_source is Commandable else null
	target = a_target if a_target is Commandable else null
	origin = a_source.global_position if a_source is Commandable else a_source
	var target_pos: Vector3 = a_target.global_position if a_target is Entity else a_target

	var horizontal_dist: float = VU.inXZ(origin).distance_to(VU.inXZ(target_pos))
	var time_to_target: float = horizontal_dist / speed
	var vert_velocity: float = -gravity * time_to_target / 2

	global_position = origin
	velocity = (target_pos - origin).normalized() * speed + (vert_velocity + gravity) * Vector3.UP
	#commander = a_source.commander
