class_name BotUsageLog
extends RefCounted

## WHAT THE BOT CONSIDERED, CHOSE, ORDERED AND WAS REFUSED, counted per piece — the record
## the piece-usage audit reads (gdd/systems/ai/piece-usage-audit.md).
##
## Two tables, because "the bot never fields X" has two different causes that look the same
## from outside:
##   * CHOICES — every scored decision over a set of piece types, with each candidate's score
##     and which one won. A piece that is CONSIDERED but never CHOSEN is one the bot's own
##     valuation ranks below its alternatives: a balance question, or a scorer question. A
##     piece that is never considered at all is one no module scores: a signalling gap.
##   * ACTIONS — every order the actuator issued or refused, by kind and piece. A piece the
##     bot CHOSE and was REFUSED is an actuation bug, and the refusal cause says which.
##
## A ledger is state by definition; this one exists only to be read out at the end of a match
## (tools/selfplay/run_match.gd) and never feeds a decision. Owned by BotActuator, the one
## surface every order passes through, so no module can act without being counted.

const OUTCOME_ISSUED: String = "issued"
const OUTCOME_REFUSED_PREFIX: String = "refused:"

## domain -> type -> {"considered": int, "chosen": int, "score_sum": float, "best_sum": float}
var _choices: Dictionary = {}
## kind -> type -> outcome -> count
var _actions: Dictionary = {}
## type -> Array of [x, z] where a targeted sanction of that ability was cast.
var _cast_positions: Dictionary = {}


## One scored decision in `a_domain` over `a_scores` (type -> score); `a_chosen` is the
## winner, or "" when nothing was taken. Recording the best score beside each candidate's is
## what lets the audit say HOW FAR below the winner a piece sat, not only that it lost.
func record_choice(a_domain: String, a_scores: Dictionary, a_chosen: StringName) -> void:
	var best: float = -INF
	for type: Variant in a_scores:
		best = maxf(best, float(a_scores[type]))
	var domain: Dictionary = _choices.get(a_domain, {})
	for type: Variant in a_scores:
		var row: Dictionary = domain.get(
			String(type), {"considered": 0, "chosen": 0, "score_sum": 0.0, "best_sum": 0.0}
		)
		row["considered"] += 1
		row["score_sum"] += float(a_scores[type])
		row["best_sum"] += best
		if String(type) == String(a_chosen):
			row["chosen"] += 1
		domain[String(type)] = row
	_choices[a_domain] = domain


## One order of `a_kind` concerning `a_type` ("" for an order about no piece in particular,
## such as an attack-move), with its outcome: OUTCOME_ISSUED, or the refusal cause.
func record_action(a_kind: String, a_type: StringName, a_outcome: String) -> void:
	var kind: Dictionary = _actions.get(a_kind, {})
	var row: Dictionary = kind.get(String(a_type), {})
	row[a_outcome] = int(row.get(a_outcome, 0)) + 1
	kind[String(a_type)] = row
	_actions[a_kind] = kind


## Where a targeted cast of `a_ability` landed. The audit's "is the bot aiming at the same
## spot every time" reads the spread of these.
func record_cast_position(a_ability: StringName, a_world: Vector3) -> void:
	var positions: Array = _cast_positions.get(String(a_ability), [])
	positions.append([snappedf(a_world.x, 0.01), snappedf(a_world.z, 0.01)])
	_cast_positions[String(a_ability)] = positions


static func refused(a_cause: MoveCommand.PreconditionFailureCause) -> String:
	return OUTCOME_REFUSED_PREFIX + MoveCommand.PreconditionFailureCause.keys()[a_cause]


func choices() -> Dictionary:
	return _choices


func actions() -> Dictionary:
	return _actions


## Everything, as plain dictionaries and arrays a JSON writer takes as is.
func summary() -> Dictionary:
	return {
		"choices": _choices.duplicate(true),
		"actions": _actions.duplicate(true),
		"cast_positions": _cast_positions.duplicate(true),
	}
