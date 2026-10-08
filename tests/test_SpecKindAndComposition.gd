extends GutTest

## `kind:` names the class a spec loads as, and nothing about what a piece IS: a game piece is
## `kind: Entity`, and whether it is built or trained, a unit or a structure, is derived from
## the components its doc declares. See gdd/systems/authoring/composition-rework.md §What
## replaces `kind:` and §Step 3.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gtest=res://tests/test_SpecKindAndComposition.gd -gdir=res://tests/none -gexit

## Preloaded rather than reached through class_name: a headless run does not refresh the
## global class cache. Same reason as test_SpecGenerators.
const SpecGenerators := preload("res://tools/spec_import/generators.gd")
const SceneSync := preload("res://tools/spec_import/scene_sync.gd")
const TscnDoc := preload("res://tools/spec_import/tscn_doc.gd")

const MOBILE: Dictionary = {"speed": "BRISK"}

## Every registry built here carries a speed ladder, as the real gdd/ tree does, so a piece's
## `movement.speed` names a class the way a real doc must.
const SPEEDS: Dictionary = {
	"kind": "SpeedLibrary", "speeds": {"ZERO": 0, "BRISK": 2.93, "SUPERSONIC": 30}
}


func _registry(a_docs: Dictionary) -> RefCounted:
	var docs: Array = [{"path": "res://gdd/x/speed_classes.md", "data": SPEEDS}]
	for id: String in a_docs:
		docs.append({"path": "res://gdd/x/%s.md" % id, "data": a_docs[id]})
	var registry: RefCounted = SpecRegistry.new()
	registry.build(docs)
	return registry


func _errors(a_data: Dictionary) -> Array:
	return _registry({"piece": a_data}).errors


func _assert_refused(a_data: Dictionary, a_fragment: String) -> void:
	var errors: Array = _errors(a_data)
	assert_true(
		errors.any(func(e: String) -> bool: return e.contains(a_fragment)),
		"refused with '%s': %s" % [a_fragment, errors]
	)


#region The kind value
func test_a_piece_with_a_footprint_and_movement_validates() -> void:
	assert_eq(
		_errors({"kind": "Entity", "footprint": [2, 2], "movement": MOBILE}),
		[],
		"the two-form piece is a piece, not an error"
	)


func test_a_piece_declaring_no_body_or_sense_is_refused() -> void:
	_assert_refused({"kind": "Entity", "title": "Nothing"}, "declares no body and no sense")


func test_a_vision_alone_is_a_body_enough() -> void:
	var registry: RefCounted = _registry(
		{
			"shapes": {"kind": "ShapeLibrary", "shapes": {"eyes": {"radius": 5}}},
			"piece": {"kind": "Entity", "senses": {"vision": "eyes"}}
		}
	)
	assert_eq(registry.errors, [], "the bodiless entity")


func test_the_design_categories_are_retired() -> void:
	_assert_refused({"kind": "unit", "movement": MOBILE}, "use `kind: Entity")
	_assert_refused({"kind": "structure", "footprint": [1, 1]}, "use `kind: Entity")
	_assert_refused({"kind": "projectile"}, "an emission is an Entity")
	_assert_refused({"kind": "Projectile"}, "an emission is an Entity")


func test_a_class_spelled_in_lowercase_is_explained() -> void:
	_assert_refused(
		{"kind": "entity", "movement": MOBILE}, "spelled as the class is: `kind: Entity`"
	)
	_assert_refused({"kind": "statuseffect"}, "`kind: StatusEffect`")


func test_build_requires_names_pieces_with_a_footprint() -> void:
	var registry: RefCounted = _registry(
		{
			"hq": {"kind": "Entity", "footprint": [2, 2]},
			"runner": {"kind": "Entity", "movement": MOBILE},
			"tower": {"kind": "Entity", "footprint": [1, 1], "build": {"requires": ["runner"]}},
		}
	)
	assert_true(
		registry.errors.any(func(e: String) -> bool: return e.contains("no footprint")),
		"a requirement must be a structure: %s" % [registry.errors]
	)


#endregion


#region An empty list removes the component
func test_an_empty_list_marks_its_component_for_removal() -> void:
	var registry: RefCounted = _registry(
		{"hq": {"kind": "Entity", "footprint": [2, 2], "trains": [], "builds": ["hq"]}}
	)
	assert_eq(registry.errors, [])
	assert_eq(registry.pieces["hq"]["_remove"], ["trains"], "only the emptied one")


func test_false_is_retired_for_a_collection() -> void:
	_assert_refused({"kind": "Entity", "footprint": [2, 2], "trains": false}, "write `trains: []`")


#endregion


