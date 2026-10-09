extends Node

## THE COMBAT MODEL'S TRAINING DATA: random fights between two compositions on the sim
## harness's flat arena, one JSON line per fight — each side's piece counts and what was left of
## it, in energy. tools/combat_model/train.py fits the model on these rows.
## gdd/systems/ai/macro-learning.md §1.
##
##   godot --headless --path . --fixed-fps 30 tools/combat_model/generate_fights.tscn -- \
##       out=tools/combat_model/out/fights_0.jsonl count=500 seed=1
##
## Arguments (`key=value` after `--`): `out` (required), `count` (fights, default 100), `seed`
## (default 1; fight k uses seed + k, so shards with disjoint seed ranges never repeat a fight),
## `prefixes` (comma-separated piece-id prefixes forming the pool, default `cl_,an_,tc_`).
##
## Both sides are inert (PASSIVE slots, as every duel spec is) and attack-move across the arena
## at each other, so the outcome is the pieces' stats and nothing a bot decided. A fight ends
## when a side has nothing left alive or the window elapses. Each side is drawn from ONE
## faction (the two sides may differ): a mixed side is reachable in play only by capture and is
## too rare to spend the model's pair budget on (Alex, 2026-10-07).
##
## What these fights cannot see is listed in gdd/systems/ai/macro-learning.md §1: no airfield
## (a charged clip fires once), no abilities a bot would cast, no unarmed pieces, no terrain.

## Arena edge, in cells: room for two clusters to form up and close.
const ARENA_CELLS: int = 60
## Seconds a fight may run; a mismatch that cannot end (nothing can hit air) runs this long.
## 240 since 2026-10-09 (was 90): long enough for a charged aircraft to fly several sorties
## from the airfield below, and for an untouchable aircraft's attrition to show in the margin
## rather than be cut off — the 90 s corpus priced the Sloop at about five Recruits
## (gdd/systems/ai/macro-learning.md §1, what the fights cannot see).
const WINDOW_SECONDS: float = 240.0
## How far behind its army a side's airfield stands, in cells: inside the arena's edge inset
## (SimArena.ANCHOR_INSET leaves a quarter of the half-extent), out of the first volley.
const AIRFIELD_SETBACK_CELLS: int = 4
## Each side's energy budget is drawn from this range...
const BUDGET_MIN: float = 300.0
const BUDGET_MAX: float = 2000.0
## ...and B's is A's times e^u, u uniform in ±this, so even and lopsided fights both appear.
const BUDGET_LOG_SPREAD: float = 0.7
## Distinct piece types per side.
const TYPES_MIN: int = 1
const TYPES_MAX: int = 3
## Bodies per side at most: past this a fight costs more than it teaches.
const MAX_UNITS_PER_SIDE: int = 16
const TECHNOLOGY_JSON: String = "res://resources/generated/technology.json"
const DEFAULT_PREFIXES: String = "cl_,an_,tc_"

var _costs: Dictionary = {}  # piece id -> energy cost
var _pool: Array[String] = []  # armed unit ids the compositions draw from
var _pool_by_faction: Dictionary = {}  # id prefix -> Array[String] of its armed unit ids
## piece id -> whether it flies (an Aerial component): a side with one gets an airfield.
var _flies: Dictionary = {}


func _ready() -> void:
	var arguments: Dictionary = _parse_arguments()
	if not arguments.has("out"):
		push_error("generate_fights: out=<path> is required")
		get_tree().quit(1)
		return
	_costs = _read_costs()
	_pool = _armed_units(str(arguments.get("prefixes", DEFAULT_PREFIXES)).split(","))
	for id: String in _pool:
		var faction: String = id.substr(0, 3)
		if not _pool_by_faction.has(faction):
			_pool_by_faction[faction] = [] as Array[String]
		(_pool_by_faction[faction] as Array[String]).append(id)
	print("[generate_fights] pool of %d armed units: %s" % [_pool.size(), ", ".join(_pool)])
	var file: FileAccess = FileAccess.open(str(arguments["out"]), FileAccess.WRITE)
	var count: int = int(arguments.get("count", "100"))
	var first_seed: int = int(arguments.get("seed", "1"))
	for k: int in count:
		var row: Dictionary = await _fight(first_seed + k)
		file.store_line(JSON.stringify(row))
		file.flush()
		if (k + 1) % 50 == 0:
			print("[generate_fights] %d / %d" % [k + 1, count])
	file.close()
	get_tree().quit(0)


