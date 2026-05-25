class_name Tool

var type: Variant
var packed_scene: PackedScene

func _init(
	a_type: Variant,
	a_packed_scene: PackedScene
) -> void:
	type = a_type
	packed_scene = a_packed_scene

static var command_tool_map: Dictionary = {
	#"command_tool_outpost": Tool.new(Entity.Type.STRUCTURE_OUTPOST, preload("res://scenes/structures/outpost.tscn")),
	#"command_tool_dwelling": Tool.new(Entity.Type.STRUCTURE_DWELLING, preload("res://scenes/structures/dwelling.tscn")),
	#"command_tool_mine": Tool.new(Entity.Type.STRUCTURE_MINE, preload("res://scenes/structures/mine.tscn")),
	#"command_tool_lab": Tool.new(Entity.Type.STRUCTURE_LAB, preload("res://scenes/structures/lab.tscn")),
	#"command_tool_compound": Tool.new(Entity.Type.STRUCTURE_COMPOUND, preload("res://scenes/structures/compound.tscn")),
	#"command_tool_armory": Tool.new(Entity.Type.STRUCTURE_ARMORY, preload("res://scenes/structures/armory.tscn")),
	#"command_tool_technician": Tool.new(Entity.Type.UNIT_TECHNICIAN, preload("res://scenes/units/technician.tscn")),
	"command_tool_sentry": Tool.new(Entity.Type.UNIT_SENTRY, load("res://scenes/units/sentry.tscn")),
	"command_tool_vanguard": Tool.new(Entity.Type.UNIT_VANGUARD, load("res://scenes/units/vanguard.tscn")),
}
