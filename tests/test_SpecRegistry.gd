extends GutTest

## Preloaded (not via class_name) so the test runs even when the global class
## cache hasn't rescanned new files.
const SpecRegistry := preload("res://tools/spec_import/spec_registry.gd")

## SpecRegistry: doc discovery, id namespace, and the validate-before-write
## contract. Two layers: synthetic docs exercise each failure mode; the real
## gdd/ tree must validate cleanly (it is the seeded source of truth).


func _registry(a_docs: Array) -> RefCounted:
	var r: RefCounted = SpecRegistry.new()
	r.build(a_docs)
	return r


func _doc(a_path: String, a_data: Dictionary) -> Dictionary:
	return {"path": a_path, "data": a_data}


const UNIT_SCENE: String = "res://scenes/entities/units/an/warlord.tscn"
const STRUCTURE_SCENE: String = "res://scenes/entities/structures/an/stronghold.tscn"


func test_real_gdd_tree_validates_cleanly() -> void:
	var r: RefCounted = SpecRegistry.new().scan("res://gdd")
	assert_eq(r.errors, [], "seeded gdd docs must validate")
	assert_gt(r.pieces.size(), 20)
	assert_gt(r.factions.size(), 1)


func test_faction_ids_are_generic_ideologies_with_titles() -> void:
	var r: RefCounted = SpecRegistry.new().scan("res://gdd")
	# Faction ids are the generic ideology, not the flavor name; the flavor lives
	# in `title` (which the importer writes to the scene faction_name).
	assert_true(r.factions.has("anarchical"), "anarchical faction id")
	assert_true(r.factions.has("colonial"), "colonial faction id")
	assert_false(r.factions.has("baladians"), "flavor name is not the id")
	for id in r.factions:
		assert_true(r.factions[id].has("title"), "faction '%s' has a title" % id)


func test_every_spec_carries_a_title() -> void:
	var r: RefCounted = SpecRegistry.new().scan("res://gdd")
	for id in r.specs:
		assert_true(r.specs[id].has("title"), "spec '%s' has a title" % id)
	# Non-faction specs currently mirror the id into the title (flavor TBD).
	assert_eq(str(r.pieces["warlord"]["title"]), "warlord")


func test_prose_docs_are_ignored() -> void:
	var r: RefCounted = SpecRegistry.new().scan("res://gdd")
	# Faction overview prose has no `id:` and must not register or error.
	assert_false(r.specs.has("overview"))


## Discovery is by the `id` key: a doc with an id is a spec (even with no kind,
## which then errors); a doc without an id is prose and is silently skipped —
## even when its frontmatter is malformed. Exercised over real files in a temp dir.
func test_discovery_is_by_id_key() -> void:
	var dir: String = "user://spec_registry_test"
	DirAccess.make_dir_recursive_absolute(dir)
	_write(dir + "/prose.md", "---\nbaladian: 1\n---\n# just notes\n")
	_write(dir + "/broken_prose.md", "---\ntags: [a, : bad\n# unterminated / malformed, but no id\n")
	_write(dir + "/relocated.md", "---\nid: relocated_unit\nkind: unit\n---\n# moved anywhere\n")
	_write(dir + "/no_kind.md", "---\nid: kindless\n---\n# has id, missing kind\n")

	var r: RefCounted = SpecRegistry.new().scan(dir)

	assert_true(r.specs.has("relocated_unit"), "a doc with an id is discovered wherever it lives")
	assert_false(r.specs.has("kindless") and r.specs["kindless"] != null)
	# Prose (with or without valid frontmatter) never registers or errors.
	for e in r.errors:
		assert_false(String(e).contains("prose.md"), "prose must not error: %s" % e)
	# A doc that HAS an id but no kind is a spec and errors loudly.
	assert_true(r.errors.any(func(e): return String(e).contains("no kind")),
		"id-without-kind should error")

	_rmdir(dir)


func _write(a_path: String, a_text: String) -> void:
	var f: FileAccess = FileAccess.open(a_path, FileAccess.WRITE)
	f.store_string(a_text)
	f.close()


func _rmdir(a_dir: String) -> void:
	var da: DirAccess = DirAccess.open(a_dir)
	if da == null:
		return
	for fn in da.get_files():
		da.remove(fn)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(a_dir))


func test_duplicate_id_errors() -> void:
	var r: RefCounted = _registry([
		_doc("res://a.md", {"kind": "unit", "id": "dupe", "scene": UNIT_SCENE}),
		_doc("res://b.md", {"kind": "projectile", "id": "dupe", "scene": UNIT_SCENE}),
	])
	assert_eq(r.errors.size(), 1)
	assert_string_contains(r.errors[0], "duplicate id 'dupe'")


