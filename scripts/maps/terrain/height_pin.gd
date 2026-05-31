@tool
class_name HeightPin
extends Node3D

signal height_changed(pin: HeightPin)

func _ready() -> void:
	if not Engine.is_editor_hint():
		queue_free()
		return
	set_notify_local_transform(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		height_changed.emit(self)
