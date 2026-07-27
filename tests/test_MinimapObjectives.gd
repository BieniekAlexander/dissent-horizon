extends GutTest

## Tests for the minimap's objective layer: the green rings and region outlines it stamps for
## whatever is currently highlighted in the world.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_MinimapObjectives.gd -gexit
##
## The Minimap normally resolves its bounds from the running scene's Map node, which a test
## has no clean way to stand up. These inject the handful of framing values _initialize_bounds
## would have computed and then drive the objective pass directly — the part under test is the
## stamping, not the bounds maths (which the terrain tests already cover).

const UNIT: PackedScene = preload("res://scenes/entities/units/an/an_bioLight_builder.tscn")

## Half-extents of the pretend map, in world units. 96 wide over 192 pixels = 0.5 world units
## per pixel, which keeps the pixel arithmetic in these tests easy to read.
const HALF_W: float = 48.0
const HALF_D: float = 27.0

var _minimap: Minimap


func before_each() -> void:
	_minimap = Minimap.new()
	add_child_autofree(_minimap)
	# Stand in for _initialize_bounds: an axis-aligned map centred on the world origin.
	# Setting _ready_to_draw also makes the deferred _initialize_bounds no-op, so it never
	# tries (and fails) to resolve a Map out of the GUT runner scene.
	_minimap._ready_to_draw = true
	_minimap._world_half_w = HALF_W
	_minimap._world_half_d = HALF_D
	_minimap._world_center = Vector2.ZERO
	_minimap._screen_aligned = false
	_minimap._world_units_per_pixel = (2.0 * HALF_W) / float(Minimap.WIDTH)
	_minimap._image.fill(Color.BLACK)


## A live highlight in the group the minimap reads, marking `entities` and `shapes`.
##
## Both arguments are TYPED arrays, and callers must pass typed locals rather than a bare []
## literal: an array literal is untyped at runtime whatever the parameter declares, and
## GDScript aborts the call rather than coercing it.
func _highlight(a_entities: Array[Entity], a_shapes: Array[HighlightShape]) -> ScenarioHighlight:
	var highlight := ScenarioHighlight.new()
	add_child_autofree(highlight)
	highlight.target_source = func() -> Dictionary:
		return {"entities": a_entities, "shapes": a_shapes}
	highlight.refresh()
	return highlight


## Whether a minimap pixel is `color`, within one 8-bit step.
##
## The image is FORMAT_RGBA8, so a component like 0.35 round-trips as 89/255 = 0.349 —
## is_equal_approx is far too strict to compare against the authored Color.
func _is(a_pixel: Color, a_color: Color) -> bool:
	const EPSILON: float = 1.5 / 255.0
	return absf(a_pixel.r - a_color.r) < EPSILON \
		and absf(a_pixel.g - a_color.g) < EPSILON \
		and absf(a_pixel.b - a_color.b) < EPSILON


## How many pixels of the minimap image match `color`.
func _count(a_color: Color) -> int:
	var n: int = 0
	for y: int in Minimap.HEIGHT:
		for x: int in Minimap.WIDTH:
			if _is(_minimap._image.get_pixel(x, y), a_color):
				n += 1
	return n


func test_nothing_is_stamped_when_nothing_is_highlighted() -> void:
	_minimap._draw_objective_markers()
	assert_eq(_count(ScenarioHighlight.OBJECTIVE_COLOR), 0)


func test_a_marked_entity_gets_a_green_ring() -> void:
	var unit: Commandable = UNIT.instantiate()
	add_child_autofree(unit)
	unit.global_position = Vector3.ZERO
	var entities: Array[Entity] = [unit]
	var no_shapes: Array[HighlightShape] = []
	_highlight(entities, no_shapes)

	_minimap._draw_objective_markers()
	assert_eq(
		_count(ScenarioHighlight.OBJECTIVE_COLOR),
		_minimap._objective_ring_offsets.size(),
		"one ring's worth of pixels, in the shared objective green"
	)


