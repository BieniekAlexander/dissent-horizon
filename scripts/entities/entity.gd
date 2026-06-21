class_name Entity
extends CharacterBody3D

## Name of the organizational header node (see commandable.tscn) that EntityTrigger child
## nodes are grouped under in the scene tree.
const TRIGGERS_HEADER := "#####TRIGGERS#####"

#region Identity
# I need to enumerate because I can't peek into packed scenes
@export var type: Type

## Inspector shortcut: set the in-game commander index for this entity.
## Entities placed in the editor use this to auto-initialize at run time;
## entities spawned by the scenario ignore it (initialize() is called explicitly).
@export_range(0, 5) var default_commander_id: int = 0

enum Type {
	# 3 - Faction {0: generic, 1: tech, 2: anarch}
	# 2 - Type {0: entity, 1: unit, 2: structure}
	# 1 - Index
	# 0 - Index
	UNDEFINED=-1,
	STRUCTURE_REDOUBT=0x2200,
	STRUCTURE_OUTPOST=0x1200,
	STRUCTURE_DWELLING=0x1201,
	STRUCTURE_MINE=0x1202,
	STRUCTURE_LAB=0x1203,
	STRUCTURE_COMPOUND=0x1204,
	STRUCTURE_ARMORY=0x1205,
	STRUCTURE_TURRET=0x1206,
	STRUCTURE_DEPOSIT=0x1207,
	STRUCTURE_SHELTER=0x1208,
	UNIT_TECHNICIAN=0x1100,
	UNIT_IRREGULAR=0x1101,
	UNIT_VANGUARD=0x1102,
	UNIT_WARLORD=0x1103,
	H_CANNON=0x1209
}

const TEAM_COLOR_MAP: Dictionary = {
	0: Color.WHITE,
	1: Color(.2, 1, 1),
	2: Color(1, 1, .2),
	3: Color(.1, .6, .1),
	4: Color(1, .2, .2)
}
#endregion

