class_name Rearm
extends MoveCommand

## Fly to an airfield, park on one of its DockingPads, refill every CHARGED weapon (see
## Weapon.charged), and take off again.
##
## The command owns the whole docking sequence rather than splitting it across Movement
## and the bay, because every stage of it is conditional on the stage before and there is
## exactly one thing driving the aircraft — this order. `state` below is the sequence.
##
## Issued two ways, and they differ only in who created the message:
##   * BY THE PLAYER, right-clicking a friendly airfield with aircraft selected.
##   * BY THE AIRCRAFT ITSELF, when its charged weapons run dry mid-order — see
##     Docking.maybe_auto_rearm, which PREPENDS this command so whatever the unit
##     was doing resumes automatically once it is rearmed.

#region Constants
## The docking sequence. Each state is entered once and exited on a condition the state
## itself can check, so the whole manoeuvre survives being interrupted at any point.
##
## TAXI_IN and TAXI_OUT are real: the aircraft comes down on the bay's RUNWAY marker,
## drives along the deck to its pad, and reverses the trip before taking off again. An
## airfield with no runway marker keeps the old one-tick behaviour, descending straight
## onto the pad — which is what every bay did before the Sky Port's apron gave the taxi
## somewhere to happen. See DockingBay.runways / Runway.
enum DockState {
	APPROACH,  ## flying to the pad's XZ at cruise altitude
	DESCEND,  ## coming down onto the deck (Aerial.land_at)
	TAXI_IN,  ## on the deck, moving to the exact pad position — currently instant
	DOCKED,  ## parked and recharging
	TAXI_OUT,  ## leaving the pad for the departure point — currently instant
	ASCEND,  ## climbing back to cruise altitude
}

## How close, in world units on XZ, a HOVERING aircraft must be to its pad before it begins
## the descent. Generous relative to Movement.HOVERING_ARRIVAL_DISTANCE because the descent
## steers horizontally as it falls (see Movement.land_at) — arriving exactly overhead first
## would make the aircraft stop dead in the air and then sink, which reads far worse than a
## shallow approach.
##
## A FLYING aircraft does not use this; see _approach_radius.
const APPROACH_RADIUS: float = 1.5

## Ground speed while taxiing, as a fraction of the aircraft's cruise speed. An aeroplane
## on the deck moves like a vehicle, not like the thing that just flew in.
const TAXI_SPEED_FACTOR: float = 0.35

## How close to a taxi waypoint counts as reached, in world units.
const TAXI_ARRIVAL: float = 0.08

## How far out the final-approach fix sits, as a multiple of the aircraft's own turning
## circle, with a floor for a very nimble one. Enough room to roll out of the turn and be
## pointed down the strip; no more, because every unit of it is a unit the aircraft has to
## fly away from the airfield before it can come back.
const LINEUP_TURN_RADII: float = 2.5
const MIN_LINEUP_DISTANCE: float = 4.0

## What "established on final" means: pointed down the strip, on the approach side, and
## within a corridor either side of the centreline.
##
## THE CORRIDOR IS SCALED TO THE TURNING CIRCLE, not a fixed width, and that is what makes
## the gate passable at all. An aircraft that has just come round 180 degrees rolls out a
## full turn DIAMETER off the line it started on; a corridor narrower than that is one no
## aircraft arriving from the far side can ever satisfy, so it flies past, turns, misses
## again, and circles the field forever. Being inside the corridor is not "lined up" but
## "close enough that the descent can converge the rest" — the descent steers at the
## threshold the whole way down, so a few units of offset comes out as a gentle correction.
const FINAL_CORRIDOR_TURNS: float = 2.5
const MIN_FINAL_CORRIDOR: float = 2.0
const FINAL_ARC_DEGREES: float = 45.0
const MIN_FINAL_DISTANCE: float = 1.0
#endregion


#region Preconditions
static func requires_position() -> bool:
	return true


