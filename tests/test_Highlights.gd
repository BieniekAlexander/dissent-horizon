extends GutTest

## Tests for the highlight layer: HighlightShape geometry, the Condition.highlight_* virtuals
## that let a check describe itself, and EventHighlight's two lifetimes (tracking its
## trigger's armed state, or fired as an ordinary event).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Highlights.gd -gexit

## Stand-in for "a unit the objective is about". Any commandable would do; this is the one
## the rest of the suite reaches for.
const UNIT: PackedScene = preload("res://scenes/entities/units/an/an_bioLight_builder.tscn")


## A condition the test drives directly, with a fixed set of things to point at.
class StubCondition extends Condition:
	var result: bool = false
	var entities: Array[Entity] = []
	var shapes: Array[HighlightShape] = []

	func evaluate(_a_manager: ScenarioTriggerManager) -> bool:
		return result

	func highlight_entities(_a_manager: ScenarioTriggerManager) -> Array[Entity]:
		return entities

	func highlight_shapes(_a_manager: ScenarioTriggerManager) -> Array[HighlightShape]:
		return shapes

	func satisfy() -> void:
		result = true
		_last = true
		state_changed.emit()


var _manager: ScenarioTriggerManager


func before_each() -> void:
	_manager = ScenarioTriggerManager.new()
	add_child_autofree(_manager)
	assert_push_warning("expected parent to be Scenario")


func after_each() -> void:
	if _manager.simulation_clock != null:
		_manager.simulation_clock.clear()
	get_tree().paused = false


# --- HighlightShape ------------------------------------------------------------

func test_circle_outline_lies_on_the_radius() -> void:
	var shape := HighlightShape.circle(Vector2(3.0, -2.0), 4.0)
	for point: Vector2 in shape.outline(16):
		assert_almost_eq(point.distance_to(shape.center), 4.0, 0.001)


func test_rect_outline_has_four_corners_at_the_half_extents() -> void:
	var shape := HighlightShape.rect(Vector2.ZERO, Vector2(2.0, 5.0))
	var points: Array[Vector2] = shape.outline()
	assert_eq(points.size(), 4, "an unrotated rect is exactly its corners")
	for point: Vector2 in points:
		assert_almost_eq(absf(point.x), 2.0, 0.001)
		assert_almost_eq(absf(point.y), 5.0, 0.001)


func test_rect_rotation_matches_the_containment_convention() -> void:
	# The painted footprint has to be the one region_contains() tests, so a rotated rect's
	# corners must land where the same Basis(UP, yaw) would put them. A quarter turn maps
	# local +x to world -z.
	var shape := HighlightShape.rect(Vector2.ZERO, Vector2(2.0, 1.0), PI * 0.5)
	var expected := Basis(Vector3.UP, PI * 0.5) * Vector3(2.0, 0.0, 1.0)
	var points: Array[Vector2] = shape.outline()
	var matched: bool = points.any(
		func(p: Vector2) -> bool:
			return p.distance_to(Vector2(expected.x, expected.z)) < 0.001
	)
	assert_true(matched, "rotated corners follow the 3D yaw, not a 2D rotation")


func test_from_collision_shape_reads_a_box_footprint() -> void:
	var node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 3.0, 8.0)
	node.shape = box
	add_child_autofree(node)
	node.global_position = Vector3(5.0, 1.0, -4.0)

	var shape: HighlightShape = HighlightShape.from_collision_shape(node)
	assert_eq(shape.kind, HighlightShape.Kind.RECT)
	assert_almost_eq(shape.center.x, 5.0, 0.001)
	assert_almost_eq(shape.center.y, -4.0, 0.001, "Vector2.y carries world Z")
	assert_almost_eq(shape.half_extents.x, 3.0, 0.001)
	assert_almost_eq(shape.half_extents.y, 4.0, 0.001)


