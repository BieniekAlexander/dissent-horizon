class_name Entity
extends CharacterBody3D

#region Identity
## The game-piece identifier: the id of this entity's spec doc in gdd/ (see
## tools/spec_import). Generated constants live in EntityIds — use
## `EntityIds.AN_BIO_MEDIUM_DOMINION_GEN`, not a raw &"an_bioMedium_dominionGen", in hand-written
## code. Empty on
## abstract inheritance-base scenes (unit.tscn etc.), which are never used in
## game; is_abstract() gates validation and export tooling on that.
@export var id: StringName = &""

## Inspector shortcut: set the in-game commander index for this entity.
## Entities placed in the editor use this to auto-initialize at run time;
## entities spawned by the scenario ignore it (initialize() is called explicitly).
@export_range(0, 5) var default_commander_id: int = 0

## How much room this entity takes up INSIDE another entity — how much of a
## [Garrison]'s `capacity` it consumes when it occupies one (see Garrison.size_of).
## 1 for an ordinary soldier; raise it for something bulky, e.g. a collective at 2,
## which fills twice as much of a transport as a lone infantryman does.
## Every entity carries a size so any of them can be a garrison occupant; it is
## meaningless for entities that never enter one (projectiles, hit boxes).
@export_range(1, 16) var occupancy_size: int = 1


## Inheritance-base scenes (unit.tscn / abstract_structure.tscn) leave `id`
## empty; they exist for scene inheritance, not gameplay.
func is_abstract() -> bool:
	return id.is_empty()


const TEAM_COLOR_MAP: Dictionary = {
	0: Color.WHITE,
	1: Color(.2, 1, 1),
	2: Color(1, 1, .2),
	3: Color(.1, .6, .1),
	4: Color(1, .2, .2),
	# Slots 5–8: the skirmish lobby offers up to Commander.NUM_MAX_COMMANDERS players.
	5: Color(1, .55, .1),
	6: Color(.7, .3, 1),
	7: Color(1, .45, .75),
	8: Color(.55, .75, .55),
}
#endregion

#region Lifecycle occurrences
## Lifecycle moments that can happen to an entity — the "occurrence" (condition-side)
## inputs that an EntityTrigger reacts to, distinct from an Event (the world-update it
## fires). Selects which EntityTrigger reacts, and is the payload of the `entity_occurrence`
## signal. Stealth occurrences emit from Stealth's state transitions. Attacker occurrences
## (ON_DEAL_DAMAGE, ON_KILL) fire on the attacker via receive_damage; ON_FINISH_BUILD fires
## on the builder from Repair.fulfill_action when construction completes.
enum EntityOccurrence {
	ON_DEATH = 0,
	ON_RECEIVE_DAMAGE = 1,
	ON_ENTER_STEALTH = 2,
	ON_EXIT_STEALTH = 3,
	ON_DEAL_DAMAGE = 4,
	ON_KILL = 5,
	ON_FINISH_BUILD = 6,
}

## Per-entity reactions are authored as EntityTrigger CHILD NODES of this entity, each
## with its own child AbstractEvent node(s). When an occurrence fires, the matching child
## trigger runs its events (see _fire_entity_occurrence). Mirrors how GlobalTriggers are
## child nodes of the ScenarioTriggerManager — no PackedScene-on-a-Resource (which crashes
## the editor inspector).

## Emitted whenever a lifecycle occurrence happens on this entity, regardless of whether
## a reaction scene is configured — so other systems (audio, score, AI) can listen.
signal entity_occurrence(occurrence: EntityOccurrence, source: Entity)

## Cached ScenarioTriggerManager (the reaction dispatcher), resolved lazily from the
## current scene. Null when the scene has no manager — reactions are then skipped,
## though `entity_occurrence` still fires.
var _trigger_manager: ScenarioTriggerManager

## The commander whose piece last hurt this one, or -1 when the last hit was unattributed (an
## unowned strike, a status effect whose source is gone). Written BEFORE ON_RECEIVE_DAMAGE fires,
## so a listener knows friendly fire from an attack — AlertCenter, which must not tell a player
## their base is under attack by their own splash. Not cleared: read it in the occurrence.
var last_hit_by_commander_id: int = -1
#endregion

#region Identity
## Ownership component — owns the commander relationship. Resolved at _ready
## time (scene composition: see unit.tscn, structure.tscn). Entities without
## an Ownership child (e.g. star.tscn) fall back to the private _commander
## field below.
@onready var ownership: Ownership = $Ownership

var commander: Commander:
	get:
		return ownership.commander
	set(value):
		ownership.commander = value

var commander_id: int:
	get:
		return ownership.commander_id


## Ownership-relationship helpers. commander_id 0 is the neutral/world owner (see
## CLAUDE.md): neither friend nor foe. These centralize the commander_id
## comparisons that were otherwise duplicated (in subtly different, easy-to-invert
## shapes) across aggro, detection, AI, and command code.
func is_neutral() -> bool:
	return commander_id == 0


## True when `other` is on this entity's side: the same owner, or an ally of it. Two neutral
## pieces are friendly to each other; a neutral and an owned piece never are.
## gdd/systems/combat/target-acquisition.md §Alliances.
func is_friendly_to(a_other: Entity) -> bool:
	return a_other != null and is_on_side_of(a_other.commander_id)


## True when `other` is an enemy of this entity: owned (not neutral) by a commander outside
## this entity's alliance.
func is_enemy_of(a_other: Entity) -> bool:
	return a_other != null and a_other.commander_id > 0 and not is_friendly_to(a_other)


## True when commander `a_commander_id` owns this entity or is an ally of its owner — the test
## for "yours or an ally's" when the asker has only an id (a viewer, the local player).
func is_on_side_of(a_commander_id: int) -> bool:
	if a_commander_id == commander_id:
		return true
	var owning: Commander = commander
	return owning != null and owning.is_allied_with(a_commander_id)


