class_name BipedAnimationProfile
extends AnimationProfile

## A two-legged soldier: moving while badly hurt plays a wounded run instead of the healthy
## one. TODO: the wounded threshold wants to be the same number as the low-health movement
## penalty once that mechanic exists, rather than a second one authored here.

const WOUNDED_MOVING_CLIP: StringName = &"moving_wounded"

## Health fraction at or below which movement plays the wounded run.
@export_range(0.0, 1.0) var wounded_health_fraction: float = 0.3


func requests_for(a_context: AnimationContext) -> Array[AnimationRequest]:
	if a_context.action == ActionTracker.Action.MOVING \
			and a_context.health_fraction <= wounded_health_fraction:
		return [AnimationRequest.new(BODY_LAYER, WOUNDED_MOVING_CLIP)]
	return super(a_context)
