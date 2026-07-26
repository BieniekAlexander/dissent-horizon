class_name Builds
extends Node

## Declares which structure Entity.Types this unit is allowed to build.
## Add as a child of any Commandable that should have build capability;
## populate buildable_types in the inspector or scene file.

@export var buildable_types: Array[StringName] = []

func _ready() -> void:
	assert(not buildable_types.is_empty(),
		"%s: Builds component has no buildable_types listed" % get_parent().name)

## Returns true when this unit can place the structure of the given type.
func can_build(structure_type: StringName) -> bool:
	return buildable_types.has(structure_type)
