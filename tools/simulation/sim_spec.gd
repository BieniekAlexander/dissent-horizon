class_name SimSpec
extends RefCounted

## A parsed, validated simulation-test spec — the PURE half of the simulation framework.
##
## Text in, a validated object graph or a list of errors out. Nothing here touches the
## engine: no Map, no scene tree, no Node. That is what lets the grammar be unit-tested in
## GUT without booting anything, and it is the layering rule the rest of this module follows
## (`~/.claude/CLAUDE.md` §7 — dependencies point inward).
##
## The grammar itself, and the reasoning behind every rule below, is
## gdd/systems/scenario-scripting/simulation-tests.md. This file is its implementation, not
## its documentation: where the two disagree the note is authoritative and this is a bug.
##
## VALIDATION IS TOTAL AND LOUD. Every problem found is appended to `errors` and the spec
## reports invalid; nothing is guessed at, defaulted around, or fuzzy-matched. A spec that
## silently measured something other than what it says would be worse than one that refuses
## to run.

#region Vocabulary
## Compass anchors, resolved against the arena's extent by the builder rather than here —
## this layer only needs to know which names are legal and which way each one points.
## Unit vectors on the XZ plane, +X east and +Z south (the grid's origin is top-left).
const ANCHOR_DIRECTIONS: Dictionary = {
	"center": Vector2(0, 0),
	"north": Vector2(0, -1),
	"south": Vector2(0, 1),
	"east": Vector2(1, 0),
	"west": Vector2(-1, 0),
	"northeast": Vector2(0.70710678, -0.70710678),
	"northwest": Vector2(-0.70710678, -0.70710678),
	"southeast": Vector2(0.70710678, 0.70710678),
	"southwest": Vector2(-0.70710678, 0.70710678),
}

## Commands a spec may issue, mapped to what their `target:` NAMES — an entity, or a place.
## `MoveCommand.requires_position()` already draws that line in the engine; this table names
## which side each command falls on so an order can be validated without instantiating
## anything.
##
## Every order names its argument with the SAME two keys, whatever the command:
##   `target:`  the thing, or the exact place, the order is aimed at
##   `near:`    a place beside that thing rather than on it — positional commands only
## One vocabulary rather than one key per command, so a reader never has to remember which
## word this particular verb wanted.
const COMMAND_ARGUMENTS: Dictionary = {
	"attack": ARG_TARGET,
	"attack_move": ARG_POSITION,
	"move": ARG_POSITION,
	"defend": ARG_POSITION,
	"stop": ARG_NONE,
}

const ARG_NONE: int = 0
const ARG_TARGET: int = 1
const ARG_POSITION: int = 2

## Formations a group may be arranged in. Realised by the builder against the same helpers
## the game's own opening forces use.
const FORMATIONS: Array[String] = ["line", "ring", "cluster"]

## How a single entity is chosen out of a group that holds several.
const PICKS: Array[String] = ["nearest", "furthest", "first"]

## Difficulty tier names, matching PlayerSlot.Difficulty. Spelled here rather than reflected
## off the enum so this file stays free of engine types.
const DIFFICULTIES: Array[String] = ["PASSIVE", "EASY", "MEDIUM", "HARD", "IMPOSSIBLE"]

## Every check name and the argument keys it accepts beyond the universal `of` / `piece` /
## `when` / `by`. A new check is a new ROW here and a new row in SimCheckLibrary — never a
## new branch (§1.2).
const CHECK_ARGUMENTS: Dictionary = {
	"alive": ["exactly", "at_least", "at_most"],
	"dead": ["exactly", "at_least", "at_most"],
	"hp_fraction": ["at_least", "at_most"],
	"owner": ["is"],
	"distance_to": ["target", "at_least", "at_most"],
	"command": ["is"],
	"idle": [],
	"garrisoned_in": ["host"],
}
#endregion

#region Inner types
## Where something stands, without ever naming a world coordinate. Either a bare anchor, or
## an offset of `distance` world units along `bearing` from `from` (an anchor or a group).
class Placement:
	extends RefCounted
	var anchor: String = ""       ## set when this is a bare anchor
	var from_ref: String = ""     ## a group reference ("A.armyA") or an anchor name
	var bearing: String = ""      ## an anchor name used as a compass direction
	var distance_units: float = 0.0

	func is_relative() -> bool:
		return from_ref != ""


