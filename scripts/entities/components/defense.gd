class_name Defense
extends Node

#region Properties
enum Armor { LIGHT, HEAVY }

@export var armor: Armor = Armor.LIGHT
@export var hp_max: float = 100
var hp: float
#endregion

#region Lifecycle
func _ready() -> void:
	hp = hp_max
#endregion
