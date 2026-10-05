extends GutTest

## Preloaded (not via class_name) so the test runs even when the global class
## cache hasn't rescanned new files (headless runs don't refresh it).
const TscnDoc := preload("res://tools/spec_import/tscn_doc.gd")

## TscnDoc: the text-level .tscn editor the spec importer writes scenes through.
## The load-bearing guarantee is byte-identical round-tripping of unmodified
## files (that's what makes importer runs idempotent), checked here against
## EVERY entity/faction scene in the repo, plus targeted mutation behavior on a
## synthetic fixture.

const FIXTURE: String = """[gd_scene load_steps=4 format=3 uid="uid://fixture001"]

[ext_resource type="PackedScene" path="res://scenes/entities/units/unit.tscn" id="1_base"]
[ext_resource type="Script" path="res://scripts/entities/components/loadout.gd" id="2_load"]

[sub_resource type="CylinderShape3D" id="CylinderShape3D_vis"]
radius = 6.0

[node name="Fixture" instance=ExtResource("1_base")]
id = &"fixture"

[node name="VisionRange" parent="." index="5"]
shape = SubResource("CylinderShape3D_vis")

[node name="Movement" parent="." index="7"]
speed = 1.2
turn_rate = 1080.0

[node name="Loadout" type="Node3D" parent="." index="13"]
script = ExtResource("2_load")

[node name="Weapon" type="Node3D" parent="Loadout" index="0"]
split_time_ticks = 45

[node name="AttackRange" type="CollisionShape3D" parent="Loadout/Weapon" index="0"]
disabled = true
"""


func _doc() -> RefCounted:
	return TscnDoc.from_text(FIXTURE)


func test_round_trip_is_byte_identical_for_fixture() -> void:
	assert_eq(_doc().to_text(), FIXTURE)


func test_round_trip_is_byte_identical_for_every_repo_scene() -> void:
	var paths: Array = _all_scene_paths(["res://scenes/entities", "res://scenes/factions"])
	assert_gt(paths.size(), 30, "scene discovery should find the entity roster")
	for path in paths:
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		var original: String = f.get_as_text()
		f.close()
		assert_eq(TscnDoc.from_text(original).to_text(), original, "round-trip mismatch: %s" % path)


func _all_scene_paths(a_dirs: Array) -> Array:
	var out: Array = []
	for dir_path in a_dirs:
		_collect_scenes(dir_path, out)
	return out


func _collect_scenes(a_dir: String, a_out: Array) -> void:
	var da: DirAccess = DirAccess.open(a_dir)
	if da == null:
		return
	da.list_dir_begin()
	var fn: String = da.get_next()
	while fn != "":
		var full: String = a_dir.path_join(fn)
		if da.current_is_dir():
			if not fn.begins_with("."):
				_collect_scenes(full, a_out)
		elif fn.get_extension() == "tscn":
			a_out.append(full)
		fn = da.get_next()
	da.list_dir_end()


func test_find_node_by_path() -> void:
	var doc: RefCounted = _doc()
	assert_eq(doc.find_node("")["attrs"]["name"], "Fixture")
	assert_eq(doc.find_node("Movement")["attrs"]["name"], "Movement")
	assert_eq(doc.find_node("Loadout/Weapon")["attrs"]["parent"], "Loadout")
	assert_eq(doc.find_node("Loadout/Weapon/AttackRange")["attrs"]["parent"], "Loadout/Weapon")
	assert_true(doc.find_node("Nonexistent").is_empty())


func test_get_prop() -> void:
	var doc: RefCounted = _doc()
	assert_eq(doc.get_prop(doc.find_node("Movement"), "speed"), "1.2")
	assert_eq(doc.get_prop(doc.find_node(""), "id"), '&"fixture"')
	assert_eq(doc.get_prop(doc.find_node("Movement"), "absent"), "")


func test_set_prop_replaces_in_place() -> void:
	var doc: RefCounted = _doc()
	doc.set_prop(doc.find_node("Movement"), "speed", "2.5")
	var text: String = doc.to_text()
	assert_string_contains(text, "speed = 2.5")
	assert_false(text.contains("speed = 1.2"))
	# Order preserved: speed still precedes turn_rate.
	assert_lt(text.find("speed = 2.5"), text.find("turn_rate = 1080.0"))


func test_set_prop_appends_before_blank_separator() -> void:
	var doc: RefCounted = _doc()
	doc.set_prop(doc.find_node("Movement"), "reverse_speed_ratio", "0.35")
	var lines: Array = doc.find_node("Movement")["lines"]
	assert_eq(lines[3], "reverse_speed_ratio = 0.35")
	assert_eq(lines[4], "")


