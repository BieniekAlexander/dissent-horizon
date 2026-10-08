class_name Attack
extends MoveCommand


#region Preconditions
static func requires_position() -> bool:
	return true


static func meets_precondition(
	actor: Actor, message: CommandMessage
) -> PreconditionFailureCause:
	if not _target_attackable(message):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	if actor == null:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	if (
		actor.weapon_inventory != null
		and actor.weapon_inventory.any_weapon_can_target(message.target)
	):
		return PreconditionFailureCause.NONE
	var garrison := actor.garrison
	if garrison != null and garrison.any_garrison_can_target(message.target):
		return PreconditionFailureCause.NONE
	return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE


#endregion


#region Private helpers
static func _target_attackable(message: CommandMessage) -> bool:
	# TODO make it possible for units to attack the floor - unfortunately,
	# I previously wrote this such that a_message.target==null => the floor should be attacked,
	# but a_message.target becomes nul when a target dies, so checking it in that manner
	# causes this to always return true, even if the target used to be an object,
	# causing downstream checks to crash
	var t: Entity = message.target
	return is_instance_valid(t) and t.is_attackable()


## True when an obstruction's body lies on the line between a_actor and a_target
## (excluding both ends: attacking a structure directly is never blocked by that same
## structure, and a structure SHOOTING is never blocked by itself — its ray starts at its
## own origin, on its own blocker body, which is how a Watch Tower once never fired
## unordered). Only between two pieces on the ground: when either is an AIR target, the
## shot clears every building, and may visually pass through one.
## Why: gdd/systems/combat/target-acquisition.md §Line of fire.
static func _obstruction_on_line(actor: Actor, target: Entity) -> bool:
	if actor.is_air_target() or target.is_air_target():
		return false
	var space_state := actor.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		actor.global_position, target.global_position, CollisionLayers.Mask.STRUCTURE_BLOCKER
	)
	# STRUCTURE_BLOCKER lives on a structure's Hurtbox child, so exclude that (and the root) of
	# both ends, so neither's own body counts as line-of-fire cover.
	var excludes: Array[RID] = []
	for end: Entity in [actor, target]:
		excludes.append(end.get_rid())
		if end.hurtbox != null:
			excludes.append(end.hurtbox.get_rid())
	query.exclude = excludes
	return not space_state.intersect_ray(query).is_empty()


## Returns the weapon from a_actor's inventory that can target message.target,
## or null if none can.
func _weapon_for(a_actor: Actor) -> Weapon:
	if a_actor.weapon_inventory == null:
		return null
	return a_actor.weapon_inventory.weapon_for_target(message.target)


## True when a_actor is acting as a bunker: it owns a Garrison with bunker fire
## enabled and at least one unit garrisoned, so its garrisoned units' weapons can
## fire at the target even when the actor itself carries no weapon.
func _is_bunker(a_actor: Actor) -> bool:
	var garrison := a_actor.garrison
	return garrison != null and garrison.bunker and garrison.garrisoned_count() > 0


## True when a_actor's own weapon can fire at message.target this tick. Requires
## the actor's body to already be facing the target — see _update_facing — so a
## unit visibly turns to aim before its first shot rather than firing sideways.
## Actors with no Movement (e.g. a stationary turret structure) have no facing
## to wait on and always pass this check.
##
## The HOLD is judged whether or not the weapon is loaded, so a weapon with an attack startup
## keeps its lock through a reload (Weapon.hold_target).
func _own_weapon_can_fire(a_actor: Actor) -> bool:
	var weapon := _weapon_for(a_actor)
	if weapon == null or not a_actor.can_use_weapons():
		return false
	var is_held: bool = (
		SU.is_in_attack_range(weapon, a_actor, message.target)
		and _dive_contact_made(a_actor, weapon)
		and _is_aimed_at_target(a_actor)
	)
	if is_held:
		weapon.hold_target(message.target)
	return is_held and weapon.is_ready() and weapon.is_locked_on(message.target)


## How far off its nose, in degrees, a unit that AIMS BY FLYING may shoot.
##
## A unit that turns to aim and then stops converges exactly on its target, so it is held to
## a hair. An aeroplane cannot: it never stops turning, its facing is a by-product of the
## velocity it is being steered along, and against anything that moves its nose lags the
## bearing permanently. Measured on a Drake attacking a tank crossing its path, that lag was
## 0.2 degrees the whole way in — dead-on to look at, and four times the tolerance, so it
## flew the entire run without firing a shot.
##
## Wide enough that ordinary steering lag never denies a shot, narrow enough that the
## aircraft still visibly points at what it is shooting rather than firing off its beam.
const FLYING_AIM_ARC_DEGREES: float = 20.0


