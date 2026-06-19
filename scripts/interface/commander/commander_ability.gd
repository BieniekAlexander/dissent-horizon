class_name CommanderAbility extends RefCounted

## A commander-level ability the player can activate at a chosen map position.
## Wraps an AbstractEvent (created fresh on each activation) with a cooldown timer.
## Subclasses override _make_event() to return the specific event to execute.

var ability_name: String = ""
var cooldown_duration: float = 60.0
var _cooldown_remaining: float = 0.0

func is_ready() -> bool:
	return _cooldown_remaining <= 0.0

func cooldown_remaining() -> float:
	return _cooldown_remaining

## 0.0 = cooldown just started, 1.0 = ready.
func cooldown_progress() -> float:
	if cooldown_duration <= 0.0:
		return 1.0
	return 1.0 - (_cooldown_remaining / cooldown_duration)

func tick(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)

## Execute the ability at the given world position. Starts the cooldown on success.
func activate(position: Vector3, manager: ScenarioTriggerManager) -> void:
	if not is_ready():
		return
	var event: AbstractEvent = _make_event()
	if event == null:
		return
	manager.add_child(event)
	event.global_position = position
	event.execute(manager)
	event.queue_free()
	_cooldown_remaining = cooldown_duration

## Return a fresh AbstractEvent instance for this ability. Override in subclasses.
func _make_event() -> AbstractEvent:
	return null
