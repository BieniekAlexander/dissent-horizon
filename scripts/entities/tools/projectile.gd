class_name Projectile
extends Entity

#region Properties
## How a projectile moves from its origin toward the target. The trajectory-specific
## math (launch velocity, per-tick advance, and landing test) is dispatched off this
## value — see _initial_velocity / _advance / _has_landed.
enum Trajectory {
	BALLISTIC,	## Gravity-driven arc. The original (and default) implementation.
	LINEAR,		## Constant-velocity straight line toward the target; no gravity.
	LOFTED,		## High lob arc — NOT YET IMPLEMENTED (see the _*_lofted stubs).
	HOMING		## Follows its target for some time
}

## Lifecycle phase. IN_FLIGHT = travelling toward the target; POST_IMPACT = landed
## and (optionally) persisting as a damage from until post_impact_lifespan frames
## elapse. This generalizes Radiation's old FLYING/FIELD state machine onto every
## projectile.
enum State {
	IN_FLIGHT,
	POST_IMPACT,
}

const gravity: float = -.005

## Sentinel tick_rate ("infinite" period): damage is applied once, on impact, and
## never repeats. GDScript ints can't hold INF, so this is a value no realistic
## lifespan reaches — the modulo in _tick_post_impact then never fires again.
const INT_MAX: int = 1 << 31

@export var hitscan: bool = false
@export var trajectory: Trajectory = Trajectory.BALLISTIC
@export var speed: float = .175
@export var base_damage: float = 5.0 ## Damage value applied by this projectile, before any modifications
@export var damage_type: Damage.Type = Damage.Type.LEAD

@export var pre_impact_lifespan: int = INT_MAX ## how long the projectile will last before detonating
@export var post_impact_lifespan: int = 1 ## how long the projectile will last after impact
@export var tick_rate: int = INT_MAX ## tick rate at which damage is reapplied POST_IMPACT

var from: Commandable
var target: Commandable
## Launch-time target point. Used by the LINEAR landing test (a straight-line shot
## has no ground-plane crossing to key off, so it lands on reaching this point).
var _destination: Vector3

var _state: State = State.IN_FLIGHT
## Frames elapsed since impact; drives the tick_rate re-application schedule.
var _frames_pre_impact: int = 0
var _frames_post_impact: int = 0

@onready var hit_shape: CollisionShape3D = get_node_or_null("HitShape")
## Per-state visuals — all optional (a scene may wire only the ones it uses). The
## in-flight pair shows while travelling; the post-impact pair while persisting.
@onready var _in_flight_sprite: Sprite3D = get_node_or_null("InFlightSprite") as Sprite3D
@onready var _in_flight_particles: GPUParticles3D = get_node_or_null("InFlightParticles") as GPUParticles3D
@onready var _post_impact_sprite: Sprite3D = get_node_or_null("PostImpactSprite") as Sprite3D
@onready var _post_impact_particles: GPUParticles3D = get_node_or_null("PostImpactParticles") as GPUParticles3D
#endregion

#region Lifecycle
func _ready() -> void:
	super()
	_apply_state_visuals()
	assert(hitscan != (hit_shape!=null), "hitscan weapon has hit shape")
	curr_physics_pos = global_position

var prev_physics_pos: Vector3
var curr_physics_pos: Vector3

func _physics_process(_delta: float) -> void:
	prev_physics_pos = curr_physics_pos
	curr_physics_pos = global_position
	match _state:
		State.IN_FLIGHT:
			if _has_landed() or _frames_pre_impact>pre_impact_lifespan:
				_enter_post_impact()
			else:
				_tick_pre_impact()
		State.POST_IMPACT:
			_tick_post_impact()

func _process(_delta: float) -> void:
	if trajectory==Trajectory.LINEAR: # TODO clean up the LERP visualization
		var alpha: float = Engine.get_physics_interpolation_fraction()
		$InFlightSprite.global_position = prev_physics_pos.lerp(curr_physics_pos, alpha)
