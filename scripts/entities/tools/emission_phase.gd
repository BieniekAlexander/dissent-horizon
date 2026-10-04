class_name EmissionPhase
extends Node3D

## One phase of an emission's life: how it moves, what ends it, and what it applies while it
## lasts. An emission is the ordered list of its EmissionPhase children, and runs them in tree
## order — see gdd/systems/combat/projectiles.md §Phases.
##
## A Node3D rather than a Resource so that AbstractEvent children can hang under it: an
## event is positioned, and a child of the phase follows the emission it belongs to.
##
## Every authored value is in human units (seconds, degrees, world units per second) and is
## converted to per-tick quantities here, at use, through TimeUtils.

#region Constants
## The named motions the roster was authored in, each a set of the motion scalars below.
## IMPORT-TIME ONLY: the spec importer expands a doc's `trajectory:` through this table, and
## nothing at runtime reads a name. An empty set is LINEAR, which is why every scalar's
## default must describe a straight, constant-speed flight.
const PRESETS: Dictionary = {
	"LINEAR": {},
	"BALLISTIC": {"gravity": BALLISTIC_GRAVITY_MPS2},
	"LOFTED": {"gravity": BALLISTIC_GRAVITY_MPS2, "launch_pitch": LOFTED_PITCH_DEGREES},
	"HOMING":
	{"turn_rate": 75.0, "launch_speed_ratio": 0.5, "acceleration": 2.25, "min_speed": 0.15},
}
## The arc every ballistic shell in the roster was tuned against.
const BALLISTIC_GRAVITY_MPS2: float = 4.5
## Steep enough to clear a wall in front of the launcher. LOFTED had no value before it was a
## preset, so this one was chosen, not inherited.
const LOFTED_PITCH_DEGREES: float = 60.0
## How close a steered emission must come to its live target to have arrived.
const STEERED_ARRIVAL_RADIUS: float = 0.5
## What an emission that has lost its lock falls under: the arc every shell is tuned against.
const LOST_LOCK_GRAVITY_MPS2: float = BALLISTIC_GRAVITY_MPS2
## How long an emission that lost its lock may fall before it bursts where it is: a backstop for
## a fall with nothing beneath it. On a map the ground ends the fall long before this.
const LOST_LOCK_FALL_SECONDS: float = 5.0
## How close to directly behind a steering goal must be for the turn to have no axis, as the
## cosine between heading and goal.
const DEAD_ASTERN_COSINE: float = -0.9999
## How far off dead astern the goal is nudged so the turn can start.
const DEAD_ASTERN_NUDGE_RADIANS: float = deg_to_rad(1.0)
## A goal this close to straight up or down cannot be nudged about the vertical.
const NEAR_VERTICAL_COSINE: float = 0.9
#endregion