## The commander ids on this entity's side, as bits (bit k = commander k): what an aggro query
## leaves out (CollisionLayers.hostile_mask). 0 for a neutral piece, which has no side.
func allied_commander_ids() -> int:
	var owning: Commander = commander
	if owning != null:
		return owning.allied_ids_mask()
	return (1 << commander_id) if commander_id > 0 else 0


#endregion

#region Components
## Defense component — owns hp, hp_max, and armor. Null for entities with no
## concept of HP (e.g. an emission, a HitBox).
@onready var defense: Defense = get_node_or_null("Defense") as Defense

## Flight and height — present on a piece that flies. See aerial.gd.
@onready var aerial: Aerial = get_node_or_null("Aerial") as Aerial

## The piece's Locomotion node, whatever its strategy and whether or not it is live. Only
## the form switch and the wiring that must survive a switch read it directly.
@onready var locomotion_component: Locomotion = get_node_or_null("Locomotion") as Locomotion

## The NAVIGATED locomotion whether or not it is live, or null when the piece moves some
## other way or not at all.
@onready var movement_component: Movement = locomotion_component as Movement

## The LIVE Movement component — the NAVIGATED locomotion — or null when the entity has none,
## and also while it is inactive (a transformer in its deployed form). Ask it only for what is
## particular to navigated movers (modes, the nav agent, landing); "can this move?" is can_move.
var movement: Movement:
	get:
		return (
			movement_component
			if movement_component != null and movement_component.is_active
			else null
		)
	set(a_value):
		movement_component = a_value
		locomotion_component = a_value

## The piece's live locomotion, whatever its strategy, or null when it has none or it is
## switched off (a transformer in its deployed form).
var locomotion: Locomotion:
	get:
		return movement if locomotion_component is Movement else locomotion_component


## Whether this piece can move at all right now: it has live locomotion, and that locomotion
## is not one that ignores its goal (a Recon Drone hovering at speed 0).
func can_move() -> bool:
	var live: Locomotion = locomotion
	return live != null and live.can_move()


## Stealth component — present on entities that can be hidden from enemies.
## Null for entities that are always fully visible.
@onready var stealth: Stealth = get_node_or_null("Stealth") as Stealth

## Detection shape — present on entities that can reveal stealthed enemies.
## The shape is tested against CollisionLayers.Mask.STEALTH each physics tick.
## Null for entities that have no detection capability.
@onready var detection_range: CollisionShape3D = get_node_or_null("DetectionRange")

@onready var vision_range_shape: CollisionShape3D = get_node_or_null("VisionRange")

## The Loadout node whose children are this entity's Weapon nodes.
## Null for entities that carry no weapons (structures without AttackRange,
## plain workers, etc.). All weapon queries go through this node.
@onready var weapon_inventory: Loadout = get_node_or_null("Loadout") as Loadout

## Selectable component — owns the per-entity "is selected" bit and joins the
## "selectables" group. Optional: present on units, structures, and any other
## entity the player can box-/click-select (e.g. ExtractionSite). Null for entities that
## are never selectable (projectile, star, hit_box). Callers gate on `!= null`.
@onready var selectable: Selectable = get_node_or_null("Selectable") as Selectable

## Child StaticBody3D carrying the targetable layer(s) — TARGETABLE_GROUND and/or
## TARGETABLE_AIR (plus STRUCTURE_BLOCKER for structures), set from components in
## _apply_targetable_layers(). The root CharacterBody3D stays off those layers so
## moving units never collide with building bodies; aggro / vision / projectile /
## AoE / line-of-fire queries hit this child. Resolve a hit collider back to the
## owning Entity with Entity.entity_from_collider(). Optional — null for entities
## with no targetable presence (star, hit_box).
@onready var hurtbox: StaticBody3D = get_node_or_null("Hurtbox") as StaticBody3D
#endregion

#region Properties
enum Attribute { MECH, BIO, UNMANNED }

@export var attributes_list: Array[Attribute] = []
var attributes: Set

var xz_position: Vector2:
	get:
		return VU.in_xz(global_position)
	set(value):
		global_position = VU.from_xz(value)

var map: Map
var pc_set: Set = Set.new()
@onready var collider: CollisionShape3D = _resolve_collider()
## The two aggro volumes: how far this piece will pick a fight with a GROUND target, and with
## an AIR one. Their shapes are DERIVED from reach (refresh_aggro_shapes), never authored; a
## null shape means no reach against that layer, so nothing there is ever picked up.
@onready var aggro_shape_ground: CollisionShape3D = get_node_or_null("AggroRangeGround")
@onready var aggro_shape_air: CollisionShape3D = get_node_or_null("AggroRangeAir")

## True while this entity is only PLANNED — a structure an issued Build order has
## claimed a site for, which no builder has laid down yet (the "blueprint"). It is a
## real node, owned, selectable and able to take train orders, but it is not physically
## on the map: no grid cells, no collision, no line of sight, no infrastructure, no tech
## contribution, and it is invisible to every commander but its owner. Placement
## (Actor.commit_construction) flips this off and turns all of that on.
##
## Set BEFORE the entity enters the tree (see Actor.plan_construction), because
## _ready and _on_commander_changed both consult it.
var is_planned: bool = false

## This piece's spawn serial: the number it took on first entering play, the same on every run
## of a seed — how a recorded order names it (Scenario.register_piece). 0 until then, and for
## good on anything that never enters play in a scenario (a build preview, a test fixture).
var spawn_serial: int = 0
#endregion

#region Targeting priority
## Aggro target-priority ranking (lower value = engaged first): armed things before
## unarmed, mobile units before structures. Aggro checks drop targets ranked worse than
## the issuing command's floor and sort the survivors by this. See
## `target_priority` and CommandMessage.target_priority.
enum TargetPriority {
	COMBAT_UNITS = 0,  ## non-structure entity that has weapons
	COMBAT_STRUCTURES = 1,  ## structure that has weapons
	NON_COMBAT_UNITS = 2,  ## non-structure entity with no weapons
	NON_COMBAT_STRUCTURES = 3,  ## structure with no weapons
}

