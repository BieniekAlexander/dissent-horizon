class_name SpecRegistry
extends RefCounted

## Scans gdd/**/*.md for spec docs and validates every cross-reference BEFORE
## anything is written. Validation failures are loud and total: callers must
## abort the import when `errors` is non-empty.
##
## DISCOVERY IS BY THE `id` FRONTMATTER KEY: a markdown file is an importable
## spec if and only if its frontmatter contains an `id` key. Nothing else — not
## the folder, not the filename — decides spec-hood, so specs can live anywhere
## under gdd/ and be moved freely. `kind` is then required *content* of a
## discovered spec (it selects how the spec is processed).
##
## No fuzzy matching anywhere: ids resolve exactly or fail (per project policy —
## the user reconciles duplicates/renames by hand).

const SpecFrontmatter := preload("res://tools/spec_import/frontmatter.gd")

const KINDS: Array = ["unit", "structure", "projectile", "status_effect", "faction"]

## All specs by id (single shared namespace across kinds, so a projectile can
## never shadow a unit id). Each spec is the frontmatter Dictionary plus:
##   "_doc_path": res:// path of the markdown doc
##   "_kind": its kind (echo of data.kind for convenience)
var specs: Dictionary = {}
## id -> spec, restricted per kind for iteration convenience.
var pieces: Dictionary = {}          # unit + structure
var projectiles: Dictionary = {}
var status_effects: Dictionary = {}
var factions: Dictionary = {}

var errors: Array = []
var warnings: Array = []


## Scans a gdd root and builds+validates the registry. Returns self.
func scan(a_root: String = "res://gdd") -> RefCounted:
	var docs: Array = []
	var paths: Array = []
	_collect_markdown(a_root, paths)
	paths.sort()
	for path in paths:
		var result: Dictionary = SpecFrontmatter.parse_file(path)
		if not result["ok"]:
			# A malformed doc is only a hard error when it was TRYING to be a spec
			# (its frontmatter names an id); otherwise it's just prose we skip, so
			# unrelated design notes with quirky frontmatter never break the import.
			if _raw_frontmatter_has_id(path):
				errors.append("%s: %s" % [path, result["error"]])
			continue
		if not result["data"].has("id"):
			continue   # not a spec (discovery is by the `id` key)
		docs.append({"path": path, "data": result["data"]})
	build(docs)
	return self


## Builds and validates from in-memory docs ({"path", "data"}) — the scan()
## backend, exposed for tests.
func build(a_docs: Array) -> void:
	for doc in a_docs:
		_register(doc["path"], doc["data"])
	for id in specs:
		_validate(specs[id])
	errors.sort()


# --------------------------------------------------------------------------- #
# Registration
# --------------------------------------------------------------------------- #
func _register(a_path: String, a_data: Dictionary) -> void:
	# Discovery guaranteed `id` is present; `kind` is required content that
	# selects how the spec is processed.
	var id: String = str(a_data.get("id", ""))
	if not _valid_id(id):
		errors.append("%s: invalid id '%s' (must be snake_case: [a-z0-9_]+)" % [a_path, id])
		return
	if not a_data.has("kind"):
		errors.append("%s [%s]: spec has an id but no kind (expected one of %s)" % [a_path, id, KINDS])
		return
	var kind: String = str(a_data["kind"])
	if kind not in KINDS:
		errors.append("%s [%s]: unknown kind '%s' (expected one of %s)" % [a_path, id, kind, KINDS])
		return
	if specs.has(id):
		errors.append("%s: duplicate id '%s' (also defined in %s)" % [a_path, id, specs[id]["_doc_path"]])
		return
	var spec: Dictionary = a_data.duplicate(true)
	spec["id"] = id
	spec["_doc_path"] = a_path
	spec["_kind"] = kind
	specs[id] = spec
	match kind:
		"unit", "structure":
			pieces[id] = spec
			if spec.get("weapons") is Array:
				_hoist_inline_projectiles(spec)
		"projectile":
			projectiles[id] = spec
		"status_effect":
			status_effects[id] = spec
		"faction":
			factions[id] = spec


## Replaces any inline `projectile: {...}` dict in a piece's weapons list with
## the resolved string id of a hoisted registry entry, so every later consumer
## (validation, scene sync) only ever sees a normal string id — same as a
## cross-doc reference.
func _hoist_inline_projectiles(a_spec: Dictionary) -> void:
	var weapons: Array = a_spec["weapons"]
	for i in weapons.size():
		var w: Variant = weapons[i]
		if not (w is Dictionary) or not (w.get("projectile") is Dictionary):
			continue
		var proj: Dictionary = w["projectile"]
		var wname: String = str(w.get("name", ""))
		var suffix: String = wname.to_snake_case() if wname != "" else str(i)
		var pid: String = str(proj["id"]) if proj.has("id") else "%s__%s" % [a_spec["id"], suffix]
		_register_inline_projectile(a_spec["_doc_path"], pid, proj)
		w["projectile"] = pid


