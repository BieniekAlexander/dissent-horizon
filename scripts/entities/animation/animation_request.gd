class_name AnimationRequest
extends RefCounted

## One clip a piece should be playing on one layer of its model, and how fast. What an
## AnimationProfile answers and an AnimationRig holds; nothing plays it yet (see AnimationRig).
## A LAYER is a part of the model animated independently — a body, a rotor, a turret — so a
## hovering gunship can run its rotors and its body without one clip having to encode both.

const DEFAULT_SPEED_SCALE: float = 1.0

var layer: StringName
var clip: StringName
## A multiplier on the clip's authored rate: 2.0 plays it twice as fast.
var speed_scale: float
## Played once and then dropped, rather than held — a cue's recoil, not an action's walk.
var is_one_shot: bool


func _init(a_layer: StringName, a_clip: StringName,
		a_speed_scale: float = DEFAULT_SPEED_SCALE, a_is_one_shot: bool = false) -> void:
	layer = a_layer
	clip = a_clip
	speed_scale = a_speed_scale
	is_one_shot = a_is_one_shot


func equals(a_other: AnimationRequest) -> bool:
	return a_other != null and layer == a_other.layer and clip == a_other.clip \
		and is_equal_approx(speed_scale, a_other.speed_scale) and is_one_shot == a_other.is_one_shot


func _to_string() -> String:
	return "%s:%s x%s%s" % [layer, clip, speed_scale, " (once)" if is_one_shot else ""]
