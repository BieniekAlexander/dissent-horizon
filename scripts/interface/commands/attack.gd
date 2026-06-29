class_name Attack
extends Command

#region Preconditions
static func requires_position() -> bool:
	return true

static func meets_precondition(
	a_actor: Commandable,
	a_message: CommandMessage
) -> PreconditionFailureCause:
	if not _target_attackable(a_message):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	if a_actor == null:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	if a_actor.weapon_inventory != null \
			and a_actor.weapon_inventory.any_weapon_can_target(a_message.target):
		return PreconditionFailureCause.NONE
	var garrison := a_actor.garrison
	if garrison != null and garrison.any_garrison_can_target(a_message.target):
		return PreconditionFailureCause.NONE
	return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
#endregion

#region Private helpers
static func _target_attackable(a_message: CommandMessage) -> bool:
	# TODO make it possible for units to attack the floor - unfortunately,
	# I previously wrote this such that a_message.target==null => the floor should be attacked,
	# but a_message.target becomes nul when a target dies, so checking it in that manner
	# causes this to always return true, even if the target used to be an object,
	# causing downstream checks to crash
	var t: Entity = a_message.target
	return is_instance_valid(t) and (t as Commandable) != null and (t as Commandable).defense != null

## Returns true when a structure's physics body lies on the line between
## a_actor and a_target (excluding a_target itself, so attacking a structure
## directly is never blocked by that same structure).
static func _structure_on_line(a_actor: Commandable, a_target: Entity) -> bool:
	var space_state := a_actor.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		a_actor.global_position,
		a_target.global_position,
		CollisionLayers.Mask.STRUCTURE_BLOCKER
	)
	# STRUCTURE_BLOCKER lives on the target's TargetBody child, so exclude that
	# (and the root) to avoid the target's own body counting as line-of-fire cover.
	var excludes: Array[RID] = [a_target.get_rid()]
	var target_cmd := a_target as Commandable
	if target_cmd != null and target_cmd.target_body != null:
		excludes.append(target_cmd.target_body.get_rid())
	query.exclude = excludes
	return not space_state.intersect_ray(query).is_empty()

## Returns the weapon from a_actor's inventory that can target message.target,
## or null if none can.
func _weapon_for(a_actor: Commandable) -> Weapon:
	if a_actor.weapon_inventory == null:
		return null
	return a_actor.weapon_inventory.weapon_for_target(message.target)

## True when a_actor is acting as a bunker: it owns a Garrison with bunker fire
## enabled and at least one unit garrisoned, so its garrisoned units' weapons can
## fire at the target even when the actor itself carries no weapon.
func _is_bunker(a_actor: Commandable) -> bool:
	var garrison := a_actor.garrison
	return garrison != null and garrison.bunker and garrison.garrisoned_count() > 0

## True when a_actor's own weapon can fire at message.target this tick.
func _own_weapon_can_fire(a_actor: Commandable) -> bool:
	var weapon := _weapon_for(a_actor)
	return weapon != null \
		and weapon.is_ready() \
		and SU.is_in_attack_range(weapon, a_actor, message.target)

## Drive a FLYING actor's dive-attack descent for this tick: while attacking a ground
## (non-air) target, ask Movement to dive toward the target so the unit drops out of the
## sky as it closes in. A no-op for non-FLYING actors and for air targets (those are
## engaged at cruise altitude). Movement eases the unit back up on its own once this stops
## being called — see Movement.request_dive / _update_flying_height.
func _update_flying_dive(a_actor: Commandable) -> void:
	var mv := a_actor.movement
	if mv == null or mv.mode != Movement.Mode.FLYING:
		return
	if not is_instance_valid(message.target):
		return
	var target_is_air: bool = \
		(message.target.targetable_layers() & CollisionLayers.Mask.TARGETABLE_AIR) != 0
	if target_is_air:
		return
	mv.request_dive(VU.inXZ(message.target.global_position))
#endregion

#region Properties
## Set to true once a melee-landing sequence has been initiated so subsequent
## ticks don't attempt to start a second landing while the first is in progress.
var _melee_landing_started: bool = false
#endregion

#region State updates
func get_updated_state(a_actor: Commandable):
	## Potentially return a new command based on a state check.
	if not is_instance_valid(message.target):
		return null
	# A target that is alive but no longer in the scene tree (e.g. it just entered a
	# Garrison, which orphans the node without freeing it) is unreachable. is_instance_valid()
	# still reports true for an orphaned node, so check tree membership explicitly — otherwise
	# reading message.target.global_position below warns and returns an identity transform.
	if not message.target.is_inside_tree():
		return null
	# A non-persistent attack (aggro / attack-move / defend) stops being pursued once the
	# target leaves the actor's leash. A persistent (player-issued) attack normally pursues
	# to completion — but only if the actor can MOVE to chase. A stationary attacker (e.g. a
	# garrison/bunker structure with no Movement) cannot close distance, so the leash applies
	# to it regardless of persist: otherwise an out-of-range manual target locks the command
	# forever — can_act stays false, the actor never goes idle, and aggro can never re-acquire
	# a target it could actually fire on (the cause of a bunker going silent after a retarget).
	# See CommandMessage.persist.
	var can_chase: bool = a_actor.movement != null
	if (not message.persist or not can_chase) and not _target_within_leash(a_actor):
		return null
	# While this attack is live, a FLYING actor dives onto a ground target (and climbs
	# back to cruise altitude once this stops being requested — i.e. when the command ends
	# above). Requested every tick because Movement.request_dive self-clears.
	_update_flying_dive(a_actor)
	return self

