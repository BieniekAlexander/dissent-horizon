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
## How many of the latest choices `recent_choices` keeps: a screenful for the debug overlay.
const RECENT_CHOICE_COUNT: int = 8

## domain -> type -> {"considered": int, "chosen": int, "score_sum": float, "best_sum": float}
var _choices: Dictionary = {}
## kind -> type -> outcome -> count
var _actions: Dictionary = {}
## type -> Array of [x, z] where a targeted sanction of that ability was cast.
var _cast_positions: Dictionary = {}
## piece id → the world positions its build orders were issued at (record_build_position).
var _build_positions: Dictionary = {}
## The latest choices, oldest first: [{"domain", "chosen", "chosen_score", "runner_up",
## "runner_up_score"}]. The tables above keep counts and lose which decision came when.
var _recent: Array[Dictionary] = []


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
	_remember(a_domain, a_scores, a_chosen)


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


## Where a build order for `a_type` was ISSUED to stand — the placement decision, which the
## action ledger counts but cannot locate. A decision sim's `placed` check reads these.
func record_build_position(a_type: StringName, a_world: Vector3) -> void:
	var positions: Array = _build_positions.get(String(a_type), [])
	positions.append(a_world)
	_build_positions[String(a_type)] = positions


## Every issued build position of `a_type`, oldest first; every type's with "".
func build_positions(a_type: String = "") -> Array:
	if a_type != "":
		return _build_positions.get(a_type, []).duplicate()
	var all: Array = []
	for type: String in _build_positions:
		all.append_array(_build_positions[type])
	return all


## The latest choices, oldest first — see `_recent`.
func recent_choices() -> Array[Dictionary]:
	return _recent.duplicate()


func _remember(a_domain: String, a_scores: Dictionary, a_chosen: StringName) -> void:
	var runner_up: String = ""
	var runner_up_score: float = -INF
	var chosen_score: float = 0.0
	# Compared as Strings: a scorer may key by String or StringName, which index apart.
	for type: Variant in a_scores:
		if String(type) == String(a_chosen):
			chosen_score = float(a_scores[type])
		elif float(a_scores[type]) > runner_up_score:
			runner_up = String(type)
			runner_up_score = float(a_scores[type])
	(
		_recent
		. append(
			{
				"domain": a_domain,
				"chosen": String(a_chosen),
				"chosen_score": chosen_score,
				"runner_up": runner_up,
				"runner_up_score": runner_up_score if runner_up != "" else 0.0,
			}
		)
	)
	if _recent.size() > RECENT_CHOICE_COUNT:
		_recent.remove_at(0)


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
