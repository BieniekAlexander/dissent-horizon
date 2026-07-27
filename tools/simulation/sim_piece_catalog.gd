class_name SimPieceCatalog
extends RefCounted

## Piece id -> entity scene path, for the simulation framework.
##
## Reads `resources/generated/tools.json` DIRECTLY as a file rather than going through
## `Tool`'s registry. That is deliberate and load-bearing: touching the registry is what
## instantiates every tool scene in the game, and a file-scope reference to it from a test
## has already taken out a whole GUT run once (CLAUDE.md §A file-scope `preload` of an entity
## scene in a test can poison the whole run). A spec parser has no business booting content,
## and reading the JSON keeps this layer pure enough to unit-test.
##
## The map is a STATIC cache: it is read once per process and never changes, the file is a
## generated artifact of the spec importer, and every validated piece reference in every spec
## hits it. Rebuilding it per lookup would re-parse a 90-entry JSON file for each unit in
## each group.

const TOOLS_JSON: String = "res://resources/generated/tools.json"

static var _scene_by_piece: Dictionary = {}
static var _loaded: bool = false


## Scene path for `a_piece`, or "" when the catalog does not know it. Callers validate
## against has_piece() and report; nothing here guesses at a near match.
static func scene_path(a_piece: String) -> String:
	SimPieceCatalog._ensure_loaded()
	return str(SimPieceCatalog._scene_by_piece.get(a_piece, ""))


static func has_piece(a_piece: String) -> bool:
	SimPieceCatalog._ensure_loaded()
	return SimPieceCatalog._scene_by_piece.has(a_piece)


## Every piece id the catalog knows, sorted — what an error message offers when a spec names
## something that does not exist.
static func known_pieces() -> Array[String]:
	SimPieceCatalog._ensure_loaded()
	var pieces: Array[String] = []
	pieces.assign(SimPieceCatalog._scene_by_piece.keys())
	pieces.sort()
	return pieces


## Drop the cache. Exists for the importer-facing tests, which regenerate tools.json inside
## one process and would otherwise read the pre-regeneration map.
static func reset() -> void:
	SimPieceCatalog._scene_by_piece = {}
	SimPieceCatalog._loaded = false


static func _ensure_loaded() -> void:
	if SimPieceCatalog._loaded:
		return
	SimPieceCatalog._loaded = true
	var text: String = FileAccess.get_file_as_string(TOOLS_JSON)
	if text == "":
		push_error("SimPieceCatalog: cannot read %s — run the spec importer" % TOOLS_JSON)
		return
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("SimPieceCatalog: %s is not a JSON object" % TOOLS_JSON)
		return
	for key: String in (parsed as Dictionary):
		var entry: Variant = (parsed as Dictionary)[key]
		if not (entry is Dictionary):
			continue
		var record: Dictionary = entry
		if record.has("id") and record.has("scene"):
			SimPieceCatalog._scene_by_piece[str(record["id"])] = str(record["scene"])
