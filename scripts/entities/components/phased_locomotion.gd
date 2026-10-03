class_name PhasedLocomotion
extends Locomotion

## The PHASED locomotion strategy: moves an emission through its phase list — the
## EmissionPhase siblings under the same root, in tree order. It owns the sequence (which
## phase is live, how long it has run, when it hands over) and the motion inside a phase
## (launch solve, steering, gravity, arrival, the swept impact test), and it ticks itself.
##
## Each tick, in order: hand over if the live phase has ended; announce `phase_ticking` — the
## host's Payload pays out on its cadence; run the phase's events; move; face the velocity;
## announce `moved`. The last phase ending is the host's death.
##
## A phased mover CANNOT STOP. Pursuing a piece that leaves the game, a steered phase keeps
## steering at the last place that piece was, which loops it round that point until its
## lifespan ends or it strikes something. See
## gdd/systems/authoring/composition-rework.md §Locomotion is bigger than `Movement`.

## A contact found by a phase's impact test: `a_collider` is what the ray struck.
signal struck(a_collider: Object)
## Phase `a_index` has taken over.
signal phase_entered(a_index: int)
## The live phase is about to run its tick, before any motion.
signal phase_ticking(a_phase: EmissionPhase)
## The emission has moved for this tick.
signal moved

## Pieces a free flight's contact ray may pass through in one tick before it gives up looking:
## each one it flies through costs another ray, and a crowd deeper than this is not a volley's
## usual path.
const MAX_CONTACT_PASSES: int = 8
## Every emission root joins this group, which is how the fog finds them to hide.
const EMISSION_GROUP: StringName = &"emission"

## What `begin_tick` did with the phase sequence.
enum Step {
	CONTINUE,  ## the live phase runs this tick
	ENTERED,  ## a new phase took over and runs this tick
	HOLD,  ## nothing runs this tick
	FINISHED,  ## the last phase has ended; the emission is spent
}

var _phases: Array[EmissionPhase] = []
## Index of the live phase; -1 before launch.
var _phase_index: int = -1
## Ticks the live phase has run.
var _phase_ticks: int = 0
## Set when the live phase's lifespan or impact test ended it; it hands over at the start of
## the following tick.
var _phase_over: bool = false
## Whether the phase that just ended was ended by the impact test, which leaves the emission at
## the contact point rather than settling it on its destination.
var _ended_by_impact: bool = false
## Set when the LAST phase's lifespan runs out: the emission expires this tick.
var _expired: bool = false
## The physics frame launch() ran on; -1 until it has. See begin_tick.
var _launch_frame: int = -1
## Whether the goal ever named a piece, so losing it can be told from never having one.
var _had_pursued: bool = false
## Where the pursued piece last was — the point a lost pursuit keeps steering at.
var _last_seen: Vector3 = Vector3.ZERO
## How far the pursued piece moved between this emission's last two ticks — its velocity, per
## tick, measured rather than read, so it holds for any way a piece moves. Valid once
## `_pursued_samples` reaches 2.
var _pursued_step: Vector3 = Vector3.ZERO
## Ticks on which the pursued piece's position has been sampled, in a row.
var _pursued_samples: int = 0
## A leading phase's aim point (EmissionPhase.lead_fraction), predicted once per phase; null
## until the pursued piece's motion has been measured.
var _lead_point: Variant = null
## Set once a steered phase LOSES ITS LOCK on the pursued piece (EmissionPhase.loses_lock):
## from then on the emission no longer steers or thrusts, and falls until it strikes something.
## Permanent, across stages: a motor that has cut does not relight.
var _lock_lost: bool = false
## Ticks the emission has fallen since losing its lock, against the backstop.
var _fall_ticks: int = 0
## Bodies the impact test passes through: the emission's own and its shooter's.
var _excluded: Array[RID] = []
## Whether this emission flies FREE: it ends only on striking its intended piece or the
## ground, never by arriving at a live target, so it can miss (projectiles.md §Free flight).
## False is a guided flight, which a hitscan shot is.
var _free_flight: bool = false
## Framework-imposed state: the velocity steering and gravity act on, before the wobble turns
## it. Kept apart from the body's velocity so the wobble never compounds from tick to tick.
var _clean_velocity: Vector3 = Vector3.ZERO
## The velocity this emission actually flew last tick, to tell a write from outside apart.
var _flown_velocity: Vector3 = Vector3.ZERO
## This emission's wobble, or null for one that never wobbles.
var _jitter: EmissionJitter = null
## Positions at the last two physics ticks, for drawing the in-flight sprite between them.
var _previous_position: Vector3
var _current_position: Vector3