## Whether the actor is pointing close enough at its target to shoot, by the standard that
## suits how it aims: exact alignment for anything that can stop and turn, a forward arc for
## anything that aims by flying.
func _is_aimed_at_target(a_actor: Actor) -> bool:
	var weapon := _weapon_for(a_actor)
	if weapon != null and weapon.turret:
		return weapon.is_turret_aimed_at(a_actor, message.target.global_position)
	if a_actor.movement == null:
		return true  # a turret structure has no facing to wait on
	if a_actor.movement.can_hold_still():
		return a_actor.movement.is_facing(message.target.global_position)
	return a_actor.movement.is_facing_within(
		message.target.global_position, deg_to_rad(FLYING_AIM_ARC_DEGREES)
	)


## True unless a DIVING attacker is still too high above its target's top to have reached it.
##
## Every AttackRange is a very tall cylinder, so it reports "in range" from cruise altitude —
## right for a unit standing on the ground, wrong for one that kills by RAMMING. So a diving
## attacker must additionally have come DOWN to within its own reach before it may strike.
##
## Gated on the WEAPON'S REACH (`Weapon.is_melee_ranged`), not on `Movement.Mode.FLYING`:
## gating on the mode stopped every ranged aircraft firing at all.
## Why: gdd/systems/combat/aerial-operations/attack-runs.md §The attack run.
func _dive_contact_made(a_actor: Actor, a_weapon: Weapon) -> bool:
	if a_weapon == null:
		return true
	var aerial: Aerial = a_actor.aerial
	if aerial == null or aerial.mode != Movement.Mode.FLYING:
		return true
	if (message.target.targetable_layers() & CollisionLayers.Mask.TARGETABLE_AIR) != 0:
		return true  # air-to-air is fought at altitude, not by ramming the ground
	if not a_weapon.is_melee_ranged(message.target):
		return true  # it shoots from cruise altitude; only a rammer has to come down
	# The gap the dive has to close is from the unit down to the TOP of its target, so it
	# strikes the target rather than burrowing through it to the ground.
	var gap: float = aerial.height_offset() - message.target.top_height()
	return gap <= a_weapon.reach_for(message.target)


## Drive a FLYING actor's dive-attack descent for this tick: while ramming a ground target,
## ask Movement to dive toward it so the unit drops out of the sky as it closes in. Movement
## eases the unit back up on its own once this stops being called — see Aerial.request_dive /
## _update_flying_height.
func _update_flying_dive(a_actor: Actor) -> void:
	if _rams_target(a_actor):
		a_actor.aerial.request_dive(
			VU.in_xz(message.target.global_position), message.target.top_height()
		)


## Whether [a_actor] attacks by RAMMING its target: a FLYING unit whose weapon reaches only
## as far as its own body (Weapon.is_melee_ranged), against a ground target. Air targets are
## engaged at cruise altitude, so they are never rammed.
func _rams_target(a_actor: Actor) -> bool:
	var aerial: Aerial = a_actor.aerial
	if aerial == null or aerial.mode != Movement.Mode.FLYING:
		return false
	if not is_instance_valid(message.target):
		return false
	var weapon := _weapon_for(a_actor)
	if weapon == null:
		return false
	if (message.target.targetable_layers() & CollisionLayers.Mask.TARGETABLE_AIR) != 0:
		return false
	# Asked AFTER the target-validity check: reach is measured against the target, so there
	# is nothing to ask until we know there is one.
	return weapon.is_melee_ranged(message.target)


## A rammer flies at its target's centre, never at the footprint-adjacent cell a FIXTURE
## target otherwise resolves to: that cell is where a WALKER stands to act, and arriving at it
## ends the order. The dive is timed to bottom out over the centre, so a drone sent to the cell
## arrived still above its reach and dropped the attack without striking (gdd/tasks.md T-009).
func movement_destination(a_actor: Actor) -> Variant:
	return message.target.global_position if _rams_target(a_actor) else null


