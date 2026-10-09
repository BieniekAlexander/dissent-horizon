class_name FixtureFields
extends BotFields

## A BotFields over a hand-made lattice with no map and no commander, for tests: open ground
## for every size class, the believed sources, home cells and presence stamps a test sets, and
## an explored set that is everywhere. Not a GutTest (hence the `_` prefix, which
## tests/test_SuiteIntegrity.gd expects of a deliberate non-collection).

var sources: Array = []
var home: Array = []
var stamps: Array = []


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


## A ground source of `a_speed` at `a_cell`.
func add_walker(a_cell: Vector2i, a_speed: float) -> void:
	(
		sources
		. append(
			{
				"cell": a_cell,
				"xz": lattice.centre_of(a_cell),
				"speed": a_speed,
				"nav_class": NavAgentClass.Size.SMALL,
				"is_air": false,
			}
		)
	)


func _gather_sources() -> Array:
	return sources


func _home_cells() -> Array:
	return home


func _presence_stamps() -> Array:
	return stamps
