class_name Spot
extends MoveCommand

## Call in a firing solution: walk to within the spotter's `target_range` of a chosen
## point, hold still for its `channel_ticks`, leave a [Beacon] there — then STAY, until a
## Bombard spends that beacon or the player orders the unit elsewhere.
##
## THE HOLD IS THE MECHANIC, and it is why this is a command rather than a one-shot
## ability. A spotter is committed: it is stationary, exposed, and doing nothing else for
## as long as its solution stands. That is what the artillery is paying for, and it gives
## the opponent something to answer — kill the spotter and the shot never comes.
##
## Three consequences follow, each with the place it lives:
##
## • It does NOT end when the beacon goes up (`fulfill_action` returns self). A command
##   that completed there would let the unit walk on to its next queued order while its
##   beacon still stood, which is precisely the commitment being sold.
## • Anything queued behind it therefore waits for the SHOT, not for the placement —
##   "spot here, then fall back" reads as one order the player gave once.
## • Being re-ordered drops the beacon (`on_released`). The solution belongs to the unit
##   holding it; a spotter told to do something else has stopped spotting, and leaving a
##   live beacon behind would let a player place them for free by re-tasking.


#region Preconditions
## A unit not granted the ability simply cannot do this; anything else about the order
## (reachability, whether the ground is worth spotting) is not a precondition's business.
static func meets_precondition(
	actor: Commandable, _message: CommandMessage
) -> MoveCommand.PreconditionFailureCause:
	if actor == null or not _can_spot(actor):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	return PreconditionFailureCause.NONE


## How close `a_actor` must get to its chosen point before it starts calling the strike in, in
## world units. It walks to within this distance and then stops, and a beacon riding a unit
## stands only while its carrier stays within it (the leash).
##
## The spot ability doc's `range:`, raised by any upgrade its commander owns that modifies this
## piece's spotting (Advanced Targetting — see UpgradeCatalog). It used to be a constant, on the
## grounds that a value that never varied was not a configuration; an upgrade is what made it
## vary.
static func target_range(a_actor: Commandable) -> float:
	return AbilityCatalog.range_for(ABILITY_ID, a_actor)


## How long the call takes once in position, in physics ticks (30/second). The channel is the
## cost of the mechanic: a spotter is stationary and exposed while it runs, and any new order
## cancels it.
const CHANNEL_TICKS: int = 300


## Whether `a_actor` is granted Spot at all. It used to be the presence of a `Spotter`
## component, whose whole content was these two constants; it is an ordinary granted ability
## now, so the capability is asked the way every other ability's is.
static func _can_spot(actor: Commandable) -> bool:
	var pool := actor.get_node_or_null("Abilities") as Abilities if actor != null else null
	return pool != null and pool.grants(ABILITY_ID)


## The `kind: AbilityDefinition` doc this command is the verb of.
const ABILITY_ID: StringName = &"spot"


## Read from that doc's `cast_by:` rather than answered here, so the authored key GOVERNS
## rather than describing. Spot is the roster's one `cast_by: ALL` ability — a second firing
## solution on the same ground is worth having, where a second Irradiate on one point is a
## wasted charge. This class extends MoveCommand rather than Ability, so it does not inherit
## Ability's lookup and has to make it itself.
static func default_cast_arity(_message: CommandMessage) -> CastArity:
	return AbilityCatalog.cast_arity_of(ABILITY_ID)


#endregion

#region Properties
## Ticks spent in position so far. Reset whenever the spotter is not yet in range, so
## being pushed out of position restarts the call rather than banking progress.
var _channelled: int = 0

## The beacon this command raised, once it has. Held so the command knows when its work
## is finished (the beacon is gone) and so it can withdraw the solution if re-ordered.
##
## `_beacon_raised` is NOT redundant with `_beacon != null`, and conflating them made the
## command immortal: a FREED object compares equal to null in Godot, so once a shot spent
## the beacon the reference read as "never placed one" and every test below fell back to
## the still-channelling branch. The flag records that the work happened; the reference
## records whether the beacon is still standing.
var _beacon: Beacon = null

