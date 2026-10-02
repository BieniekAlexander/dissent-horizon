class_name Aerial
extends Node

## Flight and height: the component a piece carries when it flies. Its presence is what makes a
## piece an aircraft, and its `mode` says which kind — HOVERING (a rotorcraft, which can hold
## station) or FLYING (a fixed wing, which cannot stop). It owns everything about being off the
## ground: altitude and terrain following, landing and take-off, the deck and the taxi, the
## dive, the idle orbit, and the model's attitude.
##
## Horizontal goal-seeking stays with the piece's locomotion (`Movement`, the navigated
## strategy), which drives straight at its goal while this component is present. The two talk
## through a narrow interface: Movement asks whether a commanded velocity is suppressed or
## shaped this tick, and this drives Movement's velocity when a landing, a taxi or a climb-out
## has to move the piece itself (see Movement's #region Aerial drive). Both tick in tree order,
## Movement first.
##
## Docking is NOT here: `Docking` says where the piece's dock is and whether it has one. This
## only knows how to come down onto a deck and leave it. The design:
## gdd/systems/authoring/composition-rework.md §Locomotion is bigger than `Movement`.

#region Constants
## How many world-units above the terrain surface an aircraft flies. Both modes share the same
## cruise altitude.
const AERIAL_HEIGHT: float = 6.0

## Height above the terrain, in world units, at or above which a piece is an AIR target
## rather than a ground one — the ONE definition of "airborne" for targeting purposes
## (see Entity.is_air_target and gdd/systems/combat/target-acquisition.md).
##
## DERIVED from AERIAL_HEIGHT rather than typed, so raising the cruise altitude cannot
## silently leave every aircraft below the line. Half of it is the meaningful fraction: a
## piece that has covered half the distance between the deck and cruise is committed to
## being in the air, and nothing in the game hovers deliberately at that height.
const AIR_TARGET_ALTITUDE: float = AERIAL_HEIGHT / 2.0

## Peak vertical rate (world-units/SECOND) at which a HOVERING unit descends to or
## ascends from the ground during a temporary landing. It is a cap, not a fixed rate:
## the manoeuvre ramps up to it and back down under LANDING_ACCEL (see below), so a
## short hop may never reach it at all.
const LANDING_SPEED: float = 1.5

## How hard the landing/takeoff vertical rate may change, world-units/s². The descent
## and ascent are acceleration-limited "arrive" curves — the same shape
## _step_smoothed_altitude uses for terrain following — so the unit eases out of the
## hover, cruises at LANDING_SPEED, then decelerates onto the ground (or onto cruise
## altitude) instead of starting and stopping dead. Lower = floatier, higher ≈ the old
## constant-rate ramp. At the current constants a full 6-unit descent takes ~4.5s
## against the old ~4.0s, so the ease-in and ease-out cost little.
const LANDING_ACCEL: float = 3.0

## Pitch-tilt applied to a HOVERING unit's model while it is LANDING or TAKING_OFF, so
## the body noses down/up slightly with its vertical motion.
## KNOWN ISSUE: _apply_hover_tilt is fed the per-TICK change in the height offset, while
## HOVER_TILT_FACTOR is calibrated for a per-SECOND rate — so the landing tilt comes out
## ~30x too small to see (under a degree, against a 20° cap). Left as-is deliberately;
## fixing the units without retuning the factor would snap the nose to the clamp.
const HOVER_TILT_FACTOR: float = 0.3
const HOVER_MAX_TILT: float = deg_to_rad(20)

## Helicopter-style attitude for an AIRBORNE HOVERING unit (see _apply_hover_bank).
## Both angles are written to the MeshVisual, never the physics body — see _attitude_node.
##
## The unit leans INTO its horizontal acceleration, whichever way that points. A rotor
## craft accelerates by tipping its disc toward the thrust it wants, so the lean is ONE
## vector in the XZ plane — aligned with the acceleration, growing with its magnitude —
## and pitch (rotation.x) and roll (rotation.z) are just that lean resolved onto the
## body's forward and right axes. Accelerating straight ahead is pure nose-down, hard
## into a turn is pure roll, and anything between is the corresponding diagonal lean.
##
## Consequently a unit at CONSTANT velocity flies level, however fast it is going: with
## no acceleration there is no thrust to tilt toward. (A real helicopter does hold a
## slight nose-down in steady cruise, to beat drag — if that reads as too flat, add a
## small speed-proportional term on top of the acceleration lean rather than going back
## to a speed-driven pitch, which held a fixed 25° dip through the whole cruise.)
##
## HOVER_TILT_PER_ACCEL is radians of lean per world-unit/s² of horizontal acceleration,
## and HOVER_MAX_LEAN caps the lean's MAGNITUDE (see _apply_hover_bank for why the cap is
## on the vector rather than per-axis). At the current values a unit with the Petrel's
## max_acceleration of 3.0 reaches ~0.36 rad of demand and so sits on the 20° cap under
## full thrust; halve the factor for a unit that should stay flatter.
##
## HOVER_BANK_RESPONSE is the per-tick fraction the visible attitude eases toward its
## target (exponential smoothing at the 30 Hz physics rate), so heading and thrust
## changes read as leans, not snaps.
const HOVER_TILT_PER_ACCEL: float = 0.12
const HOVER_MAX_LEAN: float = deg_to_rad(20)
const HOVER_BANK_RESPONSE: float = 0.15

## Aerial terrain-following (see _update_aerial_altitude). Rather than snap an aerial
## unit's Y rigidly to terrain_height + offset each tick — which jerks the body up and
## down as it crosses uneven ground — the base terrain height it follows is eased under
## a bounded vertical acceleration.
##
## MAX_VERTICAL_ACCEL — hardest the climb/descent RATE may change, world-units/s².
##   Higher ≈ the old rigid snap; lower ≈ floatier. (No max vertical SPEED cap today;
##   a tall cliff briefly climbs fast — add one here if that ever reads as too abrupt.)
## AERIAL_LOOKAHEAD_SECONDS — how far ahead, in seconds of travel at the current
##   velocity, terrain is sampled so the unit starts climbing before it reaches a rise.
## AERIAL_LOOKAHEAD_SAMPLES — points sampled from here to the look-ahead position; the
##   MAX height wins, so a rise anywhere along the span lifts the unit in time.
const MAX_VERTICAL_ACCEL: float = 5.0
const AERIAL_LOOKAHEAD_SECONDS: float = 0.6
const AERIAL_LOOKAHEAD_SAMPLES: int = 4

## FLYING dive-attack descent (see _descend_toward_dive). The dive rate is NOT a flat
## speed: it is derived each tick from the geometry — the remaining drop over the time the
## current closing speed needs to cover the remaining ground — so the unit arrives at its
## target's altitude exactly as it arrives over it. As the horizontal gap closes, the
## demanded rate steepens on its own, which is what turns a shallow approach into a
## near-vertical terminal dive.
##
## DIVE_MAX_DESCENT_RATE caps the dive, and DIVE_ACCEL bounds how fast the rate itself may
## change so the nose-over reads as a push rather than a snap. Both are generous compared
## with level flight: a diving unit is deliberately committing. Why the rate is derived:
## gdd/systems/combat/aerial-operations/attack-runs.md §A dive commits on TIME.
const DIVE_MAX_DESCENT_RATE: float = 20.0
const DIVE_ACCEL: float = 30.0

## Airplane attitude for FLYING units (see _apply_flying_attitude). Yaw is already the
## body's own (Movement.get_facing tracks velocity); these two add the rest of the aircraft.
##
## PITCH is the flight-path angle — atan2(descent, forward) — so the nose points where the
## unit is actually going: level in cruise, steepening on its own into a near-vertical
## terminal dive.
##
## ROLL is a COORDINATED-TURN bank: tan(bank) = v·yaw_rate / g, the angle at which a real
## aircraft's lift vector supplies exactly the centripetal force its current turn needs. So
## a fast unit in a tight turn lays right over, and a gentle course correction barely tips.
## FLYING_BANK_GRAVITY is that g — a tuning knob, not a physical constant: lowering it
## banks harder for the same turn.
##
## NOTE this bank is COSMETIC. A real aircraft rolls first and the turn follows from the
## banked lift vector; here the turn is still driven by Movement's velocity steering and the
## roll is derived from it after the fact.
const FLYING_BANK_GRAVITY: float = 9.8
const FLYING_MAX_BANK: float = deg_to_rad(55)
const FLYING_ATTITUDE_RESPONSE: float = 0.2

