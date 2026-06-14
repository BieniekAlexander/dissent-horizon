@tool
## Handles serialized representations of time as it relates to events,
## E.g. if I want a star to spawn after 600 frames, and then every 300 frames
class_name TimeUtils

static var rng = RandomNumberGenerator.new()

#region Public API
static func get_frames_from_seconds(a_seconds: float) -> int:
	return int(a_seconds * Engine.physics_ticks_per_second)

static func get_frame_duration_sample(a_distribution: Dictionary) -> int:
	var mean: int = (
		int(a_distribution["mean"])
		if a_distribution["mean"] is String
		else get_frames_from_seconds(a_distribution["mean"])
	)

	var stdev: int = (
		(
			int(a_distribution["stdev"])
			if a_distribution["stdev"] is String
			else get_frames_from_seconds(a_distribution["stdev"])
		) if a_distribution.has("stdev")
		else 0
	)

	return int(rng.randfn(mean, stdev))

static func get_frame_duration_from_time_spec(a_time_spec: Variant) -> int:
	if a_time_spec is Dictionary:
		return get_frame_duration_sample(a_time_spec)
	elif a_time_spec is float:
		return get_frames_from_seconds(a_time_spec)
	else:
		return int(a_time_spec)
#endregion