## Valid when the actor is an aerial unit carrying at least one charged weapon and the
## target is a friendly, finished structure whose DockingBay admits it.
##
## Room is deliberately not checked: a full bay is a queue, not a refusal, and an aircraft
## ordered to a busy airfield flies over and waits for a pad — the same rule Occupy uses
## for a full garrison. Having ammo is not checked either, so a player can top a unit up
## before it is dry, which is most of what a manual rearm order is for.
static func meets_precondition(
	actor: Actor, message: CommandMessage
) -> PreconditionFailureCause:
	if actor == null or actor.docking == null or actor.aerial == null:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	if actor.weapon_inventory == null or not actor.weapon_inventory.has_charged_weapons():
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	var bay: DockingBay = _bay_of(message.target)
	if bay == null or not bay.admits(actor):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	return PreconditionFailureCause.NONE


## The DockingBay on `target`, or null when the target is not an airfield (which includes
## an airfield that has since been DESTROYED). A static helper so the precondition can ask
## before any instance exists.
##
## `target` is deliberately UNTYPED. Godot type-checks an Object argument against the
## parameter's class BEFORE the body runs, and a freed object fails that check — so a
## typed `target: Entity` crashed here on the tick the airfield died, with the
## is_instance_valid guard one line away and unreachable. See CLAUDE.md §A freed object
## cannot be passed to a typed parameter.
static func _bay_of(target: Variant) -> DockingBay:
	if not is_instance_valid(target) or not (target is Actor):
		return null
	return (target as Actor).get_node_or_null("DockingBay") as DockingBay


#endregion

#region Properties
var state: DockState = DockState.APPROACH

## The pad this command has claimed, held from the first tick of the approach until the
## aircraft is airborne again. Claiming early is what stops two aircraft converging on one
## space; releasing late is what stops a third taking the space out from under one that is
## still rolling off it.
var _pad: DockingPad = null

## The actor holding the pad and the collision exception, captured while it is alive.
## PREDELETE runs at an arbitrary moment (see MoveCommand._notification), so the teardown
## there cannot go looking for the actor — it has to have been remembered.
var _claiming_actor: Actor = null

## Whether we have excluded the airfield's body from the actor's collisions. A parked
## aircraft sits inside the structure's footprint, which its MOVEMENT_OBSTRUCTION body
## would otherwise refuse to enter — the same problem Occupy solves the same way.
var _excluded: bool = false

## Set when the sequence ended the way it is meant to — fully rearmed, still on the pad.
## on_released reads it to decide whether to lift the aircraft off: an order that COMPLETED
## leaves it parked, an order that was interrupted must not strand it on the deck.
var _finished_docked: bool = false
#endregion


#region State updates
## Where the approach flies. Travelling matters only during APPROACH — every later state
## positions the aircraft itself, so a destination during them would fight that.
##
## The fix is out on the extended centreline rather than the airfield itself: joining the
## centreline is the whole point of having a runway. Null while no pad is held, which falls
## back to the airfield — the "circle the field until a space frees" case that makes a full
## bay a QUEUE rather than a refusal.
## Why: gdd/systems/combat/aerial-operations/runways.md §The approach fix.
func movement_destination(a_actor: Actor) -> Variant:
	if state != DockState.APPROACH or _pad == null or a_actor == null or a_actor.movement == null:
		return null
	return _approach_position(a_actor)


func should_move(_a_actor: Actor) -> bool:
	return state == DockState.APPROACH


## A rearm is never finished by arriving — arriving is where it starts. Without this the
## receiver would drop the command the tick the approach completed, and the aircraft would
## hang in the air over the airfield with nothing to do. Same reason Build and Assemble
## override it.
func ends_on_arrival() -> bool:
	return false


## Reserve a pad, and abandon the order if the airfield is destroyed under us.
##
## The reservation is retried every tick until it succeeds, which is how a full bay
## becomes a queue: the aircraft simply keeps flying at the airfield (message.position)
## until a pad frees up, then latches onto it.
func get_updated_state(a_actor: Actor) -> Variant:
	var bay: DockingBay = _bay_of(message.target)
	if bay == null:
		_release_pad()
		_clear_collision_exception()
		return null
	if _pad == null:
		_pad = bay.reserve(a_actor)
		if _pad != null:
			_claiming_actor = a_actor
	elif _pad.claimed_by() != a_actor:
		# The pad was taken from under us (the claimant died and something else moved in, or
		# the airfield was rebuilt). Drop it and re-reserve on the next tick.
		_pad = null
	return self