## Ground speed while taxiing, as a fraction of cruise. An aircraft on the deck moves like
## a vehicle, not like the thing that just flew in.
const TAXI_SPEED_FACTOR: float = 0.35
## How close to a taxi waypoint counts as reached, in world units.
const TAXI_ARRIVAL: float = 0.08
## How closely a taxiing unit must be pointed at its next waypoint before it will roll, in
## radians. An aircraft on the ground turns and drives as separate actions — it does not
## crab sideways across the tarmac — so it stops, swings the nose round, and only then goes.
const TAXI_FACING_EPSILON: float = 0.03

## How far from the anchor (as a fraction of orbit_radius) a unit must be before its
## BEARING from that anchor is treated as a real direction rather than arrival jitter.
## Inside it, set_anchor() seeds the orbit from the unit's heading instead — see there.
const ORBIT_ENTRY_CENTRED_FRACTION: float = 0.5
#endregion

#region Properties
## The phase of a landing. AIRBORNE is flying normally at AERIAL_HEIGHT; LANDING descends
## toward the ground or a deck, with horizontal movement suppressed; GROUNDED_TEMP is down
## and waiting; TAKING_OFF climbs back to AERIAL_HEIGHT.
enum LandingState {
	AIRBORNE,
	LANDING,
	GROUNDED_TEMP,
	## On the deck and rolling along an authored path — out to a runway threshold before
	## climbing, or in from one after touching down. Command-driven velocity is ignored
	## throughout: the aircraft is following the tarmac, not an order.
	TAXIING,
	TAKING_OFF
}

## Which kind of aircraft: Movement.Mode.HOVERING or Movement.Mode.FLYING. GROUNDED is not a
## flight mode — a piece that does not fly carries no Aerial at all.
@export var mode: Movement.Mode = Movement.Mode.HOVERING

@export_group("Flying")
## Orbit parameters for FLYING mode. The unit circles the anchor while idle.
@export var orbit_radius: float = 3.0  ## desired orbit distance of this unit
@export var orbit_speed: float = 1.5  ## speed of unit while orbiting, world-units/second

## Horizontal distance (world units) at which a FLYING unit COMMITS to its dive-attack
## descent. Outside it the unit holds cruise altitude; inside, it noses over and descends
## at whatever rate reaches the target's altitude on arrival (see _descend_toward_dive).
## Driven by request_dive() / _update_flying_height().
@export var dive_distance: float = 3.0

## Terminal guidance: how much harder a FLYING unit may turn while committed to its dive
## (multiplies Movement.turn_rate, see turn_rate_multiplier).
##
## Without this a ramming attack is GEOMETRICALLY IMPOSSIBLE. A unit's minimum turn radius
## is speed / turn_rate — for the kamikaze, 4.0 / 120°/s = 1.9 world units, nearly four
## times its 0.5-unit weapon reach. So the moment it overflies its target it can never
## curve back onto it: it just orbits at arm's length forever. Closing that needs ~458°/s,
## which is what the default 4x buys. Cruise handling is untouched — the boost applies only
## on the run in, which is also when a real interceptor pulls hardest.
@export var dive_turn_rate_multiplier: float = 4.0

## Orbit angular speed in degrees/second (derived from orbit_speed / orbit_radius).
var orbit_angular_speed: float:
	get:
		return rad_to_deg(orbit_speed / orbit_radius)

## The point a FLYING unit orbits while idle — the last command destination, set whenever a
## command ends. Seeded from the host's position in _ready.
var _anchor: Vector3 = Vector3.ZERO

## Current angle (radians) on the orbit circle, updated each tick by compute_orbit_velocity().
var _orbit_angle: float = 0.0

## The current phase of a landing. Always AIRBORNE unless something grounded the piece.
var _landing_state: LandingState = LandingState.AIRBORNE

## Previous tick's velocity, used by _apply_hover_bank to derive the horizontal
## acceleration that drives an AIRBORNE HOVERING unit's pitch/roll lean. Kept in
## sync (without applying a lean) in every non-AIRBORNE state so the bank doesn't
## jump on the next takeoff.
var _prev_tilt_velocity: Vector3 = Vector3.ZERO

## Aerial terrain-following state (see _update_aerial_altitude). _smoothed_terrain_y is
## the eased base terrain height the unit follows — Commandable adds height_offset() to
## it for the final world Y (follow_y). _vertical_velocity is its current rate of
## change (world-units/s), ramped under MAX_VERTICAL_ACCEL. Seeded to the actual terrain
## height on the first tick (guarded by _aerial_y_seeded) so the unit doesn't ease up
## from zero on spawn.
var _smoothed_terrain_y: float = 0.0
var _vertical_velocity: float = 0.0
var _aerial_y_seeded: bool = false

## When true the unit grounded itself with an explicit Land command and will stay
## down until a movement command is issued. Blocks the automatic take_off() that
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

## Height offset the current landing settles ONTO, rather than the ground. Zero for every
## ordinary landing; a docking pad on a raised deck sets its own deck_height here so the
## aircraft comes to rest on the deck instead of sinking through it.
var _landing_deck_offset: float = 0.0

## True while the descent in progress is onto a DOCKING PAD rather than onto open terrain.
##
## It exists to switch off the two navmesh safeguards that make an ordinary landing safe
## and a pad landing impossible. An airfield's cells are BUILDING cells, so they are
## impassable by construction: _compute_landing_correction would steer the aircraft AWAY
## from the pad to the nearest navigable ground, and _snap_to_navmesh would teleport it
## off the deck the instant it touched down. Both are exactly right for a helicopter
## setting down in the field and exactly wrong for one parking on a runway, so a pad
## landing supplies its own target and keeps it.
var _pad_landing: bool = false

## The ground path this unit is rolling along while TAXIING, what it does on reaching the
## end, and how far through it is. Empty when not taxiing.
var _taxi_path: Array[Vector3] = []
var _taxi_index: int = 0
var _taxi_on_complete: Callable = Callable()
## Legs from this index on are the TAKEOFF ROLL rather than an apron taxi: the aircraft
## opens up toward flight speed along them. -1 for a path with no roll in it (an arrival).
var _taxi_roll_from: int = -1
## Current ground speed, eased between the taxi and roll targets under max_acceleration so
## the aircraft winds up down the strip instead of jumping to flight speed at the threshold.
var _taxi_speed: float = 0.0

## Set when Movement hands on a commanded velocity, and cleared at the end of each tick. Lets
## the climb-out tell "an order is steering me" from "nothing is", so a departing aircraft can
## turn the moment it is off the ground without a commandless one stalling in mid-air.
var _velocity_commanded: bool = false

## The piece's height above the terrain it follows. Animated during a landing (decreasing),
## a take-off (increasing), and a FLYING dive-attack and its climb back to cruise.
var _current_height_offset: float = AERIAL_HEIGHT

## Signed rate (world-units/second) at which _current_height_offset is currently changing
## during a landing or takeoff — negative descending, positive ascending. Ramped under
## LANDING_ACCEL by _step_height_offset, and zeroed once the manoeuvre settles, so a unit at
## rest always starts its next descent/ascent from a standstill. A mid-manoeuvre reversal
## (land_permanently() during a takeoff) eases through zero rather than snapping.
var _landing_rate: float = 0.0

## FLYING dive-attack state. request_dive() raises _dive_requested each tick a FLYING
## unit is attacking a ground target, recording the target's XZ in _dive_target_xz;
## _update_flying_height() consumes (clears) the flag. Because it self-clears, the unit
## only keeps diving while the requests keep arriving — once they stop (target lost,
## attack ended, or target out of dive_distance handling) it eases back to AERIAL_HEIGHT.
var _dive_requested: bool = false
var _dive_target_xz: Vector2 = Vector2.ZERO

## Current descent rate of a FLYING dive, world-units/second (positive = descending).
## Ramped under DIVE_ACCEL toward the geometry-derived demand, and reset to 0 whenever the
## unit is not committed to a dive so the next one starts from level flight.
var _dive_rate: float = 0.0

## Body yaw sampled at the end of the previous tick, used to derive the turn rate that
## drives a FLYING unit's coordinated bank. NAN until the first sample, so the first tick
## contributes no spurious turn.
var _prev_flying_yaw: float = NAN

## True while a FLYING unit is inside its dive commit window (see _update_flying_height).
## Gates terminal guidance — the harder turn that lets a ramming run actually connect.
var _dive_committed: bool = false
#endregion


