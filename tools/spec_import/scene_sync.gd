class_name SpecSceneSync
extends RefCounted

## The write half of the spec importer: applies validated gdd specs to .tscn
## files through TscnDoc text edits.
##
## Change detection is SEMANTIC, not textual: each scene is instantiated
## read-only (resolving inherited defaults), spec values are compared against
## the live component values, and only differing keys produce text edits — so
## re-running the importer over unchanged docs is a byte-level no-op.
##
## Modes (collection-valued keys only — weapons, status_effects, trains, builds,
## starts_with, ordnances; scalars always overwrite when present):
##   full        — the spec list is authoritative; scene-only items are removed
##   incremental — update/create only; scene-only items are preserved
##
## Docs without a scene: get a skeleton scene created (inheriting unit.tscn /
## abstract_structure.tscn) and the new path written back into the doc. Inline
## projectiles (hoisted from a weapon's `projectile: {...}` dict) get the same
## treatment, inheriting projectile.tscn — but since they have no markdown doc
## of their own, the resolved path is written back only into the in-memory
## spec, not to any frontmatter file.

const TscnDoc := preload("res://tools/spec_import/tscn_doc.gd")

const UNIT_BASE: String = "res://scenes/entities/units/unit.tscn"
const STRUCTURE_BASE: String = "res://scenes/entities/structures/abstract_structure.tscn"
const PROJECTILE_BASE: String = "res://scenes/entities/projectiles/projectile.tscn"

const SCRIPT_LOADOUT: String = "res://scripts/entities/components/loadout.gd"
const SCRIPT_WEAPON: String = "res://scripts/entities/tools/weapon.gd"
const SCRIPT_PRODUCTION: String = "res://scripts/entities/components/production.gd"
const SCRIPT_BUILDS: String = "res://scripts/entities/components/builds.gd"
const SCRIPT_EFFECT_APPLICATOR: String = "res://scripts/entities/effects/effect_applicator.gd"

## gdd faction dir (generic ideology) -> scene faction subdir, for placing
## skeleton scenes.
const DOC_DIR_TO_SCENE_SUB: Dictionary = {"anarchical": "an", "colonial": "cl"}

var registry: RefCounted
var mode: String
var report: Dictionary = {"changed": [], "created": [], "warnings": [], "errors": []}


static func sync_all(a_registry: RefCounted, a_mode: String) -> Dictionary:
	var sync: RefCounted = new()
	sync.registry = a_registry
	sync.mode = a_mode
	sync._run()
	return sync.report


func _run() -> void:
	# Skeletons first so every piece (and every inline projectile) has a scene
	# before syncing.
	for id in registry.pieces:
		_ensure_scene(registry.pieces[id])
	for id in registry.projectiles:
		_ensure_inline_projectile_scene(registry.projectiles[id])
	if not report["errors"].is_empty():
		return
	for id in registry.pieces:
		_sync_piece(registry.pieces[id])
	for id in registry.projectiles:
		_sync_projectile(registry.projectiles[id])
	for id in registry.factions:
		_sync_faction(registry.factions[id])


# --------------------------------------------------------------------------- #
# Shared sync context
# --------------------------------------------------------------------------- #
## One scene being edited: the TscnDoc (text), the live instance (semantic
## values), and a dirty flag. Saved only when something actually changed.
class Ctx:
	var doc: RefCounted
	var inst: Node
	var path: String
	var dirty: bool = false
	## node paths created this run (they have no live counterpart in `inst`).
	var created_nodes: Dictionary = {}


func _open(a_path: String) -> Ctx:
	var packed: PackedScene = load(a_path)
	var doc: RefCounted = TscnDoc.load_file(a_path)
	if packed == null or doc == null:
		report["errors"].append("cannot open scene %s" % a_path)
		return null
	var ctx: Ctx = Ctx.new()
	ctx.doc = doc
	ctx.inst = packed.instantiate()
	ctx.path = a_path
	return ctx


func _close(a_ctx: Ctx) -> void:
	if a_ctx == null:
		return
	if a_ctx.dirty:
		if a_ctx.doc.save_file(a_ctx.path):
			report["changed"].append(a_ctx.path)
		else:
			report["errors"].append("cannot write %s" % a_ctx.path)
	a_ctx.inst.free()


## The section for a node path, creating an inherited-override section (with
## parent= and index= from the live instance) when the file has none yet.
func _section_for(a_ctx: Ctx, a_node_path: String) -> Dictionary:
	var section: Dictionary = a_ctx.doc.find_node(a_node_path)
	if not section.is_empty():
		return section
	var node: Node = a_ctx.inst.get_node_or_null(a_node_path) if a_node_path != "" else a_ctx.inst
	if node == null:
		return {}
	var parent_attr: String = "." if not a_node_path.contains("/") \
		else a_node_path.substr(0, a_node_path.rfind("/"))
	a_ctx.dirty = true
	return a_ctx.doc.add_node([
		["name", node.name], ["parent", parent_attr], ["index", str(node.get_index())],
	], {})