## Aim [a_actor] at the target. A TURRET weapon (Weapon.turret) swings itself every tick —
## on the approach too, so it is already on target when the unit arrives — and the body
## never turns to aim it. Otherwise the body turns to face the target: the same
## `rotation.y` movement drives. The body only aims or stops while stationary
## (`should_move()` false); no-op for an actor with no Movement.
##
## Zeroes velocity explicitly, and that half is load-bearing: nothing else calls set_velocity
## while the actor is merely waiting to align, so the avoidance sim would keep re-simulating
## its stale approach velocity and rotating the body toward it. Why:
## gdd/systems/combat/aerial-operations/attack-runs.md §A stationary attacker aims itself.
func _update_facing(a_actor: Actor) -> void:
	var weapon := _weapon_for(a_actor)
	var turreted: bool = weapon != null and weapon.turret
	if turreted:
		weapon.aim_turret_toward(a_actor, message.target.global_position)
	# An actor that cannot stop never halts to aim: it aims by flying, or by its turret.
	if a_actor.movement == null or should_move(a_actor) or not a_actor.movement.can_hold_still():
		return
	a_actor.movement.stop()
	if not turreted:
		a_actor.movement.face_toward(message.target.global_position)


#endregion

#region Properties
## Set to true once a melee-landing sequence has been initiated so subsequent
## ticks don't attempt to start a second landing while the first is in progress.
var _melee_landing_started: bool = false
#endregion


## This order exists in order to shoot, so an empty charged loadout makes it undoable for
## now. The receiver stands it down into the queue rather than have the unit fly at
## something it cannot touch — it resumes once the unit has been back to an airfield.
func requires_ammo() -> bool:
	return true


#region State updates
func get_updated_state(a_actor: Actor) -> Variant:
	## Potentially return a new command based on a state check.
	if not is_instance_valid(message.target):
		return null
	# A target that is alive but no longer in the scene tree (e.g. it just entered a
	# Garrison, which orphans the node without freeing it) is unreachable. is_instance_valid()
	# still reports true for an orphaned node, so check tree membership explicitly — otherwise
	# reading message.target.global_position below warns and returns an identity transform.
	if not message.target.is_inside_tree():
		return null
	if _target_lost_from_sight(a_actor):
		return null
	# A non-persistent attack (aggro / attack-move / defend) stops being pursued once the
	# target leaves the actor's leash. A persistent (player-issued) attack normally pursues
	# to completion — but only if the actor can MOVE to chase. A stationary attacker (e.g. a
	# garrison/bunker structure with no Movement) cannot close distance, so the leash applies
	# to it regardless of persist: otherwise an out-of-range manual target locks the command
	# forever — can_act stays false, the actor never goes idle, and aggro can never re-acquire
	# a target it could actually fire on (the cause of a bunker going silent after a retarget).
	# See CommandMessage.persist.
	# A piece fighting from its orbit cannot chase either: moving never closes its range.
	var can_chase: bool = a_actor.can_move() and not a_actor.fights_from_orbit()
	if (not message.persist or not can_chase) and not _target_within_leash(a_actor):
		return null
	# While this attack is live, a FLYING actor dives onto a ground target (and climbs
	# back to cruise altitude once this stops being requested — i.e. when the command ends
	# above). Requested every tick because Aerial.request_dive self-clears.
	_update_flying_dive(a_actor)
	_update_facing(a_actor)
	return self


## Whether the target has been seen during this attack. Per-command state because "lost
## from sight" is a transition: an order may name a target nobody on the side can see yet —
## a scripted assault on a fogged base — and that one is pursued until it is first seen.
var _target_was_seen: bool = false


## True once a target this attack has SEEN is no longer visible to the actor's side — it
## ran into the fog or went stealthed — so the attack is dropped, persistent or not. The same
## vision gate idle aggro acquires through (gdd/systems/combat/target-acquisition.md).
func _target_lost_from_sight(a_actor: Actor) -> bool:
	var is_seen: bool = message.target.is_visible_to(a_actor.commander_id)
	var is_lost: bool = _target_was_seen and not is_seen
	_target_was_seen = _target_was_seen or is_seen
	return is_lost


## Hysteresis factor applied to the weapon-range leash. The target is acquired at the
## (smaller) aggro range but only released past weapon-range × this factor, so a target
## jittering at the boundary doesn't churn acquire→drop — the cause of the Attack↔NULL
## flicker. > 1.0.
const _LEASH_HYSTERESIS: float = 1.25


