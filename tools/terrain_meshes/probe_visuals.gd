extends Node3D

## Lists every VisualInstance3D in a booted scenario, so "what is actually being drawn?" is
## answered by looking rather than by reasoning about which node should have been there.

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_run.call_deferred(args[0])

func _run(a_path: String) -> void:
	add_child((load(a_path) as PackedScene).instantiate())
	for _i: int in 90:
		await get_tree().physics_frame
	print("=== VisualInstance3D nodes ===")
	_walk(get_tree().root, 0)
	get_tree().quit()

func _walk(a_node: Node, a_depth: int) -> void:
	if a_node is VisualInstance3D:
		var v := a_node as VisualInstance3D
		var detail: String = ""
		if v is MeshInstance3D:
			var m: Mesh = (v as MeshInstance3D).mesh
			if m == null:
				detail = " mesh=<null>"
			else:
				var tris: int = 0
				for s: int in m.get_surface_count():
					var arr: Array = m.surface_get_arrays(s)
					var idx: Variant = arr[Mesh.ARRAY_INDEX]
					var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
					tris += (idx.size() if idx != null else verts.size()) / 3
				detail = " mesh=%s tris=%d" % [m.get_class(), tris]
		print("%s%s (%s) visible_in_tree=%s%s" % [
			"  ".repeat(a_depth), a_node.name, a_node.get_class(),
			v.is_visible_in_tree(), detail])
	for child: Node in a_node.get_children():
		_walk(child, a_depth + 1)