## Sets a property when the live value differs from the target. `a_raw` is the
## .tscn literal to write. Nodes created this run always take the write.
func _set_prop(a_ctx: Ctx, a_node_path: String, a_prop: String, a_current: Variant, a_target: Variant, a_raw: String) -> void:
	if not a_ctx.created_nodes.has(a_node_path) and _values_equal(a_current, a_target):
		return
	var section: Dictionary = _section_for(a_ctx, a_node_path)
	if section.is_empty():
		report["warnings"].append("%s: node %s not found; cannot set %s" % [a_ctx.path, a_node_path, a_prop])
		return
	if a_ctx.doc.get_prop(section, a_prop) == a_raw:
		return
	a_ctx.doc.set_prop(section, a_prop, a_raw)
	a_ctx.dirty = true


static func _values_equal(a: Variant, b: Variant) -> bool:
	if a is float or b is float:
		return is_equal_approx(float(a), float(b))
	return a == b


## Copies the optional `editor_description` spec key into the scene ROOT node's
## Godot-native `editor_description` property (the in-editor tooltip). Any scene
## whose root is a Node has this property, so it applies uniformly to units,
## structures, projectiles, and factions. Omitted key -> untouched.
func _sync_editor_description(a_ctx: Ctx, a_spec: Dictionary) -> void:
	if not a_spec.has("editor_description"):
		return
	var target: String = str(a_spec["editor_description"])
	var current: String = String(a_ctx.inst.editor_description) if "editor_description" in a_ctx.inst else ""
	_set_prop(a_ctx, "", "editor_description", current, target, TscnDoc.fmt_string(target))


## uid for a res:// path: sibling .uid file for scripts, header uid for scenes.
static func _uid_for(a_path: String) -> String:
	if a_path.get_extension() == "gd" and FileAccess.file_exists(a_path + ".uid"):
		return FileAccess.get_file_as_string(a_path + ".uid").strip_edges()
	if a_path.get_extension() == "tscn":
		var f: FileAccess = FileAccess.open(a_path, FileAccess.READ)
		if f != null:
			var header: String = f.get_line()
			f.close()
			var regex: RegEx = RegEx.new()
			regex.compile("uid=\"([^\"]+)\"")
			var m: RegExMatch = regex.search(header)
			if m != null:
				return m.get_string(1)
	return ""


func _ensure_ext(a_ctx: Ctx, a_type: String, a_path: String) -> String:
	var before: int = a_ctx.doc.sections_of("ext_resource").size()
	var id: String = a_ctx.doc.ensure_ext_resource(a_type, a_path, _uid_for(a_path))
	if a_ctx.doc.sections_of("ext_resource").size() != before:
		a_ctx.dirty = true
	return id


## Ensures a component child node exists at root level; creates the node section
## (script ext_resource included) when the live instance lacks it.
func _ensure_component(a_ctx: Ctx, a_name: String, a_type: String, a_script_path: String) -> void:
	if a_ctx.inst.get_node_or_null(a_name) != null or a_ctx.created_nodes.has(a_name):
		return
	var script_id: String = _ensure_ext(a_ctx, "Script", a_script_path)
	a_ctx.doc.add_node(
		[["name", a_name], ["type", a_type], ["parent", "."]],
		{"script": "ExtResource(\"%s\")" % script_id}
	)
	a_ctx.created_nodes[a_name] = true
	a_ctx.dirty = true


## Sets the radius of a CollisionShape3D node's cylinder shape, creating the
## sub_resource (and the node's shape override) as needed. Shapes shared by
## several nodes are never edited in place — the node gets its own shape.
func _set_shape_radius(a_ctx: Ctx, a_node_path: String, a_radius: float) -> void:
	var node: Node = a_ctx.inst.get_node_or_null(a_node_path)
	if node is CollisionShape3D and node.shape != null and "radius" in node.shape \
			and is_equal_approx(node.shape.radius, a_radius) \
			and not a_ctx.created_nodes.has(a_node_path):
		return
	var section: Dictionary = _section_for(a_ctx, a_node_path)
	if section.is_empty():
		report["warnings"].append("%s: no node %s for shape radius" % [a_ctx.path, a_node_path])
		return
	var raw: String = a_ctx.doc.get_prop(section, "shape")
	var regex: RegEx = RegEx.new()
	regex.compile("^SubResource\\(\"([^\"]+)\"\\)$")
	var m: RegExMatch = regex.search(raw)
	if m != null and _sub_resource_ref_count(a_ctx, m.get_string(1)) == 1:
		for sub in a_ctx.doc.sections_of("sub_resource"):
			if sub["attrs"].get("id", "") == m.get_string(1):
				a_ctx.doc.set_prop(sub, "radius", TscnDoc.fmt_float(a_radius))
				a_ctx.dirty = true
				return
	var sid: String = a_ctx.doc.add_sub_resource("CylinderShape3D",
		a_node_path.get_file().to_snake_case(),
		{"height": "100.0", "radius": TscnDoc.fmt_float(a_radius)})
	a_ctx.doc.set_prop(section, "shape", "SubResource(\"%s\")" % sid)
	a_ctx.dirty = true


