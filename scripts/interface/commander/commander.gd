@tool
class_name Commander
extends Node

### IDENTIFIERS
@export_range(0, 5) var id: int

### CONTROLS
@onready var selection: Array[Commandable] = []
@onready var click_screen_pos: Vector2 = Vector2.ZERO

### RESOURCES
@onready var ore: int = 500
@onready var population_used: int = 0
@onready var population_max: int = 0
@onready var dominion: int = 0
var population:
	get: return population_max-population_used

### TECHNOLOGY
# specifies what a commander can construct
var technology_mapping: Dictionary = {
	Entity.Type.STRUCTURE_OUTPOST: TechnologySpec.new(500, 0, 0, true),
	Entity.Type.STRUCTURE_MINE: TechnologySpec.new(200, 0, 0, false, func(c: Commander): return not c.structure_type_map[Entity.Type.STRUCTURE_OUTPOST].is_empty()),
	Entity.Type.STRUCTURE_LAB: TechnologySpec.new(300, 0, 0, false, func(c: Commander): return not c.structure_type_map[Entity.Type.STRUCTURE_MINE].is_empty()),
	Entity.Type.STRUCTURE_DWELLING: TechnologySpec.new(150, 0, 0, false, func(c: Commander): return not c.structure_type_map[Entity.Type.STRUCTURE_OUTPOST].is_empty()),
	Entity.Type.STRUCTURE_COMPOUND: TechnologySpec.new(300, 0, 0, false, func(c: Commander): return not c.structure_type_map[Entity.Type.STRUCTURE_DWELLING].is_empty()),
	Entity.Type.STRUCTURE_ARMORY: TechnologySpec.new(150, 0, 0, false, func(c: Commander): return not c.structure_type_map[Entity.Type.STRUCTURE_COMPOUND].is_empty()),
	Entity.Type.UNIT_TECHNICIAN: TechnologySpec.new(100, 0, 0, true),
	Entity.Type.UNIT_SENTRY: TechnologySpec.new(150, 0, 0, false, func(c: Commander): return not c.structure_type_map[Entity.Type.STRUCTURE_COMPOUND].is_empty()),
	Entity.Type.UNIT_VANGUARD: TechnologySpec.new(200, 0, 50, false, func(c: Commander): return not c.structure_type_map[Entity.Type.STRUCTURE_COMPOUND].is_empty())
}

func has_resources_for(a_type: Variant) -> bool:
	var technology_spec: TechnologySpec = technology_mapping.get(a_type)
	return (
		technology_spec!=null
		and technology_spec.available
		and ore >= technology_spec.ore_cost
		and population >= technology_spec.population_cost
		and dominion >= technology_spec.dominion_cost
	)

func use_resources_for(a_type: Variant) -> void:
	var technology_spec: TechnologySpec = technology_mapping.get(a_type)
	ore -= technology_spec.ore_cost
	dominion -= technology_spec.dominion_cost
	# TODO population

func proc_technology() -> void:
	# updates the tech tree of the commander according to changes in ownership
	for tech: TechnologySpec in technology_mapping.values():
		tech.available = tech.availability_evaluator.call(self)

### COMMANDABLES
#### STRUCTURES
@onready var structure_type_map: Dictionary

func add_structure(a_structure: Commandable) -> void:
	structure_type_map[a_structure.type].add(a_structure)
	proc_technology()

func remove_structure(a_structure: Commandable) -> void:
	structure_type_map[a_structure.type].remove(a_structure)
	proc_technology()

#### UNITS
### NODE
func _ready() -> void:
	for s in Entity.Type.values():
		structure_type_map[s] = Set.new()

func _process(delta: float) -> void:
	if id!=1: return
	$Controller/ResourceSummaryLabel.text = (
		"\tore: %s\n\tpopulation: %s\n\tdominion: %s" % [
	 	ore,
		("%s/%s" % [population_used, population_max]),
		dominion
	])

func _on_button_pressed() -> void:
	print("pressed me")