## Everything past the approach is "acting": the descent, the wait on the deck, and the
## climb out all advance in fulfill_action. During the approach this is the arrival test.
func can_act(a_actor: Actor) -> bool:
	if _pad == null:
		return false
	if state != DockState.APPROACH:
		return true
	if not _is_established_on_final(a_actor):
		return false
	# ONE AIRCRAFT PER STRIP, the arrival side of the same rule the departure obeys. A busy
	# runway is a HOLD, not a refusal: the aircraft keeps flying its approach and comes down
	# the moment the strip is clear, which is the same thing a full bay does with pads.
	#
	# Only ASKED here — the claim is taken when the descent actually starts. Claiming from an
	# approach would take the strip while the aircraft is still airborne, and the release rule
	# (airborne or parked) would hand it straight back on the next tick, so the two fought
	# every frame and a third aircraft could walk off with a strip somebody was landing on.
	var strip: Runway = _runway_for_pad()
	return strip == null or strip.is_free() or strip.claimed_by() == a_actor


## Advance one step of the docking sequence. Returns `self` while the sequence is running
## — which the receiver reads as "keep this command" — and null once the aircraft is back
## at altitude, at which point whatever was queued behind this order resumes.
func fulfill_action(a_actor: Actor) -> Variant:
	match state:
		DockState.APPROACH:
			_ensure_collision_exception(a_actor)
			# Committing to the strip now, which is when it is taken.
			_claim_runway(a_actor)
			# Lined up on the centreline now, so the descent flies STRAIGHT DOWN THE STRIP to
			# the threshold rather than dropping onto it from wherever the aircraft came from.
			a_actor.aerial.land_at(_touchdown_position(a_actor), _pad.deck_height, Callable())
			state = DockState.DESCEND
		DockState.DESCEND:
			if a_actor.aerial.is_docked():
				state = DockState.TAXI_IN
		DockState.TAXI_IN:
			_tick_taxi_in(a_actor)
		DockState.DOCKED:
			_hold_on_pad(a_actor, a_actor.docking.docked_pad)
			# The BAY does the recharging (DockingBay.tick_recharge, driven from the structure),
			# so this only decides when the aircraft has had enough. Asking the loadout rather
			# than counting ticks here means an airfield destroyed mid-service simply stops
			# refilling, and the unit leaves with whatever it managed to take on.
			#
			# A FULL AIRCRAFT STAYS ON ITS PAD. The order is over — it ends here rather than
			# taxiing out and climbing to no purpose — and the aircraft simply sits there until
			# something gives it a reason to fly: the order it broke off from resuming, or a new
			# one. CommandReceiver lifts a docked unit the moment it has somewhere to drive it,
			# so nothing is stranded; and an idle FLYING unit's orbit is suppressed while it is
			# not airborne, so it holds the deck instead of taxiing in circles.
			if not a_actor.weapon_inventory.needs_recharge() or _bay_of(message.target) == null:
				_finished_docked = true
				_clear_collision_exception()
				return null
		DockState.TAXI_OUT:
			_tick_taxi_out(a_actor)
		DockState.ASCEND:
			if a_actor.aerial.is_airborne():
				_release_pad()
				_clear_collision_exception()
				return null
	return self


#endregion


#region Sequence steps
## Roll in off the threshold: down the strip to the point nearest the pad, then across the
## apron onto it. Handed to Aerial.taxi_along, the same ground drive a departure uses in
## reverse, so the two halves cannot drift apart.
##
## A bay with no runway put the aircraft on its pad during the descent, so the path is empty
## and this resolves on the first tick.
func _tick_taxi_in(a_actor: Actor) -> void:
	if a_actor.aerial.is_taxiing():
		return
	if state != DockState.TAXI_IN:
		return  # the completion callback already moved us on
	var strip: Runway = _runway_for_pad()
	if strip == null:
		_park(a_actor)
		return
	a_actor.aerial.taxi_along(
		[strip.nearest_point(_pad.dock_position()), _pad.dock_position()], _park.bind(a_actor)
	)