#endregion

#region Impact lifecycle
func _tick_pre_impact() -> void:
	_advance()
	_frames_pre_impact += 1

## State change to post-impact, accounting for visuals and state flag
func _enter_post_impact() -> void:
	_state = State.POST_IMPACT
	velocity = Vector3.ZERO
	global_position.y = _destination.y
	_apply_state_visuals()
	_tick_post_impact()

## Apply damage per tick_rate, and die if timespan elapses
func _tick_post_impact() -> void:
	if _frames_post_impact % tick_rate == 0:
		_apply_hit()
	_frames_post_impact += 1
	if _frames_post_impact >= post_impact_lifespan:
		_on_death()
#endregion

#region Public API
func initialize_projectile(a_from: Variant, a_target: Variant, a_weapon_damage: float = 0.0) -> void:
	 # TODO revisit projectile damage: should the damage value be initialized within the projectile, or the weapon it comes from?
	# At the end of the day, I need some avenue of increasing the projectile damage according to upgrades and such
	if a_weapon_damage>0: base_damage = a_weapon_damage
	from = a_from if a_from is Commandable else null
	target = a_target if a_target is Commandable else null
	var target_pos: Vector3 = a_target.global_position if a_target is Entity else a_target
	
	_destination = target_pos
	velocity = _initial_velocity(target_pos)
	#commander = a_source.commander
#endregion

#region Trajectory dispatch
## The launch velocity for the current trajectory. Called once from
## initialize_projectile after origin/_destination are set.
func _initial_velocity(target_pos: Vector3) -> Vector3:
	match trajectory:
		Trajectory.BALLISTIC: return _initial_velocity_ballistic(target_pos)
		Trajectory.LINEAR:    return _initial_velocity_linear(target_pos)
		Trajectory.LOFTED:    return _initial_velocity_lofted(target_pos)
		Trajectory.HOMING:    return _initial_velocity_homing(target_pos)
	assert(false, "unhandled trajectory type")
	return Vector3.ZERO

## True once the projectile has reached its endpoint and should hit / despawn.
## Exposed (not inlined) so subclasses with their own lifecycle (e.g. Radiation's
## state machine) can reuse it.
func _has_landed() -> bool:
	match trajectory:
		Trajectory.BALLISTIC: return _has_landed_ballistic()
		Trajectory.LINEAR:    return _has_landed_linear()
		Trajectory.LOFTED:    return _has_landed_lofted()
		Trajectory.HOMING:    return _has_landed_homing()
	assert(false, "unhandled trajectory type")
	return true

## Advance one physics step for the current trajectory. Shared with subclasses so
## they don't reimplement the motion.
func _advance() -> void:
	match trajectory:
		Trajectory.BALLISTIC: _advance_ballistic()
		Trajectory.LINEAR:    _advance_linear()
		Trajectory.LOFTED:    _advance_lofted()
		Trajectory.HOMING:    _advance_homing()
#endregion

#region Trajectory: BALLISTIC (gravity arc)
func _initial_velocity_ballistic(target_pos: Vector3) -> Vector3:
	var to_target_xz: Vector2 = VU.inXZ(target_pos) - VU.inXZ(global_position)
	var horizontal_dist: float = to_target_xz.length()
	var time_to_target: float = horizontal_dist / speed
	# Vertical velocity needed to arrive at target_pos.y in exactly time_to_target
	# frames under constant gravity. The same-height term (-gravity*T/2) is offset
	# by the per-frame drop/climb needed to cover the vertical gap.
	var vert_velocity: float = (target_pos.y - global_position.y) / time_to_target - gravity * time_to_target / 2
	# Horizontal component uses the XZ-only direction so that a height difference
	# between origin and target doesn't bleed a spurious Y into the base velocity.
	return VU.fromXZ(to_target_xz.normalized() * speed) + (vert_velocity + gravity) * Vector3.UP

