class_name Tool

#region Properties
var type: Variant
var packed_scene: PackedScene
#endregion

#region Lifecycle
func _init(
	a_type: Variant,
	a_packed_scene: PackedScene
) -> void:
	type = a_type
	packed_scene = a_packed_scene
#endregion

#region Registry
static var command_tool_map: Dictionary = {
	# Build tools (Technician → structures).
	"command_tool_outpost": Tool.new(Entity.Type.STRUCTURE_OUTPOST, load("res://scenes/structures/outpost.tscn")),
	"command_tool_dwelling": Tool.new(Entity.Type.STRUCTURE_DWELLING, load("res://scenes/structures/dwelling.tscn")),
	"command_tool_mine": Tool.new(Entity.Type.STRUCTURE_MINE, load("res://scenes/structures/mine.tscn")),
	"command_tool_lab": Tool.new(Entity.Type.STRUCTURE_LAB, load("res://scenes/structures/lab.tscn")),
	"command_tool_compound": Tool.new(Entity.Type.STRUCTURE_COMPOUND, load("res://scenes/structures/compound.tscn")),
	"command_tool_armory": Tool.new(Entity.Type.STRUCTURE_ARMORY, load("res://scenes/structures/armory.tscn")),
	"command_tool_turret": Tool.new(Entity.Type.STRUCTURE_TURRET, load("res://scenes/structures/turret.tscn")),
	# Train tools (structures → units).
	"command_tool_technician": Tool.new(Entity.Type.UNIT_TECHNICIAN, load("res://scenes/units/technician.tscn")),
	"command_tool_irregular": Tool.new(Entity.Type.UNIT_IRREGULAR, load("res://scenes/units/irregular.tscn")),
	"command_tool_vanguard": Tool.new(Entity.Type.UNIT_VANGUARD, load("res://scenes/units/vanguard.tscn")),
}
#endregion
