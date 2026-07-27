class_name HoverAnimationProfile
extends AnimationProfile

## A rotorcraft: its rotors are a layer of their own that always turns, idling on the ground
## and spinning far faster once airborne, whatever the body is doing.

const ROTOR_LAYER: StringName = &"rotors"
const ROTOR_CLIP: StringName = &"spin"

## Rotor rate, as a multiplier on the spin clip, while landed.
@export var grounded_rotor_speed_scale: float = 0.3
## Rotor rate while hovering — well above the landed rate, which is the whole tell.
@export var hovering_rotor_speed_scale: float = 3.0
## Rotor rate in forward flight.
@export var flying_rotor_speed_scale: float = 2.0


func requests_for(a_context: AnimationContext) -> Array[AnimationRequest]:
	var requests: Array[AnimationRequest] = super(a_context)
	requests.append(AnimationRequest.new(ROTOR_LAYER, ROTOR_CLIP,
		rotor_speed_scale(a_context.flight_mode)))
	return requests


func rotor_speed_scale(a_mode: Movement.Mode) -> float:
	match a_mode:
		Movement.Mode.HOVERING:
			return hovering_rotor_speed_scale
		Movement.Mode.FLYING:
			return flying_rotor_speed_scale
		_:
			return grounded_rotor_speed_scale
