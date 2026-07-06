@tool
class_name Commander
extends Node

#region Properties

#region Identifiers
const NUM_MAX_COMMANDERS: int = 8
@export_range(0, NUM_MAX_COMMANDERS+1) var id: int
#endregion

#region Faction
## Scene defining this commander's Faction (e.g. anarchical.tscn). Instanced at
## ready into `faction`, which is the single source of truth for what this
## commander can deploy — its starting structure and available Ordnances.
@export var faction_scene: PackedScene

## The live Faction instance for this commander (child of this node). Null until
## ready, or if no faction_scene was assigned.
var faction: Faction = null

## This commander's per-match ordnance state, built from the faction's ordnance DAG:
## which ordnances are unlocked (dominion-gated) and their live cooldowns. Null when
## the commander has no faction.
var ordnance_arsenal: OrdnanceArsenal = null
#endregion

#region Controls
@onready var selection: Array[Commandable] = []
@onready var click_screen_pos: Vector2 = Vector2.ZERO
#endregion

#region Perception
## References resolved from the scene tree at _ready (Scenario/Players/<commander>),
## required by the fog-limited perception queries below and by the blackboard.
## May be injected explicitly via initialize() instead.
var map: Map
var scenario: Scenario

## Persistent, fog-limited belief about the enemy PLUS the visual memory of scouted
## structures (see CommanderBlackboard). Created at runtime for every non-neutral
## commander (player and bot alike) and ticked on a throttled cadence below. Null in
## the editor and for the neutral (id 0) commander.
var blackboard: CommanderBlackboard

## Physics ticks between belief updates (~5 Hz). The AI-only belief layer doesn't
## need to run every physics frame, and its visible_enemies() step runs expensive
## physics-space queries. The player-facing snapshot layer is NOT throttled — it
## runs every frame in blackboard.refresh_snapshots() (see _physics_process).
const BLACKBOARD_TICK_INTERVAL: int = 6
var _ticks_since_blackboard: int = 0
#endregion

#region Resources
## Starting ore/dominion are applied per-commander from its PlayerSlot (see
## Scenario); a commander built without a slot (the neutral world commander) keeps
## these zero defaults. NOT @onready — Scenario sets them before the commander enters
## the tree, and an @onready initializer would clobber that at _ready.
var ore: int = 0
var dominion: int = 0

## Vigor is the "power" resource: vigor-providing structures raise capacity
## (vigor_provided) and vigor-consuming structures raise upkeep (vigor_required).
## Every commander starts with a base 100 capacity; entities add/remove their
## contributions at runtime via adjust_vigor (see Commandable). When upkeep exceeds
## capacity the commander is "strained" — production runs at reduced speed.
const BASE_VIGOR: int = 100
var vigor_provided: int = BASE_VIGOR
var vigor_required: int = 0
## Spare capacity (capacity minus upkeep); negative when strained.
var vigor:
	get: return vigor_provided-vigor_required

## Emitted whenever any resource pool changes. Lets the HUD (and any other
## listener) update on change instead of polling every frame. All resource
## mutation goes through the mutators below so this fires consistently.
signal resources_changed

## Add `amount` ore (negative to spend). Single write-point for the ore pool.
func add_ore(amount: int) -> void:
	ore += amount
	resources_changed.emit()

## Add `amount` dominion (negative to spend). Single write-point for the dominion pool.
func add_dominion(amount: int) -> void:
	dominion += amount
	resources_changed.emit()

## Adjust the vigor accounting: `required_delta` changes upkeep consumed,
## `provided_delta` changes capacity. Either may be negative (e.g. when a provider
## or consumer is removed on death or ownership transfer).
func adjust_vigor(required_delta: int, provided_delta: int) -> void:
	vigor_required += required_delta
	vigor_provided += provided_delta
	resources_changed.emit()

## True when upkeep exceeds capacity. Production structures build at reduced speed
## while this holds (see Production.tick).
func is_vigor_strained() -> bool:
	return vigor_required > vigor_provided
#endregion

#endregion


