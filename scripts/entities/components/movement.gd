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

## Rate (world-units/tick) at which a HOVERING unit descends to or ascends from
## the ground during a temporary landing.  At 30 ticks/s and AERIAL_HEIGHT = 1.5
## this gives a ~1-second descent and a ~1-second ascent.
const LANDING_SPEED: float = 0.05
#endregion

#region Properties
enum Mode {
	GROUNDED_DIRECT = 0x0,
	HOVERING = 0x10,
	FLYING = 0x11
}

## Internal state for temporary landings (HOVERING units only).
## AIRBORNE     — flying normally at AERIAL_HEIGHT.
## LANDING      — descending toward terrain; horizontal movement suppressed.
## GROUNDED_TEMP — on the ground, waiting for the triggering command to finish.
## TAKING_OFF   — ascending back to AERIAL_HEIGHT after GROUNDED_TEMP resolves.
enum LandingState {
	AIRBORNE,
	LANDING,
	GROUNDED_TEMP,
	TAKING_OFF
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

## Fraction of max speed available when moving directly opposite to the current
## body-facing direction (180° reversal). 0.0 (default) preserves the existing
## behaviour — the unit must rotate to face the target before accelerating. A
## value around 0.35 matches real helicopter reverse-flight limits (~35% of
## forward speed) and lets the unit slide backward while the fuselage rotates
## to catch up. Only meaningful in HOVERING mode with a finite turn_rate; units
## with turn_rate = INF can always reach full speed in any direction.
@export var reverse_speed_ratio: float = 0.35

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

## Horizontal distance (world units) over which a FLYING unit performs its dive-attack
## descent: at or beyond this distance from the dive target it cruises at AERIAL_HEIGHT,
## at the target it touches the ground, interpolating linearly between. Driven by
## request_dive() / _update_flying_height().
@export var dive_distance: float = 3.0

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

## Body-facing direction for HOVERING units with reverse_speed_ratio > 0.
## Represents the nose orientation; chases the emitted velocity direction at
## turn_rate deg/s each tick. Persists when the unit is stopped so the unit
## retains its heading between commands. Zero until the unit first moves, at
## which point it is snapped to the initial velocity direction.
var _facing: Vector3 = Vector3.ZERO

## Current landing state for HOVERING units.  Always AIRBORNE for other modes.
var _landing_state: LandingState = LandingState.AIRBORNE

## Map reference used by HOVERING units for navmesh queries (landing snap and
## ascent cap). Set by configure_for_map(); null until then.
var _map: Map = null

## When true the unit grounded itself with an explicit Land command and will stay
## down until a movement command is issued.  Blocks the automatic take_off() that
## the garrison system calls after all pending units have entered; only
## take_off_for_movement() can clear this flag.
var _permanently_grounded: bool = false

## Callable fired once the unit touches down (LANDING → GROUNDED_TEMP transition).
## May be an empty Callable when landing is triggered without a follow-up action.
var _land_on_complete: Callable = Callable()

## When the predicted touchdown is off-navmesh, _try_start_landing() raises this
## flag instead of immediately entering LANDING. While true, _physics_process drives
## the unit toward _landing_target in AIRBORNE state; the descent begins only once
## the unit arrives. Cleared either on arrival (→ LANDING) or by cancel_pending_land().
var _pending_land: bool = false

## Target position the unit navigates to before descending (set by
## _compute_landing_correction when the predicted touchdown is off-navmesh).
## Also used as a steering target during LANDING when a TAKING_OFF reversal
## detects an off-navmesh prediction. Cleared when GROUNDED_TEMP is entered.
var _landing_target: Vector3 = Vector3.ZERO
var _has_landing_target: bool = false

## Tracks the unit's current Y offset above the terrain surface.  Starts at
## AERIAL_HEIGHT for HOVERING/FLYING, 0 for GROUNDED_DIRECT.  Animated during
## LANDING (decreases) and TAKING_OFF (increases); read by height_offset().
var _current_height_offset: float = 0.0

## FLYING dive-attack state. request_dive() raises _dive_requested each tick a FLYING
## unit is attacking a ground target, recording the target's XZ in _dive_target_xz;
## _update_flying_height() consumes (clears) the flag. Because it self-clears, the unit
## only keeps diving while the requests keep arriving — once they stop (target lost,
## attack ended, or target out of dive_distance handling) it eases back to AERIAL_HEIGHT.
var _dive_requested: bool = false
var _dive_target_xz: Vector2 = Vector2.ZERO

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
	_current_height_offset = AERIAL_HEIGHT if mode == Mode.HOVERING or mode == Mode.FLYING else 0.0
	if mode == Mode.GROUNDED_DIRECT:
		if not nav_agent_path.is_empty():
			_nav_agent = get_node_or_null(nav_agent_path) as NavigationAgent3D
		if _nav_agent != null:
			_nav_agent.velocity_computed.connect(_on_velocity_computed)

func _physics_process(_delta: float) -> void:
	if mode == Mode.FLYING:
		_update_flying_height()
		return
	if mode != Mode.HOVERING:
		return
	# Pre-landing navigation: stay AIRBORNE and steer to the safe landing spot
	# before beginning the descent. Descent starts once we arrive.
	if _pending_land and _landing_state == LandingState.AIRBORNE:
		var parent_pos: Vector3 = get_parent().global_position
		var to_target: Vector3 = _landing_target - parent_pos
		to_target.y = 0.0
		if to_target.length() <= HOVERING_ARRIVAL_DISTANCE:
			_pending_land = false
			_has_landing_target = false
			_landing_state = LandingState.LANDING
		else:
			var tps: float = Engine.physics_ticks_per_second
			# Brake as the unit closes in: cap speed so it arrives in at most 1 tick
			# when very close, preventing overshoot of a nearby target cell center.
			var desired_speed: float = minf(speed, to_target.length()) * tps
			var desired: Vector3 = to_target.normalized() * desired_speed
			_current_velocity = _apply_accel_limits(desired)
			velocity_ready.emit(_current_velocity)
			_update_facing(_current_velocity)
		return
	match _landing_state:
		LandingState.LANDING:
			_current_height_offset = maxf(0.0, _current_height_offset - LANDING_SPEED)
			if _current_height_offset <= 0.0:
				_landing_state = LandingState.GROUNDED_TEMP
				_has_landing_target = false
				_snap_to_navmesh()  # last-resort snap if steering fell short
				if _land_on_complete.is_valid():
					_land_on_complete.call()
			elif _has_landing_target:
				# Steer toward the corrected landing position during descent.
				# Speed is capped so the unit arrives exactly when it touches down.
				var parent_pos: Vector3 = get_parent().global_position
				var to_target: Vector3 = _landing_target - parent_pos
				to_target.y = 0.0
				var dist: float = to_target.length()
				if dist > HOVERING_ARRIVAL_DISTANCE:
					var ticks_remaining: float = _current_height_offset / LANDING_SPEED
					var tps: float = Engine.physics_ticks_per_second
					var time_remaining: float = ticks_remaining / tps
					var max_speed: float = dist / time_remaining if time_remaining > 1e-4 \
						else speed * tps
					var desired: Vector3 = to_target.normalized() \
						* minf(speed * tps, max_speed)
					_current_velocity = _apply_accel_limits(desired)
					velocity_ready.emit(_current_velocity)
					_update_facing(_current_velocity)
				elif not _current_velocity.is_zero_approx():
					_current_velocity = _apply_accel_limits(Vector3.ZERO)
					velocity_ready.emit(_current_velocity)
					_update_facing(_current_velocity)
			else:
				# No correction needed; decelerate horizontal velocity to zero.
				if not _current_velocity.is_zero_approx():
					_current_velocity = _apply_accel_limits(Vector3.ZERO)
					velocity_ready.emit(_current_velocity)
					_update_facing(_current_velocity)
		LandingState.TAKING_OFF:
			_current_height_offset = minf(AERIAL_HEIGHT, _current_height_offset + LANDING_SPEED)
			if _current_height_offset >= AERIAL_HEIGHT:
				_landing_state = LandingState.AIRBORNE
#endregion

#region Public API

#region Temporary landing (HOVERING units only)
## Begin a smooth descent to terrain level.  `on_complete` is called once the
## unit touches down and transitions to GROUNDED_TEMP.  Idempotent: a second
## call while a landing is already in progress is silently ignored.
## Non-HOVERING units: on_complete fires immediately and nothing else changes.
func land(on_complete: Callable) -> void:
	if mode != Mode.HOVERING:
		if on_complete.is_valid():
			on_complete.call()
		return
	if _landing_state != LandingState.AIRBORNE or _pending_land:
		return
	_land_on_complete = on_complete
	_try_start_landing()


## Begin a smooth ascent back to AERIAL_HEIGHT.  No-op unless the unit is
## GROUNDED_TEMP.  Also blocked when the unit grounded itself with a Land
## command (_permanently_grounded); use take_off_for_movement() in that case.
func take_off() -> void:
	if _landing_state != LandingState.GROUNDED_TEMP or _permanently_grounded:
		return
	_landing_state = LandingState.TAKING_OFF


## Like take_off() but also clears _permanently_grounded so a movement command
## can lift a unit that grounded itself with a Land command.
func take_off_for_movement() -> void:
	_permanently_grounded = false
	if _landing_state == LandingState.GROUNDED_TEMP:
		_landing_state = LandingState.TAKING_OFF


## Descend and remain grounded until a movement command is issued.  Sets
## _permanently_grounded so garrison auto-take-off is suppressed.
## Reverses a mid-ascent (TAKING_OFF → LANDING) so the command is always
## respected immediately.  Idempotent while already on the ground.
func land_permanently() -> void:
	_permanently_grounded = true
	if _pending_land:
		return  # already navigating to the safe landing spot
	match _landing_state:
		LandingState.AIRBORNE:
			_try_start_landing()
		LandingState.TAKING_OFF:
			# Mid-ascent reversal: go straight to LANDING and steer during descent
			# (no time to navigate first; the snap catches any remaining overshoot).
			_landing_state = LandingState.LANDING
			_compute_landing_correction()
		# LANDING, GROUNDED_TEMP: already heading to / at the ground; flag alone suffices.


## True while the unit is on the ground waiting (GROUNDED_TEMP state).
func is_grounded_temp() -> bool:
	return _landing_state == LandingState.GROUNDED_TEMP


## True when the unit was grounded by an explicit Land command (not by the
## garrison system).  Use this to gate the Land button's precondition.
func is_permanently_grounded() -> bool:
	return _permanently_grounded


## True while the unit is navigating to a safe landing position before descending.
func is_pending_land() -> bool:
	return _pending_land


## Abort pre-landing navigation (e.g. when the player issues a new command).
## The unit remains AIRBORNE and returns to normal command-driven movement.
func cancel_pending_land() -> void:
	_pending_land = false
	_has_landing_target = false
	_land_on_complete = Callable()
#endregion


## Navigate to the predicted touchdown position (or nearest passable cell if off
## navmesh) before descending.  If the predicted position is already passable,
## begin the descent immediately.  Called from land() and land_permanently().
func _try_start_landing() -> void:
	_compute_landing_correction()
	if _has_landing_target:
		_pending_land = true  # navigate first, then descend on arrival
	else:
		_landing_state = LandingState.LANDING  # safe to descend here directly

#region Navigation
func set_target_position(world_position: Vector3) -> void:
	target_position = world_position


func set_velocity(velocity: Vector3) -> void:
	# Suppress while landing/grounded or during pre-landing navigation (which is
	# driven by _physics_process and must not be overridden by the command system).
	if _landing_state == LandingState.LANDING \
			or _landing_state == LandingState.GROUNDED_TEMP \
			or _pending_land:
		return
	var v := _apply_accel_limits(velocity)
	if _landing_state == LandingState.TAKING_OFF and mode == Mode.HOVERING:
		v = _cap_xz_for_ascent(v)
	match mode:
		Mode.GROUNDED_DIRECT:
			if _nav_agent != null:
				_nav_agent.set_velocity(v)
		Mode.HOVERING, Mode.FLYING:
			# No avoidance system — emit the velocity directly so the entity
			# can apply it this same tick without waiting for a callback.
			_current_velocity = v
			velocity_ready.emit(v)
			_update_facing(v)


func is_navigation_finished() -> bool:
	# A temporarily grounded unit cannot navigate; treat it as "arrived" so
	# CommandReceiver skips the movement branch and checks can_act.
	# TAKING_OFF is intentionally excluded so an active movement command survives
	# until the unit is airborne (set_velocity is live during ascent).
	if _landing_state == LandingState.GROUNDED_TEMP:
		return true
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

#region FLYING dive-attack
## Ask a FLYING unit to dive toward `target_xz` (a world XZ) this tick: it descends from
## AERIAL_HEIGHT toward the ground as it closes within `dive_distance`. Call every tick the
## dive should continue (e.g. from Attack while a FLYING actor attacks a ground target) —
## the request self-clears, so the moment the calls stop the unit eases back up to cruise
## altitude. No-op outside FLYING mode.
func request_dive(target_xz: Vector2) -> void:
	if mode != Mode.FLYING:
		return
	_dive_requested = true
	_dive_target_xz = target_xz


## Per-tick FLYING altitude control, called from _physics_process. Eases
## _current_height_offset toward a target offset at LANDING_SPEED: AERIAL_HEIGHT while
## cruising, or — during a dive (request_dive() this tick) — an offset that scales with the
## unit's horizontal distance to the dive target (0 at the target, AERIAL_HEIGHT at or
## beyond dive_distance). So the unit drops as it bears down on the target and climbs back
## once the dive requests stop. Consumes (clears) _dive_requested.
func _update_flying_height() -> void:
	var desired: float = AERIAL_HEIGHT
	var parent := get_parent()
	if _dive_requested and parent is Node3D and dive_distance > 0.0:
		var dist: float = VU.inXZ((parent as Node3D).global_position).distance_to(_dive_target_xz)
		desired = AERIAL_HEIGHT * clampf(dist / dive_distance, 0.0, 1.0)
	_current_height_offset = move_toward(_current_height_offset, desired, LANDING_SPEED)
	_dive_requested = false
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
## unit's Map (hence its NavManager) is known — see Commandable.initialize. The
## navmesh wiring is a no-op in HOVERING mode, but _map is stored for all modes so
## HOVERING units can use it for the landing snap and ascent obstruction cap.
func configure_for_map(a_map: Map, nav_manager: NavManager, shape_radius: float) -> void:
	_map = a_map
	if mode != Mode.GROUNDED_DIRECT or _nav_agent == null or nav_manager == null:
		return
	set_agent_radius(shape_radius)
	nav_agent_class = NavAgentClass.class_for_radius(shape_radius)
	_nav_agent.navigation_layers = nav_manager.layer_for(nav_agent_class)


## World-units to add above the terrain surface when snapping Y.
## Commandable._on_velocity_computed and _physics_process both call this.
## For HOVERING and FLYING units this returns _current_height_offset, which is animated:
## HOVERING during LANDING (decreasing) / TAKING_OFF (increasing), and FLYING during a
## dive-attack descent / cruise-altitude climb (see _update_flying_height).
func height_offset() -> float:
	if mode == Mode.HOVERING:
		return _current_height_offset
	if mode == Mode.FLYING:
		return _current_height_offset
	return 0.0

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


## Rotate _facing toward the emitted velocity direction at turn_rate deg/s.
## Call after every velocity_ready.emit() in HOVERING mode so the body-facing
## direction stays consistent with what the physics actually produced.
## No-op when velocity is zero (facing persists through stops), when
## reverse_speed_ratio is 0 (facing not used), or in non-HOVERING modes.
func _update_facing(velocity: Vector3) -> void:
	if mode != Mode.HOVERING or reverse_speed_ratio <= 0.0 or velocity.is_zero_approx():
		return
	var target_dir := velocity.normalized()
	if _facing.is_zero_approx():
		_facing = target_dir  # first move: snap to initial direction
		return
	if turn_rate == INF:
		_facing = target_dir
		return
	var tps := float(Engine.physics_ticks_per_second)
	var max_angle := deg_to_rad(turn_rate) / tps
	var angle := _facing.angle_to(target_dir)
	if angle > max_angle:
		_facing = _facing.slerp(target_dir, max_angle / angle).normalized()
	else:
		_facing = target_dir


## Clamp the speed change from _current_velocity to desired within the
## per-tick budget derived from max_acceleration / max_deceleration.
## Also applies braking when is_final_leg is true and max_deceleration is
## bounded: caps desired speed to sqrt(2·|max_decel|·dist), the maximum speed
## from which the entity can decelerate to zero over the remaining distance.
func _apply_accel_limits(desired: Vector3) -> Vector3:
	# hovering_needs_alignment: old behaviour (reverse_speed_ratio == 0). The unit
	# must turn to face the target before accelerating; misalignment zeroes speed.
	# hovering_needs_facing: new helicopter behaviour (reverse_speed_ratio > 0 and
	# finite turn_rate). Speed is capped by body-facing alignment instead.
	# Both are false when turn_rate == INF, so the fast path still applies there.
	var hovering_needs_alignment: bool = mode == Mode.HOVERING \
			and reverse_speed_ratio == 0.0 \
			and not _current_velocity.is_zero_approx() \
			and not desired.is_zero_approx()
	var hovering_needs_facing: bool = mode == Mode.HOVERING \
			and reverse_speed_ratio > 0.0 \
			and turn_rate != INF \
			and not desired.is_zero_approx()
	if max_acceleration == INF and max_deceleration == -INF and turn_rate == INF \
			and not hovering_needs_alignment and not hovering_needs_facing:
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