#region Lifecycle
func _ready() -> void:
	var host: Node3D = _host()
	if host != null:
		_anchor = host.global_position


func _physics_process(_a_delta: float) -> void:
	if _movement_is_dormant():
		return
	if mode == Movement.Mode.FLYING:
		# Docking SUSPENDS normal flight: while a landing is under way _update_flying_height
		# must not run at all, since it owns the altitude and would push it straight back to
		# AERIAL_HEIGHT against the descent. See _tick_flying_landing.
		if _landing_state != LandingState.AIRBORNE:
			_tick_flying_landing()
		else:
			_update_flying_height()
		_update_aerial_altitude()
		_velocity_commanded = false
		return
	_velocity_commanded = false
	# Ease the terrain height this unit follows (once per tick, before any early
	# return below) so it rises and falls smoothly over uneven ground.
	_update_aerial_altitude()
	# Body attitude — applied to the MODEL only (see _attitude_node), so none of this
	# touches the collision, aggro, vision or attack-range shapes. AIRBORNE units bank into
	# their horizontal acceleration (helicopter lean — pitch on rotation.x, roll on
	# rotation.z); LANDING / TAKING_OFF nose up/down from vertical motion (set in the match
	# below); GROUNDED_TEMP eases back to level. Every non-AIRBORNE state also keeps the
	# bank's velocity baseline current so the lean doesn't jump on the next takeoff.
	match _landing_state:
		LandingState.AIRBORNE:
			_apply_hover_bank()
		LandingState.GROUNDED_TEMP:
			_prev_tilt_velocity = _velocity()
			_level_body()
		_:
			_prev_tilt_velocity = _velocity()
	# Pre-landing navigation: stay AIRBORNE and steer to the safe landing spot
	# before beginning the descent. Descent starts once we arrive.
	if _pending_land and _landing_state == LandingState.AIRBORNE:
		var to_target: Vector3 = _landing_target - _host().global_position
		to_target.y = 0.0
		if to_target.length() <= Movement.HOVERING_ARRIVAL_DISTANCE:
			_pending_land = false
			_has_landing_target = false
			_landing_state = LandingState.LANDING
		else:
			var tps: float = Engine.physics_ticks_per_second
			# Brake as the unit closes in: cap speed so it arrives in at most 1 tick
			# when very close, preventing overshoot of a nearby target cell center.
			var desired_speed: float = minf(_speed(), to_target.length() * tps)
			_drive(to_target.normalized() * desired_speed)
		return
	match _landing_state:
		LandingState.TAXIING:
			_tick_taxi()
		LandingState.LANDING:
			_apply_hover_tilt(_descend_to_touchdown())
			if _current_height_offset <= _landing_deck_offset:
				_landing_state = LandingState.GROUNDED_TEMP
				_has_landing_target = false
				# A pad landing keeps where it put itself: the deck is a building cell, so the
				# navmesh snap would shove the aircraft off it (see _pad_landing).
				if not _pad_landing:
					_snap_to_navmesh()  # last-resort snap if steering fell short
				if _land_on_complete.is_valid():
					_land_on_complete.call()
			elif _has_landing_target:
				_steer_during_descent()
			else:
				# No correction needed; decelerate horizontal velocity to zero.
				_brake_during_descent()
		LandingState.TAKING_OFF:
			_apply_hover_tilt(_step_height_offset(AERIAL_HEIGHT))
			if _current_height_offset >= AERIAL_HEIGHT:
				_landing_state = LandingState.AIRBORNE


#endregion


#region Public API
## `a_piece`'s Aerial component, or null when it does not fly.
static func of(a_piece: Node) -> Aerial:
	return a_piece.get_node_or_null("Aerial") as Aerial if a_piece != null else null


## World-units above the terrain surface Commandable adds when snapping Y.
func height_offset() -> float:
	return _current_height_offset


## The base terrain height the piece should sit at this tick — the acceleration-smoothed value
## maintained by _update_aerial_altitude. Returns `a_fallback_terrain_y` (the raw terrain
## height at the piece's XZ) until the smoother has been seeded, so spawn and the map-less
## unit-test path behave exactly like a rigid snap.
func follow_y(a_fallback_terrain_y: float) -> float:
	return _smoothed_terrain_y if _aerial_y_seeded else a_fallback_terrain_y


## Whether this aircraft can come to a dead stop and stay there. FLYING cannot: a fixed wing
## that stopped in mid-air would be a helicopter, and it has no hover to do it with.
func can_hold_still() -> bool:
	return mode != Movement.Mode.FLYING


## True when this unit is airborne at cruise altitude — not in any stage of a landing
## (descending, grounded, taxiing or ascending).
##
## A parked aeroplane is therefore shot at with a weapon's GROUND range rather than its air
## range (see Weapon.get_range_for_target, the one consumer). A plane sitting on a deck being
## immune to everything that cannot shoot upward would be a considerable exploit.
func is_airborne() -> bool:
	return _landing_state == LandingState.AIRBORNE


## True while the unit is on the ground waiting (GROUNDED_TEMP state).
func is_grounded_temp() -> bool:
	return _landing_state == LandingState.GROUNDED_TEMP


## True when the unit was grounded by an explicit Land command (not by the
## garrison system). Use this to gate the Land button's precondition.
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


## True while this unit is parked on a docking pad — grounded by land_at rather than by
## land() or a Land command. Lets the docking sequence tell "on the deck" from "set down
## in a field", which look identical through is_grounded_temp() alone.
func is_docked() -> bool:
	return _pad_landing and _landing_state == LandingState.GROUNDED_TEMP


## True while rolling along a taxi path. Distinct from is_docked(), which means PARKED.
func is_taxiing() -> bool:
	return _landing_state == LandingState.TAXIING


#endregion


#region Talking to locomotion
## Whether a commanded velocity must be ignored this tick. Landing, being on the ground,
## taxiing and pre-landing navigation are all driven from here, and none of them is the
## command system's to override: a unit rolling along a taxiway is following the tarmac, not
## an order. TAKING_OFF is deliberately NOT suppressed — an aircraft that has left the runway
## is flying, and an order may steer it from the first tick of the climb.
func suppresses_commanded_velocity() -> bool:
	return (
		_landing_state == LandingState.LANDING
		or _landing_state == LandingState.GROUNDED_TEMP
		or _landing_state == LandingState.TAXIING
		or _pending_land
	)


## A commanded velocity, after acceleration limits, as this aircraft will actually fly it.
## Records that an order is steering it (see _velocity_commanded); a HOVERING unit still
## climbing off the ground is kept clear of the buildings it has not yet risen above.
func shape_commanded_velocity(a_velocity: Vector3) -> Vector3:
	_velocity_commanded = true
	if _landing_state == LandingState.TAKING_OFF and mode == Movement.Mode.HOVERING:
		return _cap_xz_for_ascent(a_velocity)
	return a_velocity


## How much harder than its authored turn rate the piece may turn this tick: the dive's
## terminal guidance while committed, otherwise 1.
func turn_rate_multiplier() -> float:
	return dive_turn_rate_multiplier if _dive_committed else 1.0


#endregion


#region Landing
## Begin a smooth descent to terrain level. `on_complete` is called once the
## unit touches down and transitions to GROUNDED_TEMP. Idempotent: a second
## call while a landing is already in progress is silently ignored.
## A FLYING unit cannot set down in a field: on_complete fires immediately and nothing else
## changes.
func land(a_on_complete: Callable) -> void:
	if mode != Movement.Mode.HOVERING:
		if a_on_complete.is_valid():
			a_on_complete.call()
		return
	if _landing_state != LandingState.AIRBORNE or _pending_land:
		return
	_land_on_complete = a_on_complete
	_try_start_landing()


## Begin a descent onto a DOCKING PAD at `pad_position`, coming to rest `deck_offset`
## above the terrain there. `on_complete` fires on touchdown, as for land().
##
## Why it works this way: gdd/systems/combat/aerial-operations/docking-bays-and-pads.md
## §`land_at`: landing on a building deck.
func land_at(a_pad_position: Vector3, a_deck_offset: float, a_on_complete: Callable) -> void:
	if not _docks():
		if a_on_complete.is_valid():
			a_on_complete.call()
		return
	if _landing_state == LandingState.LANDING or _landing_state == LandingState.GROUNDED_TEMP:
		return
	_pad_landing = true
	_landing_deck_offset = maxf(a_deck_offset, 0.0)
	_landing_target = a_pad_position
	_has_landing_target = true
	_pending_land = false
	_land_on_complete = a_on_complete
	_landing_state = LandingState.LANDING


