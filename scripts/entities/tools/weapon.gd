@tool
class_name Weapon
extends Node3D

## A weapon that a commandable's Loadout can hold. Lives in the scene tree as
## a child of an Loadout node, with an AttackRange CollisionShape3D child that
## defines its reach. Every weapon has one — short-reach "melee" weapons simply
## use an AttackRange only slightly larger than the wielder's body shape.

#region Properties
#region ammo
## PHYSICS TICKS, not seconds — the countdowns below are decremented once per
## _physics_process, so ticks are the unit the mechanism actually works in. The gdd doc
## authors SECONDS (`split_time:` / `reload_time:`) and the importer converts through
## TimeUtils; the two are spelled differently on purpose, because they used to share a
## name and differ by a factor of 30 with nothing on either page to say so.
@export var split_time_ticks: int = 10  ## ticks between attacks
@export var reload_time_ticks: int = 10  ## ticks to restore a FULL clip
var _split_timer_ticks: int = 0  ## ticks until the next attack is ready
var _reload_timer_ticks: int = 0  ## ticks until the clip refills
@export var clip_size: int = 1  ## amount of ammo between reloads
## Ticks a target must be HELD — in range and aimed at — before the first shot at it. Doc key
## `startup_time:` (seconds). Zero fires as soon as the weapon is ready. The lock outlives a
## reload: a weapon that held its target through the reload fires again without re-waiting.
## Rules: gdd/systems/combat/weapon-cadence.md §Attack startup.
@export var startup_time_ticks: int = 0
## What the lock is on — an Entity, or a Vector3 for ground fire — and for how many ticks it
## has been held, and the physics frame it was last held on. Framework-imposed state: holding
## is observed one tick at a time by whichever command is aiming this weapon.
var _lock_target: Variant = null
var _lock_ticks: int = 0
var _lock_frame: int = -1
var _ammo: int = 1  ## current amount of ammo left, before reload timer finishes

## A CHARGED weapon does not replenish its own ammo. An ordinary weapon refills its clip
## on a timer wherever it happens to be standing; a charged one empties and STAYS empty
## until something recharges it from outside — today that is docking at an airfield's
## DockingBay, which calls recharge() every tick the unit is parked.
##
## The rate comes from the SAME `reload_time_ticks` an ordinary weapon uses, and means the same
## thing: the ticks needed to restore a full clip. So the two kinds of weapon are balanced
## against one number, and turning `charged` on changes WHERE the reload happens rather
## than how long it takes. The unloaded-time cost of being charged is the flight home,
## which is the mechanic's whole point.
@export var charged: bool = false

## The reach at or below which this weapon is MELEE: it has to be in CONTACT with what it
## is hitting. One terrain cell (Map.CELL_SIZE) — the smallest distance this game measures
## anything in, so a weapon that cannot reach across a single cell is not shooting across a
## gap, it is touching.
##
## Mirrored as SpecRules.MELEE_REACH_MAX so the importer can apply the same threshold
## without loading the terrain stack; the importer's coverage pass keeps the two together.
const MELEE_REACH_MAX: float = 1.0


## Whether this weapon can only be delivered by making contact with `a_target`.
##
## DERIVED FROM REACH, replacing the authored `dive_attack` export (and the `dive:` doc key
## that fed it). A FLYING carrier with a melee-reach weapon is a rammer — that is what
## ramming IS — so the flag was restating something the numbers already said, and a piece
## could set one without the other.
##
## The export's own comment argued against exactly this derivation, on the grounds that it
## "would silently change how a unit attacks the next time somebody rebalanced a number".
## That was right when nothing watched the numbers. It no longer is: the importer's
## `aerial_weapons_not_melee` rule refuses a FLYING piece with a melee-reach weapon unless
## its doc DECLARES itself a rammer, so pushing a reach across this threshold either trips a
## hard error or lands on a piece that has already said in writing that ramming is the plan.
## The change cannot be silent any more, which is the whole condition the objection named.
##
## Note what is NOT used: "does this weapon have a projectile". The kamikaze's bomb IS a
## projectile — it needs one to carry the blast — so that test would have switched the dive
## off for the one airframe that exists to dive.
func is_melee_ranged(a_target: Entity) -> bool:
	var reach: float = reach_for(a_target)
	return reach >= 0.0 and reach <= MELEE_REACH_MAX


## Tolerance, in ticks, when deciding a round's charge is complete. See _charge_accum.
const CHARGE_EPSILON: float = 0.001

