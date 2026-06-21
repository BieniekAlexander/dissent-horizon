@tool
extends EditorScript

## (Re)builds scenes/tools/heightmap_workbench.tscn and its generator/terrain
## resources.  Run with Ctrl+Shift+X, then open the workbench scene to generate
## heightmaps interactively via the HeightmapGeneratorTool's "Generate" button.
##
## You normally only need to run this ONCE to create the workbench; after that you
## work inside the scene itself.

const WorkbenchBuilder := preload("res://tools/terrain/heightmap_workbench_builder.gd")


func _run() -> void:
	var r: Dictionary = WorkbenchBuilder.new().build()
	if r["ok"]:
		print("heightmap_workbench: built ", r["scene_path"])
		print("  open it, select HeightmapGeneratorTool, edit ", r["generator"], ", click Generate")
	else:
		push_error("heightmap_workbench: scene save failed")
