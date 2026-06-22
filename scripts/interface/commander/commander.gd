@tool
class_name Commander
extends Node

#region Properties

#region Identifiers
const NUM_MAX_COMMANDERS: int = 8
@export_range(0, NUM_MAX_COMMANDERS+1) var id: int
#endregion

#region Controls
@onready var selection: Array[Commandable] = []
@onready var click_screen_pos: Vector2 = Vector2.ZERO
#endregion

#region Resources
@onready var ore: int = 1000
@onready var population_used: int = 0
@onready var population_max: int = 0
@onready var dominion: int = 0
var population:
	get: return population_max-population_used
#endregion

#endregion


#region Technology
# specifies what a commander can construct
var technology_mapping: Dictionary = {
	Entity.Type.TC_STRUCTURE_OUTPOST: TechnologySpec.new(500, 0, 0),
	# Redoubt: the unit-production building (trains warlords/irregulars). No
	# structure prerequisite — it's a primary base building like the outpost.
	Entity.Type.AN_STRUCTURE_REDOUBT: TechnologySpec.new(400, 0, 0),
	Entity.Type.NT_STRUCTURE_MINE: TechnologySpec.new(200, 0, 0), # [Entity.Type.TC_STRUCTURE_OUTPOST, Entity.Type.TC_STRUCTURE_DWELLING]
	Entity.Type.TC_STRUCTURE_LAB: TechnologySpec.new(300, 0, 0, [Entity.Type.NT_STRUCTURE_MINE]),
	Entity.Type.TC_STRUCTURE_DWELLING: TechnologySpec.new(150, 0, 0, [Entity.Type.TC_STRUCTURE_OUTPOST]),
	Entity.Type.TC_STRUCTURE_COMPOUND: TechnologySpec.new(300, 0, 0, [Entity.Type.TC_STRUCTURE_DWELLING]),
	Entity.Type.TC_STRUCTURE_ARMORY: TechnologySpec.new(150, 0, 0, [Entity.Type.TC_STRUCTURE_COMPOUND]),
	Entity.Type.AN_UNIT_TECHNICIAN: TechnologySpec.new(100, 0, 0),
	Entity.Type.AN_UNIT_WARLORD: TechnologySpec.new(250, 0, 0, [Entity.Type.AN_STRUCTURE_REDOUBT]),
	Entity.Type.AN_UNIT_IRREGULAR: TechnologySpec.new(75, 0, 0, [Entity.Type.AN_STRUCTURE_REDOUBT]),
	Entity.Type.TC_UNIT_VANGUARD: TechnologySpec.new(200, 0, 50, [Entity.Type.TC_STRUCTURE_COMPOUND]),
	# Abilities are gated here too. Ability.Type values (0,1,...) don't collide
	# with Entity.Type values (all >= 0x1100), so they coexist in this map.
	Ability.Type.RADIATION: TechnologySpec.new(0, 0, 0),
}

## Per-commander map of Ability.Type -> payload PackedScene (a Projectile).
## Kept per-commander (not global) so technology upgrades can unlock or swap an
## ability's payload for one commander without affecting others, and can be
## mutated at runtime. Whether a unit may use an ability is decided by its
## Inventory (does it hold a ToolSpec?) plus the technology_mapping gate above;
## this map only answers "what does using it spawn?".
var ability_payload_registry: Dictionary = {
	Ability.Type.RADIATION: load("res://scenes/projectiles/radiation.tscn"),
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
	ore -= technology_spec.ore_cost
	dominion -= technology_spec.dominion_cost
	# TODO population

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

func _process(delta: float) -> void:
	# Only the human-controlled commander carries the HUD rig (Controller +
	# ResourceSummaryLabel), and it can now be any id — or none, in spectator
	# mode. Gate on the node actually existing rather than a hardcoded id so bots
	# (and the neutral commander) don't try to write a label they don't have.
	var label := get_node_or_null("Controller/ResourceSummaryLabel") as RichTextLabel
	if label == null:
		return
	label.text = (
		"\tore: %s\n\tpopulation: %s\n\tdominion: %s" % [
	 	ore,
		("%s/%s" % [population_used, population_max]),
		dominion
	])

func _on_button_pressed() -> void:
	print("pressed me")
#endregion