#region Technology
# specifies what a commander can construct
var technology_mapping: Dictionary = {
	Entity.Type.TC_STRUCTURE_OUTPOST: TechnologySpec.new(500, 0, 0, 40*Engine.physics_ticks_per_second),
	# Redoubt: the unit-production building (trains warlords/irregulars). No
	# structure prerequisite — it's a primary base building like the outpost.
	Entity.Type.NT_STRUCTURE_MINE: TechnologySpec.new(200, 0, 0, 20*Engine.physics_ticks_per_second, []), # [Entity.Type.TC_STRUCTURE_OUTPOST, Entity.Type.TC_STRUCTURE_DWELLING]
	# AN (Anarchical)
	Entity.Type.AN_STRUCTURE_STRONGHOLD: TechnologySpec.new(400, 0, 0, 40*30, []),
	Entity.Type.AN_STRUCTURE_FIELD_HOSPITAL: TechnologySpec.new(250, 0, 0, 30*30),
	Entity.Type.AN_STRUCTURE_SAFEHOUSE: TechnologySpec.new(150, 0, 0, 20*30),
	Entity.Type.AN_STRUCTURE_HANGAR: TechnologySpec.new(500, 0, 0, 10*Engine.physics_ticks_per_second, [Entity.Type.AN_STRUCTURE_STRONGHOLD]),
	Entity.Type.AN_UNIT_WARLORD: TechnologySpec.new(250, 0, 0, 20*30),
	Entity.Type.AN_UNIT_IRREGULAR: TechnologySpec.new(75, 0, 0, 15*30),
	Entity.Type.AN_UNIT_KAMIKAZE: TechnologySpec.new(200, 0, 0, 25*30),
	Entity.Type.AN_UNIT_MERCURY: TechnologySpec.new(300, 0, 0, 25*30),
	# CL (Colonial)
	Entity.Type.CL_STRUCTURE_SETTLEMENT: TechnologySpec.new(400, 0, 0, 45*30),
	Entity.Type.CL_STRUCTURE_INTERNMENT_CAMP: TechnologySpec.new(300, 0, 0, 30*30),
	Entity.Type.CL_STRUCTURE_POWER_PLANT: TechnologySpec.new(200, 0, 0, 20*30, [Entity.Type.CL_STRUCTURE_INTERNMENT_CAMP]),
	Entity.Type.CL_STRUCTURE_BARRACKS: TechnologySpec.new(300, 0, 0, 30*30),
	Entity.Type.CL_UNIT_STOCK_TRUCK: TechnologySpec.new(600, 0, 0, 25*30),
	Entity.Type.CL_UNIT_RECRUIT: TechnologySpec.new(100, 0, 0, 20*30),
	Entity.Type.CL_UNIT_BADGER: TechnologySpec.new(200, 0, 0, 25*30),
	# TC (Technocratic)
	Entity.Type.TC_STRUCTURE_LAB: TechnologySpec.new(300, 0, 0, 40*30),
	Entity.Type.TC_STRUCTURE_DWELLING: TechnologySpec.new(150, 0, 0, 25*30),
	Entity.Type.TC_STRUCTURE_COMPOUND: TechnologySpec.new(300, 0, 0, 30*30),
	Entity.Type.TC_STRUCTURE_ARMORY: TechnologySpec.new(150, 0, 0, 30*30),
	Entity.Type.TC_UNIT_TECHNICIAN: TechnologySpec.new(100, 0, 0, 25*30),
	Entity.Type.TC_UNIT_VANGUARD: TechnologySpec.new(200, 0, 0, 20*30),
	# Abilities are gated here too. Ability.Type values (0,1,...) don't collide
	# with Entity.Type values (all >= 0x1100), so they coexist in this map.
	Ability.Type.RADIATION: TechnologySpec.new(0, 0, 0, 0),
}

## Per-commander map of Ability.Type -> payload PackedScene (a Projectile).
## Kept per-commander (not global) so technology upgrades can unlock or swap an
## ability's payload for one commander without affecting others, and can be
## mutated at runtime. Whether a unit may use an ability is decided by its
## Inventory (does it hold a ToolSpec?) plus the technology_mapping gate above;
## this map only answers "what does using it spawn?".
var ability_payload_registry: Dictionary = {
	Ability.Type.RADIATION: load("res://scenes/entities/projectiles/radiation.tscn"),
}

## True iff this commander owns at least one FINISHED (is_built) structure of the
## given Entity.Type. Single source of truth for "is this structure prereq met?",
## shared by proc_technology and ConditionStructureBuilt.
func has_built_structure(structure_type: int) -> bool:
	return structure_type_map[structure_type].get_values().any(
		func(s: Commandable): return s.is_built
	)

