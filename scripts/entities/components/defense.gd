class_name Defense
extends Node

#region Properties
enum ArmourType { LIGHT = 0, MEDIUM = 1, HEAVY = 2 }
enum FrameType { BIOLOGICAL = 0, METALLIC = 1 }

@export var armour_type: ArmourType = ArmourType.LIGHT
@export var frame_type: FrameType = FrameType.BIOLOGICAL
@export var hp_max: float = 100
var hp: float
#endregion

#region Lifecycle
func _ready() -> void:
	hp = hp_max
#endregion
