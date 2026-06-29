class_name Tool
extends ControlBinding

## A ControlBinding whose action is to build or train an entity: it adds the entity
## reference (type + packed_scene) and a specific faction over the base binding's
## command_name / label / grid_position / control_context.
##
## command_tool_map is the SINGLE SOURCE OF TRUTH for buildable/trainable things:
## to add one, add an entry here (plus its scene and the per-entity Builds/Production
## gate). Other systems read it through the typed lookups below:
##   - command_context_parser.gd   -> tools_in_context(context) (via tools_for)
##   - command_grid.gd             -> the registry feeds the grid alongside verbs
##   - build.gd / rts_controller.gd-> for_name(name) / ControlContext
##   - bot.gd / bot_actuator.gd / bot_economy.gd -> for_type(type)

#region Constants
## Which faction(s) a tool belongs to, as a bitmask (overrides ControlBinding's
## all-factions default via faction_mask()). 8 placeholder bits — names are
## arbitrary for now (first four mirror the Entity.Type prefixes NT_/TC_/AN_/CL_).
enum Faction {
	NEUTRAL     = 1 << 0,
	TECHNOCRACY = 1 << 1,
	ANARCHISTS  = 1 << 2,
	COLLECTIVE  = 1 << 3,
	FACTION_E   = 1 << 4,
	FACTION_F   = 1 << 5,
	FACTION_G   = 1 << 6,
	FACTION_H   = 1 << 7,
}
#endregion

#region Properties
## The Entity.Type this tool produces or places.
var type: Variant
var packed_scene: PackedScene
## Bitmask of Faction values; surfaced to the collision review via faction_mask().
var faction: int
#endregion

#region Lifecycle
func _init(
	a_command_name: String,
	a_type: Variant,
	a_packed_scene: PackedScene,
	a_label: String,
	a_grid_position: Vector2i,
	a_control_context: int,
	a_faction: int
) -> void:
	super(a_command_name, a_label, a_grid_position, a_control_context)
	type = a_type
	packed_scene = a_packed_scene
	faction = a_faction

func faction_mask() -> int:
	return faction
#endregion

