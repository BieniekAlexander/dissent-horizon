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
## `1.2`, `&"an_bioMedium_dominionGen"`, `SubResource("X")`); fmt_* helpers build them. Callers
## that need SEMANTIC values (e.g. "what is hp_max currently?") should
## instantiate the scene read-only instead — resolving inherited defaults is the
## engine's job, not this parser's.

## Section: {
## "tag": String              — gd_scene / ext_resource / sub_resource / node / connection /
## editable
##   "attrs": Dictionary        — parsed header attributes (String -> raw String, quotes stripped)
##   "lines": Array[String]     — verbatim lines, header first, incl. trailing blank lines
## }
var sections: Array = []

const _HEADER_TAGS: Array = [
	"gd_scene",
	"gd_resource",
	"ext_resource",
	"sub_resource",
	"node",
	"connection",
	"editable",
	"resource"
]


# --------------------------------------------------------------------------- #
# Load / save
# --------------------------------------------------------------------------- #
## (Untyped returns: the class can't name its own class_name in annotations
## when the global class cache hasn't rescanned it yet — consumers preload.)
static func from_text(text: String) -> RefCounted:
	var doc: RefCounted = new()
	doc._parse(text)
	return doc


static func load_file(path: String) -> RefCounted:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
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
static func _header_tag(line: String) -> String:
	if not line.begins_with("["):
		return ""
	for tag in _HEADER_TAGS:
		if (
			line.begins_with("[" + tag)
			and (
				line.length() == tag.length() + 2
				or line[tag.length() + 1] == " "
				or line[tag.length() + 1] == "]"
			)
		):
			if line.rstrip(" ").ends_with("]"):
				return tag
	return ""


## Header attributes: [tag key=value key2="quoted" ...] -> {key: value}. Values
## keep their raw form minus surrounding quotes (ExtResource("x") stays intact).
static func _parse_attrs(header: String) -> Dictionary:
	var attrs: Dictionary = {}
	var inner: String = header.strip_edges().trim_prefix("[").trim_suffix("]")
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
		if value.begins_with('"') and value.ends_with('"') and value.length() >= 2:
			value = value.substr(1, value.length() - 2)
		attrs[key] = value
	return attrs


## Splits header innards on spaces outside quotes/parens/brackets.
static func _split_attrs(text: String) -> Array:
	var parts: Array = []
	var depth: int = 0
	var in_quote: bool = false
	var current: String = ""
	for i in text.length():
		var c: String = text[i]
		if in_quote:
			current += c
			if c == '"':
				in_quote = false
			continue
		match c:
			'"':
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
		if (
			section["attrs"].get("name", "") == node_name
			and section["attrs"].get("parent", "") == parent_attr
		):
			return section
	return {}


## The tree path of a node section ("" for root, else "Loadout/Weapon").
static func node_path_of(section: Dictionary) -> String:
	var parent: String = section["attrs"].get("parent", "")
	var node_name: String = section["attrs"].get("name", "")
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
	var span: Vector2i = _prop_span(a_section, a_key)
	if span.x < 0:
		return ""
	var value_lines: Array = [
		(
			String(a_section["lines"][span.x])
			. substr(String(a_section["lines"][span.x]).find("=") + 1)
			. strip_edges()
		)
	]
	for i in range(span.x + 1, span.y):
		value_lines.append(a_section["lines"][i])
	return "\n".join(value_lines)


func has_prop(a_section: Dictionary, a_key: String) -> bool:
	return _prop_span(a_section, a_key).x >= 0


## Sets `key = raw_value`, replacing the existing value — every line of it, since Godot writes
## some values (an Array of Dictionaries, a string with newlines) across several — or appending
## a new one before the section's trailing blank separator.
func set_prop(a_section: Dictionary, a_key: String, a_raw_value: String) -> void:
	var new_line: String = "%s = %s" % [a_key, a_raw_value]
	var span: Vector2i = _prop_span(a_section, a_key)
	if span.x < 0:
		a_section["lines"].insert(_append_index(a_section), new_line)
		return
	for i in range(span.y - 1, span.x, -1):
		a_section["lines"].remove_at(i)
	a_section["lines"][span.x] = new_line


func remove_prop(a_section: Dictionary, a_key: String) -> void:
	var span: Vector2i = _prop_span(a_section, a_key)
	for i in range(span.y - 1, span.x - 1, -1):
		a_section["lines"].remove_at(i)


