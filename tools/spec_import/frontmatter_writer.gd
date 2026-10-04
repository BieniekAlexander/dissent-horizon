extends RefCounted

## Writes VALUES into a spec doc's frontmatter, touching only the lines that hold them — the
## write half of SpecFrontmatter, used by the debug tuning editor's Save
## (gdd/systems/ux/ui/debug-tuning.md §Saving).
##
## A path names a value the way the parsed Dictionary does: String keys into mappings, int
## indices into sequences — `["weapons", 0, "reach", "ground"]`. The writer understands the
## same YAML subset the parser reads, and keeps a doc's comments, its flow maps and the rest of
## its bytes:
##
##   * an INLINE value (a scalar, or a `{…}` / `[…]` flow collection, however nested) is
##     rewritten in place on its line, keeping the line's trailing comment;
##   * a key the doc does not have is appended to its mapping, and the canonical-order pass
##     (SpecSchema.reorder_frontmatter) then moves it where it belongs;
##   * a value written as a COLLECTION that does not fit on a line — a phase list — replaces the
##     old value's lines wholesale. Comments inside a replaced block are lost.
##
## Every edit is proved by re-parsing: the result is refused unless the parser reads back
## exactly what was written, so a shape the writer misjudges fails loudly instead of
## corrupting a doc. TODO: multi-paragraph prose whose paragraphs are not plain wrapped text
## (indented lines, lists) is refused rather than rewritten — copy is not tuned, so nothing
## writes it yet.
##
## Results are {"ok": bool, "text": String, "error": String}; on failure `text` is the input.

const SpecFrontmatter := preload("res://tools/spec_import/frontmatter.gd")
const SpecSchema := preload("res://tools/spec_import/schema.gd")

## Every nest in the roster is indented by two spaces (SpecSchema.INDENT_STEP).
const INDENT_STEP: int = 2
## A mapping or list is written on one line while its flow form is at most this long, which
## is roughly what the roster's own flow maps run to; longer ones are written as blocks.
const FLOW_MAX_LENGTH: int = 72
## A string is written as a folded block scalar (`>-`) rather than quoted once it is longer
## than this, matching how the docs already write prose (the `exceptions:` reasons).
const PROSE_MIN_LENGTH: int = 48
## The widest line a folded block scalar's body is wrapped to.
const PROSE_WRAP: int = 96


#region Public API
## `markdown` with the value at `path` set to `value`.
static func set_value(markdown: String, path: Array, value: Variant) -> Dictionary:
	return _edit(markdown, path, value, false)


## `markdown` with the value at `path` removed. Removing what is not there succeeds unchanged.
static func remove_value(markdown: String, path: Array) -> Dictionary:
	return _edit(markdown, path, null, true)


## The value at `path` in a parsed frontmatter Dictionary, or `a_default` when absent.
static func value_at(data: Variant, path: Array, a_default: Variant = null) -> Variant:
	var node: Variant = data
	for step: Variant in path:
		if step is int and node is Array and int(step) < (node as Array).size():
			node = node[step]
		elif step is String and node is Dictionary and (node as Dictionary).has(step):
			node = node[step]
		else:
			return a_default
	return node


## Whether two parsed values say the same thing — numbers by value, collections deeply.
static func is_same_value(a: Variant, b: Variant) -> bool:
	if _is_number(a) and _is_number(b):
		return is_equal_approx(float(a), float(b))
	if a is Dictionary and b is Dictionary:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return false
		for key: Variant in a:
			if not (b as Dictionary).has(key) or not is_same_value(a[key], b[key]):
				return false
		return true
	if a is Array and b is Array:
		if (a as Array).size() != (b as Array).size():
			return false
		for i: int in (a as Array).size():
			if not is_same_value(a[i], b[i]):
				return false
		return true
	if (a is String or a is StringName) and (b is String or b is StringName):
		return str(a) == str(b)
	return typeof(a) == typeof(b) and a == b


