@tool
extends EditorScript

## Bakes a grid of GraphPlateauHeightmapGenerator variations into a single
## reviewable gallery scene, plus the generator + heightmap .tres for each and a
## stats README.
##
## Run from the Script editor with Ctrl+Shift+X.  Then open
##   res://resources/graph_plateau_batch/graph_plateau_gallery.tscn
## and orbit to compare variations.  To use one in the game, drag its baked
## hm_*.tres onto Map.height_map (the Map setter rebuilds the mesh + pins), or
## assign its gp_*.tres to a HeightmapGeneratorTool.generator and click Generate.
##
## All logic lives in graph_plateau_gallery_builder.gd so it can also be driven
## headlessly (EditorScript itself cannot be instantiated outside the editor).

const GalleryBuilder := preload("res://tools/graph_plateau_gallery_builder.gd")


func _run() -> void:
	var result: Dictionary = GalleryBuilder.new().build()
	var entries: Array = result["entries"]
	print("graph_plateau_gallery: %d variations saved to res://resources/graph_plateau_batch" % entries.size())
	for e: Dictionary in entries:
		print("  hm_%s — %d%% passable, %d%% flat, connected=%s" % [
			e["tag"], e["passable_pct"], e["flat_pct"], e["connected"]
		])
	if result["ok"]:
		print("graph_plateau_gallery: open ", result["scene_path"])
	else:
		push_error("graph_plateau_gallery: scene save failed")