func _sub_resource_ref_count(a_ctx: Ctx, a_id: String) -> int:
	var needle: String = "SubResource(\"%s\")" % a_id
	var count: int = 0
	for section in a_ctx.doc.sections:
		for line in section["lines"]:
			var from: int = 0
			while true:
				from = String(line).find(needle, from)
				if from == -1:
					break
				count += 1
				from += needle.length()
	return count


static func _string_name_array_raw(a_ids: Array) -> String:
	return TscnDoc.fmt_string_name_array(a_ids)


# --------------------------------------------------------------------------- #
# Pieces
# --------------------------------------------------------------------------- #
func _sync_piece(a_spec: Dictionary) -> void:
	var ctx: Ctx = _open(a_spec["scene"])
	if ctx == null:
		return
	if not (ctx.inst is Entity):
		report["warnings"].append("%s: root is not an Entity — skipped" % ctx.path)
		ctx.inst.free()
		return

	_set_prop(ctx, "", "id", String(ctx.inst.id), String(a_spec["id"]),
		TscnDoc.fmt_string_name(a_spec["id"]))
	_sync_editor_description(ctx, a_spec)

	var defense: Node = ctx.inst.get_node_or_null("Defense")
	if a_spec.has("hp") and defense != null:
		_set_prop(ctx, "Defense", "hp_max", defense.hp_max, float(a_spec["hp"]), TscnDoc.fmt_float(float(a_spec["hp"])))
	if a_spec.has("armour") and defense != null:
		var v: int = Defense.ArmourType[str(a_spec["armour"])]
		_set_prop(ctx, "Defense", "armour_type", defense.armour_type, v, str(v))
	if a_spec.has("frame") and defense != null:
		var v: int = Defense.FrameType[str(a_spec["frame"])]
		_set_prop(ctx, "Defense", "frame_type", defense.frame_type, v, str(v))

	if a_spec.has("vision"):
		_set_shape_radius(ctx, "VisionRange", float(a_spec["vision"]))
	if a_spec.has("aggro"):
		_set_shape_radius(ctx, "AggroRange", float(a_spec["aggro"]))

	if a_spec.has("movement") and a_spec["movement"] is Dictionary:
		var movement: Node = ctx.inst.get_node_or_null("Movement")
		if movement == null:
			report["warnings"].append("%s: has movement: but no Movement node (structures don't move)" % ctx.path)
		else:
			var m: Dictionary = a_spec["movement"]
			if m.has("mode"):
				var v: int = Movement.Mode[str(m["mode"])]
				_set_prop(ctx, "Movement", "mode", movement.mode, v, str(v))
			if m.has("speed"):
				_set_prop(ctx, "Movement", "speed", movement.speed, float(m["speed"]), TscnDoc.fmt_float(float(m["speed"])))
			if m.has("turn_rate"):
				_set_prop(ctx, "Movement", "turn_rate", movement.turn_rate, float(m["turn_rate"]), TscnDoc.fmt_float(float(m["turn_rate"])))

	if a_spec.has("footprint"):
		var structure: Node = ctx.inst.get_node_or_null("Structure")
		if structure == null:
			report["warnings"].append("%s: has footprint: but no Structure component" % ctx.path)
		else:
			var target: Vector2i = Vector2i(int(a_spec["footprint"][0]), int(a_spec["footprint"][1]))
			_set_prop(ctx, "Structure", "dimensions", structure.dimensions, target,
				"Vector2i(%d, %d)" % [target.x, target.y])

	if a_spec.has("vigor") and a_spec["vigor"] is Dictionary:
		var v: Dictionary = a_spec["vigor"]
		if "vigor_provided" in ctx.inst:
			if v.has("capacity"):
				_set_prop(ctx, "", "vigor_provided", ctx.inst.vigor_provided, int(v["capacity"]), str(int(v["capacity"])))
			if v.has("upkeep"):
				_set_prop(ctx, "", "vigor_required", ctx.inst.vigor_required, int(v["upkeep"]), str(int(v["upkeep"])))

	if a_spec.has("trains"):
		_sync_id_list_component(ctx, "Production", "Node", SCRIPT_PRODUCTION,
			"producible_types", a_spec["trains"])
	if a_spec.has("builds"):
		_sync_id_list_component(ctx, "Builds", "Node", SCRIPT_BUILDS,
			"buildable_types", a_spec["builds"])

	if a_spec.has("weapons"):
		_sync_weapons(ctx, a_spec)

	_close(ctx)


