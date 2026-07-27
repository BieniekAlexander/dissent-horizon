class_name ActionTracker
extends RefCounted

## What a commandable is DOING, tick by tick: the one fact its animation and its action badge
## both read. It decides nothing itself — CommandReceiver reports what each tick of the
## command lifecycle actually did (acted, moved, or neither), and every emitter reports each
## emission leaving it — and it announces the changes.
##
## Two kinds of thing are tracked, because an animation needs both:
##   • an ACTION is sustained, and holds until the next one replaces it (walking, building);
##   • a CUE is a moment inside one (a shot leaving the barrel), which plays once and changes
##     nothing about the action.
## → gdd/systems/ux/unit-animation.md

## What a tick of the lifecycle was spent on. ACTING is a command acting that has not said
## what its action is.
enum Action {
	IDLE,
	MOVING,
	ATTACKING,
	BUILDING,
	REPAIRING,
	UNLOADING,
	INTERACTING,
	STUNNED,
	ACTING,
}

## An emission left this piece — a weapon's shot, a Bombard's shell. The source is the emission.
const CUE_EMITTED: StringName = &"emitted"

## The action changed on this tick.
signal action_changed(a_from: Action, a_to: Action)
## A momentary event happened; `a_source` is what caused it, or null.
signal cued(a_cue: StringName, a_source: Object)

## Framework-imposed state: an action is by definition what persists between ticks.
var _action: Action = Action.IDLE


func current_action() -> Action:
	return _action


## Record what this tick was spent on, announcing it when that differs from the last tick.
func observe(a_action: Action) -> void:
	if a_action == _action:
		return
	var from: Action = _action
	_action = a_action
	action_changed.emit(from, a_action)


func cue(a_cue: StringName, a_source: Object = null) -> void:
	cued.emit(a_cue, a_source)
