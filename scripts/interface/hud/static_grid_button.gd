class_name StaticGridButton
extends Button

@export var grid_index: Vector2i = Vector2i.ZERO


func _enter_tree() -> void:
	#size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	#size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pass
