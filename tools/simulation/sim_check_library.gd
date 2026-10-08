class_name SimCheckLibrary
extends RefCounted

## The check vocabulary: one [SimSpec.Check] plus a [SimGroupRoster] in, a `() -> bool`
## predicate out, for [SimulationCheck] to fold.
##
## A NEW CHECK IS A NEW ROW, never a new branch (`~/.claude/CLAUDE.md` §1.2). The names and
## their arguments are declared once in `SimSpec.CHECK_ARGUMENTS` — which is what validates a
## spec — and implemented once in `_BUILDERS` here. The two tables must name the same set;
## `tests/test_SimSpec.gd` asserts that they do, because a check that validates and then has
## no implementation would abort a run halfway through rather than refuse it up front.
##
## ONE RULE ACROSS THE WHOLE VOCABULARY: a check about the STATE of members is false when
## there are no members left to be in that state. "Above half health" is not vacuously true
## of a group that is dead, and a run where the subject was destroyed must not pass a claim
## about how well it was doing. The exceptions are `alive` and `dead`, which are claims about
## the COUNT itself and are answered from the spawn roster rather than from survivors.

#region Vocabulary
## check name -> `func(a_check: SimSpec.Check, a_roster: SimGroupRoster) -> Callable`
static var _BUILDERS: Dictionary = {
	"alive": SimCheckLibrary._build_alive,
	"dead": SimCheckLibrary._build_dead,
	"hp_fraction": SimCheckLibrary._build_hp_fraction,
	"owner": SimCheckLibrary._build_owner,
	"distance_to": SimCheckLibrary._build_distance_to,
	"command": SimCheckLibrary._build_command,
	"idle": SimCheckLibrary._build_idle,
	"garrisoned_in": SimCheckLibrary._build_garrisoned_in,
	"hit_rate": SimCheckLibrary._build_hit_rate,
	"posture": SimCheckLibrary._build_posture,
	"objective": SimCheckLibrary._build_objective,
	"ordered": SimCheckLibrary._build_ordered,
	"refused": SimCheckLibrary._build_refused,
	"chosen": SimCheckLibrary._build_chosen,
	"considered": SimCheckLibrary._build_considered,
	"claimed": SimCheckLibrary._build_claimed,
	"believes": SimCheckLibrary._build_believes,
}
## check name -> `func(a_check, a_roster) -> Callable`, for the checks that also REPORT what
## they measured (`() -> String`), beyond passing or failing.
static var _MEASURES: Dictionary = {
	"hit_rate": SimCheckLibrary._measure_hit_rate,
}


## Every check name that has an implementation here.
static func implemented_names() -> Array[String]:
	var names: Array[String] = []
	names.assign(SimCheckLibrary._BUILDERS.keys())
	names.sort()
	return names


## Compile one parsed leaf into the predicate a SimulationCheck folds. A name with no builder
## is a bug in this file rather than in the spec — validation has already rejected unknown
## names — so it fails loudly and evaluates false rather than passing quietly.
static func predicate(a_check: SimSpec.Check, a_roster: SimGroupRoster) -> Callable:
	if not SimCheckLibrary._BUILDERS.has(a_check.name):
		push_error("SimCheckLibrary has no implementation for check '%s'" % a_check.name)
		return func() -> bool: return false
	var builder: Callable = SimCheckLibrary._BUILDERS[a_check.name]
	return builder.call(a_check, a_roster)


## What a leaf measured, as `() -> String`, for the run report; an empty Callable for a check
## that reports only its verdict.
static func measurement(a_check: SimSpec.Check, a_roster: SimGroupRoster) -> Callable:
	if not SimCheckLibrary._MEASURES.has(a_check.name):
		return Callable()
	var builder: Callable = SimCheckLibrary._MEASURES[a_check.name]
	return builder.call(a_check, a_roster)


#endregion


#region Counting
## Compare `a_actual` against the leaf's count constraint. With no constraint authored, the
## claim is about EVERY member of the selection, so the requirement is `a_total`.
static func _count_holds(a_check: SimSpec.Check, a_actual: int, a_total: int) -> bool:
	var arguments: Dictionary = a_check.arguments
	if arguments.has("exactly"):
		return a_actual == int(arguments["exactly"])
	if arguments.has("at_least") and a_actual < int(arguments["at_least"]):
		return false
	if arguments.has("at_most") and a_actual > int(arguments["at_most"]):
		return false
	if arguments.has("at_least") or arguments.has("at_most"):
		return true
	return a_actual == a_total