## Ground this unit covers, at its own cruise speed, while descending from AERIAL_HEIGHT to
## `deck_offset` — i.e. how far out an approach must begin for the unit to arrive AT the
## deck rather than over it.
##
## Same shape as _dive_commit_distance and for the same reason: a descent is a TIME-limited
## manoeuvre, so a distance authored as a constant is speed-blind and a faster aircraft
## arrives high. Read by Rearm to place the start of a FLYING unit's approach; a HOVERING
## unit ignores it and descends from directly overhead, which is what a helicopter does.
func descent_run_distance(a_deck_offset: float = 0.0) -> float:
	return _speed() * _seconds_to_change_offset(AERIAL_HEIGHT - a_deck_offset)


## Begin a smooth ascent back to AERIAL_HEIGHT. No-op unless the unit is
## GROUNDED_TEMP. Also blocked when the unit grounded itself with a Land
## command (_permanently_grounded); use take_off_for_movement() in that case.
func take_off() -> void:
	if _landing_state != LandingState.GROUNDED_TEMP or _permanently_grounded:
		return
	_clear_pad_landing()
	_landing_state = LandingState.TAKING_OFF


## Like take_off() but also clears _permanently_grounded so a movement command
## can lift a unit that grounded itself with a Land command.
func take_off_for_movement() -> void:
	_permanently_grounded = false
	if _landing_state == LandingState.GROUNDED_TEMP:
		_clear_pad_landing()
		_landing_state = LandingState.TAKING_OFF


## Descend and remain grounded until a movement command is issued. Sets
## _permanently_grounded so garrison auto-take-off is suppressed.
## Reverses a mid-ascent (TAKING_OFF → LANDING) so the command is always
## respected immediately. Idempotent while already on the ground.
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


## Put this unit on a deck immediately, with no approach and no descent — the state a
## returning aircraft reaches at the END of land_at, entered directly.
##
## For an aircraft ROLLED OUT by the airfield that built it: it belongs on the pad from its
## first frame rather than being flown down onto one it was never above. Flagged as a pad
## landing so is_docked() reports true and take_off() will lift it, exactly as though it
## had flown in.
func park_on_deck(a_deck_offset: float = 0.0) -> void:
	if not _docks():
		return
	_pad_landing = true
	_landing_deck_offset = maxf(a_deck_offset, 0.0)
	_current_height_offset = _landing_deck_offset
	_landing_state = LandingState.GROUNDED_TEMP
	_pending_land = false
	_has_landing_target = false
	_set_velocity(Vector3.ZERO)
	_dive_rate = 0.0
	_dive_committed = false


## Roll along `path` on the deck, then call `on_complete`. The ONE ground-drive, used by
## both halves of the choreography: out from a pad to a runway threshold before climbing,
## and back in from one after touching down.
##
## POSITION, not velocity: a commanded velocity is suppressed outright while a unit is on the
## deck, so a velocity handed to a taxiing aircraft goes nowhere. Y is left alone —
## Commandable rewrites it from the terrain every tick.
##
## Refused unless the unit is actually on the deck, so this can never be mistaken for a
## flight instruction. A HOVERING dock would simply not call it: a helicopter has no
## roll-out, it comes straight down onto its pad and lifts straight off it again.
func taxi_along(a_path: Array[Vector3], a_on_complete: Callable, a_roll_from: int = -1) -> void:
	if not _docks() or _landing_state != LandingState.GROUNDED_TEMP:
		return
	if a_path.is_empty():
		if a_on_complete.is_valid():
			a_on_complete.call()
		return
	_taxi_path = a_path
	_taxi_index = 0
	_taxi_on_complete = a_on_complete
	_taxi_roll_from = a_roll_from
	_taxi_speed = VU.in_xz(_velocity()).length()
	_landing_state = LandingState.TAXIING


## Forget that the last landing was onto a pad, so the ordinary navmesh safeguards apply
## to the next one. Called from both take-off paths — an aircraft that has left the deck
## is an ordinary aircraft again, and the deck offset must not survive to raise its
## resting height the next time it sets down in a field.
func _clear_pad_landing() -> void:
	_pad_landing = false
	_landing_deck_offset = 0.0


## Navigate to the predicted touchdown position (or nearest passable cell if off
## navmesh) before descending. If the predicted position is already passable,
## begin the descent immediately. Called from land() and land_permanently().
func _try_start_landing() -> void:
	_compute_landing_correction()
	if _has_landing_target:
		_pending_land = true  # navigate first, then descend on arrival
	else:
		_landing_state = LandingState.LANDING  # safe to descend here directly


## Steer toward `_landing_target` during a descent, capping speed so the unit arrives
## horizontally exactly as it touches down. Shared by both modes: it is what makes a
## landing read as an approach rather than a drop, and for a FLYING unit — which has no
## hover to sink from — it is the whole approach.
func _steer_during_descent() -> void:
	var to_target: Vector3 = _landing_target - _host().global_position
	to_target.y = 0.0
	var dist: float = to_target.length()
	if dist <= Movement.HOVERING_ARRIVAL_DISTANCE:
		_brake_during_descent()
		return
	# A PAD LANDING FLIES THE APPROACH AT SPEED and lets the DESCENT RATE do the fitting (see
	# _descend_to_touchdown). Slowing the aircraft to match a fixed sink rate is the wrong way
	# round for a runway: it made the aeroplane crawl the last stretch of its final, and any
	# mismatch between the two came out as touching down early — on open ground, short of the
	# tarmac. Setting down in a field keeps the old cap, since there is no mark to hit.
	var desired: Vector3 = to_target.normalized() * _speed()
	if not _pad_landing:
		var time_remaining: float = _seconds_to_change_offset(
			_current_height_offset - _landing_deck_offset
		)
		var max_speed: float = dist / time_remaining if time_remaining > 1e-4 else _speed()
		desired = to_target.normalized() * minf(_speed(), max_speed)
	_drive(desired)


## Sink so as to arrive at deck level EXACTLY over the touchdown mark, whatever speed the
## aircraft happens to be doing. Returns the height change applied this tick.
##
## The rate is derived from the ground still to cover, not the other way round: at the
## current closing speed the aircraft is `dist / speed` seconds from the mark, so it must
## shed `height / that` per second to be down when it gets there. Recomputed every tick, so
## a slower or faster final simply changes the glide angle instead of moving the touchdown
## point — which is what "land at the end of the runway" has to mean.
##
## Falls back to the flat profile when there is no mark to aim at (a field landing) or the
## aircraft is not closing on it.
func _descend_to_touchdown() -> float:
	if not _pad_landing or not _has_landing_target:
		return _step_height_offset(_landing_deck_offset)
	var dist: float = VU.in_xz(_landing_target).distance_to(VU.in_xz(_host().global_position))
	var closing: float = VU.in_xz(_velocity()).length()
	var drop: float = _current_height_offset - _landing_deck_offset
	if drop <= 0.0:
		return 0.0
	if closing < 1e-3 or dist <= Movement.HOVERING_ARRIVAL_DISTANCE:
		return _step_height_offset(_landing_deck_offset)
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	var seconds_out: float = dist / closing
	var rate: float = minf(drop / seconds_out, DIVE_MAX_DESCENT_RATE)
	var previous: float = _current_height_offset
	_current_height_offset = maxf(_landing_deck_offset, _current_height_offset - rate * dt)
	_landing_rate = -rate
	return _current_height_offset - previous


## Bleed horizontal speed off during a descent with nowhere left to steer to.
func _brake_during_descent() -> void:
	if _velocity().is_zero_approx():
		return
	_drive(Vector3.ZERO)


