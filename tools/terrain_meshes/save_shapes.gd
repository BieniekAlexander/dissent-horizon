@tool
extends SceneTree

## Saves the HeightMapShape3D derived from each baked TerrainData as its own resource, so the
## test scenes' collider and visual-mesh generator can both reference one file instead of
## embedding 25600 floats in the scene text.
##
## Run with:
##   godot --headless -s res://tools/terrain_meshes/save_shapes.gd


func _initialize() -> void:
	for name: String in ["mesh_flat_terrain", "mesh_disc_terrain", "mesh_plateau_terrain"]:
		var path: String = "res://resources/terrain/%s.tres" % name
		var data: TerrainData = load(path)
		if data == null:
			push_error("missing %s — run generate_test_meshes.gd first" % path)
			continue
		var out: String = "res://resources/terrain/%s_shape.tres" % name
		var err: int = ResourceSaver.save(data.to_height_shape(), out)
		print("%s -> %s (%s)" % [path, out, "ok" if err == OK else "ERR %d" % err])
	quit()