#region Built or trained is derived
func test_a_fixture_is_built_and_anything_else_trained() -> void:
	var registry: RefCounted = _registry(
		{
			"hq": {"kind": "Entity", "footprint": [2, 2], "trains": ["runner"]},
			"runner": {"kind": "Entity", "movement": MOBILE},
			"tower": {"kind": "Entity", "footprint": [1, 1]},
		}
	)
	var producers: Dictionary = SpecGenerators._producers_by_trainee(registry)
	assert_true(SpecGenerators._is_built(registry.pieces["tower"], producers))
	assert_false(SpecGenerators._is_built(registry.pieces["runner"], producers))


func test_a_two_form_piece_someone_trains_is_trained() -> void:
	# The Sputnik: trained, it stands up mobile and deploys later.
	var registry: RefCounted = _registry(
		{
			"hq": {"kind": "Entity", "footprint": [2, 2], "trains": ["sputnik"]},
			"sputnik": {"kind": "Entity", "footprint": [2, 2], "movement": MOBILE},
		}
	)
	var producers: Dictionary = SpecGenerators._producers_by_trainee(registry)
	assert_false(SpecGenerators._is_built(registry.pieces["sputnik"], producers))


#endregion

#region A mobile scene gets the Fixture a footprint asks for
const MOBILE_SCENE: String = """[gd_scene format=3]

[node name="Piece" type="CharacterBody3D"]
"""


## A context whose live instance matches `a_text`: the root, plus a Fixture when it declares one.
func _ctx(a_text: String) -> RefCounted:
	var root: CharacterBody3D = CharacterBody3D.new()
	root.name = "Piece"
	if a_text.contains('[node name="Fixture"'):
		var structure: Node = (load(SceneSync.SCRIPT_FIXTURE) as GDScript).new()
		structure.name = "Fixture"
		root.add_child(structure)
	add_child_autofree(root)
	var ctx := SceneSync.Ctx.new()
	ctx.doc = TscnDoc.from_text(a_text)
	ctx.inst = root
	ctx.path = "res://scenes/entities/units/test_piece.tscn"
	return ctx


func test_a_footprint_on_a_mobile_scene_adds_the_structure_component() -> void:
	var ctx: RefCounted = _ctx(MOBILE_SCENE)
	SceneSync.new()._sync_footprint(ctx, {"footprint": [2, 3]})
	var text: String = ctx.doc.to_text()
	assert_string_contains(text, '[node name="Fixture" type="Node" parent="."]')
	assert_string_contains(text, "dimensions = Vector2i(2, 3)")


func test_dropping_the_footprint_takes_the_component_back_out() -> void:
	var sync := SceneSync.new()
	var ctx: RefCounted = _ctx(MOBILE_SCENE)
	sync._sync_footprint(ctx, {"footprint": [2, 3]})
	var with_structure: String = ctx.doc.to_text()
	var reread: RefCounted = _ctx(with_structure)
	sync._sync_footprint(reread, {})
	assert_eq(reread.doc.to_text(), MOBILE_SCENE, "add then remove gives the bytes back")


#endregion

#region Groups are derived and written
const SpecSchema := preload("res://tools/spec_import/schema.gd")


func test_the_derived_groups_follow_composition() -> void:
	assert_eq(SpecSchema.derived_groups({"movement": MOBILE}), ["piece", "unit"])
	assert_eq(
		SpecSchema.derived_groups({"footprint": [1, 1]}),
		["piece", "fixture", "structure"],
		"a structure is a fixture that takes orders"
	)
	assert_eq(
		SpecSchema.derived_groups({"footprint": [1, 1], "commandable": false}),
		["piece", "fixture"],
		"a feature is a fixture that does not"
	)
	assert_eq(
		SpecSchema.derived_groups({"footprint": [1, 1], "movement": MOBILE}),
		["piece"],
		"a two-form piece's form decides at runtime"
	)
	assert_eq(
		SpecSchema.derived_groups({"movement": MOBILE, "commandable": false}),
		["piece"],
		"a unit takes orders"
	)


func test_groups_are_written_and_an_identity_group_is_kept() -> void:
	var ctx: RefCounted = _ctx(
		"""[gd_scene format=3]

[node name="Piece" type="CharacterBody3D" groups=["shelter", "unit"]]
"""
	)
	SceneSync.new()._sync_groups(ctx, {"footprint": [3, 3]})
	assert_string_contains(ctx.doc.to_text(), 'groups=["piece", "fixture", "structure", "shelter"]')


