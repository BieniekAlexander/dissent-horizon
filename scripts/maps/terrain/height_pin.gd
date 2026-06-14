@tool
class_name HeightPin
extends Sprite3D

#region Signals
signal height_changed(pin: HeightPin)
#endregion

#region Lifecycle
func _ready() -> void:
	texture = load("res://assets/logo.png")
	scale = Vector3.ONE * .1

	if not Engine.is_editor_hint():
		queue_free()
		return
	set_notify_local_transform(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		height_changed.emit(self)
#endregion
