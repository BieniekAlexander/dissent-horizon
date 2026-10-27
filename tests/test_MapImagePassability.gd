extends GutTest

## What a round trip changed about where a unit can walk (MapImagePassability): only passages —
## ground joined or split — are reported, never an edge that moved. Masks are drawn here as text,
## one row per string, `#` walkable and `.` not.

## Two rooms, wall between: the wall's gap is the passage.
const _APART: Array[String] = [
	"#######.#######",
	"#######.#######",
	"#######.#######",
	"#######.#######",
	"#######.#######",
	"#######.#######",
	"#######.#######",
]
const _JOINED: Array[String] = [
	"#######.#######",
	"#######.#######",
	"#######.#######",
	"###############",
	"#######.#######",
	"#######.#######",
	"#######.#######",
]
## The rooms of _APART, each a cell narrower: an edge moved, nothing was joined or split.
const _NARROWER: Array[String] = [
	"######...######",
	"######...######",
	"######...######",
	"######...######",
	"######...######",
	"######...######",
	"######...######",
]
## A sliver beside a room, joined to it: too small to count as ground the map kept apart.
const _SLIVER_APART: Array[String] = [
	"##########.#...",
	"##########.#...",
	"##########.....",
	"##########.....",
	"##########.....",
	"##########.....",
	"##########.....",
]
const _SLIVER_JOINED: Array[String] = [
	"############...",
	"##########.#...",
	"##########.....",
	"##########.....",
	"##########.....",
	"##########.....",
	"##########.....",
]


## The mask on a square grid as wide as the rows, rows below them blocked.
static func _mask(rows: Array[String]) -> PackedByteArray:
	var side: int = rows[0].length()
	var out := PackedByteArray()
	out.resize(side * side)
	for z: int in rows.size():
		for x: int in side:
			out[z * side + x] = 1 if rows[z][x] == "#" else 0
	return out


func _compare_masks(a_before: Array[String], a_after: Array[String]) -> Dictionary:
	return MapImagePassability.compare(_mask(a_before), _mask(a_after), a_before[0].length())


func test_a_gap_in_a_wall_is_a_passage_opened_where_it_is() -> void:
	var result: Dictionary = _compare_masks(_APART, _JOINED)
	assert_eq(result.lines.size(), 1, "\n".join(result.lines))
	assert_string_contains(result.lines[0], "PASSAGE OPENED")
	assert_string_contains(result.lines[0], "(7, 3)")
	assert_eq(result.opened, [Vector2i(7, 3)] as Array[Vector2i])


func test_a_wall_put_back_is_a_passage_closed() -> void:
	var result: Dictionary = _compare_masks(_JOINED, _APART)
	assert_eq(result.lines.size(), 1, "\n".join(result.lines))
	assert_string_contains(result.lines[0], "PASSAGE CLOSED")
	assert_eq(result.closed, [Vector2i(7, 3)] as Array[Vector2i])


func test_an_edge_that_only_moved_is_not_reported() -> void:
	assert_eq(_compare_masks(_APART, _NARROWER).lines.size(), 0)
	assert_eq(_compare_masks(_NARROWER, _APART).lines.size(), 0)


func test_joining_a_sliver_is_not_reported() -> void:
	assert_eq(_compare_masks(_SLIVER_APART, _SLIVER_JOINED).lines.size(), 0)


func test_the_readout_marks_the_passage() -> void:
	var before: PackedByteArray = _mask(_APART)
	var after: PackedByteArray = _mask(_JOINED)
	var side: int = _APART[0].length()
	var result: Dictionary = MapImagePassability.compare(before, after, side)
	var image: Image = MapImagePassability.readout(
		before, after, side, result.opened, result.closed
	)
	assert_eq(image.get_pixel(7, 3), MapImagePassability.PASSAGE_OPENED_COLOR)
	assert_eq(image.get_pixel(0, 0), MapImagePassability.WALKABLE_COLOR)