func get_unmet_need(a_type: Variant) -> TechnologySpec.UnmetNeed:
	var technology_spec: TechnologySpec = technology_mapping.get(a_type)
	if technology_spec == null:
		return TechnologySpec.UnmetNeed.MISSING_STRUCTURE
	return technology_spec.get_unmet_need(self)

func has_resources_for(a_type: Variant) -> bool:
	return get_unmet_need(a_type) == TechnologySpec.UnmetNeed.NONE

func use_resources_for(a_type: Variant) -> void:
	var technology_spec: TechnologySpec = technology_mapping.get(a_type)
	add_ore(-technology_spec.ore_cost)
	add_dominion(-technology_spec.dominion_cost)
	# Vigor is upkeep, not a one-time spend — it's adjusted when structures are
	# built/lost (see Commandable), not deducted per train.

## Refund the cost of `a_type` — the inverse of use_resources_for. Used when a queued
## training job is cancelled. A no-op for an unknown type. Vigor is upkeep (adjusted
## on build/loss), so nothing to refund there.
func refund_resources_for(a_type: Variant) -> void:
	var technology_spec: TechnologySpec = technology_mapping.get(a_type)
	if technology_spec == null:
		return
	add_ore(technology_spec.ore_cost)
	add_dominion(technology_spec.dominion_cost)

func proc_technology() -> void:
	# updates the tech tree of the commander according to changes in ownership.
	# A spec with no required_structures has all() return true → NONE.
	for tech: TechnologySpec in technology_mapping.values():
		tech.unmet_need = (
			TechnologySpec.UnmetNeed.NONE
			if tech.required_structures.all(func(t: int): return has_built_structure(t))
			else TechnologySpec.UnmetNeed.MISSING_STRUCTURE
		)
#endregion


#region Commandables

#region Structures
@onready var structure_type_map: Dictionary

func add_structure(a_structure: Commandable) -> void:
	structure_type_map[a_structure.type].add(a_structure)
	proc_technology()

func remove_structure(a_structure: Commandable) -> void:
	structure_type_map[a_structure.type].remove(a_structure)
	proc_technology()
#endregion

#endregion


#region Build previews
## Live, out-of-tree instances of each buildable structure, kept so the build
## "ghost" can reference a team-tinted version of the real building art. Keyed by
## Entity.Type. These are deliberately NOT added to the SceneTree (so their
## _ready / physics / fog / auto-init logic never runs and they're never
## registered as real structures); because they're orphaned, we free them
## explicitly on PREDELETE. Instantiating them through the Commander also means
## runtime changes to a building type (e.g. an upgraded sprite) flow through to
## the preview automatically.
var _build_preview_instances: Dictionary = {}

## Return (creating and caching on first use) a live, team-tinted instance of the
## structure for the given Tool, for use as a placement-preview source. The
## instance carries this commander's tint via configure_preview_ownership. Never
## added to the tree. Returns null if the tool has no packed scene.
func get_build_preview_instance(a_tool: Tool) -> Node:
	if a_tool == null or a_tool.packed_scene == null:
		return null
	var cached: Variant = _build_preview_instances.get(a_tool.type)
	if cached != null and is_instance_valid(cached):
		return cached
	var instance: Node = a_tool.packed_scene.instantiate()
	if instance is Entity:
		(instance as Entity).configure_preview_ownership(self)
	_build_preview_instances[a_tool.type] = instance
	return instance

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for inst in _build_preview_instances.values():
			if is_instance_valid(inst):
				inst.free()
		_build_preview_instances.clear()
		if blackboard != null:
			blackboard.free_visuals()
#endregion


#region Perception queries (fog-limited)
# Entity.initialize() calls commander.add_child(entity), so every owned entity is a
# direct child of this node. get_children() is therefore the authoritative source
# for owned-entity queries, and requires no scene-tree scan.
func _owned_commandables() -> Array:
	return get_children().filter(func(n): return n is Commandable)

## Owned entities that contribute VISION — any child carrying a VisionRange shape.
## Broader than _owned_commandables(): it also includes non-Commandable vision
## sources such as the Scout spawned by the Radar Scan ordnance. Geometric-vision
## queries (visible_enemies / has_vision_at, and through it visible_foreign_structures
## and the blackboard's snapshot/belief memory) iterate THIS set so they match the fog
## texture — fog.gd likewise reveals for any entity with a vision_range_shape, not just
## Commandables. Without this a Scout would poke a hole in the fog but never trigger the
## sight checks that record structure snapshots.
func _owned_vision_sources() -> Array:
	return get_children().filter(
		func(n): return n is Entity and (n as Entity).vision_range_shape != null
	)

