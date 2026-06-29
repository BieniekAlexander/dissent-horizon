class_name LiberationOpportunity
extends BotOpportunity

## LiberationOpportunity — send a Warlord (any Interactor-equipped unit) to liberate a
## Shelter, gaining the free units the liberation event spawns under our commander.
##
## Utility is the spawned units' ore value minus a travel cost, so a nearer shelter
## (faster payoff, less exposure) outranks a distant one but a distant shelter can
## still be worth it when the reward is large.

## Ore-value charged per world-unit of travel to the shelter. Converts distance into a
## utility cost on the same ore-equivalent scale as the spawn value, so the two trade
## off directly. Tunable per difficulty later.
const TRAVEL_COST_PER_UNIT: float = 2.0

var _shelter: Entity
var _value: float
var _distance: float


func _init(a_warlord: Commandable, a_shelter: Entity, a_value: float) -> void:
	actor = a_warlord
	_shelter = a_shelter
	_value = a_value
	_distance = a_warlord.global_position.distance_to(a_shelter.global_position)


func utility() -> float:
	return _value - TRAVEL_COST_PER_UNIT * _distance


func execute(act: BotActuator) -> void:
	act.interact(actor, _shelter)


func describe() -> String:
	return "liberate %s (value %.0f, dist %.0f)" % [_shelter.name, _value, _distance]