## One `{ piece, count }` entry of a group's `of:` list.
class Composition:
	extends RefCounted
	var piece: String = ""
	var count: int = 1


## The entity-valued argument of an order: a group, optionally narrowed to one piece type,
## optionally reduced to a single entity by `pick`. With no `pick` the whole (filtered) set
## is the target and the order expands to one command per member.
class TargetRef:
	extends RefCounted
	var group_ref: String = ""
	var piece: String = ""
	var pick: String = ""

	func picks_one() -> bool:
		return pick != ""


## One command issued to every member of a group at t=0.
class Order:
	extends RefCounted
	var command: String = ""
	## Set for an entity-valued command: the group whose members are the targets.
	var target: TargetRef = null
	## Set for a positional command: where it is aimed.
	var position: Placement = null
	## Positional commands only: `near:` was written rather than `target:`, so the order
	## stops at the referenced group's EDGE instead of driving onto its centre.
	var approaches: bool = false


## A named set of entities belonging to one commander — the unit of ordering, targeting and
## assertion.
class Group:
	extends RefCounted
	var slot: String = ""
	var name: String = ""
	var composition: Array[Composition] = []
	var placement: Placement = null
	var facing: String = ""           ## an anchor name or a group reference
	var formation: String = ""
	var orders: Array[Order] = []

	## "A.armyA" — the qualified form every reference uses.
	func qualified_name() -> String:
		return "%s.%s" % [slot, name]

	func total_count() -> int:
		var total: int = 0
		for c: Composition in composition:
			total += c.count
		return total


## One commander slot's own configuration. Groups live under `with`, never here.
class CommanderSettings:
	extends RefCounted
	var difficulty: String = "PASSIVE"
	var faction: String = ""


## One leaf of the expectation tree: a predicate over a group, plus the temporal FOLD that
## turns its per-tick truth into a single verdict.
##
## The three modes are one mechanism — an operator and a window (see the note, §A leaf
## carries the temporal mode) — so they are stored as exactly that.
class Check:
	extends RefCounted
	enum Mode { AT_END, LIVENESS, SAFETY }

	var group_ref: String = ""
	var piece: String = ""
	var name: String = ""
	var arguments: Dictionary = {}
	var mode: Mode = Mode.AT_END
	var deadline_seconds: float = 0.0   ## LIVENESS only

	## What this leaf claims, for the run report. Derived rather than authored: a
	## description a reader has to keep in step with the check is a description that drifts.
	func describe() -> String:
		var detail: String = ""
		for key: String in arguments:
			detail += " %s=%s" % [key, arguments[key]]
		var subject: String = group_ref if piece == "" else "%s[%s]" % [group_ref, piece]
		match mode:
			Mode.LIVENESS:
				return "%s %s%s by %.1fs" % [subject, name, detail, deadline_seconds]
			Mode.SAFETY:
				return "%s %s%s always" % [subject, name, detail]
			_:
				return "%s %s%s at end" % [subject, name, detail]


## A node of the boolean tree over leaves. The tree is evaluated ONCE, at the end of a run,
## over verdicts each leaf has already folded for itself.
class ExpectNode:
	extends RefCounted
	enum Kind { LEAF, ALL, ANY, NOT }

	var kind: Kind = Kind.LEAF
	var check: Check = null
	var children: Array[ExpectNode] = []

	## Every leaf under this node, in authored order — what the run report lists and what
	## the evaluator arms.
	func leaves() -> Array[Check]:
		if kind == Kind.LEAF:
			return [check] as Array[Check]
		var found: Array[Check] = []
		for child: ExpectNode in children:
			found.append_array(child.leaves())
		return found

	## Fold the tree over already-resolved leaf verdicts, keyed by leaf object.
	func resolve(a_verdicts: Dictionary) -> bool:
		match kind:
			Kind.LEAF:
				return a_verdicts.get(check, false)
			Kind.NOT:
				return not children[0].resolve(a_verdicts)
			Kind.ANY:
				for child: ExpectNode in children:
					if child.resolve(a_verdicts):
						return true
				return false
			_:
				for child: ExpectNode in children:
					if not child.resolve(a_verdicts):
						return false
				return true
