class_name BotProduction
extends RefCounted

## BotProduction — trains the unit that best COUNTERS the believed enemy, with no
## per-unit rules and no cheap-unit bias.
##
## Each idle production building picks the producible unit with the highest
## composition value (Bot.unit_composition_value): effectiveness × per-enemy-type
## demand, where demand is each believed enemy type's importance reduced by how well
## the bot's CURRENT army already counters it. So:
##   • an enemy type the army can't handle (e.g. fliers it can't hit, or massed
##     irregulars only the Kamikaze's AOE answers) has high demand → that counter
##     gets built;
##   • once a threat is covered its demand falls (diminishing returns) → the bot
##     diversifies, and eventually values anti-structure units (warlords) for the
##     longer game, since enemy structures keep a (smaller) standing demand.
##
## Cost is NOT a tiebreaker: the wanted unit is trained when affordable, otherwise
## the building WAITS and saves up rather than spamming a cheaper, weaker unit — the
## fix for the bot drowning in irregulars. With no enemy seen yet, it just masses the
## cheapest unit to field an opening army.

var _bot: Bot
var _act: BotActuator


func _init(a_bot: Bot, a_act: BotActuator) -> void:
	_bot = a_bot
	_act = a_act


func tick() -> void:
	var demand: Dictionary = _bot.enemy_demand_map()
	for s: Commandable in _bot.get_idle_production_structures():
		var type: Entity.Type = _best_unit_for(s, demand)
		# Train the wanted unit only when we can afford it; otherwise wait and bank
		# ore for it instead of falling back to something cheaper and less useful.
		if type != Entity.Type.UNDEFINED and _bot.can_afford(type):
			_act.train(s, type)


## The producible unit at [structure] that best counters the believed enemy. With no
## intel yet (empty demand), falls back to the cheapest affordable unit so the
## building still fields an opening army.
func _best_unit_for(structure: Commandable, demand: Dictionary) -> Entity.Type:
	if demand.is_empty():
		return _cheapest_affordable_unit(structure)
	var best: Entity.Type = Entity.Type.UNDEFINED
	var best_score: float = -1.0
	for t: Entity.Type in structure.production.producible_types:
		var score: float = _bot.unit_composition_value(t, demand)
		if score > best_score:
			best_score = score
			best = t
	return best


func _cheapest_affordable_unit(structure: Commandable) -> Entity.Type:
	var best: Entity.Type = Entity.Type.UNDEFINED
	var best_cost: int = 1 << 30
	for t: Entity.Type in structure.production.producible_types:
		if _bot.can_afford(t):
			var cost: int = _ore_cost(t)
			if cost < best_cost:
				best_cost = cost
				best = t
	return best


func _ore_cost(type) -> int:
	var spec: TechnologySpec = _bot.technology_mapping.get(type)
	return spec.ore_cost if spec != null else 0