func test_from_collision_shape_reads_a_sphere_as_a_disc() -> void:
	var node := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 7.5
	node.shape = sphere
	add_child_autofree(node)

	var shape: HighlightShape = HighlightShape.from_collision_shape(node)
	assert_eq(shape.kind, HighlightShape.Kind.CIRCLE)
	assert_almost_eq(shape.radius, 7.5, 0.001)


func test_from_collision_shape_tolerates_a_shapeless_node() -> void:
	var node := CollisionShape3D.new()
	add_child_autofree(node)
	assert_null(HighlightShape.from_collision_shape(node), "callers can just skip it")


# --- Condition self-description ------------------------------------------------

func test_region_aware_condition_offers_its_bound_region() -> void:
	var node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 2.0, 4.0)
	node.shape = box
	add_child_autofree(node)

	var condition := ConditionUnitCount.new()
	assert_eq(condition.highlight_shapes(_manager), [], "no region bound, nothing to paint")
	condition.bind_region(node)
	assert_eq(condition.highlight_shapes(_manager).size(), 1, "the bound region is the footprint")


func test_units_in_region_condition_paints_its_bound_region() -> void:
	# It shares RegionAwareCondition's footprint now that its region is a scene node rather
	# than inline numbers, so what gets painted is exactly the shape the check tests.
	var node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 3.0, 8.0)
	node.shape = box
	add_child_autofree(node)
	node.global_position = Vector3(1.0, 0.0, 4.0)

	var condition := ConditionUnitsInRegion.new()
	condition.bind_region(node)
	var shapes: Array[HighlightShape] = condition.highlight_shapes(_manager)
	assert_eq(shapes.size(), 1)
	assert_eq(shapes[0].center, Vector2(1.0, 4.0), "centre of the bound shape")
	assert_eq(shapes[0].half_extents, Vector2(5.0, 4.0))


func test_at_least_count_condition_points_at_nowhere_in_particular() -> void:
	# "Get a unit here" is waiting on units that aren't there yet; there is nothing to mark,
	# and the region carries the instruction instead.
	var condition := ConditionUnitCount.new()
	condition.comparison = ConditionUnitCount.Comparison.AT_LEAST
	assert_eq(condition.highlight_entities(_manager), [], "nothing to point at")


# --- EventHighlight ------------------------------------------------------------

func _armed_trigger_with(a_condition: StubCondition) -> GlobalTrigger:
	var trigger := GlobalTrigger.new()
	trigger.conditions = [a_condition]
	_manager.add_child(trigger)
	return trigger


func test_highlight_goes_up_with_its_trigger_and_down_when_it_fires() -> void:
	var condition := StubCondition.new()
	condition.shapes = [HighlightShape.circle(Vector2.ZERO, 3.0)]
	var trigger := _armed_trigger_with(condition)
	var highlight := EventHighlight.new()
	trigger.add_child(highlight)

	assert_false(highlight.is_showing(), "nothing is marked before the trigger arms")
	trigger.arm(_manager)
	assert_true(highlight.is_showing(), "arming raises the marks")
	assert_eq(highlight.highlight().marked_shapes().size(), 1, "and they describe the condition")

	condition.satisfy()
	assert_false(highlight.is_showing(), "meeting the objective takes the marks down")


func test_lifetime_highlight_ignores_being_fired_as_an_event() -> void:
	# fire() runs every child event, this one included. A highlight that turned itself ON at
	# the moment its objective completed would be backwards, so execute() is inert here.
	var condition := StubCondition.new()
	var trigger := _armed_trigger_with(condition)
	var highlight := EventHighlight.new()
	trigger.add_child(highlight)
	trigger.arm(_manager)
	condition.satisfy()
	assert_false(highlight.is_showing(), "the completed objective leaves no marks behind")