#endregion

#region Properties
var id: String = ""                     ## the file name, which IS the test id
var description: String = ""
var arena_kind: String = "flat"
var arena_size_cells: int = 30
var run_seconds: float = 0.0
## The seed for THIS ONE RUN. -1 means the spec named none and the runner draws one; a spec
## never carries a sampling policy (see the note, §One spec is one run).
var seed_value: int = -1
var commanders: Dictionary = {}         ## slot name -> CommanderSettings
var groups: Dictionary = {}             ## "A.armyA" -> Group, in authored order
var expect_root: ExpectNode = null
var errors: Array[String] = []
#endregion

#region Parsing
## Parse spec text. Never throws and never returns null: a spec that could not be read comes
## back with `errors` populated, which is how the runner reports it as a FAILED spec rather
## than skipping it (CLAUDE.md §A skipped test file is invisible).
static func parse(a_text: String, a_id: String = "") -> SimSpec:
	var spec := SimSpec.new()
	spec.id = a_id
	var lines: Array[String] = []
	lines.assign(a_text.split("\n"))
	var parsed: Dictionary = SpecFrontmatter.parse_yaml(lines)
	if not parsed["ok"]:
		spec.errors.append("YAML: %s" % parsed["error"])
		return spec
	spec._read(parsed["data"] as Dictionary)
	return spec


static func parse_file(a_path: String) -> SimSpec:
	var text: String = FileAccess.get_file_as_string(a_path)
	var id: String = a_path.get_file().replace(".sim.yaml", "")
	if text == "" and not FileAccess.file_exists(a_path):
		var spec := SimSpec.new()
		spec.id = id
		spec.errors.append("cannot open %s" % a_path)
		return spec
	return SimSpec.parse(text, id)


func is_valid() -> bool:
	return errors.is_empty()


## Read every block, then run the checks that can only be made once everything is known
## (references, cycles). Order matters: a reference check needs the group table complete.
func _read(a_data: Dictionary) -> void:
	description = str(a_data.get("description", ""))
	_read_setting(a_data.get("setting", {}))
	_read_run(a_data.get("run", {}))
	_read_given(a_data.get("given", {}))
	_read_expect(a_data.get("expect", []))
	_validate_references()
	_validate_placement_cycles()


func _read_setting(a_value: Variant) -> void:
	if not (a_value is Dictionary):
		errors.append("`setting` must be a mapping, e.g. { kind: flat, size: 30 }")
		return
	var setting: Dictionary = a_value
	arena_kind = str(setting.get("kind", "flat"))
	if arena_kind != "flat":
		errors.append("unknown arena kind '%s'; only 'flat' exists" % arena_kind)
	if setting.has("size"):
		arena_size_cells = int(setting["size"])
	if arena_size_cells < 4:
		errors.append("`setting.size` must be at least 4 cells, got %d" % arena_size_cells)
	if setting.has("commanders"):
		errors.append(
			"commander configuration moved under `given.<slot>.settings`; "
			+ "`setting` names the arena and nothing else"
		)


func _read_run(a_value: Variant) -> void:
	if not (a_value is Dictionary):
		errors.append("`run` must be a mapping, e.g. { for: 10s }")
		return
	var run: Dictionary = a_value
	if not run.has("for"):
		errors.append("`run.for` is required — a spec with no window measures nothing")
	else:
		run_seconds = _read_seconds(run["for"], "run.for")
	if run.has("seed"):
		seed_value = int(run["seed"])
	if run.has("trials") or run.has("tolerance"):
		errors.append(
			"`run.trials` / `run.tolerance` are the RUNNER's, not the spec's — "
			+ "a spec describes one run (see simulation-tests.md §One spec is one run)"
		)