	# Old alignment-zeroing (reverse_speed_ratio == 0): when the heading diverges
	# from the target, zero desired_speed so the unit must decelerate and turn
	# before re-accelerating. The turn-rate slerp on dir below curves the rotation.
	if hovering_needs_alignment:
		var alignment: float = _current_velocity.normalized().dot(desired.normalized())
		desired_speed *= maxf(0.0, alignment)

	# Helicopter-style facing cap (reverse_speed_ratio > 0, finite turn_rate).
	# Two phases:
	#   Phase 1 — unit is moving opposite to the desired direction: decelerate in
	#             the CURRENT direction so the emitted velocity stays physically
	#             correct (no instantaneous direction flip for bounded decel).
	#   Phase 2 — unit is stopped or already moving toward desired: cap speed by
	#             how well _facing (body nose) aligns with the desired direction.
	#             Forward (facing == desired): full speed. Backward: reverse_speed.
	var decelerate_in_current_dir: bool = false
	if hovering_needs_facing:
		var desired_dir := desired.normalized()
		if not _current_velocity.is_zero_approx() \
				and _current_velocity.normalized().dot(desired_dir) < 0.0:
			# Phase 1: braking opposite to desired. Zero the target speed and flag
			# the direction override so the delta clamping decelerates forward.
			desired_speed = 0.0
			decelerate_in_current_dir = true
		else:
			# Phase 2: apply the facing-based cap. Treat unset facing as aligned.
			var f := _facing if not _facing.is_zero_approx() else desired_dir
			var alignment := f.dot(desired_dir)
			desired_speed = minf(desired_speed, lerpf(
				speed * reverse_speed_ratio * tps,
				speed * tps,
				(alignment + 1.0) * 0.5))