## True when message.target is still close enough to keep pursuing a non-persistent
## attack. A weapon measuring from its wielder's orbit leashes by its own range shape at the
## orbit's centre, grown by the same hysteresis. Otherwise, two regimes:
##   * Defend override (message.aggro_shape set): the target's footprint must stay within
##     that fixed defend area, measured from its centre point — exact, no margin. The area
##     is centred on `message.aggro_center` when the order named one, which is what pins it
##     to the POST: the shape node itself is often the defender's own AggroRange, and reading
##     its live origin would put the area wherever the defender happens to be standing (see
##     Defend._leash_to_defended_area).
##   * Ordinary aggro-acquired attack: the target must stay within
##     max(weapon AttackRange, aggro range) × _LEASH_HYSTERESIS, measured between the two
##     footprints (SU.hull_gap) — the aggro volume for the target's own layer, ground or air.
##     Taking the max of the two keeps a unit engaging a target it can still shoot (weapon
##     range) while never leashing tighter than its aggro range; the margin is the
##     hysteresis that absorbs boundary jitter.
func _target_within_leash(a_actor: Actor) -> bool:
	if message.aggro_shape != null:
		var origin: Vector3 = (
			message.aggro_center
			if message.aggro_center is Vector3
			else message.aggro_shape.global_transform.origin
		)
		var radius: float = _shape_node_xz_radius(message.aggro_shape)
		if radius < 0.0:
			return true
		return message.target.hull().distance_to_point(VU.in_xz(origin)) <= radius

	var weapon := _weapon_for(a_actor)
	if weapon != null and weapon.orbit_origin(a_actor) is Vector3:
		var reach: float = weapon.reach_for(message.target)
		return (
			reach < 0.0
			or SU.is_in_attack_range(
				weapon, a_actor, message.target, reach * (_LEASH_HYSTERESIS - 1.0)
			)
		)
	var leash: float = _leash_radius(a_actor)
	if leash < 0.0:
		return true
	return SU.hull_gap(a_actor, message.target) <= leash


## The pursue radius for an ordinary attack: max(firing weapon's AttackRange, actor's
## aggro range) XZ radius × _LEASH_HYSTERESIS, or -1.0 when neither is known (treated as
## "always in range").
func _leash_radius(a_actor: Actor) -> float:
	# A bunker host carries no weapon of its own (it fires through garrisoned units), so
	# _weapon_for returns null here. It leashes by its occupants' reach instead
	# (Actor.reach_on_layer) — the aggro fallback is capped below long reach and dropped
	# targets the occupants could still hit.
	var weapon := _weapon_for(a_actor)
	if weapon == null:
		var layer: int = (
			CollisionLayers.Mask.TARGETABLE_AIR
			if message.target.targetable_layers() & CollisionLayers.Mask.TARGETABLE_AIR != 0
			else CollisionLayers.Mask.TARGETABLE_GROUND
		)
		var base_reach: float = maxf(
			a_actor.reach_on_layer(layer),
			_shape_node_xz_radius(a_actor.aggro_shape_for(message.target))
		)
		return base_reach * _LEASH_HYSTERESIS if base_reach >= 0.0 else -1.0
	# TODO: this asks for the reach against A_ACTOR, not against message.target — so a flying
	# attacker leashes by its AIR reach while chasing something on the ground. Looks like a
	# slip rather than a decision, but correcting it changes pursuit distances for every
	# air/ground pairing, so it wants a deliberate pass rather than a drive-by fix.
	var range_shape: CollisionShape3D = (
		weapon.get_range_for_target(a_actor) if weapon != null else null
	)
	var weapon_radius: float = _shape_node_xz_radius(range_shape) if range_shape != null else -1.0
	var aggro_radius: float = _shape_node_xz_radius(a_actor.aggro_shape_for(message.target))
	var base: float = maxf(weapon_radius, aggro_radius)
	return base * _LEASH_HYSTERESIS if base >= 0.0 else -1.0


## XZ radius of a CollisionShape3D node (shape radius × the node's X-axis scale), or
## -1.0 for a null node or unsupported shape.
func _shape_node_xz_radius(a_shape_node: CollisionShape3D) -> float:
	if a_shape_node == null:
		return -1.0
	return _shape_xz_radius(a_shape_node.shape, a_shape_node.global_transform.basis.x.length())