## This entity's TargetPriority, derived from whether it currently occupies the terrain
## grid as a structure (structure_is_active) and whether it is armed (is_armed).
var target_priority: TargetPriority:
	get:
		var armed: bool = is_armed()
		if structure_is_active():
			return (
				TargetPriority.COMBAT_STRUCTURES if armed else TargetPriority.NON_COMBAT_STRUCTURES
			)
		return TargetPriority.COMBAT_UNITS if armed else TargetPriority.NON_COMBAT_UNITS


## Whether this entity can currently project weapon fire — by default, its own equipped
## weapons. Actor overrides this to ALSO count a bunker garrison that is actively
## holding armed occupants (whose fire the structure propagates), so it stays a method for
## that override rather than an inline check.
func is_armed() -> bool:
	return weapon_inventory != null and weapon_inventory.has_weapons()


## True iff this entity is a FIXTURE right now: it has a Structure component and that
## component is live (gdd/systems/authoring/piece-vocabulary.md §Facets). Callers that mean
## "is this a fixture now" ask this; callers that need the footprint's dimensions — a piece
## that WILL be one, such as a build preview — read the node itself. Resolved inline rather
## than via @onready so it answers for out-of-tree instances too.
func structure_is_active() -> bool:
	var structure := get_node_or_null("Fixture") as Fixture
	return structure != null and structure.is_active


## The Movement component if it is LIVE, else null. Resolved inline, unlike `movement`, so it
## answers for an instance outside the tree too — a build preview, a test fixture.
func live_movement() -> Movement:
	var locomotion := get_node_or_null("Locomotion") as Movement
	return locomotion if locomotion != null and locomotion.is_active else null


## Whether this piece can stand in BOTH forms — it carries a footprint and locomotion — and
## so is in exactly one of them at a time: a structure while deployed, a unit while mobile.
func has_two_forms() -> bool:
	return has_node("Fixture") and get_node_or_null("Locomotion") is Movement


## Whether a spawn site with no opinion of its own should register this piece on the grid.
## Only a fixture-only piece: a two-form piece that nobody asked to deploy spawns MOBILE, the
## form with no registration to reconcile (composition-rework §Which form a piece spawns in).
func spawns_deployed() -> bool:
	return has_node("Fixture") and not has_node("Locomotion")


## Deploy a mobile two-form piece onto the footprint centred on `a_world_center`. Refused —
## false, nothing changed — unless that footprint passes the same placement check a build
## order does: the deployed form is only ever entered through a validated footprint.
func deploy(a_world_center: Vector2) -> bool:
	var structure := get_node_or_null("Fixture") as Fixture
	if not has_two_forms() or structure.is_active or map == null:
		return false
	var message := CommandMessage.new(map, null, null, VU.from_xz(a_world_center))
	if not Fixture.valid_placement(
		message, structure.dimensions, structure.allow_uneven, structure.allow_submerged
	):
		return false
	map.add_structure(self, a_world_center)
	return true


## Take a deployed two-form piece off the grid and back to its mobile form, giving its cells
## and navmesh hole back.
func undeploy() -> void:
	if not has_two_forms() or not structure_is_active():
		return
	if map != null:
		map.remove_structure(self)
	set_deployed(false)


## Switch a two-form piece's form. Grid registration is NOT done here — deploy and a build
## order's Map.add_structure do that, and undeploy undoes it; this flips everything that
## FOLLOWS the form: which component is live, the unit/fixture/structure groups, the collision
## and target layers, and whatever an override of _on_form_changed keeps.
func set_deployed(a_deployed: bool) -> void:
	var structure := get_node_or_null("Fixture") as Fixture
	var locomotion := get_node_or_null("Locomotion") as Movement
	if structure == null or locomotion == null:
		return
	structure.is_active = a_deployed
	locomotion.set_active(not a_deployed, commander_id if ownership != null else 0)
	var mobile_groups: Array[String] = ["unit"]
	var standing_groups: Array[String] = ["fixture", "structure"]
	for group: String in mobile_groups if a_deployed else standing_groups:
		remove_from_group(group)
	for group: String in standing_groups if a_deployed else mobile_groups:
		add_to_group(group)
	refresh_movement_collision()
	_apply_targetable_layers()
	refresh_aggro_shapes()
	_on_form_changed(a_deployed)


## Whether this entity currently reveals fog for its owner. A PLANNED structure never does:
## ordering a build must not scout the site, and an ORBIT vision only while it holds its orbit
## (VisionRange.is_active). Actor narrows it further.
func grants_vision() -> bool:
	if vision_range_shape == null or vision_range_shape.shape == null or is_planned:
		return false
	return (
		not (vision_range_shape is VisionRange) or (vision_range_shape as VisionRange).is_active()
	)


#region Aggro
## The aggro volume that picks up `a_target`: the air one for a target on the air layer.
func aggro_shape_for(a_target: Entity) -> CollisionShape3D:
	return aggro_shape_air if a_target.is_air_target() else aggro_shape_ground


## The aggro volumes that currently hold a shape, ground first.
func aggro_shapes() -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	for node: CollisionShape3D in [aggro_shape_ground, aggro_shape_air]:
		if node != null and node.shape != null:
			out.append(node)
	return out


## The wider of the two aggro radii, or -1.0 when this piece picks no fights at all.
func aggro_radius() -> float:
	var best: float = -1.0
	for node: CollisionShape3D in aggro_shapes():
		best = maxf(best, RangeShapes.xz_radius(node))
	return best


## Enemy targetables within this piece's aggro, measured from its own footprint (see Hull):
## one pass per layer, each with that layer's own radius, so an anti-air reach never drags in
## a ground target. Allies and neutrals are excluded by the query's side mask, so they never
## use up `a_max_results`; vision is not, and stays the caller's to filter.
func hostiles_in_aggro(a_max_results: int = 32) -> Array[Entity]:
	var out: Array[Entity] = []
	var from: Hull = hull()
	var exclude: Array = [hurtbox.get_rid()] if hurtbox != null else []
	for pass_spec: Array in [
		[aggro_shape_ground, CollisionLayers.Mask.TARGETABLE_GROUND],
		[aggro_shape_air, CollisionLayers.Mask.TARGETABLE_AIR]
	]:
		var node: CollisionShape3D = pass_spec[0]
		if node == null or node.shape == null:
			continue
		for e: Entity in SU.entities_within(
			get_world_3d(),
			from,
			node.shape,
			global_position,
			CollisionLayers.hostile_mask(pass_spec[1], allied_commander_ids()),
			exclude,
			a_max_results
		):
			if not out.has(e):
				out.append(e)
	return out


