class_name AnimationProfile
extends Resource

## How one kind of piece turns what it is doing into clips: given an AnimationContext, which
## clip each layer of its model plays and how fast; given a cue, what plays once over the top.
## The base plays one body clip named after the action (`idle`, `moving`, `building`…) and
## ignores cues. A kind whose animation has more to it subclasses this and overrides one or
## both — which is how a rotor that speeds up in the air and a turret that recoils on firing
## live in the kind they belong to, not in one controller that knows every unit.
## → gdd/systems/ux/unit-animation.md
##
## Pure: a profile reads its context and returns requests, and touches no node. It exports
## scalars only, never a Resource (a Resource-valued export on a Resource crashes the editor
## inspector).

const BODY_LAYER: StringName = &"body"


## The clips to hold this tick, one per layer.
func requests_for(a_context: AnimationContext) -> Array[AnimationRequest]:
	return [AnimationRequest.new(BODY_LAYER, clip_for_action(a_context.action))]


## The clips to play once in answer to `a_cue` (see ActionTracker). None by default.
func requests_for_cue(_a_cue: StringName, _a_context: AnimationContext) -> Array[AnimationRequest]:
	return []


## The default clip name for an action: the action's own name in lower case.
static func clip_for_action(action: ActionTracker.Action) -> StringName:
	return StringName(String(ActionTracker.Action.keys()[action]).to_lower())
