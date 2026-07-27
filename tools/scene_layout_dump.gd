extends Node

## Acceptance harness for composing the piece scenes (composition-rework.md §Step 4): dumps
## every entity scene's RESOLVED node tree — what instantiating it produces, inheritance
## applied — so a batch of scenes rebuilt without inheritance can be diffed against the same
## scenes before. A difference is either intended and accounted for, or a regression.
##
## One line per node: scene, tree path, class, script, groups, and the doc-governed values a
## rebuild could lose (a shape's radius, a component's authored exports). Out of the tree, so
## no _ready runs and nothing is initialised.
##
## Run with:
##   godot --headless res://tools/scene_layout_dump.tscn -- <out_path> [scene_dir] [deep]
##
## `deep` records EVERY stored property of every node, embedded resources expanded, instead of
## the short list below — what proves a rebuilt scene equivalent rather than merely similar.

const DEFAULT_ROOT: String = "res://scenes/entities"
## Exported properties recorded per node. The shape radius and footprint are the doc values a
## rebuild is most likely to drop; the rest is identity.
const RECORDED_PROPERTIES: Array[String] = ["id", "dimensions", "speed", "hp_max", "disabled"]

## Set from the command line; see the header.
var _deep: bool = false


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else ""
	var root: String = args[1] if args.size() > 1 else DEFAULT_ROOT
	_deep = args.size() > 2 and args[2] == "deep"
	var lines: PackedStringArray = []
	for path: String in _scenes(root):
		lines.append_array(_dump(path))
	var text: String = "\n".join(lines) + "\n"
	if out_path.is_empty():
		print(text)
	else:
		FileAccess.open(out_path, FileAccess.WRITE).store_string(text)
		print("scene_layout_dump: %d nodes -> %s" % [lines.size(), out_path])
	get_tree().quit()


func _dump(a_path: String) -> PackedStringArray:
	var packed: PackedScene = load(a_path) as PackedScene
	if packed == null:
		return PackedStringArray(["%s | cannot load" % a_path])
	var instance: Node = packed.instantiate()
	var lines: PackedStringArray = []
	_dump_node(instance, instance, a_path, lines)
	instance.free()
	return lines


func _dump_node(a_root: Node, a_node: Node, a_scene: String, a_lines: PackedStringArray) -> void:
	var script: Script = a_node.get_script() as Script
	# As Strings: a StringName array sorts by identity, not by text, so it is not stable.
	var groups: Array[String] = []
	for group: StringName in a_node.get_groups():
		if not str(group).begins_with("_"):
			groups.append(str(group))
	groups.sort()
	a_lines.append("%s | %s | %s | %s | %s | %s" % [a_scene, a_root.get_path_to(a_node),
		a_node.get_class(), script.resource_path if script != null else "",
		",".join(groups),
		_deep_recorded(a_node) if _deep else _recorded(a_node)])
	for child: Node in a_node.get_children():
		_dump_node(a_root, child, a_scene, a_lines)


static func _recorded(a_node: Node) -> String:
	var parts: PackedStringArray = []
	for property: String in RECORDED_PROPERTIES:
		if property in a_node:
			parts.append("%s=%s" % [property, a_node.get(property)])
	var shape_node: CollisionShape3D = a_node as CollisionShape3D
	if shape_node != null and shape_node.shape != null:
		parts.append("shape=%s" % shape_node.shape.get_class())
		if "radius" in shape_node.shape:
			parts.append("radius=%s" % shape_node.shape.get("radius"))
	return " ".join(parts)


## Every stored property with its value, sorted by name. Embedded resources are expanded, so two
## scenes whose sub-resources differ only in id compare equal and a changed radius does not.
static func _deep_recorded(a_object: Object) -> String:
	var parts: PackedStringArray = []
	for property: Dictionary in a_object.get_property_list():
		if (property["usage"] & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var name: String = property["name"]
		if name == "script" or name.begins_with("resource_") or name == "unique_name_in_owner":
			continue
		parts.append("%s=%s" % [name, _value_text(a_object.get(name))])
	parts.sort()
	return " ".join(parts)


static func _value_text(a_value: Variant) -> String:
	if not (a_value is Resource):
		return var_to_str(a_value).replace("\n", " ")
	var resource: Resource = a_value
	if not resource.resource_path.is_empty() and not resource.resource_path.contains("::"):
		return "<%s>" % resource.resource_path
	return "%s{%s}" % [resource.get_class(), _deep_recorded(resource)]


static func _scenes(root: String) -> Array[String]:
	var found: Array[String] = []
	var dir: DirAccess = DirAccess.open(root)
	for sub: String in dir.get_directories():
		found.append_array(_scenes(root.path_join(sub)))
	for file: String in dir.get_files():
		if file.ends_with(".tscn"):
			found.append(root.path_join(file))
	found.sort()
	return found