## trains/builds: an id-list export on a component that may need creating.
func _sync_id_list_component(a_ctx: Ctx, a_name: String, a_type: String, a_script: String, a_prop: String, a_ids: Array) -> void:
	var target: Array = []
	for id in a_ids:
		target.append(StringName(str(id)))
	var node: Node = a_ctx.inst.get_node_or_null(a_name)
	var current: Array = []
	if node != null:
		for t in node.get(a_prop):
			current.append(t)
	if mode == "incremental" and node != null:
		# Update-only: append spec ids missing from the scene, keep scene extras.
		var merged: Array = current.duplicate()
		for t in target:
			if not merged.has(t):
				merged.append(t)
		target = merged
	_ensure_component(a_ctx, a_name, a_type, a_script)
	_set_prop(a_ctx, a_name, a_prop, current, target, _string_name_array_raw(target))


# --------------------------------------------------------------------------- #
# Weapons
# --------------------------------------------------------------------------- #
func _sync_weapons(a_ctx: Ctx, a_spec: Dictionary) -> void:
	var spec_weapons: Array = a_spec["weapons"]
	_ensure_component(a_ctx, "Loadout", "Node3D", SCRIPT_LOADOUT)
	var loadout: Node = a_ctx.inst.get_node_or_null("Loadout")

	var scene_weapons: Dictionary = {}   # name -> Weapon node
	if loadout != null:
		for w in loadout.get_children():
			if w is Weapon:
				scene_weapons[String(w.name)] = w

	for w in spec_weapons:
		var wname: String = str(w["name"])
		_sync_one_weapon(a_ctx, wname, w, scene_weapons.get(wname))

	if mode == "full":
		for wname in scene_weapons:
			if spec_weapons.any(func(w): return str(w["name"]) == wname):
				continue
			var wpath: String = "Loadout/%s" % wname
			if a_ctx.doc.find_node(wpath).is_empty():
				report["warnings"].append("%s: weapon %s comes from a base scene; cannot remove via text override" % [a_ctx.path, wname])
			else:
				a_ctx.doc.remove_node(wpath)
				a_ctx.dirty = true
				report["warnings"].append("%s: removed weapon %s (not in spec; full mode)" % [a_ctx.path, wname])


func _sync_one_weapon(a_ctx: Ctx, a_name: String, a_w: Dictionary, a_node: Node) -> void:
	var wpath: String = "Loadout/%s" % a_name
	if a_node == null and not a_ctx.created_nodes.has(wpath):
		var script_id: String = _ensure_ext(a_ctx, "Script", SCRIPT_WEAPON)
		a_ctx.doc.add_node(
			[["name", a_name], ["type", "Node3D"], ["parent", "Loadout"]],
			{"script": "ExtResource(\"%s\")" % script_id}
		)
		a_ctx.created_nodes[wpath] = true
		a_ctx.dirty = true

	var created: bool = a_ctx.created_nodes.has(wpath)
	var cur_split: int = a_node.split_time if a_node != null else -1
	var cur_reload: int = a_node.reload_time if a_node != null else -1
	var cur_clip: int = a_node.clip_size if a_node != null else -1
	var cur_mask: int = a_node.target_mask if a_node != null else -1

	if a_w.has("split_time"):
		var ticks: int = int(roundf(float(a_w["split_time"]) * 30.0))
		_set_prop(a_ctx, wpath, "split_time", cur_split, ticks, str(ticks))
	if a_w.has("reload_time"):
		var ticks: int = int(roundf(float(a_w["reload_time"]) * 30.0))
		_set_prop(a_ctx, wpath, "reload_time", cur_reload, ticks, str(ticks))
	if a_w.has("clip_size"):
		_set_prop(a_ctx, wpath, "clip_size", cur_clip, int(a_w["clip_size"]), str(int(a_w["clip_size"])))

	if a_w.has("projectile"):
		var proj_spec: Dictionary = registry.projectiles[str(a_w["projectile"])]
		var proj_path: String = str(proj_spec["scene"])
		var cur_path: String = a_node.projectile_scene.resource_path \
			if (a_node != null and a_node.projectile_scene != null) else ""
		if created or cur_path != proj_path:
			var pid: String = _ensure_ext(a_ctx, "PackedScene", proj_path)
			var section: Dictionary = _section_for(a_ctx, wpath)
			a_ctx.doc.set_prop(section, "projectile_scene", "ExtResource(\"%s\")" % pid)
			a_ctx.doc.set_prop(section, "melee_damage", "0.0")
			a_ctx.dirty = true
	else:
		if a_w.has("melee_damage"):
			var cur: float = a_node.melee_damage if a_node != null else -1.0
			_set_prop(a_ctx, wpath, "melee_damage", cur, float(a_w["melee_damage"]), TscnDoc.fmt_float(float(a_w["melee_damage"])))
		if a_w.has("melee_damage_type"):
			var v: int = Damage.Type[str(a_w["melee_damage_type"])]
			var cur: int = a_node.melee_damage_type if a_node != null else -1
			_set_prop(a_ctx, wpath, "melee_damage_type", cur, v, str(v))
		if a_node != null and a_node.projectile_scene != null:
			var section: Dictionary = _section_for(a_ctx, wpath)
			a_ctx.doc.remove_prop(section, "projectile_scene")
			a_ctx.dirty = true

	if a_w.has("hits"):
		var mask: int = 0
		for h in a_w["hits"]:
			if str(h) == "ground":
				mask |= CollisionLayers.Mask.TARGETABLE_GROUND
			elif str(h) == "air":
				mask |= CollisionLayers.Mask.TARGETABLE_AIR
		_set_prop(a_ctx, wpath, "target_mask", cur_mask, mask, str(mask))

	if a_w.has("reach"):
		_sync_reach(a_ctx, wpath, a_w["reach"], a_node)