## One fight from `a_seed`: draw the compositions, run them, report the remains.
func _fight(a_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = a_seed
	var budget_a: float = rng.randf_range(BUDGET_MIN, BUDGET_MAX)
	var budget_b: float = budget_a * exp(rng.randf_range(-BUDGET_LOG_SPREAD, BUDGET_LOG_SPREAD))
	var side_a: Dictionary = _composition(rng, budget_a)
	var side_b: Dictionary = _composition(rng, budget_b)
	var spec: SimSpec = SimSpec.parse(_spec_text(side_a, side_b), "fight_%d" % a_seed)
	var row_extra: Dictionary = {
		"airfield_a": _airfield_for(side_a) != "", "airfield_b": _airfield_for(side_b) != ""
	}
	if not spec.is_valid():
		push_error("generate_fights: %s" % "; ".join(spec.errors))
		return {"seed": a_seed, "error": "; ".join(spec.errors)}
	var arena: SimArena = SimArena.build(spec, a_seed)
	add_child(arena)
	var ticks: int = 0
	var ended_by_wipe: bool = false
	while not arena.is_finished():
		await get_tree().physics_frame
		ticks += 1
		if _all_down(arena, "A.army") or _all_down(arena, "B.army"):
			ended_by_wipe = true
			break
	var row: Dictionary = {
		"seed": a_seed,
		"a": side_a,
		"b": side_b,
		"a_value": _value_of(side_a),
		"b_value": _value_of(side_b),
		"a_left": _value_left(arena, "A.army"),
		"b_left": _value_left(arena, "B.army"),
		"seconds": snappedf(TimeUtils.seconds_from_ticks(ticks), 0.01),
		"wiped": ended_by_wipe,
	}
	row.merge(row_extra)
	arena.queue_free()
	await get_tree().process_frame
	return row


## piece id -> count: one faction, TYPES_MIN..TYPES_MAX distinct types of it, the budget split
## between them by random weights, at least one of each and no more than MAX_UNITS_PER_SIDE in
## all. The faction is the faction of a unit drawn from the whole pool, so each faction appears
## in proportion to its armed units: a uniform draw gave the Technocrats, with one armed unit, a
## third of all sides and a corpus of their mirror matches.
func _composition(a_rng: RandomNumberGenerator, a_budget: float) -> Dictionary:
	var seed_unit: String = _pool[a_rng.randi_range(0, _pool.size() - 1)]
	var pool: Array[String] = _pool_by_faction[seed_unit.substr(0, 3)]
	var types: Array[String] = []
	var wanted: int = a_rng.randi_range(TYPES_MIN, mini(TYPES_MAX, pool.size()))
	while types.size() < wanted:
		var pick: String = pool[a_rng.randi_range(0, pool.size() - 1)]
		if not types.has(pick):
			types.append(pick)
	var weights: Array[float] = []
	for _t: String in types:
		weights.append(a_rng.randf_range(0.2, 1.0))
	var total_weight: float = weights.reduce(func(s: float, w: float) -> float: return s + w, 0.0)
	var out: Dictionary = {}
	var bodies: int = 0
	for i: int in types.size():
		var share: float = a_budget * weights[i] / total_weight
		var n: int = maxi(1, roundi(share / float(_costs[types[i]])))
		n = mini(n, MAX_UNITS_PER_SIDE - bodies - (types.size() - i - 1))
		if n <= 0:
			break
		out[types[i]] = n
		bodies += n
	return out


## Each side's army at its anchor, attack-moving at the other's; a side that fields aircraft
## also gets its faction's airfield a few cells behind the army, so charged clips rearm and a
## sortie cadence exists to measure (2026-10-09; before, no airfield and a clip fired once).
func _spec_text(a_side_a: Dictionary, a_side_b: Dictionary) -> String:
	return (
		"""setting: { kind: flat, size: %d }
given:
  A:
    with:
      army: { of: %s, at: west, formation: cluster, orders: [ { attack_move: { target: east } } ] }
%s  B:
    with:
      army: { of: %s, at: east, formation: cluster, orders: [ { attack_move: { target: west } } ] }
%srun: { for: %ds }
expect:
  - { of: A.army, check: alive, at_least: 0 }
"""
		% [
			ARENA_CELLS,
			_of_list(a_side_a),
			_airfield_text("A", a_side_a, "west"),
			_of_list(a_side_b),
			_airfield_text("B", a_side_b, "east"),
			int(WINDOW_SECONDS),
		]
	)


## The `airfield` group line for a side that flies, placed AIRFIELD_SETBACK_CELLS behind its
## army toward `a_rear`; empty for a side with nothing to land.
func _airfield_text(a_slot: String, a_side: Dictionary, a_rear: String) -> String:
	var airfield: String = _airfield_for(a_side)
	if airfield == "":
		return ""
	var at: String = (
		"{ from: %s.army, distance: %d, bearing: %s }" % [a_slot, AIRFIELD_SETBACK_CELLS, a_rear]
	)
	return "      airfield: { of: [ { piece: %s, count: 1 } ], at: %s }\n" % [airfield, at]


## The faction's airfield piece id for a side that fields aircraft, "" otherwise — or when the
## faction has no airfield piece, in which case its aircraft fly on one clip as before.
func _airfield_for(a_side: Dictionary) -> String:
	var flies: bool = a_side.keys().any(func(t: String) -> bool: return _flies.get(t, false))
	if not flies:
		return ""
	var prefix: String = (a_side.keys()[0] as String).substr(0, 3)
	var airfield: String = prefix + "airField"
	return airfield if SimPieceCatalog.known_pieces().has(airfield) else ""


static func _of_list(a_side: Dictionary) -> String:
	var entries: Array = a_side.keys().map(
		func(t: String) -> String: return "{ piece: %s, count: %d }" % [t, a_side[t]]
	)
	return "[ %s ]" % ", ".join(entries)


func _all_down(a_arena: SimArena, a_group: String) -> bool:
	return a_arena.roster.living(a_group).is_empty()


func _value_of(a_side: Dictionary) -> float:
	var total: float = 0.0
	for t: String in a_side:
		total += float(_costs[t]) * a_side[t]
	return total


## What is left of `a_group` in energy: each living member's cost × its hp fraction, so a
## wounded survivor is worth less than a fresh one.
func _value_left(a_arena: SimArena, a_group: String) -> float:
	var total: float = 0.0
	for entity: Actor in a_arena.roster.living(a_group):
		var fraction: float = 1.0
		if entity.defense != null and entity.defense.hp_max > 0.0:
			fraction = clampf(entity.defense.hp / entity.defense.hp_max, 0.0, 1.0)
		total += float(_costs.get(String(entity.id), 0)) * fraction
	return snappedf(total, 0.1)


func _read_costs() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TECHNOLOGY_JSON))
	var out: Dictionary = {}
	if parsed is Dictionary:
		for id: String in parsed:
			out[id] = int(parsed[id]["cost"]["energy"])
	return out


