class_name Movement
extends Node

## Movement component — wraps a NavigationAgent3D (GROUNDED_DIRECT mode) or provides
## straight-line aerial locomotion (HOVERING / FLYING modes).
##
## All modes expose the same API used by CommandReceiver and Commandable:
##   set_target_position / target_position
##   set_velocity
##   is_navigation_finished
##   get_next_path_position
##   set_avoidance_team
##
## CommandReceiver is therefore mode-agnostic; only the Y-snap in Commandable
## needs to query height_offset() to lift aerial units above the terrain.
##
## HOVERING vs FLYING
##   HOVERING  — stays stationary when no command is active.
##   FLYING    — orbits around an anchor point (the last command destination) when
##               idle. The anchor is set by CommandReceiver whenever a command ends,
##               so a flying unit is always moving.

#region Signals
signal velocity_ready(velocity: Vector3)
#endregion

#region Constants
## How many world-units above the terrain surface an aerial unit (HOVERING or
## FLYING) flies. Both modes share the same cruise altitude.
const AERIAL_HEIGHT: float = 1.5

## XZ arrival radius for HOVERING / FLYING modes (mirrors NavigationAgent3D's
## target_desired_distance used in GROUNDED_DIRECT mode).
const HOVERING_ARRIVAL_DISTANCE: float = 0.125
#endregion

#region Properties
enum Mode {
	GROUNDED_DIRECT = 0x0,
	HOVERING = 0x10,
	FLYING = 0x11
}

## Set in the inspector / scene file to choose the locomotion style.
@export var mode: Mode = Mode.GROUNDED_DIRECT

## Path (relative to this Movement node) to the NavigationAgent3D used in
## GROUNDED_DIRECT mode. Ignored in HOVERING mode.
@export var nav_agent_path: NodePath

## Collision size class — which space-eroded navmesh this unit navigates on (see
## NavAgentClass / nav-agent-size-classes.md). NOT authored: configure_for_map()
## derives it from the unit's MovementBody footprint radius (the smallest class
## large enough for the body), so it always matches the unit's real size.
var nav_agent_class: NavAgentClass.Size = NavAgentClass.Size.MEDIUM

## Maximum rate at which the entity's speed may increase, in world-units/s².
## INF (default) means speed can jump to any value instantly.
@export var max_acceleration: float = INF

## Maximum rate at which the entity's speed may decrease, in world-units/s².
## Must be ≤ 0; -INF (default) means speed can drop to any value instantly.
@export var max_deceleration: float = -INF

## Movement speed in world-units per physics tick.
@export var speed: float = 0.125

## Maximum rate at which the entity's heading may change, in degrees per second,
## for HOVERING mode. Limits the per-tick direction change in _apply_accel_limits
## so intermediate-waypoint transitions curve smoothly (banking turn) rather than
## snapping to the new heading instantly. INF (default) means no limit.
@export var turn_rate: float = INF

## Convenience read-only: speed expressed in world-units per second.
var speed_per_second: float:
	get: return speed * Engine.physics_ticks_per_second

var _nav_agent: NavigationAgent3D

## Stores the current target for HOVERING / FLYING modes (no NavAgent).
var _hovering_target: Vector3 = Vector3.ZERO

## Orbit parameters for FLYING mode. The unit circles the anchor while idle.
@export var orbit_radius: float = 3. ## desired orbit distance of this unit
@export var orbit_speed: float = .05 ## speed of unit while orbiting, units/tick
var orbit_angular_speed: ## orbit angular speed in degrees/tick
	get: return rad_to_deg(orbit_speed/orbit_radius)

## The point a FLYING unit orbits while idle — set to the last command destination
## by CommandReceiver whenever a command ends. Seeded from the parent entity's
## position in _ready (only FLYING/HOVERING modes have a Node3D parent and ever
## read this; a plain-Node parent — e.g. in unit tests — leaves it at ZERO).
var _anchor: Vector3 = Vector3.ZERO

## Current angle (radians) on the orbit circle, updated each tick by
## compute_orbit_velocity(). Initialised from the unit's actual position relative
## to the anchor so the orbit starts smoothly without a jump.
var _orbit_angle: float = 0.0

## Velocity actually emitted last tick — used to compute the speed delta for
## acceleration/deceleration clamping. For GROUNDED_DIRECT mode this is the
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
			Mode.GROUNDED_DIRECT: return _nav_agent.target_position if _nav_agent != null else Vector3.ZERO
			Mode.HOVERING, Mode.FLYING:  return _hovering_target
		return Vector3.ZERO
	set(value):
		match mode:
			Mode.GROUNDED_DIRECT:
				if _nav_agent != null:
					_nav_agent.target_position = value
			Mode.HOVERING, Mode.FLYING:
				_hovering_target = value