func test_a_header_attribute_goes_before_the_instance() -> void:
	var doc: RefCounted = (
		TscnDoc
		. from_text(
			"""[gd_scene format=3]

[node name="Unit" unique_id=7 instance=ExtResource("1_base")]
"""
		)
	)
	var root: Dictionary = doc.root_node()
	doc.set_header_attr(root, "groups", '["piece"]')
	assert_string_contains(
		doc.to_text(),
		'[node name="Unit" unique_id=7 groups=["piece"] instance=ExtResource("1_base")]'
	)
	doc.set_header_attr(root, "groups", "")
	assert_string_contains(
		doc.to_text(), '[node name="Unit" unique_id=7 instance=ExtResource("1_base")]'
	)


#endregion


#region Identity components are declared by presence
func test_an_identity_component_follows_its_presence_key() -> void:
	var sync := SceneSync.new()
	var ctx: RefCounted = _ctx(MOBILE_SCENE)
	sync._sync_optional_components(ctx, {"shelter": true})
	var with_shelter: String = ctx.doc.to_text()
	assert_string_contains(with_shelter, '[node name="Shelter" type="Node" parent="."]')
	assert_false(with_shelter.contains("capacity"), "its tuning is the scene's, not the doc's")
	var reread: RefCounted = _ctx(with_shelter)
	var shelter: Node = Node.new()
	shelter.name = "Shelter"
	reread.inst.add_child(shelter)
	sync._sync_optional_components(reread, {"shelter": false})
	assert_eq(reread.doc.to_text(), MOBILE_SCENE, "false takes it out again")


func test_an_identity_key_takes_only_a_bool() -> void:
	_assert_refused(
		{"kind": "Entity", "footprint": [3, 3], "shelter": {"capacity": 3}},
		"its tuning lives in the scene"
	)


#endregion


#region Flight and docking are their own keys
func test_an_aircraft_names_its_mode_under_aerial() -> void:
	assert_eq(
		_errors(
			{"kind": "Entity", "movement": MOBILE, "aerial": {"mode": "FLYING"}, "docking": true}
		),
		[],
		"a docking aircraft validates"
	)


func test_the_moved_movement_keys_say_where_they_went() -> void:
	_assert_refused(
		{"kind": "Entity", "movement": {"mode": "FLYING", "speed": "BRISK"}},
		"movement.mode moved — use aerial.mode"
	)
	_assert_refused(
		{"kind": "Entity", "movement": {"docks": false, "speed": "BRISK"}},
		"movement.docks moved — use docking: true"
	)


func test_grounded_is_not_a_way_of_flying() -> void:
	_assert_refused(
		{"kind": "Entity", "movement": MOBILE, "aerial": {"mode": "GROUNDED"}},
		"aerial.mode must be one of"
	)


func test_an_orbit_is_read_only_by_a_fixed_wing() -> void:
	_assert_refused(
		{"kind": "Entity", "movement": MOBILE, "aerial": {"mode": "HOVERING", "orbit_radius": 2.0}},
		"aerial.orbit_radius is read only"
	)


func test_a_charged_weapon_needs_somewhere_to_recharge() -> void:
	var weapon: Dictionary = {
		"name": "Rocket",
		"charged": true,
		"clip_size": 4,
		"reload_time": 2.0,
		"split_time": 0.5,
		"reach": 4,
		"emits":
		{
			"id": "piece__rocket",
			"damage": 5,
			"damage_type": "LEAD",
			"speed": "SUPERSONIC",
			"trajectory": "LINEAR",
			"hitscan": true
		}
	}
	_assert_refused(
		{"kind": "Entity", "movement": MOBILE, "aerial": {"mode": "FLYING"}, "weapons": [weapon]},
		"has a charged weapon but no `docking: true`"
	)


#endregion


#region What makes a doc a spec, and one scene per doc
func test_an_empty_kind_is_not_a_spec() -> void:
	var registry := SpecRegistry.new()
	assert_false(registry._names_a_kind({"kind": ""}))
	assert_false(registry._names_a_kind({"kind": null}))
	assert_false(registry._names_a_kind({"title": "Untitled"}))
	assert_true(registry._names_a_kind({"kind": "Entity"}))


func test_two_docs_cannot_share_a_scene() -> void:
	var registry := SpecRegistry.new()
	var scene: String = "res://scenes/entities/units/zz_shared.tscn"
	(
		registry
		. build(
			[
				{"path": "res://gdd/zz_first.md", "data": {"kind": "Entity", "scene": scene}},
				{"path": "res://gdd/zz_second.md", "data": {"kind": "Entity", "scene": scene}},
			]
		)
	)
	var shared: Array = registry.errors.filter(
		func(e: String) -> bool: return e.contains("already the scene of")
	)
	assert_eq(shared.size(), 1, "the second doc is refused, naming the first")
#endregion