## Docked TICKS banked by recharge() but not yet worth a whole round. Needed because the
## usual charge rate is well below one round per tick (a 180-tick reload of a 12-round clip
## is one round every 15), so without banking the clip would never advance at all.
##
## Deliberately counted in TICKS rather than in fractional rounds. Accumulating
## clip_size/reload_time_ticks per tick drifts: sixty additions of 10/60 sum to 9.999999, which
## floors to nine rounds and leaves a weapon one short of full for as long as it sits
## there. Adding 1.0 sixty times is exact in binary floating point, and the one division
## that converts it to rounds happens once — so a clip authored to fill in reload_time_ticks
## fills in exactly reload_time_ticks.
var _charge_accum: float = 0.0
#endregion

#region projectile evaluation
@onready var attack_range_shape_ground: CollisionShape3D = (
	(
		get_node_or_null("AttackRangeGround")
		if has_node("AttackRangeGround")
		else get_node("AttackRange")
	)
	if target_mask & CollisionLayers.Mask.TARGETABLE_GROUND
	else null
)

@onready var attack_range_shape_air: CollisionShape3D = (
	get_node_or_null("AttackRangeAir")
	if has_node("AttackRangeAir")
	else get_node("AttackRange") if target_mask & CollisionLayers.Mask.TARGETABLE_AIR else null
)

## projectile produced when firing (which may have its own damage evaluation)
@export var projectile_scene: PackedScene
@export var melee_damage: float = 10
@export var melee_damage_type: Damage.Type = Damage.Type.LEAD
#endregion

#region attack conditions
## Indicates which collision-layer-based targeting the weapon can hit
@export_flags_3d_physics var target_mask: int = CollisionLayers.Mask.TARGETABLE_GROUND
#endregion

#region turret
## Whether this weapon AIMS ON ITS OWN YAW rather than with its carrier's body. A turret
## weapon tracks its target by rotating itself (turret_yaw), so the body need not turn to
## face what it shoots; a weapon without one fires along the body's facing, and the carrier
## has to turn to aim it (Attack._update_facing). Doc key `turret:` on the weapon.
##
## What the player SEES turn is `turret_visual_path`, driven from turret_yaw; without one the
## turret still aims, it just has nothing to show it.
@export var turret: bool = false

## The model part that shows this turret — a Node3D whose origin sits on the turret's yaw
## axis, parented to the hull so its rotation.y reads body-relative, exactly as turret_yaw
## does. SCENE-AUTHORED, not a doc key: which node of a model is the turret is a fact about
## that model, not about the piece's stats. Empty = a turret with no visual of its own.
@export_node_path("Node3D") var turret_visual_path: NodePath

## How fast the turret swings while aiming, in DEGREES PER SECOND. Doc key
## `turret_turn_rate:`. Meaningless unless `turret` is set.
@export var turret_turn_rate: float = 360.0

## How long a turret that has lost its target holds its last bearing before it starts
## swinging back to face forward.
const TURRET_REST_DELAY_SECONDS: float = 1.7

## The return-to-forward swing's speed, as a fraction of turret_turn_rate: an idle turret
## drifts home rather than snapping there.
const TURRET_REST_RATE_FACTOR: float = 0.2

## Tolerance (radians) for is_turret_aimed_at(). The same hair Movement.is_facing() holds a
## turning body to: the turret must point DIRECTLY at its target. aim_turret_toward() lands
## exactly on the bearing whenever the remaining swing fits in one tick, so this only
## absorbs float error.
const TURRET_ALIGNMENT_EPSILON: float = 0.001

## The turret's yaw in radians RELATIVE TO THE CARRIER'S BODY (0 = the body's forward, +Z;
## see Movement.get_facing). Relative, so the turret turns with the hull and aiming
## compensates for it — which is also how a visual turret node parented to the hull reads it.
var turret_yaw: float = 0.0

## The resolved turret_visual_path node, or null. Resolved once in _ready.
var _turret_visual: Node3D = null

## Index of the launch point the next emission leaves from. Framework-imposed state: the
## ring of launch points is walked one shot at a time, so where the last shot left is the
## one fact the next shot needs.
var _next_launch_point: int = 0
## Pieces whose weapon has already been reported as sitting on its carrier's origin, keyed
## by scene path and weapon name — so the warning is said once per piece, not per spawn.
static var _warned_origin: Dictionary = {}
## Physics ticks since aim_turret_toward() was last called. Reset to 0 by every aim and
## counted up by _physics_process, so it cannot matter which of the two runs first in a tick.
var _turret_idle_ticks: int = 0
#endregion

#endregion