# Gathers all commandables owned by an arbitrary list of commanders using the same
# child-based convention.
func _commandables_of(commanders: Array) -> Array:
	var result: Array = []
	for c: Commander in commanders:
		for child in c.get_children():
			if child is Commandable:
				result.append(child)
	return result

# Every Commander with id != 0 (neutral) and id != self.id is an enemy.
func _enemy_commanders() -> Array:
	if scenario == null:
		return []
	return scenario.commanders.filter(
		func(c: Commander): return c.id != id and c.id != 0
	)

## All enemy commandables within [radius] world units of [position]. An ENEMY is
## owned by a different, non-neutral commander (excluding neutral id 0 matches
## _enemy_commanders).
func get_enemies_near(position: Vector3, radius: float) -> Array:
	if map == null:
		return []
	return SU.get_nearby_entities(
		map.get_world_3d(), position, radius, CollisionLayers.TARGETABLE_ANY
	).filter(
		func(e): return e is Commandable and e.commander_id != id and e.commander_id != 0
	)

## Structures currently within this commander's vision that it does NOT own —
## INCLUDING neutral (id 0) ones (mines, mountains, Shelters, Deposits). Unlike
## visible_enemies(), this deliberately keeps neutral structures so the snapshot
## memory remembers them too. "Structure" means an entity carrying a Structure
## component (grid-occupying footprint) — NOT necessarily a Commandable: Shelters and
## Deposits derive from Entity, so gate on has_node("Structure"), not `is Commandable`.
## Uses the "structure" group + Fog.structure_in_vision (the SAME any-footprint-cell
## fog check fog.gd uses to reveal a structure), so it needs no targetable collision
## layer (neutral structures may not be on one), and a structure is deemed "seen"
## here on exactly the frames fog reveals it.
func visible_foreign_structures() -> Array:
	var result: Array = []
	var fog: Fog = _fog()
	for s in get_tree().get_nodes_in_group("structure"):
		# A structure is seen when ANY of its footprint cells is revealed (the same
		# any-cell rule fog.gd uses to show it) — not just the cell under its origin.
		if s.has_node("Structure") and s.commander_id != id \
				and (fog == null or fog.structure_in_vision(s)):
			result.append(s)
	return result

## Enemy commandables this commander can currently SEE: those within the VisionRange
## of any owned unit or structure. Deduplicated. This is the fog-of-war boundary for
## belief updates — it must not "cheat" by reading enemies the commander can't see.
func visible_enemies() -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	for owned: Entity in _owned_vision_sources():
		var vr: float = _shape_xz_radius(owned.vision_range_shape)
		if vr <= 0.0:
			continue
		for e in get_enemies_near(owned.global_position, vr):
			if not seen.has(e) and (e as Commandable).is_visible_to(id):
				seen[e] = true
				result.append(e)
	return result

## True when the fog pixel covering [world_pos] is currently revealed in this
## commander's fog — the SAME pixel-quantized disc fog.gd uses, NOT a geometric
## distance (which would disagree with the rasterized disc at the boundary). Used
## for point checks against a remembered structure location (belief aging, snapshot
## re-scout). For a live structure's own visibility use Fog.structure_in_vision,
## which tests its whole footprint. Returns true when this commander has no fog.
func has_vision_at(world_pos: Vector3) -> bool:
	var fog: Fog = _fog()
	if fog == null:
		return true
	return fog.fog_clear_at(VU.inXZ(world_pos))

## This commander's Fog of war. Bot Fogs are registered under their commander id,
## while the human player's Fog registers under -1 (its watching_commander_id
## default), so the player's id maps back to that key. Null for a commander with no
## Fog (the neutral/world owner, or no rig / editor).
func _fog() -> Fog:
	var key: int = -1 if id == RTSController.PLAYER_COMMANDER_ID else id
	return Fog._fogs_by_commander.get(key)

## World-space XZ radius of [entity]'s VisionRange — the SAME reveal radius the fog
## of war uses (fog.gd reads vision_range_shape identically). 0 when the entity has
## no vision shape.
func vision_radius(entity: Entity) -> float:
	return _shape_xz_radius(entity.vision_range_shape) if entity != null else 0.0

