class_name Shield
extends RefCounted

## A pool of hit points layered over a piece's Defense, which takes damage before Defense
## does. A piece holds at most one shield of each Type (Defense.apply_shield); what grants a
## shield owns its duration, so this is only the pool and the classes it resists with.
## Rules: gdd/systems/combat/shields.md.

## What kind of shield this is. One of each may stand on a piece at once.
enum Type { CRYO = 0 }

var type: Type
var hp: float
## The armour class damage meets in this shield, or null to fall through to the host's own.
## Variant because "none" is a real state: the shield borrows the host's class.
var armour_type: Variant = null
## The frame damage meets in this shield, or null to fall through to the host's own.
var frame_type: Variant = null


func _init(
	a_type: Type, a_hp: float, a_armour_type: Variant = null, a_frame_type: Variant = null
) -> void:
	type = a_type
	hp = a_hp
	armour_type = a_armour_type
	frame_type = a_frame_type


## This shield's armour class over `a_defense`: its own, or the host's when it falls through.
func armour_over(a_defense: Defense) -> Defense.ArmourType:
	return a_defense.armour_type if armour_type == null else armour_type


## This shield's frame over `a_defense`: its own, or the host's when it falls through.
func frame_over(a_defense: Defense) -> Defense.FrameType:
	return a_defense.frame_type if frame_type == null else frame_type


func is_broken() -> bool:
	return hp <= 0.0
