class_name StructureSpec

#region Properties
var placement_checker: Callable
#endregion

#region Lifecycle
func _init(a_placement_checker: Callable) -> void:
	placement_checker = a_placement_checker
#endregion

#region Registry
static var structure_type_spec_map: Dictionary[int, StructureSpec] = {
	# NOTE: I tried to supply the Script as one of the fields of the StructureSpec, but Godot couldn't interpret it, so I'm just passing the placement checking function
	Entity.Type.UNDEFINED: StructureSpec.new(Commandable.valid_placement),
	Entity.Type.STRUCTURE_MINE: StructureSpec.new(Mine.valid_placement),
	Entity.Type.STRUCTURE_DWELLING: StructureSpec.new(Commandable.valid_placement),
	Entity.Type.STRUCTURE_OUTPOST: StructureSpec.new(Commandable.valid_placement),
	Entity.Type.STRUCTURE_LAB: StructureSpec.new(Commandable.valid_placement),
	Entity.Type.STRUCTURE_COMPOUND: StructureSpec.new(Commandable.valid_placement),
	Entity.Type.STRUCTURE_ARMORY: StructureSpec.new(Commandable.valid_placement),
	Entity.Type.STRUCTURE_TURRET: StructureSpec.new(Commandable.valid_placement),
	Entity.Type.STRUCTURE_DEPOSIT: StructureSpec.new(Commandable.valid_placement),
}
#endregion