## Parked. THE PAD BECOMES THE UNIT'S HERE, not when the recharge finishes.
##
## Everything that asks "is this aircraft standing on a pad" — releasing the runway, turning
## to face the taxiway, leaving through leave_dock — goes through Docking.docked_pad, so
## holding it on the command until the clip was full meant an aircraft spent its whole
## refuelling stop still owning the runway and still pointing the way it landed.
func _park(a_actor: Actor) -> void:
	if not is_instance_valid(a_actor):
		return
	_hold_on_pad(a_actor)
	a_actor.docking.docked_pad = _pad
	_pad = null
	_claiming_actor = null
	state = DockState.DOCKED


## The climb-out is no longer this command's business — an aircraft leaves a pad through
## Docking.leave_dock, which taxis it to a threshold and hands over to Aerial. Kept
## only so an interrupted sequence has somewhere to fall through to.
func _tick_taxi_out(a_actor: Actor) -> void:
	a_actor.docking.leave_dock()
	state = DockState.ASCEND


## Take the strip this aircraft is about to land on. True when it has it (or there is no
## runway to take, which is the descend-onto-the-pad fallback).
func _claim_runway(a_actor: Actor) -> bool:
	var strip: Runway = _runway_for_pad()
	if strip == null:
		return true
	if not strip.claim(a_actor):
		return false
	a_actor.docking.claimed_runway = strip
	return true


## The runway this aircraft should use, chosen by its assigned pad so the roll in and the
## roll out are the same strip. Null for a bay with none authored.
func _runway_for_pad() -> Runway:
	var bay: DockingBay = _bay_of(message.target)
	if bay == null or _pad == null:
		return null
	return bay.runway_for(_pad)


## Where the DESCENT ends: the runway threshold, or the pad itself on a bay with no runway.
func _touchdown_position(a_actor: Actor) -> Vector3:
	var strip: Runway = _runway_for_pad()
	var pos: Vector3 = strip.takeoff_point() if strip != null else _pad.dock_position()
	if a_actor.map != null:
		pos.y = a_actor.map.terrain_height_at(VU.in_xz(pos))
	return pos


## How far out on the centreline the final-approach fix sits.
##
## A LINEUP LEG, not a glide budget. It used to be a full descent run — the ground the
## aircraft covers while shedding cruise altitude at a fixed sink rate — which put the fix
## twenty-odd units outside the field and sent anything arriving from the far side on a
## huge loop around it just to get behind the numbers. Now that the descent rate is derived
## from the distance still to run (Movement._descend_to_touchdown), the fix only has to be
## far enough out for the aircraft to be POINTED down the strip when it gets there, which
## is a couple of turn radii.
func _lineup_distance(a_actor: Actor) -> float:
	return maxf(MIN_LINEUP_DISTANCE, a_actor.movement.turn_radius() * LINEUP_TURN_RADII)


## Where the APPROACH ends and the descent begins: out beyond the threshold on the extended
## centreline, far enough back that the aircraft is lined up with the strip.
##
## This is what makes an arrival read as an approach. Aiming the descent at the threshold
## from wherever the aircraft happened to be let it come down across the runway, or back to
## front; lining it up first means it always meets the tarmac pointing the way a real one
## would. A bay with no runway keeps the old behaviour and simply descends onto the pad.
func _approach_position(a_actor: Actor) -> Vector3:
	var strip: Runway = _runway_for_pad()
	if strip == null:
		return _touchdown_position(a_actor)
	var pos: Vector3 = strip.approach_point(_lineup_distance(a_actor))
	if a_actor.map != null:
		pos.y = a_actor.map.terrain_height_at(VU.in_xz(pos))
	return pos


## Pin the aircraft to its pad's XZ.
##
## Position rather than velocity, because velocity cannot do it: Movement.set_velocity is
## suppressed outright while GROUNDED_TEMP, so a zeroed velocity is a no-op in exactly the
## state this needs to hold. The vertical needs no help either — Actor rewrites world
## Y every tick from the terrain plus the height offset — so pinning XZ is the whole job,
## and without it a parked aircraft creeps off its space under any residual drift.
## `a_pad` is untyped for the same reason _bay_of's target is: callers pass
## `Docking.docked_pad`, which is a freed reference once the airfield under it is gone.
func _hold_on_pad(a_actor: Actor, a_pad: Variant = null) -> void:
	var pad: DockingPad = a_pad if is_instance_valid(a_pad) else _pad
	if pad == null or not is_instance_valid(pad):
		return
	var pad_xz: Vector3 = pad.dock_position()
	a_actor.global_position.x = pad_xz.x
	a_actor.global_position.z = pad_xz.z


