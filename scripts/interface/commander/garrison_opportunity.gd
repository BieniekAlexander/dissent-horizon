class_name GarrisonOpportunity
extends BotOpportunity

## GarrisonOpportunity — send an idle combat unit into a friendly bunker structure
## so it can fire from inside while being protected.

var _host: Commandable
var _utility: float


func _init(a_unit: Commandable, a_host: Commandable, a_utility: float) -> void:
	actor = a_unit
	_host = a_host
	_utility = a_utility


func utility() -> float:
	return _utility


func execute(a_act: BotActuator) -> void:
	# accepts() rather than a bare room check: the host may not admit THIS unit at all
	# (its occupancy masks), and either way the Occupy order would just be refused.
	if is_instance_valid(_host) and _host.garrison != null and _host.garrison.accepts(actor):
		a_act.garrison_into(actor, _host)


func describe() -> String:
	return "garrison %s into %s (utility %.1f)" % [actor.name, _host.name, _utility]
