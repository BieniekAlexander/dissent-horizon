extends GutTest

## A piece's scene is COMPOSED from its doc, never inherited: the importer writes a bare root of
## the derived class and then adds every component the composition guarantees. See
## gdd/systems/authoring/composition-rework.md §Step 4.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_SpecComposition.gd -gexit

## Preloaded rather than reached through class_name: a headless run does not refresh the
## global class cache. Same reason as test_SpecKindAndComposition.
const SpecComposition := preload("res://tools/spec_import/composition.gd")
const SceneSync := preload("res://tools/spec_import/scene_sync.gd")

const MOBILE: Dictionary = {"speed": 1.5}
const SCRATCH: String = "user://test_spec_composition_%s.tscn"


#region The tier
func test_a_piece_that_moves_or_occupies_takes_orders() -> void:
	assert_eq(SpecComposition.tier({"movement": MOBILE}), SpecComposition.Tier.COMMANDABLE)
	assert_eq(SpecComposition.tier({"footprint": [2, 2]}), SpecComposition.Tier.COMMANDABLE)


func test_an_uncommandable_fixture_is_a_feature() -> void:
	assert_eq(
		SpecComposition.tier({"footprint": [2, 2], "commandable": false}),
		SpecComposition.Tier.FEATURE
	)


func test_anything_that_can_be_damaged_is_an_actor_even_if_not_ordered() -> void:
	assert_eq(
		SpecComposition.tier({"movement": MOBILE, "commandable": false, "defense": {"hp": 50}}),
		SpecComposition.Tier.COMMANDABLE,
		"the Recon Drone's shape"
	)


func test_vision_alone_is_bodiless() -> void:
	assert_eq(SpecComposition.tier({"senses": {"vision": "eyes"}}), SpecComposition.Tier.BODILESS)


#endregion


#region Building a scene
## The piece `a_spec` composes to, written and synced the way the importer does, then loaded.
func _compose(a_name: String, a_spec: Dictionary) -> Node:
	var path: String = SCRATCH % a_name
	var spec: Dictionary = a_spec.duplicate()
	spec["id"] = a_name
	var sync: RefCounted = SceneSync.new()
	assert_true(sync._write_skeleton(path, sync._piece_root_body(spec)), "the skeleton lands")
	var ctx: RefCounted = sync._open(path)
	sync._sync_composition(ctx, spec)
	sync._close(ctx)
	var node: Node = (
		(ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene)
		. instantiate()
	)
	add_child_autofree(node)
	return node


func _child_names(a_node: Node) -> Array[String]:
	var names: Array[String] = []
	for child: Node in a_node.get_children():
		names.append(String(child.name))
	return names


func _expected_names(a_spec: Dictionary) -> Array[String]:
	var names: Array[String] = []
	for entry: Dictionary in SpecComposition.components(a_spec):
		names.append(String(entry["name"]))
	return names


func test_a_unit_is_composed_with_the_actor_set_and_locomotion() -> void:
	var spec: Dictionary = {"movement": MOBILE}
	var unit: Node = _compose("unit", spec)
	assert_true(unit is Commandable)
	assert_eq(_child_names(unit), _expected_names(spec))
	assert_true(unit.get_node("Locomotion") is Movement and unit.has_node("NavigationAgent"))
	assert_false(unit.has_node("Structure"))
	assert_eq(unit.collision_layer, 1, "a mobile Actor collides like every unit")
	assert_eq((unit.get_node("HPBar") as Sprite3D).billboard, BaseMaterial3D.BILLBOARD_FIXED_Y)
	assert_eq(
		(unit.get_node("HPBar/HPBarFill") as Sprite3D).billboard,
		BaseMaterial3D.BILLBOARD_FIXED_Y,
		"an override inside a component instance survives"
	)