func test_fired_highlight_targets_another_trigger() -> void:
	# The other lifetime: an earlier step marks a LATER step's region as its own completion
	# event, rather than tracking its own trigger.
	var later_condition := StubCondition.new()
	later_condition.shapes = [HighlightShape.rect(Vector2(2.0, 2.0), Vector2.ONE)]
	var later := _armed_trigger_with(later_condition)

	var highlight := EventHighlight.new()
	highlight.follow_trigger_lifetime = false
	highlight.target_trigger = later
	highlight.enable = true
	_manager.add_child(highlight)

	_manager.run_event(highlight, null)
	assert_true(highlight.is_showing(), "firing raised the other trigger's marks")
	assert_eq(highlight.highlight().marked_shapes().size(), 1)

	highlight.enable = false
	_manager.run_event(highlight, null)
	assert_false(highlight.is_showing(), "firing again with enable off takes them down")


func test_highlight_drops_entities_that_leave_the_world() -> void:
	# The marks track a live set: a unit the player destroys must stop being marked without
	# anyone telling the highlight about it.
	var condition := StubCondition.new()
	var entity: Commandable = UNIT.instantiate()
	add_child_autofree(entity)
	condition.entities = [entity]
	var trigger := _armed_trigger_with(condition)
	var highlight := EventHighlight.new()
	trigger.add_child(highlight)
	trigger.arm(_manager)

	assert_eq(highlight.highlight().marked_entities().size(), 1, "the live entity is marked")
	entity.get_parent().remove_child(entity)
	highlight.highlight().refresh()
	assert_eq(
		highlight.highlight().marked_entities().size(), 0,
		"an entity that left the world stops being marked"
	)
	entity.free()


func test_highlight_ignores_pause() -> void:
	var condition := StubCondition.new()
	condition.shapes = [HighlightShape.circle(Vector2.ZERO, 1.0)]
	var trigger := _armed_trigger_with(condition)
	var highlight := EventHighlight.new()
	trigger.add_child(highlight)
	trigger.arm(_manager)
	assert_eq(
		highlight.highlight().process_mode, Node.PROCESS_MODE_ALWAYS,
		"a beat that stops the world must still show what it is waiting for"
	)


# --- Region wiring guards ------------------------------------------------------

func test_unresolvable_region_path_warns_when_the_trigger_arms() -> void:
	# The silent failure this exists to catch: a path that no longer resolves leaves the
	# check unscoped, so it matches the whole map instead of failing. Reads to the author as
	# "my trigger never fires" (or "fires immediately"), with nothing in the log.
	var condition := ConditionUnitCount.new()
	condition.region_shape_path = NodePath("NoSuchNode")
	var trigger := GlobalTrigger.new()
	trigger.name = "Destination1"
	trigger.conditions = [condition]
	_manager.add_child(trigger)

	trigger.arm(_manager)
	assert_push_warning("did not resolve to a CollisionShape3D")
	assert_false(condition.has_region(), "and the condition knows it has no region")


func test_units_in_region_warns_when_no_region_is_authored() -> void:
	# ConditionUnitCount with no region is legitimate ("how many units do I own?"), but a
	# units-IN-REGION check with no region is always a mistake.
	var condition := ConditionUnitsInRegion.new()
	var trigger := GlobalTrigger.new()
	trigger.name = "Destination1"
	trigger.conditions = [condition]
	_manager.add_child(trigger)

	trigger.arm(_manager)
	assert_push_warning("needs a region but region_shape_path is empty")


func test_unscoped_unit_count_does_not_warn() -> void:
	var condition := ConditionUnitCount.new()
	var trigger := GlobalTrigger.new()
	trigger.name = "AnyUnits"
	trigger.conditions = [condition]
	_manager.add_child(trigger)

	trigger.arm(_manager)
	assert_eq(
		get_logger().get_errors().size(), 0,
		"an optional region left unset is normal authoring, not a mistake"
	)


