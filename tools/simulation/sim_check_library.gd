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
		for entity: Commandable in alive:
			if entity.defense == null or entity.defense.hp_max <= 0.0:
				continue  # nothing to measure; a piece with no Defense cannot be hurt
			var fraction: float = entity.defense.hp / entity.defense.hp_max
			if a_check.arguments.has("at_least") \
					and fraction < float(a_check.arguments["at_least"]):
				return false
			if a_check.arguments.has("at_most") \
					and fraction > float(a_check.arguments["at_most"]):
				return false
		return true


static func _build_owner(a_check: SimSpec.Check, a_roster: SimGroupRoster) -> Callable:
	var wanted: String = str(a_check.arguments.get("is", ""))
	return func() -> bool:
		var alive: Array = a_roster.living(a_check.group_ref, a_check.piece)
		if alive.is_empty():
			return false
		for entity: Commandable in alive:
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
		var apart: float = VU.inXZ(here as Vector3).distance_to(VU.inXZ(there as Vector3))
		if a_check.arguments.has("at_least") and apart < float(a_check.arguments["at_least"]):
			return false
		if a_check.arguments.has("at_most") and apart > float(a_check.arguments["at_most"]):
			return false
		return true


static func _build_command(a_check: SimSpec.Check, a_roster: SimGroupRoster) -> Callable:
	var wanted: String = str(a_check.arguments.get("is", ""))
	return func() -> bool:
		var alive: Array = a_roster.living(a_check.group_ref, a_check.piece)
		if alive.is_empty():
			return false
		for entity: Commandable in alive:
			var command: MoveCommand = entity.current_command()
			if command == null or SimCheckLibrary._command_name(command) != wanted:
				return false
		return true


static func _build_idle(a_check: SimSpec.Check, a_roster: SimGroupRoster) -> Callable:
	return func() -> bool:
		var alive: Array = a_roster.living(a_check.group_ref, a_check.piece)
		if alive.is_empty():
			return false
		for entity: Commandable in alive:
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
		for entity: Commandable in alive:
			if not entity.is_garrisoned():
				return false
			# A Garrison is a component child, so the host is its parent.
			if not hosts.has(entity.garrisoned_in.get_parent()):
				return false
		return true
#endregion


#region Internal
## The runtime class_name of a command instance (e.g. "Attack"), or "".
static func _command_name(a_command: MoveCommand) -> String:
	var script: Script = a_command.get_script()
	return String(script.get_global_name()) if script != null else ""
#endregion