#region Motion
@export_group("Motion")
## World units per second. Under gravity it is the HORIZONTAL speed, and the launch angle is
## solved from it; with a launch pitch it is ignored, and the speed is solved instead.
@export var speed: float = 0.0
## Downward acceleration. Zero is a straight flight.
@export var gravity_mps2: float = 0.0
## Launch elevation for a lob. Only meaningful under gravity; zero means "solve it from speed".
@export var launch_pitch_degrees: float = 0.0
## Steering authority toward a live target. Zero is an unsteered flight.
@export var turn_rate_degrees_per_second: float = 0.0
## Whether a FALLING phase re-solves its arc at the pursued piece every tick, so the landing
## point follows the piece (or where it was last seen, once it has left play). Keeps the
## horizontal speed, so a static target is flown exactly as the launch arc would have flown
## it. No effect on a phase without gravity, or on a flight that never named a piece. The
## Bombard shell uses it to follow a beacon riding on a unit.
@export var tracks_goal: bool = false
## Fraction of `speed` the emission launches at. One launches at full speed.
@export var launch_speed_ratio: float = 1.0
## While steering: gained toward `speed` when facing the target, lost toward `min_speed`
## when facing away. Zero holds the launch speed.
@export var acceleration_mps2: float = 0.0
## The floor a steered emission slows to while facing away from its target.
@export var min_speed: float = 0.0
## While steering, speed shed for turning: this many world units per second squared for each
## radian the steering goal lies off the nose. It replaces the facing rule above, so a steered
## emission gains `acceleration_mps2 - turn_bleed × angle` every second, between `min_speed`
## and `speed`: a straight run climbs to full speed, a hard turn bleeds toward the floor. Zero
## keeps the facing rule. → gdd/systems/combat/projectiles.md §Turn bleed and lead
@export var turn_bleed_mps2_per_radian: float = 0.0
## How far ahead of its target a steered phase aims, as a fraction of where the target's motion
## would carry it by the time the emission arrived. The aim point is predicted once, as the phase
## begins, and held for the phase: a target that keeps its course flies into the shot, and one
## that changes course after it is drawn to an empty point. Once that point is behind it, the
## emission flies straight. Zero aims at the target itself, live, every tick.
@export var lead_fraction: float = 0.0
## How far off the nose, in degrees, a steered phase's target may get before the emission LOSES
## ITS LOCK: it stops steering, its motor cuts, and it falls (see PhasedLocomotion). 180 is lost
## only dead astern; zero never loses the lock by angle.
## → gdd/systems/combat/projectiles.md §Losing the lock
@export var lock_cone_degrees: float = 0.0
## How far away, in world units, a steered phase's target may get before the emission loses its
## lock. Zero never loses it by distance.
@export var lock_range: float = 0.0
## Seconds into the phase at which the motor burns out, after which the emission flies no
## faster than `coast_speed`: a rocket that boosts, then coasts. Zero never burns out. The
## drop is immediate, and `acceleration_mps2` then only ever climbs back to the coast speed.
## → gdd/systems/combat/projectiles.md §Rocket calibration
@export var burn_seconds: float = 0.0
## World units per second once `burn_seconds` has passed. Only read when it has.
@export var coast_speed: float = 0.0
## How far the emission's heading wanders, in degrees either side of where it is steering —
## a rocket's wobble. It is real motion, so it can make a shot miss; seeded from the gameplay
## generator, so a replay wobbles identically (EmissionJitter). Zero flies clean.
@export var jitter_degrees: float = 0.0
## How fast the wobble swings, in cycles per second.
@export var jitter_frequency_hz: float = 1.5
#endregion

#region End clauses
@export_group("End")
## Whether reaching the destination (or a steered emission's target) ends the phase. False
## lets a moving phase fly through its destination, ending only by lifespan or impact.
@export var ends_on_arrival: bool = true
## How long the phase lasts. A phase always runs at least one tick; INF is unbounded.
@export var lifespan_seconds: float = INF
## Collision layers whose contact ends the phase — the swept impact test. Zero is the
## guided test alone, which issues no physics query in flight.
@export_flags_3d_physics var impact_mask: int = 0
#endregion

#region Payload
@export_group("Payload")
## Whether the emission's payload is applied during this phase.
@export var applies_payload: bool = false
## Seconds between applications, the first on entering the phase. INF applies it once.
@export var payload_period_seconds: float = INF
## Seconds between runs of this phase's AbstractEvent children, the first on entering the
## phase. INF runs them once.
@export var event_period_seconds: float = INF
## Nodes shown while this phase is current, relative to the emission root. A node named by any
## phase is hidden while no phase naming it is current, so stages may share one.
@export var visuals: Array[NodePath] = []
#endregion


#region Public API
func duration_ticks() -> int:
	return _ticks_or_unbounded(lifespan_seconds)


func payload_period_ticks() -> int:
	return _ticks_or_unbounded(payload_period_seconds)


func event_period_ticks() -> int:
	return _ticks_or_unbounded(event_period_seconds)


func events() -> Array[AbstractEvent]:
	var found: Array[AbstractEvent] = []
	found.assign(get_children().filter(func(c: Node) -> bool: return c is AbstractEvent))
	return found


## Show or hide this phase's visuals, found relative to `a_host`. `a_skip` is a node another
## component draws (a Tracer's beam), which no phase toggles.
##
## A visual holding particle systems is switched by `emitting` alone and never hidden, so what
## it has already emitted lives out after its phase ends: an exhaust's smoke hangs in the air
## after the rocket has struck. Anything else — a mesh, a sprite — is shown or hidden. An effect
## outlasts its phase only as long as the emission does, so a phase that must show one ends
## later than its payload needs (projectiles.md §Visuals).
func show_visuals(a_host: Node, a_shown: bool, a_skip: Node = null) -> void:
	for path: NodePath in visuals:
		show_visual(a_host, path, a_shown, a_skip)