## The lines `a_key`'s value occupies, as [first, end); (-1, -1) when the section has no such
## property. A value ends on the line where its brackets and quotes balance, so a key-like line
## inside a multi-line value is never mistaken for a property of its own.
func _prop_span(a_section: Dictionary, a_key: String) -> Vector2i:
	var lines: Array = a_section["lines"]
	var i: int = 1
	while i < lines.size():
		var key: String = _prop_key(lines[i])
		if key == "":
			i += 1
			continue
		var end: int = _value_end(lines, i)
		if key == a_key:
			return Vector2i(i, end)
		i = end
	return Vector2i(-1, -1)


## The index just past the last line of the value starting on `a_start`.
static func _value_end(a_lines: Array, a_start: int) -> int:
	var depth: int = 0
	var in_string: bool = false
	var escaped: bool = false
	var i: int = a_start
	var text: String = String(a_lines[i]).substr(String(a_lines[i]).find(" = ") + 3)
	while true:
		for c: String in text:
			if in_string:
				if escaped:
					escaped = false
				elif c == "\\":
					escaped = true
				elif c == '"':
					in_string = false
			elif c == '"':
				in_string = true
			elif c in "([{":
				depth += 1
			elif c in ")]}":
				depth -= 1
		i += 1
		if (depth <= 0 and not in_string) or i >= a_lines.size():
			return i
		text = "\n" + String(a_lines[i])
	return i


## Index at which to insert a new property line: after the last non-blank line.
func _append_index(a_section: Dictionary) -> int:
	var i: int = a_section["lines"].size()
	while i > 1 and String(a_section["lines"][i - 1]).strip_edges() == "":
		i -= 1
	return i


## The property key when the line is `key = ...` at top level, else "".
static func _prop_key(line: String) -> String:
	var eq: int = line.find(" = ")
	if eq <= 0 or line.begins_with(" ") or line.begins_with("\t"):
		return ""
	var key: String = line.substr(0, eq)
	for i in key.length():
		var c: String = key[i]
		if not (
			c.to_lower() != c.to_upper() or c.is_valid_int() or c == "_" or c == "/" or c == "."
		):
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
		header = '[ext_resource type="%s" uid="%s" path="%s" id="%s"]' % [a_type, a_uid, a_path, id]
	else:
		header = '[ext_resource type="%s" path="%s" id="%s"]' % [a_type, a_path, id]
	var section: Dictionary = {
		"tag": "ext_resource", "attrs": _parse_attrs(header), "lines": [header]
	}
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


## Removes the [sub_resource] with this id, if present. Callers must have
## repointed every reference to it first — nothing here checks.
func remove_sub_resource(a_id: String) -> void:
	for section in sections_of("sub_resource"):
		if section["attrs"].get("id", "") == a_id:
			sections.erase(section)
			_update_load_steps()
			return


## Adds a [sub_resource] with the given raw properties; returns its id.
func add_sub_resource(a_type: String, a_id_hint: String, a_props: Dictionary) -> String:
	var id: String = _fresh_sub_id("%s_%s" % [a_type, a_id_hint])
	var header: String = '[sub_resource type="%s" id="%s"]' % [a_type, id]
	var section: Dictionary = {
		"tag": "sub_resource", "attrs": _parse_attrs(header), "lines": [header]
	}
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


## Sets (or, with an empty `a_raw_value`, removes) one attribute in a section's HEADER line —
## `groups=[...]` on a node, say — leaving every other attribute where it was. A new attribute
## goes before `instance=`, where Godot writes `groups`, else at the end.
func set_header_attr(a_section: Dictionary, a_key: String, a_raw_value: String) -> void:
	var header: String = str(a_section["lines"][0])
	var inner: String = header.strip_edges().trim_prefix("[").trim_suffix("]")
	var space: int = inner.find(" ")
	var tag: String = inner if space == -1 else inner.substr(0, space)
	var pairs: Array = [] if space == -1 else _split_attrs(inner.substr(space + 1))
	var replaced: bool = false
	var out: Array = []
	for pair: String in pairs:
		if pair.begins_with(a_key + "="):
			replaced = true
			if a_raw_value != "":
				out.append("%s=%s" % [a_key, a_raw_value])
		else:
			out.append(pair)
	if not replaced and a_raw_value != "":
		var at: int = out.size()
		for j: int in out.size():
			if str(out[j]).begins_with("instance="):
				at = j
				break
		out.insert(at, "%s=%s" % [a_key, a_raw_value])
	var rebuilt: String = "[%s]" % " ".join([tag] + out)
	a_section["lines"][0] = rebuilt
	a_section["attrs"] = _parse_attrs(rebuilt)


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
## [connection]/[editable] sections — or, given `a_after`, straight after that node and its
## descendants, which is also where it lands in the tree. A missing `a_after` is ignored.
func add_node(a_attr_pairs: Array, a_props: Dictionary, a_after: String = "") -> Dictionary:
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
	if a_after != "":
		for i in sections.size():
			var s: Dictionary = sections[i]
			if s["tag"] != "node":
				continue
			var p: String = node_path_of(s)
			if p == a_after or _is_descendant(p, a_after):
				insert_at = i + 1
	sections.insert(insert_at, section)
	return section