func test_painter_survives_its_last_marked_entity_dying() -> void:
	# Marks are re-queried on a cadence, so a unit dies several frames before the target list
	# notices. Drawing in that window must not open an empty ImmediateMesh surface — Godot
	# raises "No vertices were added" and it repeats every frame until the next refresh.
	var condition := StubCondition.new()
	var entity: Commandable = UNIT.instantiate()
	add_child_autofree(entity)
	condition.entities = [entity]
	var trigger := _armed_trigger_with(condition)
	var highlight := EventHighlight.new()
	trigger.add_child(highlight)
	trigger.arm(_manager)
	assert_eq(highlight.highlight().marked_entities().size(), 1, "the unit is marked")

	# Kill it WITHOUT refreshing, reproducing the mid-interval window.
	entity.get_parent().remove_child(entity)
	highlight.highlight()._redraw()
	assert_eq(
		get_logger().get_errors().size(), 0,
		"drawing a stale, now-empty target list must not touch the mesh at all"
	)
	entity.free()


# --- Objective colour + minimap sourcing --------------------------------------

func test_highlights_default_to_the_shared_objective_green() -> void:
	# One constant backs the world markers and the minimap markers, so "green means this is
	# your objective" can't drift between the two views.
	var event := EventHighlight.new()
	autofree(event)
	assert_eq(event.color, ScenarioHighlight.OBJECTIVE_COLOR)
	assert_gt(
		ScenarioHighlight.OBJECTIVE_COLOR.g, ScenarioHighlight.OBJECTIVE_COLOR.r,
		"the objective colour is green"
	)


func test_objective_green_is_not_a_team_colour() -> void:
	# Team 3 is a dark green; an objective marker that reads as somebody's units is worse
	# than no marker.
	for team_color: Color in Entity.TEAM_COLOR_MAP.values():
		var distance: float = Vector3(
			ScenarioHighlight.OBJECTIVE_COLOR.r - team_color.r,
			ScenarioHighlight.OBJECTIVE_COLOR.g - team_color.g,
			ScenarioHighlight.OBJECTIVE_COLOR.b - team_color.b
		).length()
		assert_gt(distance, 0.35, "objective green is distinguishable from team %s" % team_color)


func test_a_live_highlight_joins_the_group_the_minimap_reads() -> void:
	# The minimap finds what to stamp through this group, so it needs to know nothing about
	# triggers, conditions or objectives.
	var condition := StubCondition.new()
	condition.shapes = [HighlightShape.circle(Vector2.ZERO, 4.0)]
	var trigger := _armed_trigger_with(condition)
	var highlight := EventHighlight.new()
	trigger.add_child(highlight)

	assert_eq(get_tree().get_nodes_in_group(ScenarioHighlight.GROUP).size(), 0, "nothing yet")
	trigger.arm(_manager)
	var marked: Array = get_tree().get_nodes_in_group(ScenarioHighlight.GROUP)
	assert_eq(marked.size(), 1, "raising the highlight registers it")
	assert_eq((marked[0] as ScenarioHighlight).color, highlight.color, "and carries its colour")

	condition.satisfy()
	# queue_free takes effect at end of frame, so the node is still in the group here; what
	# matters is that it is on its way out rather than lingering as a stale minimap source.
	assert_true((marked[0] as ScenarioHighlight).is_queued_for_deletion())


func test_perimeter_points_subdivide_long_edges() -> void:
	# Shared by the world painter (drape over terrain) and the minimap (one pixel per step).
	# Four corners alone would be a stretched rectangle in both.
	var shape := HighlightShape.rect(Vector2.ZERO, Vector2(10.0, 10.0))
	assert_eq(shape.outline().size(), 4, "a rect is four corners")
	var sampled: Array[Vector2] = shape.perimeter_points(1.0)
	assert_gt(sampled.size(), 60, "each 20-unit edge is subdivided at ~1 unit spacing")
	for i: int in sampled.size():
		var next: Vector2 = sampled[(i + 1) % sampled.size()]
		assert_lt(sampled[i].distance_to(next), 1.5, "no gap larger than the spacing")
