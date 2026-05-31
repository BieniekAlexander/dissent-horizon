@tool
class_name CollisionLayers
extends Node

enum Layer {
	BODY     	= 1 << 0,
	STRUCTURE	= 1 << 1,
	SELECTION	= 1 << 8,
	TERRAIN		= 1 << 7
}

func _notification(what):
	match what:
		NOTIFICATION_EDITOR_PRE_SAVE:
			apply_to_project_settings()
			print('w')
			# Useful for clearing temporary editor-only nodes


func apply_to_project_settings():
	for key in Layer.keys():
		var val: int = Layer[key]
		var layer_num: int = 1 + int(log(val) / log(2))  # 1-based Godot layer index
		ProjectSettings.set("layer_names/3d_physics/layer_%d" % layer_num, key)
	ProjectSettings.save()
	print("CollisionLayers: project settings updated.")
