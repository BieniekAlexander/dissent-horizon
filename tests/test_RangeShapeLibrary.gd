extends GutTest

## A weapon's `reach:` names a SHAPE-LIBRARY bucket (an entry of the one
## `kind: ShapeLibrary` doc, gdd/shapes/shapes.md) rather than carrying a radius of its
## own. Three halves are pinned here: the registry resolves the ids and refuses a bare
## number, the generator writes a loadable cylinder, and the scene sync points range nodes
## at the shared resource.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gtest=res://tests/test_RangeShapeLibrary.gd -gdir=res://tests/none -gexit

## Preloaded rather than reached through class_name: a headless run does not refresh the
## global class cache. Same reason as test_SpecGenerators.
const SpecRegistry := preload("res://tools/spec_import/spec_registry.gd")
const SpecGenerators := preload("res://tools/spec_import/generators.gd")
const SceneSync := preload("res://tools/spec_import/scene_sync.gd")
const TscnDoc := preload("res://tools/spec_import/tscn_doc.gd")

const SHORT_RADIUS: float = 2.5
const LONG_RADIUS: float = 6.0
const BLIND_RADIUS: float = 1.0
const BURST_RADIUS: float = 0.25

## A weapon whose single AttackRange owns a cylinder of its own — the state every scene was
## in before the library existed.
const SCENE_WITH_OWN_CYLINDER: String = """[gd_scene load_steps=2 format=3]

[sub_resource type="CylinderShape3D" id="CylinderShape3D_attack_range"]
height = 100.0
radius = 6.0

[node name="Piece" type="CharacterBody3D"]

[node name="Loadout" type="Node" parent="."]

[node name="Gun" type="Node3D" parent="Loadout"]

[node name="AttackRange" type="CollisionShape3D" parent="Loadout/Gun"]
shape = SubResource("CylinderShape3D_attack_range")
"""

const LIBRARY_PATH: String = "res://gdd/x/shapes.md"


## A registry over one ShapeLibrary doc — the four fixture shapes plus [a_shapes] — and
## the docs in [a_docs], keyed by id.
func _registry(a_docs: Dictionary, a_shapes: Dictionary = {}) -> RefCounted:
	var entries: Dictionary = {
		"short": {"radius": SHORT_RADIUS},
		"long": {"kind": "CylinderShape3D", "radius": LONG_RADIUS},
		"blind": {"radius": BLIND_RADIUS},
		"burst": {"kind": "SphereShape3D", "radius": BURST_RADIUS},
	}
	entries.merge(a_shapes)
	var docs: Array = [
		{"path": LIBRARY_PATH, "data": {"kind": "ShapeLibrary", "shapes": entries}},
	]
	for id: String in a_docs:
		docs.append({"path": "res://gdd/x/%s.md" % id, "data": a_docs[id]})
	var registry: RefCounted = SpecRegistry.new()
	registry.build(docs)
	return registry


func _piece_with_reach(a_reach: Variant, a_hits: Array = ["ground"]) -> Dictionary:
	return {
		"kind": "Entity",
		"senses": {"vision": "long"},
		"weapons": [{"name": "Gun", "melee_damage": 1, "reach": a_reach, "hits": a_hits}]
	}


func _assert_refused(a_registry: RefCounted, a_fragment: String) -> void:
	assert_true(
		a_registry.errors.any(func(e: String) -> bool: return e.contains(a_fragment)),
		"refused with '%s': %s" % [a_fragment, a_registry.errors]
	)


#region The registry
func test_each_library_entry_is_registered_as_a_shape() -> void:
	var registry: RefCounted = _registry({})

	assert_eq(registry.errors, [])
	assert_eq(registry.shapes.keys().size(), 4)
	assert_eq(
		registry.shapes["short"]["_doc_path"],
		LIBRARY_PATH,
		"an error or a generated resource points back at the one library doc"
	)
	assert_false(registry.specs.has("shapes"), "the library doc itself is not a spec")


func test_an_entry_with_no_kind_is_a_cylinder() -> void:
	assert_eq(_registry({}).shapes["short"]["kind"], "CylinderShape3D")