## Durations carry their unit: "10s", "2.5s". A bare number is REFUSED rather than assumed
## to be seconds, because the thing it would silently be mistaken for is ticks — and a
## window wrong by a factor of thirty is a spec that passes for the wrong reason.
func _read_seconds(a_value: Variant, a_where: String) -> float:
	var text: String = str(a_value).strip_edges()
	if not text.ends_with("s"):
		errors.append("%s must name its unit in seconds, e.g. `10s` (got '%s')" % [a_where, text])
		return 0.0
	var number: String = text.substr(0, text.length() - 1)
	if not number.is_valid_float():
		errors.append("%s is not a number of seconds: '%s'" % [a_where, text])
		return 0.0
	var seconds: float = number.to_float()
	if seconds <= 0.0:
		errors.append("%s must be positive, got %s" % [a_where, text])
	return seconds


func _read_given(a_value: Variant) -> void:
	if not (a_value is Dictionary) or (a_value as Dictionary).is_empty():
		errors.append("`given` must name at least one commander slot")
		return
	for slot: String in (a_value as Dictionary):
		var body: Variant = (a_value as Dictionary)[slot]
		if not (body is Dictionary):
			errors.append("`given.%s` must be a mapping with a `with` block" % slot)
			continue
		commanders[slot] = _read_settings(slot, (body as Dictionary).get("settings", {}))
		_read_with(slot, (body as Dictionary).get("with", null))
		for key: String in (body as Dictionary):
			if key != "with" and key != "settings":
				errors.append(
					"`given.%s.%s` is neither `with` nor `settings`; groups go under `with`"
					% [slot, key]
				)


func _read_settings(a_slot: String, a_value: Variant) -> CommanderSettings:
	var settings := CommanderSettings.new()
	if not (a_value is Dictionary):
		errors.append("`given.%s.settings` must be a mapping" % a_slot)
		return settings
	var body: Dictionary = a_value
	settings.difficulty = str(body.get("difficulty", "PASSIVE"))
	if not DIFFICULTIES.has(settings.difficulty):
		errors.append(
			"unknown difficulty '%s' for slot %s; one of %s"
			% [settings.difficulty, a_slot, ", ".join(DIFFICULTIES)]
		)
	settings.faction = str(body.get("faction", ""))
	return settings


func _read_with(a_slot: String, a_value: Variant) -> void:
	if not (a_value is Dictionary) or (a_value as Dictionary).is_empty():
		errors.append("`given.%s.with` must name at least one group" % a_slot)
		return
	for name: String in (a_value as Dictionary):
		var group: Group = _read_group(a_slot, name, (a_value as Dictionary)[name])
		if group != null:
			groups[group.qualified_name()] = group


func _read_group(a_slot: String, a_name: String, a_value: Variant) -> Group:
	var where: String = "%s.%s" % [a_slot, a_name]
	if not (a_value is Dictionary):
		errors.append("group `%s` must be a mapping" % where)
		return null
	var body: Dictionary = a_value
	var group := Group.new()
	group.slot = a_slot
	group.name = a_name
	group.composition = _read_composition(where, body.get("of", null))
	group.placement = _read_placement(body.get("at", null), "%s.at" % where)
	group.facing = str(body.get("facing", ""))
	group.formation = str(body.get("formation", ""))
	if group.formation != "" and not FORMATIONS.has(group.formation):
		errors.append(
			"unknown formation '%s' on `%s`; one of %s"
			% [group.formation, where, ", ".join(FORMATIONS)]
		)
	group.orders = _read_orders(where, body.get("orders", []))
	return group


func _read_composition(a_where: String, a_value: Variant) -> Array[Composition]:
	var result: Array[Composition] = []
	if not (a_value is Array) or (a_value as Array).is_empty():
		errors.append("`%s.of` must list at least one { piece, count }" % a_where)
		return result
	for entry: Variant in (a_value as Array):
		if not (entry is Dictionary) or not (entry as Dictionary).has("piece"):
			errors.append("`%s.of` entries must name a `piece`" % a_where)
			continue
		var composition := Composition.new()
		composition.piece = str((entry as Dictionary)["piece"])
		composition.count = int((entry as Dictionary).get("count", 1))
		if composition.count < 1:
			errors.append("`%s.of` count must be at least 1, got %d" % [a_where, composition.count])
		if not SimPieceCatalog.has_piece(composition.piece):
			errors.append("`%s.of` names unknown piece '%s'" % [a_where, composition.piece])
		result.append(composition)
	return result


