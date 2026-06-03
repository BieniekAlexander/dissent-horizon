@tool
class_name CollisionLayers
extends Node

enum Layer {
	MOVEMENT_OBSTRUCTION = 1 << 0,  ## Units only. Governs physical push-back during move_and_slide.
	TARGETABLE           = 1 << 1,  ## All commandables (units + structures). Queried by aggro, vision, projectiles, AoE, and bot scans.
	STRUCTURE_BLOCKER    = 1 << 2,  ## Structures only. Queried by Attack line-of-fire raycasts.
	STEALTH              = 1 << 3,  ## Set at runtime by Stealth component. Queried by detection-range checks.
	TERRAIN              = 1 << 7,  ## Terrain StaticBody. Queried by ground-click raycasts.
	SELECTION            = 1 << 8,  ## Selectable Area3D. Queried by click-to-select raycasts.
}

func _notification(what):
	match what:
		NOTIFICATION_EDITOR_PRE_SAVE:
			apply_to_project_settings()
			# Useful for clearing temporary editor-only nodes


func apply_to_project_settings():
	for key in Layer.keys():
		var val: int = Layer[key]
		var layer_num: int = 1 + int(log(val) / log(2))  # 1-based Godot layer index
		ProjectSettings.set("layer_names/3d_physics/layer_%d" % layer_num, key)
	ProjectSettings.save()
	print("CollisionLayers: project settings updated.")