## Registers a hoisted inline projectile exactly like a standalone spec doc
## (deep-duplicated, tagged with id/_doc_path/_kind) so it validates through
## the normal `_validate_projectile` pass and resolves normal cross-references.
## `_doc_path` is the OWNING unit/structure doc, for error messages — it has no
## markdown doc of its own. `_inline` marks it for scene-skeleton auto-creation
## (see SpecSceneSync._ensure_inline_projectile_scene).
func _register_inline_projectile(a_doc_path: String, a_id: String, a_data: Dictionary) -> void:
	if not _valid_id(a_id):
		errors.append("%s: invalid inline projectile id '%s' (must be snake_case: [a-z0-9_]+)" % [a_doc_path, a_id])
		return
	if specs.has(a_id):
		errors.append("%s: duplicate id '%s' (also defined in %s)" % [a_doc_path, a_id, specs[a_id]["_doc_path"]])
		return
	var spec: Dictionary = a_data.duplicate(true)
	spec["id"] = a_id
	spec["_doc_path"] = a_doc_path
	spec["_kind"] = "projectile"
	spec["_inline"] = true
	specs[a_id] = spec
	projectiles[a_id] = spec


static func _valid_id(a_id: String) -> bool:
	if a_id.is_empty():
		return false
	for i in a_id.length():
		var c: String = a_id[i]
		if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_"):
			return false
	return true


# --------------------------------------------------------------------------- #
# Validation
# --------------------------------------------------------------------------- #
func _validate(a_spec: Dictionary) -> void:
	var kind: String = a_spec["_kind"]
	if a_spec.has("scene"):
		var scene: String = str(a_spec["scene"])
		if not scene.begins_with("res://") or scene.get_extension() != "tscn":
			_err(a_spec, "scene must be a res://...tscn path, got '%s'" % scene)
		elif not FileAccess.file_exists(scene):
			_err(a_spec, "scene does not exist: %s" % scene)
	elif kind == "status_effect" or kind == "faction":
		_err(a_spec, "%s docs must have a scene: field" % kind)

	match kind:
		"unit", "structure":
			_validate_piece(a_spec)
		"projectile":
			_validate_projectile(a_spec)
		"faction":
			_validate_faction(a_spec)


func _validate_piece(a_spec: Dictionary) -> void:
	_check_enum(a_spec, "armour", Defense.ArmourType)
	_check_enum(a_spec, "frame", Defense.FrameType)
	if a_spec.has("movement") and a_spec["movement"] is Dictionary and a_spec["movement"].has("mode"):
		if not Movement.Mode.has(str(a_spec["movement"]["mode"])):
			_err(a_spec, "movement.mode '%s' is not a Movement.Mode" % a_spec["movement"]["mode"])
	for key in ["requires", "trains", "builds"]:
		if not a_spec.has(key):
			continue
		if not (a_spec[key] is Array):
			_err(a_spec, "%s must be a list" % key)
			continue
		for ref in a_spec[key]:
			var rid: String = str(ref)
			if not pieces.has(rid):
				_err(a_spec, "%s references unknown piece '%s'" % [key, rid])
			elif key == "requires" and pieces[rid]["_kind"] != "structure":
				_err(a_spec, "requires must name structures; '%s' is a %s" % [rid, pieces[rid]["_kind"]])
	if a_spec.has("footprint"):
		var fp: Variant = a_spec["footprint"]
		if not (fp is Array and fp.size() == 2 and fp[0] is int and fp[1] is int):
			_err(a_spec, "footprint must be [width, length] ints")
	if a_spec.has("weapons"):
		if not (a_spec["weapons"] is Array):
			_err(a_spec, "weapons must be a list")
		else:
			var seen_names: Dictionary = {}
			for w in a_spec["weapons"]:
				if not (w is Dictionary):
					_err(a_spec, "each weapons entry must be a mapping")
					continue
				_validate_weapon(a_spec, w, seen_names)
	if a_spec.has("ui") and a_spec["ui"] is Dictionary and a_spec["ui"].has("grid"):
		var g: Variant = a_spec["ui"]["grid"]
		if not (g is Array and g.size() == 2 and g[0] is int and g[1] is int):
			_err(a_spec, "ui.grid must be [column, row] ints")