#endregion


#region The edit
static func _edit(markdown: String, path: Array, value: Variant, remove: bool) -> Dictionary:
	if path.is_empty():
		return _fail(markdown, "an empty path names the whole frontmatter")
	var all_lines: PackedStringArray = markdown.split("\n")
	var fence_end: int = _fence_end(all_lines)
	if fence_end < 0:
		return _fail(markdown, "the doc has no closed frontmatter block")
	var current: Dictionary = SpecFrontmatter.parse(markdown)
	if not current["ok"]:
		return _fail(markdown, "the doc does not parse: %s" % current["error"])
	# An edit that would say what the doc already says leaves every byte alone — including
	# a value spelled differently from how the writer would spell it.
	var absent: Object = RefCounted.new()
	var existing: Variant = value_at(current["data"], path, absent)
	var is_present: bool = not (existing is Object and existing == absent)
	if (
		(remove and not is_present)
		or (not remove and is_present and is_same_value(existing, value))
	):
		return {"ok": true, "text": markdown, "error": ""}
	var lines: Array = []
	for i: int in range(1, fence_end):
		lines.append(all_lines[i])

	var error: String = _edit_mapping(lines, 0, lines.size(), 0, -1, path, value, remove)
	if not error.is_empty():
		return _fail(markdown, error)

	var out: Array = [all_lines[0]]
	out.append_array(lines)
	for i: int in range(fence_end, all_lines.size()):
		out.append(all_lines[i])
	var text: String = SpecSchema.reorder_frontmatter("\n".join(out))
	return _proved(markdown, text, path, value, remove)


## Refuse an edit the parser does not read back as written.
static func _proved(
	original: String, text: String, path: Array, value: Variant, remove: bool
) -> Dictionary:
	var parsed: Dictionary = SpecFrontmatter.parse(text)
	if not parsed["ok"]:
		return _fail(original, "the edit left a doc that does not parse: %s" % parsed["error"])
	var absent: Object = RefCounted.new()
	var read_back: Variant = value_at(parsed["data"], path, absent)
	if remove:
		if read_back is Object and read_back == absent:
			return {"ok": true, "text": text, "error": ""}
		return _fail(original, "%s is still there after removing it" % _path_text(path))
	if read_back is Object and read_back == absent:
		return _fail(original, "%s was not written" % _path_text(path))
	if not is_same_value(read_back, value):
		return _fail(original, "%s reads back as %s, not %s" % [_path_text(path), read_back, value])
	return {"ok": true, "text": text, "error": ""}


## Edit the mapping in `lines[start, end)` whose keys sit at `indent`. `dash` is the column of
## the `- ` that opens a sequence item when the mapping is one (its first key shares that
## line), else -1. Returns "" or an error.
static func _edit_mapping(
	lines: Array,
	start: int,
	end: int,
	indent: int,
	dash: int,
	path: Array,
	value: Variant,
	remove: bool
) -> String:
	if not (path[0] is String):
		return "%s indexes a mapping with a number" % _path_text(path)
	var key: String = path[0]
	var entries: Array = _entries(lines, start, end, indent, dash)
	var entry: Dictionary = {}
	for candidate: Dictionary in entries:
		if candidate["key"] == key:
			entry = candidate
	if entry.is_empty():
		if remove:
			return ""
		var nested: Variant = _nest(path.slice(1), value)
		var at: int = _last_content_line(lines, start, end) + 1
		var new_lines: Array = _entry_lines(key, nested, indent)
		for i: int in new_lines.size():
			lines.insert(at + i, new_lines[i])
		return ""

	var line: int = entry["line"]
	var inline: String = entry["inline"]
	if path.size() == 1:
		if remove:
			if line == start and dash >= 0:
				return "cannot remove %s: it opens its list item" % key
			_delete(lines, line, entry["end"])
			return ""
		return _replace_entry(lines, entry, value, indent)

	if not inline.is_empty() and not _is_block_scalar_header(inline):
		var edited: Variant = _flow_edit(inline, path.slice(1), value, remove)
		if edited is Dictionary:
			return str(edited["error"])
		lines[line] = _with_inline(lines[line], entry, str(edited))
		return ""
	var child_start: int = line + 1
	var child_end: int = entry["end"]
	var first: int = _first_content_line(lines, child_start, child_end)
	if first < 0:
		# `key:` with nothing under it: treat as an empty mapping or list to grow.
		var grown: Variant = _nest(path.slice(1), value)
		lines[line] = _with_inline(lines[line], entry, "")
		var block: Array = _block_lines(grown, indent + INDENT_STEP)
		for i: int in block.size():
			lines.insert(child_start + i, block[i])
		return ""
	var child_indent: int = _indent_of(lines[first])
	if _text_at(lines[first], child_indent).begins_with("- "):
		return _edit_sequence(
			lines, child_start, child_end, child_indent, path.slice(1), value, remove
		)
	return _edit_mapping(
		lines, child_start, child_end, child_indent, -1, path.slice(1), value, remove
	)


