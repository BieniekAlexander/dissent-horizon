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
##   - block scalars: `key: |` (literal, newlines kept) and `key: >` (folded,
##     newlines within a paragraph become spaces, blank lines stay breaks).
##     A chomping indicator (`|-`, `>+`, …) parses but is ignored: the value is
##     always trailing-trimmed, which is what every consumer of this schema wants.
##     Comment stripping does NOT apply inside a block scalar, so prose may
##     contain `#`.
## Anchors, aliases, and tag syntax are NOT supported.
##
## Obsidian wikilinks are accepted anywhere a string scalar appears: a value that
## is entirely a wikilink ("[[warlord]]", "[[dir/warlord#Heading|alias]]") is
## reduced to the link target's basename ("warlord"), so docs can stay navigable
## in Obsidian while the importer sees plain identifiers.

## parse/parse_file result: {"ok": bool, "data": Dictionary, "error": String}.
## `error` is "" on success; on failure `data` is empty and `error` names the
## offending line.


static func parse_file(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return _err("cannot open %s" % path)
	var text: String = f.get_as_text()
	f.close()
	return parse(text)


## Parses a full markdown document; returns ok with empty data when the document
## has no frontmatter block (a prose-only doc is not an error).
static func parse(markdown: String) -> Dictionary:
	var lines: PackedStringArray = markdown.split("\n")
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
static func parse_yaml(lines: Array[String]) -> Dictionary:
	var cleaned: Variant = _clean_lines(lines)
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


## Index of the colon separating a key from its value on one line, or -1 when the
## line is not a key/value pair. Exposed because the canonical-order rewrite
## (SpecSchema) works on the same lines and must agree with this parser about
## where a key ends.
static func key_colon(text: String) -> int:
	return _find_key_colon(text)


## "[[target|alias]]" / "[[dir/target#anchor]]" -> "target"; other strings pass
## through unchanged. Only applies when the WHOLE string is one wikilink.
static func strip_wikilink(value: String) -> String:
	var s: String = value.strip_edges()
	if not (s.begins_with("[[") and s.ends_with("]]")):
		return value
	var inner: String = s.substr(2, s.length() - 4)
	if inner.contains("]]") or inner.contains("[["):
		return value
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
static func _clean_lines(lines: Array[String]) -> Variant:
	var rows: Array = []
	var i: int = 0
	while i < lines.size():
		var line: String = lines[i]
		var no_comment: String = _strip_comment(line)
		if no_comment.strip_edges() == "":
			i += 1
			continue
		var indent: int = 0
		while indent < no_comment.length() and no_comment[indent] == " ":
			indent += 1
		if indent < no_comment.length() and no_comment[indent] == "\t":
			return "tab indentation is not valid YAML: %s" % line.strip_edges()
		var text: String = no_comment.substr(indent).strip_edges()
		# A block scalar is collapsed into ONE row carrying its finished value, so the
		# mapping/sequence parsers below never learn that multi-line scalars exist.
		var header: Dictionary = _block_scalar_header(text)
		if header.is_empty():
			rows.append({"indent": indent, "text": text})
			i += 1
			continue
		var gathered: Dictionary = _gather_block_scalar(lines, i + 1, indent, header["folded"])
		rows.append({
			"indent": indent, "text": "%s:" % header["key"], "scalar": gathered["value"],
		})
		i = gathered["next"]
	return rows


## `{"key": …, "folded": bool}` when `a_text` is a block-scalar header (`name: |`,
## `name: >-`), else {}. A dash-prefixed sequence item is deliberately excluded: this
## schema always writes block scalars as their own `key:` line inside an item.
static func _block_scalar_header(text: String) -> Dictionary:
	if text.begins_with("- "):
		return {}
	var colon: int = _find_key_colon(text)
	if colon == -1:
		return {}
	var rest: String = text.substr(colon + 1).strip_edges()
	if rest != "|" and rest != ">" and rest != "|-" and rest != ">-" \
			and rest != "|+" and rest != ">+":
		return {}
	return {
		"key": _unquote(text.substr(0, colon).strip_edges()),
		"folded": rest.begins_with(">"),
	}


## Reads a block scalar's body: every line after the header that is blank or indented
## deeper than the header, with the block's own indentation removed.
##
## Blank lines are KEPT (they are paragraph breaks in the value) even though the row
## scanner drops them elsewhere, and comments are NOT stripped — a `#` inside prose is
## content, not a comment. Returns {"value": String, "next": int}.
static func _gather_block_scalar(lines: Array[String], start: int, key_indent: int,
		folded: bool) -> Dictionary:
	var raw: Array[String] = []
	var i: int = start
	var block_indent: int = -1
	while i < lines.size():
		var line: String = lines[i]
		if line.strip_edges() == "":
			raw.append("")
			i += 1
			continue
		var indent: int = 0
		while indent < line.length() and line[indent] == " ":
			indent += 1
		if indent <= key_indent:
			break
		if block_indent == -1:
			block_indent = indent
		raw.append(line.substr(mini(block_indent, indent)))
		i += 1
	# Trailing blank lines are never part of the value (chomping is not honoured; see
	# the class docs), so drop them before joining.
	while not raw.is_empty() and raw[raw.size() - 1].strip_edges() == "":
		raw.remove_at(raw.size() - 1)
	return {"value": _join_block(raw, folded), "next": i}


## Literal: the lines as they stand. Folded: newlines inside a paragraph become spaces,
## and a blank line stays a single break between paragraphs.
static func _join_block(raw: Array[String], folded: bool) -> String:
	if not folded:
		return "\n".join(raw)
	var paragraphs: Array[String] = []
	var current: Array[String] = []
	for line: String in raw:
		if line.strip_edges() == "":
			if not current.is_empty():
				paragraphs.append(" ".join(current))
				current = []
		else:
			current.append(line.strip_edges())
	if not current.is_empty():
		paragraphs.append(" ".join(current))
	return "\n".join(paragraphs)


## Removes a trailing " # comment" that is outside quotes/brackets.
static func _strip_comment(line: String) -> String:
	var in_quote: String = ""
	for i in line.length():
		var c: String = line[i]
		if in_quote != "":
			if c == in_quote:
				in_quote = ""
			continue
		if c == "\"" or c == "'":
			in_quote = c
		elif c == "#" and (i == 0 or line[i - 1] == " " or line[i - 1] == "\t"):
			return line.substr(0, i)
	return line


# --------------------------------------------------------------------------- #
# Block parsing
# --------------------------------------------------------------------------- #
## Parses rows[start..] at exactly `indent` into one value (mapping or sequence).
## Returns {"value": Variant, "next": int} or {"error": String}.
static func _parse_block(rows: Array, start: int, indent: int) -> Dictionary:
	if rows[start]["text"].begins_with("- ") or rows[start]["text"] == "-":
		return _parse_sequence(rows, start, indent)
	return _parse_mapping(rows, start, indent)


static func _parse_mapping(rows: Array, start: int, indent: int) -> Dictionary:
	var map: Dictionary = {}
	var i: int = start
	while i < rows.size():
		var row: Dictionary = rows[i]
		if row["indent"] < indent:
			break
		if row["indent"] > indent:
			return {"error": "unexpected indentation: %s" % row["text"]}
		var text: String = row["text"]
		if text.begins_with("- "):
			break
		var colon: int = _find_key_colon(text)
		if colon == -1:
			return {"error": "expected 'key: value': %s" % text}
		var key: String = _unquote(text.substr(0, colon).strip_edges())
		# A KEY WRITTEN TWICE AT ONE LEVEL ABORTS THE IMPORT rather than taking the last one.
		# YAML's own rule is last-wins, silently, which is the worst possible answer here: the
		# value a reader sees first is not the value the game gets, and the two are usually
		# different precisely because someone edited the wrong line. Validation in this
		# pipeline is total and loud, and a doc that says two things about one key is exactly
		# the case that policy exists for.
		if map.has(key):
			return {"error": "duplicate key '%s' at this level: %s" % [key, text]}
		var rest: String = text.substr(colon + 1).strip_edges()
		i += 1
		if row.has("scalar"):
			# A block scalar, already resolved by _clean_lines.
			map[key] = row["scalar"]
		elif rest != "":
			var scalar: Variant = _parse_flow(rest)
			if scalar is Dictionary and scalar.has("__error"):
				return {"error": scalar["__error"]}
			map[key] = scalar
		elif i < rows.size() and rows[i]["indent"] > indent:
			var nested: Dictionary = _parse_block(rows, i, rows[i]["indent"])
			if nested.has("error"):
				return nested
			map[key] = nested["value"]
			i = nested["next"]
		elif i < rows.size() and rows[i]["indent"] == indent \
				and (rows[i]["text"].begins_with("- ") or rows[i]["text"] == "-"):
			# YAML allows sequence items at the SAME indent as their key.
			var seq: Dictionary = _parse_sequence(rows, i, indent)
			if seq.has("error"):
				return seq
			map[key] = seq["value"]
			i = seq["next"]
		else:
			map[key] = null
	return {"value": map, "next": i}


static func _parse_sequence(rows: Array, start: int, indent: int) -> Dictionary:
	var seq: Array = []
	var i: int = start
	while i < rows.size():
		var row: Dictionary = rows[i]
		if row["indent"] != indent or not (row["text"].begins_with("- ") or row["text"] == "-"):
			if row["indent"] >= indent and (row["text"].begins_with("- ") or row["text"] == "-"):
				return {"error": "misaligned sequence item: %s" % row["text"]}
			break
		var rest: String = row["text"].substr(1).strip_edges()   # after the dash
		# Gather this item's continuation lines (deeper-indented block under the dash).
		var block_end: int = i + 1
		while block_end < rows.size() and rows[block_end]["indent"] > indent:
			block_end += 1
		if rest == "":
			if block_end == i + 1:
				seq.append(null)
			else:
				var nested: Dictionary = _parse_block(rows, i + 1, rows[i + 1]["indent"])
				if nested.has("error"):
					return nested
				seq.append(nested["value"])
			i = block_end
		elif _find_key_colon(rest) != -1 and not rest.begins_with("{") and not rest.begins_with("["):
			# Mapping whose first entry sits on the dash line. Re-parse the item as
			# its own mini-document: the dash-line content dedented to the
			# continuation indent, followed by the continuation lines.
			var item_rows: Array = [{"indent": indent + 2, "text": rest}]
			for j in range(i + 1, block_end):
				item_rows.append(rows[j])
			var item: Dictionary = _parse_mapping(item_rows, 0, indent + 2)
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
static func _parse_flow(text: String) -> Variant:
	var s: String = text.strip_edges()
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
static func _split_flow(text: String) -> Array:
	var parts: Array = []
	var depth: int = 0
	var in_quote: String = ""
	var current: String = ""
	for i in text.length():
		var c: String = text[i]
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


static func _parse_scalar(text: String) -> Variant:
	var s: String = text.strip_edges()
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
static func _find_key_colon(text: String) -> int:
	var in_quote: String = ""
	for i in text.length():
		var c: String = text[i]
		if in_quote != "":
			if c == in_quote:
				in_quote = ""
			continue
		if c == "\"" or c == "'":
			in_quote = c
		elif c == ":" and (i == text.length() - 1 or text[i + 1] == " "):
			return i
	return -1


static func _unquote(text: String) -> String:
	if (text.begins_with("\"") and text.ends_with("\"") and text.length() >= 2) \
			or (text.begins_with("'") and text.ends_with("'") and text.length() >= 2):
		return text.substr(1, text.length() - 2)
	return text


static func _err(message: String) -> Dictionary:
	return {"ok": false, "data": {}, "error": message}
