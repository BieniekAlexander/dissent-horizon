@tool
class_name TimeUtils

#region Public API
static func get_frames_from_seconds(a_seconds: float) -> int:
	return int(a_seconds * Engine.physics_ticks_per_second)
#endregion