#region tool
func _validate_property(a_property: Dictionary) -> void:
	match a_property.name:
		"projectile":
			a_property.usage |= PROPERTY_USAGE_UPDATE_ALL_IF_MODIFIED
		"clip_size":
			a_property.usage |= PROPERTY_USAGE_UPDATE_ALL_IF_MODIFIED
		"melee_damage":
			if projectile_scene != null:
				melee_damage = 0.
				a_property.usage = a_property.usage | PROPERTY_USAGE_READ_ONLY
			else:
				a_property.usage = a_property.usage & ~PROPERTY_USAGE_READ_ONLY
		"melee_damage_type":
			melee_damage_type = Damage.Type.LEAD
			a_property.usage = (
				a_property.usage & ~PROPERTY_USAGE_READ_ONLY
				if projectile_scene == null
				else a_property.usage | PROPERTY_USAGE_READ_ONLY
			)
		"charged":
			a_property.usage |= PROPERTY_USAGE_UPDATE_ALL_IF_MODIFIED
		"reload_time_ticks":
			# A CHARGED weapon always authors its own reload_time_ticks, whatever the clip size:
			# the number is how long the unit must sit on a pad, so pinning it to split_time_ticks
			# for a single-round clip would make every such aircraft rearm instantly.
			if clip_size == 1 and not charged:
				reload_time_ticks = split_time_ticks
				a_property.usage = a_property.usage | PROPERTY_USAGE_READ_ONLY
			else:
				a_property.usage = a_property.usage & ~PROPERTY_USAGE_READ_ONLY


#endregion


#region lifecycle
func _ready() -> void:
	assert(
		(target_mask & CollisionLayers.TARGETABLE_ANY) != 0,
		"Weapon '%s': must set something as targetable" % name
	)
	assert(
		(target_mask & ~CollisionLayers.TARGETABLE_ANY) == 0,
		"Weapon '%s': target_mask may only set TARGETABLE_GROUND / TARGETABLE_AIR" % name
	)
	# An ordinary weapon is filled by the first _physics_process tick (its reload countdown
	# starts at 0). A charged one never runs that countdown, so it has to be seeded here or
	# it would spawn holding the single round _ammo is declared with.
	if charged:
		fill_clip()
	_resolve_turret_visual()
	_warn_if_launching_from_origin()


func _physics_process(_a_delta: float) -> void:
	if turret:
		_update_turret_rest()
	# CLAMPED AT ZERO, because is_ready() asks for EXACTLY zero. A weapon that becomes ready
	# and has nothing to shoot at must STAY ready — letting the timer run on into negatives
	# disarms it the tick after it came up.
	#
	# An ordinary weapon survived that (the reload branch below resets the timer every
	# `reload_time_ticks` ticks, so it recovered on its own within a clip), which is what hid this
	# for so long. A CHARGED weapon never reaches that branch — it returns two lines down —
	# so its timer went negative once and never came back: the Drake sat holding four rockets
	# it could not fire, spending no ammo and giving no sign of why.
	_split_timer_ticks = maxi(_split_timer_ticks - 1, 0)
	# A charged weapon's clip is refilled by recharge(), never by the passage of time, so
	# the reload countdown is simply not run for it — leaving it to tick would refill the
	# clip on schedule and there would be nothing to fly home for.
	if charged:
		return
	_reload_timer_ticks -= 1

	if _reload_timer_ticks <= 0:
		_split_timer_ticks = 0
		_ammo = clip_size


#endregion


#region Turret
## Swing the turret one tick toward `a_world_position` (XZ only), at turret_turn_rate.
## Called every tick by whatever is aiming this weapon (Attack, FocusFire); it also holds
## off the return-to-forward swing. Lands exactly on the bearing when the remaining swing
## fits in this tick, which is what lets is_turret_aimed_at() demand exact alignment.
func aim_turret_toward(a_carrier: Node3D, a_world_position: Vector3) -> void:
	_turret_idle_ticks = 0
	var dir: Vector3 = a_world_position - a_carrier.global_position
	dir.y = 0.0
	if dir.is_zero_approx():
		return
	var wanted: float = wrapf(atan2(dir.x, dir.z) - a_carrier.global_rotation.y, -PI, PI)
	_swing_turret_toward(wanted, turret_turn_rate)


## Whether the turret points DIRECTLY at `a_world_position` (XZ only). Vacuously true for a
## target on top of the carrier.
func is_turret_aimed_at(a_carrier: Node3D, a_world_position: Vector3) -> bool:
	var dir: Vector3 = a_world_position - a_carrier.global_position
	dir.y = 0.0
	if dir.is_zero_approx():
		return true
	return (
		absf(angle_difference(turret_world_yaw(a_carrier), atan2(dir.x, dir.z)))
		<= TURRET_ALIGNMENT_EPSILON
	)