func test_a_structure_is_composed_with_its_footprint_and_no_locomotion() -> void:
	var spec: Dictionary = {"footprint": [2, 2]}
	var structure: Node = _compose("structure", spec)
	assert_true(structure is Commandable)
	assert_eq(_child_names(structure), _expected_names(spec))
	assert_true(structure.has_node("Structure") and structure.has_node("FootprintVisualizer"))
	assert_false(structure.has_node("Locomotion"))
	assert_eq((structure.get_node("HPBar") as Sprite3D).billboard, BaseMaterial3D.BILLBOARD_ENABLED)


func test_a_feature_is_a_plain_entity_with_no_actor_components() -> void:
	var spec: Dictionary = {"footprint": [2, 2], "commandable": false}
	var feature: Node = _compose("feature", spec)
	assert_false(feature is Commandable)
	assert_true(feature is Entity)
	assert_eq(_child_names(feature), _expected_names(spec))
	for actor_only: String in ["Defense", "HPBar", "NavigationAgent", "Veterancy"]:
		assert_false(feature.has_node(actor_only), "a feature has no %s" % actor_only)


func test_a_bodiless_piece_is_ownership_and_vision() -> void:
	var bodiless: Node = _compose("bodiless", {"senses": {"vision": "eyes"}})
	assert_eq(_child_names(bodiless), ["VisionRange", "Ownership"])


func test_composing_a_composed_scene_changes_nothing() -> void:
	var spec: Dictionary = {"movement": MOBILE, "id": "again"}
	_compose("again", spec)
	var sync: RefCounted = SceneSync.new()
	var ctx: RefCounted = sync._open(SCRATCH % "again")
	sync._sync_composition(ctx, spec)
	assert_false(ctx.dirty, "every guaranteed component is already there")
	sync._close(ctx)


#endregion


#region A renamed component
## A scene written before a component was renamed carries the OLD node name. The sync renames
## it in place rather than composing a second copy beside it — two locomotion nodes on one
## piece would each drive it, and a duplicate declaration crashes at teardown.
func test_a_renamed_component_is_renamed_in_place_not_duplicated() -> void:
	var path: String = SCRATCH % "legacy"
	var spec: Dictionary = {"id": "legacy", "movement": MOBILE}
	var sync: RefCounted = SceneSync.new()
	assert_true(sync._write_skeleton(path, sync._piece_root_body(spec)), "the skeleton lands")
	var ctx: RefCounted = sync._open(path)
	sync._sync_composition(ctx, spec)
	sync._close(ctx)
	# Put the old name back, as a scene from before the rename would have it.
	var text: String = FileAccess.get_file_as_string(path).replace(
		'[node name="Locomotion"', '[node name="Movement"'
	)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

	ctx = sync._open(path)
	sync._rename_legacy_components(ctx)
	sync._sync_composition(ctx, spec)
	sync._close(ctx)

	var node: Node = (
		(ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene)
		. instantiate()
	)
	add_child_autofree(node)
	assert_false(node.has_node("Movement"), "the old name is gone")
	assert_true(node.get_node("Locomotion") is Movement, "carried over, not replaced")
	assert_eq(
		node.get_children().filter(func(c: Node) -> bool: return c is Movement).size(),
		1,
		"and there is exactly one"
	)


#endregion


#region Flight and docking
## An aircraft's Aerial and Docking sit straight after its Locomotion, which is the tree order
## that ticks flight right after the locomotion it rides on.
func test_an_aircraft_is_composed_with_flight_beside_its_locomotion() -> void:
	var spec: Dictionary = {"movement": MOBILE, "aerial": {"mode": "FLYING"}, "docking": true}
	var jet: Node = _compose("jet", spec)
	var names: Array[String] = _child_names(jet)
	var at: int = names.find("Locomotion")
	assert_eq(names.slice(at, at + 3), ["Locomotion", "Aerial", "Docking"] as Array[String])
	assert_true(jet.get_node("Aerial") is Aerial)
	assert_true(jet.get_node("Docking") is Docking)


func test_a_piece_that_does_not_fly_has_neither() -> void:
	var truck: Node = _compose("truck", {"movement": MOBILE})
	assert_false(truck.has_node("Aerial"))
	assert_false(truck.has_node("Docking"))
#endregion
