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


func _home_positions() -> Array:
	var positions: Array = []
	for cell: Vector2i in home:
		positions.append(lattice.centre_of(cell))
	return positions