## The turret's yaw in world space: the body's yaw plus turret_yaw.
func turret_world_yaw(a_carrier: Node3D) -> float:
	return wrapf(a_carrier.global_rotation.y + turret_yaw, -PI, PI)


## Once the turret has gone TURRET_REST_DELAY_SECONDS without being aimed, drift it back
## to the body's forward at TURRET_REST_RATE_FACTOR of its aiming speed.
func _update_turret_rest() -> void:
	_turret_idle_ticks += 1
	if _turret_idle_ticks <= TimeUtils.ticks_from_seconds(TURRET_REST_DELAY_SECONDS):
		return
	_swing_turret_toward(0.0, turret_turn_rate * TURRET_REST_RATE_FACTOR)


## Rotate turret_yaw toward `a_wanted` (body-relative radians) by at most one tick of
## `a_rate_degrees` per second, the short way round.
func _swing_turret_toward(a_wanted: float, a_rate_degrees: float) -> void:
	var max_step: float = deg_to_rad(a_rate_degrees) / float(TimeUtils.ticks_per_second())
	var delta: float = angle_difference(turret_yaw, a_wanted)
	if absf(delta) <= max_step:
		turret_yaw = a_wanted
	else:
		turret_yaw = wrapf(turret_yaw + signf(delta) * max_step, -PI, PI)
	_sync_turret_visual()


## Find the turret's model part. Skipped in the editor: this is a @tool script, and writing
## a rotation into an instanced model there would save it into the scene as an override.
## A path that is SET but resolves to nothing is a broken scene, so it warns; an empty one
## is a turret nobody has modelled yet, which is not an error.
func _resolve_turret_visual() -> void:
	if Engine.is_editor_hint() or not turret or turret_visual_path.is_empty():
		return
	_turret_visual = get_node_or_null(turret_visual_path) as Node3D
	if _turret_visual == null:
		push_warning(
			(
				"Weapon '%s': turret_visual_path %s does not resolve to a Node3D"
				% [name, turret_visual_path]
			)
		)
	else:
		_sync_turret_visual()


## Show turret_yaw on the model. Called wherever turret_yaw changes, so the model is
## never more than the tick it is aimed on behind the aim itself.
func _sync_turret_visual() -> void:
	if _turret_visual != null:
		_turret_visual.rotation.y = turret_yaw


#endregion


#region Launch points
## Where this weapon's emissions leave from: its LAUNCH POINTS, the Marker3D children, walked
## as a ring one shot at a time — a salvo launcher's separate tubes. With none, the weapon's
## own position is the one launch point. No count has to match the clip.
##
## A turret's weapon is placed in the TURRET'S frame rather than its carrier's, so its shots
## leave from the barrel however the turret has swung: the turret model when there is one
## (turret_visual_path), otherwise the carrier turned by turret_yaw. The Weapon node cannot
## live under the turret model — the Loadout owns it — so its position is READ in that frame,
## and the editor draws it in the carrier's. Positions are world units: the frames' scale
## (a weapon's basis scales its range shapes) is dropped.
func next_launch_position() -> Vector3:
	var points: Array[Marker3D] = launch_points()
	var local: Vector3 = Vector3.ZERO
	if not points.is_empty():
		_next_launch_point %= points.size()
		local = points[_next_launch_point].position
		_next_launch_point = (_next_launch_point + 1) % points.size()
	return launch_frame() * local


func launch_points() -> Array[Marker3D]:
	var found: Array[Marker3D] = []
	found.assign(get_children().filter(func(c: Node) -> bool: return c is Marker3D))
	return found


## The frame launch points are placed in, with this weapon's own position as its origin.
func launch_frame() -> Transform3D:
	var frame: Transform3D
	if _turret_visual != null:
		frame = Transform3D(
			_turret_visual.global_basis.orthonormalized(), _turret_visual.global_position
		)
	else:
		var carrier: Node3D = get_parent_node_3d()
		frame = (
			Transform3D(carrier.global_basis.orthonormalized(), carrier.global_position)
			if carrier != null
			else Transform3D.IDENTITY
		)
		if turret:
			frame.basis = frame.basis * Basis(Vector3.UP, turret_yaw)
	return frame * Transform3D(Basis.IDENTITY, position)


