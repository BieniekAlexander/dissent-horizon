@tool
extends EditorScript

## Bakes a blocked-mask review scene (terrain + red blocked-cell overlay).
## Run from the Script editor with Ctrl+Shift+X, then open
##   res://resources/block_mask_demo/block_mask_demo.tscn
## Logic lives in block_mask_demo_builder.gd (EditorScript can't run headlessly).

const DemoBuilder := preload("res://tools/terrain/block_mask_demo_builder.gd")


func _run() -> void:
	var r: Dictionary = DemoBuilder.new().build()
	print("block_mask_demo: %d / %d cells blocked" % [r["blocked"], r["cells"]])
	if r["ok"]:
		print("block_mask_demo: open ", r["scene_path"])
	else:
		push_error("block_mask_demo: scene save failed")