## This piece's longest reach against one targetable layer (a CollisionLayers.Mask bit), in
## world units, or -1.0 when nothing it carries reaches that layer.
func reach_on_layer(a_layer: int) -> float:
	var best: float = -1.0
	if weapon_inventory != null:
		for w: Weapon in weapon_inventory.get_weapons():
			best = maxf(best, w.reach_on_layer(a_layer))
	return best


## Re-derive both aggro volumes from reach (RangeShapes.aggro_shape_for_reach). Called at
## _ready, on a form switch (the immobile cap depends on whether it can move), and by a
## bunker Garrison whenever its occupants change.
func refresh_aggro_shapes() -> void:
	var is_mobile: bool = can_move()
	if aggro_shape_ground != null:
		aggro_shape_ground.shape = RangeShapes.aggro_shape_for_reach(
			reach_on_layer(CollisionLayers.Mask.TARGETABLE_GROUND), is_mobile
		)
	if aggro_shape_air != null:
		aggro_shape_air.shape = RangeShapes.aggro_shape_for_reach(
			reach_on_layer(CollisionLayers.Mask.TARGETABLE_AIR), is_mobile
		)


#endregion


## Hook for what a subclass keeps in step with the form (Actor: its commander's
## structure registry). Runs after every set_deployed.
func _on_form_changed(_a_deployed: bool) -> void:
	pass


## Settle a two-form piece into the form its spawn chose: DEPLOYED if a validated footprint
## already registered it, MOBILE otherwise.
func _resolve_initial_form() -> void:
	if has_two_forms():
		set_deployed(is_on_grid())


## Whether this entity's body should stop a shot passing THROUGH it — the
## STRUCTURE_BLOCKER layer Attack's line-of-fire raycast queries.
##
## Only an OBSTRUCTION is cover: the fixtures that block the navmesh, never an occupant-only
## one a unit walks across. Why: gdd/systems/combat/target-acquisition.md §Line of fire.
##
## Cover is what a FINISHED building gives. A foundation is a site with materials on it: it
## occupies the grid, it can be shot, and units path around it, but there is nothing
## standing there yet for a bullet to hit. Actor overrides this to say so — a
## structure earns the layer on the tick it completes (see advance_build_progress), not on
## the tick it is placed.
func blocks_line_of_fire() -> bool:
	return structure_is_active() and has_obstructing_footprint()


#endregion


#region Spatial queries
## The entity's primary collision shape. Commandables name their movement shape
## "MovementBody"; other Entity scenes (radiation, star) use "Body". Prefer "Body"
## when present so scenes mid-rename keep working, falling back to "MovementBody".
func _resolve_collider() -> CollisionShape3D:
	var node := get_node_or_null("Body")
	if node == null:
		node = get_node_or_null("MovementBody")
	return node as CollisionShape3D


## Resolve a physics-query collider to its owning Entity. Because the targetable
## layers / STRUCTURE_BLOCKER now live on the child Hurtbox, query hits are that child
## — walk up to its Entity parent. Colliders that are themselves Entities (any
## other layer) pass straight through. Returns null for non-entity colliders.
static func entity_from_collider(node: Object) -> Entity:
	if node is Entity:
		return node as Entity
	if node is Node:
		return (node as Node).get_parent() as Entity
	return null


## Circumscribed radius of the collision shape on the physics object that
## participates in `layer`: the smallest circle (in XZ) that fully contains the
## shape. Use this for conservative packing/spacing (e.g. placing bodies so they
## can't overlap) where a single scalar is needed regardless of shape — for a
## box this is the half-diagonal, not a side, so the circle still encloses it.
func bounding_radius(a_layer: int) -> float:
	var shape := _collision_shape_for_layer(a_layer)
	if shape == null:
		push_error("%s has no collision shape on layer %d" % [name, a_layer])
		return -1.0
	if shape is SphereShape3D:
		return shape.radius
	if shape is CylinderShape3D:
		return shape.radius
	if shape is BoxShape3D:
		return Vector2(shape.size.x, shape.size.z).length() * 0.5
	push_error("unhandled collider type %s" % typeof(shape))
	return -1.0


## Where a steered weapon aims at this piece: the centre of its hurtbox (Hurtbox/HurtboxShape),
## which stands on the piece's base; the piece's origin when it has no hurtbox.
## → gdd/systems/combat/projectiles.md §A rocket aims at the hurtbox
func aim_point() -> Vector3:
	var node: CollisionShape3D = (
		hurtbox.get_node_or_null("HurtboxShape") as CollisionShape3D
		if hurtbox != null
		else null
	)
	return node.global_position if node != null and node.is_inside_tree() else global_position


## How far the top of this piece's hurtbox stands above the ground under it — where a rammer
## strikes it. Zero for a piece with no targetable shape.
func top_height() -> float:
	var node: CollisionShape3D = (
		hurtbox.get_node_or_null("HurtboxShape") as CollisionShape3D
		if hurtbox != null
		else null
	)
	if node == null or node.shape == null or not node.is_inside_tree():
		return 0.0
	var half: float = _half_height_of(node.shape) * node.global_transform.basis.y.length()
	var ground_y: float = global_position.y - height_offset()
	return maxf(node.global_position.y + half - ground_y, 0.0)


static func _half_height_of(shape: Shape3D) -> float:
	if shape is BoxShape3D:
		return (shape as BoxShape3D).size.y * 0.5
	if shape is CylinderShape3D:
		return (shape as CylinderShape3D).height * 0.5
	if shape is CapsuleShape3D:
		return (shape as CapsuleShape3D).height * 0.5
	if shape is SphereShape3D:
		return (shape as SphereShape3D).radius
	return 0.0


