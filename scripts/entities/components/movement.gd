class_name Movement
extends Locomotion

## The NAVIGATED locomotion strategy — wraps a NavigationAgent3D for a piece on the ground, or
## drives straight at its goal for a piece that flies. Drivers set a goal and call `tick` (see
## Locomotion); the path, braking and what a unit that cannot stop does instead are decided
## here, in #region Locomotion strategy.
##
## Flight itself — height, landing, the deck, the dive, the idle orbit — is the sibling
## `Aerial` component's, whose presence also decides `mode`. This keeps horizontal
## goal-seeking and the velocity pipeline both share; #region Aerial drive is the narrow
## interface Aerial steers through when it moves the piece itself.

#region Signals
signal velocity_ready(velocity: Vector3)
#endregion

#region Constants
## XZ arrival radius for HOVERING / FLYING modes (mirrors NavigationAgent3D's
## target_desired_distance used in GROUNDED mode).
const HOVERING_ARRIVAL_DISTANCE: float = 0.125

## Parachute descent (see begin_parachute_descent). A unit released in mid-air by an air
## transport hangs under a canopy and floats down; these are the two numbers that shape it.
##
## PARACHUTE_GRAVITY is emphatically NOT Earth's g — this is a canopy, and the drop has to
## read as a slow float rather than a fall. PARACHUTE_TERMINAL_SPEED is the rate it settles
## at, reached about half a second in, and is what actually decides how long a drop takes:
## from a transport's cruise altitude (Aerial.AERIAL_HEIGHT) it is a little over three seconds.
const PARACHUTE_GRAVITY: float = 4.0
const PARACHUTE_TERMINAL_SPEED: float = 2.0

## Tolerance (radians) for is_facing() to treat the owner's rotation.y as
## "caught up" with a face_toward() target.
const _FACING_ALIGNMENT_EPSILON: float = 0.001
#endregion

#region Properties
## How the piece moves: on the ground, or which kind of flight. The locomotion vocabulary the
## rest of the game reads (garrison admission, the command grid, visuals); the value lives on
## the Aerial component, and a piece without one is GROUNDED.
enum Mode { GROUNDED = 0x0, HOVERING = 0x10, FLYING = 0x11 }

var mode: Mode:
	get:
		var aerial: Aerial = _aerial()
		return aerial.mode if aerial != null else Mode.GROUNDED

## Crush size classes (see can_crush()). Independent of nav_agent_class (navmesh
## erosion) and the body's real bounding_radius — this is purely the crush-eligibility
## tier, authored per unit type.
enum CrushClass { TINY = 0, SMALL = 1, MEDIUM = 2, LARGE = 3, HUGE = 4 }

## Set in the inspector to size this unit for the crush mechanic (see can_crush()).
@export var crush_class: CrushClass = CrushClass.SMALL

# --- Shared across all modes (ungrouped) ---

## Maximum rate at which the entity's speed may increase, in world-units/s².
## INF (default) means speed can jump to any value instantly.
@export var max_acceleration: float = INF

## Maximum rate at which the entity's speed may decrease, in world-units/s².
## Must be ≤ 0; -INF (default) means speed can drop to any value instantly.
@export var max_deceleration: float = -INF

## Movement speed in world-units per second.
@export var speed: float = 3.75

## Temporary override for commanded travel speed, in world-units per second. 0.0
## (default) means uncapped — use `speed` as normal. Set by a group move order
## (see RTSController.assign_command_to_units) so a mixed-speed selection travels
## at its slowest member's pace; cleared back to 0.0 when that unit's MoveCommand
## is destroyed (see MoveCommand._notification).
var speed_cap: float = 0.0

## Maximum rate at which the entity's heading may change, in degrees per second.
## HOVERING/FLYING: limits banking turns in _apply_accel_limits.
## GROUNDED: limits facing rotation before velocity reflects the new direction.
## INF (default) means no limit — the body snaps to face its heading instantly.
@export var turn_rate: float = INF

@export_group("Grounded")
## Path (relative to this Movement node) to the NavigationAgent3D used in
## GROUNDED mode. Ignored in HOVERING mode.
@export var nav_agent_path: NodePath

## GROUNDED only. The speed the unit holds while it is still rotating
## toward a new heading, as a fraction of its current commanded speed. It applies
## for the whole turn (not just the part where the target is behind): until the
## nose is aligned the unit travels at min_turn_speed_ratio of its desired speed —
## forward when the destination is ahead, in reverse when it is behind. Once
## aligned it drives straight at full speed.
##   0.0 (default) — no translation while turning: the unit pivots in place and
##                   only then sets off in a straight line, with no curved
##                   approach (infantry-style).
##   0.3–0.5       — the unit must keep rolling while it reorients, backing up to
##                   swing around — three-point turns (vehicle-style, C&C Generals).
##   1.0           — full-speed arcs: the unit never slows to turn, curving onto
##                   the new heading at speed.
## Ignored when turn_rate is INF (instant turning) or in aerial modes.
@export var min_turn_speed_ratio: float = 0.0

@export_group("Hovering")
## Fraction of max speed available when moving directly opposite to the current
## body-facing direction (180° reversal). 0.0 (default) preserves the existing
## behaviour — the unit must rotate to face the target before accelerating. A
## value around 0.35 matches real helicopter reverse-flight limits (~35% of
## forward speed) and lets the unit slide backward while the fuselage rotates
## to catch up. Only meaningful in HOVERING mode with a finite turn_rate; units
## with turn_rate = INF can always reach full speed in any direction.
@export var reverse_speed_ratio: float = 0.35

# --- Internal state (not exported) ---

## Collision size class — which space-eroded navmesh this unit navigates on (see
## NavAgentClass / gdd/systems/terrain-and-navigation/agent-size-classes.md). NOT authored:
## configure_for_map()
## derives it from the unit's MovementBody footprint radius (the smallest class
## large enough for the body), so it always matches the unit's real size.
var nav_agent_class: NavAgentClass.Size = NavAgentClass.Size.MEDIUM

var _nav_agent: NavigationAgent3D

## The unit's path, queried and followed here (#region Path following) rather than by the agent,
## which is kept for avoidance only. Empty until a target is submitted, and after a query that
## found no route.
var _path: PackedVector3Array = PackedVector3Array()
var _path_index: int = 0
## The agent's own three state flags, mirrored so arrival behaves exactly as it did.
var _is_target_submitted: bool = false
var _is_path_finished: bool = true
var _is_last_waypoint_reached: bool = false
## The newest navmesh change (NavManager.NavChange serial) this path has been checked against.
var _path_change_serial: int = 0
## Set by configure_for_map. Null in a rig with no NavManager, which then re-plans on no change.
var _nav_manager: NavManager = null
## Reused for every query: pooled because a moving unit may query every tick while it chases.
var _path_query: NavigationPathQueryParameters3D = null
var _path_result: NavigationPathQueryResult3D = null

## Stores the current target for HOVERING / FLYING modes (no NavAgent).
var _hovering_target: Vector3 = Vector3.ZERO

## Velocity actually emitted last tick — used to compute the speed delta for
## acceleration/deceleration clamping. For GROUNDED mode this is the
## avoidance-adjusted value, keeping the budget honest.
var _current_velocity: Vector3 = Vector3.ZERO

## Parachute-descent state (see the region of the same name below). Live only between a
## begin_parachute_descent and its touchdown, which is the whole life of a dropped unit's
## fall — every other unit in the game carries these three fields inert.
var _is_parachuting: bool = false
## Height still to fall, world units. This IS the unit's height while descending.
var _parachute_altitude: float = 0.0
## Current descent rate, world-units/second, ramping to PARACHUTE_TERMINAL_SPEED.
var _parachute_rate: float = 0.0
## Fired once, at touchdown. What the caller uses to take the canopy away again.
var _parachute_landed: Callable = Callable()

## Map reference used for the string-pull line test. Set by configure_for_map(); null until
## then.
var _map: Map = null

## The sibling Aerial component, or null, cached once the piece is in the tree. Resolved lazily
## rather than in _ready so an out-of-tree instance (a build preview, an importer's scene read)
## still reports its mode. A piece's components are fixed once it enters the tree — flight is
## never bolted on or taken off at runtime — which is what makes the cache safe.
var _aerial_node: Aerial = null
var _aerial_resolved: bool = false