func test_remove_prop() -> void:
	var doc: RefCounted = _doc()
	doc.remove_prop(doc.find_node("Movement"), "turn_rate")
	assert_false(doc.to_text().contains("turn_rate"))
	assert_string_contains(doc.to_text(), "speed = 1.2")


func test_ensure_ext_resource_dedupes_by_path() -> void:
	var doc: RefCounted = _doc()
	var id: String = doc.ensure_ext_resource(
		"Script", "res://scripts/entities/components/loadout.gd"
	)
	assert_eq(id, "2_load")
	assert_eq(doc.to_text(), FIXTURE)  # nothing changed


func test_ensure_ext_resource_adds_and_updates_load_steps() -> void:
	var doc: RefCounted = _doc()
	var id: String = doc.ensure_ext_resource(
		"PackedScene", "res://scenes/entities/projectiles/an/warlord_rocket.tscn"
	)
	var text: String = doc.to_text()
	assert_string_contains(
		text, 'path="res://scenes/entities/projectiles/an/warlord_rocket.tscn" id="%s"' % id
	)
	assert_string_contains(text, "load_steps=5")
	# Placement: after the last existing ext_resource, before sub_resources.
	assert_lt(text.find('id="2_load"'), text.find(id))
	assert_lt(text.find(id), text.find("[sub_resource"))
	# Still parseable and stable on re-round-trip.
	assert_eq(TscnDoc.from_text(text).to_text(), text)


func test_add_sub_resource() -> void:
	var doc: RefCounted = _doc()
	var id: String = doc.add_sub_resource(
		"CylinderShape3D", "reach", {"height": "100.0", "radius": "4.0"}
	)
	var text: String = doc.to_text()
	assert_string_contains(text, '[sub_resource type="CylinderShape3D" id="%s"]' % id)
	assert_string_contains(text, "load_steps=5")
	assert_lt(text.find("CylinderShape3D_vis"), text.find(id))
	assert_lt(text.find(id), text.find('[node name="Fixture"'))
	assert_eq(TscnDoc.from_text(text).to_text(), text)


func test_add_node_groups_under_parent_subtree() -> void:
	var doc: RefCounted = _doc()
	doc.add_node(
		[["name", "Weapon2"], ["type", "Node3D"], ["parent", "Loadout"]], {"split_time_ticks": "30"}
	)
	var text: String = doc.to_text()
	# New sibling lands after the existing Weapon subtree (incl. AttackRange).
	assert_lt(text.find('[node name="AttackRange"'), text.find('[node name="Weapon2"'))
	assert_eq(TscnDoc.from_text(text).to_text(), text)
	assert_eq(TscnDoc.from_text(text).find_node("Loadout/Weapon2")["attrs"]["parent"], "Loadout")


func test_remove_node_removes_descendants() -> void:
	var doc: RefCounted = _doc()
	doc.remove_node("Loadout/Weapon")
	var text: String = doc.to_text()
	assert_false(text.contains('[node name="Weapon"'))
	assert_false(text.contains('[node name="AttackRange"'))
	assert_string_contains(text, '[node name="Loadout"')
	assert_eq(TscnDoc.from_text(text).to_text(), text)


## Removing a component must take its script entry with it. Godot LOADS every
## [ext_resource], referenced or not, so an orphan left pointing at a script that is later
## deleted makes the scene emit errors on every load — which is how eight scenes ended up
## carrying a retired `SanctionCaster` reference nothing could resolve.
func test_remove_node_prunes_the_ext_resource_it_orphaned() -> void:
	var doc: RefCounted = _doc()
	doc.remove_node("Loadout")
	var text: String = doc.to_text()
	assert_false(text.contains("loadout.gd"), "the component's script entry goes with it")
	assert_string_contains(text, "load_steps=3", "and load_steps is corrected")
	assert_eq(TscnDoc.from_text(text).to_text(), text)


func test_pruning_spares_an_ext_resource_something_still_uses() -> void:
	var doc: RefCounted = _doc()
	doc.remove_node("Loadout")
	var text: String = doc.to_text()
	assert_string_contains(text, "unit.tscn", "the base scene is still instanced by the root")


func test_removing_a_node_leaves_unrelated_ext_resources_alone() -> void:
	# Only the removal's own orphans go. A node with no script entry of its own must not
	# take anything with it.
	var doc: RefCounted = _doc()
	doc.remove_node("Movement")
	var text: String = doc.to_text()
	assert_string_contains(text, "loadout.gd")
	assert_string_contains(text, "unit.tscn")


# --------------------------------------------------------------------------- #
# Removal is TOTAL — the step 0 contract
# --------------------------------------------------------------------------- #
## Composition makes removal routine: deleting a doc key deletes a node, on every run. That
## turns "add, then remove, and the bytes come back" from a nicety into the property the
## whole pass rests on — residue (an unread script entry, a shape nothing points at, a
## stale load_steps) makes the NEXT add differ from the first, and the difference
## compounds silently. These tests are that contract, per component shape the importer
## creates. See gdd/systems/authoring/composition-rework.md §Step 0.


