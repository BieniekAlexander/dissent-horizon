class_name InteractOpportunity
extends BotOpportunity

## InteractOpportunity — send an Interactor unit to perform an Interaction on a target,
## valued in ore-equivalent so it ranks against every other [BotOpportunity]. Generic
## over the interaction kind: the gatherer computes the gain (`value`) and this just
## charges travel and issues the Interact. Used for the Colonial capture / shelter-
## collect / internment-deposit loop (see BotOpportunist), and reusable by any future
## interaction-driven dominion mechanic.

## Ore-value charged per world-unit of travel — same scale/idea as LiberationOpportunity,
## so a nearer target outranks a distant one of equal gain.
const TRAVEL_COST_PER_UNIT: float = 2.0

var _target: Entity
var _value: float
var _distance: float
var _label: String
var _travel_weight: float


## `a_travel_weight` scales the per-distance cost. Defaults to TRAVEL_COST_PER_UNIT for
## opportunistic errands (capture/collect) where a nearer target is clearly better. Pass
## 0.0 for "bring it home" actions like depositing, which must happen regardless of how
## far the carrier wandered — otherwise distance would veto banking prisoners.
func _init(a_actor: Commandable, a_target: Entity, a_value: float, a_label: String, a_travel_weight: float = TRAVEL_COST_PER_UNIT) -> void:
	actor = a_actor
	_target = a_target
	_value = a_value
	_label = a_label
	_travel_weight = a_travel_weight
	_distance = a_actor.global_position.distance_to(a_target.global_position)


func utility() -> float:
	return _value - _travel_weight * _distance


func execute(act: BotActuator) -> void:
	act.interact(actor, _target)


func describe() -> String:
	return "%s %s (value %.0f, dist %.0f)" % [_label, _target.name, _value, _distance]