## Show or hide the one visual at `a_path` under `a_host`, by the rule show_visuals describes.
static func show_visual(a_host: Node, a_path: NodePath, a_shown: bool, a_skip: Node = null) -> void:
	var node: Node = a_host.get_node_or_null(a_path)
	if node == null or node == a_skip:
		return
	var particles: Array[Node] = particle_systems_in(node)
	if not particles.is_empty():
		for system: Node in particles:
			if system is EmissionParticles:
				(system as EmissionParticles).set_phase_emitting(a_shown)
			else:
				system.set(&"emitting", a_shown)
	elif node is Node3D:
		(node as Node3D).visible = a_shown


## Every particle system at or under `node`. Typed by capability rather than class because
## GPUParticles3D and CPUParticles3D share no particles-specific base.
static func particle_systems_in(node: Node) -> Array[Node]:
	var candidates: Array[Node] = [node]
	candidates.append_array(node.find_children("*", "", true, false))
	var found: Array[Node] = []
	found.assign(
		candidates.filter(func(n: Node) -> bool: return n is GPUParticles3D or n is CPUParticles3D)
	)
	return found


func has_jitter() -> bool:
	return jitter_degrees > 0.0 and jitter_frequency_hz > 0.0 and not is_motionless()


## A phase that does not move: nothing carries the emission while it lasts.
func is_motionless() -> bool:
	return speed <= 0.0 and gravity_mps2 <= 0.0


## Run this phase's scenario events, as `a_commander_id`'s, through `a_manager`.
func run_events(a_commander_id: int, a_manager: ScenarioTriggerManager) -> void:
	for event: AbstractEvent in events():
		# Same optional-property idiom Sanction uses: only an event that declares it takes it.
		event.set("commander_id", a_commander_id)
		event.execute(a_manager)


func is_steered() -> bool:
	return turn_rate_degrees_per_second > 0.0


func is_straight() -> bool:
	return gravity_mps2 <= 0.0 and not is_steered()


## The velocity, per tick, that this phase starts `a_origin` on toward `a_destination`.
func launch_velocity(a_origin: Vector3, a_destination: Vector3) -> Vector3:
	if gravity_mps2 > 0.0:
		return (
			_lob_velocity(a_origin, a_destination)
			if launch_pitch_degrees > 0.0
			else _ballistic_velocity(a_origin, a_destination, _speed_per_tick())
		)
	return a_origin.direction_to(a_destination) * _speed_per_tick() * launch_speed_ratio


## One tick of goal-tracking under gravity (see tracks_goal): the fall is left exactly as it
## is, and the HORIZONTAL velocity is re-aimed so the emission crosses `a_goal`'s height over
## `a_goal`. The time left to fall is solved from the live vertical velocity with the same
## integrator tick() uses (move, then fall), so re-aiming never lengthens or shortens the
## flight — the shell lands when it would have, wherever the goal has got to. Unchanged when
## this phase does not track, does not fall, or has no goal.
##
## The re-aim is unbounded: a goal that moved is always caught. TODO — how far a shell may
## turn (and so whether a fast carrier can escape it) is the Bombard's open trajectory design
## (gdd/design-framework/static-defence.md §The Bombard); this is the quickest version that
## follows.
func tracked_velocity(a_velocity: Vector3, a_position: Vector3, a_goal: Variant) -> Vector3:
	if not tracks_goal or gravity_mps2 <= 0.0 or not (a_goal is Vector3):
		return a_velocity
	var goal: Vector3 = a_goal
	var fall: float = gravity_mps2 / float(_ticks_squared())
	# y after n ticks = y0 + n*vy - fall*n*(n-1)/2; solve for the later crossing of goal.y.
	var b: float = a_velocity.y + fall / 2.0
	var discriminant: float = b * b + 2.0 * fall * (a_position.y - goal.y)
	var ticks_left: float = 1.0
	if discriminant > 0.0:
		ticks_left = maxf((b + sqrt(discriminant)) / fall, 1.0)
	var to_goal_xz: Vector2 = VU.in_xz(goal) - VU.in_xz(a_position)
	return VU.from_xz(to_goal_xz / ticks_left) + a_velocity.y * Vector3.UP


## One tick of steering at `a_target`, before the move. Unchanged when unsteered or targetless.
func steered_velocity(a_velocity: Vector3, a_position: Vector3, a_target: Entity) -> Vector3:
	return steered_toward(
		a_velocity, a_position, a_target.aim_point() if a_target != null else null
	)


