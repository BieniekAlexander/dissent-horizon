class_name FixtureFields
extends BotFields

## A BotFields over a hand-made lattice with no map and no commander, for tests: open ground
## for every size class, the believed sources, home cells and presence stamps a test sets, and
## an explored set that is everywhere. Not a GutTest (hence the `_` prefix, which
## tests/test_SuiteIntegrity.gd expects of a deliberate non-collection).

var sources: Array = []
var home: Array = []
var stamps: Array = []
## The bot's own responders, in _own_sources' shape, and its static defences' reach discs.
var own: Array = []
var defences: Array = []
## The bot's own armed pieces as strength sources, {"cell", "type", "value"} (add_own); the
## believed enemy's are `sources`.
var own_strength: Array = []
## Attacker type → the target types it can damage, for the strength fields' answerability; a
## type not listed damages everything, so a fixture that never sets it is all-answerable.
var damage: Dictionary = {}


## Open ground under `a_bounds` at the bot's pitch.
static func over_open(a_bounds: Rect2) -> FixtureFields:
	var fields := FixtureFields.new()
	fields.lattice = Lattice.covering(a_bounds, PITCH)
	var open := PackedByteArray()
	open.resize(fields.lattice.cell_count())
	open.fill(1)
	# Pre-seeded so passable_mask never reaches for a map.
	for size: int in NavAgentClass.Size.values():
		fields._passable[size] = open
	return fields


## A ground source of `a_speed` at `a_cell`, of type `a_type` (what a kill clock prices it by).
func add_walker(
	a_cell: Vector2i, a_speed: float, a_type: StringName = &"fake_walker", a_value: float = 100.0
) -> void:
	sources.append(_walker(a_cell, a_speed, a_type, a_value))


## One of the bot's own armed walkers at `a_cell`, worth `a_value`, answering after `a_delay`.
func add_responder(
	a_cell: Vector2i, a_speed: float, a_delay: float = 0.0, a_value: float = 100.0
) -> void:
	var source: Dictionary = _walker(a_cell, a_speed, &"fake_responder", a_value)
	source["delay"] = a_delay
	own.append(source)


## One of the bot's own static defences reaching `a_reach` from `a_cell`'s centre.
func add_defence(a_cell: Vector2i, a_reach: float, a_value: float = 100.0) -> void:
	defences.append({"xz": lattice.centre_of(a_cell), "reach": a_reach, "value": a_value})


## One of the bot's own armed pieces at `a_cell`, of `a_type`, worth `a_value`, reaching
## `a_reach` — a strength source only (it stamps no presence penalty and answers no threat).
func add_own(
	a_cell: Vector2i, a_type: StringName, a_value: float = 100.0, a_reach: float = 0.0
) -> void:
	own_strength.append({"cell": a_cell, "type": a_type, "value": a_value, "reach": a_reach})


## A believed enemy piece standing still at `a_cell`, of `a_type`, worth `a_value`, reaching
## `a_reach`: a source with no speed, so it seeds the band and the strength fields and no
## arrival field.
func add_enemy(
	a_cell: Vector2i, a_type: StringName, a_value: float = 100.0, a_reach: float = 0.0
) -> void:
	var source: Dictionary = _walker(a_cell, 0.0, a_type, a_value)
	source["reach"] = a_reach
	sources.append(source)


func _walker(a_cell: Vector2i, a_speed: float, a_type: StringName, a_value: float) -> Dictionary:
	return {
		"cell": a_cell,
		"xz": lattice.centre_of(a_cell),
		"speed": a_speed,
		"nav_class": NavAgentClass.Size.SMALL,
		"is_air": false,
		"type": a_type,
		"is_structure": false,
		"value": a_value,
	}


func _gather_sources() -> Array:
	return sources


func _home_cells() -> Array:
	return home


func _presence_stamps() -> Array:
	var all: Array = stamps.duplicate()
	for defence: Dictionary in defences:
		(
			all
			. append(
				{
					"xz": defence["xz"],
					"reach": defence["reach"],
					"value": defence["value"],
					"is_structure": true,
				}
			)
		)
	return all


func _own_sources() -> Array:
	return own


func _own_strength_sources(_a_stamps: Array) -> Array:
	return own_strength


func _enemy_strength_sources(a_sources: Array) -> Array:
	var out: Array = []
	for source: Dictionary in a_sources:
		(
			out
			. append(
				{
					"cell": source["cell"],
					"type": source["type"],
					"value": float(source["value"]),
					"reach": float(source.get("reach", 0.0)),
				}
			)
		)
	return out


func _strength_can_damage(a_type: StringName, a_target_type: StringName) -> bool:
	if not damage.has(a_type):
		return true
	return (damage[a_type] as Array).has(a_target_type)


func _home_positions() -> Array:
	var positions: Array = []
	for cell: Vector2i in home:
		positions.append(lattice.centre_of(cell))
	return positions