#region Lifecycle occurrences
## Lifecycle moments that can happen to an entity — the "occurrence" (condition-side)
## inputs that an EntityTrigger reacts to, distinct from an Event (the world-update it
## fires). Selects which EntityTrigger reacts, and is the payload of the `entity_occurrence`
## signal. Currently only ON_DEATH and ON_RECEIVE_DAMAGE are wired (see _on_death /
## Commandable.receive_damage); the stealth occurrences are enumerated for future use
## (they'd emit from Stealth's state transitions).
enum EntityOccurrence {
	ON_DEATH = 0,
	ON_RECEIVE_DAMAGE = 1,
	ON_ENTER_STEALTH = 2,
	ON_EXIT_STEALTH = 3
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
#endregion

#region Identity
## Ownership component — owns the commander relationship. Resolved at _ready
## time (scene composition: see unit.tscn, structure.tscn). Entities without
## an Ownership child (e.g. star.tscn) fall back to the private _commander
## field below.
@onready var ownership: Ownership = $Ownership

var commander: Commander:
	get: return ownership.commander
	set(value):
		ownership.commander = value

var commander_id: int:
	get: return ownership.commander_id
#endregion

#region Components
## Defense component — owns hp, hp_max, and armor. Null for entities with no
## concept of HP (e.g. Projectile, HitBox).
@onready var defense: Defense = get_node_or_null("Defense") as Defense

## Movement component — wraps NavigationAgent3D for entities that pathfind.
## Null for entities that don't (structures, items). Callers must gate on
## `movement != null` before using it.
@onready var movement: Movement = get_node_or_null("Movement") as Movement

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

## The Inventory component holding this entity's ability ToolSpecs. Null for
## entities with no abilities. Distinct from `inventory` (carried items) below.
@onready var ability_inventory: Inventory = get_node_or_null("Inventory") as Inventory

## Selectable component — owns the per-entity "is selected" bit and joins the
## "selectables" group. Optional: present on units, structures, and any other
## entity the player can box-/click-select (e.g. Deposit). Null for entities that
## are never selectable (projectile, star, hit_box). Callers gate on `!= null`.
@onready var selectable: Selectable = get_node_or_null("Selectable") as Selectable

## Child StaticBody3D carrying the targetable layer(s) — TARGETABLE_GROUND and/or
## TARGETABLE_AIR (plus STRUCTURE_BLOCKER for structures), set from components in
## _apply_targetable_layers(). The root CharacterBody3D stays off those layers so
## moving units never collide with building bodies; aggro / vision / projectile /
## AoE / line-of-fire queries hit this child. Resolve a hit collider back to the
## owning Entity with Entity.entity_from_collider(). Optional — null for entities
## with no targetable presence (star, hit_box).
@onready var target_body: StaticBody3D = get_node_or_null("TargetBody") as StaticBody3D
#endregion

#region Properties
enum LocomotionMode { GROUNDED, FLYING }
enum Attribute { MECH, BIO, UNMANNED }

@export var attributes_list: Array[Attribute] = []
var attributes: Set

var xz_position: Vector2:
	get: return VU.inXZ(global_position)
	set(value): global_position = VU.fromXZ(value)

var map: Map
var pc_set: Set = Set.new()
@onready var collider: CollisionShape3D = _resolve_collider()
@onready var aggro_range_shape: CollisionShape3D = get_node_or_null("AggroRange")
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
## layers / STRUCTURE_BLOCKER now live on the child TargetBody, query hits are that child
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
func bounding_radius(layer: int) -> float:
	var shape := _collision_shape_for_layer(layer)
	if shape == null:
		push_error("%s has no collision shape on layer %d" % [name, layer])
		return -1.0
	if shape is SphereShape3D: return shape.radius
	if shape is CylinderShape3D: return shape.radius
	if shape is BoxShape3D: return Vector2(shape.size.x, shape.size.z).length() * 0.5
	push_error("unhandled collider type %s" % typeof(shape))
	return -1.0

## Distance (in XZ) from this entity's center to the boundary of its collision
## shape on `layer`, in the direction of `target_xz`. Unlike bounding_radius this
## is shape-appropriate: a box reports how far its edge actually extends toward
## the target (accounting for the body's Y rotation), so a square reads as a
## square rather than as its circumscribed circle. Use this for proximity /
## border-to-border comparisons.
func collision_extent_toward(target_xz: Vector2, layer: int) -> float:
	var shape := _collision_shape_for_layer(layer)
	if shape == null:
		push_error("%s has no collision shape on layer %d" % [name, layer])
		return -1.0
	if shape is SphereShape3D: return shape.radius
	if shape is CylinderShape3D: return shape.radius
	if shape is BoxShape3D:
		var dir := target_xz - xz_position
		if dir.is_zero_approx():
			return 0.0
		# Rotate the direction into the body's local frame (Y rotation only) so
		# we can treat the box as axis-aligned, then ray-cast to the box edge.
		var local_dir := dir.rotated(global_rotation.y).normalized()
		var half := Vector2(shape.size.x, shape.size.z) * 0.5
		var tx: float = half.x / absf(local_dir.x) if not is_zero_approx(local_dir.x) else INF
		var tz: float = half.y / absf(local_dir.y) if not is_zero_approx(local_dir.y) else INF
		return minf(tx, tz)
	push_error("unhandled collider type %s" % typeof(shape))
	return -1.0

## Resolve the CollisionShape3D's Shape3D for the physics object carrying
## `layer`. The CharacterBody3D's own Body shape carries the movement/targetable
## layers; otherwise we search child CollisionObject3D nodes (e.g. Area3D ranges).
func _collision_shape_for_layer(layer: int) -> Shape3D:
	if (collision_layer & layer) != 0:
		# `collider` is @onready, so it's still null on a freshly instantiated
		# instance that hasn't entered the tree yet (e.g. spawned units measured
		# for spacing before placement). _resolve_collider() uses get_node_or_null,
		# which works out-of-tree, so resolve on demand when the cached var is null.
		var shape_node := collider if collider != null else _resolve_collider()
		if shape_node != null:
			return shape_node.shape
	for child in get_children():
		if child is CollisionObject3D and (child.collision_layer & layer) != 0:
			for sub in child.get_children():
				if sub is CollisionShape3D:
					return sub.shape
	return null


## The root CharacterBody3D acts as a MOVEMENT_OBSTRUCTION only while the entity
## is NOT registered as a terrain-grid obstruction. Registered structures are
## obstacles via the navmesh, so their root carries no collision layer — which is
## what stops moving units from running into building corners. Re-run whenever
## grid registration changes (initialize / Map.add_structure / remove_structure).
func refresh_movement_collision() -> void:
	# Preserve the STEALTH bit, which the Stealth component toggles on the root
	# independently of grid registration.
	collision_layer &= CollisionLayers.Mask.STEALTH
	collision_mask = 0
	if not is_grid_obstruction():
		collision_layer |= CollisionLayers.Mask.MOVEMENT_OBSTRUCTION

## True when this entity currently occupies cells in the terrain grid (i.e. a
## placed structure). Units and unplaced entities are never grid obstructions.
func is_grid_obstruction() -> bool:
	return map != null and map.structure_cell_map.has(self)

## Set the TargetBody's targetable collision layers from this entity's components —
## the single place that decides what a weapon can lock onto:
##   - a structure (has a Structure component) is a ground target, and also blocks
##     line-of-fire, so it carries STRUCTURE_BLOCKER too;
##   - a unit (has a Movement component) is an air target when flying/hovering,
##     otherwise a ground target;
##   - an entity with neither component exposes no targetable layer (not attackable).
func _apply_targetable_layers() -> void:
	if target_body == null:
		return
	# Clear the bits we own here, then recompute, leaving any unrelated bits intact.
	var layers: int = target_body.collision_layer & ~(
		CollisionLayers.Mask.TARGETABLE_GROUND
		| CollisionLayers.Mask.TARGETABLE_AIR
		| CollisionLayers.Mask.STRUCTURE_BLOCKER
	)
	if has_node("Structure"):
		layers |= CollisionLayers.Mask.TARGETABLE_GROUND | CollisionLayers.Mask.STRUCTURE_BLOCKER
	elif movement != null:
		layers |= (
			CollisionLayers.Mask.TARGETABLE_AIR
			if movement.mode in [Movement.Mode.FLYING, Movement.Mode.HOVERING]
			else CollisionLayers.Mask.TARGETABLE_GROUND
		)
	target_body.collision_layer = layers

## The TARGETABLE_GROUND / TARGETABLE_AIR bits this entity currently exposes, or 0
## when it isn't targetable. A weapon may attack it iff its target_mask intersects
## these. Sourced from the TargetBody configured by _apply_targetable_layers().
func targetable_layers() -> int:
	if target_body == null:
		return 0
	return target_body.collision_layer & CollisionLayers.TARGETABLE_ANY
#endregion

#region Lifecycle
func _ready() -> void:
	ownership.commander_changed.connect(_on_commander_changed)