## True when the current movement leg is the entity's last queued destination
## (no commands follow in the queue). Set each tick by CommandReceiver; used
## to trigger braking so the entity decelerates to a halt at the target instead
## of arriving at full speed and snapping to a stop.
var is_final_leg: bool = false

var target_position: Vector3:
	get:
		match mode:
			Mode.GROUNDED:
				return _nav_agent.target_position if _nav_agent != null else Vector3.ZERO
			Mode.HOVERING, Mode.FLYING:
				return _hovering_target
		return Vector3.ZERO
	set(value):
		match mode:
			Mode.GROUNDED:
				if _nav_agent != null:
					_submit_target(value)
			Mode.HOVERING, Mode.FLYING:
				_hovering_target = value
#endregion


#region Lifecycle
func _ready() -> void:
	if mode != Mode.GROUNDED:
		return
	if not nav_agent_path.is_empty():
		_nav_agent = get_node_or_null(nav_agent_path) as NavigationAgent3D
	if _nav_agent != null:
		_nav_agent.velocity_computed.connect(_on_velocity_computed)


## A unit under a canopy is doing exactly one thing: falling. Everything about flight is
## Aerial's, which ticks after this in tree order.
func _physics_process(_a_delta: float) -> void:
	if _is_parachuting:
		_tick_parachute()


#endregion


#region Locomotion strategy
func can_move() -> bool:
	return is_active and speed > 0.0


## A navigated goal primes the agent's target AT ONCE: a fresh agent reports its navigation
## finished, so a command checked before the next tick would read as already arrived.
func set_goal(
	a_position: Vector3, a_arrival: Arrival = Arrival.STOP, a_entity: Entity = null
) -> void:
	super.set_goal(a_position, a_arrival, a_entity)
	if target_position != a_position:
		set_target_position(a_position)


## Steer toward the goal for one tick. Against a pursued piece it HOLDS — still pursuing, not
## moving — so a follower does not shove into the unit it follows. Braking is armed only when
## the goal asks to STOP, and never for a FLYING unit, which approaches at full speed and
## eases into its orbit instead.
func tick() -> Progress:
	var pursued: Entity = goal_entity()
	if pursued != null and _body_touches(pursued):
		stop()
		return Progress.HOLDING
	if is_navigation_finished():
		return Progress.ARRIVED
	is_final_leg = goal_arrival == Arrival.STOP and mode != Mode.FLYING
	set_velocity(velocity_toward_next_path_position())
	return Progress.MOVING


## A FLYING unit cannot stop, so arriving at a place starts an orbit around where it is; one
## pursuing a piece, and anything that can stop, simply takes its own position as the target.
func arrive() -> void:
	is_final_leg = false
	if mode == Mode.FLYING and goal_entity() == null:
		_aerial().set_anchor(_owner_node().global_position)
		set_velocity(_aerial().compute_orbit_velocity())
		return
	set_target_position(_owner_node().global_position)


func stop() -> void:
	is_final_leg = false
	set_velocity(Vector3.ZERO)


## A FLYING unit orbits `a_anchor` — the last place its goal was — or keeps its current
## circuit when there is none; anything else stops.
func settle(a_anchor: Variant = null) -> void:
	is_final_leg = false
	if mode != Mode.FLYING:
		set_velocity(Vector3.ZERO)
		return
	if a_anchor is Vector3:
		_aerial().set_anchor(a_anchor)
	set_velocity(_aerial().compute_orbit_velocity())


## Full-speed velocity toward the next path point, flattened to XZ so RVO avoidance receives a
## clean 2D input; vertical terrain tracking is Commandable's, per tick.
func velocity_toward_next_path_position() -> Vector3:
	var owner_node: Node3D = _owner_node()
	var velocity: Vector3 = (
		owner_node.global_position.direction_to(get_next_path_position()) * effective_max_speed()
	)
	velocity.y = 0.0
	return velocity


## Whether this piece's MOVEMENT_OBSTRUCTION body would overlap `a_other`'s — centre-to-centre
## XZ distance within the sum of their body radii.
func _body_touches(a_other: Entity) -> bool:
	var me: Entity = _owner_node() as Entity
	var gap: float = VU.in_xz(me.global_position).distance_to(VU.in_xz(a_other.global_position))
	var reach: float = (
		me.bounding_radius(CollisionLayers.Mask.MOVEMENT_OBSTRUCTION)
		+ a_other.bounding_radius(CollisionLayers.Mask.MOVEMENT_OBSTRUCTION)
	)
	return gap <= reach


#endregion


#region Parachute descent
## Release this unit [a_altitude] world-units above the ground, to float down under a canopy
## and resume ordinary movement where it touches down. [a_on_landed] fires once, at touchdown
## — including IMMEDIATELY when the unit is refused, so a caller's cleanup never has to ask
## which kind of unit it just released.
##
## A STATE ON GROUNDED rather than a fourth `Mode`, which is why anything that is not
## GROUNDED is refused: an aircraft tipped out of a transport flies away, it does not
## fall. Why that shape, and why targeting is the one reader that does not follow `mode`:
## gdd/systems/macroeconomics/sanctions/off-map-abilities.md §Parachute descent is a STATE.
func begin_parachute_descent(a_altitude: float, a_on_landed: Callable) -> void:
	if mode != Mode.GROUNDED or a_altitude <= 0.0:
		if a_on_landed.is_valid():
			a_on_landed.call()
		return
	_is_parachuting = true
	_parachute_altitude = a_altitude
	_parachute_rate = 0.0
	_parachute_landed = a_on_landed


## Whether this unit is still on its way down. The gate on command processing (see
## CommandReceiver._process_commands): a unit under a canopy has no say in where it goes.
func is_parachuting() -> bool:
	return _is_parachuting


## Advance the descent one tick: ramp the rate toward terminal, spend it against the
## remaining altitude, and land when there is none left.
##
## The callback is cleared BEFORE it is called, so a callback that starts a second descent
## (or frees the canopy and something else re-drops the unit) cannot be run twice by the
## same touchdown.
func _tick_parachute() -> void:
	var dt: float = 1.0 / TimeUtils.ticks_per_second()
	_parachute_rate = minf(_parachute_rate + PARACHUTE_GRAVITY * dt, PARACHUTE_TERMINAL_SPEED)
	_parachute_altitude -= _parachute_rate * dt
	if _parachute_altitude > 0.0:
		return
	_parachute_altitude = 0.0
	_parachute_rate = 0.0
	_is_parachuting = false
	var landed: Callable = _parachute_landed
	_parachute_landed = Callable()
	if landed.is_valid():
		landed.call()


#endregion
#region Navigation
## The travel speed CommandReceiver should drive toward: speed_cap when a group
## move has capped it, otherwise the unit's own speed.
func effective_max_speed() -> float:
	return speed_cap if speed_cap > 0.0 else speed


## The turn rate to steer and point at this tick, in degrees/second. Normally the authored
## turn_rate; an aircraft may sharpen it (Aerial.turn_rate_multiplier — a committed dive's
## terminal guidance). INF stays INF — an already-instant turn cannot be sharpened.
func _effective_turn_rate() -> float:
	var aerial: Aerial = _aerial()
	if turn_rate == INF or aerial == null:
		return turn_rate
	return turn_rate * aerial.turn_rate_multiplier()


func set_target_position(a_world_position: Vector3) -> void:
	target_position = a_world_position


