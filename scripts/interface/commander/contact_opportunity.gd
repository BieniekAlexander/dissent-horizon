class_name ContactOpportunity
extends BotOpportunity

## ContactOpportunity — walk one of our units onto another unit, where CONTACT ITSELF is the
## whole mechanic. There is nothing to issue but a move; arriving is the action.
##
## Two mechanics have this shape, and neither has a command of its own:
##   - LIBERATION — a [Liberator] (a Warlord) converts a neutral Terrestrial it walks past.
##   - CAPTURE — a crusher with a hold (a Stock Truck) takes prisoner what it drives over,
##     see Garrison.can_capture.
##
## Utility is the prize's energy value minus a travel cost, so a nearer target (faster
## payoff, less exposure) outranks a distant one while a distant one can still be worth it
## when the reward is large.

## Energy-value charged per world-unit of travel to the target. Converts distance into a
## utility cost on the same energy-equivalent scale as the prize's value, so the two trade
## off directly. Tunable per difficulty later.
const TRAVEL_COST_PER_UNIT: float = 2.0

var _target: Actor
var _value: float
var _distance: float
var _label: String


func _init(a_actor: Actor, a_target: Actor, a_value: float, a_label: String) -> void:
	actor = a_actor
	_target = a_target
	_value = a_value
	_label = a_label
	_distance = a_actor.global_position.distance_to(a_target.global_position)


func utility() -> float:
	return _value - TRAVEL_COST_PER_UNIT * _distance


func execute(a_act: BotActuator) -> void:
	# A move AT the target, not attack-move and not a move to where it stands: the point is
	# to ARRIVE ON IT, and it moves. Attack-moving would stop the unit to shoot at whatever it
	# met on the way, and for a Warlord the prize is a neutral it must not shoot at all; a
	# move to a position arrived on empty ground whenever the prey had walked on (observed
	# 2026-10-06: the truck took one prisoner per errand and lost the rest).
	a_act.move_at([actor], _target)


func describe() -> String:
	return "%s %s (value %.0f, dist %.0f)" % [_label, _target.name, _value, _distance]