## reach: 4  -> one range shape; reach: {ground: 4, air: 10} -> split shapes.
## Existing node names are respected; missing shapes are created.
func _sync_reach(a_ctx: Ctx, a_wpath: String, a_reach: Variant, a_node: Node) -> void:
	var has_ground: bool = a_node != null and a_node.get_node_or_null("AttackRangeGround") != null
	var has_air: bool = a_node != null and a_node.get_node_or_null("AttackRangeAir") != null
	var has_single: bool = a_node != null and a_node.get_node_or_null("AttackRange") != null

	if a_reach is Dictionary:
		var ground: float = float(a_reach.get("ground", a_reach.get("air", 0)))
		var air: float = float(a_reach.get("air", a_reach.get("ground", 0)))
		if has_ground or has_air:
			if has_ground:
				_set_shape_radius(a_ctx, a_wpath + "/AttackRangeGround", ground)
			if has_air:
				_set_shape_radius(a_ctx, a_wpath + "/AttackRangeAir", air)
		elif has_single:
			report["warnings"].append("%s: %s has one AttackRange but spec wants split ground/air reach — split the shapes in the editor first" % [a_ctx.path, a_wpath])
		else:
			_create_range_shape(a_ctx, a_wpath, "AttackRangeGround", ground)
			_create_range_shape(a_ctx, a_wpath, "AttackRangeAir", air)
	else:
		var radius: float = float(a_reach)
		if has_ground or has_air:
			if has_ground:
				_set_shape_radius(a_ctx, a_wpath + "/AttackRangeGround", radius)
			if has_air:
				_set_shape_radius(a_ctx, a_wpath + "/AttackRangeAir", radius)
		elif has_single:
			_set_shape_radius(a_ctx, a_wpath + "/AttackRange", radius)
		else:
			_create_range_shape(a_ctx, a_wpath, "AttackRange", radius)


func _create_range_shape(a_ctx: Ctx, a_wpath: String, a_name: String, a_radius: float) -> void:
	var sid: String = a_ctx.doc.add_sub_resource("CylinderShape3D", a_name.to_snake_case(),
		{"height": "100.0", "radius": TscnDoc.fmt_float(a_radius)})
	a_ctx.doc.add_node(
		[["name", a_name], ["type", "CollisionShape3D"], ["parent", a_wpath],
		 ["groups", "[\"debug_shape_attack_range\"]"]],
		{"visible": "false", "shape": "SubResource(\"%s\")" % sid, "disabled": "true"}
	)
	a_ctx.created_nodes[a_wpath + "/" + a_name] = true
	a_ctx.dirty = true