## Marks the instanced scene at `a_path` editable, so overrides of the nodes INSIDE it survive
## an editor re-save. Godot's saver drops such overrides from an instance not marked editable.
func ensure_editable(a_path: String) -> void:
	for section in sections_of("editable"):
		if section["attrs"].get("path", "") == a_path:
			return
	var header: String = '[editable path="%s"]' % a_path
	var lines: Array = [header]
	# Godot writes editable lines consecutively, with the file's closing newline after the last.
	if (
		not sections.is_empty()
		and sections.back()["tag"] == "editable"
		and String(sections.back()["lines"].back()) == ""
	):
		sections.back()["lines"].pop_back()
	lines.append("")
	sections.append({"tag": "editable", "attrs": _parse_attrs(header), "lines": lines})


## Removes a node section and every section for its descendants, then every resource entry
## the removal orphaned. A no-op for paths with no section.
##
## REMOVAL IS TOTAL, and that is a contract rather than a courtesy: the spec importer is
## moving to a model where deleting a doc key deletes a node on every run, so
## add -> remove -> add has to reproduce the earlier bytes exactly. Residue — an unread
## script entry, a shape nothing points at, a stale `load_steps` — makes the second add
## differ from the first, and the difference compounds silently over runs.
func remove_node(a_path: String) -> void:
	var doomed: Array = []
	for section in sections_of("node"):
		var p: String = node_path_of(section)
		if p == a_path or _is_descendant(p, a_path):
			doomed.append(section)
	for section in doomed:
		sections.erase(section)
	_prune_orphaned_resources()


## Drop every [ext_resource] and [sub_resource] nothing in the document references any more.
##
## Run after a node removal because that is the only thing that orphans one. Two distinct
## costs, which is why both kinds are pruned:
##
## * an orphaned ext_resource is LOADED anyway — Godot does not skip unreferenced entries —
##   so one left pointing at a script that is later deleted makes the scene emit three
##   errors on every load, forever. Eight scenes reached exactly that state via a retired
##   `SanctionCaster` component, and nothing in the pipeline cleaned them up because
##   ensure_ext_resource only ever ADDS.
## * an orphaned sub_resource is merely unread, and used to be left alone for that reason —
##   but it is still bytes and still a `load_steps` count, so leaving one breaks the
##   add -> remove -> add identity that remove_node now owes its callers. Every
##   doc-governed shape is a sub_resource, so this is the common case, not the rare one.
##
## Reachability is transitive: a sub_resource may reference other resources (a mesh naming
## its material), so the live set is grown to a fixpoint before anything is dropped.
func _prune_orphaned_resources() -> void:
	var live: Dictionary = {}  # resource id -> true, ext and sub alike
	var pending: Array = []  # sub_resource ids already scanned for further refs
	for section in sections:
		if section["tag"] == "ext_resource" or section["tag"] == "sub_resource":
			continue
		_collect_resource_refs(section, live)
	# Grow through live sub_resources until no new id appears.
	var changed: bool = true
	while changed:
		changed = false
		for section in sections_of("sub_resource"):
			var id: String = section["attrs"].get("id", "")
			if not live.has(id) or pending.has(id):
				continue
			pending.append(id)
			var before: int = live.size()
			_collect_resource_refs(section, live)
			changed = changed or live.size() != before

	var orphans: Array = []
	for tag: String in ["ext_resource", "sub_resource"]:
		for section in sections_of(tag):
			if not live.has(section["attrs"].get("id", "")):
				orphans.append(section)
	if orphans.is_empty():
		return
	for section in orphans:
		sections.erase(section)
	_normalize_ext_block()
	_update_load_steps()