## This piece's footprint on the XZ plane, from its Hurtbox's shape: what every
## piece-to-piece range is measured from (see Hull). A piece with no targetable shape is
## measured as the point it stands on.
func hull() -> Hull:
	var node: CollisionShape3D = (
		hurtbox.get_node_or_null("HurtboxShape") as CollisionShape3D
		if hurtbox != null
		else null
	)
	if node == null or node.shape == null:
		return Hull.point(xz_position)
	# Out of the tree (a build preview) global_transform is unavailable; compose it instead.
	var xform: Transform3D = (
		node.global_transform
		if node.is_inside_tree()
		else global_transform * hurtbox.transform * node.transform
	)
	var at: Vector2 = VU.in_xz(xform.origin)
	var shape: Shape3D = node.shape
	if shape is BoxShape3D:
		var size: Vector3 = (shape as BoxShape3D).size
		return Hull.rect(
			at,
			Vector2(size.x * xform.basis.x.length(), size.z * xform.basis.z.length()) * 0.5,
			VU.in_xz(xform.basis.x),
			VU.in_xz(xform.basis.z)
		)
	var round_radius: float = RangeShapes.radius_of(shape)
	if shape is CapsuleShape3D:
		round_radius = (shape as CapsuleShape3D).radius
	assert(
		round_radius >= 0.0, "%s: a target shape must be a box, cylinder, sphere or capsule" % name
	)
	return Hull.circle(at, round_radius * xform.basis.x.length())


## Resolve the CollisionShape3D's Shape3D for the physics object carrying
## `layer`. The CharacterBody3D's own Body shape carries the movement/targetable
## layers; otherwise we search child CollisionObject3D nodes (e.g. Area3D ranges).
func _collision_shape_for_layer(a_layer: int) -> Shape3D:
	if (collision_layer & a_layer) != 0:
		# `collider` is @onready, so it's still null on a freshly instantiated
		# instance that hasn't entered the tree yet (e.g. spawned units measured
		# for spacing before placement). _resolve_collider() uses get_node_or_null,
		# which works out-of-tree, so resolve on demand when the cached var is null.
		var shape_node := collider if collider != null else _resolve_collider()
		if shape_node != null:
			return shape_node.shape
	for child in get_children():
		if child is CollisionObject3D and (child.collision_layer & a_layer) != 0:
			for sub in child.get_children():
				if sub is CollisionShape3D:
					return sub.shape
	return null


## The root CharacterBody3D acts as a MOVEMENT_OBSTRUCTION only while the entity
## is NOT registered on the terrain grid. Registered fixtures are obstacles via the
## navmesh (or, if they do not obstruct, walkable ground), so their root carries no collision layer
## — which is
## what stops moving units from running into building corners. Re-run whenever
## grid registration changes (initialize / Map.add_structure / remove_structure).
func refresh_movement_collision() -> void:
	# Preserve the STEALTH bit, which the Stealth component toggles on the root
	# independently of grid registration.
	collision_layer &= CollisionLayers.Mask.STEALTH
	collision_mask = 0
	# A planned structure isn't there yet: units walk through where it will stand, so it
	# takes neither MOVEMENT_OBSTRUCTION nor (via _apply_targetable_layers) any targetable
	# layer. Only its Selectable area stays live, which is what lets the player click it.
	if is_planned:
		return
	if not is_on_grid():
		collision_layer |= CollisionLayers.Mask.MOVEMENT_OBSTRUCTION


## True when this entity is registered on the terrain grid — a placed fixture, an extractor
## overlaying its site included. Units and unplaced entities never are.
func is_on_grid() -> bool:
	return map != null and map.structure_cell_map.has(self)


## True when this entity is on the grid AND its cells leave the navmesh. An occupant-only
## fixture (`Fixture.is_obstruction` false) is on the grid without obstructing.
func is_grid_obstruction() -> bool:
	return is_on_grid() and has_obstructing_footprint()


## True when this piece's footprint, once placed, takes its cells out of the navmesh — an
## OBSTRUCTION rather than an occupant-only fixture. Read from the piece itself rather than
## its grid registration, so it holds before placement too.
func has_obstructing_footprint() -> bool:
	var structure := get_node_or_null("Fixture") as Fixture
	return structure == null or structure.is_obstruction


## Whether this entity is high enough off the ground to be an AIR target — THE definition of
## "airborne" for targeting, and the only one. ALTITUDE, not locomotion mode: an AERIAL unit
## can be on the ground and a GROUNDED one can be in the air.
##
## Distinct from `is_airborne()`, a FLIGHT-STATE question that governs what a piece may DO.
## False for anything that neither flies nor falls — a structure is a ground target by being a
## structure. Why, and what asking the mode cost:
## gdd/systems/combat/target-acquisition.md §One definition of "airborne".
func is_air_target() -> bool:
	return height_offset() >= Aerial.AIR_TARGET_ALTITUDE


## How far above the terrain under it this piece is, in world units: an aircraft's height, a
## soldier's still to fall under a canopy, and 0 for anything standing on the ground.
func height_offset() -> float:
	if aerial != null:
		return aerial.height_offset()
	return movement.descent_altitude() if movement != null else 0.0


## The air/ground answer the Hurtbox's current layers were written for. Compared once a
## tick (see refresh_targetable_altitude) so the layer is rewritten only when the piece
## actually crosses the threshold, rather than every frame it spends in the air.
var _targetable_as_air: bool = false


## Re-file this entity on the AIR or GROUND layer if its altitude has crossed the threshold
## since the layers were last written. Called every tick by Actor, where the same
## height is already being applied to the body — so this costs one float comparison, and a
## property write only on the tick the answer flips.
func refresh_targetable_altitude() -> void:
	if hurtbox == null or movement == null or is_planned:
		return
	if is_air_target() != _targetable_as_air:
		_apply_targetable_layers()