## The pad's world position with Y resolved against the terrain beneath it, which is the
## frame Movement's landing works in (it descends a height OFFSET above the terrain, not
## to an absolute altitude).
func _pad_world_position(a_actor: Actor) -> Vector3:
	var pos: Vector3 = _pad.dock_position()
	if a_actor.map != null:
		pos.y = a_actor.map.terrain_height_at(VU.in_xz(pos))
	return pos


## Whether the aircraft may start down: it is on the approach side of the threshold, near
## the centreline, and POINTED DOWN THE STRIP.
##
## THE HEADING IS THE PART THAT MATTERS. The test used to be distance to the fix alone, so
## an aircraft arriving from the far side flew straight through the fix at cruise speed —
## heading directly AWAY from the runway — and committed anyway. The descent then had to
## turn it 180 degrees while it sank, which is the wide, repeated swinging that looks like
## an aircraft unable to find the field. Refusing here leaves it in APPROACH instead, where
## it is flying level at full speed with its destination behind it: it comes round in one
## clean circuit and lands on the next pass.
##
## A bay with no runway keeps the old point-proximity rule — there is no centreline to be
## established on, and a HOVERING dock descends from directly overhead anyway.
func _is_established_on_final(a_actor: Actor) -> bool:
	var strip: Runway = _runway_for_pad()
	if strip == null:
		return _distance_to_approach(a_actor) <= _approach_radius(a_actor)
	var along: Vector2 = VU.in_xz(strip.heading())
	var to_threshold: Vector2 = VU.in_xz(strip.takeoff_point()) - VU.in_xz(a_actor.global_position)
	# Positive means the threshold is still ahead of us down the strip's own axis.
	var ahead: float = to_threshold.dot(along)
	var corridor: float = maxf(
		MIN_FINAL_CORRIDOR, a_actor.movement.turn_radius() * FINAL_CORRIDOR_TURNS
	)
	if ahead < MIN_FINAL_DISTANCE or ahead > _lineup_distance(a_actor) + corridor:
		return false
	if absf(to_threshold.cross(along)) > corridor:
		return false
	var facing: Vector2 = VU.in_xz(a_actor.movement.get_facing())
	if facing.is_zero_approx():
		return false
	return facing.normalized().dot(along) >= cos(deg_to_rad(FINAL_ARC_DEGREES))


## Distance to where the descent is aimed — the runway, not the pad. Measuring to the pad
## would start the glide by the wrong margin on any airfield whose runway is not on top of
## its parking, which is every airfield with room to taxi across.
func _distance_to_approach(a_actor: Actor) -> float:
	return VU.in_xz(a_actor.global_position).distance_to(VU.in_xz(_approach_position(a_actor)))


## Where this aircraft's descent begins, and the one place the two aerial modes genuinely
## differ: a HOVERING unit arrives overhead and sinks, a FLYING one commits from
## `descent_run_distance` so the descent works out as a shallow glide onto the pad. Derived
## from the unit's own speed rather than authored, so a faster airframe commits earlier
## instead of overshooting — the reasoning behind Movement._dive_commit_distance.
## Why: gdd/systems/combat/aerial-operations/runways.md.
func _approach_radius(a_actor: Actor) -> float:
	# With a runway, the glide budget lives in WHERE the fix is (_approach_position), so what
	# is left here is an arrival tolerance. Without one there is no fix to fly to, the old
	# rule stands, and the descent commits a full glide out from the pad.
	if _runway_for_pad() != null:
		return APPROACH_RADIUS
	if a_actor.aerial.mode != Movement.Mode.FLYING:
		return APPROACH_RADIUS
	return maxf(APPROACH_RADIUS, a_actor.aerial.descent_run_distance(_pad.deck_height))


#endregion


#region Pad + collision bookkeeping
func _release_pad() -> void:
	if _pad != null and is_instance_valid(_pad) and is_instance_valid(_claiming_actor):
		_pad.release(_claiming_actor)
	_pad = null
	_claiming_actor = null