func test_a_shape_doc_of_its_own_is_retired() -> void:
	_assert_refused(
		_registry({"loose": {"kind": "CylinderShape3D", "radius": 1}}),
		"`kind: CylinderShape3D` is retired"
	)
	_assert_refused(
		_registry({"loose": {"kind": "SphereShape3D", "radius": 1}}),
		"`kind: SphereShape3D` is retired"
	)


func test_an_entry_id_shares_the_spec_namespace() -> void:
	_assert_refused(
		_registry({"short": {"kind": "Entity", "footprint": [1, 1]}}), "duplicate id 'short'"
	)


func test_an_entry_of_an_unknown_class_is_refused() -> void:
	_assert_refused(
		_registry({}, {"box": {"kind": "BoxShape3D", "radius": 1}}), "a shape's kind must be one of"
	)


func test_an_unknown_library_key_is_refused() -> void:
	var registry: RefCounted = SpecRegistry.new()
	registry.build(
		[
			{
				"path": LIBRARY_PATH,
				"data": {"kind": "ShapeLibrary", "radius": 3, "shapes": {"a": {"radius": 1}}}
			}
		]
	)
	_assert_refused(registry, "unknown ShapeLibrary key 'radius'")


func test_one_id_is_the_reach_on_every_layer() -> void:
	var registry: RefCounted = _registry({"piece": _piece_with_reach("short")})

	assert_eq(registry.errors, [])
	assert_eq(
		registry.pieces["piece"]["weapons"][0]["_reach_radii"],
		{"ground": SHORT_RADIUS, "air": SHORT_RADIUS}
	)


func test_a_mapping_resolves_each_layer_separately() -> void:
	var registry: RefCounted = _registry(
		{"piece": _piece_with_reach({"ground": "short", "air": "long"}, ["ground", "air"])}
	)

	assert_eq(registry.errors, [])
	assert_eq(
		registry.pieces["piece"]["weapons"][0]["_reach_radii"],
		{"ground": SHORT_RADIUS, "air": LONG_RADIUS}
	)


func test_a_bare_number_is_refused() -> void:
	# A per-weapon radius is exactly what the library replaced.
	_assert_refused(_registry({"piece": _piece_with_reach(5)}), "range library")


func test_an_unknown_shape_is_refused() -> void:
	_assert_refused(_registry({"piece": _piece_with_reach("medium")}), "range library")


func test_a_shape_needs_a_radius_and_only_a_cylinder_takes_a_height() -> void:
	_assert_refused(_registry({}, {"bad": {}}), "needs radius")
	_assert_refused(
		_registry({}, {"bad": {"kind": "SphereShape3D", "radius": 1, "height": 10}}),
		"a sphere is only a radius"
	)
	assert_eq(_registry({}, {"ok": {"radius": 1, "height": 10}}).errors, [])


func test_a_sense_names_a_shape_and_keeps_its_radius() -> void:
	var registry: RefCounted = _registry({"piece": _piece_with_reach("short")})
	var spec: Dictionary = registry.pieces["piece"]

	assert_eq(spec["vision"], LONG_RADIUS, "the rules keep reading a number")
	assert_eq(spec["_shape_ids"], {"vision": "long"}, "the sync keeps the name")


func test_a_sense_given_a_number_is_refused() -> void:
	var piece: Dictionary = _piece_with_reach("short")
	piece["senses"] = {"vision": 10}
	_assert_refused(_registry({"piece": piece}), "must name a shape from the library")


func test_a_sense_can_still_be_taken_away() -> void:
	var registry: RefCounted = _registry(
		{"piece": {"kind": "Entity", "footprint": [1, 1], "senses": {"vision": false}}}
	)
	assert_eq(registry.errors, [])
	assert_eq(registry.pieces["piece"]["vision"], 0)


func test_a_blast_names_a_shape() -> void:
	var registry: RefCounted = _registry({"boom": {"kind": "Entity", "blast": "burst"}})
	assert_eq(registry.projectiles["boom"]["blast"], BURST_RADIUS)
	_assert_refused(
		_registry({"boom": {"kind": "Entity", "blast": 2}}), "must name a shape from the library"
	)


