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
	for i in Layer.values():
		ProjectSettings.set("layer_names/3d_physics/layer_%s" % (i+1),  Layer.keys()[i])
	ProjectSettings.save()
	print("CollisionLayers: project settings updated.")
