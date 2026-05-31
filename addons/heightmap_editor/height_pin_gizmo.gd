@tool
extends EditorNode3DGizmoPlugin

func _init() -> void:
	create_material("wire", Color(1.0, 0.6, 0.0))
	create_handle_material("handle")

func _has_gizmo(node: Node3D) -> bool:
	return node is HeightPin

func _get_gizmo_name() -> String:
	return "HeightPin"

func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()

	# Three-circle wireframe sphere
	var mat := get_material("wire", gizmo)
	var lines := PackedVector3Array()
	const R := 0.15
	const SEG := 16
	for i in SEG:
		var a0 := float(i) / SEG * TAU
		var a1 := float(i + 1) / SEG * TAU
		var c0 := cos(a0) * R;  var s0 := sin(a0) * R
		var c1 := cos(a1) * R;  var s1 := sin(a1) * R
		lines.append(Vector3(c0, s0, 0.0));  lines.append(Vector3(c1, s1, 0.0))
		lines.append(Vector3(c0, 0.0, s0));  lines.append(Vector3(c1, 0.0, s1))
		lines.append(Vector3(0.0, c0, s0));  lines.append(Vector3(0.0, c1, s1))
	gizmo.add_lines(lines, mat)

	# Single handle at the pin's local origin — enables click-select and box-select.
	gizmo.add_handles(PackedVector3Array([Vector3.ZERO]), get_material("handle", gizmo), [0])


func _get_handle_name(_gizmo: EditorNode3DGizmo, _id: int, _secondary: bool) -> String:
	return "Height"

func _get_handle_value(gizmo: EditorNode3DGizmo, _id: int, _secondary: bool) -> Variant:
	return gizmo.get_node_3d().position.y

func _set_handle(gizmo: EditorNode3DGizmo, _id: int, _secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var pin := gizmo.get_node_3d() as HeightPin
	var ray_from := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)

	# Intersect with a vertical plane that faces the camera, passing through the pin.
	# This lets mouse movement in screen-Y map naturally to world-Y movement.
	var cam_xz := Vector3(ray_dir.x, 0.0, ray_dir.z)
	if cam_xz.length_squared() < 1e-6:
		return  # Camera pointing straight up/down; skip
	var plane := Plane(cam_xz.normalized(), pin.global_position)
	var hit := plane.intersects_ray(ray_from, ray_dir)
	if hit == null:
		return

	# Convert to HeightPins (Map) local space and apply only the Y component.
	pin.position.y = (pin.get_parent() as Node3D).to_local(hit).y

func _commit_handle(gizmo: EditorNode3DGizmo, _id: int, _secondary: bool, restore: Variant, cancel: bool) -> void:
	if cancel:
		(gizmo.get_node_3d() as HeightPin).position.y = restore
