@tool
extends EditorPlugin

## Adds a "Cam Angle" button to the 3D editor toolbar. Pressing it is a one-shot:
## the editor viewport camera jumps to RTSCamera3D.initial_position() and looks at
## the scene origin, reproducing the player's game view so flat sprites are
## composed the way the player will see them. The editor leaves the camera there
## until you next navigate, so this is a plain one-shot — no continuous lock.

#region Properties
var _button: Button = null
#endregion

#region Lifecycle
func _enter_tree() -> void:
	_button = Button.new()
	_button.text = "Cam Angle"
	_button.tooltip_text = "Snap the editor camera to the game view: distance %s at %d°, looking at the origin." % [
		str(RTSCamera3D.INITIAL_DISTANCE), int(RTSCamera3D.CAMERA_ANGLE_DEGREES)]
	_button.pressed.connect(_apply_view)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _button)


func _exit_tree() -> void:
	if _button != null:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _button)
		_button.queue_free()
		_button = null
#endregion

#region View
## Move the editor viewport camera to the game's starting vantage and aim it at
## the scene origin. look_at forces the canonical downward angle from there.
func _apply_view() -> void:
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	if viewport == null:
		return
	var camera := viewport.get_camera_3d()
	if camera == null:
		return
	camera.global_position = RTSCamera3D.initial_position()
	camera.look_at(Vector3.ZERO, Vector3.UP)
#endregion