## Drive the piece at `a_velocity` under its acceleration and turn limits. A commanded velocity
## is refused while the piece is under a canopy, and while its Aerial is flying a manoeuvre of
## its own (Aerial.suppresses_commanded_velocity).
func set_velocity(a_velocity: Vector3) -> void:
	var aerial: Aerial = _aerial()
	if _is_parachuting or (aerial != null and aerial.suppresses_commanded_velocity()):
		return
	var v := _apply_accel_limits(a_velocity)
	if aerial != null:
		v = aerial.shape_commanded_velocity(v)
	match mode:
		Mode.GROUNDED:
			# The agent passes a velocity on to avoidance only while it is heading somewhere;
			# once its path is finished it holds still until the next target, as the engine's
			# own agent did.
			if _nav_agent != null and _is_target_submitted:
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
	var aerial: Aerial = _aerial()
	if aerial != null and aerial.is_grounded_temp():
		return true
	match mode:
		Mode.GROUNDED:
			if _nav_agent == null:
				return true
			_update_path()
			return _is_path_finished
		Mode.HOVERING, Mode.FLYING:
			var pos_xz := Vector2(get_parent().global_position.x, get_parent().global_position.z)
			var tgt_xz := Vector2(_hovering_target.x, _hovering_target.z)
			return (
				pos_xz.distance_squared_to(tgt_xz)
				< HOVERING_ARRIVAL_DISTANCE * HOVERING_ARRIVAL_DISTANCE
			)
	return true


#region Aerial drive
## The velocity actually emitted last tick.
func current_velocity() -> Vector3:
	return _current_velocity


## Steer at `a_desired` under the acceleration and turn limits and emit the result, whatever
## the command suppression says — for a manoeuvre Aerial is flying itself.
func drive(a_desired: Vector3) -> void:
	_current_velocity = _apply_accel_limits(a_desired)
	velocity_ready.emit(_current_velocity)
	_update_facing(_current_velocity)


## Emit `a_velocity` exactly, with no limits and no turn toward it.
func emit_velocity(a_velocity: Vector3) -> void:
	_current_velocity = a_velocity
	velocity_ready.emit(a_velocity)


## Record `a_velocity` as what the piece is doing, without emitting it — for motion Aerial
## applies by position (a taxi), whose velocity only seeds what comes next.
func set_current_velocity(a_velocity: Vector3) -> void:
	_current_velocity = a_velocity


## Height still to fall under a canopy, or 0 when not descending.
func descent_altitude() -> float:
	return _parachute_altitude if _is_parachuting else 0.0


#endregion


func get_next_path_position() -> Vector3:
	match mode:
		Mode.GROUNDED:
			if _nav_agent == null:
				return Vector3.ZERO
			# Always asked, even when string-pulling: this is what advances the cursor along the
			# path, and skipping it would leave the unit permanently on waypoint 0.
			var next: Vector3 = _next_path_position()
			if not string_pull:
				return next
			var pulled: Vector3 = _string_pulled_target()
			return next if pulled == Vector3.INF else pulled
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

#region Crush
## How many CrushClass tiers a unit must outrank another by to crush it. Two, not
## one, so crushing is reserved for a clear size mismatch — e.g. LARGE crushes
## TINY/SMALL but not MEDIUM.
const CRUSH_CLASS_GAP: int = 2


## True when this unit can crush (instant-kill on contact, and steer through rather
## than avoid) `other`.
##
## Crushing is a GROUND mechanic: it models weight bearing down on something underfoot,
## which is meaningless once either party is flying. So an aerial unit (HOVERING or
## FLYING) neither crushes nor is crushed, whatever the two size classes are — a gunship
## does not squash the infantry it passes over, and a heavy vehicle does not squash the
## gunship. The check is on the MODE, not on altitude: a HOVERING unit sitting on the
## ground during a temporary landing is still an aircraft, and grinding it to death under
## a passing truck is not the behaviour we want either.
func can_crush(a_other: Movement) -> bool:
	if is_aerial_mode() or a_other.is_aerial_mode():
		return false
	return int(crush_class) >= int(a_other.crush_class) + CRUSH_CLASS_GAP


## True when this unit outranks the SMALLEST class by the crush gap — i.e. there is
## some unit it could crush. Lets Commandable skip the whole per-tick crush scan for
## the majority of units, which can never crush anything whatever is next to them.
## Aerial units are excluded wholesale for the reason above, which also spares them the
## scan entirely.
func can_crush_anything() -> bool:
	if is_aerial_mode():
		return false
	return int(crush_class) >= int(CrushClass.TINY) + CRUSH_CLASS_GAP


#endregion

#region RVO avoidance
## RVO avoidance notes: every agent broadcasts on a shared channel and avoids
## everyone (mask = ALL); the avoidance layers do NOT encode teams. The
## "enemies don't get out of our way" requirement is upheld by the command loop,
## not the mask: only commanded, moving units apply an avoidance velocity, so
## idle enemy units never reposition to accommodate us. Per-pair exemptions (a
## unit following another) are handled by AvoidanceAgent3D exceptions, driven via
## set_avoidance_follow_target() below.

## Whether this component is LIVE. An inactive Movement is dormant rather than absent: it
## keeps its authored stats, but drives nothing, holds no avoidance entry and reads as null
## through Entity.movement. Switched only by Entity.set_deployed, for a two-form piece.
var is_active: bool = true


## Switch this component on or off. Off gives back what it holds outside itself — the RVO
## avoidance entry and the obstacle broadcast — and stops it driving the body. On re-arms
## avoidance for `a_commander_id`'s team; an unowned piece (id 0 or less) is armed later,
## by ownership, as every piece is.
func set_active(a_active: bool, a_commander_id: int) -> void:
	if a_active == is_active:
		return
	is_active = a_active
	set_physics_process(a_active)
	_current_velocity = Vector3.ZERO
	if avoidance_obstacle != null:
		avoidance_obstacle.avoidance_enabled = a_active
	if _nav_agent == null:
		return
	if a_active:
		if a_commander_id > 0:
			enable_avoidance(a_commander_id)
	else:
		_nav_agent.avoidance_enabled = false
		var body := get_parent() as Node3D
		if body != null and body.is_inside_tree():
			_submit_target(body.global_position)


## Saved avoidance_layers value while suppression is active; 0 means not suppressed.
var _saved_avoidance_layers: int = 0
## Saved obstacle avoidance_layers while suppression is active; 0 means not suppressed.
var _saved_obstacle_layers: int = 0

## NavigationObstacle3D that broadcasts this unit as an obstacle for cross-team
## one-sided avoidance. Assigned by Commandable._ready after both nodes exist.
var avoidance_obstacle: NavigationObstacle3D = null

## The commandable this unit currently ignores in RVO — the one it is following, or the
## other half of a garrison order (see CommandReceiver._avoidance_exception_target).
## null = none. Untyped because the unit it names can be freed while it is held, and a freed
## object fails a typed read or parameter (CLAUDE.md §A freed object cannot be passed to a
## typed parameter); `_follow_agent` validates it.
var _avoidance_follow: Variant = null


## The NavigationAgent3D as an AvoidanceAgent3D, or null if it isn't one (e.g. a
## plain agent in a unit test). Gates the per-pair avoidance-exception API.
func avoidance_agent() -> AvoidanceAgent3D:
	return _nav_agent as AvoidanceAgent3D


## Turn on RVO avoidance for `commander_id`'s team. Called once ownership is
## established. Each commander owns one avoidance team bit; a unit avoids its own
## team (and any agent currently in a per-pair exception) — see AvoidanceAgent3D.
func enable_avoidance(a_commander_id: int) -> void:
	var agent := avoidance_agent()
	if mode == Mode.GROUNDED and agent != null:
		agent.enable_avoidance(a_commander_id)


## Avoidance priority for a unit standing its ground to fire. The engine's ceiling, so it
## gives way to nobody and the units behind it must be walked clear by the player.
const AVOIDANCE_PRIORITY_ENGAGED: float = 1.0
## Avoidance priority for a unit that is actually going somewhere. Only its ORDER against
## the other two tiers matters; it sits between them.
const AVOIDANCE_PRIORITY_TRAVELLING: float = 0.75
## Avoidance priority for a unit that is standing still with nothing to hold ground for.
const AVOIDANCE_PRIORITY_STANDING: float = 0.5