## One tick of steering at the point `a_goal`, before the move. Unchanged when unsteered. A
## null `a_goal` (a ground-aimed shot, or a lead point already behind) holds the heading but
## still thrusts, as though facing its goal: the motor does not need a target to burn.
func steered_toward(a_velocity: Vector3, a_position: Vector3, a_goal: Variant) -> Vector3:
	if not is_steered():
		return a_velocity
	if not (a_goal is Vector3):
		return _thrust_along_heading(a_velocity)
	var goal_direction: Vector3 = a_position.direction_to(a_goal)
	# Dead astern a turn has no axis — the slerp between opposed vectors never leaves the
	# heading — so a shot that overflew its goal would fly straight on forever. Commit to a side.
	if a_velocity.normalized().dot(goal_direction) < DEAD_ASTERN_COSINE:
		var axis: Vector3 = (
			Vector3.UP
			if absf(goal_direction.dot(Vector3.UP)) < NEAR_VERTICAL_COSINE
			else Vector3.RIGHT
		)
		goal_direction = goal_direction.rotated(axis, DEAD_ASTERN_NUDGE_RADIANS)
	var is_facing: bool = a_velocity.normalized().dot(goal_direction.normalized()) >= 0
	var off_nose: float = a_velocity.angle_to(goal_direction)
	var turned: Vector3 = VU.get_rotated_vector_3d(
		a_velocity,
		goal_direction,
		deg_to_rad(turn_rate_degrees_per_second / float(TimeUtils.ticks_per_second()))
	)
	var step: float = acceleration_mps2 / float(_ticks_squared())
	if turn_bleed_mps2_per_radian > 0.0:
		var change: float = (
			(acceleration_mps2 - turn_bleed_mps2_per_radian * off_nose) / float(_ticks_squared())
		)
		return (
			turned.normalized()
			* clampf(
				turned.length() + change,
				min_speed / float(TimeUtils.ticks_per_second()),
				maxf(_speed_per_tick(), min_speed / float(TimeUtils.ticks_per_second()))
			)
		)
	return (
		turned.normalized()
		* (
			minf(turned.length() + step, _speed_per_tick())
			if is_facing
			else maxf(turned.length() - step, min_speed / float(TimeUtils.ticks_per_second()))
		)
	)


## `a_velocity` on its own heading, sped up by one tick of this phase's acceleration toward
## `speed` — the facing branch of steered_toward, with no turn.
func _thrust_along_heading(a_velocity: Vector3) -> Vector3:
	if a_velocity.is_zero_approx():
		return a_velocity
	var step: float = acceleration_mps2 / float(_ticks_squared())
	var thrusted: float = minf(a_velocity.length() + step, _speed_per_tick())
	return a_velocity.normalized() * maxf(thrusted, a_velocity.length())


func leads() -> bool:
	return lead_fraction > 0.0 and is_steered()


## Whether an emission at `a_position`, flying `a_velocity`, loses its lock on a target at
## `a_target_point`: the target is farther off the nose than `lock_cone_degrees`, or farther away
## than `lock_range`. Never for an unsteered phase, nor for a knob left at zero.
func loses_lock(a_velocity: Vector3, a_position: Vector3, a_target_point: Vector3) -> bool:
	if not is_steered():
		return false
	var to_target: Vector3 = a_target_point - a_position
	if lock_range > 0.0 and to_target.length() > lock_range:
		return true
	return (
		lock_cone_degrees > 0.0
		and not a_velocity.is_zero_approx()
		and not to_target.is_zero_approx()
		and rad_to_deg(a_velocity.angle_to(to_target)) > lock_cone_degrees
	)


## Where this phase aims to meet a target at `a_target_position` moving `a_target_step` per
## tick, flying from `a_origin` at full speed: the target's position advanced by `lead_fraction`
## of its motion until the intercept. A target too fast to intercept is led by the time this
## phase would take to reach where it is now.
func intercept_point(
	a_origin: Vector3, a_target_position: Vector3, a_target_step: Vector3
) -> Vector3:
	var own_step: float = _speed_per_tick()
	var to_target: Vector3 = a_target_position - a_origin
	var ticks: float = to_target.length() / own_step if own_step > 0.0 else 0.0
	# |to_target + step·t| = own_step·t, for the earliest t > 0.
	var a: float = a_target_step.length_squared() - own_step * own_step
	var b: float = 2.0 * to_target.dot(a_target_step)
	var c: float = to_target.length_squared()
	if absf(a) > 1e-9:
		var discriminant: float = b * b - 4.0 * a * c
		if discriminant >= 0.0:
			var root: float = sqrt(discriminant)
			var first: float = minf((-b - root) / (2.0 * a), (-b + root) / (2.0 * a))
			var second: float = maxf((-b - root) / (2.0 * a), (-b + root) / (2.0 * a))
			if first > 0.0:
				ticks = first
			elif second > 0.0:
				ticks = second
	elif absf(b) > 1e-9 and -c / b > 0.0:
		ticks = -c / b
	return a_target_position + a_target_step * ticks * lead_fraction


