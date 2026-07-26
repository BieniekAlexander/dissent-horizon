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

[ext_resource type="PackedScene" uid="uid://base001" path="res://scenes/entities/units/unit.tscn" id="1_base"]
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
split_time = 45

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
	assert_eq(doc.get_prop(doc.find_node(""), "id"), "&\"fixture\"")
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
	var id: String = doc.ensure_ext_resource("Script", "res://scripts/entities/components/loadout.gd")
	assert_eq(id, "2_load")
	assert_eq(doc.to_text(), FIXTURE)   # nothing changed


func test_ensure_ext_resource_adds_and_updates_load_steps() -> void:
	var doc: RefCounted = _doc()
	var id: String = doc.ensure_ext_resource("PackedScene", "res://scenes/entities/projectiles/an/warlord_rocket.tscn")
	var text: String = doc.to_text()
	assert_string_contains(text, "path=\"res://scenes/entities/projectiles/an/warlord_rocket.tscn\" id=\"%s\"" % id)
	assert_string_contains(text, "load_steps=5")
	# Placement: after the last existing ext_resource, before sub_resources.
	assert_lt(text.find("id=\"2_load\""), text.find(id))
	assert_lt(text.find(id), text.find("[sub_resource"))
	# Still parseable and stable on re-round-trip.
	assert_eq(TscnDoc.from_text(text).to_text(), text)


func test_add_sub_resource() -> void:
	var doc: RefCounted = _doc()
	var id: String = doc.add_sub_resource("CylinderShape3D", "reach", {"height": "100.0", "radius": "4.0"})
	var text: String = doc.to_text()
	assert_string_contains(text, "[sub_resource type=\"CylinderShape3D\" id=\"%s\"]" % id)
	assert_string_contains(text, "load_steps=5")
	assert_lt(text.find("CylinderShape3D_vis"), text.find(id))
	assert_lt(text.find(id), text.find("[node name=\"Fixture\""))
	assert_eq(TscnDoc.from_text(text).to_text(), text)


func test_add_node_groups_under_parent_subtree() -> void:
	var doc: RefCounted = _doc()
	doc.add_node(
		[["name", "Weapon2"], ["type", "Node3D"], ["parent", "Loadout"]],
		{"split_time": "30"}
	)
	var text: String = doc.to_text()
	# New sibling lands after the existing Weapon subtree (incl. AttackRange).
	assert_lt(text.find("[node name=\"AttackRange\""), text.find("[node name=\"Weapon2\""))
	assert_eq(TscnDoc.from_text(text).to_text(), text)
	assert_eq(TscnDoc.from_text(text).find_node("Loadout/Weapon2")["attrs"]["parent"], "Loadout")


func test_remove_node_removes_descendants() -> void:
	var doc: RefCounted = _doc()
	doc.remove_node("Loadout/Weapon")
	var text: String = doc.to_text()
	assert_false(text.contains("[node name=\"Weapon\""))
	assert_false(text.contains("[node name=\"AttackRange\""))
	assert_string_contains(text, "[node name=\"Loadout\"")
	assert_eq(TscnDoc.from_text(text).to_text(), text)


func test_fmt_helpers() -> void:
	assert_eq(TscnDoc.fmt_float(1.0), "1.0")
	assert_eq(TscnDoc.fmt_float(1.2), "1.2")
	assert_eq(TscnDoc.fmt_float(0.175), "0.175")
	assert_eq(TscnDoc.fmt_string("a \"b\""), "\"a \\\"b\\\"\"")
	# Newlines/tabs escape so a multi-line editor_description stays one .tscn line.
	assert_eq(TscnDoc.fmt_string("line1\nline2"), "\"line1\\nline2\"")
	assert_eq(TscnDoc.fmt_string_name("warlord"), "&\"warlord\"")
	assert_eq(
		TscnDoc.fmt_string_name_array(["a", "b"]),
		"Array[StringName]([&\"a\", &\"b\"])"
	)
