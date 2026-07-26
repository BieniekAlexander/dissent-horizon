class_name TscnDoc
extends RefCounted

## Text-level editor for Godot .tscn files.
##
## Why text-level: PackedScene.pack() outside the editor flattens scene
## inheritance, and re-saving via ResourceSaver churns uids/formatting. Editing
## the text directly keeps untouched lines byte-identical (round-tripping an
## unmodified file reproduces it exactly), preserves inheritance overrides, and
## makes importer runs idempotent.
##
## The file is modeled as an ordered list of sections. Each section is a header
## line ("[node name=... parent=...]") plus its verbatim body lines (properties,
## trailing blank separators). Mutations replace or insert individual lines;
## everything else is left exactly as read.
##
## Property values are handled as RAW STRINGS in .tscn literal syntax (e.g.
## `1.2`, `&"warlord"`, `SubResource("X")`); fmt_* helpers build them. Callers
## that need SEMANTIC values (e.g. "what is hp_max currently?") should
## instantiate the scene read-only instead — resolving inherited defaults is the
## engine's job, not this parser's.

## Section: {
##   "tag": String              — gd_scene / ext_resource / sub_resource / node / connection / editable
##   "attrs": Dictionary        — parsed header attributes (String -> raw String, quotes stripped)
##   "lines": Array[String]     — verbatim lines, header first, incl. trailing blank lines
## }
var sections: Array = []

const _HEADER_TAGS: Array = ["gd_scene", "gd_resource", "ext_resource", "sub_resource", "node", "connection", "editable", "resource"]


# --------------------------------------------------------------------------- #
# Load / save
# --------------------------------------------------------------------------- #
## (Untyped returns: the class can't name its own class_name in annotations
## when the global class cache hasn't rescanned it yet — consumers preload.)
static func from_text(a_text: String) -> RefCounted:
	var doc: RefCounted = new()
	doc._parse(a_text)
	return doc


static func load_file(a_path: String) -> RefCounted:
	var f: FileAccess = FileAccess.open(a_path, FileAccess.READ)
	if f == null:
		return null
	var text: String = f.get_as_text()
	f.close()
	return from_text(text)


func to_text() -> String:
	var out: Array = []
	for section in sections:
		for line in section["lines"]:
			out.append(line)
	return "\n".join(out)


