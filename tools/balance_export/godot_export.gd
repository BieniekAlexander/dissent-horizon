extends SceneTree

## Godot -> YAML balance exporter (Phase 2 of the dh-balance bridge).
##
## DISCOVERY-DRIVEN: walks the unit/structure scene dirs, and for every scene in
## the "unit"/"structure" groups instantiates it WITHOUT adding it to the tree
## (so _ready / _auto_initialize never fire), reads the resolved component stats
## (Defense, Weapon, Projectile, StatusEffect), and normalizes them into the
## shared catalogs (weapons / projectiles / status_effects, deduped by id).
##
## The manifest is now a METADATA OVERLAY, not an allowlist: it supplies the
## fields that aren't reliably on the scenes (cost, tech `requires`, faction
## grouping), matched to a discovered scene by its res:// path. A scene with no
## manifest entry is STILL exported -- with placeholder cost/requires, grouped
## under the "unassigned" faction, and a loud WARN -- so a brand-new unit can
## never be silently forgotten. Output goes to a separate data_exported/ dir so
## it can be diffed against the hand-authored data/ before promoting.
##
## Run:  godot --headless -s res://tools/balance_export/godot_export.gd

const MANIFEST_PATH := "res://tools/balance_export/manifest.json"

## Dirs scanned for buildable scenes when the manifest omits "scan_dirs".
const DEFAULT_SCAN_DIRS: Array = ["res://scenes/entities/units", "res://scenes/entities/structures"]

## Faction bucket for discovered scenes with no manifest entry.
const UNASSIGNED_FACTION := "unassigned"

var _weapons: Dictionary = {}          # id -> weapon dict
var _projectiles: Dictionary = {}      # id -> projectile dict
var _status_effects: Dictionary = {}   # id -> status effect dict
var _warnings: Array = []


func _initialize() -> void:
	var manifest: Dictionary = _load_json(MANIFEST_PATH)
	if manifest.is_empty():
		push_error("export: could not read manifest at %s" % MANIFEST_PATH)
		quit(1)
		return

	var out_dir: String = manifest.get("output_dir", "res://tools/balance/data_exported")
	DirAccess.make_dir_recursive_absolute(out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir + "/factions")

	# Metadata overlay (scene_path -> {faction, entry}) + faction display info.
	var overlay: Dictionary = _build_overlay(manifest)
	var faction_meta: Dictionary = _faction_meta(manifest)

	# Discover buildable scenes on disk, then group by faction. Stats come from
	# the scene; cost/requires/faction come from the matching overlay entry (or
	# placeholders + a warning when there is none). Populates the shared catalogs
	# as a side effect.
	var scan_dirs: Array = manifest.get("scan_dirs", DEFAULT_SCAN_DIRS)
	var scenes: Array = _discover_scenes(scan_dirs)

	var by_faction: Dictionary = {}   # faction_id -> Array[buildable dict]
	for scene_path in scenes:
		var ov: Dictionary = overlay.get(scene_path, {})
		var entry: Dictionary = ov.get("entry", {})
		var b: Dictionary = _build_buildable(scene_path, entry)
		if b.is_empty():
			continue   # not a unit/structure, or failed to load (already warned)
		var faction_id: String = ov.get("faction", UNASSIGNED_FACTION)
		if not ov.has("entry"):
			_warnings.append(
				"%s auto-included (no manifest entry) -> placeholder cost/requires, faction=%s"
				% [scene_path, UNASSIGNED_FACTION])
		if not by_faction.has(faction_id):
			by_faction[faction_id] = []
		by_faction[faction_id].append(b)

	# Flag manifest entries whose scene was never discovered (renamed/deleted/skipped).
	for scene_path in overlay:
		if scene_path not in scenes:
			_warnings.append("manifest entry references %s but it was not discovered (renamed/deleted/skipped?)" % scene_path)

	# Write one roster file per faction. Manifest order first, then any extras
	# (e.g. "unassigned") appended deterministically.
	var faction_order: Array = []
	for faction in manifest.get("factions", []):
		faction_order.append(faction["id"])
	for faction_id in by_faction:
		if faction_id not in faction_order:
			faction_order.append(faction_id)

	for faction_id in faction_order:
		if not by_faction.has(faction_id):
			continue
		var meta: Dictionary = faction_meta.get(faction_id, {
			"name": String(faction_id).capitalize(),
			"description": "Auto-grouped; assign these to a real faction in manifest.json.",
		})
		var path: String = "%s/factions/%s.yaml" % [out_dir, faction_id]
		_write(path, _header("faction roster") + _yaml({
			"faction": faction_id,
			"name": meta["name"],
			"description": meta["description"],
			"buildables": by_faction[faction_id],
		}, 0))

	# Then the catalogs they referenced.
	_write(out_dir + "/status_effects.yaml", _header("status effect catalog") + _yaml({"status_effects": _status_effects}, 0))
	_write(out_dir + "/projectiles.yaml", _header("projectile catalog") + _yaml({"projectiles": _projectiles}, 0))
	_write(out_dir + "/weapons.yaml", _header("weapon catalog") + _yaml({"weapons": _weapons}, 0))

	# Damage table straight from the game TSVs.
	var dmg: Dictionary = manifest.get("damage_csv", {})
	if dmg.has("armour"):
		var tables: Dictionary = {
			"vs_armour": _load_csv_table(dmg["armour"]),
			"vs_attribute": _load_csv_table(dmg["attribute"]),
		}
		if dmg.has("frame"):
			tables["vs_frame"] = _load_csv_table(dmg["frame"])
		_write(out_dir + "/damage_table.yaml", _header("damage table (from game TSVs)") + _yaml(tables, 0))

	print("\nexport complete -> ", out_dir)
	print("  weapons=%d projectiles=%d status_effects=%d" % [
		_weapons.size(), _projectiles.size(), _status_effects.size()])
	for w in _warnings:
		print("  WARN: ", w)
	quit()


