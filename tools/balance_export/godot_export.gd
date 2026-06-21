extends SceneTree

## Godot -> YAML balance exporter (Phase 2 of the dh-balance bridge).
##
## Reads tools/balance_export/manifest.json, instantiates each listed scene
## WITHOUT adding it to the tree (so _ready / _auto_initialize never fire), reads
## the resolved component stats (Defense, Weapon, Projectile, StatusEffect),
## normalizes them into the shared catalogs (weapons / projectiles /
## status_effects, deduped by id), and writes the YAML the dh_balance Python
## framework consumes. Costs and tech `requires` come from the manifest (they're
## not reliably on the scenes yet). Output goes to a separate data_exported/ dir
## so it can be diffed against the hand-authored data/ before promoting.
##
## Run:  godot --headless -s res://tools/balance_export/godot_export.gd

const MANIFEST_PATH := "res://tools/balance_export/manifest.json"

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

	# Factions first (this populates the shared catalogs as a side effect).
	for faction in manifest.get("factions", []):
		var doc: Dictionary = _build_faction(faction)
		var path: String = "%s/factions/%s.yaml" % [out_dir, faction["id"]]
		_write(path, _header("faction roster") + _yaml({
			"faction": faction["id"],
			"name": faction.get("name", faction["id"]),
			"description": faction.get("description", ""),
			"buildables": doc["buildables"],
		}, 0))

	# Then the catalogs they referenced.
	_write(out_dir + "/status_effects.yaml", _header("status effect catalog") + _yaml({"status_effects": _status_effects}, 0))
	_write(out_dir + "/projectiles.yaml", _header("projectile catalog") + _yaml({"projectiles": _projectiles}, 0))
	_write(out_dir + "/weapons.yaml", _header("weapon catalog") + _yaml({"weapons": _weapons}, 0))

	# Damage table straight from the game CSVs.
	var dmg: Dictionary = manifest.get("damage_csv", {})
	if dmg.has("armour"):
		_write(out_dir + "/damage_table.yaml", _header("damage table (from game CSVs)") + _yaml({
			"vs_armour": _load_csv_table(dmg["armour"]),
			"vs_attribute": _load_csv_table(dmg["attribute"]),
		}, 0))

	print("\nexport complete -> ", out_dir)
	print("  weapons=%d projectiles=%d status_effects=%d" % [
		_weapons.size(), _projectiles.size(), _status_effects.size()])
	for w in _warnings:
		print("  WARN: ", w)
	quit()


# --------------------------------------------------------------------------- #
# Extraction
# --------------------------------------------------------------------------- #
func _build_faction(faction: Dictionary) -> Dictionary:
	var buildables: Array = []
	for entry in faction.get("buildables", []):
		var b: Dictionary = _build_buildable(faction["id"], entry)
		if not b.is_empty():
			buildables.append(b)
	return {"buildables": buildables}


func _build_buildable(faction_id: String, entry: Dictionary) -> Dictionary:
	var scene_path: String = entry["scene"]
	var packed: PackedScene = load(scene_path)
	if packed == null:
		_warnings.append("could not load scene %s (skipped)" % scene_path)
		return {}
	var inst: Node = packed.instantiate()
	if inst == null:
		_warnings.append("could not instantiate %s (skipped)" % scene_path)
		return {}

	var bid: String = entry["id"]
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
	return "UNARMORED"


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
# CSV -> damage table
# --------------------------------------------------------------------------- #
func _load_csv_table(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		_warnings.append("could not read CSV %s" % path)
		return {}
	var header: PackedStringArray = f.get_csv_line()
	var cols: Array = []
	for i in range(1, header.size()):
		cols.append(header[i].strip_edges())
	var table: Dictionary = {}
	while not f.eof_reached():
		var row: PackedStringArray = f.get_csv_line()
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
