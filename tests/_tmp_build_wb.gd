extends SceneTree
const B := preload("res://tools/heightmap_workbench_builder.gd")
func _init() -> void:
	var r: Dictionary = B.new().build()
	print("BUILD ok=%s scene=%s" % [r["ok"], r["scene_path"]])
	# Reload and inspect wiring.
	var scene: PackedScene = load(r["scene_path"])
	var inst: Node = scene.instantiate()
	var t: Node = inst.get_node_or_null("Terrain/HeightmapGeneratorTool")
	var m: Node = inst.get_node_or_null("Terrain/HeightmapMeshGenerator")
	print("  tool=%s meshgen=%s cam=%s" % [t != null, m != null, inst.get_node_or_null("Camera3D") != null])
	if t != null:
		print("  tool.generator=%s tool.shape=%s mesh_generator=%s" % [
			t.generator != null, t.shape != null, t.mesh_generator != null])
	if m != null:
		var gm: Node = m.get_node_or_null("GeneratedMesh")
		print("  meshgen.shape=%s GeneratedMesh=%s has_mesh=%s" % [
			m.shape != null, gm != null, (gm != null and gm.mesh != null)])
	inst.free()
	quit(0)
