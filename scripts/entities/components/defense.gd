class_name Defense
extends Node

#region Properties
enum ArmourType { LIGHT = 0, MEDIUM = 1, STRONG = 2 }
enum FrameType { BIO = 0, MECH = 1 }

@export var armour_type: ArmourType = ArmourType.LIGHT
@export var frame_type: FrameType = FrameType.BIO
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
func apply_damage(a_amount: float) -> bool:
	var was_alive: bool = hp > 0
	hp -= a_amount
	hp_changed.emit(hp, hp_max)
	return was_alive and hp <= 0


## Raise hp by `amount`, never past hp_max. Returns true once the entity is at FULL
## health, so a mender (the Repair command, a heal aura) can stop on the tick it finishes
## rather than polling hp itself. A no-op call — already full, or a non-positive amount —
## emits nothing, so a repairer parked on a healthy target doesn't repaint the HP bar
## every physics frame.
##
## REFUSED WHILE THE HOST IS STAGGERED: a piece that has just been hit cannot be mended
## through the fire it is taking, so healing joins the channeled actions stagger already
## suppresses (Build, Repair, PLANT). Enforced HERE rather than at each mender so the
## Repair command, a heal aura and whatever is added next cannot come to disagree — and a
## staggered patient reads as "not full yet", which keeps a repairer standing by rather
## than dropping its order. See Commandable.is_staggered.
##
## Construction is untouched: advance_build_progress writes hp directly, because raising a
## building is not healing it.
func restore(a_amount: float) -> bool:
	if a_amount <= 0.0:
		return hp >= hp_max
	var host := get_parent() as Commandable
	var is_staggered: bool = host != null and host.is_staggered()
	# A heal that lands takes off whatever an enemy has stuck on the piece — a beacon, a planted
	# charge — whether or not there was any hp to restore, so a heal proc on a whole piece still
	# clears markers its owner may not be able to see.
	if host != null and not is_staggered:
		host.shed_hostile_markers()
	if hp >= hp_max:
		# Whole, but still wearing a marker the stagger kept on: not done yet.
		return not (is_staggered and host.has_hostile_markers())
	if is_staggered:
		return false
	hp = minf(hp + a_amount, hp_max)
	hp_changed.emit(hp, hp_max)
	return hp >= hp_max


## Drop hp straight to 0 without running the damage pipeline, for effects that must
## destroy an entity outright (e.g. SuicideStatusEffect). Death still routes through
## the normal hp <= 0 detection in Commandable._update_state.
func kill() -> void:
	if hp == 0:
		return
	hp = 0
	hp_changed.emit(hp, hp_max)
#endregion
