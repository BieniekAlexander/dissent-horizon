class_name Defense
extends Node

#region Properties
enum ArmourType { UNARMORED = 0, LIGHT = 1, MEDIUM = 2, HEAVY = 3 }

@export var armour_type: ArmourType = ArmourType.UNARMORED
@export var hp_max: float = 100
var hp: float
#endregion

#region Lifecycle
func _ready() -> void:
	hp = hp_max
#endregion