## Set the Hurtbox's targetable collision layers from this entity's components —
## the single place that decides what a weapon can lock onto:
##   - a structure (has a Structure component) is a ground target, and once it is
##     FINISHED it also blocks line-of-fire, so it carries STRUCTURE_BLOCKER too
##     (see blocks_line_of_fire — a foundation is shootable but is not cover);
##   - a unit (has a Movement component) is an air target when it is flying HIGH ENOUGH
##     (see is_air_target), otherwise a ground target;
##   - an entity with neither component exposes no targetable layer (not attackable);
##   - whatever it exposes, it also carries its owner's side bit (CollisionLayers.side_bits).
func _apply_targetable_layers() -> void:
	if hurtbox == null:
		return
	# Clear the bits we own here, then recompute, leaving any unrelated bits intact.
	var layers: int = (
		hurtbox.collision_layer
		& ~(
			CollisionLayers.TARGETABLE_ANY
			| CollisionLayers.all_side_bits(CollisionLayers.TARGETABLE_ANY)
			| CollisionLayers.Mask.STRUCTURE_BLOCKER
		)
	)
	# A planned structure exposes nothing to shoot at or fire through — it isn't there. Nor
	# does a charge riding on another piece: shooting at it is shooting at its carrier.
	if is_planned or PlantedCharge.is_riding(self):
		hurtbox.collision_layer = layers
		return
	_targetable_as_air = is_air_target()
	if structure_is_active():
		layers |= CollisionLayers.Mask.TARGETABLE_GROUND
		if blocks_line_of_fire():
			layers |= CollisionLayers.Mask.STRUCTURE_BLOCKER
	# Any other piece that can be hurt stands in the world to be shot — a unit whose locomotion
	# is dormant (a deployed one), and an immobile token (a planted charge), as well as a mover.
	elif movement_component != null or defense != null:
		layers |= (
			CollisionLayers.Mask.TARGETABLE_AIR
			if _targetable_as_air
			else CollisionLayers.Mask.TARGETABLE_GROUND
		)
	# The side bit is what lets an aggro query skip allies (CollisionLayers.hostile_mask); it
	# follows the owner, which is why a capture re-applies these layers.
	layers |= CollisionLayers.side_bits(layers & CollisionLayers.TARGETABLE_ANY, commander_id)
	hurtbox.collision_layer = layers


## The ATTACKABLE facet: a weapon can lock onto it and it can take damage
## (gdd/systems/authoring/piece-vocabulary.md §Facets). Deliberately says nothing about
## commandability — an uncommandable token with a Defense is as shootable as a unit.
func is_attackable() -> bool:
	return defense != null and targetable_layers() != 0


## Whether commander [a_viewer_commander_id] can currently perceive this entity: its fog
## pixel is clear for that commander AND it is not stealthed from them. Stealth hides a piece
## from the other side only: its owner and their allies see through it. Looks up the viewer's
## own Fog instance directly, so it is correct for bots reasoning about their own vision
## regardless of which commander is being spectated.
func is_visible_to(a_viewer_commander_id: int) -> bool:
	if (
		stealth != null
		and stealth.state == Stealth.State.STEALTHED
		and not is_on_side_of(a_viewer_commander_id)
	):
		return false
	var fog: Fog = Fog.for_commander(a_viewer_commander_id)
	if fog == null:
		return true
	return fog.fog_clear_at(VU.in_xz(global_position))


## The TARGETABLE_GROUND / TARGETABLE_AIR bits this entity currently exposes, or 0
## when it isn't targetable. A weapon may attack it iff its target_mask intersects
## these. Sourced from the Hurtbox configured by _apply_targetable_layers().
func targetable_layers() -> int:
	if hurtbox == null:
		return 0
	return hurtbox.collision_layer & CollisionLayers.TARGETABLE_ANY


## True when this entity is currently FLYING — it has an Aerial and is not mid-landing or
## temporarily grounded. False for a piece that does not fly, and for an aircraft in any
## landing state (LANDING / GROUNDED_TEMP / TAXIING / TAKING_OFF).
##
## NOT the targeting question — see is_air_target() for that. This one asks about an
## aircraft's flight state, so it is the right test for "may it shoot", "is it done with
## the runway", "can it be ordered to land". It cannot answer "is it an air target",
## because a parachuting soldier does not fly and a parked jet does.
func is_airborne() -> bool:
	return aerial != null and aerial.is_airborne()


#endregion


#region Lifecycle
func _ready() -> void:
	ownership.commander_changed.connect(_on_commander_changed)

	# The Hurtbox's shape is the scene's own: the importer fits it to the model, standing on
	# the piece's base (gdd/systems/ux/ui/generated-visual-defaults.md §The hurtbox).
	if hurtbox != null:
		_apply_targetable_layers()

	_resolve_initial_form()
	refresh_aggro_shapes()

	# Any entity with a VisionRange contributes line-of-sight, so it joins the "los"
	# group that fog.gd iterates to reveal fog — independent of "piece". This is
	# what lets a non-Actor recon entity (e.g. Scout) clear fog for its owner.
	# A merely PLANNED structure grants none: ordering a build must not scout the site.
	# commit_construction adds it to the group when the structure is actually placed.
	if vision_range_shape != null and not is_planned:
		add_to_group("los")

	_take_spawn_serial()

	# Scene-placed entities (map == null) weren't spawned by the Scenario loader,
	# so we self-initialize from default_commander_id after all _ready() calls
	# have run (ensuring Scenario._ready() has already created the commanders).
	if map == null and not Engine.is_editor_hint():
		call_deferred(&"_auto_initialize")

	_validate()


## Number this piece on its first entry into a scenario. Only pieces are numbered: an emission
## is never named by an order.
func _take_spawn_serial() -> void:
	if spawn_serial != 0 or not is_in_group("piece") or Engine.is_editor_hint():
		return
	var scenario: Scenario = Scenario.of(self)
	if scenario != null:
		spawn_serial = scenario.register_piece(self)