	var speed_delta: float = desired_speed - current_speed

	var clamped_delta: float = clampf(
		speed_delta,
		max_deceleration / tps,  # negative bound (deceleration)
		max_acceleration / tps   # positive bound (acceleration)
	)
	var new_speed: float = maxf(0.0, current_speed + clamped_delta)

	if new_speed < 1e-4:
		return Vector3.ZERO

	# Direction: when decelerating for a reversal, keep the current heading so the
	# unit brakes forward rather than instantly emitting a backward velocity.
	var dir: Vector3
	if decelerate_in_current_dir and not _current_velocity.is_zero_approx():
		dir = _current_velocity.normalized()
	elif not desired.is_zero_approx():
		dir = desired.normalized()
	else:
		dir = _current_velocity.normalized()

	# Banking turn: limit heading change for smooth intermediate-waypoint curves.
	# Skipped for HOVERING with reverse_speed_ratio > 0 — velocity direction
	# changes freely and body-facing is tracked separately via _update_facing().
	if (mode == Mode.FLYING or (mode == Mode.HOVERING and reverse_speed_ratio == 0.0)) \
			and turn_rate != INF and not _current_velocity.is_zero_approx():
		var current_dir: Vector3 = _current_velocity.normalized()
		var max_angle: float = deg_to_rad(turn_rate) / tps
		var angle: float = current_dir.angle_to(dir)
		if angle > max_angle:
			dir = current_dir.slerp(dir, max_angle / angle).normalized()
	return dir * new_speed


func _on_velocity_computed(velocity: Vector3) -> void:
	_current_velocity = velocity
	velocity_ready.emit(velocity)


## Called before starting a descent. If the unit's current cell (or the predicted
## touchdown cell for a moving unit) is off the navmesh, BFS from the CURRENT cell
## to the nearest passable cell and store it as _landing_target. _try_start_landing
## then defers the descent until the unit has navigated there (_pending_land).
## TODO: landing target is sometimes placed beyond the obstruction rather than at the
## nearest navmesh edge to the predicted position. The nearest_navmesh_point query
## is correct in principle but the predicted world-Y (aerial height) may bias the 3D
## proximity search away from the correct edge — revisit with a terrain-height Y.
func _compute_landing_correction() -> void:
	_has_landing_target = false
	if _map == null or _map.terrain_grid == null:
		return
	var parent_node := get_parent() as Node3D
	if parent_node == null:
		return
	var pos_xz := Vector2(parent_node.global_position.x, parent_node.global_position.z)
	var current_cell: Vector2i = _map.world_to_grid(pos_xz)
	var current_passable: bool = _map.terrain_grid.is_passable(current_cell)