func test_the_calibration_rules_measure_the_resolved_radius() -> void:
	# A piece that shoots further than it sees: the rule only fires if it reads the library
	# radius (2.5), since `reach:` itself is now a name.
	var tower: Dictionary = {
		"kind": "Entity",
		"footprint": [1, 1],
		"senses": {"vision": "blind"},
		"weapons": [{"name": "Gun", "melee_damage": 1, "reach": "short"}],
	}
	var registry: RefCounted = _registry({"tower": tower})

	_assert_refused(registry, "reaches 2.5 but sees 1")


#endregion


#region The generator
func test_the_generated_resource_loads_as_a_tall_cylinder() -> void:
	var path: String = "user://test_range_shape.tres"
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(
		SpecGenerators.shape_tres_text(
			{"_doc_path": "res://gdd/x/short.md", "radius": SHORT_RADIUS}
		)
	)
	f.close()

	var shape: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)

	assert_true(shape is CylinderShape3D, "the header comment does not stop it parsing")
	assert_eq((shape as CylinderShape3D).radius, SHORT_RADIUS)
	assert_eq(
		(shape as CylinderShape3D).height,
		SceneSync.SHAPE_HEIGHT,
		"never authored: a short cylinder would put cruising aircraft out of reach"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_sphere_generates_without_a_height_and_a_cylinder_keeps_its_own() -> void:
	var sphere: String = SpecGenerators.shape_tres_text(
		{"_doc_path": "x.md", "kind": "SphereShape3D", "radius": BURST_RADIUS}
	)
	assert_string_contains(sphere, 'type="SphereShape3D"')
	assert_false(sphere.contains("height"))
	var squat: String = SpecGenerators.shape_tres_text(
		{"_doc_path": "x.md", "kind": "CylinderShape3D", "radius": 1.0, "height": 7.0}
	)
	assert_string_contains(squat, "height = 7.0")


func test_the_tooltip_reads_one_number_when_both_layers_agree() -> void:
	assert_eq(SpecGenerators._reach_phrase({"ground": 5.0, "air": 5.0}), "5")
	assert_eq(SpecGenerators._reach_phrase({"ground": 5.0, "air": 10.0}), "5 ground / 10 air")
	assert_eq(SpecGenerators._reach_phrase({"air": 6.0}), "6 air")


#endregion


#region The scene sync
func _ctx() -> RefCounted:
	var root := CharacterBody3D.new()
	root.name = "Piece"
	var loadout := Node.new()
	loadout.name = "Loadout"
	root.add_child(loadout)
	var gun := Node3D.new()
	gun.name = "Gun"
	loadout.add_child(gun)
	var range_node := CollisionShape3D.new()
	range_node.name = "AttackRange"
	range_node.shape = CylinderShape3D.new()
	gun.add_child(range_node)
	add_child_autofree(root)
	var ctx := SceneSync.Ctx.new()
	ctx.doc = TscnDoc.from_text(SCENE_WITH_OWN_CYLINDER)
	ctx.inst = root
	ctx.path = "res://scenes/entities/units/test_piece.tscn"
	return ctx


func test_one_id_points_the_range_node_at_the_library() -> void:
	var sync := SceneSync.new()
	var ctx: RefCounted = _ctx()

	sync._sync_reach(ctx, "Loadout/Gun", "short", ctx.inst.get_node("Loadout/Gun"))

	var text: String = ctx.doc.to_text()
	assert_string_contains(text, 'path="%s"' % SpecGenerators.shape_path("short"))
	assert_false(
		text.contains("CylinderShape3D_attack_range"),
		"the scene's own cylinder has no user left, so it does not stay behind"
	)


func test_a_mapping_splits_a_locally_declared_range_node() -> void:
	var sync := SceneSync.new()
	var ctx: RefCounted = _ctx()

	sync._sync_reach(
		ctx, "Loadout/Gun", {"ground": "short", "air": "long"}, ctx.inst.get_node("Loadout/Gun")
	)

	var text: String = ctx.doc.to_text()
	assert_false(text.contains('name="AttackRange" '), "the single node is replaced")
	assert_string_contains(text, 'name="AttackRangeGround"')
	assert_string_contains(text, 'name="AttackRangeAir"')
	assert_string_contains(text, 'path="%s"' % SpecGenerators.shape_path("long"))
	assert_eq(sync.report["warnings"], [])


func test_a_node_already_on_its_shape_is_left_alone() -> void:
	var sync := SceneSync.new()
	var ctx: RefCounted = _ctx()
	var path: String = SpecGenerators.shape_path("test_only_never_generated")
	ctx.inst.get_node("Loadout/Gun/AttackRange").shape.resource_path = path

	sync._set_shape_resource(ctx, "Loadout/Gun/AttackRange", path)

	assert_false(ctx.dirty, "an import that changes nothing writes nothing")


#endregion

#region The blast
## A projectile inheriting the base's 0.05-scaled HitShape, the state every emission is in
## before its doc names a blast.
const PROJECTILE_SCENE: String = """[gd_scene load_steps=2 format=3]

[sub_resource type="SphereShape3D" id="SphereShape3D_blast"]
radius = 1.5

[node name="Shell" type="Node3D"]

[node name="HitShape" type="CollisionShape3D" parent="."]
transform = Transform3D(0.05, 0, 0, 0, 0.05, 0, 0, 0, 0.05, 0, 0, 0)
shape = SubResource("SphereShape3D_blast")
"""


func test_a_blast_points_the_hit_shape_at_the_library_at_full_scale() -> void:
	var root := Node3D.new()
	root.name = "Shell"
	var hit := CollisionShape3D.new()
	hit.name = "HitShape"
	hit.shape = SphereShape3D.new()
	hit.transform = Transform3D(Basis.from_scale(Vector3.ONE * 0.05), Vector3.ZERO)
	root.add_child(hit)
	add_child_autofree(root)
	var ctx := SceneSync.Ctx.new()
	ctx.doc = TscnDoc.from_text(PROJECTILE_SCENE)
	ctx.inst = root
	ctx.path = "res://scenes/entities/projectiles/test_shell.tscn"

	SceneSync.new()._set_blast_shape(ctx, SpecGenerators.shape_path("aoe_test"))

	var text: String = ctx.doc.to_text()
	assert_string_contains(text, "aoe_test.tres")
	assert_string_contains(
		text,
		"Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)",
		"the base's 0.05 scale would shrink every bucket twentyfold"
	)
	assert_false(text.contains("SphereShape3D_blast"), "the old sphere has no user left")


#endregion


#region Garrison reach
func _host(a_garrison: Dictionary) -> Dictionary:
	return {
		"kind": "Entity", "footprint": [1, 1], "senses": {"vision": "long"}, "garrison": a_garrison
	}


func test_a_range_bonus_is_the_gap_between_two_buckets() -> void:
	var registry: RefCounted = _registry(
		{"host": _host({"range_bonus": {"from": "short", "to": "long"}})}
	)
	assert_eq(registry.errors, [])
	assert_almost_eq(
		float(registry.pieces["host"]["garrison"]["range_bonus"]), LONG_RADIUS - SHORT_RADIUS, 0.001
	)


func test_a_numeric_range_bonus_is_refused() -> void:
	_assert_refused(_registry({"host": _host({"range_bonus": 4})}), "garrison.range_bonus")


func test_a_range_bonus_that_shortens_is_refused() -> void:
	_assert_refused(
		_registry({"host": _host({"range_bonus": {"from": "long", "to": "short"}})}),
		"shorter bucket to a longer one"
	)


func test_a_reach_by_piece_resolves_to_the_bucket_radius() -> void:
	var registry: RefCounted = _registry(
		{
			"host": _host({"reach_by_piece": {"piece": "long"}}),
			"piece": _piece_with_reach("short"),
		}
	)
	assert_eq(registry.errors, [])
	assert_eq(registry.pieces["host"]["garrison"]["reach_by_piece"], {"piece": LONG_RADIUS})


func test_a_reach_by_piece_must_name_a_bucket_and_a_piece() -> void:
	_assert_refused(
		_registry({"host": _host({"reach_by_piece": {"nobody": "long"}})}), "unknown piece 'nobody'"
	)
	_assert_refused(
		_registry({"host": _host({"reach_by_piece": {"host": 12}})}),
		"garrison.reach_by_piece.host must name a shape"
	)
#endregion