## Rank this unit in same-team RVO: ENGAGED above TRAVELLING above STANDING. Called every
## tick from Commandable._physics_process, which says whether the current order is holding
## ground (MoveCommand.holds_ground).
##
## Why it works this way:
## gdd/systems/terrain-and-navigation/navigation-and-pathing.md §Avoidance priority.
func update_avoidance_priority(a_is_holding_ground: bool) -> void:
	var agent := avoidance_agent()
	if mode != Mode.GROUNDED or agent == null:
		return
	if a_is_holding_ground:
		agent.avoidance_priority = AVOIDANCE_PRIORITY_ENGAGED
	elif is_navigation_finished():
		agent.avoidance_priority = AVOIDANCE_PRIORITY_STANDING
	else:
		agent.avoidance_priority = AVOIDANCE_PRIORITY_TRAVELLING


## Make this unit and `other` ignore each other in RVO (used while following a unit, and
## while the two halves of a garrison order close with each other), leaving all their other
## avoidance interactions intact. Passing a
## different target (or null) drops the previous exception first, so this can be
## driven straight from the per-tick command state. No-op in HOVERING mode or when
## either side lacks an AvoidanceAgent3D.
func set_avoidance_follow_target(a_other: Commandable) -> void:
	var agent := avoidance_agent()
	if mode != Mode.GROUNDED or agent == null or a_other == _avoidance_follow:
		return
	var prev: AvoidanceAgent3D = _follow_agent(_avoidance_follow)
	if prev != null:
		agent.remove_avoidance_exception_with(prev)
	_avoidance_follow = a_other
	var next: AvoidanceAgent3D = _follow_agent(a_other)
	if next != null:
		agent.add_avoidance_exception_with(next)


## `a_c`'s avoidance agent, or null for nothing, a freed piece or one with no movement. Untyped
## for the reason `_avoidance_follow` is.
func _follow_agent(a_c: Variant) -> AvoidanceAgent3D:
	if not is_instance_valid(a_c) or not (a_c is Commandable) or a_c.movement == null:
		return null
	return (a_c as Commandable).movement.avoidance_agent()


## Zero this agent's broadcast layers and its obstacle layers so no other agent
## RVO-steers around it. Used by Occupy to let the approaching unit walk into
## the garrison target without the avoidance system pushing them apart.
## No-op if already suppressed or in HOVERING mode.
func suppress_avoidance_layers() -> void:
	if mode != Mode.GROUNDED or _nav_agent == null or _saved_avoidance_layers != 0:
		return
	_saved_avoidance_layers = _nav_agent.avoidance_layers
	_nav_agent.avoidance_layers = 0
	if avoidance_obstacle != null and avoidance_obstacle.avoidance_enabled:
		_saved_obstacle_layers = avoidance_obstacle.avoidance_layers
		avoidance_obstacle.avoidance_layers = 0


## Restore the avoidance_layers cleared by suppress_avoidance_layers.
func restore_avoidance_layers() -> void:
	if mode != Mode.GROUNDED or _nav_agent == null or _saved_avoidance_layers == 0:
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
	if mode == Mode.GROUNDED and _nav_agent != null and a_radius > 0.0:
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
## A* polygon budget per path query. Godot defaults NavigationAgent3D to 4096, which is FEWER
## POLYGONS THAN THIS GAME'S NAVMESH HAS: one quad per cell means an s1-sized map bakes ~12,500
## polygons per agent class. Any path forced to detour around a sizeable obstacle exhausts the
## budget — and the server then returns a PARTIAL path rather than an error, so the unit walks
## as far as the search got and stops, which reads exactly like "it refuses to path around the
## mountain".
##
## Measured on a 159x159 map, ground to a plateau top reachable only by a ramp on the far side:
## at the default budget the query came back 43 points long, ending 17.2 units short at the
## base of the cliff; raised, the same query returned 109 points ending exactly on target.
##
## Raising it is close to free: it is a CAP, not a preallocation, so a short path still explores
## only what it needs. Sized well past any single map's polygon count so the cap is never the
## thing that decides whether a route exists.
const PATH_SEARCH_MAX_POLYGONS: int = 1 << 16


func configure_for_map(a_map: Map, a_nav_manager: NavManager, a_shape_radius: float) -> void:
	_map = a_map
	_nav_manager = a_nav_manager
	if mode != Mode.GROUNDED or _nav_agent == null or a_nav_manager == null:
		return
	set_agent_radius(a_shape_radius)
	nav_agent_class = NavAgentClass.class_for_radius(a_shape_radius, Map.CELL_SIZE)
	_nav_agent.navigation_layers = a_nav_manager.layer_for(nav_agent_class)
	_nav_agent.path_search_max_polygons = PATH_SEARCH_MAX_POLYGONS


## The tightest circle this unit can fly at cruise, in world units. 0 for an instant turn.
## Used to size manoeuvres that have to be flown rather than assumed — a lineup leg is only
## as long as the turn onto it needs.
func turn_radius() -> float:
	if turn_rate == INF or turn_rate <= 0.0:
		return 0.0
	return speed / deg_to_rad(turn_rate)


## Whether this locomotion mode can come to a dead stop and stay there.
##
## FLYING cannot: a fixed wing that stopped in mid-air would be a helicopter, and it has no
## hover to do it with. Everything else can — a ground unit plants its feet, and a HOVERING
## gunship holds station, which is the whole difference between the two aerial modes.
##
## Read by CommandReceiver, which otherwise zeroes an actor's velocity the moment it acts.
## For a ground unit stopping to shoot is right; for an aeroplane it froze it in the sky
## over its target, and it is why an attack run had no run in it.
func can_hold_still() -> bool:
	var aerial: Aerial = _aerial()
	return aerial == null or aerial.can_hold_still()


## Whether the piece flies — has a sibling Aerial. Internal to the velocity pipeline, which
## drives a flying piece straight at its goal; everything else asks the piece for its Aerial.
func is_aerial_mode() -> bool:
	return _aerial() != null


## The sibling Aerial component, or null for a piece on the ground.
func _aerial() -> Aerial:
	if _aerial_resolved:
		return _aerial_node
	var host: Node = get_parent()
	_aerial_node = host.get_node_or_null("Aerial") as Aerial if host != null else null
	_aerial_resolved = is_inside_tree()
	return _aerial_node


## Straight-line distance from the parent entity to its current movement target.
## HOVERING/FLYING: XZ-only, matching is_navigation_finished. GROUNDED: 3D
## distance to the nav target, used as an approximation of remaining path length.
func _distance_to_target() -> float:
	match mode:
		Mode.HOVERING, Mode.FLYING:
			var pos_xz := Vector2(get_parent().global_position.x, get_parent().global_position.z)
			var tgt_xz := Vector2(_hovering_target.x, _hovering_target.z)
			return pos_xz.distance_to(tgt_xz)
		Mode.GROUNDED:
			if _nav_agent != null:
				return get_parent().global_position.distance_to(_nav_agent.target_position)
	return 0.0


## Rotate the owner node's rotation.y toward the emitted velocity direction at
## turn_rate deg/s. Call after every velocity_ready.emit() in HOVERING/FLYING
## mode so the body-facing direction (rotation.y — see get_facing()) stays
## consistent with what the physics actually produced. No-op when velocity is
## zero (facing persists through stops) or in GROUNDED mode (turn
## handled by _apply_grounded_turn instead).
func _update_facing(a_velocity: Vector3) -> void:
	if mode == Mode.GROUNDED or a_velocity.is_zero_approx():
		return
	turn_toward(a_velocity)


## The Node3D whose rotation.y is this Movement's single source of truth for
## facing direction — its parent in the scene tree. null in unit tests that
## add a Movement under a plain Node.
func _owner_node() -> Node3D:
	return get_parent() as Node3D


## The unit's current XZ facing direction, derived from the owner node's
## rotation.y. Drop-in replacement for the old _facing field for any external
## caller. Uses the owner node's +Z axis as "forward": our models are authored
## facing -Y in Blender, which the glTF importer maps to +Z in Godot (NOT the
## engine's own -Z forward), so +Z is the visual front of the mesh and the
## root's rotation.y orients it directly. Defaults to (0, 0, 1) (rotation.y ==
## 0) when there's no owner Node3D.
func get_facing() -> Vector3:
	var owner_node: Node3D = _owner_node()
	if owner_node == null:
		return Vector3(0, 0, 1)
	return Vector3(sin(owner_node.rotation.y), 0, cos(owner_node.rotation.y))


