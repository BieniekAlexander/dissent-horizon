extends GutTest

## TAKING A DETECTION VOLUME AWAY FROM A PIECE, from its spec doc.
##
## `senses.vision:` may be set to `false` or simply LEFT EMPTY, and both
## mean the same thing: this piece has no such volume. Two halves are pinned here —
## validation accepts the empty spelling instead of erroring on it, and the scene sync
## REMOVES the VisionRange rather than writing a cylinder of radius nothing (and composition
## never gives an unsighted piece one).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gexit \
##     -gtest=res://tests/test_SpecShapeRemoval.gd

## Preloaded rather than reached through class_name: a headless run does not refresh the
## global class cache. Same reason as test_SpecGenerators.
const SceneSync := preload("res://tools/spec_import/scene_sync.gd")
const SpecRegistry := preload("res://tools/spec_import/spec_registry.gd")
const SpecComposition := preload("res://tools/spec_import/composition.gd")
const TscnDoc := preload("res://tools/spec_import/tscn_doc.gd")

## A piece whose VisionRange carries a cylinder of its own — the state a doc that used to name
## a radius leaves behind.
const SCENE_WITH_VISION: String = """[gd_scene load_steps=2 format=3]

[sub_resource type="CylinderShape3D" id="CylinderShape3D_vision"]
height = 100.0
radius = 8.0

[node name="Piece" type="CharacterBody3D"]

[node name="VisionRange" type="CollisionShape3D" parent="."]
shape = SubResource("CylinderShape3D_vision")
"""

## The same piece already without one.
const SCENE_WITHOUT_VISION: String = """[gd_scene load_steps=1 format=3]

[node name="Piece" type="CharacterBody3D"]
"""


## A live node tree standing in for the instantiated scene: a VisionRange carrying `a_shape`,
## or none at all for a null one.
func _inst(a_shape: Shape3D) -> Node:
	var root := CharacterBody3D.new()
	root.name = "Piece"
	if a_shape != null:
		var vision := CollisionShape3D.new()
		vision.name = "VisionRange"
		vision.shape = a_shape
		root.add_child(vision)
	add_child_autofree(root)
	return root


func _cylinder(a_radius: float) -> CylinderShape3D:
	var shape := CylinderShape3D.new()
	shape.height = 100.0
	shape.radius = a_radius
	return shape


func _ctx(a_text: String, a_shape: Shape3D) -> RefCounted:
	var ctx := SceneSync.Ctx.new()
	ctx.doc = TscnDoc.from_text(a_text)
	ctx.inst = _inst(a_shape)
	ctx.path = "res://scenes/entities/units/test_piece.tscn"
	return ctx


#region Validation: an empty value is a statement, not a mistake
func test_an_empty_radius_reads_as_zero_where_zero_disables() -> void:
	var registry := SpecRegistry.new()
	var spec: Dictionary = {"_doc_path": "doc.md", "id": "p", "vision": null}

	registry._check_radius(spec, "vision", true)

	assert_eq(registry.errors, [], "an emptied key is how a volume is taken away, not an error")
	assert_eq(spec["vision"], 0, "and it normalises to 0, so nothing downstream sees null")


func test_false_still_reads_as_zero() -> void:
	var registry := SpecRegistry.new()
	var spec: Dictionary = {"_doc_path": "doc.md", "id": "p", "vision": false}

	registry._check_radius(spec, "vision", true)

	assert_eq(registry.errors, [], "the older spelling keeps working")
	assert_eq(spec["vision"], 0)


func test_an_empty_radius_is_still_refused_where_the_volume_is_not_optional() -> void:
	# Every piece pushes through the world and every piece is shootable, so there is no
	# "no MovementBody" to ask for.
	var registry := SpecRegistry.new()
	registry._check_radius(
		{"_doc_path": "doc.md", "id": "p", "movement_radius": null}, "movement_radius", false
	)

	assert_eq(registry.errors.size(), 1, "emptying a mandatory volume is still an error")
	assert_false(
		registry.errors[0].contains("left empty"), "and it is not offered as an option there"
	)


func test_true_is_still_refused() -> void:
	# A radius has no default to take, so a bare `true` cannot mean anything.
	var registry := SpecRegistry.new()
	registry._check_radius({"_doc_path": "doc.md", "id": "p", "vision": true}, "vision", true)

	assert_eq(registry.errors.size(), 1, "true is not a radius")


#endregion


#region The scene sync: removal deletes the node
func test_removal_deletes_the_node_rather_than_collapsing_the_shape() -> void:
	var sync := SceneSync.new()
	var ctx: RefCounted = _ctx(SCENE_WITH_VISION, _cylinder(8.0))

	sync._sync_shapes(ctx, {"vision": 0})

	var text: String = ctx.doc.to_text()
	assert_false(text.contains('[node name="VisionRange"'), "the volume is gone, not emptied")
	assert_false(
		text.contains("radius = 0"),
		"a radius-nothing cylinder is a detector in the inspector and not one in the game"
	)
	assert_true(ctx.dirty, "the scene is rewritten")


func test_removal_drops_the_sub_resource_it_was_the_only_user_of() -> void:
	var sync := SceneSync.new()
	var ctx: RefCounted = _ctx(SCENE_WITH_VISION, _cylinder(8.0))

	sync._sync_shapes(ctx, {"vision": 0})

	assert_false(
		ctx.doc.to_text().contains("CylinderShape3D_vision"),
		"nothing references it any more, so it does not stay behind as an orphan"
	)


func test_removing_an_absent_volume_changes_nothing() -> void:
	# The importer runs repeatedly over the same tree; a second pass must be a no-op.
	var sync := SceneSync.new()
	var ctx: RefCounted = _ctx(SCENE_WITHOUT_VISION, null)

	sync._sync_shapes(ctx, {"vision": 0})

	assert_false(ctx.dirty, "nothing to do, so nothing is written")


func test_composition_gives_an_unsighted_piece_no_vision_range() -> void:
	var names: Array = SpecComposition.components({"kind": "Entity", "vision": 0}).map(
		func(e: Dictionary) -> String: return e["name"]
	)
	assert_false(names.has("VisionRange"), "switched off in the doc, never composed")
	names = SpecComposition.components({"kind": "Entity", "vision": 8}).map(
		func(e: Dictionary) -> String: return e["name"]
	)
	assert_true(names.has("VisionRange"), "a sighted piece still gets one")


#endregion


#region Routing: which keys removal applies to
func test_a_named_shape_points_at_the_library() -> void:
	var sync := SceneSync.new()
	var ctx: RefCounted = _ctx(SCENE_WITH_VISION, _cylinder(8.0))

	sync._sync_shapes(ctx, {"vision": 12, "_shape_ids": {"vision": "vision_test"}})

	var text: String = ctx.doc.to_text()
	assert_string_contains(text, "vision_test.tres")
	assert_string_contains(text, '[node name="VisionRange"', "a named shape is not a removal")


func test_only_the_detection_volumes_are_removable() -> void:
	assert_eq(
		SceneSync.REMOVABLE_SHAPE_KEYS,
		["vision"] as Array[String],
		"the physical bodies are not optional — _check_radius refuses zero for them"
	)
#endregion