## Descending and at or below the target's height — i.e. reached the landing plane.
## Keying off _destination.y (not origin.y) so an elevated launch point doesn't
## trigger impact prematurely on the way back down through the weapon height.
func _has_landed_ballistic() -> bool:
	return velocity.y < 0 and global_position.y <= _destination.y

func _advance_ballistic() -> void:
	global_position += velocity
	velocity += Vector3.UP * gravity
#endregion

#region Trajectory: LINEAR (straight line, no gravity)
func _initial_velocity_linear(target_pos: Vector3) -> Vector3:
	return (target_pos - global_position).normalized() * speed

## Reached the launch-time target point (within one step). A linear shot has no
## ground-plane crossing, so we key off arrival at _destination instead.
func _has_landed_linear() -> bool:
	return global_position.distance_to(_destination) <= speed

func _advance_linear() -> void:
	global_position += velocity
#endregion

#region Trajectory: LOFTED (high lob — UNIMPLEMENTED)
func _initial_velocity_lofted(_target_pos: Vector3) -> Vector3:
	_raise_lofted_unimplemented()
	return Vector3.ZERO

func _has_landed_lofted() -> bool:
	_raise_lofted_unimplemented()
	return true

func _advance_lofted() -> void:
	_raise_lofted_unimplemented()

## LOFTED is reserved but not yet implemented; fail loudly if a projectile is
## configured to use it. Replace these stubs with the real lob math when adding it.
func _raise_lofted_unimplemented() -> void:
	push_error("Projectile.Trajectory.LOFTED is not implemented yet")
	assert(false, "Projectile.Trajectory.LOFTED is not implemented yet")
#endregion

#region Trjajectory: HOMING
const rotation_rate: float = deg_to_rad(2.5) # TODO expose, probably
const acceleration: float = .0025
const min_speed: float = .005
var flight_time: int = 180

func _initial_velocity_homing(a_target_pos: Vector3) -> Vector3:
	return global_position.direction_to(a_target_pos)*speed/2

func _has_landed_homing() -> bool:
	 # TODO update this check, this is temp
	return (
		global_position.distance_squared_to(target.global_position)<.25
		if is_instance_valid(target)
		else flight_time<=0
	)

func _advance_homing() -> void:
	flight_time -= 1 # TODO move this out
	if target:
		var goal_direction: Vector3 = global_position.direction_to(target.global_position)
		var dot: float = velocity.normalized().dot(global_position.direction_to(target.global_position).normalized())
		velocity = VU.get_rotated_vector_3d(velocity, goal_direction, rotation_rate)
		velocity = velocity.normalized() * (
			min(velocity.length()+acceleration, speed)
			if dot >= 0
			else max(velocity.length()-acceleration, min_speed)
		)
	
	global_position += velocity
#endregion

#region Private helpers
## Show the visuals for the current state (in-flight pair while travelling, the
## post-impact pair once landed) and hide the other. Each node is optional.
func _apply_state_visuals() -> void:
	var in_flight: bool = _state == State.IN_FLIGHT
	_set_visual(_in_flight_sprite, _in_flight_particles, in_flight)
	_set_visual(_post_impact_sprite, _post_impact_particles, not in_flight)

func _set_visual(sprite: Sprite3D, particles: GPUParticles3D, on: bool) -> void:
	if sprite != null:
		sprite.visible = on
	if particles != null:
		particles.visible = on
		particles.emitting = on

func _apply_hit() -> void:
	if hit_shape == null:
		target.receive_damage(from, base_damage)
	else:
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = hit_shape.shape
		params.transform = hit_shape.global_transform
		params.collision_mask = CollisionLayers.Mask.TARGETABLE
		params.exclude = [self]
		var hits: Array = get_world_3d().direct_space_state.intersect_shape(params, 32)
		
		for hit in hits:
			var entity: Entity = Entity.entity_from_collider(hit["collider"])
			var cmd: Commandable = entity as Commandable if entity != null else null
			if cmd != null and cmd.defense != null:
				cmd.receive_damage(from, base_damage)

#endregion
