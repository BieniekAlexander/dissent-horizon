class_name ConditionTimer
extends Condition

enum Mode {
	## True once total scenario physics frames >= seconds * 30.
	ELAPSED_SINCE_START,
	## True once N seconds have passed since this condition was first evaluated.
	## Countdown resets when the owning trigger resets (repeating triggers).
	COUNTDOWN
}

@export var mode: Mode = Mode.ELAPSED_SINCE_START
@export var seconds: float = 60.0

var _start_frame: int = -1

func evaluate(manager: ScenarioEventManager) -> bool:
	var target_frames := TimeUtils.get_frames_from_seconds(seconds)
	if mode == Mode.ELAPSED_SINCE_START:
		return manager.scenario.frame >= target_frames
	if _start_frame < 0:
		_start_frame = manager.scenario.frame
	return (manager.scenario.frame - _start_frame) >= target_frames

func reset() -> void:
	_start_frame = -1