#endregion


#region Builders
static func _build_alive(a_check: SimSpec.Check, a_roster: SimGroupRoster) -> Callable:
	return func() -> bool:
		var total: int = a_roster.spawned_count(a_check.group_ref, a_check.piece)
		var alive: int = a_roster.living(a_check.group_ref, a_check.piece).size()
		return SimCheckLibrary._count_holds(a_check, alive, total)


static func _build_dead(a_check: SimSpec.Check, a_roster: SimGroupRoster) -> Callable:
	return func() -> bool:
		var total: int = a_roster.spawned_count(a_check.group_ref, a_check.piece)
		var dead: int = a_roster.dead_count(a_check.group_ref, a_check.piece)
		return SimCheckLibrary._count_holds(a_check, dead, total)


## Every living member is within the authored band of its own hp_max. Per-member rather than
## pooled: "the squad averaged half health" hides one casualty behind four untouched units,
## and the claim a spec makes is about the units it named.
static func _build_hp_fraction(a_check: SimSpec.Check, a_roster: SimGroupRoster) -> Callable:
	return func() -> bool:
		var alive: Array = a_roster.living(a_check.group_ref, a_check.piece)
		if alive.is_empty():
			return false
		for entity: Actor in alive:
			if entity.defense == null or entity.defense.hp_max <= 0.0:
				continue  # nothing to measure; a piece with no Defense cannot be hurt
			var fraction: float = entity.defense.hp / entity.defense.hp_max
			if (
				a_check.arguments.has("at_least")
				and fraction < float(a_check.arguments["at_least"])
			):
				return false
			if a_check.arguments.has("at_most") and fraction > float(a_check.arguments["at_most"]):
				return false
		return true


static func _build_owner(a_check: SimSpec.Check, a_roster: SimGroupRoster) -> Callable:
	var wanted: String = str(a_check.arguments.get("is", ""))
	return func() -> bool:
		var alive: Array = a_roster.living(a_check.group_ref, a_check.piece)
		if alive.is_empty():
			return false
		for entity: Actor in alive:
			if a_roster.slot_of(entity.commander_id) != wanted:
				return false
		return true


static func _build_distance_to(a_check: SimSpec.Check, a_roster: SimGroupRoster) -> Callable:
	var other: String = str(a_check.arguments.get("target", ""))
	return func() -> bool:
		var here: Variant = a_roster.centroid(a_check.group_ref, a_check.piece)
		var there: Variant = a_roster.centroid(other)
		if here == null or there == null:
			return false
		var apart: float = VU.in_xz(here as Vector3).distance_to(VU.in_xz(there as Vector3))
		if a_check.arguments.has("at_least") and apart < float(a_check.arguments["at_least"]):
			return false
		if a_check.arguments.has("at_most") and apart > float(a_check.arguments["at_most"]):
			return false
		return true


## Every living member's current order is the named command — and, when asked, is aimed at a
## piece of `target`, or has its destination within `within` of `near`'s centroid. The
## target and destination are read off the live order (decision-sims.md §Identity in a
## check): an order issued and finished between two polls is invisible, which no real
## order is.
static func _build_command(a_check: SimSpec.Check, a_roster: SimGroupRoster) -> Callable:
	var wanted: String = str(a_check.arguments.get("is", ""))
	var target_ref: String = str(a_check.arguments.get("target", ""))
	var near_ref: String = str(a_check.arguments.get("near", ""))
	var within: float = float(a_check.arguments.get("within", 0.0))
	return func() -> bool:
		var alive: Array = a_roster.living(a_check.group_ref, a_check.piece)
		if alive.is_empty():
			return false
		var target_ids: Array = a_roster.member_ids(target_ref) if target_ref != "" else []
		var there: Variant = a_roster.centroid(near_ref) if near_ref != "" else null
		for entity: Actor in alive:
			var command: MoveCommand = entity.current_command()
			if command == null or SimCheckLibrary._command_name(command) != wanted:
				return false
			if target_ref != "":
				var aimed: Variant = command.message.target
				if aimed == null or not is_instance_valid(aimed):
					return false
				if not target_ids.has((aimed as Object).get_instance_id()):
					return false
			if near_ref != "":
				if there == null:
					return false
				var destination: Vector2 = VU.in_xz(command.message.position)
				if destination.distance_to(VU.in_xz(there as Vector3)) > within:
					return false
		return true


