extends GutTest

## Entity scenes are COMPOSED, never inherited (composition-rework §Step 4): every piece
## declares its own components, instancing the component library for the ones with children.
##
## What this file guards is the trap inheritance left behind. Godot cannot remove an inherited
## node, so a scene that declared one its base already had ended up with BOTH — which leaks
## the node and segfaults the process during engine teardown, long after the code that caused
## it. Without bases that can no longer happen by inheritance, but the same shape survives in
## a single file: two sibling declarations of one name, which is how cl_commandCenter carried
## three placeholder models until the composition pass found them.
##
## The roster-wide guards read the .tscn TEXT: a second declaration is exactly what an
## instantiated scene cannot show you, since it resolves to one node (or a renamed one).
## Instantiating every entity scene in one test also segfaults the engine, so the
## instantiated assertions are made against a named sample.
##
## See gdd/systems/authoring/entity-scene-hierarchy.md.
##
## PATHS, not preloads (see CLAUDE.md): a file-scope preload of an entity scene fires Tool's
## static registry initialiser at PARSE time and makes Tool.for_name return null for the rest
## of the run. This file sorts near the front of the directory.

const ENTITY_ROOT: String = "res://scenes/entities"

## Pieces whose layout is worth naming outright: the one that hides the generated stand-in
## behind its own art, the two that keep the dummy as deliberate bulk beside a real model,
## and two plain infantrymen.
var _WELL_KNOWN: Dictionary = {
	"res://scenes/entities/structures/cl/cl_airField.tscn": ["sky_port"],
	"res://scenes/entities/structures/cl/cl_infrastructure.tscn": ["Model", "hexagonal_prism"],
	"res://scenes/entities/structures/an/an_commandCenter.tscn": ["Model", "cube"],
	"res://scenes/entities/units/cl/cl_bioLight_antiLight.tscn": ["irregular", "cube"],
	"res://scenes/entities/units/an/an_bioLight_builder.tscn": ["irregular"],
}


## Build Tool's registry BEFORE this file loads any scene: referencing it loads every tool
## scene in the game, and doing that from inside another scene's load re-enters the loader.
func before_all() -> void:
	Tool.for_name("")


func _entity_scenes() -> Array[String]:
	var found: Array[String] = []
	_collect(ENTITY_ROOT, found)
	found.sort()
	return found


func _collect(a_dir: String, a_into: Array[String]) -> void:
	var dir := DirAccess.open(a_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var full: String = "%s/%s" % [a_dir, entry]
		if dir.current_is_dir():
			_collect(full, a_into)
		elif entry.ends_with(".tscn"):
			a_into.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


## Instantiated OUT OF TREE and freed by the caller — this asks about node layout, which
## needs no _ready to have run.
func _instantiate(a_path: String) -> Node:
	var packed: PackedScene = load(a_path)
	return packed.instantiate() if packed != null else null


func _children_named(a_node: Node, a_name: String) -> Array[Node]:
	var out: Array[Node] = []
	for child: Node in a_node.get_children():
		if child.name == a_name:
			out.append(child)
	return out


#region No scene inherits another
func test_no_entity_scene_inherits_another() -> void:
	var scanned: int = 0
	for path: String in _entity_scenes():
		scanned += 1
		var root: String = _root_header(FileAccess.get_file_as_string(path))
		assert_false(root.contains("instance="), "%s inherits a scene: %s" % [path, root])
	assert_gt(scanned, 100, "the scan actually covered the roster")


func test_no_entity_scene_declares_two_siblings_of_one_name() -> void:
	var header: RegEx = RegEx.create_from_string(
		'^\\[node name="([^"]+)"(?:[^\\]]*? parent="([^"]*)")?'
	)
	for path: String in _entity_scenes():
		var seen: Dictionary = {}
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			var found: RegExMatch = header.search(line)
			if found == null:
				continue
			var key: String = "%s/%s" % [found.get_string(2), found.get_string(1)]
			assert_false(seen.has(key), "%s declares %s twice" % [path, key])
			seen[key] = true


func _root_header(a_text: String) -> String:
	for line: String in a_text.split("\n"):
		if line.begins_with("[node "):
			return line
	return ""


#endregion


#region The sample that is instantiated
func test_the_well_known_pieces_keep_their_models_where_they_were() -> void:
	for path: String in _WELL_KNOWN:
		var inst: Node = _instantiate(path)
		assert_not_null(inst, path)
		if inst == null:
			continue
		var visuals: Array[Node] = _children_named(inst, "MeshVisual")
		assert_eq(visuals.size(), 1, "%s has exactly one MeshVisual" % path)
		if visuals.size() == 1:
			assert_true(visuals[0] is MeshVisual, "%s: it carries mesh_visual.gd" % path)
			var names: Array = []
			for child: Node in visuals[0].get_children():
				names.append(String(child.name))
			assert_eq(names, _WELL_KNOWN[path] as Array, "%s: model children, in order" % path)
		inst.free()


## The resolved form of the guard above, for the sample.
func test_no_sampled_scene_has_two_siblings_of_one_name() -> void:
	var sample: Array[String] = [
		"res://scenes/entities/nt_aircraftLight_recon.tscn",
		"res://scenes/entities/structures/nt/nt_extractionSite.tscn",
		"res://scenes/entities/structures/nt/nt_shelter.tscn"
	]
	sample.append_array(_WELL_KNOWN.keys())
	for path: String in sample:
		var inst: Node = _instantiate(path)
		if inst == null:
			continue
		_assert_names_unique(inst, inst, path)
		inst.free()


func _assert_names_unique(a_node: Node, a_root: Node, a_path: String) -> void:
	var seen: Dictionary = {}
	for child: Node in a_node.get_children():
		var key: String = String(child.name)
		assert_false(
			seen.has(key),
			"%s: %s has two children called %s" % [a_path, a_root.get_path_to(a_node), key]
		)
		seen[key] = true
		_assert_names_unique(child, a_root, a_path)
#endregion
