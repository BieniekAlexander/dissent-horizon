class_name ShapeOutline
extends RefCounted

## Draws a collision volume as Godot's own wireframe of its shape, on the piece it belongs to —
## for the debug tuning editor, while a field sizing that volume is being edited
## (gdd/systems/ux/ui/debug-tuning.md §Where the editor is). Deliberately the engine's outline
## and not the range rings a player sees on the terrain: the editor is tuning the volume, and
## the rings are a derived drawing of it.

## The outline is a SIBLING of its volume, named after it, at the volume's transform: collision
## volumes are hidden nodes, and a child of one is never drawn.
const NAME_FORMAT: String = "%sTuningOutline"
## How tall a RANGE cylinder's outline is drawn. Range volumes are SHAPE_HEIGHT tall on purpose
## (RangeShapes), so their rims sit far above and below the ground and only the radius means
## anything; drawn at full height the circles are off-screen. The radius is drawn exactly.
const RANGE_OUTLINE_HEIGHT: float = 2.0
## Bright enough to read against terrain and fog alike.
const COLOR: Color = Color(1.0, 0.85, 0.2)


## Outline `a_volume`, replacing any outline it already carries. Nothing for a volume with no
## shape.
static func show_on(a_volume: CollisionShape3D) -> void:
	hide_on(a_volume)
	if a_volume == null or a_volume.shape == null:
		return
	var outline := MeshInstance3D.new()
	outline.name = NAME_FORMAT % a_volume.name
	outline.transform = a_volume.transform
	var cylinder: CylinderShape3D = a_volume.shape as CylinderShape3D
	if cylinder != null and cylinder.height >= RangeShapes.SHAPE_HEIGHT:
		outline.scale.y *= RANGE_OUTLINE_HEIGHT / cylinder.height
	outline.mesh = _edges_of(a_volume.shape.get_debug_mesh())
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.albedo_color = COLOR
	outline.material_override = material
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	a_volume.get_parent().add_child(outline)


static func hide_on(a_volume: CollisionShape3D) -> void:
	if a_volume == null or not is_instance_valid(a_volume) or a_volume.get_parent() == null:
		return
	var outline: Node = a_volume.get_parent().get_node_or_null(
		NodePath(NAME_FORMAT % a_volume.name)
	)
	if outline != null:
		outline.get_parent().remove_child(outline)
		outline.queue_free()


## Only the edges of a shape's debug mesh. Godot's debug mesh also carries the shape's filled
## faces, which drawn through everything (no depth test) would cover the screen.
static func _edges_of(a_debug: ArrayMesh) -> ArrayMesh:
	var edges := ArrayMesh.new()
	for i: int in a_debug.get_surface_count():
		if a_debug.surface_get_primitive_type(i) == Mesh.PRIMITIVE_LINES:
			edges.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, a_debug.surface_get_arrays(i))
	return edges
