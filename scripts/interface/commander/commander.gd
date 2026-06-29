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