func _ready() -> void:
	get_parent().add_to_group(EMISSION_GROUP)
	_phases.assign(
		get_parent().get_children().filter(func(c: Node) -> bool: return c is EmissionPhase)
	)
	if _phases.is_empty():
		push_error(
			(
				"Emission '%s' has no EmissionPhase children — it can never act"
				% (get_parent() as Entity).id
			)
		)
	_show_visuals_of(0)
	_current_position = _body().global_position


func _physics_process(_a_delta: float) -> void:
	_previous_position = _current_position
	_current_position = _body().global_position
	match begin_tick():
		Step.HOLD:
			return
		Step.FINISHED:
			(get_parent() as Entity).die()
			return
		Step.ENTERED:
			phase_entered.emit(_phase_index)
			_show_visuals_of(_phase_index)
	var phase: EmissionPhase = current_phase()
	phase_ticking.emit(phase)
	if is_on_cadence(phase.event_period_ticks()):
		_run_events(phase)
	tick()
	face_velocity()
	moved.emit()
	if _expired:
		(get_parent() as Entity).die()


## Draws a straight flight's in-flight sprite between physics ticks.
## TODO clean up the LERP visualization: it names one node and suits one kind of flight.
func _process(_a_delta: float) -> void:
	var phase: EmissionPhase = current_phase()
	var sprite: Sprite3D = get_parent().get_node_or_null("InFlightSprite") as Sprite3D
	if phase != null and phase.is_straight() and sprite != null:
		var alpha: float = Engine.get_physics_interpolation_fraction()
		sprite.global_position = _previous_position.lerp(_current_position, alpha)


#region Locomotion strategy
func can_move() -> bool:
	return true


## Start the first phase toward `a_destination`, pursuing `a_pursued` when there is one. The
## launch velocity is written onto the body; `a_excluded` are bodies the impact test ignores.
##
## A FREE flight (`a_free`) can miss: see _free_flight. Its wobble, if any phase has one, is
## seeded here from the gameplay generator, so a replay flies it identically.
func launch(
	a_destination: Vector3, a_pursued: Entity, a_excluded: Array[RID], a_free: bool = false
) -> void:
	set_goal(a_destination, Arrival.PASS_THROUGH, a_pursued)
	_free_flight = a_free
	if _phases.any(func(p: EmissionPhase) -> bool: return p.has_jitter()):
		_jitter = EmissionJitter.new(SU.rng)
	_had_pursued = a_pursued != null
	_last_seen = a_pursued.aim_point() if a_pursued != null else a_destination
	_pursued_samples = 0
	_lead_point = null
	_lock_lost = false
	_fall_ticks = 0
	_excluded = a_excluded
	_launch_frame = Engine.get_physics_frames()
	_phase_index = 0
	_phase_ticks = 0
	var phase: EmissionPhase = current_phase()
	if phase != null:
		redirect(phase.launch_velocity(_body().global_position, goal_position))


## Set the emission's heading outright — a launch, or an emitter's aim error applied to it.
func redirect(a_velocity: Vector3) -> void:
	_clean_velocity = a_velocity
	_flown_velocity = a_velocity
	_body().velocity = a_velocity


## Hand over to the next phase when the live one has ended — by its lifespan, its impact test,
## or arriving — and report what happened. The tick-of-flight rule: nothing ends on the frame
## of launch, so two shots fired on one tick both resolve and mutual kills stay possible
## (projectiles.md §Impact); the emission holds where it is and hands over next tick.
func begin_tick() -> Step:
	var phase: EmissionPhase = current_phase()
	if phase == null:
		return Step.HOLD
	var has_arrived: bool = (
		phase.ends_on_arrival
		and not (_free_flight and _had_pursued)
		and phase.has_arrived(
			_body().global_position, _body().velocity, goal_position, goal_entity()
		)
	)
	if not (_phase_over or has_arrived):
		return Step.CONTINUE
	if Engine.get_physics_frames() == _launch_frame:
		return Step.HOLD
	return Step.ENTERED if _enter_next_phase(has_arrived) else Step.FINISHED


