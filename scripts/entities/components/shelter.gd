class_name Shelter
extends Node
## Shelter component — component for a special neutral structure, with which each faction has unique interactions
##
## See [Interactor] / [Interaction] / [Interact] for the interaction mechanic
## this gates.

#region Properties
## Seconds the shelter spends counting down before it becomes available.
@export var startup_delay: float = 60.0

## Seconds remaining until available. Initialised to `startup_delay` on ready
## and decremented each physics tick down to 0.
var _remaining: float = 0.0

## True once the startup countdown has fully elapsed (timer rested at 0.0).
var available: bool:
	get: return _remaining <= 0.0
#endregion

#region Public API
## Restart the countdown to maximum, making the shelter unavailable again. Called
## when a unit completes a consuming interaction (LIBERATE) on this shelter, so it
## must recharge before it can be interacted with again.
func reset() -> void:
	_remaining = startup_delay
#endregion

#region Lifecycle
func _ready() -> void:
	_remaining = startup_delay

func _physics_process(delta: float) -> void:
	if _remaining > 0.0:
		_remaining = maxf(0.0, _remaining - delta)

@onready var temp_label: Label3D = get_parent().find_child("TempLabel") if get_parent() != null else null
func _process(_delta: float) -> void:
	if temp_label != null:
		temp_label.text = "Shelter %s" % int(_remaining)
#endregion