## Rotate the owner toward `target_position` (XZ only) at turn_rate deg/s —
## the same rotation.y driving movement (see get_facing()). Public entry point
## for non-movement callers that need the unit's body to turn, e.g. Attack
## aiming a weapon before firing. There's only one facing today (the root
## node's), so aiming and movement share it; if a unit ever needs an
## independently-aimed part (e.g. a tank turret vs. its treads) that would get
## its own rotation separate from this one.
func face_toward(a_target_position: Vector3) -> void:
	var owner_node: Node3D = _owner_node()
	if owner_node == null:
		return
	var dir: Vector3 = a_target_position - owner_node.global_position
	dir.y = 0.0
	turn_toward(dir)


## True when the owner's current facing (get_facing()) already points at
## `target_position` (XZ only), within a tight tolerance. Pairs with
## face_toward(): callers that gate an action on facing (e.g. Attack firing)
## call face_toward() every tick to turn, then is_facing() to know when the
## turn has caught up. Vacuously true with no owner Node3D or a degenerate
## (on top of the owner) target.
func is_facing(a_target_position: Vector3) -> bool:
	return is_facing_within(a_target_position, _FACING_ALIGNMENT_EPSILON)


## As is_facing(), but within an arbitrary arc in radians.
##
## The tight default suits anything that TURNS TO AIM and then stops: it converges exactly,
## so "has the turn caught up yet" is a fair question. It is the wrong question for a unit
## whose heading is a by-product of steering — an aeroplane never stops turning, so its nose
## perpetually lags the bearing to a moving target by a fraction of a degree and never
## converges at all. Measured against a target crossing its path, a Drake held its nose
## 0.2 degrees off all the way in: visually dead-on, four rockets unspent, because the
## default tolerance is 0.057 degrees. Such a unit is asked for an ARC instead — see
## Attack.FLYING_AIM_ARC_DEGREES.
func is_facing_within(a_target_position: Vector3, a_tolerance: float) -> bool:
	var owner_node: Node3D = _owner_node()
	if owner_node == null:
		return true
	var dir: Vector3 = a_target_position - owner_node.global_position
	dir.y = 0.0
	if dir.is_zero_approx():
		return true
	return get_facing().angle_to(dir.normalized()) <= a_tolerance


## Rotate the owner node's rotation.y so its +Z (forward) axis points along the
## XZ direction of `target_dir`, at turn_rate deg/s (instantly if turn_rate is
## INF). +Z is our meshes' visual front (authored -Y in Blender → +Z on glTF
## import; matches get_facing()), so this is the yaw that visually points the
## mesh at target_dir. No-op if there's no owner Node3D or target_dir is
## degenerate.
func turn_toward(a_target_dir: Vector3) -> void:
	var owner_node: Node3D = _owner_node()
	if owner_node == null or a_target_dir.is_zero_approx():
		return
	var target_angle: float = atan2(a_target_dir.x, a_target_dir.z)
	if turn_rate == INF:
		owner_node.rotation.y = target_angle
		return
	var tps: float = float(TimeUtils.ticks_per_second())
	var max_delta: float = deg_to_rad(_effective_turn_rate()) / tps
	owner_node.rotation.y += clampf(
		angle_difference(owner_node.rotation.y, target_angle), -max_delta, max_delta
	)


## Clamp the speed change from `_current_velocity` toward [a_desired] within the per-tick
## budget derived from max_acceleration / max_deceleration, applying in order: the final-leg
## braking cap, the turn-radius governor, and whichever hovering alignment rule is in force.
func _apply_accel_limits(a_desired: Vector3) -> Vector3:
	# Grounded units run their acceleration / deceleration as a SIGNED longitudinal speed in
	# _apply_grounded_turn (so a forward<->reverse command eases through zero instead of
	# snapping to the opposite velocity). Only the final-leg braking cap belongs here; the
	# per-tick rate limiting happens after avoidance.
	if mode == Mode.GROUNDED:
		if a_desired.is_zero_approx():
			return a_desired
		var capped: float = _braking_capped_speed(a_desired.length())
		return a_desired.normalized() * capped if capped < a_desired.length() else a_desired

	var needs_alignment: bool = _hovering_needs_alignment(a_desired)
	var needs_facing: bool = _hovering_needs_facing(a_desired)
	if (
		max_acceleration == INF
		and max_deceleration == -INF
		and turn_rate == INF
		and not needs_alignment
		and not needs_facing
	):
		return a_desired  # fast path — no clamping, no braking, no turn-rate limit

	var desired_speed: float = _turn_limited_speed(_braking_capped_speed(a_desired.length()))
	if needs_alignment:
		# When the heading diverges from the target, scale desired_speed down so the unit must
		# decelerate and turn before re-accelerating. The turn-rate slerp curves the rotation.
		desired_speed *= maxf(0.0, _current_velocity.normalized().dot(a_desired.normalized()))

	# A helicopter braking out of a reversal decelerates in its CURRENT direction, so the
	# emitted velocity stays physically correct — no instantaneous flip under bounded decel.
	var decelerate_in_current_dir: bool = needs_facing and _is_braking_for_reversal(a_desired)
	if decelerate_in_current_dir:
		desired_speed = 0.0
	elif needs_facing:
		desired_speed = _facing_capped_speed(a_desired, desired_speed)

	var tps: float = TimeUtils.ticks_per_second()
	var current_speed: float = _current_velocity.length()
	var clamped_delta: float = clampf(
		desired_speed - current_speed,
		max_deceleration / tps,  # negative bound (deceleration)
		max_acceleration / tps,  # positive bound (acceleration)
	)
	var new_speed: float = maxf(0.0, current_speed + clamped_delta)
	if new_speed < 1e-4:
		return Vector3.ZERO
	return _heading_for(a_desired, decelerate_in_current_dir, tps) * new_speed


## The final-leg braking cap on [a_speed]. `sqrt(2·|max_decel|·dist)` is the fastest the unit
## can still be travelling and come to a full stop exactly at the destination. Returns
## [a_speed] unchanged when braking does not apply — not the final leg, or unbounded decel.
func _braking_capped_speed(a_speed: float) -> float:
	if not is_final_leg or max_deceleration == -INF:
		return a_speed
	var distance: float = _distance_to_target()
	var braking_speed: float = (
		sqrt(2.0 * absf(max_deceleration) * distance) if distance > 0.0 else 0.0
	)
	return minf(a_speed, braking_speed)


## THE OLD hovering rule (reverse_speed_ratio == 0): the unit must turn to face the target
## before accelerating, and misalignment scales its speed toward zero.
func _hovering_needs_alignment(a_desired: Vector3) -> bool:
	return (
		mode == Mode.HOVERING
		and reverse_speed_ratio == 0.0
		and not _current_velocity.is_zero_approx()
		and not a_desired.is_zero_approx()
	)


## THE HELICOPTER rule (reverse_speed_ratio > 0 and a finite turn_rate): speed is capped by
## how well the BODY's facing aligns with where it is being sent, rather than zeroed.
##
## Both hovering rules are false when turn_rate is INF, which is what keeps the fast path in
## _apply_accel_limits available.
func _hovering_needs_facing(a_desired: Vector3) -> bool:
	return (
		mode == Mode.HOVERING
		and reverse_speed_ratio > 0.0
		and turn_rate != INF
		and not a_desired.is_zero_approx()
	)


## Whether the unit is currently moving OPPOSITE to where it is being sent, so it has to
## brake before it can set off — phase 1 of the helicopter rule.
func _is_braking_for_reversal(a_desired: Vector3) -> bool:
	return (
		not _current_velocity.is_zero_approx()
		and _current_velocity.normalized().dot(a_desired.normalized()) < 0.0
	)


## Phase 2 of the helicopter rule: cap [a_speed] by how well the OWNER's current facing
## (get_facing(), driven by rotation.y) aligns with the desired direction. Facing straight
## at it gives full speed; facing directly away gives `speed * reverse_speed_ratio`.
func _facing_capped_speed(a_desired: Vector3, a_speed: float) -> float:
	var alignment: float = get_facing().dot(a_desired.normalized())
	return minf(a_speed, lerpf(speed * reverse_speed_ratio, speed, (alignment + 1.0) * 0.5))