# --------------------------------------------------------------------------- #
# Projectiles
# --------------------------------------------------------------------------- #
func _sync_projectile(a_spec: Dictionary) -> void:
	if not a_spec.has("scene"):
		report["warnings"].append("projectile '%s' has no scene: — skeletons are only auto-created for pieces and inline projectiles" % a_spec["id"])
		return
	var ctx: Ctx = _open(a_spec["scene"])
	if ctx == null:
		return
	if not (ctx.inst is Projectile):
		report["warnings"].append("%s: root is not a Projectile — skipped" % ctx.path)
		ctx.inst.free()
		return

	_sync_editor_description(ctx, a_spec)

	if a_spec.has("damage"):
		_set_prop(ctx, "", "base_damage", ctx.inst.base_damage, float(a_spec["damage"]), TscnDoc.fmt_float(float(a_spec["damage"])))
	if a_spec.has("damage_type"):
		var v: int = Damage.Type[str(a_spec["damage_type"])]
		_set_prop(ctx, "", "damage_type", ctx.inst.damage_type, v, str(v))
	if a_spec.has("speed"):
		_set_prop(ctx, "", "speed", ctx.inst.speed, float(a_spec["speed"]), TscnDoc.fmt_float(float(a_spec["speed"])))
	if a_spec.has("trajectory"):
		var v: int = Projectile.Trajectory[str(a_spec["trajectory"])]
		_set_prop(ctx, "", "trajectory", ctx.inst.trajectory, v, str(v))
	if a_spec.has("hitscan"):
		_set_prop(ctx, "", "hitscan", ctx.inst.hitscan, bool(a_spec["hitscan"]),
			"true" if a_spec["hitscan"] else "false")

	if a_spec.has("status_effects"):
		_sync_status_effects(ctx, a_spec["status_effects"])

	_close(ctx)


## Projectile status_effects: instanced status-effect scenes under
## EffectApplicator, matched by scene path. Embedded (non-instanced) effect
## nodes are opaque to the doc layer — warned, never touched.
func _sync_status_effects(a_ctx: Ctx, a_effect_ids: Array) -> void:
	var want: Dictionary = {}   # scene path -> effect id
	for id in a_effect_ids:
		var spec: Dictionary = registry.status_effects[str(id)]
		want[str(spec["scene"])] = str(id)

	var applicator: Node = a_ctx.inst.get_node_or_null("EffectApplicator")
	if applicator == null and not a_ctx.created_nodes.has("EffectApplicator"):
		var script_id: String = _ensure_ext(a_ctx, "Script", SCRIPT_EFFECT_APPLICATOR)
		a_ctx.doc.add_node(
			[["name", "EffectApplicator"], ["type", "Sprite3D"], ["parent", "."]],
			{"script": "ExtResource(\"%s\")" % script_id}
		)
		a_ctx.created_nodes["EffectApplicator"] = true
		a_ctx.dirty = true

	var have: Dictionary = {}   # scene path -> child name
	if applicator != null:
		for child in applicator.get_children():
			if child.scene_file_path != "":
				have[child.scene_file_path] = String(child.name)
			elif child is StatusEffect:
				report["warnings"].append("%s: embedded status effect %s is not doc-governable (extract it to a scene)" % [a_ctx.path, child.name])

	for scene_path in want:
		if have.has(scene_path):
			continue
		var eid: String = _ensure_ext(a_ctx, "PackedScene", scene_path)
		a_ctx.doc.add_node(
			[["name", str(want[scene_path]).to_pascal_case()], ["parent", "EffectApplicator"],
			 ["instance", "ExtResource(\"%s\")" % eid]],
			{}
		)
		a_ctx.dirty = true

	if mode == "full":
		for scene_path in have:
			if want.has(scene_path):
				continue
			var child_path: String = "EffectApplicator/%s" % have[scene_path]
			if a_ctx.doc.find_node(child_path).is_empty():
				report["warnings"].append("%s: %s comes from a base scene; cannot remove" % [a_ctx.path, child_path])
			else:
				a_ctx.doc.remove_node(child_path)
				a_ctx.dirty = true
				report["warnings"].append("%s: removed status effect %s (not in spec; full mode)" % [a_ctx.path, have[scene_path]])


# --------------------------------------------------------------------------- #
# Factions
# --------------------------------------------------------------------------- #
func _sync_faction(a_spec: Dictionary) -> void:
	var ctx: Ctx = _open(a_spec["scene"])
	if ctx == null:
		return
	if not (ctx.inst is Faction):
		report["warnings"].append("%s: root is not a Faction — skipped" % ctx.path)
		ctx.inst.free()
		return

	_sync_editor_description(ctx, a_spec)

	# `title` is the user-facing display name; for a faction that is its
	# faction_name (the id stays a generic, non-flavor identifier).
	if a_spec.has("title"):
		_set_prop(ctx, "", "faction_name", ctx.inst.faction_name, str(a_spec["title"]),
			TscnDoc.fmt_string(str(a_spec["title"])))

	if a_spec.has("starts_with"):
		var structure_scene: String = ""
		var unit_scenes: Array = []
		for ref in a_spec["starts_with"]:
			var piece: Dictionary = registry.pieces[str(ref)]
			if piece["_kind"] == "structure":
				structure_scene = str(piece["scene"])
			else:
				unit_scenes.append(str(piece["scene"]))

		var cur_structure: String = ctx.inst.starting_structure.resource_path \
			if ctx.inst.starting_structure != null else ""
		if cur_structure != structure_scene:
			var sid: String = _ensure_ext(ctx, "PackedScene", structure_scene)
			var root: Dictionary = _section_for(ctx, "")
			ctx.doc.set_prop(root, "starting_structure", "ExtResource(\"%s\")" % sid)
			ctx.dirty = true

		var cur_units: Array = []
		for packed in ctx.inst.starting_units:
			cur_units.append(packed.resource_path if packed != null else "")
		if cur_units != unit_scenes:
			var parts: Array = []
			for path in unit_scenes:
				parts.append("ExtResource(\"%s\")" % _ensure_ext(ctx, "PackedScene", path))
			var root: Dictionary = _section_for(ctx, "")
			ctx.doc.set_prop(root, "starting_units", "Array[PackedScene]([%s])" % ", ".join(parts))
			ctx.dirty = true

	if a_spec.has("ordnances"):
		_sync_ordnances(ctx, a_spec)

	_close(ctx)