	# Predicted touchdown position: where velocity will carry the unit by the time
	# it descends from _current_height_offset to the ground.
	var tps: float = Engine.physics_ticks_per_second
	var time_to_land: float = _current_height_offset / LANDING_SPEED / tps
	var pred_xz: Vector2 = pos_xz \
		+ Vector2(_current_velocity.x, _current_velocity.z) * time_to_land

	if current_passable:
		if _current_velocity.is_zero_approx():
			return  # stationary over a passable cell — no correction needed
		var pred_cell: Vector2i = _map.world_to_grid(pred_xz)
		if _map.terrain_grid.is_passable(pred_cell):
			return  # predicted touchdown is also safe

	# Correction required. Query the navmesh for the closest valid landing point
	# to the predicted touchdown position — sends the unit toward the nearest
	# navmesh edge to where it would naturally end up, not where it currently is.
	var pred_world_pos := Vector3(pred_xz.x, parent_node.global_position.y, pred_xz.y)
	_landing_target = _map.nearest_navmesh_point(pred_world_pos)
	_has_landing_target = true


## BFS outward from `from` to the nearest in-bounds passable cell.
## Returns `from` unchanged only when the entire map is impassable (degenerate).
## Caller must have already verified _map and _map.terrain_grid are non-null.
func _nearest_passable_cell_to(from: Vector2i) -> Vector2i:
	if _map.terrain_grid.is_passable(from):
		return from
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = []
	queue.append(from)
	visited[from] = true
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if _map.terrain_grid.is_passable(cur):
			return cur
		for d: Vector2i in dirs:
			var nb: Vector2i = cur + d
			if not visited.has(nb) and _map.terrain_grid.is_in_bounds(nb):
				visited[nb] = true
				queue.append(nb)
	return from


## Last-resort teleport if steering during descent still landed off the navmesh.
## Called at the LANDING → GROUNDED_TEMP transition after _has_landing_target is cleared.
func _snap_to_navmesh() -> void:
	if _map == null or _map.terrain_grid == null:
		return
	var parent_node := get_parent() as Node3D
	if parent_node == null:
		return
	var pos_xz := Vector2(parent_node.global_position.x, parent_node.global_position.z)
	var cell: Vector2i = _map.world_to_grid(pos_xz)
	if _map.terrain_grid.is_passable(cell):
		return
	var found: Vector2i = _nearest_passable_cell_to(cell)
	if not _map.terrain_grid.is_passable(found):
		return
	var world: Vector3 = _map.grid_to_world(found)
	parent_node.global_position = Vector3(world.x, parent_node.global_position.y, world.z)


## Cap the XZ speed of `v` so the unit cannot enter a building-occupied (or
## out-of-bounds) cell before it has finished ascending to AERIAL_HEIGHT.
##
## Works by marching a DDA ray through the grid in the velocity direction.
## If a blocked cell is found at distance `d` (world units), the XZ speed is
## capped to d / ticks_remaining_in_seconds — the maximum speed that keeps the
## unit clear of the obstruction until it clears the building height.
func _cap_xz_for_ascent(v: Vector3) -> Vector3:
	if _map == null or _map.terrain_grid == null or _map.height_map == null:
		return v
	var xz := Vector2(v.x, v.z)
	if xz.is_zero_approx():
		return v
	var speed := xz.length()
	var dir := xz.normalized()
	var ticks_remaining: float = (AERIAL_HEIGHT - _current_height_offset) / LANDING_SPEED
	if ticks_remaining <= 0.0:
		return v
	var tps: float = Engine.physics_ticks_per_second
	var max_dist: float = speed * ticks_remaining / tps