## Returns the effective XZ radius for supported shape types, or -1 for unknown shapes.
static func _shape_xz_radius(shape: Shape3D, scale: float) -> float:
	var cyl := shape as CylinderShape3D
	if cyl != null:
		return cyl.radius * scale
	var sph := shape as SphereShape3D
	if sph != null:
		return sph.radius * scale
	return -1.0


## Whether the actor should still be closing on its target.
##
## AN ACTOR THAT CANNOT HOLD STILL ALWAYS SAYS YES. A fixed wing has no way to stop and
## trade fire, so "in range" is not a reason for it to stop being driven — it flies at the
## target, shoots as it goes, passes over and comes around. Without this it fell into the
## hole between the two branches the moment its clip ran dry: not able to act (nothing
## loaded), not supposed to move (already in range), so nothing drove it at all and it
## coasted to a dead stop in mid-air over its victim.
##
## A PIECE FIGHTING FROM ITS ORBIT NEVER SAYS YES (Actor.fights_from_orbit): its range is
## measured from the orbit's centre, so flying at the target would close nothing — the target
## changes what it shoots at, never where it flies.
func should_move(a_actor: Actor) -> bool:
	if not _target_attackable(message):
		return false
	var weapon := _weapon_for(a_actor)
	if weapon == null or a_actor.fights_from_orbit():
		return false
	if a_actor.movement != null and not a_actor.movement.can_hold_still():
		return true
	return (
		not SU.is_in_attack_range(weapon, a_actor, message.target)
		or _obstruction_on_line(a_actor, message.target)
	)


func releases_hold_fire() -> bool:
	return true


## A piece fighting from its orbit keeps circling the orbit it had: its target is something it
## shoots at, not somewhere it flies.
func orbit_anchor(a_actor: Actor) -> Variant:
	return null if a_actor.fights_from_orbit() else message.position


func holds_ground(a_actor: Actor) -> bool:
	return _target_attackable(message) and _weapon_for(a_actor) != null and not should_move(a_actor)


func acting_action(_a_actor: Actor) -> ActionTracker.Action:
	return ActionTracker.Action.ATTACKING


func can_act(a_actor: Actor) -> bool:
	if not _target_attackable(message) or message.target == a_actor:
		return false
	if _obstruction_on_line(a_actor, message.target):
		return false
	# Act when either the actor's own weapon or — for a bunker — any garrisoned
	# unit's weapon is loaded and in range. A weaponless bunker has no own weapon,
	# so the garrison branch is the only one that fires.
	return (
		_own_weapon_can_fire(a_actor)
		or (_is_bunker(a_actor) and a_actor.garrison.can_fire_at(a_actor, message.target))
	)


func fulfill_action(a_actor: Actor) -> Variant:
	# Fire the actor's own weapon when it is loaded and in range.
	if _own_weapon_can_fire(a_actor):
		var weapon := _weapon_for(a_actor)
		# A HOVERING unit attacking a grounded target with a melee weapon must
		# land first.  The strike fires from the landing callback; this branch
		# returns self to keep the command alive while the descent is in progress.
		# Once the callback fires the command is cleared by update_commands(null).
		var target_is_air: bool = (
			(message.target.targetable_layers() & CollisionLayers.Mask.TARGETABLE_AIR) != 0
		)
		if (
			weapon.projectile_scene == null
			and a_actor.aerial != null
			and a_actor.aerial.mode == Movement.Mode.HOVERING
			and not target_is_air
		):
			if not _melee_landing_started:
				_melee_landing_started = true
				a_actor.aerial.land(
					func() -> void:
						if not is_instance_valid(a_actor) or not is_instance_valid(message.target):
							return
						weapon.fire(a_actor, message.target)
						if a_actor.stealth != null:
							a_actor.stealth.unstealth()
						a_actor.update_commands(null)
				)
			return self
		weapon.fire(a_actor, message.target)
		# Attacking breaks stealth: force the timed UNSTEALTHED window.
		if a_actor.stealth != null:
			a_actor.stealth.unstealth()
	# Bunker fire: each garrisoned inventory produces a projectile from its first
	# target-capable, loaded, in-range weapon, fired from the actor's position.
	if _is_bunker(a_actor):
		a_actor.garrison.tick_bunker_fire(a_actor, message.target)
	return self


#endregion


#region Debug
func _to_string() -> String:
	return "Attack: %s" % message.position
#endregion