# --------------------------------------------------------------------------- #
# Extraction
# --------------------------------------------------------------------------- #
## scene_path -> {"faction": String, "entry": Dictionary} for every manifest
## buildable, so a discovered scene can pull its cost/requires/faction by path.
func _build_overlay(manifest: Dictionary) -> Dictionary:
	var overlay: Dictionary = {}
	for faction in manifest.get("factions", []):
		for entry in faction.get("buildables", []):
			if not entry.has("scene"):
				continue
			if overlay.has(entry["scene"]):
				_warnings.append("manifest lists %s more than once; using the last entry" % entry["scene"])
			overlay[entry["scene"]] = {"faction": faction["id"], "entry": entry}
	return overlay


## faction_id -> {"name", "description"} from the manifest factions.
func _faction_meta(manifest: Dictionary) -> Dictionary:
	var meta: Dictionary = {}
	for faction in manifest.get("factions", []):
		meta[faction["id"]] = {
			"name": faction.get("name", faction["id"]),
			"description": faction.get("description", ""),
		}
	return meta


## All res:// .tscn paths under dirs. Whether each is a real buildable (vs. an
## ABSTRACT inheritance scaffold or a non-unit/structure node) is decided later
## in _build_buildable, which needs an instance to read the root's type/groups.
func _discover_scenes(dirs: Array) -> Array:
	var found: Array = []
	for dir_path in dirs:
		_discover_scenes_in(dir_path, found)
	found.sort()
	return found


## Recurse into faction subfolders (an/, cl/, ...) under each scan dir.
func _discover_scenes_in(dir_path: String, found: Array) -> void:
	var da: DirAccess = DirAccess.open(dir_path)
	if da == null:
		_warnings.append("scan dir not found: %s" % dir_path)
		return
	da.list_dir_begin()
	var fn: String = da.get_next()
	while fn != "":
		var full: String = dir_path.path_join(fn)
		if da.current_is_dir():
			if not fn.begins_with("."):
				_discover_scenes_in(full, found)
		elif fn.get_extension() == "tscn":
			found.append(full)
		fn = da.get_next()
	da.list_dir_end()