## One tick of the live phase's motion: steer, move, fall, test for impact, and count the tick
## against the phase's lifespan.
func tick() -> Progress:
	var phase: EmissionPhase = current_phase()
	var body: CharacterBody3D = _body()
	var before: Vector3 = body.global_position
	if not body.velocity.is_equal_approx(_flown_velocity):
		_clean_velocity = body.velocity  # written from outside since the last tick
	var goal: Variant = _steering_goal()
	if not _lock_lost and goal_entity() != null and phase.loses_lock(_clean_velocity, before, goal):
		_lock_lost = true
	if _lock_lost:
		return _fall(phase, body, before)
	_clean_velocity = phase.tracked_velocity(_clean_velocity, before, goal)
	_clean_velocity = phase.steered_toward(
		_clean_velocity, before, _led_goal(phase, before, goal) if phase.leads() else goal
	)
	_clean_velocity = phase.burnt_velocity(_clean_velocity, _phase_seconds())
	body.velocity = (
		_jitter.perturbed(phase, _phase_seconds(), _clean_velocity)
		if _jitter != null
		else _clean_velocity
	)
	body.global_position += body.velocity
	_flown_velocity = body.velocity
	_clean_velocity = phase.fallen_velocity(_clean_velocity)
	if _free_flight and not phase.is_motionless():
		_test_contact(phase, before)
	elif phase.impact_mask != 0:
		_test_impact(phase, before)
	_phase_ticks += 1
	var duration: int = phase.duration_ticks()
	if duration > 0 and _phase_ticks >= duration:
		_phase_over = true
		_expired = _phase_index == _phases.size() - 1
	return Progress.MOVING


## One tick of a flight that has lost its lock: no steering, no thrust, just gravity, until it
## strikes something. Its stages' lifespans no longer end it — it falls rather than expiring —
## save for the backstop, which bursts it where it is. (projectiles.md §Losing the lock)
func _fall(a_phase: EmissionPhase, a_body: CharacterBody3D, a_before: Vector3) -> Progress:
	a_body.velocity = _clean_velocity
	a_body.global_position += a_body.velocity
	_flown_velocity = a_body.velocity
	_clean_velocity += (
		Vector3.DOWN * EmissionPhase.LOST_LOCK_GRAVITY_MPS2 / float(EmissionPhase._ticks_squared())
	)
	if _free_flight:
		_test_contact(a_phase, a_before)
	elif a_phase.impact_mask != 0:
		_test_impact(a_phase, a_before)
	_fall_ticks += 1
	if _fall_ticks >= TimeUtils.ticks_from_seconds(EmissionPhase.LOST_LOCK_FALL_SECONDS):
		_phase_over = true
	_expired = _phase_over and _next_burst_index() < 0
	return Progress.MOVING


## The index of the first phase after the live one that does not move — where a flight that
## ended (by a contact, or by falling out of its lock) goes next — or -1 when there is none.
func _next_burst_index() -> int:
	for index: int in range(_phase_index + 1, _phases.size()):
		if _phases[index].is_motionless():
			return index
	return -1


#endregion


#region Queries
## Seconds the live phase has run.
func _phase_seconds() -> float:
	return float(_phase_ticks) / float(TimeUtils.ticks_per_second())


func current_phase() -> EmissionPhase:
	return _phases[_phase_index] if _phase_index >= 0 and _phase_index < _phases.size() else null


func phase_index() -> int:
	return _phase_index


func phase_ticks() -> int:
	return _phase_ticks


func phase_count() -> int:
	return _phases.size()


func phase_at(a_index: int) -> EmissionPhase:
	return _phases[a_index]


## Whether the last phase's lifespan ran out this tick.
func is_expired() -> bool:
	return _expired