## One tick of a FLYING unit's pad landing — the fixed-wing counterpart of the HOVERING
## LANDING / GROUNDED_TEMP / TAKING_OFF block in _physics_process.
##
## FLYING has no landing regime of its own: `_update_flying_height` owns the altitude and
## pushes it back to AERIAL_HEIGHT every tick, and an idle FLYING unit orbits rather than
## stopping. So docking one is not a matter of reusing the hover landing — it is a matter
## of SUSPENDING normal flight, which is what `_landing_state != AIRBORNE` means for this
## mode. `_physics_process` routes here instead of `_update_flying_height` while that holds,
## so the two never fight over `_current_height_offset`.
##
## Only ever reached for a PAD landing: nothing else sets a FLYING unit's landing state, so
## `land()` and the Land command remain HOVERING-only.
func _tick_flying_landing() -> void:
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	match _landing_state:
		LandingState.LANDING:
			var change: float = _descend_to_touchdown()
			if _current_height_offset <= _landing_deck_offset:
				_landing_state = LandingState.GROUNDED_TEMP
				_has_landing_target = false
				_settle_on_deck()
				if _land_on_complete.is_valid():
					_land_on_complete.call()
				return
			if _has_landing_target:
				_steer_during_descent()
			else:
				_brake_during_descent()
			# Nose down along the descent path, as in a dive — the same attitude model, driven
			# by the landing rate instead of the dive rate.
			_apply_flying_attitude(-change / dt, VU.in_xz(_velocity()).length(), dt)
		LandingState.GROUNDED_TEMP:
			_settle_on_deck()
		LandingState.TAXIING:
			_tick_taxi()
		LandingState.TAKING_OFF:
			var change: float = _step_height_offset(AERIAL_HEIGHT)
			# Fly the climb-out rather than rising vertically off the pad: a fixed wing has to be
			# moving to be flying at all, and a plane that levitated to cruise altitude and only
			# then set off would look nothing like one.
			#
			# AN ORDER MAY STEER IT FROM THE FIRST TICK OF THE CLIMB. The aircraft has left the
			# runway and is flying; making it hold the runway heading all the way to cruise
			# altitude would be a long, rigid straight line out of every airfield. So this only
			# supplies a heading when nothing else did — a departure under orders turns as soon
			# as it is off the ground, and a commandless one still flies rather than stalling.
			if not _velocity_commanded:
				_accelerate_along_facing()
			_apply_flying_attitude(-change / dt, VU.in_xz(_velocity()).length(), dt)
			if _current_height_offset >= AERIAL_HEIGHT:
				_landing_state = LandingState.AIRBORNE
				_dive_rate = 0.0
				# Orbit from where it left, not from wherever the anchor was last set — otherwise
				# a plane that just took off turns straight back toward its old station.
				var host: Node3D = _host()
				if host != null:
					set_anchor(host.global_position)


## Drive the unit forward along the way it is already pointing, at its cruise speed and
## within its acceleration limits. The climb-out from a pad: it leaves the way it parked,
## which for an instant taxi is the closest thing to a runway heading available.
func _accelerate_along_facing() -> void:
	var movement: Movement = _movement()
	if movement == null:
		return
	_drive(movement.get_facing() * movement.effective_max_speed())


## Bring a parked FLYING unit fully to rest and level its model. A stopped aeroplane is
## just an object on the ground: no orbit, no bank, no residual velocity to carry it off
## its pad.
func _settle_on_deck() -> void:
	if not _velocity().is_zero_approx():
		_emit_velocity(Vector3.ZERO)
	_dive_rate = 0.0
	_dive_committed = false
	_level_body()


#endregion


#region Taxi
## Advance one tick of the roll. Reaching the last waypoint hands over to the completion
## callback, which is what starts a climb-out or finishes a park.
func _tick_taxi() -> void:
	var host: Node3D = _host()
	var movement: Movement = _movement()
	if host == null or movement == null or _taxi_index >= _taxi_path.size():
		_finish_taxi()
		return
	_level_body()
	var here: Vector2 = VU.in_xz(host.global_position)
	var there: Vector2 = VU.in_xz(_taxi_path[_taxi_index])
	var to_target: Vector2 = there - here
	var distance: float = to_target.length()
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	# TWO REGIMES. Crossing the apron is a crawl — an aircraft on a taxiway is a vehicle. The
	# last leg of a DEPARTURE is the takeoff roll down the strip, and there it is winding up
	# toward flight speed, because that is what leaving the ground requires.
	var rolling: bool = _taxi_roll_from >= 0 and _taxi_index >= _taxi_roll_from
	var target_speed: float = movement.speed if rolling else movement.speed * TAXI_SPEED_FACTOR
	var accel: float = (
		movement.max_acceleration if movement.max_acceleration != INF else movement.speed
	)
	_taxi_speed = move_toward(_taxi_speed, target_speed, accel * dt)
	var step: float = _taxi_speed * dt
	# Arriving SNAPS to the mark rather than stopping near it: a waypoint is a spot, not a
	# tolerance, and leaving the last few centimetres on the clock would show as aircraft
	# sitting slightly differently on identical pads.
	if distance <= maxf(TAXI_ARRIVAL, step):
		host.global_position.x = there.x
		host.global_position.z = there.y
		_taxi_index += 1
		if _taxi_index >= _taxi_path.size():
			_finish_taxi()
		return
	# TURN, THEN ROLL — never both. On the ground an aircraft is a vehicle with a nosewheel:
	# it stops, swings round to point at where it is going, and only then drives. Doing both
	# at once slid it diagonally across the apron, which is the one thing an aeroplane cannot
	# do. The velocity is left at zero through the turn so the stop is real.
	var aim: Vector3 = Vector3(there.x, host.global_position.y, there.y)
	if not movement.is_facing_within(aim, TAXI_FACING_EPSILON):
		movement.turn_toward(VU.from_xz(to_target))
		_set_velocity(Vector3.ZERO)
		_taxi_speed = 0.0
		return
	var moved: Vector2 = here + to_target / distance * step
	host.global_position.x = moved.x
	host.global_position.z = moved.y
	# CARRY THE VELOCITY, even though the roll is written as position. It is what the aircraft
	# is actually doing, and the climb-out reads it as its starting heading — without it the
	# turn-rate clamp sees a standing start, has no heading to turn FROM, and takes the first
	# commanded direction whole. A jet leaving the runway snapped through 180 degrees.
	_set_velocity(VU.from_xz(to_target / distance) * _taxi_speed)


func _finish_taxi() -> void:
	var done: Callable = _taxi_on_complete
	_taxi_path = []
	_taxi_index = 0
	_taxi_roll_from = -1
	_taxi_on_complete = Callable()
	_landing_state = LandingState.GROUNDED_TEMP
	# The velocity is deliberately NOT zeroed: a departure hands straight over to the climb,
	# which needs the runway heading to turn from. A taxi that ends at a pad is stopped by
	# _settle_on_deck on the next tick instead.
	if done.is_valid():
		done.call()


#endregion


#region FLYING orbit
## Set the anchor that a FLYING unit circles while idle. Initialises _orbit_angle
## from the unit's current position so the orbit starts without a positional jump.
func set_anchor(a_pos: Vector3) -> void:
	_anchor = a_pos
	var host: Node3D = _host()
	if host == null:
		return
	var offset: Vector2 = VU.in_xz(host.global_position) - VU.in_xz(a_pos)
	var heading: Vector2 = VU.in_xz(_velocity())
	# Seed the orbit clock so the unit enters the pattern from where it is, going the way it
	# is already going. Which reading is meaningful depends on where it is:
	#
	#   OFF-CENTRE — an anchor set while the unit is somewhere else. Its bearing from the
	#     anchor is real, so start the clock there and it flies the arc it is already on.
	#
	#   ON THE ANCHOR — the normal case, because the anchor is the destination the unit just
	#     ARRIVED at. Here the offset is pure arrival jitter, well under the arrival
	#     tolerance, and carries no usable direction. Seeding off it put the first ideal point
	#     somewhere unrelated to travel, and the unit turned twice before settling.
	#
	# From the centre no entry is free — every point on the circle is radially outward — but
	# flying straight ahead costs nothing now and leaves a single, natural turn onto the
	# circle later. So seed the clock to put the first ideal point directly in front.
	if offset.length() >= orbit_radius * ORBIT_ENTRY_CENTRED_FRACTION:
		_orbit_angle = atan2(offset.y, offset.x)
	elif not heading.is_zero_approx():
		_orbit_angle = atan2(heading.y, heading.x)
	# Stationary on the anchor: no bearing and no heading to prefer — keep the current angle.


