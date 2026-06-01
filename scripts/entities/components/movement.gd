class_name Movement
extends Node

## Movement component — wraps a NavigationAgent3D (DEFAULT mode) or provides
## straight-line aerial locomotion (AERIAL mode).
##
## Both modes expose the same API used by CommandReceiver and Commandable:
##   set_target_position / target_position
##   set_velocity
##   is_navigation_finished
##   get_next_path_position
##   set_avoidance_team
##
## CommandReceiver is therefore mode-agnostic; only the Y-snap in Commandable
## needs to query height_offset() to hover aerial units above the terrain.

signal velocity_ready(velocity: Vector3)

enum Mode { DEFAULT, AERIAL }

## Set in the inspector / scene file to choose the locomotion style.
@export var mode: Mode = Mode.DEFAULT

## Path (relative to this Movement node) to the NavigationAgent3D used in
## DEFAULT mode. Ignored in AERIAL mode.
@export var nav_agent_path: NodePath

## Maximum rate at which the entity's speed may increase, in world-units/s².
## INF (default) means speed can jump to any value instantly.
@export var max_acceleration: float = INF

## Maximum rate at which the entity's speed may decrease, in world-units/s².
## Must be ≤ 0; -INF (default) means speed can drop to any value instantly.
@export var max_deceleration: float = -INF

## How many world-units above the terrain surface an AERIAL unit flies.
const AERIAL_HEIGHT: float = 3.0

## XZ arrival radius for AERIAL mode (mirrors NavigationAgent3D's
## target_desired_distance used in DEFAULT mode).
const AERIAL_ARRIVAL_DISTANCE: float = 0.25

## Movement speed in world-units per physics tick.
@export var speed: float = 0.25

## Convenience read-only: speed expressed in world-units per second.
var speed_per_second: float:
	get: return speed * Engine.physics_ticks_per_second

var _nav_agent: NavigationAgent3D

## Stores the current target for AERIAL mode (no NavAgent to delegate to).
var _aerial_target: Vector3 = Vector3.ZERO

## Velocity actually emitted last tick — used to compute the speed delta for
## acceleration/deceleration clamping. For DEFAULT mode this is the
## avoidance-adjusted value, keeping the budget honest.
var _current_velocity: Vector3 = Vector3.ZERO

## True when the current movement leg is the entity's last queued destination
## (no commands follow in the queue). Set each tick by CommandReceiver; used
## to trigger braking so the entity decelerates to a halt at the target instead
## of arriving at full speed and snapping to a stop.
var is_final_leg: bool = false


var target_position: Vector3:
	get:
		match mode:
			Mode.DEFAULT: return _nav_agent.target_position if _nav_agent != null else Vector3.ZERO
			Mode.AERIAL:  return _aerial_target
		return Vector3.ZERO
	set(value):
		match mode:
			Mode.DEFAULT:
				if _nav_agent != null:
					_nav_agent.target_position = value
			Mode.AERIAL:
				_aerial_target = value


func _ready() -> void:
	if mode == Mode.DEFAULT:
		if not nav_agent_path.is_empty():
			_nav_agent = get_node_or_null(nav_agent_path) as NavigationAgent3D
		if _nav_agent != null:
			_nav_agent.velocity_computed.connect(_on_velocity_computed)


func set_target_position(world_position: Vector3) -> void:
	target_position = world_position


func set_velocity(velocity: Vector3) -> void:
	var v := _apply_accel_limits(velocity)
	match mode:
		Mode.DEFAULT:
			if _nav_agent != null:
				_nav_agent.set_velocity(v)
		Mode.AERIAL:
			# No avoidance system — emit the velocity directly so the entity
			# can apply it this same tick without waiting for a callback.
			_current_velocity = v
			velocity_ready.emit(v)


func is_navigation_finished() -> bool:
	match mode:
		Mode.DEFAULT:
			return _nav_agent.is_navigation_finished() if _nav_agent != null else true
		Mode.AERIAL:
			var pos_xz := Vector2(get_parent().global_position.x, get_parent().global_position.z)
			var tgt_xz := Vector2(_aerial_target.x, _aerial_target.z)
			return pos_xz.distance_squared_to(tgt_xz) \
				< AERIAL_ARRIVAL_DISTANCE * AERIAL_ARRIVAL_DISTANCE
	return true