func save_file(a_path: String) -> bool:
	var f: FileAccess = FileAccess.open(a_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(to_text())
	f.close()
	return true


func _parse(a_text: String) -> void:
	sections = []
	var current: Dictionary = {}
	for line in a_text.split("\n"):
		var tag: String = _header_tag(line)
		if tag != "":
			if not current.is_empty():
				sections.append(current)
			current = {"tag": tag, "attrs": _parse_attrs(line), "lines": [line]}
		elif current.is_empty():
			# Preamble before any header (shouldn't happen in valid files).
			current = {"tag": "", "attrs": {}, "lines": [line]}
		else:
			current["lines"].append(line)
	if not current.is_empty():
		sections.append(current)


## The section tag when the line is a section header, else "".
static func _header_tag(a_line: String) -> String:
	if not a_line.begins_with("["):
		return ""
	for tag in _HEADER_TAGS:
		if a_line.begins_with("[" + tag) and (a_line.length() == tag.length() + 2 or a_line[tag.length() + 1] == " " or a_line[tag.length() + 1] == "]"):
			if a_line.rstrip(" ").ends_with("]"):
				return tag
	return ""


## Header attributes: [tag key=value key2="quoted" ...] -> {key: value}. Values
## keep their raw form minus surrounding quotes (ExtResource("x") stays intact).
static func _parse_attrs(a_header: String) -> Dictionary:
	var attrs: Dictionary = {}
	var inner: String = a_header.strip_edges().trim_prefix("[").trim_suffix("]")
	var i: int = inner.find(" ")
	if i == -1:
		return attrs
	inner = inner.substr(i + 1)
	for pair in _split_attrs(inner):
		var eq: int = pair.find("=")
		if eq == -1:
			continue
		var key: String = pair.substr(0, eq)
		var value: String = pair.substr(eq + 1)
		if value.begins_with("\"") and value.ends_with("\"") and value.length() >= 2:
			value = value.substr(1, value.length() - 2)
		attrs[key] = value
	return attrs


## Splits header innards on spaces outside quotes/parens/brackets.
static func _split_attrs(a_text: String) -> Array:
	var parts: Array = []
	var depth: int = 0
	var in_quote: bool = false
	var current: String = ""
	for i in a_text.length():
		var c: String = a_text[i]
		if in_quote:
			current += c
			if c == "\"":
				in_quote = false
			continue
		match c:
			"\"":
				in_quote = true
				current += c
			"(", "[":
				depth += 1
				current += c
			")", "]":
				depth -= 1
				current += c
			" ":
				if depth == 0:
					if current != "":
						parts.append(current)
					current = ""
				else:
					current += c
			_:
				current += c
	if current != "":
		parts.append(current)
	return parts


# --------------------------------------------------------------------------- #
# Section lookup
# --------------------------------------------------------------------------- #
func sections_of(a_tag: String) -> Array:
	var out: Array = []
	for section in sections:
		if section["tag"] == a_tag:
			out.append(section)
	return out


## The scene's root node section (the [node] with no parent attribute).
func root_node() -> Dictionary:
	for section in sections_of("node"):
		if not section["attrs"].has("parent"):
			return section
	return {}


## Finds a node section by its scene-tree path relative to the root, e.g. ""
## (root), "Movement", "Loadout/Weapon". Returns {} when the file has no section
## for it (an inherited node with no overrides has none).
func find_node(a_path: String) -> Dictionary:
	if a_path == "" or a_path == ".":
		return root_node()
	var parts: PackedStringArray = a_path.split("/")
	var node_name: String = parts[-1]
	parts.remove_at(parts.size() - 1)
	var parent_attr: String = "." if parts.is_empty() else "/".join(parts)
	for section in sections_of("node"):
		if section["attrs"].get("name", "") == node_name and section["attrs"].get("parent", "") == parent_attr:
			return section
	return {}


## The tree path of a node section ("" for root, else "Loadout/Weapon").
static func node_path_of(a_section: Dictionary) -> String:
	var parent: String = a_section["attrs"].get("parent", "")
	var node_name: String = a_section["attrs"].get("name", "")
	if parent == "":
		return ""
	if parent == ".":
		return node_name
	return parent + "/" + node_name


# --------------------------------------------------------------------------- #
# Properties (raw .tscn literal strings)
# --------------------------------------------------------------------------- #
## The raw value of `key = value` in the section, or "" when absent. Multi-line
## values (strings with embedded newlines) are returned joined with "\n".
func get_prop(a_section: Dictionary, a_key: String) -> String:
	var collecting: bool = false
	var value_lines: Array = []
	for i in range(1, a_section["lines"].size()):
		var line: String = a_section["lines"][i]
		if collecting:
			if _prop_key(line) != "" or line.strip_edges() == "":
				break
			value_lines.append(line)
			continue
		if _prop_key(line) == a_key:
			value_lines.append(line.substr(line.find("=") + 1).strip_edges())
			collecting = true
	return "\n".join(value_lines)


func has_prop(a_section: Dictionary, a_key: String) -> bool:
	for i in range(1, a_section["lines"].size()):
		if _prop_key(a_section["lines"][i]) == a_key:
			return true
	return false


## Sets `key = raw_value`, replacing the existing line or appending a new one
## before the section's trailing blank separator.
func set_prop(a_section: Dictionary, a_key: String, a_raw_value: String) -> void:
	var new_line: String = "%s = %s" % [a_key, a_raw_value]
	for i in range(1, a_section["lines"].size()):
		if _prop_key(a_section["lines"][i]) == a_key:
			a_section["lines"][i] = new_line
			return
	a_section["lines"].insert(_append_index(a_section), new_line)


func remove_prop(a_section: Dictionary, a_key: String) -> void:
	for i in range(1, a_section["lines"].size()):
		if _prop_key(a_section["lines"][i]) == a_key:
			a_section["lines"].remove_at(i)
			return


## Index at which to insert a new property line: after the last non-blank line.
func _append_index(a_section: Dictionary) -> int:
	var i: int = a_section["lines"].size()
	while i > 1 and String(a_section["lines"][i - 1]).strip_edges() == "":
		i -= 1
	return i


## The property key when the line is `key = ...` at top level, else "".
static func _prop_key(a_line: String) -> String:
	var eq: int = a_line.find(" = ")
	if eq <= 0 or a_line.begins_with(" ") or a_line.begins_with("\t"):
		return ""
	var key: String = a_line.substr(0, eq)
	for i in key.length():
		var c: String = key[i]
		if not (c.to_lower() != c.to_upper() or c.is_valid_int() or c == "_" or c == "/" or c == "."):
			return ""
	return key


# --------------------------------------------------------------------------- #
# Resources
# --------------------------------------------------------------------------- #
## Returns the id of the ext_resource with this path, adding the entry (after
## the last existing ext_resource, or right after the gd_scene header) if
## missing. `a_uid` may be "" when unknown — Godot resolves by path and fills
## uids in on the next editor save.
func ensure_ext_resource(a_type: String, a_path: String, a_uid: String = "") -> String:
	for section in sections_of("ext_resource"):
		if section["attrs"].get("path", "") == a_path:
			return section["attrs"].get("id", "")
	var id: String = _fresh_ext_id()
	var header: String
	if a_uid != "":
		header = "[ext_resource type=\"%s\" uid=\"%s\" path=\"%s\" id=\"%s\"]" % [a_type, a_uid, a_path, id]
	else:
		header = "[ext_resource type=\"%s\" path=\"%s\" id=\"%s\"]" % [a_type, a_path, id]
	var section: Dictionary = {"tag": "ext_resource", "attrs": _parse_attrs(header), "lines": [header]}
	var ext: Array = sections_of("ext_resource")
	if ext.is_empty():
		# After the gd_scene header section; keep its trailing blank line, then a
		# blank line after the new block is provided by the next section's shape.
		section["lines"].append("")
		sections.insert(1, section)
	else:
		sections.insert(sections.find(ext[-1]) + 1, section)
		_ensure_trailing_blank(section)
		_strip_trailing_blank(ext[-1])
	_update_load_steps()
	return id


## Adds a [sub_resource] with the given raw properties; returns its id.
func add_sub_resource(a_type: String, a_id_hint: String, a_props: Dictionary) -> String:
	var id: String = _fresh_sub_id("%s_%s" % [a_type, a_id_hint])
	var header: String = "[sub_resource type=\"%s\" id=\"%s\"]" % [a_type, id]
	var section: Dictionary = {"tag": "sub_resource", "attrs": _parse_attrs(header), "lines": [header]}
	for key in a_props:
		section["lines"].append("%s = %s" % [key, a_props[key]])
	section["lines"].append("")
	var subs: Array = sections_of("sub_resource")
	if not subs.is_empty():
		sections.insert(sections.find(subs[-1]) + 1, section)
	else:
		# Before the first node section.
		var nodes: Array = sections_of("node")
		var at: int = sections.find(nodes[0]) if not nodes.is_empty() else sections.size()
		sections.insert(at, section)
	_update_load_steps()
	return id


# --------------------------------------------------------------------------- #
# Nodes
# --------------------------------------------------------------------------- #
## Adds a [node] section. `a_attr_pairs` is an ordered list of [key, value]
## pairs (order matters for readable headers: name, type, parent, index, ...);
## values are emitted quoted except booleans/numbers/calls. `a_props` maps
## property names to raw value strings, emitted in the given order.
##
## Placement: after every existing node section belonging to the parent's
## subtree (so children stay grouped in tree order), and always before
## [connection]/[editable] sections.
func add_node(a_attr_pairs: Array, a_props: Dictionary) -> Dictionary:
	var header: String = "[node"
	for pair in a_attr_pairs:
		header += " %s=%s" % [pair[0], _fmt_attr(pair[1])]
	header += "]"
	var section: Dictionary = {"tag": "node", "attrs": _parse_attrs(header), "lines": [header]}
	for key in a_props:
		section["lines"].append("%s = %s" % [key, a_props[key]])
	section["lines"].append("")

	# Parent path: "Loadout/Weapon" -> "Loadout"; "Movement" -> "" (root).
	var path: String = node_path_of(section)
	var parent_path: String = path.substr(0, path.rfind("/")) if path.contains("/") else ""

	var insert_at: int = -1
	for i in sections.size():
		var s: Dictionary = sections[i]
		if s["tag"] == "node":
			var p: String = node_path_of(s)
			if p == parent_path or _is_descendant(p, parent_path):
				insert_at = i + 1
		elif s["tag"] == "connection" or s["tag"] == "editable":
			if insert_at == -1:
				insert_at = i
			break
	if insert_at == -1:
		insert_at = sections.size()
	sections.insert(insert_at, section)
	return section


## Removes a node section and every section for its descendants. A no-op for
## paths with no section. Does not remove now-unreferenced ext/sub resources.
func remove_node(a_path: String) -> void:
	var doomed: Array = []
	for section in sections_of("node"):
		var p: String = node_path_of(section)
		if p == a_path or _is_descendant(p, a_path):
			doomed.append(section)
	for section in doomed:
		sections.erase(section)


static func _is_descendant(a_path: String, a_ancestor: String) -> bool:
	if a_ancestor == "":
		return a_path != ""
	return a_path.begins_with(a_ancestor + "/")


# --------------------------------------------------------------------------- #
# Value formatting (GDScript-literal raw strings for set_prop / add_node)
# --------------------------------------------------------------------------- #
static func fmt_float(a_value: float) -> String:
	# Godot serializes floats with a decimal point (1.0, 1.2) and up to full
	# precision; %g-style trimming plus a forced ".0" matches common output.
	if a_value == floor(a_value) and absf(a_value) < 1e15:
		return "%.1f" % a_value
	var s: String = ("%.6f" % a_value).rstrip("0")
	return s + "0" if s.ends_with(".") else s


static func fmt_string(a_value: String) -> String:
	# Godot reads \n / \t escapes inside a quoted .tscn string, so an authored
	# multi-line value (e.g. an editor_description) round-trips on one line.
	return "\"%s\"" % a_value.replace("\\", "\\\\").replace("\"", "\\\"") \
		.replace("\n", "\\n").replace("\t", "\\t")


static func fmt_string_name(a_value: String) -> String:
	return "&" + fmt_string(a_value)


static func fmt_string_name_array(a_values: Array) -> String:
	var parts: Array = []
	for v in a_values:
		parts.append(fmt_string_name(String(v)))
	return "Array[StringName]([%s])" % ", ".join(parts)


static func _fmt_attr(a_value: Variant) -> String:
	if a_value is String or a_value is StringName:
		# Calls like ExtResource("x") and arrays like groups=[...] pass through
		# raw; everything else (including numeric strings — Godot writes
		# index="8" quoted) is quoted.
		var s: String = String(a_value)
		if s.begins_with("ExtResource(") or s.begins_with("SubResource(") or s.begins_with("["):
			return s
		return "\"%s\"" % s
	if a_value is int or a_value is float or a_value is bool:
		return str(a_value)
	return str(a_value)


# --------------------------------------------------------------------------- #
# Internals
# --------------------------------------------------------------------------- #
func _fresh_ext_id() -> String:
	var used: Dictionary = {}
	for section in sections_of("ext_resource"):
		used[section["attrs"].get("id", "")] = true
	var n: int = 1
	while used.has("%d_spec" % n):
		n += 1
	return "%d_spec" % n


func _fresh_sub_id(a_base: String) -> String:
	var used: Dictionary = {}
	for section in sections_of("sub_resource"):
		used[section["attrs"].get("id", "")] = true
	if not used.has(a_base):
		return a_base
	var n: int = 2
	while used.has("%s%d" % [a_base, n]):
		n += 1
	return "%s%d" % [a_base, n]


## load_steps = ext_resources + sub_resources + 1 (the scene itself). Godot
## omits the attribute when there are no ext/sub resources.
func _update_load_steps() -> void:
	if sections.is_empty():
		return
	var head: Dictionary = sections[0]
	if head["tag"] != "gd_scene" and head["tag"] != "gd_resource":
		return
	var steps: int = sections_of("ext_resource").size() + sections_of("sub_resource").size() + 1
	var header: String = head["lines"][0]
	var regex: RegEx = RegEx.new()
	regex.compile("load_steps=\\d+")
	if regex.search(header) != null:
		header = regex.sub(header, "load_steps=%d" % steps)
	elif steps > 1:
		header = header.replace("[%s " % head["tag"], "[%s load_steps=%d " % [head["tag"], steps])
	head["lines"][0] = header
	head["attrs"] = _parse_attrs(header)


func _ensure_trailing_blank(a_section: Dictionary) -> void:
	if String(a_section["lines"][-1]).strip_edges() != "":
		a_section["lines"].append("")


func _strip_trailing_blank(a_section: Dictionary) -> void:
	while a_section["lines"].size() > 1 and String(a_section["lines"][-1]).strip_edges() == "":
		a_section["lines"].remove_at(a_section["lines"].size() - 1)