func test_id_but_no_kind_errors() -> void:
	# Discovery finds it (it has an id), but a spec must declare its kind.
	var r: RefCounted = _registry([
		_doc("res://a.md", {"id": "kindless"}),
	])
	assert_eq(r.errors.size(), 1)
	assert_string_contains(r.errors[0], "no kind")


func test_invalid_id_format_errors() -> void:
	var r: RefCounted = _registry([
		_doc("res://a.md", {"kind": "unit", "id": "Bad Name", "scene": UNIT_SCENE}),
	])
	assert_eq(r.errors.size(), 1)
	assert_string_contains(r.errors[0], "invalid id")


func test_unknown_requires_reference_errors() -> void:
	var r: RefCounted = _registry([
		_doc("res://a.md", {"kind": "unit", "id": "u", "scene": UNIT_SCENE, "requires": ["nonexistent"]}),
	])
	assert_eq(r.errors.size(), 1)
	assert_string_contains(r.errors[0], "unknown piece 'nonexistent'")


func test_requires_must_name_structures() -> void:
	var r: RefCounted = _registry([
		_doc("res://a.md", {"kind": "unit", "id": "u1", "scene": UNIT_SCENE}),
		_doc("res://b.md", {"kind": "unit", "id": "u2", "scene": UNIT_SCENE, "requires": ["u1"]}),
	])
	assert_eq(r.errors.size(), 1)
	assert_string_contains(r.errors[0], "requires must name structures")


func test_bad_enum_name_errors() -> void:
	var r: RefCounted = _registry([
		_doc("res://a.md", {"kind": "unit", "id": "u", "scene": UNIT_SCENE, "armour": "ADAMANTIUM"}),
	])
	assert_eq(r.errors.size(), 1)
	assert_string_contains(r.errors[0], "ADAMANTIUM")


func test_weapon_projectile_reference_and_name_key() -> void:
	var r: RefCounted = _registry([
		_doc("res://a.md", {"kind": "unit", "id": "u", "scene": UNIT_SCENE, "weapons": [
			{"name": "Gun", "projectile": "nope"},
			{"projectile": "nope2"},
		]}),
	])
	assert_eq(r.errors.size(), 3)   # unknown projectile x2 + missing name


func test_missing_scene_file_errors() -> void:
	var r: RefCounted = _registry([
		_doc("res://a.md", {"kind": "unit", "id": "u", "scene": "res://nope/missing.tscn"}),
	])
	assert_eq(r.errors.size(), 1)
	assert_string_contains(r.errors[0], "does not exist")


func test_piece_without_scene_is_allowed() -> void:
	# The Mutalisk flow: a designed-but-unbuilt piece gets its skeleton scene
	# created by the importer, so no scene: is not an error.
	var r: RefCounted = _registry([
		_doc("res://a.md", {"kind": "unit", "id": "mutalisk", "hp": 120}),
	])
	assert_eq(r.errors, [])


func test_faction_needs_exactly_one_structure() -> void:
	var r: RefCounted = _registry([
		_doc("res://u.md", {"kind": "unit", "id": "u", "scene": UNIT_SCENE}),
		_doc("res://f.md", {"kind": "faction", "id": "f", "scene": "res://scenes/factions/anarchical.tscn", "starts_with": ["u", "u"]}),
	])
	assert_eq(r.errors.size(), 1)
	assert_string_contains(r.errors[0], "exactly 1 structure")


func test_faction_valid_roster_passes() -> void:
	var r: RefCounted = _registry([
		_doc("res://s.md", {"kind": "structure", "id": "s", "scene": STRUCTURE_SCENE}),
		_doc("res://u.md", {"kind": "unit", "id": "u", "scene": UNIT_SCENE}),
		_doc("res://f.md", {"kind": "faction", "id": "f", "scene": "res://scenes/factions/anarchical.tscn", "starts_with": ["s", "u", "u"], "ordnances": ["ambush"]}),
	])
	assert_eq(r.errors, [])


func test_projectile_status_effect_reference() -> void:
	var r: RefCounted = _registry([
		_doc("res://p.md", {"kind": "projectile", "id": "p", "scene": UNIT_SCENE, "status_effects": ["ghost_fx"]}),
	])
	assert_eq(r.errors.size(), 1)
	assert_string_contains(r.errors[0], "unknown status effect 'ghost_fx'")
