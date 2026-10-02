class_name FocusFire
extends MoveCommand

## Shoot at a PLACE. The order names a point on the ground and nothing else, so the actor
## walks into range, turns to face it, and keeps firing at it until told otherwise.
##
## Its own class rather than a mode of [Attack], because Attack is built end to end around
## a target ENTITY: `weapon_for_target`, `is_in_attack_range`, the leash, the dive gate and
## `Weapon.fire` all take one, and the one hook that could have carried a point — a null
## `message.target` — is the same null a DEAD target leaves behind. Attack's own
## `_target_attackable` carries the note about that: making null mean "the floor" made every
## finished engagement read as an order to shell the ground where the victim had stood.
##
## Why it is worth having: reach without a target. Shelling a chokepoint, flushing something
## out of a treeline, and putting a blast down on ground a spotter has eyes on are all
## orders the game could not previously express.
##
## What lands is the projectile's business. A blast splashes whatever is standing there; a
## single-target shot resolves onto the target it was fired at — nobody — and does nothing.
## Only a weapon that can do something to a point is offered the order at all (see
## Weapon.can_fire_at_ground).


#region Preconditions
static func requires_position() -> bool:
	return true


## Offered to an actor holding a weapon that can be aimed at ground, and refused to an
## IMMOBILE one aimed past its reach — a turret told to shell something it can never walk
## closer to would hold the order for ever (see MoveCommand.unreachable_for_immobile).
static func meets_precondition(
	actor: Commandable, message: CommandMessage
) -> PreconditionFailureCause:
	if actor == null or not is_instance_valid(actor):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	var weapon: Weapon = ground_weapon_of(actor)
	if weapon == null:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	var reach: float = weapon.ground_reach()
	# unreachable_for_immobile measures to message.position, which prefers a piece under the
	# cursor; this order aims at the ground, so it measures to the aim point instead.
	if (
		reach >= 0.0
		and message != null
		and not actor.can_move()
		and not within_reach(actor.hull(), VU.inXZ(aim_point(message)), reach)
	):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	return PreconditionFailureCause.NONE


## Where the order aims: the GROUND point the player clicked — never a piece under the
## cursor. The controller writes the piece under the pointer onto `message.target` for every
## order, and `CommandMessage.position` prefers that piece over the clicked ground, so reading
## `position` here let a ground-only weapon (a Badger) be pointed at a HOVERING unit: the
## rocket flew at the aircraft's altitude, burst in the air beside it, and its blast did the
## damage the weapon's own target mask forbids. `world_position` is always the terrain under
## the cursor (RTSController._cursor_ground_point), which is what "shoot at a place" means.
static func aim_point(a_message: CommandMessage) -> Vector3:
	return a_message.world_position


## The weapon `a_actor` would shell a point with, or null if it has none. Static so the
## precondition and the HUD's capability question read one statement of it.
static func ground_weapon_of(actor: Commandable) -> Weapon:
	if actor == null or not is_instance_valid(actor):
		return null
	var loadout := actor.get_node_or_null("Loadout") as Loadout
	return loadout.weapon_for_ground_fire() if loadout != null else null


#endregion


#region Properties
## Whether a firer with footprint `from` is close enough to the aimed point to shoot, given
## `reach`: the gap from its footprint to the point, as for every range (a point is a
## footprint of no size — see Hull). Height is ignored for the same reason every AttackRange
## is authored as a very tall cylinder: a slope must never deny a shot.
static func within_reach(from: Hull, point: Vector2, reach: float) -> bool:
	return reach >= 0.0 and from.distance_to_point(point) <= reach


#endregion


#region State updates
func _aim() -> Vector3:
	return aim_point(message)


func _aim_xz() -> Vector2:
	return VU.inXZ(aim_point(message))


## An order to shoot is undoable with an empty charged clip; the receiver stands it down
## and the unit flies home. Same rule Attack states, for the same reason.
func requires_ammo() -> bool:
	return true


func get_updated_state(a_actor: Commandable) -> Variant:
	var weapon: Weapon = ground_weapon_of(a_actor)
	if weapon == null:
		return null
	# A turret weapon swings itself onto the point every tick, as in Attack._update_facing.
	if weapon.turret:
		weapon.aim_turret_toward(a_actor, _aim())
	# Otherwise turn to face the point once we have stopped closing on it, exactly as Attack
	# does — while still approaching, Movement's own turn-toward-heading facing owns
	# rotation.y and the two must not fight over it.
	if a_actor.movement != null and not should_move(a_actor):
		a_actor.movement.stop()
		if not weapon.turret:
			a_actor.movement.face_toward(_aim())
	return self


## Arriving is the SETUP, not the point: the actor walks into range in order to shoot from
## there. Dropping the order on arrival would leave it standing on the spot it was told to
## shell with nothing to do (see MoveCommand.ends_on_arrival).
func ends_on_arrival() -> bool:
	return false


func should_move(a_actor: Commandable) -> bool:
	var weapon: Weapon = ground_weapon_of(a_actor)
	if weapon == null:
		return false
	# A fixed wing cannot stop to shoot, so being in range is no reason to stop driving it —
	# it flies at the point, fires as it goes, and comes around. See Attack.should_move.
	if a_actor.movement != null and not a_actor.movement.can_hold_still():
		return true
	return not within_reach(a_actor.hull(), _aim_xz(), weapon.ground_reach())


func holds_ground(a_actor: Commandable) -> bool:
	return ground_weapon_of(a_actor) != null and not should_move(a_actor)


func acting_action(_a_actor: Commandable) -> ActionTracker.Action:
	return ActionTracker.Action.ATTACKING


func can_act(a_actor: Commandable) -> bool:
	var weapon: Weapon = ground_weapon_of(a_actor)
	if weapon == null or not a_actor.can_use_weapons():
		return false
	# Held whether or not the weapon is loaded, as in Attack, so an attack startup survives a reload.
	var is_held: bool = (
		within_reach(a_actor.hull(), _aim_xz(), weapon.ground_reach())
		and _is_aimed_at_point(a_actor)
	)
	if is_held:
		weapon.hold_target(_aim())
	return is_held and weapon.is_ready() and weapon.is_locked_on(_aim())


## Whether the actor is pointing close enough at the aimed point to shoot, by the standard
## that suits how it aims — exact for anything that can stop and turn, a forward arc for
## anything that aims by flying. Mirrors Attack's rule, which is the one the player has
## already learned; the arc constant is shared rather than restated.
func _is_aimed_at_point(a_actor: Commandable) -> bool:
	var weapon: Weapon = ground_weapon_of(a_actor)
	if weapon != null and weapon.turret:
		return weapon.is_turret_aimed_at(a_actor, _aim())
	if a_actor.movement == null:
		return true  # a turret structure has no facing to wait on
	if a_actor.movement.can_hold_still():
		return a_actor.movement.is_facing(_aim())
	return a_actor.movement.is_facing_within(_aim(), deg_to_rad(Attack.FLYING_AIM_ARC_DEGREES))


## KEEPS FIRING. Ground does not die, so nothing ends this order except the player — which
## is what "attack ground" means in every game that has it: a battery told to shell a
## crossing shells it until it is told to stop.
func fulfill_action(a_actor: Commandable) -> Variant:
	var weapon: Weapon = ground_weapon_of(a_actor)
	if weapon == null:
		return null
	weapon.fire_at_position(a_actor, _aim())
	if a_actor.stealth != null:
		a_actor.stealth.unstealth()
	return self


#endregion


#region Debug
func _to_string() -> String:
	return "FocusFire: %s" % aim_point(message)
#endregion
