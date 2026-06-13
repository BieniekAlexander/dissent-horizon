class_name Stealth
extends Node

## Stealth component — tracks how visible an entity currently is via a small
## three-state machine, and manages the countdown that returns a combat-revealed
## unit to hiding.
##
## States:
##   STEALTHED   — hidden: no detector sees it and it hasn't been in combat.
##                 Invisible to enemies; faintly visible to its owner.
##   REVEALED    — a detector currently overlaps it. Transient: the unit drops
##                 back to STEALTHED the moment it leaves every detector's range.
##                 Faintly visible to everyone.
##   UNSTEALTHED — it has attacked or been attacked, forcing it fully visible for
##                 UNSTEALTH_DURATION_FRAMES regardless of detector coverage.
##
## Detection protocol (frame-stamp approach, ordering-safe):
##   - Any entity with a DetectionRange shape calls reveal() on this node each
##     physics frame it overlaps the stealthed entity. reveal() records the
##     current physics-frame index rather than setting a flag, so this unit's own
##     tick() can compare against the frame index regardless of which entity
##     processed first this tick.
##   - Combat events (attacked / attacking) call unstealth(), which starts the
##     timed UNSTEALTHED window. That window is independent of detector coverage.

enum State {
	STEALTHED,    ## hidden from enemies
	REVEALED,     ## seen by a detector, but not combat-revealed
	UNSTEALTHED,  ## attacked or been attacked — fully visible, timed
}

## Physics frames the unit stays UNSTEALTHED after the last combat event.
## 90 frames ≈ 3 s at 30 ticks/s.
const UNSTEALTH_DURATION_FRAMES: int = 90

## Current visibility state. Read by Commandable._process (sprite alpha) and the
## controller's cursor (STEALTHED enemies are unclickable / untargetable).
var state: State = State.STEALTHED

## Remaining frames in the UNSTEALTHED window. Only meaningful while
## state == State.UNSTEALTHED; counts down each tick.
var _unstealth_timer_frames: int = 0

## Physics-frame index of the most recent reveal() call. -1 = never detected.
var _last_detected_frame: int = -1


func _ready() -> void:
	# Register on the STEALTH collision layer so DetectionRange shapes can
	# find this entity via a targeted physics query.
	var entity := get_parent() as Entity
	if entity != null:
		entity.collision_layer |= CollisionLayers.Mask.STEALTH


## Called by a detecting entity each physics frame it overlaps this unit.
## Stamps the current frame index; tick() uses this to drive the REVEALED state.
func reveal() -> void:
	_last_detected_frame = Engine.get_physics_frames()


## Called when this unit attacks or is attacked. Forces the timed UNSTEALTHED
## window, which persists even after the unit leaves every detector's range.
func unstealth() -> void:
	state = State.UNSTEALTHED
	_unstealth_timer_frames = UNSTEALTH_DURATION_FRAMES


## Advance stealth state by one physics tick. Must be called once per tick from
## Commandable._update_state().
func tick() -> void:
	var detected := Engine.get_physics_frames() == _last_detected_frame

	# An open combat window pins the unit UNSTEALTHED until the timer elapses,
	# regardless of detector coverage. Once it closes, fall through to the
	# detector-driven STEALTHED/REVEALED decision below.
	if state == State.UNSTEALTHED:
		_unstealth_timer_frames -= 1
		if _unstealth_timer_frames > 0:
			return
		_unstealth_timer_frames = 0

	state = State.REVEALED if detected else State.STEALTHED