static func _edit_sequence(
	lines: Array, start: int, end: int, indent: int, path: Array, value: Variant, remove: bool
) -> String:
	if not (path[0] is int):
		return "%s names a key in a list" % _path_text(path)
	var index: int = path[0]
	var items: Array = _items(lines, start, end, indent)
	if index == items.size() and path.size() == 1 and not remove:
		var at: int = _last_content_line(lines, start, end) + 1
		var new_lines: Array = _item_lines(value, indent)
		for i: int in new_lines.size():
			lines.insert(at + i, new_lines[i])
		return ""
	if index < 0 or index >= items.size():
		return "" if remove else "%s is past the end of its list" % _path_text(path)
	var item: Dictionary = items[index]
	if path.size() == 1:
		_delete(lines, item["line"], item["end"])
		if remove:
			return ""
		var new_lines: Array = _item_lines(value, indent)
		for i: int in new_lines.size():
			lines.insert(item["line"] + i, new_lines[i])
		return ""
	var content: String = _content(lines[item["line"]]).substr(indent + 2).strip_edges()
	if content.begins_with("{") or content.begins_with("["):
		var edited: Variant = _flow_edit(content, path.slice(1), value, remove)
		if edited is Dictionary:
			return str(edited["error"])
		lines[item["line"]] = (
			" ".repeat(indent) + "- " + str(edited) + _comment_of(lines[item["line"]])
		)
		return ""
	return _edit_mapping(
		lines, item["line"], item["end"], indent + 2, indent, path.slice(1), value, remove
	)


## Rewrite one entry's value: on its own line when it fits there, as a block under it when not.
static func _replace_entry(lines: Array, entry: Dictionary, value: Variant, indent: int) -> String:
	var line: int = entry["line"]
	_delete(lines, line + 1, entry["end"])
	if _fits_inline(value):
		lines[line] = _with_inline(lines[line], entry, _inline(value))
		return ""
	lines[line] = _with_inline(lines[line], entry, _block_header(value))
	var block: Array = _block_body(value, indent + INDENT_STEP)
	for i: int in block.size():
		lines.insert(line + 1 + i, block[i])
	return ""


#endregion