func _validate() -> void:
	# Abstract base scenes never enter the tree themselves, so an in-tree
	# unit/structure with an empty id is a piece missing its spec-doc identity.
	if id.is_empty() and (is_in_group("unit") or is_in_group("fixture")):
		push_warning(
			(
				"Entity '%s' has an empty id (scene: %s) — set it from the piece's gdd doc."
				% [name, scene_file_path if scene_file_path != "" else "<not from a scene file>"]
			)
		)


## Finds the Map and the Commander matching default_commander_id in the scene
## tree and calls initialize() on this entity. Only runs when map is still null
## (i.e. the entity was placed directly in the scene rather than spawned by
## the Scenario loader).
func _auto_initialize() -> void:
	# Out of the world by the time the deferred call lands (garrisoned on its first frame): there
	# is no tree to look the map up in.
	if map != null or not is_inside_tree():
		return
	# A GUT run has no current_scene — tests instantiate entities directly rather than
	# opening a scene — and calling find_child on that null is an error, not a miss.
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var found_map := scene_root.find_child("Map", true, false) as Map
	if found_map == null:
		push_warning("%s: auto-init skipped — no Map node in scene" % name)
		return
	var found_commander: Commander = null
	for node in scene_root.find_children("*", "", true, false):
		if node is Commander and (node as Commander).id == default_commander_id:
			found_commander = node
			break
	if found_commander == null:
		push_warning(
			"%s: auto-init skipped — no Commander with id=%d" % [name, default_commander_id]
		)
		return
	# Capture position before initialize(), which reparents via _on_commander_changed.
	var pre_init_pos := global_position
	initialize(found_map, found_commander)
	# Grid registration: editor-placed structures aren't spawned through
	# map.add_entity(), so add_structure() has never been called for them.
	# pre_init_pos is the visual centre; add_structure resolves the footprint from it
	# via Map.footprint_origin — identical to the editor terrain-snap plugin, so an
	# even-sized structure registers on the same cells it snapped to (no load shift).
	# A scene-placed piece is turned in the editor by yawing its root; the grid can only hold a
	# quarter turn, so the authored yaw is read as the nearest one (and the piece squared up to it).
	if spawns_deployed() and not found_map.structure_cell_map.has(self):
		found_map.add_structure(
			self, VU.in_xz(pre_init_pos), Fixture.quarter_turns_of_yaw(rotation.y), false
		)


func _on_commander_changed(_a_old_commander: Commander, a_new_commander: Commander) -> void:
	_apply_team_tint()
	_apply_targetable_layers()
	# Keep the scene tree organised: entities live as children of their commander.
	# Reparent only when already in the tree; add_child in initialize() covers
	# the not-yet-in-tree case.
	if a_new_commander != null and is_inside_tree() and get_parent() != a_new_commander:
		reparent(a_new_commander, true)


## This entity's owning team's colour. Resolves the Ownership node DIRECTLY (rather than
## via the @onready `ownership` shim) so it also works on out-of-tree instances — e.g.
## the commander-owned build-placement previews, whose @onready members never resolve
## because they're never added to the SceneTree.
##
## Exposed rather than inlined into _apply_team_tint because other things are drawn in a
## commandable's colours without going through its model at all — AltitudeIndicator's
## ground marker, for one.
func team_color() -> Color:
	var own := get_node_or_null("Ownership") as Ownership
	return TEAM_COLOR_MAP.get(own.commander_id if own != null else 0, Color.WHITE)


func _apply_team_tint() -> void:
	# Previously this lived inline in the commander setter, which meant the setter had to
	# know about the entity's art. Now it's a separate concern driven by Ownership's
	# commander_changed signal, and MeshVisual owns everything below it.
	var mesh_visual := get_node_or_null("MeshVisual") as MeshVisual
	if mesh_visual != null:
		mesh_visual.set_team_color(team_color())


## Configure this entity as a commander-owned visual preview (the build
## placement "ghost") without the full initialize() / tree-entry path: assign
## ownership and apply the team tint, but skip map registration, physics, group
## activation and reparenting. Safe to call on an instance that is never added
## to the SceneTree (so its @onready members never resolve).
func configure_preview_ownership(a_commander: Commander) -> void:
	var own := get_node_or_null("Ownership") as Ownership
	if own != null:
		own.commander = a_commander
	_apply_team_tint()


func initialize(a_map: Map, a_commander: Commander):
	map = a_map

	# Add to the tree FIRST (standard dynamic-spawn path: trained units, built
	# structures, projectiles). Entering the tree resolves the @onready
	# `ownership` node, which the `commander` setter below delegates through —
	# assigning before add_child would dereference a null ownership and crash.
	# Already-in-tree entities (auto-initialize from scene placement) skip this;
	# _on_commander_changed handles their reparenting via the signal.
	if not is_inside_tree():
		a_commander.add_child(self)

	# Always honor the commander handed to us. The previous `default_commander_id
	# > 0` gate dropped it for every dynamically-spawned entity (those default to
	# 0), leaving Ownership._commander null — which crashes anything reading
	# commander_id (e.g. fog.gd each physics frame). Scene-placed entities get
	# their commander from Scenario._ready directly, so this doesn't disturb them.
	commander = a_commander

	# Default movement-collision state: units (and not-yet-placed structures) act
	# as MOVEMENT_OBSTRUCTION. Map.add_structure re-runs this once a structure is
	# registered, clearing the layer so units don't collide with it.
	refresh_movement_collision()


func receive_damage(a_damage: Damage, a_from: Actor = null) -> void:
	if defense == null:
		return
	var was_alive: bool = defense.hp > 0
	var final_amount: float = defense.take_damage(a_damage.amount, a_damage.type)
	var was_lethal: bool = was_alive and defense.hp <= 0
	if a_from != null and a_from.veterancy != null:
		a_from.veterancy.gain_experience(roundi(final_amount * Veterancy.XP_PER_DAMAGE))
		a_from._fire_entity_occurrence(EntityOccurrence.ON_DEAL_DAMAGE)
	if was_lethal:
		_credit_kill(a_from)
	last_hit_by_commander_id = (
		a_from.commander_id if a_from != null and is_instance_valid(a_from) else -1
	)
	_fire_entity_occurrence(EntityOccurrence.ON_RECEIVE_DAMAGE)