func _validate_weapon(a_spec: Dictionary, a_weapon: Dictionary, a_seen: Dictionary) -> void:
	var wname: String = str(a_weapon.get("name", ""))
	if wname == "":
		_err(a_spec, "every weapon needs a name (it is the sync key)")
	elif a_seen.has(wname):
		_err(a_spec, "duplicate weapon name '%s'" % wname)
	a_seen[wname] = true
	if a_weapon.has("projectile"):
		var pid: String = str(a_weapon["projectile"])
		if not projectiles.has(pid):
			_err(a_spec, "weapon '%s' references unknown projectile '%s'" % [wname, pid])
	elif not a_weapon.has("melee_damage"):
		_err(a_spec, "weapon '%s' needs either projectile: or melee_damage:" % wname)
	if a_weapon.has("melee_damage_type") and not Damage.Type.has(str(a_weapon["melee_damage_type"])):
		_err(a_spec, "weapon '%s' melee_damage_type '%s' is not a Damage.Type" % [wname, a_weapon["melee_damage_type"]])
	if a_weapon.has("hits"):
		for h in a_weapon["hits"]:
			if str(h) not in ["ground", "air"]:
				_err(a_spec, "weapon '%s' hits entries must be ground/air, got '%s'" % [wname, h])
	if a_weapon.has("reach") and a_weapon["reach"] is Dictionary:
		for k in a_weapon["reach"]:
			if str(k) not in ["ground", "air"]:
				_err(a_spec, "weapon '%s' reach keys must be ground/air, got '%s'" % [wname, k])


func _validate_projectile(a_spec: Dictionary) -> void:
	_check_enum(a_spec, "damage_type", Damage.Type)
	_check_enum(a_spec, "trajectory", Projectile.Trajectory)
	if a_spec.has("status_effects"):
		for ref in a_spec["status_effects"]:
			if not status_effects.has(str(ref)):
				_err(a_spec, "status_effects references unknown status effect '%s'" % ref)


func _validate_faction(a_spec: Dictionary) -> void:
	if not a_spec.has("starts_with") or not (a_spec["starts_with"] is Array):
		_err(a_spec, "faction needs a starts_with: list")
		return
	var structure_count: int = 0
	for ref in a_spec["starts_with"]:
		var rid: String = str(ref)
		if not pieces.has(rid):
			_err(a_spec, "starts_with references unknown piece '%s'" % rid)
		elif pieces[rid]["_kind"] == "structure":
			structure_count += 1
	if structure_count != 1:
		_err(a_spec, "starts_with must contain exactly 1 structure (the HQ), found %d" % structure_count)
	if a_spec.has("ordnances"):
		if not (a_spec["ordnances"] is Array):
			_err(a_spec, "ordnances must be a list of identifiers")
		else:
			for o in a_spec["ordnances"]:
				if not _valid_id(str(o)):
					_err(a_spec, "ordnance id '%s' must be snake_case" % o)


func _check_enum(a_spec: Dictionary, a_key: String, a_enum: Dictionary) -> void:
	if a_spec.has(a_key) and not a_enum.has(str(a_spec[a_key])):
		_err(a_spec, "%s '%s' is not one of %s" % [a_key, a_spec[a_key], a_enum.keys()])


func _err(a_spec: Dictionary, a_message: String) -> void:
	errors.append("%s [%s]: %s" % [a_spec["_doc_path"], a_spec["id"], a_message])


# --------------------------------------------------------------------------- #
# Discovery
# --------------------------------------------------------------------------- #
## True if the file's leading frontmatter block contains an `id:` line — a cheap
## raw scan used only to decide whether an UNPARSEABLE doc was meant to be a spec.
func _raw_frontmatter_has_id(a_path: String) -> bool:
	var f: FileAccess = FileAccess.open(a_path, FileAccess.READ)
	if f == null:
		return false
	var in_fence: bool = false
	while not f.eof_reached():
		var line: String = f.get_line()
		var stripped: String = line.strip_edges()
		if not in_fence:
			if stripped == "---":
				in_fence = true
				continue
			break   # no opening fence -> no frontmatter
		if stripped == "---" or stripped == "...":
			break
		if stripped.begins_with("id:"):
			f.close()
			return true
	f.close()
	return false


func _collect_markdown(a_dir: String, a_out: Array) -> void:
	var da: DirAccess = DirAccess.open(a_dir)
	if da == null:
		return
	da.list_dir_begin()
	var fn: String = da.get_next()
	while fn != "":
		var full: String = a_dir.path_join(fn)
		if da.current_is_dir():
			if not fn.begins_with("."):
				_collect_markdown(full, a_out)
		elif fn.get_extension() == "md":
			a_out.append(full)
		fn = da.get_next()
	da.list_dir_end()