func _build_buildable(scene_path: String, entry: Dictionary) -> Dictionary:
	var packed: PackedScene = load(scene_path)
	if packed == null:
		_warnings.append("could not load scene %s (skipped)" % scene_path)
		return {}
	var inst: Node = packed.instantiate()
	if inst == null:
		_warnings.append("could not instantiate %s (skipped)" % scene_path)
		return {}

	# Ignore inheritance-only scaffolds (base scenes Godot uses for inheritance,
	# not real game entities) -- flagged by the root's type. Silent, not an error.
	if inst is Entity and inst.type == Entity.Type.ABSTRACT:
		inst.free()
		return {}

	# Belt-and-suspenders: only unit/structure-group roots are buildables.
	if not (inst.is_in_group("unit") or inst.is_in_group("structure")):
		inst.free()
		return {}

	var bid: String = entry.get("id", scene_path.get_file().get_basename())
	var is_structure: bool = inst.is_in_group("structure")

	# Ordered for readable output.
	var b: Dictionary = {
		"id": bid,
		"kind": "structure" if is_structure else "unit",
		"name": String(inst.name),
		"cost": entry.get("cost", {"ore": 0}),
		"requires": entry.get("requires", []),
	}

	var defense: Node = inst.get_node_or_null("Defense")
	if defense != null:
		b["armour"] = _armour_name(defense.armour_type)
		b["frame"] = _frame_name(defense.frame_type)
		b["hp"] = defense.hp_max

	var movement: Node = inst.get_node_or_null("Movement")
	if movement != null:
		b["movement"] = {"layer": _layer_name(movement.mode), "speed": movement.speed}

	var attributes: Array = []
	if inst.get_node_or_null("Stealth") != null:
		attributes.append("HAS_STEALTH")
	b["attributes"] = attributes

	var weapon_ids: Array = []
	var loadout: Node = inst.get_node_or_null("Loadout")
	if loadout != null:
		for w in loadout.get_children():
			if w is Weapon:
				weapon_ids.append(_extract_weapon(bid, w))
	b["weapons"] = weapon_ids

	inst.free()
	return b


func _extract_weapon(bid: String, w: Node) -> String:
	var wid: String = "%s_%s" % [bid, _weapon_suffix(w.name)]
	var d: Dictionary = {"name": String(w.name)}
	if w.projectile_scene != null:
		d["projectile"] = _extract_projectile(w.projectile_scene)
	else:
		d["melee_damage"] = w.melee_damage
		d["melee_damage_type"] = _dtype_name(w.melee_damage_type)
	d["split_time"] = w.split_time
	d["reload_time"] = w.reload_time
	d["clip_size"] = w.clip_size
	var ar: Node = w.get_node_or_null("AttackRange")
	d["reach"] = ar.shape.radius if (ar != null and ar.shape != null and "radius" in ar.shape) else 0.0
	d["hits"] = _hits(w.target_mask)
	_weapons[wid] = d
	return wid


func _extract_projectile(packed: PackedScene) -> String:
	var pid: String = packed.resource_path.get_file().get_basename()
	if _projectiles.has(pid):
		return pid   # shared projectile already captured
	var p: Node = packed.instantiate()
	var d: Dictionary = {
		"base_damage": p.base_damage,
		"damage_type": _dtype_name(p.damage_type),
		"speed": p.get("speed"),
	}
	var effect_ids: Array = []
	var idx: int = 0
	for child in p.get_children():
		if child is EffectApplicator:
			for se in child.get_children():
				if se is DamageOverTimeStatusEffect:
					effect_ids.append(_extract_dot(pid, idx, se))
					idx += 1
	d["status_effects"] = effect_ids
	p.free()
	_projectiles[pid] = d
	return pid


func _extract_dot(pid: String, idx: int, se: Node) -> String:
	var sid: String = pid + ("_dot" if idx == 0 else "_dot%d" % idx)
	_status_effects[sid] = {
		"kind": "damage_over_time",
		"damage_per_tick": se.damage_per_tick,
		"tick_rate": se.tick_rate,
		"duration_ticks": se.duration_ticks,
		"damage_type": _dtype_name(se.damage_type),
	}
	return sid