	# Mirror the root Body shape onto the TargetBody so targeting matches the
	# entity's footprint (mine/turret/compound override Body with a box). Entities
	# with no root collider (e.g. a Deposit, whose footprint lives only on the
	# TargetBody) keep their authored TargetBody shape.
	if target_body != null:
		if collider != null:
			(target_body.get_node("Shape") as CollisionShape3D).shape = collider.shape
		_apply_targetable_layers()

	# Scene-placed entities (map == null) weren't spawned by the Scenario loader,
	# so we self-initialize from default_commander_id after all _ready() calls
	# have run (ensuring Scenario._ready() has already created the commanders).
	if map == null and not Engine.is_editor_hint():
		call_deferred(&"_auto_initialize")

	_validate()

func _validate() -> void:
	if type == Entity.Type.UNDEFINED:
		push_error("Entity '%s' has an UNDEFINED type (scene: %s) — set its `type` in the scene." % [
			name, scene_file_path if scene_file_path != "" else "<not from a scene file>"
		])

## Finds the Map and the Commander matching default_commander_id in the scene
## tree and calls initialize() on this entity. Only runs when map is still null
## (i.e. the entity was placed directly in the scene rather than spawned by
## the Scenario loader).
func _auto_initialize() -> void:
	if map != null:
		return
	var scene_root := get_tree().current_scene
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
		push_warning("%s: auto-init skipped — no Commander with id=%d" % [name, default_commander_id])
		return
	# Capture position before initialize(), which reparents via _on_commander_changed.
	var pre_init_pos := global_position
	initialize(found_map, found_commander)
	# Grid registration: editor-placed structures aren't spawned through
	# map.add_entity(), so add_structure() has never been called for them.
	# pre_init_pos is the visual centre; add_structure resolves the footprint from it
	# via Map.footprint_origin — identical to the editor terrain-snap plugin, so an
	# even-sized structure registers on the same cells it snapped to (no load shift).
	var obstruction := get_node_or_null("Structure") as Structure
	if obstruction != null and not found_map.structure_cell_map.has(self):
		found_map.add_structure(self, VU.inXZ(pre_init_pos), 0, false)

func _on_commander_changed(_old_commander: Commander, new_commander: Commander) -> void:
	_apply_team_tint()
	# Keep the scene tree organised: entities live as children of their commander.
	# Reparent only when already in the tree; add_child in initialize() covers
	# the not-yet-in-tree case.
	if new_commander != null and is_inside_tree() and get_parent() != new_commander:
		reparent(new_commander, true)

func _apply_team_tint() -> void:
	# Previously this lived inline in the commander setter, which meant the
	# setter had to know about the Sprite child. Now it's a separate concern
	# driven by Ownership's commander_changed signal; a future SpriteVisual
	# component should own this logic entirely.
	#
	# Resolve the Ownership node directly (rather than via the @onready
	# `ownership` shim) so this also works on out-of-tree instances — e.g. the
	# commander-owned build-placement previews, whose @onready members never
	# resolve because they're never added to the SceneTree.
	var own := get_node_or_null("Ownership") as Ownership
	var id: int = own.commander_id if own != null else 0
	var sprite: Node = get_node_or_null("Sprite")
	if sprite != null and "modulate" in sprite:
		sprite.modulate = TEAM_COLOR_MAP.get(id, Color.WHITE)

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

func receive_damage(damage: Damage, from: Commandable = null) -> void:
	if defense == null:
		return
	var final_amount: float = DamageTable.calculate_damage(damage.amount, damage.type, self)
	var was_alive: bool = defense.hp > 0
	defense.hp -= final_amount
	if was_alive and defense.hp <= 0 and from != null and from.veterancy != null:
		from.veterancy.gain_experience(10)
	_fire_entity_occurrence(EntityOccurrence.ON_RECEIVE_DAMAGE)

func _on_death() -> void:
	# Fire the death reaction FIRST, while map / global_position / commander are
	# still valid (the teardown + queue_free below would invalidate them). This is
	# the single death chokepoint: Commandable._on_death reaches it via super()
	# after its commander bookkeeping, which leaves those references intact.
	_fire_entity_occurrence(EntityOccurrence.ON_DEATH)