## Whether an emission would leave from the carrier's origin: this weapon has no offset of its
## own and some launch point has none either. The origin is inside the model on every piece.
func launches_from_origin() -> bool:
	if not position.is_zero_approx():
		return false
	var points: Array[Marker3D] = launch_points()
	return (
		points.is_empty()
		or points.any(func(m: Marker3D) -> bool: return m.position.is_zero_approx())
	)


## Report, once per piece, a weapon whose shots would come out of its carrier's origin. Only a
## scene-authored weapon is judged: one built in code has no authored position to be wrong.
func _warn_if_launching_from_origin() -> void:
	if Engine.is_editor_hint() or owner == null or not launches_from_origin():
		return
	var key: String = "%s:%s" % [owner.scene_file_path, name]
	if _warned_origin.has(key):
		return
	_warned_origin[key] = true
	push_warning(
		(
			(
				"Weapon '%s' on %s launches from its carrier's origin; give it a position "
				% [name, owner.scene_file_path]
			)
			+ "or launch points (Marker3D children)"
		)
	)


#endregion


#region Public API
## Returns true when this weapon can target the given entity: i.e. the target
## exposes a targetable layer (ground/air) that this weapon's target_mask covers.
## Entities with no targetable layer (targetable_layers() == 0) can't be attacked.
func can_target(a_target: Entity) -> bool:
	return (target_mask & a_target.targetable_layers()) != 0


## Rough per-shot damage this weapon deals: melee_damage for a melee weapon, or the
## fired projectile's base_damage for a ranged one (matching fire(), which applies
## melee_damage directly or spawns the projectile). Pre-modifier — ignores veterancy
## and the damage-vs-armour table — so it's a coarse figure for AI combat-power
## estimates, not exact in-fight damage. The ranged value is read by instantiating
## the projectile scene once (out of tree, so no _ready) and cached.
func per_shot_damage() -> float:
	_ensure_shot_cache()
	return _cached_per_shot_damage


## The Damage.Type a shot applies: melee_damage_type for melee, the projectile's
## damage_type for ranged. Pairs with per_shot_damage() for damage-table lookups
## (e.g. the bot's effectiveness-vs-armour targeting signal).
func per_shot_damage_type() -> Damage.Type:
	_ensure_shot_cache()
	return _cached_damage_type


## The range shape this weapon reaches `a_target` with: its AIR reach if the target is high
## enough off the ground, its GROUND reach otherwise.
##
## Asks `Entity.is_air_target()` — the same predicate that decides which targetable LAYER
## the piece sits on — so "what can shoot it" and "at what range" are one answer. It used to
## ask `is_airborne()`, a flight-state test that no ground unit could ever satisfy; a
## parachuting soldier was then shot at ground range while sitting on the air layer.
##
## NULL means THIS WEAPON HAS NO REACH AGAINST THAT SIDE — a ground-only weapon asked about
## an air target, or an anti-air one asked about a target on the ground. Callers must read it
## as "not in range" rather than assuming a shape is always there: `can_target()` is not a
## guarantee, because it reads the LATCHED Hurtbox layer while this reads LIVE altitude,
## and the two disagree for the one tick a piece spends crossing AIR_TARGET_ALTITUDE.
func get_range_for_target(a_target: Entity) -> CollisionShape3D:
	return attack_range_shape_air if a_target.is_air_target() else attack_range_shape_ground


## This weapon's reach against `a_target`, in world units — the XZ radius of the range
## shape it would use. -1.0 when there is no applicable range shape.
##
## Only the RADIUS is meaningful: every AttackRange is authored as a very tall cylinder
## (the spec importer forces height = SHAPE_HEIGHT), deliberately, so that a height
## difference between attacker and target never denies a shot across sloped terrain. That
## makes the shape useless as a measure of vertical separation — see Attack's dive-contact
## gate, which has to supply that separately.
func reach_for(a_target: Entity) -> float:
	return _range_radius(get_range_for_target(a_target))


## This weapon's reach against bare GROUND, in world units, or -1.0 when it has no ground
## range shape. The position-target counterpart of reach_for, which needs a target entity
## to decide which of the two range shapes applies; a patch of dirt is always the ground one.
func ground_reach() -> float:
	return _range_radius(attack_range_shape_ground)


## This weapon's reach against one targetable layer (a CollisionLayers.Mask bit), or -1.0
## when it cannot hit that layer at all.
func reach_on_layer(a_layer: int) -> float:
	if target_mask & a_layer == 0:
		return -1.0
	return _range_radius(
		(
			attack_range_shape_air
			if a_layer == CollisionLayers.Mask.TARGETABLE_AIR
			else attack_range_shape_ground
		)
	)