## Let the aircraft cross into the airfield's footprint. Its MOVEMENT_OBSTRUCTION body
## would otherwise stop it short of the deck — the same approach Occupy takes for a unit
## walking into a garrison host.
func _ensure_collision_exception(a_actor: Actor) -> void:
	if _excluded:
		return
	if (
		is_instance_valid(a_actor)
		and is_instance_valid(message.target)
		and message.target is CollisionObject3D
	):
		a_actor.add_collision_exception_with(message.target)
		_claiming_actor = a_actor
		_excluded = true


func _clear_collision_exception() -> void:
	if (
		_excluded
		and is_instance_valid(_claiming_actor)
		and is_instance_valid(message.target)
		and message.target is CollisionObject3D
	):
		_claiming_actor.remove_collision_exception_with(message.target)
	_excluded = false


#endregion


#region Lifecycle
## Everything this command was holding on the world's behalf, dropped at the one moment the
## actor is guaranteed to be fully alive: the pad, the collision exception, and the
## aircraft itself if the order ended while it was still parked.
##
## THIS USED TO BE DONE IN _notification(PREDELETE), AND THAT IS A SEGFAULT. A RefCounted's
## destructor fires whenever its last reference happens to drop, which for a unit that dies
## mid-command is during that unit's own teardown — and `is_instance_valid()` cannot guard
## it, because it keeps reporting true for an object already inside its destructor while
## the script instance behind `actor.aerial` is gone. Reading through it killed the
## process outright, with no GDScript error. MoveCommand._notification documents the same
## trap for the group-move speed cap, which is what on_released was added for; this is the
## second thing to fall into it.
func on_released(a_actor: Actor) -> void:
	_clear_collision_exception()
	# The pad is NOT released on a completed rearm: the aircraft is still standing on it, and
	# handing the space to somebody else would land a second aircraft on top of it. It goes
	# back when the unit actually leaves — see Docking.leave_dock.
	if _finished_docked:
		return
	# INTERRUPTED WHILE PARKED — the player re-ordered it off the pad part-way through
	# recharging. Leave it standing there: whatever order replaced this one takes it off
	# through leave_dock, which TAXIS. Lifting it here instead is what made a part-charged
	# aircraft rise vertically off its parking space, skipping the runway entirely, while a
	# fully-charged one taxied out correctly.
	#
	# The pad is usually already the unit's (_park hands it over on touchdown); the transfer
	# here covers an interrupt that lands between reserving one and reaching it.
	if a_actor != null and a_actor.aerial != null and a_actor.aerial.is_docked():
		if _pad != null and is_instance_valid(_pad):
			a_actor.docking.docked_pad = _pad
			_pad = null
			_claiming_actor = null
		return
	# Interrupted in the air or mid-roll: it would stay on the deck forever otherwise, since
	# the order that grounded it is gone. Aerial's take-off is a no-op unless it is actually
	# grounded, so this is safe from any state.
	if a_actor != null and a_actor.aerial != null:
		a_actor.aerial.take_off()
	_release_pad()


## Last-resort net for the PAD ALONE — a command built and dropped without ever reaching a
## receiver (a scenario event abandoning an order, a test) never gets on_released, and a
## stranded pad is a space lost for the rest of the match.
##
## Deliberately touches NOTHING on the actor. Releasing a pad passes the actor as a plain
## reference and compares it (see DockingPad.release), which never dereferences its script;
## everything that WOULD is in on_released above.
func _notification(a_what: int) -> void:
	if a_what == NOTIFICATION_PREDELETE:
		# Not on a completed rearm — the aircraft is still parked there and now owns the claim
		# itself (see fulfill_action's DOCKED branch).
		if (
			not _finished_docked
			and _pad != null
			and is_instance_valid(_pad)
			and _claiming_actor != null
		):
			_pad.release(_claiming_actor)
		_pad = null
		_excluded = false
		_claiming_actor = null
	super._notification(a_what)


#endregion


#region Debug
func _to_string() -> String:
	return "Rearm: %s (%s)" % [message.position, DockState.keys()[state]]
#endregion