	# Structure-flavored grid teardown: any entity that occupies the terrain grid
	# (registered via Structure → Map.add_structure) must release its cells so the
	# navmesh reopens them. Commandable._on_death adds commander/economy teardown
	# on top of this via super(). Gated on group + map so plain units skip it.
	if is_in_group("structure") and map != null:
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
func _fire_entity_occurrence(occurrence: EntityOccurrence) -> void:
	entity_occurrence.emit(occurrence, self)
	var manager := _resolve_trigger_manager()
	if manager == null:
		return
	# Report to the manager's bus regardless of whether THIS entity has a reaction —
	# cumulative conditions (ConditionOccurrenceTally) need to see every occurrence.
	manager.report_entity_occurrence(occurrence, self)
	var trigger := _trigger_for(occurrence)
	if trigger != null:
		trigger.fire(manager, self)

## The child EntityTrigger to fire for `occurrence`: the first matching one. Null when no
## trigger matches. EntityTriggers live under the "#####TRIGGERS#####" organizational
## header (see commandable.tscn) when present, else directly under this entity.
func _trigger_for(occurrence: EntityOccurrence) -> EntityTrigger:
	for child in _triggers_root().get_children():
		var trigger := child as EntityTrigger
		if trigger == null:
			continue
		if trigger.occurrence != occurrence:
			continue
		return trigger
	return null

## The node whose children are this entity's EntityTriggers: the "#####TRIGGERS#####"
## header node if it exists, otherwise the entity itself.
func _triggers_root() -> Node:
	for child in get_children():
		if child.name == TRIGGERS_HEADER:
			return child
	return self

## Lazily resolve (and cache) the scene's ScenarioTriggerManager. Returns null when
## the current scene has none (reactions are then skipped; the signal still fires).
func _resolve_trigger_manager() -> ScenarioTriggerManager:
	if _trigger_manager != null and is_instance_valid(_trigger_manager):
		return _trigger_manager
	var scene_root := get_tree().current_scene if is_inside_tree() else null
	if scene_root != null:
		_trigger_manager = scene_root.get_node_or_null("ScenarioTriggerManager") as ScenarioTriggerManager
	return _trigger_manager
#endregion