## Whether the live phase's tick count falls on a cadence of `a_period` ticks, the first at
## the phase's first tick. An unbounded period (-1) falls only on that first tick.
func is_on_cadence(a_period: int) -> bool:
	return _phase_ticks == 0 if a_period < 0 else _phase_ticks % a_period == 0


#endregion


#region Private helpers
func _body() -> CharacterBody3D:
	return get_parent() as CharacterBody3D


## Shows the visuals phase `a_index` names and hides every other phase's, leaving alone the beam
## a Tracer draws.
func _show_visuals_of(a_index: int) -> void:
	var tracer: Tracer = Tracer.of(get_parent())
	var beam: Node = tracer.beam() if tracer != null else null
	for i: int in _phases.size():
		_phases[i].show_visuals(get_parent(), i == a_index, beam)


## Runs the phase's scenario events at the emission's position, as its owner's.
func _run_events(a_phase: EmissionPhase) -> void:
	if a_phase.events().is_empty():
		return
	var host: Entity = get_parent() as Entity
	var manager: ScenarioTriggerManager = host._resolve_trigger_manager()
	if manager == null:
		return
	a_phase.run_events(host.commander.id if host.commander != null else 0, manager)


## Turn to face the current velocity. Skipped when velocity is ~zero (impact) to avoid a
## degenerate look_at; a flight straight up or down looks along FORWARD instead. Called at launch
## too, so the emission is not drawn in its scene's rest pose on the frame before its first tick.
func face_velocity() -> void:
	var body: CharacterBody3D = _body()
	if not body.is_inside_tree() or body.velocity.length_squared() <= 0.001:
		return
	var up: Vector3 = Vector3.UP
	if absf(body.velocity.normalized().dot(Vector3.UP)) > 0.999:
		up = Vector3.FORWARD
	body.look_at(body.global_position + body.velocity, up)


## Where a steered phase aims: the centre of the pursued piece's hitbox (Entity.aim_point), or
## where it was last seen once it has left the game; null for a goal that never named a piece,
## which is flown unsteered.
func _steering_goal() -> Variant:
	var pursued: Entity = goal_entity()
	if pursued != null:
		var aim: Vector3 = pursued.aim_point()
		if _pursued_samples > 0:
			_pursued_step = aim - _last_seen
		_pursued_samples += 1
		_last_seen = aim
		return _last_seen
	_pursued_samples = 0
	return _last_seen if _had_pursued else null


## Where a LEADING phase steers from `a_position`: the point its target was predicted to reach,
## fixed the first tick the target's motion is known (its live position until then), and
## nothing once that point is behind — the emission then flies straight.
func _led_goal(a_phase: EmissionPhase, a_position: Vector3, a_goal: Variant) -> Variant:
	if _lead_point == null:
		if _pursued_samples < 2 or not (a_goal is Vector3):
			return a_goal
		_lead_point = a_phase.intercept_point(a_position, a_goal, _pursued_step)
	var point: Vector3 = _lead_point
	return point if _clean_velocity.dot(point - a_position) > 0.0 else null


