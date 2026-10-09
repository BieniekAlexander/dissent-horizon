class_name Spot
extends MoveCommand

## Call in a firing solution: walk to within the spotter's `target_range` of a chosen
## point, hold still for CHANNEL_SECONDS, leave a [Beacon] there — then STAY, until a
## Bombard fires on that beacon or the player orders the unit elsewhere.
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
## • A Bombard left on automatic fires on the beacon as soon as one is ready, the nearest
##   to the beacon first (Bombard.autofire_on); a gun switched to manual waits for an order.
## • It ends when a Bombard FIRES on the beacon — not when the shell lands — so anything
##   queued behind it waits for the shot, and "spot here, then fall back" reads as one order
##   the player gave once. The fired-on beacon stands until the shell lands: it is tracking it.
## • Being re-ordered, or dying, drops an unfired beacon (`on_released`,
##   `Beacon.dismiss_with_spotter`). The solution belongs to the unit holding it; leaving a
##   live beacon behind would let a player place them for free by re-tasking.
##
## A PLANTER (a piece with a [BeaconPlanter]: the Sleeper) performs the same order its own
## way: it walks to the point itself, channels, leaves a ground beacon there — the point beacon
## a Beacon Drop places, never one riding a unit — and the order ENDS. Nothing holds that
## beacon, so it is not withdrawn when the planter moves on, and it calls no automatic fire.
## See gdd/systems/combat/bombardment.md §Planting a beacon.
##
## THE CHARGE is spent when the channel starts and its recharge is HELD until the order ends,
## however it ends: the cooldown counts from the moment the spotter is free again, so a
## spotter cannot bank one while holding a solution. An order abandoned before the channel
## starts costs nothing.


#region Preconditions
## A unit not granted the ability simply cannot do this, one whose commander has not researched
## the upgrade gating it for this piece may not (the Sleeper's Cell Activation), and one whose
## charge is spent must wait; anything else about the order (reachability, whether the ground
## is worth spotting) is not a precondition's business.
static func meets_precondition(
	actor: Actor, _message: CommandMessage
) -> MoveCommand.PreconditionFailureCause:
	if actor == null or not _can_spot(actor):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	if not UpgradeCatalog.is_ability_unlocked(actor, ABILITY_ID):
		return PreconditionFailureCause.MISSING_UPGRADE
	if not _pool(actor).is_ready(ABILITY_ID):
		return PreconditionFailureCause.ABILITY_NO_CHARGES
	return PreconditionFailureCause.NONE


## How close `a_actor` must get to its chosen point before it starts calling the strike in, in
## world units. It walks to within this distance and then stops, and a beacon riding a unit
## stands only while its carrier stays within it (the leash).
##
## The spot ability doc's `range:`, raised by any upgrade its commander owns that modifies this
## piece's spotting (Advanced Targetting — see UpgradeCatalog). It used to be a constant, on the
## grounds that a value that never varied was not a configuration; an upgrade is what made it
## vary.
static func target_range(a_actor: Actor) -> float:
	return AbilityCatalog.range_for(ABILITY_ID, a_actor)


## How long the call takes once in position. The channel is the cost of the mechanic: a
## spotter is stationary and exposed while it runs, and any new order cancels it.
const CHANNEL_SECONDS: float = 3.0


## CHANNEL_SECONDS in physics ticks, the unit the channel is counted in.
static func channel_ticks() -> int:
	return TimeUtils.ticks_from_seconds(CHANNEL_SECONDS)


## Whether `a_actor` is granted Spot at all. It used to be the presence of a `Spotter`
## component; it is an ordinary granted ability now, so the capability is asked the way every
## other ability's is.
static func _can_spot(actor: Actor) -> bool:
	var pool: Abilities = _pool(actor)
	return pool != null and pool.grants(ABILITY_ID)


## `a_actor`'s ability pool, or null for a piece with none.
static func _pool(a_actor: Actor) -> Abilities:
	return a_actor.get_node_or_null("Abilities") as Abilities if a_actor != null else null


## The `kind: AbilityDefinition` doc this command is the verb of.
const ABILITY_ID: StringName = &"spot"


## Read from that doc's `cast_by:` rather than answered here, so the authored key GOVERNS
## rather than describing. This class extends MoveCommand rather than Ability, so it does not
## inherit Ability's lookup and has to make it itself.
static func default_cast_arity(_message: CommandMessage) -> CastArity:
	return AbilityCatalog.cast_arity_of(ABILITY_ID)


## Free unless already spotting — the job rule (MoveCommand.is_free_to_take).
static func is_free_to_take(actor: Actor) -> bool:
	return holds_none_of(actor, [Spot])


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

## The pool whose charge this order spent and whose recharge it holds, or null before the
## channel starts. Kept so the hold is lifted on exactly the pool it was put on.
var _held_pool: Abilities = null
#endregion


#region State updates
## Calling a strike in is a channeled action, so a hit interrupts it exactly as it
## interrupts building.
func blocked_by_stagger(_a_actor: Actor) -> bool:
	return true


## Once the beacon is up, this command's life is the beacon's. It ends when a Bombard fires
## on it, or when it leaves play some other way, and until then holds the unit in place.
func get_updated_state(_a_actor: Actor) -> Variant:
	if _beacon_raised and (not is_instance_valid(_beacon) or _beacon.is_used()):
		return null
	return self