## XZ radius of a CollisionShape3D (cylinder/sphere radius × node X-scale), or 0.
func _shape_xz_radius(shape_node: CollisionShape3D) -> float:
	if shape_node == null:
		return 0.0
	var scale: float = shape_node.global_transform.basis.x.length()
	var shp: Shape3D = shape_node.shape
	if shp is CylinderShape3D:
		return (shp as CylinderShape3D).radius * scale
	if shp is SphereShape3D:
		return (shp as SphereShape3D).radius * scale
	return 0.0

## Seconds elapsed since the scenario started, derived from the physics frame
## counter (30 ticks per second).
func seconds_elapsed() -> float:
	if scenario == null:
		return 0.0
	return float(scenario.frame) / float(Engine.physics_ticks_per_second)
#endregion


#region Node
func _ready() -> void:
	for s in Entity.Type.values():
		structure_type_map[s] = Set.new()
	_instance_faction()
	# Drive the HUD resource label off resource changes rather than polling it
	# every frame (see resources_changed). Paint once now for the initial values.
	resources_changed.connect(_refresh_resource_label)
	_refresh_resource_label()

	# Runtime-only perception setup. Commander is @tool, so guard against the editor
	# (where there's no live Scenario to walk up to).
	if Engine.is_editor_hint():
		return
	_resolve_scene_references()
	# The neutral world commander (id 0) never views and has no strategic beliefs,
	# so it needs no blackboard or snapshots.
	if id != 0:
		blackboard = CommanderBlackboard.new(self)
	# Run this commander's _physics_process AFTER fog.gd's (default priority 0), so the
	# snapshot visibility swap reads each real structure's freshly-updated `visible`
	# this frame — making the memory the exact complement of what fog shows.
	process_physics_priority = 100

## Resolve [map] and [scenario] from the expected position Scenario/Players/<self>.
## Scenario._ready() places all commanders under a "Players" node that is a direct
## child of Scenario, so two get_parent() calls suffice. No-ops on already-set refs
## (e.g. injected via initialize()).
func _resolve_scene_references() -> void:
	var players := get_parent()
	if players != null and scenario == null:
		scenario = players.get_parent() as Scenario
	if scenario != null and map == null:
		map = scenario.map

## Explicit injection alternative to the tree-walk in _ready(), for when references
## must be wired before any _ready() callbacks fire.
func initialize(a_map: Map, a_scenario: Scenario) -> void:
	map = a_map
	scenario = a_scenario

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or blackboard == null or map == null:
		return
	# The player-facing snapshot layer (creation + visibility) runs EVERY frame
	# (cheap: a handful of structures, fog-pixel lookups only), so a remembered
	# structure appears the exact frame fog hides the real one — no gap or lag. It
	# reads each real structure's fog-driven `visible`, so it must run AFTER fog:
	# see process_physics_priority in _ready.
	blackboard.refresh_snapshots()
	# The AI-only belief refresh (visible_enemies physics queries + aging) is the
	# heavy, non-player-facing part, so it's throttled to ~5 Hz.
	_ticks_since_blackboard += 1
	if _ticks_since_blackboard < BLACKBOARD_TICK_INTERVAL:
		return
	_ticks_since_blackboard = 0
	blackboard.update()

## Instance this commander's faction_scene as a child and cache it in `faction`.
## Safe to call with no faction_scene assigned (faction stays null).
func _instance_faction() -> void:
	if faction_scene == null:
		return
	var instance: Node = faction_scene.instantiate()
	faction = instance as Faction
	add_child(instance)
	if faction != null:
		ordnance_arsenal = OrdnanceArsenal.new(self, faction.ordnance_unlocks)

## Repaint the HUD resource summary. Only the human-controlled commander carries
## the HUD rig (Controller + ResourceSummaryLabel), and it can now be any id — or
## none, in spectator mode. Gate on the node actually existing rather than a
## hardcoded id so bots (and the neutral commander) don't try to write a label
## they don't have.
func _refresh_resource_label() -> void:
	var label := get_node_or_null("Controller/ResourceSummaryLabel") as RichTextLabel
	if label == null:
		return
	label.text = (
		"\tore: %s\n\tvigor: %s/%s\n\tdominion: %s" % [
	 	ore,
		vigor_required, vigor_provided,
		dominion
	])
#endregion
