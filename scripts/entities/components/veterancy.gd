class_name Veterancy
extends Node

enum Level { NONE = 0, VETERAN = 1, ELITE = 2, HEROIC = 3 }

var experience: int = 0
@export var level: Level = Level.NONE

@onready var _label: Label3D = get_parent().find_child("VeterancyLabel")

const _LEVEL_THRESHOLDS: Array[int] = [0, 20, 50, 100]

func _ready() -> void:
	experience = _LEVEL_THRESHOLDS[int(level)]
	_update_label()

func gain_experience(amount: int) -> void:
	experience += amount
	_update_level()

func _update_level() -> void:
	var new_level: Level
	if experience >= 100:
		new_level = Level.HEROIC
	elif experience >= 50:
		new_level = Level.ELITE
	elif experience >= 20:
		new_level = Level.VETERAN
	else:
		new_level = Level.NONE
	if new_level != level:
		level = new_level
		_update_label()

func _update_label() -> void:
	if _label == null:
		return
	if level == Level.NONE:
		_label.visible = false
	else:
		_label.visible = true
		_label.text = str(int(level))