## Kill this piece outright, credited to `a_from` exactly as a lethal hit would be — the
## killer's kill experience, its ON_KILL, the kill bounty — then die. For a death that is not
## damage: a flushed garrison's occupants (Garrison.flush), who die out of the world.
func kill(a_from: Actor = null) -> void:
	if defense != null:
		if defense.hp <= 0:
			return
		defense.apply_damage(defense.hp)
	_credit_kill(a_from)
	_on_death()


## What `a_from` earns for killing this piece: experience for the kill, its ON_KILL, and the
## kill bounty. Nothing for an unattributed death.
func _credit_kill(a_from: Actor) -> void:
	if a_from != null and is_instance_valid(a_from) and a_from.veterancy != null:
		a_from.veterancy.gain_experience(roundi(defense.hp_max * Veterancy.XP_PER_KILL_HP))
		a_from._fire_entity_occurrence(EntityOccurrence.ON_KILL)
	_pay_kill_bounty(a_from)


## Pay the killer's standing kill bounty (the Anarchists' Scavenge passive) for
## destroying THIS entity. A no-op for every commander that has not unlocked one, which
## is the normal case — kill_bounty_for short-circuits on a zero rate.
##
## Here rather than in _on_death because this is the one place the KILLER is known: a
## death handler sees only the corpse, and the bounty is owed to whoever caused it. The
## cost of that is what it cannot pay for — a unit that starves, is scuttled, or dies to
## an unattributed effect pays nobody, which is right: those are not kills.
##
## Enemies only, so friendly fire and scuttling your own losses can never fund you.
func _pay_kill_bounty(a_from: Actor) -> void:
	if a_from == null or not is_instance_valid(a_from) or a_from.commander == null:
		return
	if not a_from.is_enemy_of(self):
		return
	var bounty: int = a_from.commander.kill_bounty_for(id)
	if bounty > 0:
		a_from.commander.add_energy(bounty)


## Leave play because a Lifespan ran out — not a death, so no death reaction, bounty or
## death sound. Anything that must hear it go listens for the free itself — a Beacon
## component signals its spotter as its host is freed.
func expire() -> void:
	queue_free()


## Leave play by dying — the death reaction, sound and teardown. What a component calls when the
## piece it belongs to is finished (an emission whose last phase has ended).
func die() -> void:
	_on_death()


func _on_death() -> void:
	# Fire the death reaction FIRST, while map / global_position / commander are
	# still valid (the teardown + queue_free below would invalidate them). This is
	# the single death chokepoint: Actor._on_death reaches it via super()
	# after its commander bookkeeping, which leaves those references intact.
	_fire_entity_occurrence(EntityOccurrence.ON_DEATH)
	# The main loop rather than get_tree(): a piece may die out of the world (a flushed
	# occupant) and is still heard.
	EntityDeathSounds.play_for(id, Engine.get_main_loop() as SceneTree)

	# Structure-flavored grid teardown: any entity that occupies the terrain grid
	# (registered via Structure → Map.add_structure) must release its cells so the
	# navmesh reopens them. Actor._on_death adds commander/economy teardown
	# on top of this via super(). Gated on group + map so plain units skip it.
	if is_in_group("fixture") and map != null:
		map.remove_structure(self)

	for coords: Vector2i in pc_set.get_values():
		map.spatial_partition_grid[coords.x][coords.y].remove(self)

	queue_free()


#endregion


#region Lifecycle occurrence dispatch
## Announce that `occurrence` happened on this entity: emit the entity_occurrence signal,
## report it to the manager's bus, and fire the matching child EntityTrigger (if any).
## Safe to call even when the scene has no ScenarioTriggerManager (the signal still fires;
## reactions are skipped).
func _fire_entity_occurrence(a_occurrence: EntityOccurrence) -> void:
	entity_occurrence.emit(a_occurrence, self)
	var manager := _resolve_trigger_manager()
	if manager == null:
		return
	# Report to the manager's bus regardless of whether THIS entity has a reaction —
	# cumulative conditions (ConditionOccurrenceTally) need to see every occurrence.
	manager.report_entity_occurrence(a_occurrence, self)
	var trigger := _trigger_for(a_occurrence)
	if trigger != null:
		trigger.fire(manager, self)


## The child EntityTrigger to fire for `occurrence`: the first matching one. Null when no
## trigger matches. EntityTriggers live under the "#####TRIGGERS#####" organizational
## header (see commandable.tscn) when present, else directly under this entity.
func _trigger_for(a_occurrence: EntityOccurrence) -> EntityTrigger:
	for child in _triggers_root().get_children():
		var trigger := child as EntityTrigger
		if trigger == null:
			continue
		if trigger.occurrence != a_occurrence:
			continue
		return trigger
	return null


## The node whose children are this entity's EntityTriggers: the "#####TRIGGERS#####"
## header node if it exists, otherwise the entity itself.
func _triggers_root() -> Node:
	for child in get_children():
		if child.name == "#####TRIGGERS#####":  # TODO refactor - the agent did this too literally
			return child
	return self


## Lazily resolve (and cache) the scene's ScenarioTriggerManager. Returns null when
## the current scene has none (reactions are then skipped; the signal still fires).
func _resolve_trigger_manager() -> ScenarioTriggerManager:
	if _trigger_manager != null and is_instance_valid(_trigger_manager):
		return _trigger_manager
	# The main loop rather than get_tree(), so a piece out of the world (a garrison occupant)
	# still reports what happens to it — a flushed occupant's death counts toward objectives.
	var tree := Engine.get_main_loop() as SceneTree
	var scene_root: Node = tree.current_scene if tree != null else null
	if scene_root != null:
		_trigger_manager = (
			scene_root.get_node_or_null("ScenarioTriggerManager") as ScenarioTriggerManager
		)
	return _trigger_manager
#endregion