## Unit pieces with at least one weapon and a price, whose ids start with one of `a_prefixes`.
## Found by instancing each scene off the tree, which is what the piece IS rather than what a
## doc says of it.
func _armed_units(a_prefixes: PackedStringArray) -> Array[String]:
	var out: Array[String] = []
	for id: String in SimPieceCatalog.known_pieces():
		if not a_prefixes.has(id.substr(0, 3)) or int(_costs.get(id, 0)) <= 0:
			continue
		var packed: PackedScene = load(SimPieceCatalog.scene_path(id)) as PackedScene
		if packed == null:
			continue
		var piece: Node = packed.instantiate()
		var loadout: Node = piece.get_node_or_null("Loadout")
		var armed: bool = (
			piece.is_in_group("unit")
			and loadout != null
			and loadout.get_children().any(func(c: Node) -> bool: return c is Weapon)
		)
		var flies: bool = piece.get_node_or_null("Aerial") != null
		piece.free()
		if armed:
			out.append(id)
			_flies[id] = flies
	return out


func _parse_arguments() -> Dictionary:
	var parsed: Dictionary = {}
	for argument: String in OS.get_cmdline_user_args():
		var split: int = argument.find("=")
		if split > 0:
			parsed[argument.substr(0, split)] = argument.substr(split + 1)
	return parsed