#endregion

#region Lifecycle
func _ready() -> void:
	var parent := get_parent()
	if parent is Node3D:
		_anchor = (parent as Node3D).global_position
	if mode == Mode.GROUNDED_DIRECT:
		if not nav_agent_path.is_empty():
			_nav_agent = get_node_or_null(nav_agent_path) as NavigationAgent3D
		if _nav_agent != null:
			_nav_agent.velocity_computed.connect(_on_velocity_computed)
#endregion

#region Public API

#region Navigation
func set_target_position(world_position: Vector3) -> void:
	target_position = world_position


func set_velocity(velocity: Vector3) -> void:
	var v := _apply_accel_limits(velocity)
	match mode:
		Mode.GROUNDED_DIRECT:
			if _nav_agent != null:
				_nav_agent.set_velocity(v)
		Mode.HOVERING, Mode.FLYING:
			# No avoidance system — emit the velocity directly so the entity
			# can apply it this same tick without waiting for a callback.
			_current_velocity = v
			velocity_ready.emit(v)


func is_navigation_finished() -> bool:
	match mode:
		Mode.GROUNDED_DIRECT:
			return _nav_agent.is_navigation_finished() if _nav_agent != null else true
		Mode.HOVERING, Mode.FLYING:
			var pos_xz := Vector2(get_parent().global_position.x, get_parent().global_position.z)
			var tgt_xz := Vector2(_hovering_target.x, _hovering_target.z)
			return pos_xz.distance_squared_to(tgt_xz) \
				< HOVERING_ARRIVAL_DISTANCE * HOVERING_ARRIVAL_DISTANCE
	return true


func get_next_path_position() -> Vector3:
	match mode:
		Mode.GROUNDED_DIRECT:
			return _nav_agent.get_next_path_position() if _nav_agent != null else Vector3.ZERO
		Mode.HOVERING, Mode.FLYING:
			# Return the target with Y matched to the entity's current Y so that
			# direction_to() in CommandReceiver produces a horizontal unit vector;
			# zeroing Y is then a no-op. Speed is managed by _apply_accel_limits
			# (braking on the final leg when max_deceleration is bounded).
			var flat := _hovering_target
			flat.y = get_parent().global_position.y
			return flat
	return Vector3.ZERO
#endregion

#region FLYING orbit
## Set the anchor that a FLYING unit circles while idle. Initialises _orbit_angle
## from the unit's current position so the orbit starts without a positional jump.
func set_anchor(pos: Vector3) -> void:
	_anchor = pos
	var offset: Vector2 = VU.inXZ(get_parent().global_position) - VU.inXZ(pos)
	if offset.length_squared() > 1e-4:
		_orbit_angle = atan2(offset.y, offset.x)


## Advance the orbit one physics tick and return the XZ velocity (Y=0) that moves
## the unit toward the next point on the orbit circle. Call set_velocity() with
## this result so accel/turn-rate limits are applied normally.
func compute_orbit_velocity() -> Vector3:
	var tps: float = Engine.physics_ticks_per_second
	# Advance the angle deterministically — do NOT re-derive it from the unit's
	# actual position. Re-deriving each tick means the "ideal point" on the circle
	# is always measured from wherever the unit happens to be, so any radial error
	# produces a target that's slightly off-angle, giving no net restoring force and
	# causing the unit to oscillate in and out of the circle.
	# set_anchor() seeds _orbit_angle from the real position once; from there the
	# angle is a clock that ticks forward at orbit_angular_speed regardless of where
	# the unit is. If it drifts off-radius, the ideal point is still on the circle,
	# so direction_to() naturally has a corrective radial component that pulls the
	# unit back while continuing the orbit.
	_orbit_angle += orbit_speed / orbit_radius
	var ideal_xz: Vector2 = VU.inXZ(_anchor) + Vector2(cos(_orbit_angle), sin(_orbit_angle)) * orbit_radius
	var ideal_3d: Vector3 = VU.fromXZ(ideal_xz)
	# Match Y so direction_to() gives a horizontal vector; Y is snapped by Commandable.
	ideal_3d.y = get_parent().global_position.y
	# Use orbit_speed (not speed_per_second) so the unit travels at the same rate
	# as the ideal point advances along the arc. Both move at orbit_speed, so once
	# on the circle the unit tracks the ideal exactly — and orbit_radius is the true
	# governing parameter rather than the generic movement speed. Multiply by tps
	# to convert from units/tick to units/second (the unit CharacterBody3D.velocity
	# expects, consistent with speed_per_second used elsewhere).
	return get_parent().global_position.direction_to(ideal_3d) * orbit_speed * tps