## The direction to emit this tick.
##
## While decelerating out of a reversal the CURRENT heading is kept, so the unit brakes
## forward rather than instantly emitting a backward velocity. A BANKING limit is then
## applied for smooth intermediate-waypoint curves — skipped for HOVERING with
## reverse_speed_ratio > 0, where velocity direction changes freely and body facing is
## tracked separately by _update_facing().
func _heading_for(
	a_desired: Vector3, a_decelerate_in_current_dir: bool, a_ticks_per_second: float
) -> Vector3:
	var dir: Vector3
	if a_decelerate_in_current_dir and not _current_velocity.is_zero_approx():
		dir = _current_velocity.normalized()
	elif not a_desired.is_zero_approx():
		dir = a_desired.normalized()
	else:
		dir = _current_velocity.normalized()
	if (
		(mode == Mode.FLYING or (mode == Mode.HOVERING and reverse_speed_ratio == 0.0))
		and turn_rate != INF
		and not _current_velocity.is_zero_approx()
	):
		var max_angle: float = deg_to_rad(_effective_turn_rate()) / a_ticks_per_second
		dir = _turn_heading_toward(_current_velocity, dir, max_angle)
	return dir


## Rotate `from`'s heading toward `toward` by at most `max_angle`, on XZ.
##
## A SIGNED 2D ANGLE, not Vector3.slerp, and that is the whole point of the function. Slerp
## builds its rotation axis from the cross product of the two vectors, which is ZERO when
## they are exactly opposite — so a unit asked to reverse course got back its own heading
## unchanged and flew straight on, forever, at full speed. That is not a rare corner: an
## aircraft that has just overflown its target and is sent home to an airfield BEHIND it is
## asked for exactly 180°, every time. The Drake flew off the map instead of coming around.
##
## Vector2.angle_to returns a signed angle that is well defined at PI (it reports +PI), so
## the reversal simply resolves to a turn in a definite direction and the aircraft banks
## around. Which way it goes at exactly 180° is arbitrary — there is no better side — but it
## is decided rather than left to numerical noise.
func _turn_heading_toward(a_from: Vector3, a_toward: Vector3, a_max_angle: float) -> Vector3:
	var current: Vector2 = VU.in_xz(a_from)
	var wanted: Vector2 = VU.in_xz(a_toward)
	if current.is_zero_approx() or wanted.is_zero_approx():
		return a_toward
	current = current.normalized()
	var signed: float = current.angle_to(wanted.normalized())
	if absf(signed) <= a_max_angle:
		return a_toward
	return VU.from_xz(current.rotated(signf(signed) * a_max_angle))


## Cap `desired_speed` so this unit's minimum turn radius is small enough to actually curve
## onto its destination, instead of lapping it.
##
## The modes that steer by SLERPING their velocity (FLYING, and HOVERING with no reverse
## authority) trace a circle of radius `speed / turn_rate` when turning hardest. A point
## inside that circle is unreachable — the unit orbits it at arm's length forever, which is
## what happens whenever a destination is both close and off to the side.
##
## The geometry has a closed form. With the target `dist` away and `h` its perpendicular
## offset from the current heading, the hardest turn still passes through it when
##     radius <= dist² / (2h)
## (a target dead ahead has h = 0 and needs no limit; one directly abeam has h = dist and
## needs radius <= dist/2). Turning that into a speed via radius = speed / turn_rate gives
## the cap. So the unit only slows when it is actually cornering — a straight run in is
## untouched — and the closer and more abeam the destination, the more it eases off, which
## is exactly the "fly past a little, then tighten up" behaviour of a real aircraft.
##
## Uses the EFFECTIVE turn rate, so a kamikaze under terminal guidance is allowed the
## higher speed its sharper turn earns it. Skipped once navigation is finished, so a FLYING
## unit's deliberate idle orbit around its anchor is never governed.
func _turn_limited_speed(a_desired_speed: float) -> float:
	if turn_rate == INF:
		return a_desired_speed
	var slerp_steered: bool = (
		mode == Mode.FLYING or (mode == Mode.HOVERING and reverse_speed_ratio == 0.0)
	)
	if not slerp_steered or is_navigation_finished():
		return a_desired_speed
	var owner_node: Node3D = _owner_node()
	if owner_node == null:
		return a_desired_speed
	var heading: Vector2 = VU.in_xz(_current_velocity)
	if heading.is_zero_approx():
		return a_desired_speed  # stopped: it can set off in any direction, no turn to make
	var to_target: Vector2 = VU.in_xz(_hovering_target) - VU.in_xz(owner_node.global_position)
	var dist: float = to_target.length()
	if dist < 1e-3:
		return a_desired_speed
	var dir: Vector2 = heading.normalized()
	# |cross| — how far off the current heading line the destination sits.
	var h: float = absf(dir.x * to_target.y - dir.y * to_target.x)
	if h < 1e-3:
		return a_desired_speed  # dead ahead or dead astern: any radius eventually gets there
	var max_radius: float = dist * dist / (2.0 * h)
	return minf(a_desired_speed, max_radius * deg_to_rad(_effective_turn_rate()))


func _on_velocity_computed(a_velocity: Vector3) -> void:
	# Always route grounded velocity through _apply_grounded_turn, including when
	# turn_rate is INF: it also drives the body rotation (via turn_toward),
	# and INF just makes that an instant snap while returning the velocity
	# unchanged. Gating this on turn_rate != INF (as before) meant INF grounded
	# units never had their rotation.y — and therefore their model — updated.
	if mode == Mode.GROUNDED:
		a_velocity = _apply_grounded_turn(a_velocity)
	_current_velocity = a_velocity
	velocity_ready.emit(a_velocity)


## Rotate the owner's rotation.y toward the avoidance-adjusted velocity direction
## at turn_rate and shape the emitted velocity so the unit moves the way it is
## actually pointing (get_facing()) — not instantly toward where it wants to go.
##
## Translation is a SIGNED longitudinal speed along the facing axis: positive drives
## forward, negative reverses. Each tick that signed speed is rate-limited toward a
## target by _approach_signed_speed, so it eases through zero on a forward↔reverse
## flip rather than snapping to the opposite velocity — the smooth part of a
## three-point turn.
##
## The target signed speed is:
##   - the full desired speed (forward) once the nose is aligned with the destination;
##   - otherwise min_turn_speed_ratio of the desired speed, signed by whether the
##     destination is ahead of or behind the current facing. A ratio of 0 means no
##     translation while turning — the unit pivots in place until aligned.
func _apply_grounded_turn(a_velocity: Vector3) -> Vector3:
	var tps: float = float(TimeUtils.ticks_per_second())
	# Signed longitudinal speed carried over from last tick. The emitted velocity is
	# always along ±facing, and facing hasn't rotated yet this tick, so projecting the
	# previous velocity onto it recovers that signed speed (sign included).
	var facing: Vector3 = get_facing()
	var s_prev: float = _current_velocity.dot(facing)

	var desired_speed: float = a_velocity.length()
	if desired_speed <= 1e-4:
		# No destination this tick: coast the longitudinal speed down to zero within
		# the deceleration budget (a moving vehicle shouldn't stop dead). An unbounded
		# decel reaches zero immediately, preserving the old snap-to-stop.
		var s_stop: float = _approach_signed_speed(s_prev, 0.0, tps)
		return s_stop * facing if absf(s_stop) >= 1e-4 else Vector3.ZERO

	var desired_dir: Vector3 = a_velocity / desired_speed
	var max_angle: float = deg_to_rad(turn_rate) / tps
	var angle: float = facing.angle_to(desired_dir)
	turn_toward(desired_dir)
	var new_facing: Vector3 = get_facing()

	# Target signed speed, and the axis it is applied along. Once aligned the unit
	# drives straight at full speed along the destination direction; while still
	# turning it moves along its facing at the maneuvering speed, signed by whether
	# the destination lies ahead of (or behind) that facing.
	var target_signed: float
	var out_dir: Vector3
	if angle <= max_angle:
		target_signed = desired_speed
		out_dir = desired_dir
	else:
		var progress_sign: float = 1.0 if new_facing.dot(desired_dir) >= 0.0 else -1.0
		target_signed = progress_sign * min_turn_speed_ratio * desired_speed
		out_dir = new_facing

	var s_new: float = _approach_signed_speed(s_prev, target_signed, tps)
	return s_new * out_dir if absf(s_new) >= 1e-4 else Vector3.ZERO