## An `at:` / `to:` expression: a bare anchor, or `{ from, distance, bearing }`.
func _read_placement(a_value: Variant, a_where: String) -> Placement:
	if a_value == null:
		return null
	var placement := Placement.new()
	if a_value is String or a_value is StringName:
		var name: String = str(a_value)
		if ANCHOR_DIRECTIONS.has(name):
			placement.anchor = name
		else:
			# A bare word that is not an anchor is a group reference used as a position.
			placement.from_ref = name
		return placement
	if not (a_value is Dictionary):
		errors.append("`%s` must be an anchor, a group reference, or a { from, … } offset" % a_where)
		return null
	var body: Dictionary = a_value
	placement.from_ref = str(body.get("from", ""))
	placement.bearing = str(body.get("bearing", ""))
	placement.distance_units = float(body.get("distance", 0.0))
	if placement.from_ref == "":
		errors.append("`%s` names no `from` to offset against" % a_where)
	if placement.bearing != "" and not ANCHOR_DIRECTIONS.has(placement.bearing):
		errors.append(
			"`%s.bearing` must be a compass anchor, got '%s'" % [a_where, placement.bearing]
		)
	if placement.distance_units != 0.0 and placement.bearing == "":
		errors.append("`%s` gives a distance with no bearing to travel along" % a_where)
	return placement


func _read_orders(a_where: String, a_value: Variant) -> Array[Order]:
	var result: Array[Order] = []
	if a_value == null:
		return result
	if not (a_value is Array):
		errors.append("`%s.orders` must be a list" % a_where)
		return result
	for index: int in (a_value as Array).size():
		var entry: Variant = (a_value as Array)[index]
		var order: Order = _read_order("%s.orders[%d]" % [a_where, index], entry)
		if order != null:
			result.append(order)
	return result


func _read_order(a_where: String, a_value: Variant) -> Order:
	if not (a_value is Dictionary) or (a_value as Dictionary).size() != 1:
		errors.append("`%s` must be a single { command: argument } pair" % a_where)
		return null
	var body: Dictionary = a_value
	var order := Order.new()
	order.command = body.keys()[0]
	if not COMMAND_ARGUMENTS.has(order.command):
		errors.append(
			"`%s` names unknown command '%s'; one of %s"
			% [a_where, order.command, ", ".join(PackedStringArray(COMMAND_ARGUMENTS.keys()))]
		)
		return null
	var argument: Variant = body[order.command]
	var kind: int = COMMAND_ARGUMENTS[order.command]
	if kind == ARG_NONE:
		return order
	if not (argument is Dictionary):
		errors.append("`%s` must carry a `target:` or a `near:`" % a_where)
		return order
	var body_arg: Dictionary = argument
	if body_arg.has("to"):
		errors.append(
			"`%s` uses `to:`, which was renamed — a command's argument is `target:` (the thing "
			% a_where + "or exact place) or `near:` (beside it)"
		)
		return order
	var has_target: bool = body_arg.has("target")
	var has_near: bool = body_arg.has("near")
	if has_target and has_near:
		errors.append("`%s` sets both `target:` and `near:`; an order is aimed one way" % a_where)
		return order
	if not has_target and not has_near:
		errors.append("`%s`: %s takes a `target:` or a `near:`" % [a_where, order.command])
		return order
	if kind == ARG_TARGET:
		if has_near:
			errors.append(
				"`%s`: %s names an ENTITY, so it takes `target:` — `near:` is a place"
				% [a_where, order.command]
			)
			return order
		order.target = _read_target(a_where, body_arg["target"])
		return order
	# A positional command: both keys name a place, and `near:` is the one that stops short.
	order.approaches = has_near
	var key: String = "near" if has_near else "target"
	order.position = _read_placement(body_arg[key], "%s.%s" % [a_where, key])
	return order


