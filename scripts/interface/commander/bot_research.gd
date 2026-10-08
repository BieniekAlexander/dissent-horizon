class_name BotResearch
extends RefCounted

## BotResearch — buys an upgrade when what it does for the pieces the bot FIELDS is worth
## more than it costs. No upgrade is known by name: each is read off UpgradeCatalog as
## `modifies:` entries, and every entry is a FACTOR on something — hit points, a rearm or
## recharge rate, an ability's reach — so one rule prices them all:
##
##   value = Σ over entries of (factor − 1) × the cost of the fielded pieces it selects
##
## A quarter more hit points on 2,000 energy of tanks is worth 500; a reach tripled on 300
## energy of spotters is worth 600; an upgrade to pieces the bot has none of is worth
## nothing, which is what keeps it from researching ahead of its army. The bar is
## `tech_value_margin`, the same "this much better than what I have" the tech rung buys a
## building on, and the purchase is an ordinary train job at the structure that researches
## it (BotActuator.train), with the reserve respected like any other spend.
## gdd/systems/ai/bot-architecture.md §The research rung.

## Work units per upgrade priced.
const UPGRADE_WORK_UNITS: int = 60

## The usage-log domain research choices are recorded under, so the audit can see an upgrade
## that was priced and never bought beside one that was never priced.
const CHOICE_DOMAIN: String = "research"

var _bot: Bot
var _act: BotActuator

## How many times its cost an upgrade must be worth before it is bought
## (BotDifficulty.tech_value_margin, pushed by BotBrain._apply_config).
var tech_value_margin: float = 1.3
## Energy that must still be banked after the purchase (BotDifficulty.economy_reserve).
var reserve: int = 0


func _init(a_bot: Bot, a_act: BotActuator) -> void:
	_bot = a_bot
	_act = a_act


## Returns the work units spent.
func tick() -> int:
	var priced: int = 0
	for structure: Commandable in _bot.get_research_structures():
		if not structure.production.is_free():
			continue
		var scores: Dictionary = {}
		for id: StringName in structure.production.producible_types:
			if not UpgradeCatalog.is_upgrade(id) or _bot.is_research_taken(id):
				continue
			scores[id] = _value_of(id)
			priced += 1
		if scores.is_empty():
			continue
		var best: StringName = _best(scores)
		_act.usage.record_choice(CHOICE_DOMAIN, scores, best)
		if _worth_buying(best, scores[best]):
			_act.train(structure, best)
	return priced * UPGRADE_WORK_UNITS


## What `a_upgrade` is worth to this bot right now, in energy — see the class note.
func _value_of(a_upgrade: StringName) -> float:
	var total: float = 0.0
	var fielded: Array = _bot.get_units() + _bot.get_structures()
	for modifier: Dictionary in UpgradeCatalog.modifiers_of(a_upgrade):
		var selected: Array = fielded.filter(
			func(piece: Entity) -> bool: return UpgradeCatalog.applies_to(modifier, piece)
		)
		if selected.is_empty():
			continue
		var factor: float = _factor_of(modifier, selected[0])
		if factor <= 1.0:
			continue
		var cost: float = 0.0
		for piece: Entity in selected:
			cost += float(_bot.unit_cost(piece.id))
		total += (factor - 1.0) * cost
	return total


## The multiplier `a_modifier` applies: its factor as authored, or, for a reach, the new reach
## over the reach `a_sample` has today (upgrades already owned included), so a second range
## upgrade is priced on what it still adds.
func _factor_of(a_modifier: Dictionary, a_sample: Entity) -> float:
	for key: StringName in [
		UpgradeCatalog.HP_FACTOR,
		UpgradeCatalog.REARM_RATE_FACTOR,
		UpgradeCatalog.COOLDOWN_RATE_FACTOR
	]:
		if a_modifier.has(key):
			return float(a_modifier[key])
	if a_modifier.has("range"):
		var ability: StringName = StringName(str(a_modifier.get("ability", "")))
		var current: float = AbilityCatalog.range_for(ability, a_sample)
		return float(a_modifier["range"]) / current if current > 0.0 else 1.0
	return 1.0


func _worth_buying(a_upgrade: StringName, a_value: float) -> bool:
	var cost: int = _bot.unit_cost(a_upgrade)
	if a_value < float(cost) * tech_value_margin:
		return false
	return _bot.can_afford(a_upgrade) and _bot.energy - cost >= reserve


static func _best(a_scores: Dictionary) -> StringName:
	var best: StringName = &""
	var best_score: float = -INF
	for id: StringName in a_scores:
		if float(a_scores[id]) > best_score:
			best_score = float(a_scores[id])
			best = id
	return best