## Adds every ExtResource("x") / SubResource("x") id named in the section to `a_into`.
static func _collect_resource_refs(section: Dictionary, into: Dictionary) -> void:
	for line in section["lines"]:
		for hit in _EXT_REF.search_all(line):
			into[hit.get_string(1)] = true
		for hit in _SUB_REF.search_all(line):
			into[hit.get_string(1)] = true


## Godot writes the [ext_resource] entries packed together with a single blank line after
## the last. ensure_ext_resource maintains that when it inserts; this restores it when a
## removal takes the entry that was carrying the block's blank line, which is what makes
## "add an ext_resource, then remove it" give the bytes back rather than closing the gap
## between the block and whatever follows it.
func _normalize_ext_block() -> void:
	var ext: Array = sections_of("ext_resource")
	if ext.is_empty():
		return
	for i in ext.size():
		if i == ext.size() - 1:
			_ensure_trailing_blank(ext[i])
		else:
			_strip_trailing_blank(ext[i])


## Matches an `ExtResource("id")` / `SubResource("id")` reference, capturing the id.
static var _EXT_REF: RegEx = RegEx.create_from_string('ExtResource\\("([^"]+)"\\)')
static var _SUB_REF: RegEx = RegEx.create_from_string('SubResource\\("([^"]+)"\\)')


static func _is_descendant(path: String, ancestor: String) -> bool:
	if ancestor == "":
		return path != ""
	return path.begins_with(ancestor + "/")


# --------------------------------------------------------------------------- #
# Value formatting (GDScript-literal raw strings for set_prop / add_node)
# --------------------------------------------------------------------------- #
static func fmt_float(value: float) -> String:
	# Godot serializes floats with a decimal point (1.0, 1.2) and up to full
	# precision; %g-style trimming plus a forced ".0" matches common output.
	if value == floor(value) and absf(value) < 1e15:
		return "%.1f" % value
	var s: String = ("%.6f" % value).rstrip("0")
	return s + "0" if s.ends_with(".") else s


static func fmt_string(value: String) -> String:
	# Godot reads \n / \t escapes inside a quoted .tscn string, so an authored
	# multi-line value (e.g. an editor_description) round-trips on one line.
	return (
		'"%s"'
		% value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")
	)


static func fmt_string_name(value: String) -> String:
	return "&" + fmt_string(value)


static func fmt_string_name_array(values: Array) -> String:
	var parts: Array = []
	for v in values:
		parts.append(fmt_string_name(String(v)))
	return "Array[StringName]([%s])" % ", ".join(parts)


static func fmt_vector3(value: Vector3) -> String:
	return "Vector3(%s, %s, %s)" % [fmt_float(value.x), fmt_float(value.y), fmt_float(value.z)]


## A Transform3D literal: the basis in COLUMN-MAJOR order (x axis, y axis, z axis), then
## the origin — the order Godot itself serializes, and the order its constructor reads.
static func fmt_transform(value: Transform3D) -> String:
	var b: Basis = value.basis
	var parts: Array = []
	for axis: Vector3 in [b.x, b.y, b.z, value.origin]:
		parts.append_array([fmt_float(axis.x), fmt_float(axis.y), fmt_float(axis.z)])
	return "Transform3D(%s)" % ", ".join(parts)


## A property value of whatever type a shape/mesh descriptor carries. Descriptors come
## from visual_defaults.gd, which is pure and therefore knows nothing of .tscn syntax —
## this is the boundary where its typed values become literals.
static func fmt_value(value: Variant) -> String:
	if value is Vector3:
		return fmt_vector3(value)
	if value is Transform3D:
		return fmt_transform(value)
	if value is float or value is int:
		return fmt_float(float(value))
	return str(value)


static func _fmt_attr(value: Variant) -> String:
	if value is String or value is StringName:
		# Calls like ExtResource("x") and arrays like groups=[...] pass through
		# raw; everything else (including numeric strings — Godot writes
		# index="8" quoted) is quoted.
		var s: String = String(value)
		if s.begins_with("ExtResource(") or s.begins_with("SubResource(") or s.begins_with("["):
			return s
		return '"%s"' % s
	if value is int or value is float or value is bool:
		return str(value)
	return str(value)


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
		header = regex.sub(header, "load_steps=%d " % steps).replace("load_steps=1 ", "").replace(
			"  ", " "
		)
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
