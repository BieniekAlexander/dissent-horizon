class_name ConditionOccurrenceTally
extends Condition

## True once `count` matching entity occurrences have CUMULATIVELY happened — e.g. "10 of
## commander 1's units have died." PUSH-based: arm() subscribes to the manager's
## entity_occurrence bus (fed by Entity._fire_entity_occurrence → ScenarioTriggerManager.
## report_entity_occurrence) and the handler accumulates and emits state_changed on the
## threshold edge; evaluate()/is_met() report the cached tally. Counting via signal means
## occurrences still count after the units are gone / replaced (unlike a polled count).

#region Properties
## The lifecycle occurrence to tally (e.g. ON_DEATH).
@export var occurrence: Entity.EntityOccurrence = Entity.EntityOccurrence.ON_DEATH
## Only count occurrences from this commander; -1 counts any commander.
@export var commander_id: int = -1
## How many matching occurrences must accumulate for this condition to be met.
@export var count: int = 1

var _tally: int = 0
#endregion

#region Push wiring
func arm(manager: ScenarioTriggerManager) -> void:
	if not manager.entity_occurrence.is_connected(_on_entity_occurrence):
		manager.entity_occurrence.connect(_on_entity_occurrence)


func disarm(manager: ScenarioTriggerManager) -> void:
	if manager.entity_occurrence.is_connected(_on_entity_occurrence):
		manager.entity_occurrence.disconnect(_on_entity_occurrence)
#endregion

#region Public API
func evaluate(_manager: ScenarioTriggerManager) -> bool:
	return _tally >= count


func reset() -> void:
	super.reset()
	_tally = 0
#endregion

#region Private helpers
func _on_entity_occurrence(an_occurrence: Entity.EntityOccurrence, source: Entity) -> void:
	if an_occurrence != occurrence:
		return
	if commander_id != -1 and (source == null or source.commander_id != commander_id):
		return
	_tally += 1
	var now: bool = _tally >= count
	if now != _last:
		_last = now
		state_changed.emit()
#endregion