func _read_target(a_where: String, a_value: Variant) -> TargetRef:
	var target := TargetRef.new()
	if a_value is String or a_value is StringName:
		target.group_ref = str(a_value)
		return target
	if not (a_value is Dictionary):
		errors.append("`%s.target` must be a group reference or an { of, … } selector" % a_where)
		return target
	var body: Dictionary = a_value
	target.group_ref = str(body.get("of", ""))
	target.piece = str(body.get("piece", ""))
	target.pick = str(body.get("pick", ""))
	if target.group_ref == "":
		errors.append("`%s.target` selector names no `of`" % a_where)
	if target.pick != "" and not PICKS.has(target.pick):
		errors.append(
			"`%s.target.pick` must be one of %s, got '%s'"
			% [a_where, ", ".join(PICKS), target.pick]
		)
	return target
#endregion

#region Expectations
func _read_expect(a_value: Variant) -> void:
	if not (a_value is Array) or (a_value as Array).is_empty():
		errors.append("`expect` must list at least one check")
		return
	# The top-level list is an implicit ALL.
	var root := ExpectNode.new()
	root.kind = ExpectNode.Kind.ALL
	for index: int in (a_value as Array).size():
		var node: ExpectNode = _read_expect_node("expect[%d]" % index, (a_value as Array)[index])
		if node != null:
			root.children.append(node)
	expect_root = root


func _read_expect_node(a_where: String, a_value: Variant) -> ExpectNode:
	if not (a_value is Dictionary):
		errors.append("`%s` must be a check or one of all / any / not" % a_where)
		return null
	var body: Dictionary = a_value
	for combinator: String in ["all", "any", "not"]:
		if body.has(combinator):
			return _read_combinator(a_where, combinator, body)
	return _read_leaf(a_where, body)


func _read_combinator(a_where: String, a_name: String, a_body: Dictionary) -> ExpectNode:
	if a_body.size() != 1:
		errors.append("`%s`: `%s` takes only a list of children" % [a_where, a_name])
	var node := ExpectNode.new()
	node.kind = {
		"all": ExpectNode.Kind.ALL,
		"any": ExpectNode.Kind.ANY,
		"not": ExpectNode.Kind.NOT,
	}[a_name]
	var children: Variant = a_body[a_name]
	if not (children is Array) or (children as Array).is_empty():
		errors.append("`%s.%s` must list at least one child" % [a_where, a_name])
		return node
	for index: int in (children as Array).size():
		var child: ExpectNode = _read_expect_node(
			"%s.%s[%d]" % [a_where, a_name, index], (children as Array)[index]
		)
		if child != null:
			node.children.append(child)
	if node.kind == ExpectNode.Kind.NOT and node.children.size() != 1:
		errors.append("`%s.not` takes exactly one child, got %d" % [a_where, node.children.size()])
	return node


func _read_leaf(a_where: String, a_body: Dictionary) -> ExpectNode:
	var check := Check.new()
	check.group_ref = str(a_body.get("of", ""))
	check.piece = str(a_body.get("piece", ""))
	check.name = str(a_body.get("check", ""))
	if check.group_ref == "":
		errors.append("`%s` names no `of`" % a_where)
	if not CHECK_ARGUMENTS.has(check.name):
		errors.append(
			"`%s` names unknown check '%s'; one of %s"
			% [a_where, check.name, ", ".join(PackedStringArray(CHECK_ARGUMENTS.keys()))]
		)
		return null
	_read_leaf_mode(a_where, a_body, check)
	_read_leaf_arguments(a_where, a_body, check)
	var node := ExpectNode.new()
	node.kind = ExpectNode.Kind.LEAF
	node.check = check
	return node


## `when:` and `by:` are the two ways to name a fold, and naming both is a contradiction
## rather than a merge — so it is refused rather than resolved by precedence.
func _read_leaf_mode(a_where: String, a_body: Dictionary, a_check: Check) -> void:
	var has_when: bool = a_body.has("when")
	var has_by: bool = a_body.has("by")
	if has_when and has_by:
		errors.append("`%s` sets both `when` and `by`; a leaf folds one way" % a_where)
		return
	if has_by:
		a_check.mode = Check.Mode.LIVENESS
		a_check.deadline_seconds = _read_seconds(a_body["by"], "%s.by" % a_where)
		return
	if has_when:
		var when: String = str(a_body["when"])
		if when == "always":
			a_check.mode = Check.Mode.SAFETY
		elif when == "at_end":
			a_check.mode = Check.Mode.AT_END
		else:
			errors.append("`%s.when` must be `always` or `at_end`, got '%s'" % [a_where, when])


