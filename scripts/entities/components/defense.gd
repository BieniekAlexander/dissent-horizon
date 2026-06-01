class_name Defense
extends Node

enum Armor { LIGHT, HEAVY }

@export var armor: Armor = Armor.LIGHT
@export var hp_max: float = 100
var hp: float

func _ready() -> void:
	hp = hp_max