## Ends the live phase and starts the next. False when there is no next phase. A flight that
## ended by arriving snaps onto a live piece it was chasing; one that ended any way but an
## impact settles at its destination's height.
##
## Two flight stages in a row are ONE flight: a moving phase whose lifespan ran out hands the
## next moving phase its position, heading and speed, rather than relaunching it from scratch.
## And a contact ends the flight, not the stage: it skips every moving phase after it, straight
## to the next one that does not move — the burst. (projectiles.md §Phases)
func _enter_next_phase(a_has_arrived: bool) -> bool:
	var body: CharacterBody3D = _body()
	var ended: EmissionPhase = current_phase()
	var next: EmissionPhase = (
		_phases[_phase_index + 1] if _phase_index + 1 < _phases.size() else null
	)
	if (
		next != null
		and not next.is_motionless()
		and not ended.is_motionless()
		and not _ended_by_impact
		and not _lock_lost
		and not a_has_arrived
	):
		_phase_index += 1
		_phase_ticks = 0
		_phase_over = false
		_lead_point = null
		# A straight stage flies at its own speed on the inherited heading; a steered stage
		# works the inherited speed toward its own under its acceleration rule, and a falling
		# one keeps its motion and falls.
		if next.is_straight():
			redirect(_clean_velocity.normalized() * next.speed / TimeUtils.ticks_per_second())
		return true
	if _ended_by_impact or _lock_lost:
		while _phase_index + 1 < _phases.size() and not _phases[_phase_index + 1].is_motionless():
			_phase_index += 1
	var pursued: Entity = goal_entity()
	# A GUIDED flight that arrived snaps onto the piece it was chasing: it can hit a target it
	# geometrically missed. A free flight never arrives at a piece, so never snaps.
	if a_has_arrived and pursued != null and not _free_flight:
		body.global_position = pursued.global_position
	# Settle onto the destination's height — unless the flight ended by striking something, or
	# a free flight ran out of lifespan in the air, where it bursts where it is.
	if not _ended_by_impact and (a_has_arrived or not _free_flight):
		body.global_position.y = goal_position.y
	_phase_index += 1
	_phase_ticks = 0
	_phase_over = false
	_ended_by_impact = false
	_lead_point = null
	var phase: EmissionPhase = current_phase()
	if phase == null:
		return false
	redirect(phase.launch_velocity(body.global_position, goal_position))
	if phase.is_motionless():
		_level(body)
	return true


## Stand the emission upright, keeping its heading: a phase that does not move was left facing
## along its last flight, which for a falling shell is nearly straight down, and a burst or a
## ground ring drawn in that frame would lie on its side.
static func _level(body: Node3D) -> void:
	var forward: Vector3 = -body.global_basis.z
	forward.y = 0.0
	body.global_basis = (
		Basis.IDENTITY
		if forward.length_squared() < 0.0001
		else Basis.looking_at(forward.normalized(), Vector3.UP)
	)


## The swept impact test: a ray along this tick's move against the phase's impact mask. A
## contact ends the phase where it happened; what the contact MEANS is the emission's.
func _test_impact(a_phase: EmissionPhase, a_before: Vector3) -> void:
	var body: CharacterBody3D = _body()
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		a_before, body.global_position, a_phase.impact_mask, _excluded
	)
	var hit: Dictionary = body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	_end_by_contact(hit)


## A free flight's contact test: a ray along this tick's move that stops only at the GROUND,
## at the piece it was aimed at, or at the phase's impact_mask layers. Any other piece in the
## way is flown straight through — a rocket fired at one tank does not detonate on the soldier
## in front of it. Where it stops is where it bursts; WHO the burst reaches is the Payload's
## blast, decided separately.
func _test_contact(a_phase: EmissionPhase, a_before: Vector3) -> void:
	var body: CharacterBody3D = _body()
	var intended: Entity = goal_entity()
	var mask: int = (
		CollisionLayers.Mask.TERRAIN
		| a_phase.impact_mask
		| (CollisionLayers.TARGETABLE_ANY if intended != null else 0)
	)
	var excluded: Array[RID] = _excluded.duplicate()
	for pass_index: int in MAX_CONTACT_PASSES:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			a_before, body.global_position, mask, excluded
		)
		var hit: Dictionary = body.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return
		if _is_contact(hit["collider"], intended, a_phase.impact_mask):
			_end_by_contact(hit)
			return
		excluded.append((hit["collider"] as CollisionObject3D).get_rid())


## Whether a free flight stops at `a_collider`: the ground, the piece it was aimed at, or a
## layer its phase asks to strike.
static func _is_contact(a_collider: Object, a_intended: Entity, a_impact_mask: int) -> bool:
	var layers: int = (
		(a_collider as CollisionObject3D).collision_layer if a_collider is CollisionObject3D else 0
	)
	if layers & (CollisionLayers.Mask.TERRAIN | a_impact_mask):
		return true
	return a_intended != null and Entity.entity_from_collider(a_collider) == a_intended


## End the live phase at a contact point.
func _end_by_contact(a_hit: Dictionary) -> void:
	var body: CharacterBody3D = _body()
	body.global_position = a_hit["position"]
	redirect(Vector3.ZERO)
	_phase_over = true
	_ended_by_impact = true
	struck.emit(a_hit["collider"])
#endregion