## Add a component the way the importer does, remove it again, and the file must be the
## bytes it started as. Parameterised over the shapes the importer actually creates: a
## script-only Node, a Node3D component, and a CollisionShape3D that brings its own
## sub_resource (which is most of them — every doc-governed radius is a shape).
func test_removing_a_created_component_gives_the_bytes_back() -> void:
	for name: String in ["Repairs", "Abilities", "DetectionRange"]:
		var doc: RefCounted = _doc()
		_add_component(doc, name)
		doc.remove_node(name)
		assert_eq(doc.to_text(), FIXTURE, "%s: add then remove left residue" % name)


func test_add_remove_add_is_byte_identical() -> void:
	for name: String in ["Repairs", "Abilities", "DetectionRange"]:
		var once: RefCounted = _doc()
		_add_component(once, name)
		var twice: RefCounted = _doc()
		_add_component(twice, name)
		twice.remove_node(name)
		var again: RefCounted = TscnDoc.from_text(twice.to_text())
		_add_component(again, name)
		assert_eq(
			again.to_text(), once.to_text(), "%s: the second add must reproduce the first" % name
		)


## The three creation shapes, spelled the way SpecSceneSync spells them.
func _add_component(a_doc: RefCounted, a_name: String) -> void:
	match a_name:
		"DetectionRange":
			var sid: String = a_doc.add_sub_resource(
				"CylinderShape3D", "detection_range", {"height": "100.0", "radius": "3.5"}
			)
			a_doc.add_node(
				[["name", a_name], ["type", "CollisionShape3D"], ["parent", "."]],
				{"disabled": "true", "shape": 'SubResource("%s")' % sid}
			)
		_:
			var script_id: String = a_doc.ensure_ext_resource(
				"Script", "res://scripts/entities/components/%s.gd" % a_name.to_snake_case()
			)
			a_doc.add_node(
				[
					["name", a_name],
					["type", "Node" if a_name == "Repairs" else "Node3D"],
					["parent", "."]
				],
				{"script": 'ExtResource("%s")' % script_id}
			)


func _with_repairs() -> RefCounted:
	var doc: RefCounted = _doc()
	var id: String = doc.ensure_ext_resource(
		"Script", "res://scripts/entities/components/repairs.gd"
	)
	doc.add_node(
		[["name", "Repairs"], ["type", "Node"], ["parent", "."]],
		{"script": 'ExtResource("%s")' % id}
	)
	return doc


## Every doc-governed SHAPE is a sub_resource, so a component that owns one is the common
## case rather than the rare one. Leaving the shape behind was defensible while removal was
## a bug fix on a rarely-taken path; under composition it is the residue that breaks the
## identity above.
func test_remove_node_prunes_the_sub_resource_it_orphaned() -> void:
	var doc: RefCounted = _doc()
	doc.remove_node("VisionRange")
	var text: String = doc.to_text()
	assert_false(text.contains("CylinderShape3D_vis"), "the node's own shape goes with it")
	assert_string_contains(text, "load_steps=3", "and load_steps is corrected")
	assert_eq(TscnDoc.from_text(text).to_text(), text)


func test_pruning_spares_a_sub_resource_another_node_still_uses() -> void:
	var doc: RefCounted = _doc()
	doc.add_node(
		[["name", "AggroRange"], ["type", "CollisionShape3D"], ["parent", "."]],
		{"shape": 'SubResource("CylinderShape3D_vis")'}
	)
	doc.remove_node("VisionRange")
	assert_string_contains(doc.to_text(), "CylinderShape3D_vis", "still referenced elsewhere")


## Reachability is transitive: a mesh names its material, so a sub_resource can be live
## purely because another live sub_resource points at it.
func test_pruning_is_transitive_through_sub_resources() -> void:
	const NESTED: String = """[gd_scene load_steps=3 format=3 uid="uid://nested001"]

[sub_resource type="StandardMaterial3D" id="Material_a"]
albedo_color = Color(1, 1, 1, 1)

[sub_resource type="BoxMesh" id="Mesh_a"]
material = SubResource("Material_a")

[node name="Root" type="Node3D"]

[node name="Model" type="MeshInstance3D" parent="."]
mesh = SubResource("Mesh_a")
"""
	var doc: RefCounted = TscnDoc.from_text(NESTED)
	assert_eq(doc.to_text(), NESTED)
	doc.remove_node("Model")
	var text: String = doc.to_text()
	assert_false(text.contains("Mesh_a"), "the mesh had one referrer")
	assert_false(text.contains("Material_a"), "and so the material it named is unreachable too")
	assert_false(
		text.contains("load_steps"),
		"no resources left, so the count goes, as Godot writes a scene with none"
	)