#region Reading the lines
## The keys of the mapping in `lines[start, end)` at `indent`: {key, line, inline, end,
## value_column}, where `end` is the first line past the entry's value.
static func _entries(lines: Array, start: int, end: int, indent: int, dash: int) -> Array:
	var keyed: Array = []
	for i: int in range(start, end):
		if _is_blank_or_comment(lines[i]):
			continue
		var is_dash_line: bool = i == start and dash >= 0
		if not is_dash_line and _indent_of(lines[i]) != indent:
			continue
		var text: String = _content(lines[i]).substr(indent)
		if not is_dash_line and text.begins_with("- "):
			continue
		var colon: int = SpecFrontmatter.key_colon(text)
		if colon < 0:
			continue
		(
			keyed
			. append(
				{
					"key": SpecFrontmatter._unquote(text.substr(0, colon).strip_edges()),
					"line": i,
					"inline": text.substr(colon + 1).strip_edges(),
					"value_column": indent + colon + 1,
				}
			)
		)
	for k: int in keyed.size():
		var next: int = keyed[k + 1]["line"] if k + 1 < keyed.size() else end
		keyed[k]["end"] = _last_content_line(lines, keyed[k]["line"], next) + 1
	return keyed


## The items of the sequence in `lines[start, end)` whose dashes sit at `indent`.
static func _items(lines: Array, start: int, end: int, indent: int) -> Array:
	var openers: Array[int] = []
	for i: int in range(start, end):
		if _is_blank_or_comment(lines[i]) or _indent_of(lines[i]) != indent:
			continue
		if _text_at(lines[i], indent).begins_with("- ") or _text_at(lines[i], indent) == "-":
			openers.append(i)
	var items: Array = []
	for k: int in openers.size():
		var next: int = openers[k + 1] if k + 1 < openers.size() else end
		items.append({"line": openers[k], "end": _last_content_line(lines, openers[k], next) + 1})
	return items


static func _fence_end(lines: PackedStringArray) -> int:
	if lines.size() == 0 or lines[0].strip_edges() != "---":
		return -1
	for i: int in range(1, lines.size()):
		var stripped: String = lines[i].strip_edges()
		if stripped == "---" or stripped == "...":
			return i
	return -1


static func _last_content_line(lines: Array, start: int, end: int) -> int:
	var last: int = start - 1
	for i: int in range(start, end):
		if not _is_blank_or_comment(lines[i]):
			last = i
	return last


static func _first_content_line(lines: Array, start: int, end: int) -> int:
	for i: int in range(start, end):
		if not _is_blank_or_comment(lines[i]):
			return i
	return -1


static func _is_blank_or_comment(line: String) -> bool:
	var stripped: String = line.strip_edges()
	return stripped.is_empty() or stripped.begins_with("#")


static func _indent_of(line: String) -> int:
	return line.length() - line.lstrip(" ").length()


static func _text_at(line: String, column: int) -> String:
	return _content(line).substr(column)


## A line without its trailing comment or trailing whitespace.
static func _content(line: String) -> String:
	return SpecFrontmatter._strip_comment(line).rstrip(" ")


## A line's trailing comment, with the spacing before it, or "".
static func _comment_of(line: String) -> String:
	var content: String = SpecFrontmatter._strip_comment(line)
	if content.length() == line.length():
		return ""
	return line.substr(content.rstrip(" ").length())


static func _is_block_scalar_header(inline: String) -> bool:
	return inline.length() <= 2 and (inline.begins_with("|") or inline.begins_with(">"))


static func _delete(lines: Array, start: int, end: int) -> void:
	for i: int in range(end - 1, start - 1, -1):
		lines.remove_at(i)


## An entry's line with its value replaced by `inline` (which may be ""), keeping the key, the
## dash of a list item and the trailing comment.
static func _with_inline(line: String, entry: Dictionary, inline: String) -> String:
	var head: String = line.substr(0, entry["value_column"])
	return head + (" " + inline if not inline.is_empty() else "") + _comment_of(line)


#endregion