#region Registry
## SINGLE SOURCE OF TRUTH (name -> Tool). Ordered (Godot dicts keep insertion
## order). Declared as a plain literal — NOT computed from another static var —
## because a static var that calls a method touching another static var sees it
## empty at init time; derived indexes below are built lazily on first use.
## _init args: command_name, type, scene, label, grid_position, control_context,
## faction.
static var command_tool_map: Dictionary = {
	# Build tools (Technician → structures): ControlContext.BUILD.
	"command_tool_dwelling": Tool.new("command_tool_dwelling", Entity.Type.TC_STRUCTURE_DWELLING, load("res://scenes/entities/structures/tc/dwelling.tscn"), "Dwelling", Vector2i(1, 0), ControlContext.BUILD, Faction.TECHNOCRACY),
	"command_tool_mine": Tool.new("command_tool_mine", Entity.Type.NT_STRUCTURE_MINE, load("res://scenes/entities/structures/nt/mine.tscn"), "Mine", Vector2i(2, 0), ControlContext.BUILD, Faction.NEUTRAL),
	"command_tool_stronghold": Tool.new("command_tool_stronghold", Entity.Type.AN_STRUCTURE_STRONGHOLD, load("res://scenes/entities/structures/an/stronghold.tscn"), "Redoubt", Vector2i(4, 0), ControlContext.BUILD, Faction.ANARCHISTS),
	"command_tool_lab": Tool.new("command_tool_lab", Entity.Type.TC_STRUCTURE_LAB, load("res://scenes/entities/structures/tc/lab.tscn"), "Lab", Vector2i(3, 0), ControlContext.BUILD, Faction.TECHNOCRACY),
	"command_tool_compound": Tool.new("command_tool_compound", Entity.Type.TC_STRUCTURE_COMPOUND, load("res://scenes/entities/structures/tc/compound.tscn"), "Compound", Vector2i(0, 1), ControlContext.BUILD, Faction.TECHNOCRACY),
	"command_tool_armory": Tool.new("command_tool_armory", Entity.Type.TC_STRUCTURE_ARMORY, load("res://scenes/entities/structures/tc/armory.tscn"), "Armory", Vector2i(1, 1), ControlContext.BUILD, Faction.TECHNOCRACY),
	"command_tool_hangar": Tool.new("command_tool_hangar", Entity.Type.AN_STRUCTURE_HANGAR, load("res://scenes/entities/structures/an/hangar.tscn"), "Hangar", Vector2i(4, 1), ControlContext.BUILD, Faction.ANARCHISTS),
	"command_tool_field_hospital": Tool.new("command_tool_field_hospital", Entity.Type.AN_STRUCTURE_FIELD_HOSPITAL, load("res://scenes/entities/structures/an/field_hospital.tscn"), "Field Hosp", Vector2i(4, 2), ControlContext.BUILD, Faction.ANARCHISTS),
	"command_tool_safehouse": Tool.new("command_tool_safehouse", Entity.Type.AN_STRUCTURE_SAFEHOUSE, load("res://scenes/entities/structures/an/safehouse.tscn"), "Safehouse", Vector2i(3, 2), ControlContext.BUILD, Faction.ANARCHISTS),
	"command_tool_settlement": Tool.new("command_tool_settlement", Entity.Type.CL_STRUCTURE_SETTLEMENT, load("res://scenes/entities/structures/cl/settlement.tscn"), "Settlement", Vector2i(0, 0), ControlContext.BUILD, Faction.COLLECTIVE),
	"command_tool_power_plant": Tool.new("command_tool_power_plant", Entity.Type.CL_STRUCTURE_POWER_PLANT, load("res://scenes/entities/structures/cl/power_plant.tscn"), "Power Plant", Vector2i(1, 0), ControlContext.BUILD, Faction.COLLECTIVE),
	"command_tool_barracks": Tool.new("command_tool_barracks", Entity.Type.CL_STRUCTURE_BARRACKS, load("res://scenes/entities/structures/cl/barracks.tscn"), "Barracks", Vector2i(2, 0), ControlContext.BUILD, Faction.COLLECTIVE),
	"command_tool_internment_camp": Tool.new("command_tool_internment_camp", Entity.Type.CL_STRUCTURE_INTERNMENT_CAMP, load("res://scenes/entities/structures/cl/internment_camp.tscn"), "Internment", Vector2i(3, 0), ControlContext.BUILD, Faction.COLLECTIVE),
	# Train tools (structures → units): ControlContext.TRAIN.
	"command_tool_technician": Tool.new("command_tool_technician", Entity.Type.TC_UNIT_TECHNICIAN, load("res://scenes/entities/units/an/technician.tscn"), "Techie", Vector2i(1, 2), ControlContext.TRAIN, Faction.ANARCHISTS),
	"command_tool_irregular": Tool.new("command_tool_irregular", Entity.Type.AN_UNIT_IRREGULAR, load("res://scenes/entities/units/an/irregular.tscn"), "Irregular", Vector2i(2, 2), ControlContext.TRAIN, Faction.ANARCHISTS),
	"command_tool_kamikaze": Tool.new("command_tool_kamikaze", Entity.Type.AN_UNIT_KAMIKAZE, load("res://scenes/entities/units/an/kamikaze.tscn"), "Kamikaze", Vector2i(0,0), ControlContext.TRAIN, Faction.ANARCHISTS),
	"command_tool_warlord": Tool.new("command_tool_warlord", Entity.Type.AN_UNIT_WARLORD, load("res://scenes/entities/units/an/warlord.tscn"), "Warlord", Vector2i(1, 2), ControlContext.TRAIN, Faction.ANARCHISTS),
	"command_tool_vanguard": Tool.new("command_tool_vanguard", Entity.Type.TC_UNIT_VANGUARD, load("res://scenes/entities/units/tc/vanguard.tscn"), "Vanguard", Vector2i(3, 2), ControlContext.TRAIN, Faction.TECHNOCRACY),
	"command_tool_stock_truck": Tool.new("command_tool_stock_truck", Entity.Type.CL_UNIT_STOCK_TRUCK, load("res://scenes/entities/units/cl/stock_truck.tscn"), "Stock Truck", Vector2i(0, 2), ControlContext.TRAIN, Faction.COLLECTIVE),
	"command_tool_recruit": Tool.new("command_tool_recruit", Entity.Type.CL_UNIT_RECRUIT, load("res://scenes/entities/units/cl/recruit.tscn"), "Recruit", Vector2i(1, 2), ControlContext.TRAIN, Faction.COLLECTIVE),
	"command_tool_badger": Tool.new("command_tool_badger", Entity.Type.CL_UNIT_BADGER, load("res://scenes/entities/units/cl/badger.tscn"), "Badger", Vector2i(2, 2), ControlContext.TRAIN, Faction.COLLECTIVE),
}

## Entity.Type -> Tool. Lazily built (see note above); cached after first use.
static var _by_type_cache: Dictionary = {}

static func _by_type() -> Dictionary:
	if _by_type_cache.is_empty():
		for t: Tool in command_tool_map.values():
			_by_type_cache[t.type] = t
	return _by_type_cache
#endregion

#region Lookups
## The Tool with this command name, or null.
static func for_name(a_command_name: String) -> Tool:
	return command_tool_map.get(a_command_name)

## The Tool that produces/places this Entity.Type, or null. Replaces the
## hand-rolled type→tool scans in bot.gd / bot_actuator.gd.
static func for_type(a_type: Variant) -> Tool:
	return _by_type().get(a_type)

## Tools (in registry order) whose control_context intersects the given context
## bitmask. The single context filter used by command_context_parser.tools_for().
static func tools_in_context(a_context: int) -> Array:
	var out: Array = []
	for t: Tool in command_tool_map.values():
		if (t.control_context & a_context) != 0:
			out.append(t)
	return out
#endregion