## Whether this weapon can be aimed at bare GROUND — the gate FocusFire is offered on.
##
## Two things are required and neither implies the other. It has to be allowed to hit the
## ground layer at all, and it has to deliver its damage with a PROJECTILE: melee damage is
## applied straight to a target entity (see fire), and a map coordinate is not one, so a
## bayonet has nothing it could do to a point.
func can_fire_at_ground() -> bool:
	return projectile_scene != null and (target_mask & CollisionLayers.Mask.TARGETABLE_GROUND) != 0


## The range node this weapon reaches the ground (or the air) with, whether or not the weapon
## currently hits that layer: AttackRangeGround / AttackRangeAir, or the one AttackRange both
## share. Null when the weapon has none.
func range_node(a_is_air: bool) -> CollisionShape3D:
	var split: String = "AttackRangeAir" if a_is_air else "AttackRangeGround"
	if has_node(split):
		return get_node(split) as CollisionShape3D
	return get_node_or_null("AttackRange") as CollisionShape3D


#region Range origin
## Where this weapon's reach is measured from. Doc key `range_from:` on the weapon.
## Rules: gdd/systems/combat/range-buckets.md §Where a reach is measured from.
enum RangeOrigin {
	## The gap between the wielder's footprint and the target's (SU.hull_gap) — so the wielder
	## closes range by moving.
	HULL,
	## The range shape standing at the centre of the wielder's ORBIT, overlapping the target's
	## hurtbox. The wielder's own position plays no part, so moving never closes range, and an
	## Attack never steers it (Commandable.fights_from_orbit).
	ORBIT,
}

@export var range_origin: RangeOrigin = RangeOrigin.HULL


## The point this weapon measures its reach from on [a_wielder], or null when that is its
## footprint (HULL). An ORBIT weapon on a wielder that does not orbit — anything but FLYING —
## falls back to its footprint: there is no orbit to stand the shape at.
func orbit_origin(a_wielder: Entity) -> Variant:
	if range_origin != RangeOrigin.ORBIT or a_wielder == null:
		return null
	var aerial: Aerial = a_wielder.get_node_or_null("Aerial") as Aerial
	if aerial == null or aerial.mode != Movement.Mode.FLYING:
		return null
	return aerial.anchor()


#endregion


## Change which targetable layers this weapon hits, re-resolving the range shapes that follow
## from it (they are chosen by the mask at _ready).
func retarget(a_mask: int) -> void:
	target_mask = (target_mask & ~CollisionLayers.TARGETABLE_ANY) | a_mask
	if not is_node_ready():
		return
	attack_range_shape_ground = (
		range_node(false) if target_mask & CollisionLayers.Mask.TARGETABLE_GROUND else null
	)
	attack_range_shape_air = (
		range_node(true) if target_mask & CollisionLayers.Mask.TARGETABLE_AIR else null
	)


## Change the clip size in play, keeping the fraction of the clip still loaded.
func resize_clip(a_clip_size: int) -> void:
	var old: int = maxi(clip_size, 1)
	clip_size = maxi(a_clip_size, 1)
	_ammo = clampi(roundi(float(_ammo) * clip_size / old), 0, clip_size)


## XZ radius of a range shape node — its shape radius scaled by the node's own X axis — or
## -1.0 for a missing node or an unsupported shape.
func _range_radius(a_shape_node: CollisionShape3D) -> float:
	if a_shape_node == null or a_shape_node.shape == null:
		return -1.0
	var scale: float = a_shape_node.global_transform.basis.x.length()
	if a_shape_node.shape is CylinderShape3D:
		return (a_shape_node.shape as CylinderShape3D).radius * scale
	if a_shape_node.shape is SphereShape3D:
		return (a_shape_node.shape as SphereShape3D).radius * scale
	return -1.0


## Populate the per-shot damage + type cache on first use, instantiating the
## projectile scene once (out of tree → no _ready) for ranged weapons.
func _ensure_shot_cache() -> void:
	if _cached_per_shot_damage >= 0.0:
		return
	if projectile_scene == null:
		_cached_per_shot_damage = melee_damage
		_cached_damage_type = melee_damage_type
	else:
		var proj: Node = projectile_scene.instantiate()
		var payload: Payload = Payload.of(proj)
		if payload != null:
			_cached_per_shot_damage = payload.base_damage
			_cached_damage_type = payload.damage_type
		else:
			_cached_per_shot_damage = 0.0
			_cached_damage_type = melee_damage_type
		proj.free()