#region Flow collections
## `flow` (a `{…}` or `[…]` literal) with the value at `path` set or removed, or
## {"error": String}.
static func _flow_edit(flow: String, path: Array, value: Variant, remove: bool) -> Variant:
	var is_map: bool = flow.begins_with("{")
	if not is_map and not flow.begins_with("["):
		return {"error": "%s goes inside a value that is not a collection" % _path_text(path)}
	var parts: Array = _split_flow(flow.substr(1, flow.length() - 2))
	var step: Variant = path[0]
	var found: int = -1
	if is_map:
		if not (step is String):
			return {"error": "%s indexes a mapping with a number" % _path_text(path)}
		for i: int in parts.size():
			var colon: int = SpecFrontmatter.key_colon(parts[i])
			if (
				colon >= 0
				and SpecFrontmatter._unquote(parts[i].substr(0, colon).strip_edges()) == step
			):
				found = i
	else:
		if not (step is int):
			return {"error": "%s names a key in a list" % _path_text(path)}
		found = step if int(step) < parts.size() else -1

	if found < 0:
		if remove:
			return flow
		if not is_map and int(step) != parts.size():
			return {"error": "%s is past the end of its list" % _path_text(path)}
		var nested: Variant = _nest(path.slice(1), value)
		parts.append(("%s: %s" % [step, _inline(nested)]) if is_map else _inline(nested))
	elif path.size() == 1:
		if remove:
			parts.remove_at(found)
		else:
			parts[found] = ("%s: %s" % [step, _inline(value)]) if is_map else _inline(value)
	else:
		var inner: String = parts[found]
		var head: String = ""
		if is_map:
			var colon: int = SpecFrontmatter.key_colon(inner)
			head = inner.substr(0, colon + 1) + " "
			inner = inner.substr(colon + 1).strip_edges()
		var edited: Variant = _flow_edit(inner, path.slice(1), value, remove)
		if edited is Dictionary:
			return edited
		parts[found] = head + str(edited)
	var body: String = ", ".join(parts)
	return ("{%s}" if is_map else "[%s]") % body


## A flow literal's body split at its top-level commas, each part trimmed.
static func _split_flow(body: String) -> Array:
	var parts: Array = []
	var depth: int = 0
	var quote: String = ""
	var from: int = 0
	for i: int in body.length():
		var c: String = body[i]
		if not quote.is_empty():
			if c == quote:
				quote = ""
			continue
		if c == '"' or c == "'":
			quote = c
		elif c == "{" or c == "[":
			depth += 1
		elif c == "}" or c == "]":
			depth -= 1
		elif c == "," and depth == 0:
			parts.append(body.substr(from, i - from).strip_edges())
			from = i + 1
	var last: String = body.substr(from).strip_edges()
	if not last.is_empty():
		parts.append(last)
	return parts


#endregion


#region Writing values
## `value` wrapped in the mappings `path` names, for a key the doc does not have yet. A numeric
## step makes a one-item list.
static func _nest(path: Array, value: Variant) -> Variant:
	var nested: Variant = value
	for i: int in range(path.size() - 1, -1, -1):
		nested = [nested] if path[i] is int else {path[i]: nested}
	return nested


## A new `key: value` entry, inline or as a block.
static func _entry_lines(key: String, value: Variant, indent: int) -> Array:
	var pad: String = " ".repeat(indent)
	if _fits_inline(value):
		return [pad + key + ": " + _inline(value)]
	var out: Array = [pad + key + ":" + _block_header_suffix(value)]
	out.append_array(_block_body(value, indent + INDENT_STEP))
	return out


## A new list item, its first key on the dash line.
static func _item_lines(value: Variant, indent: int) -> Array:
	var pad: String = " ".repeat(indent)
	if _fits_inline(value) or not (value is Dictionary):
		return [pad + "- " + _inline(value)]
	var body: Array = _block_lines(value, indent + 2)
	if body.is_empty():
		return [pad + "- {}"]
	body[0] = pad + "- " + str(body[0]).substr(indent + 2)
	return body


## `value` as the lines of a block at `indent` — mapping entries or list items.
static func _block_lines(value: Variant, indent: int) -> Array:
	var out: Array = []
	if value is Dictionary:
		for key: Variant in value:
			out.append_array(_entry_lines(str(key), value[key], indent))
	elif value is Array:
		for item: Variant in value:
			out.append_array(_item_lines(item, indent))
	return out