# --------------------------------------------------------------------------- #
# Enum / mask mapping
# --------------------------------------------------------------------------- #
func _dtype_name(v: int) -> String:
	for k in Damage.Type:
		if Damage.Type[k] == v:
			return k
	return "LEAD"


func _armour_name(v: int) -> String:
	for k in Defense.ArmourType:
		if Defense.ArmourType[k] == v:
			return k
	return "LIGHT"


func _frame_name(v: int) -> String:
	for k in Defense.FrameType:
		if Defense.FrameType[k] == v:
			return k
	return "BIOLOGICAL"


func _layer_name(mode: int) -> String:
	if mode == Movement.Mode.HOVERING or mode == Movement.Mode.FLYING:
		return "air"
	return "ground"


func _hits(mask: int) -> Array:
	var out: Array = []
	if mask & CollisionLayers.Mask.TARGETABLE_GROUND:
		out.append("ground")
	if mask & CollisionLayers.Mask.TARGETABLE_AIR:
		out.append("air")
	if out.is_empty():
		out.append("ground")
	return out


func _weapon_suffix(node_name: String) -> String:
	var s: String = node_name.to_lower()
	if s.length() > 6 and s.ends_with("weapon"):
		s = s.substr(0, s.length() - 6)
	return s if s != "" else "weapon"


# --------------------------------------------------------------------------- #
# TSV -> damage table
# --------------------------------------------------------------------------- #
func _load_csv_table(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		_warnings.append("could not read TSV %s" % path)
		return {}
	var header: PackedStringArray = f.get_csv_line("\t")
	var cols: Array = []
	for i in range(1, header.size()):
		cols.append(header[i].strip_edges())
	var table: Dictionary = {}
	while not f.eof_reached():
		var row: PackedStringArray = f.get_csv_line("\t")
		if row.size() < 2:
			continue
		var rname: String = row[0].strip_edges()
		if rname == "":
			continue
		var d: Dictionary = {}
		for i in range(1, row.size()):
			var cell: String = row[i].strip_edges()
			if cell != "":
				d[cols[i - 1]] = float(cell)
		table[rname] = d
	f.close()
	return table


# --------------------------------------------------------------------------- #
# YAML emitter (tailored to this schema: maps, lists, scalars)
# --------------------------------------------------------------------------- #
func _yaml(value: Variant, indent: int) -> String:
	var pad: String = "  ".repeat(indent)
	var out: String = ""
	if value is Dictionary:
		for k in value:
			var v: Variant = value[k]
			if (v is Dictionary and not v.is_empty()) or (v is Array and not v.is_empty()):
				out += pad + str(k) + ":\n" + _yaml(v, indent + 1)
			elif v is Dictionary:
				out += pad + str(k) + ": {}\n"
			elif v is Array:
				out += pad + str(k) + ": []\n"
			else:
				out += pad + str(k) + ": " + _scalar(v) + "\n"
	elif value is Array:
		for item in value:
			if item is Dictionary or item is Array:
				out += pad + "-\n" + _yaml(item, indent + 1)
			else:
				out += pad + "- " + _scalar(item) + "\n"
	return out


func _scalar(v: Variant) -> String:
	if v is bool:
		return "true" if v else "false"
	if v is int:
		return str(v)
	if v is float:
		return _fmt_float(v)
	if v is String or v is StringName:
		return "\"%s\"" % String(v).replace("\\", "\\\\").replace("\"", "\\\"")
	return str(v)


func _fmt_float(v: float) -> String:
	var s: String = "%.4f" % v
	if s.contains("."):
		s = s.rstrip("0").rstrip(".")
	if s == "" or s == "-":
		s = "0"
	return s


# --------------------------------------------------------------------------- #
# IO
# --------------------------------------------------------------------------- #
func _header(what: String) -> String:
	return "# AUTO-GENERATED by tools/balance_export/godot_export.gd (%s).\n# Do not edit by hand; edit the scenes or manifest.json and re-run.\n" % what


func _load_json(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


func _write(path: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("export: cannot write %s" % path)
		return
	f.store_string(text)
	f.close()