static func _build_idle(a_check: SimSpec.Check, a_roster: SimGroupRoster) -> Callable:
	return func() -> bool:
		var alive: Array = a_roster.living(a_check.group_ref, a_check.piece)
		if alive.is_empty():
			return false
		for entity: Actor in alive:
			if entity.has_command():
				return false
		return true


static func _build_garrisoned_in(a_check: SimSpec.Check, a_roster: SimGroupRoster) -> Callable:
	var host_ref: String = str(a_check.arguments.get("host", ""))
	return func() -> bool:
		var alive: Array = a_roster.living(a_check.group_ref, a_check.piece)
		if alive.is_empty():
			return false
		var hosts: Array = a_roster.living(host_ref)
		if hosts.is_empty():
			return false
		for entity: Actor in alive:
			if not entity.is_garrisoned():
				return false
			# A Garrison is a component child, so the host is its parent.
			if not hosts.has(entity.garrisoned_in.get_parent()):
				return false
		return true


## Of the shots the group fired that have settled, the fraction that landed on the target group
## lies in the authored band. Shots still in flight count for nothing, and a run that settled no
## shot at all fails: a hit rate measured over nothing is not a hit rate.
## (simulation-tests.md §Counting shots)
static func _build_hit_rate(a_check: SimSpec.Check, a_roster: SimGroupRoster) -> Callable:
	return func() -> bool:
		var tally: Vector2i = SimCheckLibrary._hit_tally(a_check, a_roster)
		if tally.y == 0:
			return false
		var rate: float = float(tally.x) / float(tally.y)
		if a_check.arguments.has("at_least") and rate < float(a_check.arguments["at_least"]):
			return false
		if a_check.arguments.has("at_most") and rate > float(a_check.arguments["at_most"]):
			return false
		return true


static func _measure_hit_rate(a_check: SimSpec.Check, a_roster: SimGroupRoster) -> Callable:
	return func() -> String:
		var tally: Vector2i = SimCheckLibrary._hit_tally(a_check, a_roster)
		return "%d of %d shots hit" % [tally.x, tally.y]


static func _hit_tally(a_check: SimSpec.Check, a_roster: SimGroupRoster) -> Vector2i:
	var target_ids: Array = a_roster.member_ids(str(a_check.arguments.get("target", "")))
	return a_roster.shots.tally(a_check.group_ref, a_check.piece, target_ids)


#endregion

#region Bot-state builders
## What a thinking slot decided, read from its own records (gdd/systems/ai/decision-sims.md
## §Bot-state checks). A slot whose brain has not built its managers yet answers false: the
## decision has not been made, and a check about it should not pass by default.


static func _build_posture(a_check: SimSpec.Check, a_roster: SimGroupRoster) -> Callable:
	var wanted: String = str(a_check.arguments.get("is", ""))
	return func() -> bool:
		var military: BotMilitary = SimCheckLibrary._military_of(a_roster, a_check.slot)
		if military == null:
			return false
		return BotMilitary.Posture.keys()[military.current_posture()] == wanted


## The army's objective lies within `within` of `near`'s centroid.
static func _build_objective(a_check: SimSpec.Check, a_roster: SimGroupRoster) -> Callable:
	var near_ref: String = str(a_check.arguments.get("near", ""))
	var within: float = float(a_check.arguments.get("within", 0.0))
	return func() -> bool:
		var military: BotMilitary = SimCheckLibrary._military_of(a_roster, a_check.slot)
		if military == null:
			return false
		var objective: Variant = military.current_objective()
		var there: Variant = a_roster.centroid(near_ref)
		if objective == null or there == null:
			return false
		return VU.in_xz(objective as Vector3).distance_to(VU.in_xz(there as Vector3)) <= within


## The actuator has ISSUED at least `at_least` (default 1) orders of `kind` for `piece`
## ("" matches any piece of that kind) — BotUsageLog.actions, a ledger by type.
static func _build_ordered(a_check: SimSpec.Check, a_roster: SimGroupRoster) -> Callable:
	return SimCheckLibrary._build_action_count(a_check, a_roster, BotUsageLog.OUTCOME_ISSUED)


