class_name StructureSpec

var placement_checker: Callable

## The size of the structure in tiles
var dimensions: Vector2

func _init(
	a_placement_checker: Callable,
	a_dimensions: Vector2i
) -> void:
	placement_checker = a_placement_checker
	dimensions = a_dimensions

static var structure_type_spec_map: Dictionary[int, StructureSpec] = {
	# NOTE: I tried to supply the Script as one of the fields of the StructureSpec, but Godot couldn't interpret it, so I'm just passing the placement checking function
	Entity.Type.UNDEFINED: StructureSpec.new(Commandable.valid_placement, Vector2i.ONE),
	Entity.Type.STRUCTURE_MINE: StructureSpec.new(Mine.valid_placement, Vector2i.ONE),
	Entity.Type.STRUCTURE_DWELLING: StructureSpec.new(Commandable.valid_placement, Vector2i.ONE),
	Entity.Type.STRUCTURE_OUTPOST: StructureSpec.new(Commandable.valid_placement, Vector2i.ONE*3),
	Entity.Type.STRUCTURE_LAB: StructureSpec.new(Commandable.valid_placement, Vector2i.ONE*2),
	Entity.Type.STRUCTURE_COMPOUND: StructureSpec.new(Commandable.valid_placement, Vector2i.ONE*2),
	Entity.Type.STRUCTURE_ARMORY: StructureSpec.new(Commandable.valid_placement, Vector2i.ONE*2)
}