#endregion

#region RVO avoidance
## RVO avoidance notes: every agent broadcasts on a shared channel and avoids
## everyone (mask = ALL); the avoidance layers do NOT encode teams. The
## "enemies don't get out of our way" requirement is upheld by the command loop,
## not the mask: only commanded, moving units apply an avoidance velocity, so
## idle enemy units never reposition to accommodate us. Per-pair exemptions (a
## unit following another) are handled by AvoidanceAgent3D exceptions, driven via
## set_avoidance_follow_target() below.

## Saved avoidance_layers value while suppression is active; 0 means not suppressed.
var _saved_avoidance_layers: int = 0
## Saved obstacle avoidance_layers while suppression is active; 0 means not suppressed.
var _saved_obstacle_layers: int = 0

## NavigationObstacle3D that broadcasts this unit as an obstacle for cross-team
## one-sided avoidance. Assigned by Commandable._ready after both nodes exist.
var avoidance_obstacle: NavigationObstacle3D = null

## The commandable this unit is currently "following" (its move destination is
## that unit), for which reciprocal RVO avoidance is suppressed. null = none.
var _avoidance_follow: Commandable = null

## The NavigationAgent3D as an AvoidanceAgent3D, or null if it isn't one (e.g. a
## plain agent in a unit test). Gates the per-pair avoidance-exception API.
func avoidance_agent() -> AvoidanceAgent3D:
	return _nav_agent as AvoidanceAgent3D

## Turn on RVO avoidance for `commander_id`'s team. Called once ownership is
## established. Each commander owns one avoidance team bit; a unit avoids its own
## team (and any agent currently in a per-pair exception) — see AvoidanceAgent3D.
func enable_avoidance(commander_id: int) -> void:
	var agent := avoidance_agent()
	if mode == Mode.GROUNDED_DIRECT and agent != null:
		agent.enable_avoidance(commander_id)

## Make this unit and `other` ignore each other in RVO (used while following a
## unit), leaving all their other avoidance interactions intact. Passing a
## different target (or null) drops the previous exception first, so this can be
## driven straight from the per-tick command state. No-op in HOVERING mode or when
## either side lacks an AvoidanceAgent3D.
func set_avoidance_follow_target(other: Commandable) -> void:
	var agent := avoidance_agent()
	if mode != Mode.GROUNDED_DIRECT or agent == null or other == _avoidance_follow:
		return
	var prev: AvoidanceAgent3D = _follow_agent(_avoidance_follow)
	if prev != null:
		agent.remove_avoidance_exception_with(prev)
	_avoidance_follow = other
	var next: AvoidanceAgent3D = _follow_agent(other)
	if next != null:
		agent.add_avoidance_exception_with(next)

func _follow_agent(c: Commandable) -> AvoidanceAgent3D:
	if c == null or not is_instance_valid(c) or c.movement == null:
		return null
	return c.movement.avoidance_agent()

## Zero this agent's broadcast layers and its obstacle layers so no other agent
## RVO-steers around it. Used by Occupy to let the approaching unit walk into
## the garrison target without the avoidance system pushing them apart.
## No-op if already suppressed or in HOVERING mode.
func suppress_avoidance_layers() -> void:
	if mode != Mode.GROUNDED_DIRECT or _nav_agent == null or _saved_avoidance_layers != 0:
		return
	_saved_avoidance_layers = _nav_agent.avoidance_layers
	_nav_agent.avoidance_layers = 0
	if avoidance_obstacle != null and avoidance_obstacle.avoidance_enabled:
		_saved_obstacle_layers = avoidance_obstacle.avoidance_layers
		avoidance_obstacle.avoidance_layers = 0

## Restore the avoidance_layers cleared by suppress_avoidance_layers.
func restore_avoidance_layers() -> void:
	if mode != Mode.GROUNDED_DIRECT or _nav_agent == null or _saved_avoidance_layers == 0:
		return
	_nav_agent.avoidance_layers = _saved_avoidance_layers
	_saved_avoidance_layers = 0
	if avoidance_obstacle != null and _saved_obstacle_layers != 0:
		avoidance_obstacle.avoidance_layers = _saved_obstacle_layers
		_saved_obstacle_layers = 0
#endregion