func test_the_ring_is_hollow_so_the_team_dot_shows_through() -> void:
	# The marker says "this one matters", not "this one is green" — ownership must stay
	# readable underneath it.
	var unit: Commandable = UNIT.instantiate()
	add_child_autofree(unit)
	unit.global_position = Vector3.ZERO
	var entities: Array[Entity] = [unit]
	var no_shapes: Array[HighlightShape] = []
	_highlight(entities, no_shapes)

	var centre: Vector2i = _minimap.world_to_minimap(Vector2.ZERO)
	_minimap._image.set_pixel(centre.x, centre.y, Color.RED)
	_minimap._draw_objective_markers()
	assert_eq(
		_minimap._image.get_pixel(centre.x, centre.y), Color.RED,
		"the centre pixel is untouched"
	)


func test_a_marked_region_is_outlined() -> void:
	var shapes: Array[HighlightShape] = [HighlightShape.rect(Vector2.ZERO, Vector2(10.0, 10.0))]
	var no_entities: Array[Entity] = []
	_highlight(no_entities, shapes)

	_minimap._draw_objective_markers()
	assert_gt(_count(ScenarioHighlight.OBJECTIVE_COLOR), 0, "the footprint is drawn")
	# A 20x20 world rect at 0.5 units/pixel is 40x~74 pixels; its outline is the perimeter,
	# far short of the filled area — the minimap draws an outline, not a blob.
	assert_lt(_count(ScenarioHighlight.OBJECTIVE_COLOR), 40 * 74, "outlined, not filled")


func test_the_region_outline_is_continuous() -> void:
	# Sampled at half a pixel's worth of world distance, so a long edge lands on every pixel
	# it crosses instead of dotting. Check the top edge has no gaps.
	var shapes: Array[HighlightShape] = [HighlightShape.rect(Vector2.ZERO, Vector2(10.0, 10.0))]
	var no_entities: Array[Entity] = []
	_highlight(no_entities, shapes)
	_minimap._draw_objective_markers()

	var left: Vector2i = _minimap.world_to_minimap(Vector2(-10.0, -10.0))
	var right: Vector2i = _minimap.world_to_minimap(Vector2(10.0, -10.0))
	for x: int in range(left.x, right.x + 1):
		assert_true(
			_is(_minimap._image.get_pixel(x, left.y), ScenarioHighlight.OBJECTIVE_COLOR),
			"pixel %d of the top edge is filled" % x
		)


func test_markers_use_the_highlights_own_colour() -> void:
	# The minimap reads each highlight's colour rather than assuming green, so a highlight
	# that means something other than "objective" still agrees with its world markers.
	var unit: Commandable = UNIT.instantiate()
	add_child_autofree(unit)
	unit.global_position = Vector3.ZERO
	var entities: Array[Entity] = [unit]
	var no_shapes: Array[HighlightShape] = []
	var highlight := _highlight(entities, no_shapes)
	highlight.color = Color(1.0, 0.3, 0.25)

	_minimap._draw_objective_markers()
	assert_eq(_count(ScenarioHighlight.OBJECTIVE_COLOR), 0, "not the default green")
	assert_eq(_count(Color(1.0, 0.3, 0.25)), _minimap._objective_ring_offsets.size())


func test_entities_that_left_the_world_are_not_stamped() -> void:
	var unit: Commandable = UNIT.instantiate()
	add_child(unit)
	unit.global_position = Vector3.ZERO
	var entities: Array[Entity] = [unit]
	var no_shapes: Array[HighlightShape] = []
	_highlight(entities, no_shapes)

	unit.get_parent().remove_child(unit)
	_minimap._draw_objective_markers()
	assert_eq(_count(ScenarioHighlight.OBJECTIVE_COLOR), 0, "a dead target leaves no marker")
	unit.free()
