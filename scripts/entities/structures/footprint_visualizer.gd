@tool
class_name FootprintVisualizer
extends Node3D

## Editor-only overlay that renders a semi-transparent flat rectangle showing
## exactly which terrain grid cells this structure occupies.
##
## Sizing: Map.CELL_SIZE * Structure dimensions for this structure type.
## Removed from the scene tree at runtime so it carries zero gameplay cost.

#region Lifecycle
func _ready() -> void:
	if not Engine.is_editor_hint():
		queue_free()
		return
	_rebuild()
#endregion

#region Private helpers
func _rebuild() -> void:
	for child in get_children():
		child.free()

	var entity := get_parent() as Entity
	if entity == null:
		return

	var obs: Structure = get_parent().find_child("Structure")
	var w: float = obs.dimensions.x * Map.CELL_SIZE
	var d: float = obs.dimensions.y * Map.CELL_SIZE

	var plane := PlaneMesh.new()
	plane.size = Vector2(w, d)

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.2, 0.5, 1.0, 0.35)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position.y = 0.05
	add_child(mi)
#endregion