## Arriving is where the work STARTS. Without this the receiver would drop the order the
## moment the spotter stopped walking — the same defect that used to lose a Build on
## approach.
func ends_on_arrival() -> bool:
	return false


## Stand still once the beacon is standing: the unit is committed to holding the solution,
## not to walking back to the point it was called from.
func should_move(a_actor: Actor) -> bool:
	return not _beacon_raised and not can_act(a_actor)


func can_act(a_actor: Actor) -> bool:
	if not _can_spot(a_actor):
		return false
	if _beacon_raised:
		# Holding. can_act stays true so the receiver keeps handing us ticks instead of
		# treating the unit as idle and letting aggro pick a target for it.
		return true
	if BeaconPlanter.plants(a_actor):
		return a_actor.xz_position.distance_to(_ground_xz()) <= BeaconPlanter.PLANT_REACH
	return a_actor.xz_position.distance_to(message.xz_position) <= Spot.target_range(a_actor)


## A planter walks to the ground it was pointed at, never after a unit it was pointed over.
func movement_destination(a_actor: Actor) -> Variant:
	return message.world_position if BeaconPlanter.plants(a_actor) else null


func fulfill_action(a_actor: Actor) -> Variant:
	if _beacon_raised:
		_hold_leash(a_actor)
		# Call the shot in from a battery left on automatic, as soon as one is ready. The
		# order still ends on the shot, so get_updated_state releases the spotter next tick.
		if is_instance_valid(_beacon):
			Bombard.autofire_on(_beacon)
		return self
	if not _can_spot(a_actor):
		return null
	if _held_pool == null and not _start_channel(a_actor):
		return null
	_channelled += 1
	if _channelled < Spot.channel_ticks():
		return self
	if BeaconPlanter.plants(a_actor):
		_plant_beacon(a_actor)
		return null  # planted and left: the order is done, and its cooldown starts now
	_beacon = _raise_beacon(a_actor)
	if _beacon == null:
		return null
	_beacon.dismiss_with_spotter(a_actor)
	_beacon_raised = true
	return self


## How far through the call this spotter is, 0..1 — for a HUD readout. 1.0 once the
## beacon stands, since the call is finished even though the command is not.
func channel_progress(a_actor: Actor) -> float:
	if _beacon_raised:
		return 1.0
	if not _can_spot(a_actor):
		return 0.0
	return clampf(float(_channelled) / float(Spot.channel_ticks()), 0.0, 1.0)


## Withdraw the solution when this order is replaced or cleared — unless a shot has been
## fired on it, when the shell in flight still needs it — and start the spotter's cooldown.
## See the class docs for why a re-ordered spotter must not leave its beacon behind.
func on_released(_a_actor: Actor) -> void:
	if is_instance_valid(_beacon) and not _beacon.is_used():
		_beacon.dismiss()
	_beacon = null
	_beacon_raised = false
	if is_instance_valid(_held_pool):
		_held_pool.release_recharge(ABILITY_ID, self)
	_held_pool = null


#endregion


#region Private helpers
## Spend the spotter's charge and hold its recharge until this order ends. False when it has
## none to spend — a queued order whose charge another order used first.
func _start_channel(a_actor: Actor) -> bool:
	var pool: Abilities = Spot._pool(a_actor)
	if pool == null or not pool.spend(ABILITY_ID):
		return false
	pool.hold_recharge(ABILITY_ID, self)
	_held_pool = pool
	return true


## Place the beacon at the ordered point — or, when the order named an enemy unit that can
## carry one (Beacon.can_carry: a grounded MECH unit), ON that unit, so it moves with it. It
## never expires on its own: a spotter's solution is held by the spotter, so its lifetime is
## this command's, not a timer's.
func _raise_beacon(a_actor: Actor) -> Beacon:
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


## Leave a point beacon on the ground the order named — what a Beacon Drop places. Not kept:
## nothing holds a planted beacon, so on_released must not find it to withdraw.
func _plant_beacon(a_actor: Actor) -> void:
	var map: Map = message.map if message.map != null else a_actor.map
	if map == null or a_actor.commander == null:
		return
	var piece: Entity = Beacon.SCENE.instantiate() as Entity
	piece.initialize(map, a_actor.commander)
	var xz: Vector2 = _ground_xz()
	piece.global_position = Vector3(xz.x, map.terrain_height_at(xz), xz.y)


## The ground point the order named, whatever piece it was aimed over.
func _ground_xz() -> Vector2:
	return VU.in_xz(message.world_position)


## THE LEASH: a beacon riding on a unit stands only while that unit stays within the
## spotter's target_range. A carrier that drives out of it drops the beacon — and a shell
## already tracking it lands where it last was. A point beacon has no leash.
func _hold_leash(a_actor: Actor) -> void:
	if not is_instance_valid(_beacon):
		return
	var carrier: Entity = _beacon.carrier()
	if (
		carrier != null
		and a_actor.xz_position.distance_to(carrier.xz_position) > Spot.target_range(a_actor)
	):
		_beacon.dismiss()
#endregion