## Advance a signed longitudinal speed `s` toward `target` within one tick's
## acceleration / deceleration budget. Growing the speed's magnitude (driving harder
## in the current direction of travel) is bounded by max_acceleration; shrinking it —
## which includes easing down through zero to reverse — is bounded by max_deceleration.
## max_deceleration is treated as a magnitude, so either sign of the authored value
## works. INF bounds reproduce the old instant behaviour.
func _approach_signed_speed(a_s: float, a_target: float, a_tps: float) -> float:
	var accel_step: float = max_acceleration / a_tps
	var decel_step: float = absf(max_deceleration) / a_tps
	if a_target > a_s:
		# Raising s: accelerating if already moving forward (s >= 0), otherwise slowing
		# a reverse motion back toward zero (deceleration).
		return minf(a_s + (accel_step if a_s >= 0.0 else decel_step), a_target)
	elif a_target < a_s:
		# Lowering s: accelerating if already reversing (s <= 0), otherwise braking a
		# forward motion (deceleration).
		return maxf(a_s - (accel_step if a_s <= 0.0 else decel_step), a_target)
	return a_s


#endregion

#region Path following
## The ground unit's own path: queried with the agent's settings, followed with the agent's
## waypoint and arrival rules (NavigationAgent3D._update_navigation, Godot 4.7). What differs
## is ONE rule. The agent re-plans whenever the navigation map changes, and every structure
## placed or destroyed changes it, so every moving unit re-planned in the same tick. This
## re-plans only when a change crosses the rest of the path. Why, and what that costs:
## gdd/systems/terrain-and-navigation/navigation-and-pathing.md §Re-planning after a navmesh
## change.
##
## INVARIANT: nothing may ask the agent for a path (is_navigation_finished,
## get_next_path_position, get_final_position, is_target_reachable). Those run the agent's own
## query, and its own "finished" transition then stops it passing velocities to avoidance — the
## agent keeps a target only so that it keeps doing so. No API can stop a caller making those
## calls; every path question goes through this class instead.


## The path as this unit is following it; empty when it has none. For probes and debugging.
func current_path() -> PackedVector3Array:
	return _path


## Head for `a_position`: the agent is given it (so it keeps feeding avoidance), and the path is
## re-planned on the next read.
func _submit_target(a_position: Vector3) -> void:
	_nav_agent.target_position = a_position
	_path = PackedVector3Array()
	_path_index = 0
	_is_target_submitted = true
	_is_path_finished = false
	_is_last_waypoint_reached = false


## Re-plan if the path is missing, strayed from, or crossed by a navmesh change, then advance
## along it and decide whether the unit has arrived.
func _update_path() -> void:
	if not _is_target_submitted:
		return
	var body := get_parent() as Node3D
	if body == null or not body.is_inside_tree():
		return
	var origin: Vector3 = body.global_position
	if _path.is_empty() or _has_strayed_from_path(origin) or _is_crossed_by_a_change(origin):
		_plan_path(origin)
	if _path.is_empty() or _is_path_finished:
		return
	_advance_waypoints(origin)
	if origin.distance_to(_nav_agent.target_position) < _nav_agent.target_desired_distance:
		_finish_path()
	elif _is_last_waypoint_reached and not _is_target_reachable():
		_finish_path()


## Plan a path to the target: the straight line when this unit's class can walk it, else a
## navmesh query. The straight line is what path straightening would steer along anyway, so the
## unit moves identically; what it saves is the query — for a unit chasing a moving target, one
## on every tick the target moves. Why: gdd/systems/terrain-and-navigation/
## navigation-and-pathing.md §A path is the straight line whenever the unit can walk it.
func _plan_path(a_origin: Vector3) -> void:
	var target: Vector3 = _nav_agent.target_position
	if (
		string_pull
		and _map != null
		and _map.terrain_grid != null
		and _line_is_navigable(a_origin, target)
	):
		_path_change_serial = _nav_manager.landed_serial() if _nav_manager != null else 0
		_path = PackedVector3Array([a_origin, target])
		_path_index = 0
		_is_path_finished = false
		_is_last_waypoint_reached = false
		return
	_query_path(a_origin)


func _query_path(a_origin: Vector3) -> void:
	if _path_query == null:
		_path_query = NavigationPathQueryParameters3D.new()
		_path_result = NavigationPathQueryResult3D.new()
	_path_query.map = _nav_agent.get_navigation_map()
	_path_query.start_position = a_origin
	_path_query.target_position = _nav_agent.target_position
	_path_query.navigation_layers = _nav_agent.navigation_layers
	_path_query.metadata_flags = _nav_agent.path_metadata_flags
	_path_query.pathfinding_algorithm = _nav_agent.pathfinding_algorithm
	_path_query.path_postprocessing = _nav_agent.path_postprocessing
	_path_query.simplify_path = _nav_agent.simplify_path
	_path_query.simplify_epsilon = _nav_agent.simplify_epsilon
	_path_query.path_return_max_length = _nav_agent.path_return_max_length
	_path_query.path_return_max_radius = _nav_agent.path_return_max_radius
	_path_query.path_search_max_polygons = _nav_agent.path_search_max_polygons
	_path_query.path_search_max_distance = _nav_agent.path_search_max_distance
	# Changes that have not landed are checked against this path once they do.
	_path_change_serial = _nav_manager.landed_serial() if _nav_manager != null else 0
	NavigationServer3D.query_path(_path_query, _path_result)
	_path = _path_result.path
	_path_index = 0
	_is_path_finished = false
	_is_last_waypoint_reached = false


## Whether the unit has drifted `path_max_distance` or more off the leg it is on.
func _has_strayed_from_path(a_origin: Vector3) -> bool:
	if _path_index <= 0 or _path_index >= _path.size():
		return false
	var offset := Vector3(0.0, _nav_agent.path_height_offset, 0.0)
	var closest: Vector3 = Geometry3D.get_closest_point_to_segment(
		a_origin, _path[_path_index - 1] - offset, _path[_path_index] - offset
	)
	return a_origin.distance_to(closest) >= _nav_agent.path_max_distance


## Whether a navmesh change that path queries can now see crosses the rest of this path. A path
## that stops short of its target re-plans on a change around the target instead — within one
## cell more than the gap it stops short by — since that is where a change could open the way.
## A unit that fell behind the change history always re-plans.
func _is_crossed_by_a_change(a_origin: Vector3) -> bool:
	if _nav_manager == null:
		return false
	var changes: Array[NavManager.NavChange] = _nav_manager.landed_changes_since(
		_path_change_serial
	)
	if changes.is_empty():
		return false
	var is_forgotten: bool = _nav_manager.has_forgotten(_path_change_serial)
	_path_change_serial = changes.back().serial
	if is_forgotten:
		return true
	if not _is_target_reachable():
		var target: Vector3 = _nav_agent.target_position
		var reach: float = (
			VU.in_xz(_final_path_position()).distance_to(VU.in_xz(target)) + Map.CELL_SIZE
		)
		return changes.any(func(c: NavManager.NavChange) -> bool: return c.is_near(target, reach))
	return changes.any(
		func(c: NavManager.NavChange) -> bool: return c.crosses(a_origin, _path, _path_index)
	)


## Move the cursor past every waypoint already within `path_desired_distance`.
func _advance_waypoints(a_origin: Vector3) -> void:
	if _is_last_waypoint_reached:
		return
	var offset := Vector3(0.0, _nav_agent.path_height_offset, 0.0)
	while a_origin.distance_to(_path[_path_index] - offset) < _nav_agent.path_desired_distance:
		if _path_index == _path.size() - 1:
			_is_last_waypoint_reached = true
			return
		_path_index += 1