var _cached_per_shot_damage: float = -1.0
var _cached_damage_type: Damage.Type = Damage.Type.LEAD


## Forget the per-shot cache, so the next read re-derives it — after a retune of the melee
## damage or of the emission this fires.
func invalidate_shot_cache() -> void:
	_cached_per_shot_damage = -1.0


## Set what one shot does without reading the emission scene — for the debug tuning editor,
## whose edited emission differs from the scene this would otherwise instantiate.
func set_shot_profile(a_damage: float, a_type: Damage.Type) -> void:
	_cached_per_shot_damage = a_damage
	_cached_damage_type = a_type


## Damage per second over a sustained firing cycle: a clip's shots `split` apart, then the
## reload. The reload timer restarts on every shot, so a reload no longer than the split never
## holds the weapon up. Base damage only — no armour, no blast, no misses, no startup.
static func sustained_damage_per_second(
	a_per_shot: float, a_split_ticks: int, a_reload_ticks: int, a_clip: int
) -> float:
	var clip: int = maxi(a_clip, 1)
	var split: float = TimeUtils.seconds_from_ticks(maxi(a_split_ticks, 1))
	var reload: float = TimeUtils.seconds_from_ticks(a_reload_ticks)
	if reload <= split:
		return a_per_shot / split
	return clip * a_per_shot / ((clip - 1) * split + reload)


## This weapon's sustained damage per second (sustained_damage_per_second).
func approximate_dps() -> float:
	return sustained_damage_per_second(
		per_shot_damage(), split_time_ticks, reload_time_ticks, clip_size
	)


func is_ready() -> bool:
	return _ammo > 0 and _split_timer_ticks == 0


#region Attack startup
## Record that `a_target` was held — in range and aimed at — on physics frame `a_frame`. Counts
## at most once per frame, so a command that asks twice in a tick does not double the hold. A
## different target, or a frame skipped since the last hold, starts the count again.
func hold_target(a_target: Variant, a_frame: int = Engine.get_physics_frames()) -> void:
	if a_frame == _lock_frame and _is_same_target(a_target):
		return
	if not _is_same_target(a_target) or a_frame != _lock_frame + 1:
		_lock_target = a_target
		_lock_ticks = 0
	_lock_ticks += 1
	_lock_frame = a_frame


## Whether the startup has been paid on `a_target`: held for startup_time_ticks, and held as
## recently as the previous frame. Always true for a weapon with no startup.
func is_locked_on(a_target: Variant, a_frame: int = Engine.get_physics_frames()) -> bool:
	return (
		startup_time_ticks <= 0
		or (
			_is_same_target(a_target)
			and _lock_ticks >= startup_time_ticks
			and a_frame - _lock_frame <= 1
		)
	)


## How far through its startup on `a_target` the weapon is, 0.0–1.0.
func lock_fraction(a_target: Variant, a_frame: int = Engine.get_physics_frames()) -> float:
	if startup_time_ticks <= 0:
		return 1.0
	if not _is_same_target(a_target) or a_frame - _lock_frame > 1:
		return 0.0
	return clampf(float(_lock_ticks) / float(startup_time_ticks), 0.0, 1.0)


## Entities compare by identity, points by position. Typed Variant because a held Entity may
## have been freed since, and a freed object cannot be passed to a typed parameter.
func _is_same_target(a_target: Variant) -> bool:
	if a_target is Vector3 and _lock_target is Vector3:
		return (a_target as Vector3).is_equal_approx(_lock_target)
	if a_target is Vector3 or _lock_target is Vector3 or _lock_target == null:
		return false
	return is_instance_valid(_lock_target) and is_same(a_target, _lock_target)


#endregion


#region Ammo
## Rounds left in the clip. Meaningful for every weapon; only a CHARGED one can be
## observed sitting at zero, since an ordinary weapon refills itself on the next tick.
func ammo() -> int:
	return _ammo


## True when this weapon is out of rounds AND cannot get more on its own — i.e. it is
## charged and empty. This is the single question the rearm mechanic asks: an ordinary
## weapon between shots is never "needing rearm", it is merely reloading.
func needs_recharge() -> bool:
	return charged and _ammo < clip_size


## True when a charged weapon is dry. Distinct from needs_recharge(): a half-full aircraft
## can still fight, and only a fully dry one has nothing left to do but fly home.
func is_out_of_ammo() -> bool:
	return charged and _ammo <= 0