## Advance the orbit one physics tick and return the XZ velocity (Y=0) that moves
## the unit toward the next point on the orbit circle. Hand this to Movement.set_velocity so
## accel/turn-rate limits are applied normally.
##
## A VECTOR FIELD, not a chase. At any point the unit is told which way to fly: blend the
## circle's tangent (which carries it round) with the outward radial (which carries it to the
## right radius), weighted purely by how far off-radius it currently is. The two weights are
## a unit decomposition — w outward, sqrt(1-w²) tangential — so the result is already a
## direction:
##
##   at the centre  (w = 1) — straight out along its heading, no sideways lurch;
##   on the circle  (w = 0) — pure tangent, a clean orbit;
##   outside it     (w < 0) — angled back in.
##
## A field has no carrot to outrun: however fast the unit arrives, every point still names a
## direction that converges on the circle, which is what stops a fast arrival sailing out
## past the radius and being hauled back in.
func compute_orbit_velocity() -> Vector3:
	var host: Node3D = _host()
	if host == null:
		return Vector3.ZERO
	# A parked or landing plane does not orbit. CommandReceiver feeds this to any idle FLYING
	# unit every tick, so without the gate a plane whose docking order ended — or was
	# interrupted while it sat on the deck — would taxi off its pad in a circle.
	if _landing_state != LandingState.AIRBORNE:
		return Vector3.ZERO
	var centre: Vector2 = VU.in_xz(_anchor)
	var offset: Vector2 = VU.in_xz(host.global_position) - centre
	var radius_now: float = offset.length()
	# Outward radial. Sitting exactly on the anchor there is no bearing to read, so fall back
	# to the orbit clock — which set_anchor() seeded from the unit's heading precisely for
	# this tick, so it sets off the way it is already pointing.
	var outward: Vector2 = (
		offset / radius_now if radius_now > 1e-3 else Vector2(cos(_orbit_angle), sin(_orbit_angle))
	)
	var tangent: Vector2 = Vector2(-outward.y, outward.x)  # +90 deg: the CCW orbit direction
	var radial_weight: float = clampf((orbit_radius - radius_now) / orbit_radius, -1.0, 1.0)
	var dir: Vector2 = outward * radial_weight + tangent * sqrt(1.0 - radial_weight * radial_weight)
	# Keep the clock in step with where the unit actually is, so anything reading it (and the
	# centre fallback above) stays meaningful.
	_orbit_angle = atan2(outward.y, outward.x)
	return VU.from_xz(dir) * orbit_speed


#endregion


#region FLYING dive-attack
## Ask a FLYING unit to dive toward `target_xz` (a world XZ) this tick: it descends from
## AERIAL_HEIGHT toward the ground as it closes within `dive_distance`. Call every tick the
## dive should continue (e.g. from Attack while a FLYING actor attacks a ground target) —
## the request self-clears, so the moment the calls stop the unit eases back up to cruise
## altitude. No-op outside FLYING mode.
func request_dive(a_target_xz: Vector2) -> void:
	if mode != Movement.Mode.FLYING:
		return
	_dive_requested = true
	_dive_target_xz = a_target_xz


## Per-tick FLYING altitude control, called from _physics_process. Two regimes:
##   * committed to a dive — inside dive_distance of the requested target, descending at
##     the rate that lands it on the target's altitude (see _descend_toward_dive);
##   * otherwise — climbing back to AERIAL_HEIGHT at the flat LANDING_SPEED, wings level.
## Consumes (clears) _dive_requested, so the moment Attack stops asking, the unit pulls up
## and comes around for another pass rather than staying on the deck.
func _update_flying_height() -> void:
	var host: Node3D = _host()
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	var wants_dive: bool = _dive_requested and host != null and dive_distance > 0.0
	_dive_requested = false
	if wants_dive:
		var dist: float = VU.in_xz(host.global_position).distance_to(_dive_target_xz)
		if dist <= _dive_commit_distance(VU.in_xz(_velocity()).length()):
			_dive_committed = true
			_descend_toward_dive(dist, dt)
			return
	# Cruising (or still outside the commit window): recover altitude, nose level. The bank
	# still tracks the turn — a cruising aircraft banks through its course changes.
	_dive_committed = false
	_dive_rate = 0.0
	_current_height_offset = move_toward(_current_height_offset, AERIAL_HEIGHT, LANDING_SPEED * dt)
	_apply_flying_attitude(0.0, VU.in_xz(_velocity()).length(), dt)


## The horizontal distance at which a FLYING unit must nose over to still reach its target's
## altitude in time. A dive is TIME-limited, not distance-limited, so this scales with the
## unit's current speed and takes `dive_distance` as its floor. Computed from AERIAL_HEIGHT
## rather than the current altitude, so it does not shrink as the unit descends.
func _dive_commit_distance(a_horizontal_speed: float) -> float:
	var descent_time: float = (
		AERIAL_HEIGHT / DIVE_MAX_DESCENT_RATE + DIVE_MAX_DESCENT_RATE / DIVE_ACCEL
	)
	return maxf(dive_distance, a_horizontal_speed * descent_time)


## Drive one tick of a committed dive. The descent rate demanded this tick is the remaining
## drop over the time the current closing speed needs to cover the remaining ground — so
## the unit is level with its target exactly as it arrives over it. `_dive_rate` chases it
## under DIVE_ACCEL so the nose-over is a push, not a snap.
##
## With no closing speed (hovering over the target, or stopped) there is no arrival to time
## the descent against, so it simply drops at the cap.
func _descend_toward_dive(a_dist: float, a_dt: float) -> void:
	var horizontal_speed: float = VU.in_xz(_velocity()).length()
	var desired: float = DIVE_MAX_DESCENT_RATE
	if horizontal_speed > 1e-3 and a_dist > 1e-3:
		desired = _current_height_offset / (a_dist / horizontal_speed)
	desired = clampf(desired, 0.0, DIVE_MAX_DESCENT_RATE)
	_dive_rate = move_toward(_dive_rate, desired, DIVE_ACCEL * a_dt)
	_current_height_offset = maxf(0.0, _current_height_offset - _dive_rate * a_dt)
	_apply_flying_attitude(_dive_rate, horizontal_speed, a_dt)


#endregion


#region Attitude
## Fly a FLYING unit's MODEL like an aircraft: nose along the flight path, banked into the
## turn. Yaw is not touched here — the body already tracks its velocity direction, and the
## model inherits it.
##
## Pitch is the flight-path angle, so the nose points where the unit is actually going.
## Roll is the coordinated-turn bank for the yaw rate it is currently pulling. Both ease in
## at FLYING_ATTITUDE_RESPONSE. Applied to the model only (see _attitude_node) — no-op
## without a MeshVisual. See the constants block for the cosmetic-bank caveat.
func _apply_flying_attitude(a_descent_rate: float, a_horizontal_speed: float, a_dt: float) -> void:
	var host: Node3D = _host()
	var yaw_rate: float = 0.0
	if host != null:
		var yaw: float = host.rotation.y
		if not is_nan(_prev_flying_yaw) and a_dt > 0.0:
			yaw_rate = angle_difference(_prev_flying_yaw, yaw) / a_dt
		_prev_flying_yaw = yaw
	var attitude: Node3D = _attitude_node()
	if attitude == null:
		return

	# +rotation.x tips the +Z nose toward the ground, so a positive descent noses down.
	var target_pitch: float = atan2(maxf(a_descent_rate, 0.0), maxf(a_horizontal_speed, 1e-3))

	# Coordinated turn: tan(bank) = v * yaw_rate / g. A positive (left-hand) yaw rate needs
	# the left wing down; +rotation.z lifts the +X (right) side, so the sign lines up
	# directly. Clamped so a hard course reversal doesn't roll past vertical.
	var target_roll: float = clampf(
		atan(a_horizontal_speed * yaw_rate / FLYING_BANK_GRAVITY), -FLYING_MAX_BANK, FLYING_MAX_BANK
	)

	attitude.rotation.x = lerpf(attitude.rotation.x, target_pitch, FLYING_ATTITUDE_RESPONSE)
	attitude.rotation.z = lerpf(attitude.rotation.z, target_roll, FLYING_ATTITUDE_RESPONSE)


## The node that carries PITCH and ROLL — the MeshVisual, i.e. the art and nothing else.
##
## Deliberately NOT the host, which carries the range shapes: leaning those swung their
## ground-level footprint several world units off the unit. Yaw stays on the host because
## facing is REAL; pitch and roll are decoration. Null when there is no MeshVisual, and such
## a unit simply does not lean. Why, with the measured figures:
## gdd/systems/combat/aerial-operations/attack-runs.md §Pitch and roll go on the ART.
func _attitude_node() -> Node3D:
	var host: Node3D = _host()
	return host.get_node_or_null("MeshVisual") as Node3D if host != null else null