## Name-only ordnance matching (this pass): each doc identifier must match an
## existing OrdnanceUnlock in the scene (normalized ordnance_name). The
## ordnance_unlocks array is rebuilt in doc order; full mode drops unmatched
## unlocks from the array (their sub_resources stay in the file, harmless).
func _sync_ordnances(a_ctx: Ctx, a_spec: Dictionary) -> void:
	var by_name: Dictionary = {}      # normalized name -> index into ordnance_unlocks
	var current_order: Array = []     # normalized names, scene order
	for i in a_ctx.inst.ordnance_unlocks.size():
		var unlock: OrdnanceUnlock = a_ctx.inst.ordnance_unlocks[i]
		if unlock == null or unlock.ordnance == null:
			continue
		var norm: String = String(unlock.ordnance.ordnance_name).to_snake_case()
		by_name[norm] = i
		current_order.append(norm)

	var wanted: Array = []
	for o in a_spec["ordnances"]:
		var norm: String = str(o)
		if not by_name.has(norm):
			report["errors"].append("%s [%s]: ordnances names '%s' but the faction scene has no OrdnanceUnlock with that ordnance_name — author it in the scene first" % [a_spec["_doc_path"], a_spec["id"], norm])
			return
		wanted.append(norm)

	var final_order: Array = wanted.duplicate()
	if mode == "incremental":
		for norm in current_order:
			if not final_order.has(norm):
				final_order.append(norm)
	if final_order == current_order:
		return

	# Rebuild the array property from the file's existing SubResource ids, in
	# the same element order the live instance reported.
	var root: Dictionary = _section_for(a_ctx, "")
	var raw: String = a_ctx.doc.get_prop(root, "ordnance_unlocks")
	var regex: RegEx = RegEx.new()
	regex.compile("^(Array\\[[^\\]]+\\])\\(\\[(.*)\\]\\)$")
	var m: RegExMatch = regex.search(raw)
	if m == null:
		report["warnings"].append("%s: cannot parse ordnance_unlocks property — left untouched" % a_ctx.path)
		return
	var element_raws: Array = []
	for part in m.get_string(2).split(", "):
		if part.strip_edges() != "":
			element_raws.append(part.strip_edges())
	if element_raws.size() != current_order.size():
		report["warnings"].append("%s: ordnance_unlocks array/text mismatch — left untouched" % a_ctx.path)
		return
	var raw_by_name: Dictionary = {}
	for i in current_order.size():
		raw_by_name[current_order[i]] = element_raws[i]
	var out: Array = []
	for norm in final_order:
		out.append(raw_by_name[norm])
	a_ctx.doc.set_prop(root, "ordnance_unlocks", "%s([%s])" % [m.get_string(1), ", ".join(out)])
	a_ctx.dirty = true


# --------------------------------------------------------------------------- #
# Skeleton scenes (the "design a Mutalisk in markdown" flow)
# --------------------------------------------------------------------------- #
func _ensure_scene(a_spec: Dictionary) -> void:
	if a_spec.has("scene"):
		return
	var is_structure: bool = a_spec["_kind"] == "structure"
	var base: String = STRUCTURE_BASE if is_structure else UNIT_BASE
	var sub: String = ""
	for doc_dir in DOC_DIR_TO_SCENE_SUB:
		if str(a_spec["_doc_path"]).contains("/factions/%s/" % doc_dir):
			sub = DOC_DIR_TO_SCENE_SUB[doc_dir]
	var dir: String = "res://scenes/entities/%s" % ("structures" if is_structure else "units")
	if sub != "":
		dir = dir.path_join(sub)
	var path: String = dir.path_join(str(a_spec["id"]) + ".tscn")
	if FileAccess.file_exists(path):
		report["errors"].append("%s [%s]: wants a new scene at %s but the file already exists — link it explicitly with scene: or rename" % [a_spec["_doc_path"], a_spec["id"], path])
		return

	var uid_int: int = ResourceUID.create_id()
	var uid: String = ResourceUID.id_to_text(uid_int)
	var root_name: String = str(a_spec["id"]).to_pascal_case()
	var text: String = "\n".join([
		"[gd_scene load_steps=2 format=3 uid=\"%s\"]" % uid,
		"",
		"[ext_resource type=\"PackedScene\" uid=\"%s\" path=\"%s\" id=\"1_base\"]" % [_uid_for(base), base],
		"",
		"[node name=\"%s\" instance=ExtResource(\"1_base\")]" % root_name,
		"id = %s" % TscnDoc.fmt_string_name(str(a_spec["id"])),
		"",
	])
	DirAccess.make_dir_recursive_absolute(dir)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		report["errors"].append("cannot create %s" % path)
		return
	f.store_string(text)
	f.close()
	if ResourceUID.has_id(uid_int):
		ResourceUID.set_id(uid_int, path)
	else:
		ResourceUID.add_id(uid_int, path)

	a_spec["scene"] = path
	report["created"].append(path)
	_write_scene_back_into_doc(a_spec, path)