func get_next_path_position() -> Vector3:
	match mode:
		Mode.DEFAULT:
			return _nav_agent.get_next_path_position() if _nav_agent != null else Vector3.ZERO
		Mode.AERIAL:
			# Return the target with Y matched to the entity's current Y so that
			# direction_to() in CommandReceiver produces a horizontal unit vector.
			# Zeroing Y from that vector is then a no-op, and full SPEED_PER_SECOND
			# is applied in XZ throughout the approach — no deceleration on arrival.
			var flat := _aerial_target
			flat.y = get_parent().global_position.y
			return flat
	return Vector3.ZERO


## Configure avoidance so same-team units avoid each other.
## No-op in AERIAL mode (no NavAgent, no avoidance mesh).
func set_avoidance_team(commander_id: int) -> void:
	if mode == Mode.DEFAULT and _nav_agent != null:
		var mask: int = 1 << commander_id
		_nav_agent.avoidance_layers = mask
		_nav_agent.avoidance_mask = mask


## World-units to add above the terrain surface when snapping Y.
## Commandable._on_velocity_computed and _physics_process both call this.
func height_offset() -> float:
	return AERIAL_HEIGHT if mode == Mode.AERIAL else 0.0


## Straight-line distance from the parent entity to its current movement target.
## AERIAL: XZ-only, matching is_navigation_finished. DEFAULT: 3D distance to
## the nav target, used as an approximation of remaining path length.
func _distance_to_target() -> float:
	match mode:
		Mode.AERIAL:
			var pos_xz := Vector2(get_parent().global_position.x, get_parent().global_position.z)
			var tgt_xz := Vector2(_aerial_target.x, _aerial_target.z)
			return pos_xz.distance_to(tgt_xz)
		Mode.DEFAULT:
			if _nav_agent != null:
				return get_parent().global_position.distance_to(_nav_agent.target_position)
	return 0.0


## Clamp the speed change from _current_velocity to desired within the
## per-tick budget derived from max_acceleration / max_deceleration.
## Also applies braking when is_final_leg is true and max_deceleration is
## bounded: caps desired speed to sqrt(2·|max_decel|·dist), the maximum speed
## from which the entity can decelerate to zero over the remaining distance.
func _apply_accel_limits(desired: Vector3) -> Vector3:
	if max_acceleration == INF and max_deceleration == -INF:
		return desired  # fast path — no clamping, no braking (decel is -INF)

	var tps: float = Engine.physics_ticks_per_second
	var current_speed: float = _current_velocity.length()
	var desired_speed: float = desired.length()

	# Braking: on the final leg with a bounded deceleration, cap speed so that
	# the entity can come to a full stop exactly at the destination.
	if is_final_leg and max_deceleration != -INF:
		var dist := _distance_to_target()
		# v_max = sqrt(2 * |decel| * remaining_dist) — the speed that allows
		# stopping in time given constant deceleration.
		var braking_speed := sqrt(2.0 * absf(max_deceleration) * dist) if dist > 0.0 else 0.0
		desired_speed = minf(desired_speed, braking_speed)

	var speed_delta: float = desired_speed - current_speed

	var clamped_delta: float = clampf(
		speed_delta,
		max_deceleration / tps,  # negative bound (deceleration)
		max_acceleration / tps   # positive bound (acceleration)
	)
	var new_speed: float = maxf(0.0, current_speed + clamped_delta)

	if new_speed < 1e-4:
		return Vector3.ZERO
	# Prefer the desired direction; fall back to current when desired is zero
	# (e.g. an explicit stop request while deceleration is still in progress).
	var dir: Vector3 = desired.normalized() if not desired.is_zero_approx() \
		else _current_velocity.normalized()
	return dir * new_speed


func _on_velocity_computed(velocity: Vector3) -> void:
	_current_velocity = velocity
	velocity_ready.emit(velocity)
