extends SceneTree

## Entity.Type <-> packed-scene validation (CLI).
##
## Audits how the Entity.Type enum tracks the scenes that represent it. A scene
## "declares" a type = its root Entity instance's `type` property equals that
## enum value (read by instantiating out-of-tree, same trick the exporter uses,
## so _ready / _auto_initialize never fire). Summarizes:
##
##   [1] Entity.Type values that NO scanned scene instantiates with (unused).
##   [2] Entity.Type values whose name-stem (the text after the last '_', e.g.
##       STRUCTURE_STRONGHOLD -> "STRONGHOLD") does NOT appear (case-insensitively) in
##       the filename of a scene that declares them -- i.e. the enum and the
##       scene it lives in have drifted apart.
##
## Scenes whose root type is Entity.Type.ABSTRACT are ignored (Godot inheritance
## scaffolds, not real game entities); the report prints how many were skipped.
##
## Scope: only the dirs in SCAN_DIRS are walked, so an enum whose scene lives
## elsewhere would show as unused -- the report prints the scanned dirs so that
## caveat is visible.
##
## Run:  godot --headless -s res://tools/balance_export/validation.gd

const SCAN_DIRS: Array = ["res://scenes/entities/units", "res://scenes/entities/structures"]


func _initialize() -> void:
	var scenes: Array = []
	for dir_path in SCAN_DIRS:
		_collect_scenes(dir_path, scenes)
	scenes.sort()

	# enum value (int) -> Array of scene file basenames that instantiate as it.
	var type_to_scenes: Dictionary = {}
	var entity_count: int = 0
	var abstract_count: int = 0        # ABSTRACT scaffolds, intentionally ignored
	var undefined_scenes: Array = []   # scenes whose root resolved to UNDEFINED
	for path in scenes:
		var t: Variant = _scene_type(path)
		if t == null:
			continue   # not an Entity root, or failed to load
		if t == Entity.Type.ABSTRACT:
			abstract_count += 1
			continue   # inheritance-only scaffold, not a real game entity
		entity_count += 1
		var fname: String = path.get_file().get_basename()
		if t == Entity.Type.UNDEFINED:
			undefined_scenes.append(fname)
			continue
		if not type_to_scenes.has(t):
			type_to_scenes[t] = []
		type_to_scenes[t].append(fname)

	# [1] enum values no scene claims. ABSTRACT/UNDEFINED aren't real entity types.
	var unused: Array = []
	for enum_name: String in Entity.Type:
		var value: int = Entity.Type[enum_name]
		if value == Entity.Type.UNDEFINED or value == Entity.Type.ABSTRACT:
			continue
		if not type_to_scenes.has(value):
			unused.append("%s (0x%X)" % [enum_name, value])

	# [2] enum name-stem absent from the declaring scene's filename.
	var mismatches: Array = []
	for enum_name: String in Entity.Type:
		var value: int = Entity.Type[enum_name]
		if value == Entity.Type.UNDEFINED or value == Entity.Type.ABSTRACT:
			continue
		if not type_to_scenes.has(value):
			continue
		var stem: String = _name_stem(enum_name)
		for fname: String in type_to_scenes[value]:
			if not fname.to_lower().contains(stem.to_lower()):
				mismatches.append("%s (stem \"%s\") declared by %s.tscn" % [enum_name, stem, fname])

	_print_report(scenes.size(), entity_count, abstract_count, unused, mismatches, undefined_scenes)
	quit()


# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
func _collect_scenes(dir_path: String, out: Array) -> void:
	var da: DirAccess = DirAccess.open(dir_path)
	if da == null:
		push_warning("validation: cannot open %s" % dir_path)
		return
	da.list_dir_begin()
	var fn: String = da.get_next()
	while fn != "":
		var full: String = dir_path.path_join(fn)
		if da.current_is_dir():
			if not fn.begins_with("."):
				_collect_scenes(full, out)
		elif fn.get_extension() == "tscn":
			out.append(full)
		fn = da.get_next()
	da.list_dir_end()


## The root node's `type`, read straight from scene data — never instantiated.
## Instantiating to read one property builds the whole node tree and spams
## "implicit_initializer is null" in headless; SceneState avoids both. Walks the
## inheritance chain: a scene that doesn't override `type` inherits it from the
## base scene it instances. null = the chain never sets `type` (or won't load).
func _scene_type(path: String) -> Variant:
	var packed: PackedScene = load(path)
	if packed == null:
		return null
	return _type_from_packed(packed)


func _type_from_packed(packed: PackedScene) -> Variant:
	var state: SceneState = packed.get_state()
	if state.get_node_count() == 0:
		return null
	# Root node is index 0. Use its `type` override if this scene sets one.
	for i: int in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == &"type":
			return state.get_node_property_value(0, i)
	# Not overridden here — recurse into the base scene this root inherits from.
	var base: PackedScene = state.get_node_instance(0)
	return _type_from_packed(base) if base != null else null


## Text after the last underscore: STRUCTURE_STRONGHOLD -> STRONGHOLD. No '_' -> whole.
func _name_stem(enum_name: String) -> String:
	var i: int = enum_name.rfind("_")
	return enum_name.substr(i + 1) if i >= 0 else enum_name


func _print_report(total: int, entities: int, abstracts: int, unused: Array, mismatches: Array, undefined_scenes: Array) -> void:
	print("\n=== Entity.Type <-> scene validation ===")
	print("scanned dirs: %s" % ", ".join(SCAN_DIRS))
	print("scenes found: %d (%d Entity roots, %d ABSTRACT ignored)\n" % [total, entities, abstracts])

	print("[1] UNUSED Entity.Type values (no scanned scene instantiates with this type): %d" % unused.size())
	if unused.is_empty():
		print("    (none)")
	for line in unused:
		print("    - " + line)

	print("\n[2] NAME/SCENE MISMATCHES (enum name-stem not in declaring scene's filename): %d" % mismatches.size())
	if mismatches.is_empty():
		print("    (none)")
	for line in mismatches:
		print("    - " + line)

	if not undefined_scenes.is_empty():
		print("\n(note) scenes whose root resolved to UNDEFINED (no type set): %d" % undefined_scenes.size())
		for fname in undefined_scenes:
			print("    - %s.tscn" % fname)
	print("")