func _read_leaf_arguments(a_where: String, a_body: Dictionary, a_check: Check) -> void:
	const UNIVERSAL: Array[String] = ["of", "piece", "check", "when", "by"]
	var accepted: Array = CHECK_ARGUMENTS[a_check.name]
	for key: String in a_body:
		if UNIVERSAL.has(key):
			continue
		if not accepted.has(key):
			# `pick` is called out by name because it is the plausible mistake: it belongs to
			# an order's target selector, where choosing ONE entity is meaningful. A check
			# quantifies over a set, so a pick here would silently narrow what is measured.
			if key == "pick":
				errors.append(
					"`%s` uses `pick`, which belongs to an order's target — a check "
					% a_where + "quantifies over the whole selection (use a count argument)"
				)
			else:
				errors.append(
					"`%s`: check '%s' does not take '%s'%s"
					% [
						a_where, a_check.name, key,
						"" if accepted.is_empty() else "; it takes %s" % ", ".join(PackedStringArray(accepted)),
					]
				)
			continue
		a_check.arguments[key] = a_body[key]
#endregion

#region Whole-spec validation
## Every group reference names a group that exists, and every check's `of` does too. Run
## after the whole file is read, because a forward reference is legal.
func _validate_references() -> void:
	for reference: String in groups:
		var group: Group = groups[reference]
		if group.placement != null:
			_require_place_ref(group.placement, "group `%s`.at" % reference)
		if group.facing != "" and not ANCHOR_DIRECTIONS.has(group.facing):
			_require_group(group.facing, "group `%s`.facing" % reference)
		for order: Order in group.orders:
			if order.target != null:
				_require_group(order.target.group_ref, "`%s` order target" % reference)
				if order.target.piece != "" and not SimPieceCatalog.has_piece(order.target.piece):
					errors.append(
						"`%s` order target names unknown piece '%s'"
						% [reference, order.target.piece]
					)
			if order.position != null:
				_require_place_ref(order.position, "`%s` order destination" % reference)
	if expect_root != null:
		for check: Check in expect_root.leaves():
			_require_group(check.group_ref, "check `%s`" % check.name)
			if check.piece != "" and not SimPieceCatalog.has_piece(check.piece):
				errors.append("check `%s` names unknown piece '%s'" % [check.name, check.piece])
			if check.arguments.has("target"):
				_require_group(str(check.arguments["target"]), "check `%s` target" % check.name)
			if check.arguments.has("host"):
				_require_group(str(check.arguments["host"]), "check `%s` host" % check.name)
			if check.arguments.has("is") and check.name == "owner":
				var slot: String = str(check.arguments["is"])
				if not commanders.has(slot):
					errors.append("check `owner` names unknown slot '%s'" % slot)


func _require_place_ref(a_placement: Placement, a_where: String) -> void:
	if a_placement.anchor != "":
		return
	if ANCHOR_DIRECTIONS.has(a_placement.from_ref):
		return
	_require_group(a_placement.from_ref, a_where)


func _require_group(a_reference: String, a_where: String) -> void:
	if a_reference == "":
		return
	if groups.has(a_reference):
		return
	if not a_reference.contains("."):
		errors.append(
			"%s names '%s' unqualified; a group reference is always <slot>.<group>"
			% [a_where, a_reference]
		)
		return
	errors.append("%s names unknown group '%s'" % [a_where, a_reference])


## A group placed relative to a group placed relative to it has no position at all, and the
## builder would recurse forever resolving it. Caught here instead.
func _validate_placement_cycles() -> void:
	for reference: String in groups:
		var seen: Array[String] = []
		var at: String = reference
		while true:
			if seen.has(at):
				errors.append("placement cycle: %s" % " -> ".join(seen + [at]))
				break
			seen.append(at)
			var group: Group = groups.get(at)
			if group == null or group.placement == null or not group.placement.is_relative():
				break
			var next: String = group.placement.from_ref
			if ANCHOR_DIRECTIONS.has(next) or not groups.has(next):
				break
			at = next
#endregion