## `a_velocity` held to the coast speed once the burn is over, `a_phase_seconds` into the
## phase. Unchanged before burn-out and for a phase that never burns out. Applied after
## steering, so a steered emission's own acceleration rule still runs, under this cap.
func burnt_velocity(a_velocity: Vector3, a_phase_seconds: float) -> Vector3:
	if burn_seconds <= 0.0 or a_phase_seconds < burn_seconds:
		return a_velocity
	var cap: float = coast_speed / float(TimeUtils.ticks_per_second())
	return a_velocity.limit_length(cap)


## One tick of gravity, after the move.
func fallen_velocity(a_velocity: Vector3) -> Vector3:
	return a_velocity + Vector3.DOWN * gravity_mps2 / float(_ticks_squared())


## Whether the emission has reached where it was going. A steered phase aims at its target's
## hurtbox centre (Entity.aim_point) and never arrives without one; a falling one lands on
## crossing its destination's height on the way down; anything else arrives within one step of
## the destination.
func has_arrived(
	a_position: Vector3, a_velocity: Vector3, a_destination: Vector3, a_target: Entity
) -> bool:
	if is_steered():
		return (
			a_target != null
			and (
				a_position.distance_squared_to(a_target.aim_point())
				< STEERED_ARRIVAL_RADIUS * STEERED_ARRIVAL_RADIUS
			)
		)
	if gravity_mps2 > 0.0:
		return a_velocity.y < 0 and a_position.y <= a_destination.y
	return a_position.distance_to(a_destination) <= _speed_per_tick()


#endregion


#region Private helpers
func _speed_per_tick() -> float:
	return speed / float(TimeUtils.ticks_per_second())


static func _ticks_squared() -> int:
	return TimeUtils.ticks_per_second() * TimeUtils.ticks_per_second()


## A phase period in ticks, never less than one; -1 for an unbounded (INF) one.
static func _ticks_or_unbounded(seconds: float) -> int:
	if is_inf(seconds):
		return -1
	return maxi(1, TimeUtils.ticks_from_seconds(seconds))


## The launch that reaches `a_destination` under gravity, travelling horizontally at
## `a_horizontal_step` per tick. The first tick's gravity is folded into the launch so the
## discrete arc lands on the destination's height exactly when it arrives over it.
func _ballistic_velocity(
	a_origin: Vector3, a_destination: Vector3, a_horizontal_step: float
) -> Vector3:
	var to_target_xz: Vector2 = VU.in_xz(a_destination) - VU.in_xz(a_origin)
	var fall_per_tick: float = -gravity_mps2 / float(_ticks_squared())
	# A shot at its own position would take zero ticks; one tick lands it next tick instead.
	var ticks_to_target: float = maxf(to_target_xz.length() / a_horizontal_step, 1.0)
	var vertical: float = (
		(a_destination.y - a_origin.y) / ticks_to_target - fall_per_tick * ticks_to_target / 2
	)
	return (
		VU.from_xz(to_target_xz.normalized() * a_horizontal_step)
		+ (vertical + fall_per_tick) * Vector3.UP
	)


## A lob at `launch_pitch_degrees`: the flight time that pitch implies under gravity, then the
## same integrator as a ballistic shot. A destination too high for the pitch is shot as a
## plain ballistic arc at `speed` instead.
func _lob_velocity(a_origin: Vector3, a_destination: Vector3) -> Vector3:
	var horizontal: float = (VU.in_xz(a_destination) - VU.in_xz(a_origin)).length()
	var rise: float = (
		horizontal * tan(deg_to_rad(launch_pitch_degrees)) - (a_destination.y - a_origin.y)
	)
	if rise <= 0.0 or horizontal <= 0.0:
		return _ballistic_velocity(a_origin, a_destination, _speed_per_tick())
	var ticks_to_target: float = sqrt(2.0 * rise * _ticks_squared() / gravity_mps2)
	return _ballistic_velocity(a_origin, a_destination, horizontal / ticks_to_target)
#endregion