## Size the RVO avoidance radius to the body's real footprint so agents keep
## a correct distance from one another. No-op in HOVERING mode (no NavAgent).
func set_agent_radius(a_radius: float) -> void:
	if mode == Mode.GROUNDED_DIRECT and _nav_agent != null and a_radius > 0.0:
		_nav_agent.radius = a_radius


## Configure the agent from its MovementBody footprint `shape_radius`: set the RVO
## avoidance radius to that footprint, derive the unit's size class (the smallest
## NavAgentClass large enough to contain it), and select that class's space-eroded
## navmesh via the agent's navigation_layers. The agent STAYS on the shared default
## navigation map (every class mesh is a region on it), so RVO avoidance still sees
## all units regardless of size — only the pathfinding layer differs. Called once the
## unit's Map (hence its NavManager) is known — see Commandable.initialize. No-op in
## HOVERING mode or when the agent / nav_manager is missing (e.g. plain test agents).
func configure_for_map(nav_manager: NavManager, shape_radius: float) -> void:
	if mode != Mode.GROUNDED_DIRECT or _nav_agent == null or nav_manager == null:
		return
	set_agent_radius(shape_radius)
	nav_agent_class = NavAgentClass.class_for_radius(shape_radius)
	_nav_agent.navigation_layers = nav_manager.layer_for(nav_agent_class)


## World-units to add above the terrain surface when snapping Y.
## Commandable._on_velocity_computed and _physics_process both call this.
func height_offset() -> float:
	return AERIAL_HEIGHT if mode == Mode.HOVERING or mode == Mode.FLYING else 0.0

#endregion

#region Private helpers
## Straight-line distance from the parent entity to its current movement target.
## HOVERING/FLYING: XZ-only, matching is_navigation_finished. GROUNDED_DIRECT: 3D
## distance to the nav target, used as an approximation of remaining path length.
func _distance_to_target() -> float:
	match mode:
		Mode.HOVERING, Mode.FLYING:
			var pos_xz := Vector2(get_parent().global_position.x, get_parent().global_position.z)
			var tgt_xz := Vector2(_hovering_target.x, _hovering_target.z)
			return pos_xz.distance_to(tgt_xz)
		Mode.GROUNDED_DIRECT:
			if _nav_agent != null:
				return get_parent().global_position.distance_to(_nav_agent.target_position)
	return 0.0


## Clamp the speed change from _current_velocity to desired within the
## per-tick budget derived from max_acceleration / max_deceleration.
## Also applies braking when is_final_leg is true and max_deceleration is
## bounded: caps desired speed to sqrt(2·|max_decel|·dist), the maximum speed
## from which the entity can decelerate to zero over the remaining distance.
func _apply_accel_limits(desired: Vector3) -> Vector3:
	# The fast path is safe only when no alignment scaling is needed: a moving
	# HOVERING unit must go through the full path so the turn-deceleration below
	# can scale desired_speed even when accel/decel limits are infinite.
	var hovering_needs_alignment: bool = mode == Mode.HOVERING \
			and not _current_velocity.is_zero_approx() \
			and not desired.is_zero_approx()
	if max_acceleration == INF and max_deceleration == -INF and turn_rate == INF \
			and not hovering_needs_alignment:
		return desired  # fast path — no clamping, no braking, no turn-rate limit

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

	# Alignment-based speed scaling for HOVERING: when the unit's current heading
	# diverges from the direction to the target (e.g. mid-turn at a waypoint), cap
	# desired_speed proportionally so the unit decelerates through the turn and
	# accelerates back to full speed once it is pointed at the destination. The
	# existing max_deceleration clamp below makes the slowdown gradual.
	if hovering_needs_alignment:
		var alignment: float = _current_velocity.normalized().dot(desired.normalized())
		desired_speed *= maxf(0.0, alignment)

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
	# Banking turn: in HOVERING mode, limit how fast the heading can swing per tick
	# so intermediate-waypoint transitions produce a smooth curve rather than a
	# hard snap. Skipped when the unit is stopped (no current direction to blend from)
	# or when turn_rate is unconstrained.
	if (mode == Mode.HOVERING or mode == Mode.FLYING) and turn_rate != INF and not _current_velocity.is_zero_approx():
		var current_dir: Vector3 = _current_velocity.normalized()
		var max_angle: float = deg_to_rad(turn_rate) / tps
		var angle: float = current_dir.angle_to(dir)
		if angle > max_angle:
			dir = current_dir.slerp(dir, max_angle / angle).normalized()
	return dir * new_speed


func _on_velocity_computed(velocity: Vector3) -> void:
	_current_velocity = velocity
	velocity_ready.emit(velocity)
#endregion