## The actuator REFUSED at least `at_least` orders of `kind` for `piece`, with `cause` (a
## MoveCommand.PreconditionFailureCause name) when given, any refusal otherwise.
static func _build_refused(a_check: SimSpec.Check, a_roster: SimGroupRoster) -> Callable:
	var cause: String = str(a_check.arguments.get("cause", ""))
	var outcome: String = BotUsageLog.OUTCOME_REFUSED_PREFIX + cause
	return SimCheckLibrary._build_action_count(a_check, a_roster, outcome)


static func _build_action_count(
	a_check: SimSpec.Check, a_roster: SimGroupRoster, a_outcome: String
) -> Callable:
	var kind: String = str(a_check.arguments.get("kind", ""))
	var wanted: int = int(a_check.arguments.get("at_least", 1))
	return func() -> bool:
		var log: BotUsageLog = SimCheckLibrary._usage_of(a_roster, a_check.slot)
		if log == null:
			return false
		var rows: Dictionary = log.actions().get(kind, {})
		var count: int = 0
		for type: String in rows:
			if a_check.piece != "" and type != a_check.piece:
				continue
			for outcome: String in rows[type]:
				if (
					outcome == a_outcome
					or (
						a_outcome == BotUsageLog.OUTCOME_REFUSED_PREFIX
						and outcome.begins_with(BotUsageLog.OUTCOME_REFUSED_PREFIX)
					)
				):
					count += int(rows[type][outcome])
		return count >= wanted


## `piece` won a scored decision in `domain` at least once — BotUsageLog.choices.
static func _build_chosen(a_check: SimSpec.Check, a_roster: SimGroupRoster) -> Callable:
	return SimCheckLibrary._build_choice_count(a_check, a_roster, "chosen")


## `piece` was SCORED in `domain` at least once, whether or not it won: the "not aware"
## versus "judged not worth it" split of the piece-usage audit.
static func _build_considered(a_check: SimSpec.Check, a_roster: SimGroupRoster) -> Callable:
	return SimCheckLibrary._build_choice_count(a_check, a_roster, "considered")


static func _build_choice_count(
	a_check: SimSpec.Check, a_roster: SimGroupRoster, a_column: String
) -> Callable:
	var domain: String = str(a_check.arguments.get("domain", ""))
	return func() -> bool:
		var log: BotUsageLog = SimCheckLibrary._usage_of(a_roster, a_check.slot)
		if log == null:
			return false
		var rows: Dictionary = log.choices().get(domain, {})
		var row: Dictionary = rows.get(a_check.piece, {})
		return int(row.get(a_column, 0)) > 0


## Every living member is held by `holder` (a manager's claim owner name) in its own bot's
## claims registry.
static func _build_claimed(a_check: SimSpec.Check, a_roster: SimGroupRoster) -> Callable:
	var holder: StringName = StringName(str(a_check.arguments.get("holder", "")))
	return func() -> bool:
		var alive: Array = a_roster.living(a_check.group_ref, a_check.piece)
		if alive.is_empty():
			return false
		for entity: Actor in alive:
			var brain: BotBrain = a_roster.brain_of(a_roster.slot_of(entity.commander_id))
			if brain == null or brain.claims.owner_of(entity) != holder:
				return false
		return true


## `slot` BELIEVES that many members of `of` — the blackboard, not the scene — with the
## count semantics of `alive` (no argument: all of them).
static func _build_believes(a_check: SimSpec.Check, a_roster: SimGroupRoster) -> Callable:
	return func() -> bool:
		var bot: Bot = a_roster.bot_of(a_check.slot)
		if bot == null or bot.blackboard == null:
			return false
		var ids: Array = a_roster.member_ids(a_check.group_ref)
		var believed: int = 0
		for id: int in ids:
			if bot.blackboard.believes(id):
				believed += 1
		return SimCheckLibrary._count_holds(a_check, believed, ids.size())


static func _military_of(a_roster: SimGroupRoster, a_slot: String) -> BotMilitary:
	var brain: BotBrain = a_roster.brain_of(a_slot)
	return brain.get_military() if brain != null else null


static func _usage_of(a_roster: SimGroupRoster, a_slot: String) -> BotUsageLog:
	var brain: BotBrain = a_roster.brain_of(a_slot)
	if brain == null:
		return null
	var actuator: BotActuator = brain.get_actuator()
	return actuator.usage if actuator != null else null


#endregion


#region Internal
## The runtime class_name of a command instance (e.g. "Attack"), or "".
static func _command_name(a_command: MoveCommand) -> String:
	var script: Script = a_command.get_script()
	return String(script.get_global_name()) if script != null else ""
#endregion
