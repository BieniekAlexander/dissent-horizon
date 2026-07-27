@tool
extends EditorScript

## Editor-only authoring tool: mirror CollisionLayers.Mask into the project's
## 3D physics layer names so the inspector's layer checkboxes read as the game's
## semantic names. Run it from the editor (File > Run) after editing the enum.
##
## Deliberately has NO class_name and lives outside scripts/: it extends
## EditorScript, which does not exist in export templates, so nothing shipped in
## the game may reference it. See scripts/collision_layers.gd.

func _run() -> void:
	for layer_num: int in range(1, 32 + 1):
		ProjectSettings.set("layer_names/3d_physics/layer_%d" % layer_num, "Layer %s" % layer_num)

	for key in CollisionLayers.Mask.keys():
		var val: int = CollisionLayers.Mask[key]
		var layer_num: int = 1 + int(log(val) / log(2))  # 1-based Godot layer index
		ProjectSettings.set("layer_names/3d_physics/layer_%d" % layer_num, key)

	# The per-side targetable bits (CollisionLayers.side_bits): one per commander per layer.
	for commander_id: int in range(1, Commander.NUM_MAX_COMMANDERS + 1):
		for pair: Array in [["GROUND", CollisionLayers.Mask.TARGETABLE_GROUND],
				["AIR", CollisionLayers.Mask.TARGETABLE_AIR]]:
			var bit: int = CollisionLayers.side_bits(pair[1], commander_id)
			var layer_num: int = 1 + int(log(bit) / log(2))
			ProjectSettings.set("layer_names/3d_physics/layer_%d" % layer_num,
				"TARGETABLE_%s_SIDE_%d" % [pair[0], commander_id])

	ProjectSettings.save()
	print("CollisionLayers: project settings updated.")
