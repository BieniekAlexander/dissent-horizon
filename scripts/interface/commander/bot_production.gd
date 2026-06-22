class_name BotProduction
extends RefCounted

## BotProduction — keeps production buildings busy with a tactically-chosen unit.
##
## Composition policy (army-comparison driven):
##   • When we DON'T clearly outnumber the enemy, build the anti-unit unit
##     (Irregular) to win the field fight.
##   • Once we outnumber them by SUPERIORITY_RATIO, switch to the anti-structure
##     unit (Warlord) to convert that lead into razing the enemy's base.
## The desired type is trained when a structure can produce + afford it; otherwise
## we fall back to whatever it can afford, so production never stalls.
##
## NOTE: the unit→role mapping is hardcoded to the current roster. There's no
## per-unit role/damage metadata in the game yet (that lives in the offline
## balance tool), so until there is, ANTI_UNIT / ANTI_STRUCTURE name the picks
## directly. Revisit when units carry queryable role or damage-vs-class data.

## The unit to mass when we need to beat the enemy ARMY.
const ANTI_UNIT: Entity.Type = Entity.Type.AN_UNIT_IRREGULAR
## The unit to mass when we're ahead and want to crush the enemy's STRUCTURES.
const ANTI_STRUCTURE: Entity.Type = Entity.Type.AN_UNIT_WARLORD

## How many times the enemy's combat-unit count we must field before we consider
## ourselves dominant enough to pivot to anti-structure production.
const SUPERIORITY_RATIO: float = 1.5

var _bot: Bot
var _act: BotActuator


func _init(a_bot: Bot, a_act: BotActuator) -> void:
	_bot = a_bot
	_act = a_act


func tick() -> void:
	var desired: Entity.Type = _desired_unit_type()
	for s: Commandable in _bot.get_idle_production_structures():
		var type: Entity.Type = _pick_trainable(s, desired)
		if type != Entity.Type.UNDEFINED:
			_act.train(s, type)


## Anti-structure when we clearly outnumber the enemy's army (finish them off),
## otherwise anti-unit (win the field fight first). With no enemy units left,
## any army of ours counts as dominant → push anti-structure to raze the base.
func _desired_unit_type() -> Entity.Type:
	var own: int = _combat_count(_bot.get_units())
	var enemy: int = _combat_count(_bot.get_enemy_units())
	if own > 0 and own >= enemy * SUPERIORITY_RATIO:
		return ANTI_STRUCTURE
	return ANTI_UNIT


## Train the desired type if this structure can make and afford it; else fall back
## to the highest-value unit it can currently afford (so a building is never idle
## when it could be producing something useful).
func _pick_trainable(structure: Commandable, desired: Entity.Type) -> Entity.Type:
	if structure.production.can_produce(desired) and _bot.can_afford(desired):
		return desired
	return _best_affordable_unit(structure)


func _best_affordable_unit(structure: Commandable) -> Entity.Type:
	var best: Entity.Type = Entity.Type.UNDEFINED
	for t: Entity.Type in structure.production.producible_types:
		if _bot.can_afford(t) and t > best:
			best = t
	return best


func _combat_count(units: Array) -> int:
	return units.filter(func(u: Commandable): return u.weapon_inventory != null).size()