## Inline-projectile counterpart to _ensure_scene: same skeleton-creation
## mechanics (inherits PROJECTILE_BASE, grouped into the same faction subdir
## as the owning unit), but the resolved path is written back only into the
## in-memory spec — `_doc_path` here is the OWNING unit's doc, which already
## has its own `scene:` field, so there is no frontmatter to insert into.
func _ensure_inline_projectile_scene(a_spec: Dictionary) -> void:
	if a_spec.has("scene") or not a_spec.get("_inline", false):
		return
	var sub: String = ""
	for doc_dir in DOC_DIR_TO_SCENE_SUB:
		if str(a_spec["_doc_path"]).contains("/factions/%s/" % doc_dir):
			sub = DOC_DIR_TO_SCENE_SUB[doc_dir]
	var dir: String = "res://scenes/entities/projectiles"
	if sub != "":
		dir = dir.path_join(sub)
	var path: String = dir.path_join(str(a_spec["id"]) + ".tscn")
	if FileAccess.file_exists(path):
		# Inline projectiles have no frontmatter to persist scene: into, so
		# every run recomputes this same deterministic path from the (stable)
		# projectile id. Unlike the piece flow — where reaching this branch
		# means a genuine conflict, since a successful prior run would have
		# short-circuited via the persisted scene: field — a file already
		# here just means a previous run created it. Adopt it silently and
		# let _sync_projectile update its contents like any other scene, so
		# re-running stays a no-op when nothing changed.
		a_spec["scene"] = path
		return

	var uid_int: int = ResourceUID.create_id()
	var uid: String = ResourceUID.id_to_text(uid_int)
	var root_name: String = str(a_spec["id"]).to_pascal_case()
	var text: String = "\n".join([
		"[gd_scene load_steps=2 format=3 uid=\"%s\"]" % uid,
		"",
		"[ext_resource type=\"PackedScene\" uid=\"%s\" path=\"%s\" id=\"1_base\"]" % [_uid_for(PROJECTILE_BASE), PROJECTILE_BASE],
		"",
		"[node name=\"%s\" instance=ExtResource(\"1_base\")]" % root_name,
		"",
	])
	DirAccess.make_dir_recursive_absolute(dir)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		report["errors"].append("cannot create %s" % path)
		return
	f.store_string(text)
	f.close()
	if ResourceUID.has_id(uid_int):
		ResourceUID.set_id(uid_int, path)
	else:
		ResourceUID.add_id(uid_int, path)

	a_spec["scene"] = path
	report["created"].append(path)


## Inserts `scene: <path>` into the doc's frontmatter, after the id: line (or
## the kind: line when no explicit id is authored).
func _write_scene_back_into_doc(a_spec: Dictionary, a_scene_path: String) -> void:
	var doc_path: String = str(a_spec["_doc_path"])
	var text: String = FileAccess.get_file_as_string(doc_path)
	var lines: PackedStringArray = text.split("\n")
	var insert_at: int = -1
	var in_fm: bool = false
	for i in lines.size():
		var line: String = lines[i].strip_edges()
		if i == 0 and line == "---":
			in_fm = true
			continue
		if not in_fm:
			break
		if line == "---":
			if insert_at == -1:
				insert_at = i
			break
		if line.begins_with("id:") or (line.begins_with("kind:") and insert_at == -1):
			insert_at = i + 1
	if insert_at == -1:
		report["warnings"].append("%s: could not write scene: back into frontmatter" % doc_path)
		return
	var out: Array = []
	for i in lines.size():
		if i == insert_at:
			out.append("scene: %s" % a_scene_path)
		out.append(lines[i])
	var f: FileAccess = FileAccess.open(doc_path, FileAccess.WRITE)
	if f == null:
		report["warnings"].append("cannot write back to %s" % doc_path)
		return
	f.store_string("\n".join(out))
	f.close()