## How full the clip is, 0.0–1.0 — the figure a HUD ammo bar draws. Guards clip_size == 0
## rather than trusting the export, since a zero would come back as a division by zero on
## a piece nobody has finished authoring.
func ammo_fraction() -> float:
	if clip_size <= 0:
		return 1.0
	return clampf(float(_ammo) / float(clip_size), 0.0, 1.0)


## How far an ORDINARY weapon is toward refilling its clip, 0.0–1.0; 0.0 when the clip is full.
## The clip refills whole, once `reload_time_ticks` pass without a shot, so this is one span
## rather than a per-round figure. A CHARGED weapon has no such clock — it refills only while
## something recharges it — and always reports 0.0.
func reload_fraction() -> float:
	if charged or _ammo >= clip_size or reload_time_ticks <= 0:
		return 0.0
	return clampf(1.0 - float(_reload_timer_ticks) / float(reload_time_ticks), 0.0, 1.0)


## Restore rounds worth `ticks` of docked time. `reload_time_ticks` is the ticks needed for a
## FULL clip, so the per-tick rate is clip_size / reload_time_ticks; the remainder is banked in
## _charge_accum so a rate below one round per tick still advances.
##
## Returns true once the clip is full, which is what tells the docking sequence the unit
## may take off again. A weapon that is not charged is a no-op reporting done — a bay that
## happens to hold an ordinary-weapon aircraft should release it, not hold it forever.
func recharge(a_ticks: float = 1.0) -> bool:
	if not charged or _ammo >= clip_size:
		_charge_accum = 0.0
		return true
	if reload_time_ticks <= 0 or clip_size <= 0:
		fill_clip()
		return true
	var ticks_per_round: float = float(reload_time_ticks) / float(clip_size)
	_charge_accum += a_ticks
	# CHARGE_EPSILON absorbs the residue left by a rate that does not divide evenly (a bay
	# charge_rate of 1.5, say). Without it a round can sit a whole extra tick behind a
	# boundary it has effectively reached; a tolerance of a thousandth of a tick cannot
	# advance a round early by any amount a player could perceive.
	while _charge_accum + CHARGE_EPSILON >= ticks_per_round and _ammo < clip_size:
		_charge_accum -= ticks_per_round
		_ammo += 1
	if _ammo >= clip_size:
		_charge_accum = 0.0
	# A weapon that was dry must not fire the instant its first round lands mid-burst
	# cadence, so the between-shots timer is deliberately NOT reset here — it is left to run
	# down on its own. (It used to be clamped up to zero at this point, which is now the
	# business of _physics_process and true every tick rather than only while docked.)
	return _ammo >= clip_size


## Fill the clip outright, bypassing the charge rate. For spawn seeding and for effects
## that resupply instantly.
func fill_clip() -> void:
	_ammo = clip_size
	_charge_accum = 0.0
	_reload_timer_ticks = 0


#endregion


func fire(a_owner: Commandable, a_target: Entity) -> void:
	if projectile_scene != null:
		_launch(a_owner, a_target)
	else:
		a_target.receive_damage(Damage.new(melee_damage, melee_damage_type), a_owner)

	consume_round()


## Fire at a POINT rather than at an entity — the ground-attack path (see FocusFire).
## Silently does nothing for a weapon that cannot shoot ground (see can_fire_at_ground), so
## a caller that has already gated on that never spends a round it cannot use.
##
## What the shot then does is the projectile's business, and honestly so: a blast lands and
## splashes whatever is standing there, while a single-target shot resolves onto the target
## it was fired at — which is nobody — and hurts nothing. Shelling a chokepoint works;
## emptying a rifle into the dirt does not.
func fire_at_position(a_owner: Commandable, a_position: Vector3) -> void:
	if not can_fire_at_ground():
		return
	_launch(a_owner, a_position)
	consume_round()


## Spawn one projectile at this weapon's next launch point, aimed at `a_target` — an Entity to
## home on or a bare Vector3 to land at (Emitter.launch takes either).
func _launch(a_owner: Commandable, a_target: Variant) -> void:
	var projectile: Entity = projectile_scene.instantiate()
	projectile.initialize(a_owner.map, a_owner.commander)
	projectile.global_position = next_launch_position()
	Emitter.launch(projectile, a_owner, a_target)


## Spend one round and restart both timers. Split out of fire() so the ammo bookkeeping
## can be exercised without a live target and a projectile scene — which for a CHARGED
## weapon is most of what there is to test.
func consume_round() -> void:
	_ammo -= 1
	_split_timer_ticks = split_time_ticks
	_reload_timer_ticks = reload_time_ticks
#endregion