## Pitch the MODEL's rotation.x a little in response to vertical motion while
## LANDING/TAKING_OFF (`a_vertical_velocity` = this tick's change in _current_height_offset —
## negative while descending, positive while ascending). No-op without a MeshVisual.
## See HOVER_TILT_FACTOR for the known units mismatch that makes this barely visible.
## TODO: tune tilt for 3D model
func _apply_hover_tilt(a_vertical_velocity: float) -> void:
	var attitude: Node3D = _attitude_node()
	if attitude == null:
		return
	attitude.rotation.x = clampf(
		-a_vertical_velocity * HOVER_TILT_FACTOR, -HOVER_MAX_TILT, HOVER_MAX_TILT
	)
	# No lateral banking during a straight-down landing/takeoff — settle any
	# residual roll carried in from cruise.
	attitude.rotation.z = lerpf(attitude.rotation.z, 0.0, HOVER_BANK_RESPONSE)


## Give an AIRBORNE HOVERING unit a helicopter attitude: lean the airframe INTO its
## horizontal acceleration, whichever way that points.
##
## The lean is a single vector in the XZ plane — pointing along this tick's acceleration,
## with a magnitude proportional to it — and pitch (rotation.x) and roll (rotation.z) are
## that one lean resolved onto the body's forward and right axes. That makes the attitude
## read as the unit's thrust rather than as two independent effects, and it means
## constant-velocity flight is level: no acceleration, no rotor tilt to show.
##
## The visible rotation eases toward the target (HOVER_BANK_RESPONSE) so the lean reads
## smoothly even when the underlying velocity change is abrupt. Applied to the MODEL, not
## the body (see _attitude_node) — no-op without a MeshVisual.
func _apply_hover_bank() -> void:
	var attitude: Node3D = _attitude_node()
	var movement: Movement = _movement()
	if attitude == null or movement == null:
		return
	var tps: float = float(Engine.physics_ticks_per_second)
	var velocity: Vector3 = _velocity()
	var accel: Vector3 = (velocity - _prev_tilt_velocity) * tps
	_prev_tilt_velocity = velocity
	accel.y = 0.0
	var facing: Vector3 = movement.get_facing()  # +Z forward, unit XZ vector
	var right: Vector3 = Vector3(facing.z, 0.0, -facing.x)  # facing turned 90° clockwise

	# The lean, in body axes: x = along facing, y = along right.
	var lean: Vector2 = Vector2(accel.dot(facing), accel.dot(right)) * HOVER_TILT_PER_ACCEL
	# Clamp the lean as a VECTOR, not per-axis. Capping the two components independently
	# would let a 45° diagonal thrust lean sqrt(2) times further than a straight one, so
	# identical thrust would read as a bigger tilt purely because of its heading.
	if lean.length() > HOVER_MAX_LEAN:
		lean = lean.normalized() * HOVER_MAX_LEAN

	# +rotation.x tips the +Z nose toward the ground, so accelerating forward noses down.
	# +rotation.z LIFTS the +X (right) side, so accelerating rightward takes the opposite
	# sign to drop that side — banking into the turn rather than away from it.
	attitude.rotation.x = lerpf(attitude.rotation.x, lean.x, HOVER_BANK_RESPONSE)
	attitude.rotation.z = lerpf(attitude.rotation.z, -lean.y, HOVER_BANK_RESPONSE)


## Ease the model's pitch and roll back to level. Used while grounded so a unit that
## touched down mid-lean settles flat on the ground. No-op without a MeshVisual.
func _level_body() -> void:
	var attitude: Node3D = _attitude_node()
	if attitude == null:
		return
	attitude.rotation.x = lerpf(attitude.rotation.x, 0.0, HOVER_BANK_RESPONSE)
	attitude.rotation.z = lerpf(attitude.rotation.z, 0.0, HOVER_BANK_RESPONSE)


#endregion


#region Height
## Advance the aerial terrain-following height one tick. Eases _smoothed_terrain_y toward the
## HIGHEST terrain along the unit's near-future path under MAX_VERTICAL_ACCEL, so the body
## climbs and descends smoothly over uneven ground and lifts early enough to clear an upcoming
## rise. Terrain is sampled analytically via Map.terrain_height_at (a cheap bilinear heightmap
## read — no physics query and no structures), so this stays O(1) per unit regardless of the
## scene. No-op without a host or a Map.
func _update_aerial_altitude() -> void:
	var host: Node3D = _host()
	var map: Map = _map()
	if host == null or map == null:
		return
	var pos_xz: Vector2 = VU.in_xz(host.global_position)
	# Seed to the actual terrain on the first tick so the unit doesn't ease up from 0.
	if not _aerial_y_seeded:
		_smoothed_terrain_y = map.terrain_height_at(pos_xz)
		_vertical_velocity = 0.0
		_aerial_y_seeded = true
		return
	# Target = the highest terrain the unit is about to fly over. Sampling only the
	# single look-ahead point could miss a taller cell between here and there; taking
	# the max across the span guarantees the unit is lifted in time to clear it.
	var target_terrain: float = map.terrain_height_at(pos_xz)
	var vel_xz: Vector2 = VU.in_xz(_velocity())
	if not vel_xz.is_zero_approx():
		var ahead: Vector2 = vel_xz * AERIAL_LOOKAHEAD_SECONDS
		for i: int in AERIAL_LOOKAHEAD_SAMPLES:
			var f: float = float(i + 1) / float(AERIAL_LOOKAHEAD_SAMPLES)
			target_terrain = maxf(target_terrain, map.terrain_height_at(pos_xz + ahead * f))
	_step_smoothed_altitude(target_terrain)


## Advance _smoothed_terrain_y one tick toward `target_terrain` under MAX_VERTICAL_ACCEL.
## Acceleration-limited "arrive": approach at the fastest speed from which the unit can
## still brake to a stop within the remaining gap (v = sqrt(2·a·d)), then ramp the actual
## vertical speed toward that within the per-tick accel budget. Split out from
## _update_aerial_altitude (which supplies the terrain target) so the controller can be
## exercised without a Map.
func _step_smoothed_altitude(a_target_terrain: float) -> void:
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	var gap: float = a_target_terrain - _smoothed_terrain_y
	var approach_speed: float = signf(gap) * sqrt(2.0 * MAX_VERTICAL_ACCEL * absf(gap))
	var dv_max: float = MAX_VERTICAL_ACCEL * dt
	_vertical_velocity += clampf(approach_speed - _vertical_velocity, -dv_max, dv_max)
	var new_y: float = _smoothed_terrain_y + _vertical_velocity * dt
	# Anti-overshoot: if this step reaches or crosses the target, settle exactly on it
	# (the crossing is sub-tick away, so this is invisible) and drop the residual speed.
	# Without it the steep sqrt curve near zero leaves a small buzzing limit cycle; a
	# still-moving terrain target just re-opens the gap next tick and re-accelerates.
	if gap == 0.0 or signf(a_target_terrain - new_y) != signf(gap):
		_smoothed_terrain_y = a_target_terrain
		_vertical_velocity = 0.0
	else:
		_smoothed_terrain_y = new_y


## Advance _current_height_offset one tick toward `target_offset` under LANDING_ACCEL,
## capped at LANDING_SPEED — the same acceleration-limited "arrive" as
## _step_smoothed_altitude, so the manoeuvre eases in off the hover and settles onto the
## target instead of starting and stopping dead. Returns this tick's change in the offset
## (what _apply_hover_tilt reads).
func _step_height_offset(a_target_offset: float) -> float:
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	var previous: float = _current_height_offset
	var gap: float = a_target_offset - _current_height_offset
	var approach: float = signf(gap) * minf(LANDING_SPEED, sqrt(2.0 * LANDING_ACCEL * absf(gap)))
	var dv_max: float = LANDING_ACCEL * dt
	_landing_rate += clampf(approach - _landing_rate, -dv_max, dv_max)
	var stepped: float = _current_height_offset + _landing_rate * dt
	# Anti-overshoot, exactly as in _step_smoothed_altitude: a step that reaches or crosses
	# the target settles exactly on it and drops the residual rate. Without it the offset
	# buzzes either side of the target, and the LANDING / TAKING_OFF exit tests flicker.
	if gap == 0.0 or signf(a_target_offset - stepped) != signf(gap):
		_current_height_offset = a_target_offset
		_landing_rate = 0.0
	else:
		_current_height_offset = stepped
	return _current_height_offset - previous


