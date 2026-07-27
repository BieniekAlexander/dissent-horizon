class_name AnimationContext
extends RefCounted

## Everything an AnimationProfile may consult about its piece this tick, gathered in one place
## so the profiles stay pure: they read a context and return requests, and never touch a node.
## A new thing a profile wants to vary on (a load carried, a weather state) is a field here.

var action: ActionTracker.Action = ActionTracker.Action.IDLE
## Current over maximum hit points; 1.0 for a piece with no Defense.
var health_fraction: float = 1.0
## The piece's flight mode — GROUNDED for anything that cannot leave the ground.
var flight_mode: Movement.Mode = Movement.Mode.GROUNDED
## Horizontal speed this tick, in world units per second.
var speed_mps: float = 0.0


## The context of `actor` as it stands now.
static func of(actor: Commandable) -> AnimationContext:
	var context: AnimationContext = AnimationContext.new()
	context.action = actor.action_tracker.current_action()
	if actor.defense != null and actor.defense.hp_max > 0.0:
		context.health_fraction = clampf(actor.defense.hp / actor.defense.hp_max, 0.0, 1.0)
	if actor.movement != null:
		context.flight_mode = actor.movement.mode
	# A commandable moves by move_and_slide, whose velocity is already per second.
	context.speed_mps = VU.inXZ(actor.velocity).length()
	return context