## What follows `key:` on its own line for a value written as a block.
static func _block_header(value: Variant) -> String:
	return _block_header_suffix(value).strip_edges()


static func _block_header_suffix(value: Variant) -> String:
	return " >-" if value is String or value is StringName else ""


## The lines under `key:` for a block value: a mapping, a list, or folded prose.
static func _block_body(value: Variant, indent: int) -> Array:
	if value is String or value is StringName:
		return _folded_lines(str(value), indent)
	return _block_lines(value, indent)


## Prose as a folded block's body: each paragraph wrapped, a blank line between paragraphs
## (which is what the parser reads back as one line break).
static func _folded_lines(text: String, indent: int) -> Array:
	var out: Array = []
	var paragraphs: PackedStringArray = text.split("\n")
	for p: int in paragraphs.size():
		if p > 0:
			out.append("")
		var line: String = ""
		for word: String in paragraphs[p].split(" ", false):
			if not line.is_empty() and indent + line.length() + 1 + word.length() > PROSE_WRAP:
				out.append(" ".repeat(indent) + line)
				line = word
			else:
				line = word if line.is_empty() else line + " " + word
		if not line.is_empty():
			out.append(" ".repeat(indent) + line)
	return out


static func _fits_inline(value: Variant) -> bool:
	if value is String or value is StringName:
		var text: String = str(value)
		return (
			text.length() <= PROSE_MIN_LENGTH
			and not text.contains("\n")
			and not (text.contains('"') and text.contains("'"))
		)
	if value is Dictionary or value is Array:
		var members: Array = (value as Dictionary).values() if value is Dictionary else value
		for item: Variant in members:
			if item is Dictionary and value is Array:
				return false
			if not _fits_inline(item):
				return false
		return _inline(value).length() <= FLOW_MAX_LENGTH
	return true


## `value` on one line: a scalar, or a flow collection.
static func _inline(value: Variant) -> String:
	if value is Dictionary:
		var parts: Array = []
		for key: Variant in value:
			parts.append("%s: %s" % [key, _inline(value[key])])
		return "{%s}" % ", ".join(parts)
	if value is Array:
		var items: Array = []
		for item: Variant in value:
			items.append(_inline(item))
		return "[%s]" % ", ".join(items)
	return _scalar_text(value)


static func _scalar_text(value: Variant) -> String:
	if value == null:
		return "null"
	if value is bool:
		return "true" if value else "false"
	if _is_number(value):
		return _number_text(float(value))
	var text: String = str(value)
	if not _needs_quotes(text):
		return text
	return ("'%s'" if text.contains('"') else '"%s"') % text


## A number as briefly as it can be written: whole numbers without a point, the rest to the
## precision a tuning field can mean.
static func _number_text(number: float) -> String:
	if is_equal_approx(number, roundf(number)) and absf(number) < 1.0e9:
		return str(int(roundf(number)))
	return String.num(number, 4)


static func _needs_quotes(text: String) -> bool:
	if text.is_empty() or text in ["true", "false", "null", "~"]:
		return true
	if text.is_valid_float() or text.is_valid_int():
		return true
	for c: String in [" #", ": ", ",", "{", "}", "[", "]", "'", '"', "\n"]:
		if text.contains(c):
			return true
	if text.ends_with(":"):
		return true
	return text != text.strip_edges() or text[0] in ["-", ">", "|", "#", "&", "*", "!", "%", "@"]


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


#endregion


static func _path_text(path: Array) -> String:
	var parts: Array = []
	for step: Variant in path:
		parts.append("[%d]" % step if step is int else ".%s" % step)
	return "".join(parts).trim_prefix(".")


static func _fail(text: String, error: String) -> Dictionary:
	return {"ok": false, "text": text, "error": error}