## Seconds the vertical offset needs to cover `distance` under LANDING_ACCEL, capped at
## LANDING_SPEED — a symmetric accelerate / cruise / decelerate profile from rest to rest.
## Computed from REST rather than from the live _landing_rate, so it slightly
## OVERestimates mid-manoeuvre — the safe direction for both callers, which then steer a
## little slower and scan a little further than strictly needed.
func _seconds_to_change_offset(a_distance: float) -> float:
	var d: float = absf(a_distance)
	if d <= 0.0 or LANDING_ACCEL <= 0.0 or LANDING_SPEED <= 0.0:
		return 0.0
	# Distance consumed by accelerating to the cap and back down to rest.
	var ramp_distance: float = LANDING_SPEED * LANDING_SPEED / LANDING_ACCEL
	if d <= ramp_distance:
		return 2.0 * sqrt(d / LANDING_ACCEL)  # triangular — never reaches the cap
	return 2.0 * LANDING_SPEED / LANDING_ACCEL + (d - ramp_distance) / LANDING_SPEED


#endregion


#region The ground below
## Called before starting a descent. If the unit's current cell (or the predicted
## touchdown cell for a moving unit) is off the navmesh, find the closest valid landing point
## and store it as _landing_target. _try_start_landing then defers the descent until the unit
## has navigated there (_pending_land).
## TODO: landing target is sometimes placed beyond the obstruction rather than at the
## nearest navmesh edge to the predicted position. The nearest_navmesh_point query
## is correct in principle but the predicted world-Y (aerial height) may bias the 3D
## proximity search away from the correct edge — revisit with a terrain-height Y.
func _compute_landing_correction() -> void:
	_has_landing_target = false
	var map: Map = _map()
	var host: Node3D = _host()
	if map == null or map.terrain_grid == null or host == null:
		return
	var pos_xz := Vector2(host.global_position.x, host.global_position.z)
	var current_cell: Vector2i = map.world_to_grid(pos_xz)
	var current_passable: bool = map.terrain_grid.is_passable(current_cell)

	# Predicted touchdown position: where velocity will carry the unit by the time
	# it descends from _current_height_offset to the ground.
	var velocity: Vector3 = _velocity()
	var time_to_land: float = _seconds_to_change_offset(_current_height_offset)
	var pred_xz: Vector2 = pos_xz + Vector2(velocity.x, velocity.z) * time_to_land

	if current_passable:
		if velocity.is_zero_approx():
			return  # stationary over a passable cell — no correction needed
		var pred_cell: Vector2i = map.world_to_grid(pred_xz)
		if map.terrain_grid.is_passable(pred_cell):
			return  # predicted touchdown is also safe

	# Correction required. Query the navmesh for the closest valid landing point
	# to the predicted touchdown position — sends the unit toward the nearest
	# navmesh edge to where it would naturally end up, not where it currently is.
	var pred_world_pos := Vector3(pred_xz.x, host.global_position.y, pred_xz.y)
	_landing_target = map.nearest_navmesh_point(pred_world_pos)
	_has_landing_target = true


## BFS outward from `from` to the nearest in-bounds passable cell.
## Returns `from` unchanged only when the entire map is impassable (degenerate).
static func _nearest_passable_cell_to(a_grid: TerrainGrid, a_from: Vector2i) -> Vector2i:
	if a_grid.is_passable(a_from):
		return a_from
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = []
	queue.append(a_from)
	visited[a_from] = true
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if a_grid.is_passable(cur):
			return cur
		for d: Vector2i in dirs:
			var nb: Vector2i = cur + d
			if not visited.has(nb) and a_grid.is_in_bounds(nb):
				visited[nb] = true
				queue.append(nb)
	return a_from


## Last-resort teleport if steering during descent still landed off the navmesh.
## Called at the LANDING → GROUNDED_TEMP transition after _has_landing_target is cleared.
func _snap_to_navmesh() -> void:
	var map: Map = _map()
	var host: Node3D = _host()
	if map == null or map.terrain_grid == null or host == null:
		return
	var pos_xz := Vector2(host.global_position.x, host.global_position.z)
	var cell: Vector2i = map.world_to_grid(pos_xz)
	if map.terrain_grid.is_passable(cell):
		return
	var found: Vector2i = _nearest_passable_cell_to(map.terrain_grid, cell)
	if not map.terrain_grid.is_passable(found):
		return
	var world: Vector3 = map.grid_to_world(found)
	host.global_position = Vector3(world.x, host.global_position.y, world.z)


## Cap the XZ speed of `v` so the unit cannot enter a building-occupied (or
## out-of-bounds) cell before it has finished ascending to AERIAL_HEIGHT.
##
## Works by marching a DDA ray through the grid in the velocity direction.
## If a blocked cell is found at distance `d` (world units), the XZ speed is
## capped to d / seconds_remaining — the maximum speed that keeps the unit
## clear of the obstruction until it clears the building height.
func _cap_xz_for_ascent(a_v: Vector3) -> Vector3:
	var map: Map = _map()
	if map == null or map.terrain_grid == null or map.height_map == null:
		return a_v
	var xz := Vector2(a_v.x, a_v.z)
	if xz.is_zero_approx():
		return a_v
	var xz_speed := xz.length()
	var dir := xz.normalized()
	var seconds_remaining: float = _seconds_to_change_offset(AERIAL_HEIGHT - _current_height_offset)
	if seconds_remaining <= 0.0:
		return a_v
	var max_dist: float = xz_speed * seconds_remaining

	var host: Node3D = _host()
	if host == null:
		return a_v
	var pos_xz := Vector2(host.global_position.x, host.global_position.z)

	# Convert world XZ to fractional cell space for DDA.
	# Cell (gx, gz) occupies [gx, gx+1) in cell space.
	var inv := map.global_transform.affine_inverse()
	var hw: float = (map.height_map.map_width - 1) * 0.5
	var hd: float = (map.height_map.map_depth - 1) * 0.5
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
	var t_max_x: float = (
		((1.0 - frac_x) / dx) if dx > 1e-6 else (frac_x / -dx) if dx < -1e-6 else INF
	)
	var t_max_z: float = (
		((1.0 - frac_z) / dz) if dz > 1e-6 else (frac_z / -dz) if dz < -1e-6 else INF
	)
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
		if (
			not map.terrain_grid.is_in_bounds(next_cell)
			or map.terrain_grid.is_building_at(next_cell)
		):
			var capped_speed: float = t / seconds_remaining if seconds_remaining > 1e-6 else 0.0
			return Vector3(dir.x * capped_speed, a_v.y, dir.y * capped_speed)
	return a_v


#endregion


#region Private helpers
func _host() -> Node3D:
	return get_parent() as Node3D


## The piece's locomotion, when it is the navigated strategy. Null for an aircraft with no
## locomotion of its own, which then holds its position.
func _movement() -> Movement:
	var host: Node = get_parent()
	return host.get_node_or_null("Locomotion") as Movement if host != null else null


## Whether the piece's locomotion is switched off (a two-form piece in its deployed form), in
## which case flight is suspended with it.
func _movement_is_dormant() -> bool:
	var movement: Movement = _movement()
	return movement != null and not movement.is_active


func _map() -> Map:
	var host: Entity = get_parent() as Entity
	return host.map if host != null else null


## Whether the piece docks at all (it carries a Docking). Every deck manoeuvre is refused
## without it.
func _docks() -> bool:
	var host: Node = get_parent()
	return host != null and host.has_node("Docking")


func _speed() -> float:
	var movement: Movement = _movement()
	return movement.speed if movement != null else 0.0


func _velocity() -> Vector3:
	var movement: Movement = _movement()
	return movement.current_velocity() if movement != null else Vector3.ZERO


## Steer the piece at `a_desired` under its acceleration and turn limits, bypassing the
## command suppression — for the manoeuvres this component flies itself.
func _drive(a_desired: Vector3) -> void:
	var movement: Movement = _movement()
	if movement != null:
		movement.drive(a_desired)


## Emit `a_velocity` as it is, with no limits and no turn toward it.
func _emit_velocity(a_velocity: Vector3) -> void:
	var movement: Movement = _movement()
	if movement != null:
		movement.emit_velocity(a_velocity)


## Record `a_velocity` as the piece's current velocity without emitting it — a taxi moves the
## piece by position, and its velocity is only what the climb-out reads its heading from.
func _set_velocity(a_velocity: Vector3) -> void:
	var movement: Movement = _movement()
	if movement != null:
		movement.set_current_velocity(a_velocity)
#endregion
