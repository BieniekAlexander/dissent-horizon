class_name BotSavings
extends RefCounted

## THE SHARED SAVINGS GOAL (Alex, 2026-10-07): the one purchase the bot is saving for, and the
## claim it holds on the bank. Every manager that spends proposes the best thing it WANTS,
## affordable or not, on one scale — strength per energy (Bot.unit_composition_value) of the
## unit it is, or of the best unit a building would unlock — and the best proposal is the goal.
## A spend that is not the goal may go ahead only if it leaves the goal's price banked.
##
## Without it each producer bought whatever it could afford the moment it could, and nothing
## dear was ever bought: five barracks of 100-energy Recruits kept the balance below a
## 1200-energy war factory, a 500-energy vehicle and every tech structure, all match.
##
## One goal at a time, so the bot cannot freeze saving for everything. The claim is lifted
## while the base is under threat (`held`), so a bot saving for a tech building still trains
## the units that defend it.

## Source (a manager's name) -> {"type": StringName, "value": float, "cost": int}: each
## manager's latest proposal, replaced every time it thinks.
var _proposals: Dictionary = {}
## False while the claim is suspended. Set by whoever decides that, every think.
var held: bool = true


## Replace `a_source`'s proposal: `a_type` (&"" withdraws it), worth `a_value`, costing
## `a_cost` energy. `a_demanded` marks a purchase wanted for the WORK it does rather than for a
## value it scored — a siege gun while the bot has spotting to use it with — which outranks a
## valued purchase of equal value (Alex, 2026-10-10: a demand is "I need this to use what I
## own", a value is "this would be nice"). A demand has no value on the purchase scale by
## construction, so it is proposed at the best trainable unit's and would otherwise lose every
## tie to the dearer producer.
func propose(
	a_source: StringName, a_type: StringName, a_value: float, a_cost: int, a_demanded: bool = false
) -> void:
	if a_type == &"" or a_value <= 0.0:
		_proposals.erase(a_source)
		return
	_proposals[a_source] = {
		"type": a_type, "value": a_value, "cost": a_cost, "demanded": a_demanded
	}


## The goal's type, or &"" while nothing is being saved for. The highest value wins; a tie goes
## to a DEMANDED purchase over a valued one, then to the dearer purchase (it is the one saving
## exists for), then to the type's name.
func goal() -> StringName:
	var best: Dictionary = _best()
	return best["type"] if not best.is_empty() else &""


## How much of the bank `a_type` must leave untouched: the goal's price, unless `a_type` IS the
## goal or the claim is lifted.
func claim_against(a_type: StringName) -> int:
	var best: Dictionary = _best()
	if best.is_empty() or not held or best["type"] == a_type:
		return 0
	return best["cost"]


## Every manager's current proposal, source → {"type", "value", "cost"}. For the debug overlay.
func proposals() -> Dictionary:
	return _proposals.duplicate(true)


## Forget every proposal naming `a_type`: it has been bought.
func spent(a_type: StringName) -> void:
	for source: StringName in _proposals.keys():
		if _proposals[source]["type"] == a_type:
			_proposals.erase(source)


func _best() -> Dictionary:
	var best: Dictionary = {}
	for proposal: Dictionary in _proposals.values():
		if best.is_empty() or _outranks(proposal, best):
			best = proposal
	return best


static func _outranks(a: Dictionary, b: Dictionary) -> bool:
	if a["value"] != b["value"]:
		return a["value"] > b["value"]
	if bool(a.get("demanded", false)) != bool(b.get("demanded", false)):
		return bool(a.get("demanded", false))
	if a["cost"] != b["cost"]:
		return a["cost"] > b["cost"]
	return String(a["type"]) < String(b["type"])