	var parent_node := get_parent() as Node3D
	if parent_node == null:
		return v
	var pos_xz := Vector2(parent_node.global_position.x, parent_node.global_position.z)

	# Convert world XZ to fractional cell space for DDA.
	# Cell (gx, gz) occupies [gx, gx+1) in cell space.
	var inv := _map.global_transform.affine_inverse()
	var hw: float = (_map.height_map.map_width - 1) * 0.5
	var hd: float = (_map.height_map.map_depth - 1) * 0.5
	var local_pos := inv * Vector3(pos_xz.x, 0.0, pos_xz.y)
	var lx: float = local_pos.x + hw
	var lz: float = local_pos.z + hd
	var cur_x: int = floori(lx)
	var cur_z: int = floori(lz)

	# Transform the world-space direction through the map's inverse basis so DDA
	# t-values are in map-local units (= world units when map scale = CELL_SIZE).
	var local_dir := inv.basis * Vector3(dir.x, 0.0, dir.y)
	var dx: float = local_dir.x
	var dz: float = local_dir.z

	var step_x: int = 1 if dx >= 0.0 else -1
	var step_z: int = 1 if dz >= 0.0 else -1

	# t-distance (local units) to each axis's first boundary, then per-cell step.
	var frac_x: float = lx - cur_x
	var frac_z: float = lz - cur_z
	var t_max_x: float = ((1.0 - frac_x) / dx) if dx > 1e-6 else \
						 (frac_x / -dx)          if dx < -1e-6 else INF
	var t_max_z: float = ((1.0 - frac_z) / dz) if dz > 1e-6 else \
						 (frac_z / -dz)          if dz < -1e-6 else INF
	var t_delta_x: float = (1.0 / absf(dx)) if absf(dx) > 1e-6 else INF
	var t_delta_z: float = (1.0 / absf(dz)) if absf(dz) > 1e-6 else INF

	while true:
		var t: float
		if t_max_x < t_max_z:
			t = t_max_x
			cur_x += step_x
			t_max_x += t_delta_x
		else:
			t = t_max_z
			cur_z += step_z
			t_max_z += t_delta_z
		if t >= max_dist:
			break
		var next_cell := Vector2i(cur_x, cur_z)
		if not _map.terrain_grid.is_in_bounds(next_cell) \
				or _map.terrain_grid.is_building_at(next_cell):
			var t_seconds: float = ticks_remaining / tps
			var capped_speed: float = t / t_seconds if t_seconds > 1e-6 else 0.0
			return Vector3(dir.x * capped_speed, v.y, dir.y * capped_speed)
	return v
#endregion