## Whether the beacon was ever raised — see above.
var _beacon_raised: bool = false
#endregion


#region State updates
## Calling a strike in is a channeled action, so a hit interrupts it exactly as it
## interrupts building.
func blocked_by_stagger(_a_actor: Commandable) -> bool:
	return true


## Once the beacon is up, this command's life is the beacon's. It ends when the beacon
## does — spent by a shot, or expired — and until then holds the unit in place.
func get_updated_state(_a_actor: Commandable) -> Variant:
	if _beacon_raised and not is_instance_valid(_beacon):
		return null
	return self


## Arriving is where the work STARTS. Without this the receiver would drop the order the
## moment the spotter stopped walking — the same defect that used to lose a Build on
## approach.
func ends_on_arrival() -> bool:
	return false


## Stand still once the beacon is standing: the unit is committed to holding the solution,
## not to walking back to the point it was called from.
func should_move(a_actor: Commandable) -> bool:
	return not _beacon_raised and not can_act(a_actor)


func can_act(a_actor: Commandable) -> bool:
	if not _can_spot(a_actor):
		return false
	if _beacon_raised:
		# Holding. can_act stays true so the receiver keeps handing us ticks instead of
		# treating the unit as idle and letting aggro pick a target for it.
		return true
	return a_actor.xz_position.distance_to(message.xz_position) <= Spot.target_range(a_actor)


func fulfill_action(a_actor: Commandable) -> Variant:
	if _beacon_raised:
		_hold_leash(a_actor)
		return self  # holding the solution; nothing further to do each tick
	if not _can_spot(a_actor):
		return null
	_channelled += 1
	if _channelled < Spot.CHANNEL_TICKS:
		return self
	_beacon = _raise_beacon(a_actor)
	if _beacon == null:
		return null
	_beacon_raised = true
	return self


## How far through the call this spotter is, 0..1 — for a HUD readout. 1.0 once the
## beacon stands, since the call is finished even though the command is not.
func channel_progress(a_actor: Commandable) -> float:
	if _beacon_raised:
		return 1.0
	if not _can_spot(a_actor):
		return 0.0
	return clampf(float(_channelled) / float(Spot.CHANNEL_TICKS), 0.0, 1.0)


## Withdraw the solution when this order is replaced or cleared. See the class docs for
## why a re-ordered spotter must not leave its beacon behind.
func on_released(_a_actor: Commandable) -> void:
	if is_instance_valid(_beacon):
		_beacon.dismiss()
	_beacon = null
	_beacon_raised = false


#endregion


#region Private helpers
## Place the beacon at the ordered point — or, when the order named an enemy unit that can
## carry one (Beacon.can_carry: a grounded MECH unit), ON that unit, so it moves with it. It
## never expires on its own: a spotter's solution is held by the spotter, so its lifetime is
## this command's, not a timer's.
func _raise_beacon(a_actor: Commandable) -> Beacon:
	var map: Map = message.map if message.map != null else a_actor.map
	if map == null or a_actor.commander == null:
		return null
	var piece: Entity = Beacon.SCENE.instantiate() as Entity
	piece.initialize(map, a_actor.commander)
	var xz: Vector2 = message.xz_position
	piece.global_position = Vector3(xz.x, map.terrain_height_at(xz), xz.y)
	var beacon: Beacon = Beacon.of(piece)
	var target: Variant = message.target
	if beacon != null and Beacon.can_carry(target) and a_actor.is_enemy_of(target as Entity):
		beacon.attach_to(target as Entity)
	return beacon


## THE LEASH: a beacon riding on a unit stands only while that unit stays within the
## spotter's target_range. A carrier that drives out of it drops the beacon — and a shell
## already tracking it lands where it last was. A point beacon has no leash.
func _hold_leash(a_actor: Commandable) -> void:
	if not is_instance_valid(_beacon):
		return
	var carrier: Entity = _beacon.carrier()
	if (
		carrier != null
		and a_actor.xz_position.distance_to(carrier.xz_position) > Spot.target_range(a_actor)
	):
		_beacon.dismiss()
#endregion