## Hysteresis factor applied to the weapon-range leash. The target is acquired at the
## (smaller) aggro range but only released past weapon-range × this factor, so a target
## jittering at the boundary doesn't churn acquire→drop — the cause of the Attack↔NULL
## flicker. > 1.0.
const _LEASH_HYSTERESIS: float = 1.25

## True when message.target is still close enough to keep pursuing a non-persistent
## attack. Two regimes:
##   * Defend override (message.aggro_shape set): the target must stay within that fixed
##     defend area, measured from the shape's own origin — unchanged, exact (no margin).
##   * Ordinary aggro-acquired attack: the target must stay within
##     max(weapon AttackRange, aggro range) × _LEASH_HYSTERESIS, measured from the actor.
##     Taking the max of the two keeps a unit engaging a target it can still shoot (weapon
##     range) while never leashing tighter than its aggro range; the margin is the
##     hysteresis that absorbs boundary jitter.
func _target_within_leash(a_actor: Commandable) -> bool:
	if message.aggro_shape != null:
		var origin: Vector3 = message.aggro_shape.global_transform.origin
		var radius: float = _shape_node_xz_radius(message.aggro_shape)
		if radius < 0.0:
			return true
		return VU.inXZ(origin).distance_to(VU.inXZ(message.target.global_position)) <= radius

	var leash: float = _leash_radius(a_actor)
	if leash < 0.0:
		return true
	return VU.inXZ(a_actor.global_position).distance_to(VU.inXZ(message.target.global_position)) <= leash

## The pursue radius for an ordinary attack: max(firing weapon's AttackRange, actor's
## aggro range) XZ radius × _LEASH_HYSTERESIS, or -1.0 when neither is known (treated as
## "always in range").
func _leash_radius(a_actor: Commandable) -> float:
	# A bunker host carries no weapon of its own (it fires through garrisoned units), so
	# _weapon_for returns null here — fall back to the aggro range alone rather than crashing.
	var weapon := _weapon_for(a_actor)
	var range_shape: CollisionShape3D = weapon.get_range_for_target(a_actor) if weapon != null else null
	var weapon_radius: float = _shape_node_xz_radius(range_shape) if range_shape != null else -1.0
	var aggro_radius: float = _shape_node_xz_radius(a_actor.aggro_range_shape)
	var base: float = maxf(weapon_radius, aggro_radius)
	return base * _LEASH_HYSTERESIS if base >= 0.0 else -1.0

## XZ radius of a CollisionShape3D node (shape radius × the node's X-axis scale), or
## -1.0 for a null node or unsupported shape.
func _shape_node_xz_radius(shape_node: CollisionShape3D) -> float:
	if shape_node == null:
		return -1.0
	return _shape_xz_radius(shape_node.shape, shape_node.global_transform.basis.x.length())


## Returns the effective XZ radius for supported shape types, or -1 for unknown shapes.
static func _shape_xz_radius(shape: Shape3D, scale: float) -> float:
	var cyl := shape as CylinderShape3D
	if cyl != null:
		return cyl.radius * scale
	var sph := shape as SphereShape3D
	if sph != null:
		return sph.radius * scale
	return -1.0

func should_move(a_actor: Commandable) -> bool:
	if not _target_attackable(message):
		return false
	var weapon := _weapon_for(a_actor)
	if weapon == null:
		return false
	return (
		not SU.is_in_attack_range(weapon, a_actor, message.target)
		or _structure_on_line(a_actor, message.target)
	)

func can_act(a_actor: Commandable) -> bool:
	if not _target_attackable(message) or message.target == a_actor:
		return false
	if _structure_on_line(a_actor, message.target):
		return false
	# Act when either the actor's own weapon or — for a bunker — any garrisoned
	# unit's weapon is loaded and in range. A weaponless bunker has no own weapon,
	# so the garrison branch is the only one that fires.
	return _own_weapon_can_fire(a_actor) \
		or (_is_bunker(a_actor) and a_actor.garrison.can_fire_at(a_actor, message.target))

func fulfill_action(a_actor: Commandable) -> Variant:
	# Fire the actor's own weapon when it is loaded and in range.
	if _own_weapon_can_fire(a_actor):
		var weapon := _weapon_for(a_actor)
		# A HOVERING unit attacking a grounded target with a melee weapon must
		# land first.  The strike fires from the landing callback; this branch
		# returns self to keep the command alive while the descent is in progress.
		# Once the callback fires the command is cleared by update_commands(null).
		var target_is_air: bool = (message.target.targetable_layers() & CollisionLayers.Mask.TARGETABLE_AIR) != 0
		if weapon.projectile_scene == null \
				and a_actor.movement != null \
				and a_actor.movement.mode == Movement.Mode.HOVERING \
				and not target_is_air:
			if not _melee_landing_started:
				_melee_landing_started = true
				a_actor.movement.land(func() -> void:
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