func test_a_live_sub_resource_keeps_the_material_it_names() -> void:
	const NESTED: String = """[gd_scene load_steps=3 format=3 uid="uid://nested002"]

[sub_resource type="StandardMaterial3D" id="Material_a"]
albedo_color = Color(1, 1, 1, 1)

[sub_resource type="BoxMesh" id="Mesh_a"]
material = SubResource("Material_a")

[node name="Root" type="Node3D"]

[node name="Spare" type="Node3D" parent="."]

[node name="Model" type="MeshInstance3D" parent="."]
mesh = SubResource("Mesh_a")
"""
	var doc: RefCounted = TscnDoc.from_text(NESTED)
	doc.remove_node("Spare")
	var text: String = doc.to_text()
	assert_string_contains(text, "Mesh_a", "the mesh still has a referrer")
	assert_string_contains(text, "Material_a", "and so does the material it names")
	assert_string_contains(text, "load_steps=3")


## The acceptance criterion stated in the plan, as a standing check: nothing in the entity
## roster points at a resource file that is not there. An orphan ext_resource is LOADED
## anyway, so one left behind by a removal makes the scene error on every load once the
## file it names is deleted.
func test_no_entity_scene_references_a_missing_resource() -> void:
	var dangling: Array = []
	for path in _all_scene_paths(["res://scenes/entities", "res://scenes/factions"]):
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		var doc: RefCounted = TscnDoc.from_text(f.get_as_text())
		f.close()
		for section in doc.sections_of("ext_resource"):
			var res_path: String = section["attrs"].get("path", "")
			if (
				res_path != ""
				and not ResourceLoader.exists(res_path)
				and not FileAccess.file_exists(res_path)
			):
				dangling.append("%s -> %s" % [path, res_path])
	assert_eq(dangling, [], "scenes pointing at resources that do not exist")


## Removal has to survive the real roster, not just a fixture: pull each scene's own
## root-level component nodes out one at a time and check the document still parses,
## round-trips, and names no resource it no longer defines.
func test_removing_any_component_from_any_roster_scene_leaves_no_dangling_reference() -> void:
	var checked: int = 0
	for path in _all_scene_paths(["res://scenes/entities"]):
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		var original: String = f.get_as_text()
		f.close()
		for node_path in _own_root_node_paths(TscnDoc.from_text(original)):
			var doc: RefCounted = TscnDoc.from_text(original)
			doc.remove_node(node_path)
			var text: String = doc.to_text()
			var reparsed: RefCounted = TscnDoc.from_text(text)
			assert_eq(
				reparsed.to_text(), text, "%s minus %s no longer round-trips" % [path, node_path]
			)
			assert_eq(
				_undefined_refs(reparsed),
				[],
				"%s minus %s references a resource it no longer defines" % [path, node_path]
			)
			checked += 1
	assert_gt(checked, 100, "the sweep should reach the whole roster")


## Node paths the FILE declares directly under the root (an inherited node with no override
## has no section, and cannot be removed by a text edit anyway).
func _own_root_node_paths(a_doc: RefCounted) -> Array:
	var out: Array = []
	for section in a_doc.sections_of("node"):
		if section["attrs"].get("parent", "") == ".":
			out.append(TscnDoc.node_path_of(section))
	return out


## Resource ids the document REFERENCES but no longer DEFINES.
func _undefined_refs(a_doc: RefCounted) -> Array:
	var defined: Dictionary = {}
	for tag: String in ["ext_resource", "sub_resource"]:
		for section in a_doc.sections_of(tag):
			defined[section["attrs"].get("id", "")] = true
	var missing: Dictionary = {}
	var pattern: RegEx = RegEx.create_from_string('(?:Ext|Sub)Resource\\("([^"]+)"\\)')
	for section in a_doc.sections:
		for line in section["lines"]:
			for hit in pattern.search_all(line):
				if not defined.has(hit.get_string(1)):
					missing[hit.get_string(1)] = true
	var out: Array = missing.keys()
	out.sort()
	return out


func test_fmt_helpers() -> void:
	assert_eq(TscnDoc.fmt_float(1.0), "1.0")
	assert_eq(TscnDoc.fmt_float(1.2), "1.2")
	assert_eq(TscnDoc.fmt_float(0.175), "0.175")
	assert_eq(TscnDoc.fmt_string('a "b"'), '"a \\"b\\""')
	# Newlines/tabs escape so a multi-line editor_description stays one .tscn line.
	assert_eq(TscnDoc.fmt_string("line1\nline2"), '"line1\\nline2"')
	assert_eq(TscnDoc.fmt_string_name("warlord"), '&"warlord"')
	assert_eq(TscnDoc.fmt_string_name_array(["a", "b"]), 'Array[StringName]([&"a", &"b"])')
