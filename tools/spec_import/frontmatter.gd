class_name SpecFrontmatter
extends RefCounted

## Parses the YAML frontmatter block of an Obsidian markdown doc into a Dictionary.
##
## Only the frontmatter (the block between the leading `---` fences) is read; the
## markdown body is ignored. The YAML subset supported is exactly what the spec
## schema needs (see tools/spec_import/README.md):
##   - scalar values: int, float, bool, null, quoted/unquoted strings
##   - flow collections: {a: 1, b: 2} and [x, y]
##   - block mappings (nested by indentation) and block sequences ("- item"),
##     including sequences of mappings (the `weapons:` list)
##   - full-line and trailing `#` comments
## Anchors, aliases, multi-line scalars, and tag syntax are NOT supported.
##
## Obsidian wikilinks are accepted anywhere a string scalar appears: a value that
## is entirely a wikilink ("[[warlord]]", "[[dir/warlord#Heading|alias]]") is
## reduced to the link target's basename ("warlord"), so docs can stay navigable
## in Obsidian while the importer sees plain identifiers.

## parse/parse_file result: {"ok": bool, "data": Dictionary, "error": String}.
## `error` is "" on success; on failure `data` is empty and `error` names the
## offending line.


static func parse_file(a_path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(a_path, FileAccess.READ)
	if f == null:
		return _err("cannot open %s" % a_path)
	var text: String = f.get_as_text()
	f.close()
	return parse(text)


## Parses a full markdown document; returns ok with empty data when the document
## has no frontmatter block (a prose-only doc is not an error).
static func parse(a_markdown: String) -> Dictionary:
	var lines: PackedStringArray = a_markdown.split("\n")
	if lines.size() == 0 or lines[0].strip_edges() != "---":
		return {"ok": true, "data": {}, "error": ""}
	var fence_end: int = -1
	for i in range(1, lines.size()):
		var stripped: String = lines[i].strip_edges()
		if stripped == "---" or stripped == "...":
			fence_end = i
			break
	if fence_end == -1:
		return _err("frontmatter fence '---' is never closed")
	var body: Array[String] = []
	for i in range(1, fence_end):
		body.append(lines[i])
	return parse_yaml(body)


## Parses bare YAML lines (no fences). Exposed for tests.
static func parse_yaml(a_lines: Array[String]) -> Dictionary:
	var cleaned: Variant = _clean_lines(a_lines)
	if cleaned is String:
		return _err(cleaned as String)
	var rows: Array = cleaned
	if rows.is_empty():
		return {"ok": true, "data": {}, "error": ""}
	var result: Dictionary = _parse_block(rows, 0, rows[0]["indent"])
	if result.has("error"):
		return _err(result["error"])
	if not (result["value"] is Dictionary):
		return _err("top-level frontmatter must be a mapping")
	if result["next"] != rows.size():
		return _err("unexpected content at line: %s" % rows[result["next"]]["text"])
	return {"ok": true, "data": result["value"], "error": ""}


## "[[target|alias]]" / "[[dir/target#anchor]]" -> "target"; other strings pass
## through unchanged. Only applies when the WHOLE string is one wikilink.
static func strip_wikilink(a_value: String) -> String:
	var s: String = a_value.strip_edges()
	if not (s.begins_with("[[") and s.ends_with("]]")):
		return a_value
	var inner: String = s.substr(2, s.length() - 4)
	if inner.contains("]]") or inner.contains("[["):
		return a_value
	# The reference is the link TARGET; the display alias (after |) is cosmetic.
	inner = inner.split("|")[0]
	inner = inner.split("#")[0]
	inner = inner.get_file() if inner.contains("/") else inner
	return inner.strip_edges()


# --------------------------------------------------------------------------- #
# Line preparation
# --------------------------------------------------------------------------- #
## Rows of {"indent": int, "text": String} with blanks/comments removed and
## trailing comments stripped. Returns an error String on tab indentation.
static func _clean_lines(a_lines: Array[String]) -> Variant:
	var rows: Array = []
	for line in a_lines:
		var no_comment: String = _strip_comment(line)
		if no_comment.strip_edges() == "":
			continue
		var indent: int = 0
		while indent < no_comment.length() and no_comment[indent] == " ":
			indent += 1
		if indent < no_comment.length() and no_comment[indent] == "\t":
			return "tab indentation is not valid YAML: %s" % line.strip_edges()
		rows.append({"indent": indent, "text": no_comment.substr(indent).strip_edges()})
	return rows


## Removes a trailing " # comment" that is outside quotes/brackets.
static func _strip_comment(a_line: String) -> String:
	var in_quote: String = ""
	for i in a_line.length():
		var c: String = a_line[i]
		if in_quote != "":
			if c == in_quote:
				in_quote = ""
			continue
		if c == "\"" or c == "'":
			in_quote = c
		elif c == "#" and (i == 0 or a_line[i - 1] == " " or a_line[i - 1] == "\t"):
			return a_line.substr(0, i)
	return a_line


# --------------------------------------------------------------------------- #
# Block parsing
# --------------------------------------------------------------------------- #
## Parses rows[start..] at exactly `indent` into one value (mapping or sequence).
## Returns {"value": Variant, "next": int} or {"error": String}.
static func _parse_block(a_rows: Array, a_start: int, a_indent: int) -> Dictionary:
	if a_rows[a_start]["text"].begins_with("- ") or a_rows[a_start]["text"] == "-":
		return _parse_sequence(a_rows, a_start, a_indent)
	return _parse_mapping(a_rows, a_start, a_indent)


static func _parse_mapping(a_rows: Array, a_start: int, a_indent: int) -> Dictionary:
	var map: Dictionary = {}
	var i: int = a_start
	while i < a_rows.size():
		var row: Dictionary = a_rows[i]
		if row["indent"] < a_indent:
			break
		if row["indent"] > a_indent:
			return {"error": "unexpected indentation: %s" % row["text"]}
		var text: String = row["text"]
		if text.begins_with("- "):
			break
		var colon: int = _find_key_colon(text)
		if colon == -1:
			return {"error": "expected 'key: value': %s" % text}
		var key: String = _unquote(text.substr(0, colon).strip_edges())
		var rest: String = text.substr(colon + 1).strip_edges()
		i += 1
		if rest != "":
			var scalar: Variant = _parse_flow(rest)
			if scalar is Dictionary and scalar.has("__error"):
				return {"error": scalar["__error"]}
			map[key] = scalar
		elif i < a_rows.size() and a_rows[i]["indent"] > a_indent:
			var nested: Dictionary = _parse_block(a_rows, i, a_rows[i]["indent"])
			if nested.has("error"):
				return nested
			map[key] = nested["value"]
			i = nested["next"]
		elif i < a_rows.size() and a_rows[i]["indent"] == a_indent \
				and (a_rows[i]["text"].begins_with("- ") or a_rows[i]["text"] == "-"):
			# YAML allows sequence items at the SAME indent as their key.
			var seq: Dictionary = _parse_sequence(a_rows, i, a_indent)
			if seq.has("error"):
				return seq
			map[key] = seq["value"]
			i = seq["next"]
		else:
			map[key] = null
	return {"value": map, "next": i}


static func _parse_sequence(a_rows: Array, a_start: int, a_indent: int) -> Dictionary:
	var seq: Array = []
	var i: int = a_start
	while i < a_rows.size():
		var row: Dictionary = a_rows[i]
		if row["indent"] != a_indent or not (row["text"].begins_with("- ") or row["text"] == "-"):
			if row["indent"] >= a_indent and (row["text"].begins_with("- ") or row["text"] == "-"):
				return {"error": "misaligned sequence item: %s" % row["text"]}
			break
		var rest: String = row["text"].substr(1).strip_edges()   # after the dash
		# Gather this item's continuation lines (deeper-indented block under the dash).
		var block_end: int = i + 1
		while block_end < a_rows.size() and a_rows[block_end]["indent"] > a_indent:
			block_end += 1
		if rest == "":
			if block_end == i + 1:
				seq.append(null)
			else:
				var nested: Dictionary = _parse_block(a_rows, i + 1, a_rows[i + 1]["indent"])
				if nested.has("error"):
					return nested
				seq.append(nested["value"])
			i = block_end
		elif _find_key_colon(rest) != -1 and not rest.begins_with("{") and not rest.begins_with("["):
			# Mapping whose first entry sits on the dash line. Re-parse the item as
			# its own mini-document: the dash-line content dedented to the
			# continuation indent, followed by the continuation lines.
			var item_rows: Array = [{"indent": a_indent + 2, "text": rest}]
			for j in range(i + 1, block_end):
				item_rows.append(a_rows[j])
			var item: Dictionary = _parse_mapping(item_rows, 0, a_indent + 2)
			if item.has("error"):
				return item
			if item["next"] != item_rows.size():
				return {"error": "unexpected content in sequence item: %s" % rest}
			seq.append(item["value"])
			i = block_end
		else:
			if block_end != i + 1:
				return {"error": "scalar sequence item cannot have a nested block: %s" % rest}
			var scalar: Variant = _parse_flow(rest)
			if scalar is Dictionary and scalar.has("__error"):
				return {"error": scalar["__error"]}
			seq.append(scalar)
			i = block_end
	return {"value": seq, "next": i}


# --------------------------------------------------------------------------- #
# Flow (inline) values
# --------------------------------------------------------------------------- #
static func _parse_flow(a_text: String) -> Variant:
	var s: String = a_text.strip_edges()
	if s.begins_with("{"):
		if not s.ends_with("}"):
			return {"__error": "unterminated flow mapping: %s" % s}
		var map: Dictionary = {}
		for part in _split_flow(s.substr(1, s.length() - 2)):
			if part.strip_edges() == "":
				continue
			var colon: int = _find_key_colon(part)
			if colon == -1:
				return {"__error": "expected 'key: value' in flow mapping: %s" % part}
			var v: Variant = _parse_flow(part.substr(colon + 1))
			if v is Dictionary and v.has("__error"):
				return v
			map[_unquote(part.substr(0, colon).strip_edges())] = v
		return map
	if s.begins_with("["):
		if not s.ends_with("]"):
			return {"__error": "unterminated flow list: %s" % s}
		var list: Array = []
		for part in _split_flow(s.substr(1, s.length() - 2)):
			if part.strip_edges() == "":
				continue
			var v: Variant = _parse_flow(part)
			if v is Dictionary and v.has("__error"):
				return v
			list.append(v)
		return list
	return _parse_scalar(s)


## Splits flow-collection innards on top-level commas (quotes and nesting aware).
static func _split_flow(a_text: String) -> Array:
	var parts: Array = []
	var depth: int = 0
	var in_quote: String = ""
	var current: String = ""
	for i in a_text.length():
		var c: String = a_text[i]
		if in_quote != "":
			current += c
			if c == in_quote:
				in_quote = ""
			continue
		match c:
			"\"", "'":
				in_quote = c
				current += c
			"{", "[":
				depth += 1
				current += c
			"}", "]":
				depth -= 1
				current += c
			",":
				if depth == 0:
					parts.append(current)
					current = ""
				else:
					current += c
			_:
				current += c
	parts.append(current)
	return parts


static func _parse_scalar(a_text: String) -> Variant:
	var s: String = a_text.strip_edges()
	if s == "" or s == "~" or s == "null":
		return null
	if (s.begins_with("\"") and s.ends_with("\"") and s.length() >= 2) \
			or (s.begins_with("'") and s.ends_with("'") and s.length() >= 2):
		return strip_wikilink(s.substr(1, s.length() - 2))
	if s == "true":
		return true
	if s == "false":
		return false
	if s.is_valid_int():
		return s.to_int()
	if s.is_valid_float():
		return s.to_float()
	return strip_wikilink(s)


# --------------------------------------------------------------------------- #
# Small helpers
# --------------------------------------------------------------------------- #
## Index of the colon separating a key from its value: the first ": " (or a
## trailing ":"), outside quotes. -1 when the text is not a key/value pair.
## Plain colons inside values ("res://x") don't match because they lack the space.
static func _find_key_colon(a_text: String) -> int:
	var in_quote: String = ""
	for i in a_text.length():
		var c: String = a_text[i]
		if in_quote != "":
			if c == in_quote:
				in_quote = ""
			continue
		if c == "\"" or c == "'":
			in_quote = c
		elif c == ":" and (i == a_text.length() - 1 or a_text[i + 1] == " "):
			return i
	return -1


static func _unquote(a_text: String) -> String:
	if (a_text.begins_with("\"") and a_text.ends_with("\"") and a_text.length() >= 2) \
			or (a_text.begins_with("'") and a_text.ends_with("'") and a_text.length() >= 2):
		return a_text.substr(1, a_text.length() - 2)
	return a_text


static func _err(a_message: String) -> Dictionary:
	return {"ok": false, "data": {}, "error": a_message}
