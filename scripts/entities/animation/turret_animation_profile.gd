class_name TurretAnimationProfile
extends AnimationProfile

## A gun on a turret: every emission leaving the piece kicks the turret back once, on the
## exact tick it is launched (ActionTracker.CUE_EMITTED comes from Emitter.launch).
## TODO: a piece with more than one gun recoils one turret for all of them; telling which fired
## needs the cue to name its Weapon, which Emitter.launch is not told.

const TURRET_LAYER: StringName = &"turret"
const RECOIL_CLIP: StringName = &"recoil"


func requests_for_cue(a_cue: StringName, a_context: AnimationContext) -> Array[AnimationRequest]:
	if a_cue == ActionTracker.CUE_EMITTED:
		return [
			AnimationRequest.new(
				TURRET_LAYER, RECOIL_CLIP, AnimationRequest.DEFAULT_SPEED_SCALE, true
			)
		]
	return super(a_cue, a_context)
