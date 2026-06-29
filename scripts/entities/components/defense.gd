class_name Defense
extends Node

#region Properties
enum ArmourType { LIGHT = 0, MEDIUM = 1, HEAVY = 2 }
enum FrameType { BIOLOGICAL = 0, METALLIC = 1 }

@export var armour_type: ArmourType = ArmourType.LIGHT
@export var frame_type: FrameType = FrameType.BIOLOGICAL
@export var hp_max: float = 100
var hp: float

## Emitted whenever hp changes, so visuals (the HP bar) can update reactively
## instead of polling hp every frame. Carries the new hp and hp_max.
signal hp_changed(hp: float, hp_max: float)
#endregion

#region Lifecycle
func _ready() -> void:
	hp = hp_max
#endregion

#region Mutators
## Lower hp by `amount` (already armour-adjusted by the caller). Returns true when
## this brought a previously-living entity to 0 or below — i.e. the hit was lethal —
## so the caller can run death-attribution logic. Death handling itself stays with
## the caller (Commandable._update_state detects hp <= 0).
func apply_damage(amount: float) -> bool:
	var was_alive: bool = hp > 0
	hp -= amount
	hp_changed.emit(hp, hp_max)
	return was_alive and hp <= 0

## Drop hp straight to 0 without running the damage pipeline, for effects that must
## destroy an entity outright (e.g. SuicideStatusEffect). Death still routes through
## the normal hp <= 0 detection in Commandable._update_state.
func kill() -> void:
	if hp == 0:
		return
	hp = 0
	hp_changed.emit(hp, hp_max)
#endregion