## Whether the path ends within `target_desired_distance` of the target — false for a path that
## stops short because the target cannot be reached.
func _is_target_reachable() -> bool:
	return (
		_nav_agent.target_desired_distance
		>= _final_path_position().distance_to(_nav_agent.target_position)
	)


func _final_path_position() -> Vector3:
	if _path.is_empty():
		return Vector3.ZERO
	return _path[_path.size() - 1] - Vector3(0.0, _nav_agent.path_height_offset, 0.0)


func _next_path_position() -> Vector3:
	_update_path()
	if _path.is_empty():
		return (get_parent() as Node3D).global_position
	return _path[_path_index] - Vector3(0.0, _nav_agent.path_height_offset, 0.0)


## Arrived, or as close as the path goes: stop feeding avoidance a velocity, as the agent did.
func _finish_path() -> void:
	_is_path_finished = true
	_is_target_submitted = false
	if not _nav_agent.avoidance_enabled:
		return
	var rid: RID = _nav_agent.get_rid()
	NavigationServer3D.agent_set_position(rid, (get_parent() as Node3D).global_position)
	NavigationServer3D.agent_set_velocity(rid, Vector3.ZERO)
	NavigationServer3D.agent_set_velocity_forced(rid, Vector3.ZERO)
	# A velocity handed to the agent earlier this tick would otherwise reach avoidance next tick.
	_nav_agent.set_velocity(Vector3.ZERO)


#endregion

#region Path straightening (string-pull)
## Steer at the FURTHEST waypoint the unit can reach in a straight line, instead of at the
## next one.
##
## WHY THIS EXISTS. The navmesh is one quad per cell (NavManager explains at length why it
## cannot be anything else in this engine), so A* hands the funnel a STAIRCASE corridor of unit
## cells. The funnel then returns the shortest path INSIDE that corridor, which for any heading
## that is not axis-aligned or exactly diagonal is a bowed polyline — the straight line lies
## outside the corridor and is not available to it. Measured on flat, empty ground, a 12-unit
## move at 30 degrees came back bowed 1.45 units off the straight line, with every segment
## 12-19 degrees off the ordered heading; a unit ordered 30 degrees away travelled at up to 33
## degrees of error the whole way.
##
## It is easy to miss, because PATH LENGTH barely registers it: the bow goes out and comes back,
## so the polyline is only ~1% longer while the direction is wrong throughout. Heading error is
## the metric that shows it (tools/terrain_meshes/probe_velocity_angle.gd).
##
## NOT Godot's `NavigationAgent3D.simplify_path`, which was measured and does not fix this.
## That is Ramer-Douglas-Peucker over the polyline's own geometry: it can only DELETE points, it
## knows nothing about what is walkable, and so it cannot move the path onto the straight line.
## At epsilon 0.5 it left mean heading error at a 200-degree bearing WORSE (15.97 -> 23.85).
##
## The corridor is not fixable (merging polygons is unrepresentable in Godot — see NavManager
## and tests/test_NavPathDirectness.gd), so the straightening has to happen after the path is
## returned. That is what this does.
@export var string_pull: bool = true

## Recompute the pulled target at most this often. Steering at a slightly stale far waypoint is
## harmless — it is many units away — and the search costs a line test per candidate, so this
## keeps a large army's per-tick cost bounded.
const STRING_PULL_RECHECK_TICKS: int = 6
## How far from the unit, in cells, a waypoint may be and still be a candidate when the
## destination itself is out of sight. Around an obstacle A* hands back about one waypoint per
## cell, so this bounds a recheck to ~reach² cell tests however long the path; a farther point
## that comes into view is picked up on a later recheck, as the unit advances.
const STRING_PULL_REACH_CELLS: float = 32.0
var _pulled_target: Vector3 = Vector3.INF
var _pulled_tick: int = -1000
var _pulled_from: Vector3 = Vector3.INF


## The waypoint to steer at (pulled_waypoint_index), or Vector3.INF when there is none (no
## path, no map, or even the next waypoint is not directly reachable — in which case the caller
## falls back to the agent's own answer).
func _string_pulled_target() -> Vector3:
	var parent := get_parent() as Node3D
	if parent == null or _map == null or _map.terrain_grid == null:
		return Vector3.INF

	var here: Vector3 = parent.global_position
	var tick: int = Engine.get_physics_frames()
	# Reuse the cached answer unless it has aged out or the unit has travelled far enough that
	# the geometry it was computed from no longer applies.
	if (
		_pulled_target != Vector3.INF
		and tick - _pulled_tick < STRING_PULL_RECHECK_TICKS
		and _pulled_from != Vector3.INF
		and VU.in_xz(here).distance_squared_to(VU.in_xz(_pulled_from)) < 1.0
	):
		return _pulled_target

	_pulled_tick = tick
	_pulled_from = here
	_pulled_target = Vector3.INF

	var path: PackedVector3Array = _path
	if path.size() < 2:
		return Vector3.INF
	var next_index: int = _path_index
	var reach: float = STRING_PULL_REACH_CELLS * Map.CELL_SIZE
	var reach_index: int = next_index
	while (
		reach_index + 1 < path.size()
		and VU.in_xz(here).distance_to(VU.in_xz(path[reach_index + 1])) <= reach
	):
		reach_index += 1
	var index: int = pulled_waypoint_index(
		path.size(),
		next_index,
		reach_index,
		func(i: int) -> bool: return _line_is_navigable(here, path[i])
	)
	if index >= 0:
		_pulled_target = path[index]
	return _pulled_target


## Which of a path's `path_size` waypoints to steer at, given `is_reachable(index) -> bool`:
## the destination when it is in a straight line, else the furthest reachable waypoint from
## `reach_index` back to `next_index` (the agent's next one), or -1 when none is. Searching back
## from the furthest candidate, not forward from the nearest, is what lets a unit cut across to
## a waypoint that comes back into view past a bend — a forward search stops at the first one
## out of sight, and measured ~6% longer routes around an obstacle.
static func pulled_waypoint_index(
	path_size: int, next_index: int, reach_index: int, is_reachable: Callable
) -> int:
	var last: int = path_size - 1
	if last < 0:
		return -1
	if is_reachable.call(last):
		return last
	for i: int in range(mini(reach_index, last - 1), maxi(next_index, 0) - 1, -1):
		if is_reachable.call(i):
			return i
	return -1


## The first of `a_points`, in the order given, that a path on THIS unit's own class navmesh
## gets within `a_tolerance` of (XZ), or null when none does — or when there is no navmesh to
## ask (not GROUNDED, no agent, an empty map in a test). One path query per point tried, so
## callers pass a short list and cache the answer rather than asking every tick.
func first_reachable(a_points: Array, a_tolerance: float) -> Variant:
	if mode != Mode.GROUNDED or _nav_agent == null or not _nav_agent.is_inside_tree():
		return null
	var nav_map: RID = _nav_agent.get_navigation_map()
	var from: Vector3 = (owner as Node3D).global_position
	for point: Vector3 in a_points:
		var path: PackedVector3Array = NavigationServer3D.map_get_path(
			nav_map, from, point, true, _nav_agent.navigation_layers
		)
		if path.is_empty():
			continue
		if VU.in_xz(path[path.size() - 1]).distance_to(VU.in_xz(point)) <= a_tolerance:
			return point
	return null


## Whether a straight XZ segment stays on ground THIS unit's own agent class may navigate.
##
## Tested against TerrainGrid with this class's erosion parameters rather than against the
## navmesh polygons, for two reasons: NavigationServer's closest-point query is not filtered by
## navigation layer, so it would answer for the un-eroded base mesh and let a large unit cut a
## corner it does not fit through; and the grid already keeps a precomputed clearance field, so
## the test is a handful of array reads.
func _line_is_navigable(a_from: Vector3, a_to: Vector3) -> bool:
	var cs: float = Map.CELL_SIZE
	return _map.terrain_grid.is_segment_navigable_for(
		_map.world_to_grid_point(VU.in_xz(a_from)),
		_map.world_to_grid_point(VU.in_xz(a_to)),
		NavAgentClass.erosion_rings(nav_agent_class, cs),
		NavAgentClass.required_clearance(nav_agent_class, cs)
	)
#endregion
