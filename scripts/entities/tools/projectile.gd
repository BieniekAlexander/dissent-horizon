class_name Projectile
extends Entity

### PROPERTIES
var attack_type: Weapon.AttackType = Weapon.AttackType.BALLISTIC

### ORIGIN
var source: Commandable

### MOVEMENT
const gravity: float = -.1
const speed: float = .5
var origin: Vector3
var damage: float = 5


### NODE
func _physics_process(delta: float) -> void:
	# TODO revisit this collision check
	if velocity.y<0 and global_position.y <= origin.y:
		var bodies: Array = map.get_nearby_entities(global_position, .1)
		
		for body: Entity in AU.sort_on_key(
			func(b): return VU.inXZ(global_position).distance_squared_to(VU.inXZ(b.global_position)),
			bodies
		):
			if body is Commandable and VU.inXZ(global_position).distance_squared_to(VU.inXZ(body.global_position))<(body.collision_radius**2):
				if not is_instance_valid(source): source = null
				body.receive_damage(
					source,
					Weapon.damage_multiplier_patterns[attack_type].eval(body)*source.DAMAGE
				)
				body.receive_damage(source, damage)
		
		_on_death()
	
	global_position += velocity
	velocity += Vector3.UP * gravity


func initialize_projectile(a_source: Variant, a_target: Variant) -> void:
	source = a_source if a_source is Commandable else null
	origin = a_source.global_position if a_source is Commandable else a_source
	var target: Vector3 = a_target.global_position if a_target is Entity else a_target
	
	var horizontal_dist: float = VU.inXZ(origin).distance_to(VU.inXZ(target))
	var time_to_target: float = horizontal_dist/speed
	var vert_velocity: float = -gravity*time_to_target/2
	
	global_position = origin
	velocity = (target-origin).normalized()*speed + (vert_velocity+gravity)*Vector3.UP
