class_name CombatModel
extends RefCounted

## THE LEARNED COMBAT MODEL: who comes out ahead when two compositions fight, and so what one
## more piece of a type is worth against the enemy the bot believes in. Fitted offline by
## tools/combat_model/train.py on fights the sim harness generated; this class only reads the
## lookup tables it exported. gdd/systems/ai/macro-learning.md §1.
##
## The prediction is a MARGIN in [-1, 1]: own fraction of value left minus enemy fraction left.
## It is an intercept plus one table per side-and-type ("own:<id>", "enemy:<id>") indexed by
## count, plus a few pairwise tables indexed by two counts — the GA2M form, so every term can be
## read on its own. `predict` averages the model with its mirror (`(f(o, e) − f(e, o)) / 2`),
## which makes the two sides exactly opposite even where the fit is not.
##
## Counts are SCALED before lookup: the training fights never put more than `cap` bodies on a
## side, so both compositions are shrunk by one shared factor until the larger is that size, and
## a fractional count interpolates between table entries. That keeps the ratio of the two forces
## and the mix within each, which is what the model learned, at the cost of the absolute size
## (Lanchester's square law says size matters beyond the ratio; the fights did not cover it).

## Where the trainer writes the model, beside the trained roster. Committed like roster.json.
const PATH: String = "res://resources/bots/combat_model.json"

var _intercept: float = 0.0
var _cap: int = 0
var _types: Dictionary = {}  # piece id -> true
var _main: Dictionary = {}  # "own:<id>" / "enemy:<id>" -> Array of floats, index = count
var _pairs: Array = []  # [{"a": term name, "b": term name, "grid": Array of Arrays}]

## The shared model, read once per process: parsing the tables on every production decision
## would be most of the decision's cost. Null when no model has been trained.
static var _shared: CombatModel = null
static var _shared_read: bool = false


## The model the game ships, or null when the trainer has not produced one — an unfinished
## dependency, not a failure: callers fall back to the hand-written valuation.
static func shared() -> CombatModel:
	if not _shared_read:
		_shared_read = true
		_shared = from_file(PATH)
	return _shared


## A model from the trainer's JSON at `path`, or null when the file is absent or not one.
static func from_file(path: String) -> CombatModel:
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return from_dict(parsed) if parsed is Dictionary else null


## A model from the trainer's export, already parsed; null when it lacks the tables.
static func from_dict(data: Dictionary) -> CombatModel:
	if not (data.get("main") is Dictionary and data.get("types") is Array):
		return null
	var model := CombatModel.new()
	model._intercept = float(data.get("intercept", 0.0))
	model._cap = int(data.get("cap", 0))
	for t: Variant in data["types"]:
		model._types[StringName(t)] = true
	model._main = data["main"]
	model._pairs = data.get("pairs", [])
	return model


## Whether the model was trained on fights with pieces of `a_type`.
func knows(a_type: StringName) -> bool:
	return _types.has(a_type)


## The margin a fight between `a_own` and `a_enemy` (piece id -> count) is predicted to end on,
## from own's side: 1 is a clean win, −1 a clean loss. Types the model does not know are
## ignored, so a caller that cares asks `knows` first.
func predict(a_own: Dictionary, a_enemy: Dictionary) -> float:
	var scale: float = _scale_for(a_own, a_enemy)
	var own: Dictionary = _scaled(a_own, scale)
	var enemy: Dictionary = _scaled(a_enemy, scale)
	return (_raw(own, enemy) - _raw(enemy, own)) / 2.0


## How much one more `a_type` moves the predicted margin, at the scale of the fight it joins.
func marginal(a_own: Dictionary, a_enemy: Dictionary, a_type: StringName) -> float:
	var with_it: Dictionary = a_own.duplicate()
	with_it[a_type] = int(with_it.get(a_type, 0)) + 1
	return predict(with_it, a_enemy) - predict(a_own, a_enemy)


## The one factor both sides are shrunk by so the larger has at most `_cap` bodies.
func _scale_for(a_own: Dictionary, a_enemy: Dictionary) -> float:
	var largest: float = maxf(_bodies(a_own), _bodies(a_enemy))
	return minf(1.0, float(_cap) / largest) if largest > 0.0 and _cap > 0 else 1.0


func _raw(a_own: Dictionary, a_enemy: Dictionary) -> float:
	var counts: Dictionary = {}  # term name -> count
	for t: Variant in a_own:
		counts["own:%s" % t] = a_own[t]
	for t: Variant in a_enemy:
		counts["enemy:%s" % t] = a_enemy[t]
	var total: float = _intercept
	for term: String in counts:
		if _main.has(term):
			total += _lookup(_main[term], counts[term])
	for pair: Dictionary in _pairs:
		total += _lookup_pair(pair["grid"], counts.get(pair["a"], 0.0), counts.get(pair["b"], 0.0))
	return total


## `a_table` at a fractional count: linear between the two entries either side, clamped to the
## table.
static func _lookup(table: Array, count: float) -> float:
	var at: float = clampf(count, 0.0, float(table.size() - 1))
	var low: int = floori(at)
	var high: int = mini(low + 1, table.size() - 1)
	return lerpf(float(table[low]), float(table[high]), at - low)


## `a_grid` at two fractional counts: bilinear, clamped.
static func _lookup_pair(grid: Array, row: float, column: float) -> float:
	var at: float = clampf(row, 0.0, float(grid.size() - 1))
	var low: int = floori(at)
	var high: int = mini(low + 1, grid.size() - 1)
	return lerpf(_lookup(grid[low], column), _lookup(grid[high], column), at - low)


static func _scaled(composition: Dictionary, scale: float) -> Dictionary:
	var out: Dictionary = {}
	for t: Variant in composition:
		out[t] = float(composition[t]) * scale
	return out


static func _bodies(composition: Dictionary) -> float:
	var total: float = 0.0
	for t: Variant in composition:
		total += float(composition[t])
	return total
