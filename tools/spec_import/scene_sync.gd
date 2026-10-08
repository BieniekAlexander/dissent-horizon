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
## starts_with, sanctions; scalars always overwrite when present):
##   full        — the spec list is authoritative; scene-only items are removed
##   incremental — update/create only; scene-only items are preserved
##
## SCENES ARE NEVER A PREREQUISITE — the importer creates any it is missing, so
## every kind can be authored doc-first ("design a Mutalisk in markdown"):
##   * no `scene:` — the path is INFERRED from the doc's faction dir + id, the
##     skeleton is created there, and the path is written back into the doc.
##     No scene inherits another: a piece is COMPOSED from the component library
##     (SpecComposition), an emission is an Entity root with its hit shape.
##   * `scene:` naming a file that does not exist — the skeleton is created at
##     that DECLARED path (nothing is inferred, and the doc already holds the
##     path so there is nothing to write back). This is the only route for
##     factions and status effects, which must always name their scene.
## Inline projectiles (hoisted from a weapon's `projectile: {...}` dict) have no
## doc of their own, so their resolved path is written back only into the
## in-memory spec, not to any frontmatter file.
##
## A skeleton is deliberately bare — root node, script, id — because
## _sync_composition then adds the guaranteed components and _sync_* fills in
## everything the doc specifies. Art stays editor work.

const SpecComposition := preload("res://tools/spec_import/composition.gd")
const SpecGenerators := preload("res://tools/spec_import/generators.gd")
const SpecSchema := preload("res://tools/spec_import/schema.gd")
const EmissionPhases := preload("res://tools/spec_import/emission_phases.gd")
const TscnDoc := preload("res://tools/spec_import/tscn_doc.gd")
const VisualDefaults := preload("res://tools/spec_import/visual_defaults.gd")
const VisualMeasure := preload("res://tools/spec_import/visual_measure.gd")

## Height of every cylinder the importer writes — the runtime's range-volume height, so a
## doc-governed shape and a derived aggro shape can never disagree (see RangeShapes).
const SHAPE_HEIGHT: float = RangeShapes.SHAPE_HEIGHT

## Sanction grid authoring. A cell the doc declares and the scene lacks is created from
## these three: the two Resource scripts, plus the stub payload — an unimplemented
## sanction should be a visibly inert cell, never a null event_scene (which arms a button
## that then never disarms).
const SCRIPT_SANCTION: String = "res://scripts/interface/commander/sanction.gd"
const SCRIPT_SANCTION_UNLOCK: String = "res://scripts/interface/commander/sanction_unlock.gd"
const SANCTION_STUB_SCENE: String = "res://scenes/scenario_events/sanction_stub.tscn"

const SCRIPT_LOADOUT: String = "res://scripts/entities/components/loadout.gd"
const SCRIPT_WEAPON: String = "res://scripts/entities/tools/weapon.gd"
const SCRIPT_PRODUCTION: String = "res://scripts/entities/components/production.gd"
const SCRIPT_BUILDS: String = "res://scripts/entities/components/builds.gd"
const SCRIPT_REPAIRS: String = "res://scripts/entities/components/repairs.gd"
## The Colonial bombardment components, both plain data: a radius, and a reach plus a
## channel time. The GUN half is not here — a battery is an ability (see the `abilities:`
## key), so its cooldown is a charge pool and its shell is the ability's `emits:`.
const SCRIPT_BEACON_RANGE: String = "res://scripts/entities/components/beacon_range.gd"
## Added to any piece whose doc declares `ability_groups:` — it holds that piece's
## abilities and the charge pools they draw on (see Abilities).
const SCRIPT_ABILITIES: String = "res://scripts/entities/components/abilities.gd"
const SCRIPT_STEALTH: String = "res://scripts/entities/components/stealth.gd"
const SCRIPT_DEPLOYABLE: String = "res://scripts/entities/components/deployable.gd"
const SCRIPT_GARRISON: String = "res://scripts/entities/components/garrison.gd"
const SCRIPT_EFFECT_APPLICATOR: String = "res://scripts/entities/effects/effect_applicator.gd"
const SCRIPT_FACTION: String = "res://scripts/interface/commander/faction.gd"
const SCRIPT_STATUS_EFFECT: String = "res://scripts/entities/effects/status_effect.gd"
const SCRIPT_STRUCTURE: String = "res://scripts/entities/components/structure.gd"
## IDENTITY components — behaviour one piece (or a named handful) has, like the Shelter.
## Doc key -> [node name, script]. The doc declares only PRESENCE; the component's tuning is
## scene-authored, because a mechanic this specific does not earn a doc schema until it is
## reused (composition-rework §Step 4).
const IDENTITY_COMPONENTS: Dictionary = {
	"shelter": ["Shelter", "res://scripts/entities/components/shelter.gd"],
	"extraction_site": ["ExtractionSite", "res://scripts/entities/structures/extraction_site.gd"],
	"extractor": ["Extractor", "res://scripts/entities/structures/extractor.gd"],
	"plants_beacons": ["BeaconPlanter", "res://scripts/entities/components/beacon_planter.gd"],
}
const SCRIPT_EMISSION_PHASE: String = "res://scripts/entities/tools/emission_phase.gd"
const SCRIPT_SPAWN_EMISSION: String = "res://scripts/scenario/events/event_spawn_emission.gd"
## Emission-root properties the phase list replaced. Stripped from every emission scene the
## pass touches, so each fact is stated once — on its phase.
const RETIRED_EMISSION_PROPERTIES: Array[String] = [
	"speed", "trajectory", "pre_impact_lifespan", "post_impact_lifespan", "tick_rate"
]
## The EmissionPhase properties the doc governs, all of them, in the order they are written.
const PHASE_PROPERTIES: Array[String] = [
	"speed",
	"gravity_mps2",
	"launch_pitch_degrees",
	"turn_rate_degrees_per_second",
	"launch_speed_ratio",
	"acceleration_mps2",
	"min_speed",
	"jitter_degrees",
	"jitter_frequency_hz",
	"burn_seconds",
	"coast_speed",
	"turn_bleed_mps2_per_radian",
	"lead_fraction",
	"lock_cone_degrees",
	"lock_range",
	"ends_on_arrival",
	"lifespan_seconds",
	"impact_mask",
	"applies_payload",
	"payload_period_seconds",
	"event_period_seconds",
	"visuals"
]
## The child an `emits:` phase runs on its cadence.
const PHASE_EMIT_NODE: String = "Emit"

## Doc key -> the CollisionShape3D whose radius it sets: vision, and the body the piece pushes
## through the world with (nav footprint / avoidance radius). Composition gives a piece the
## nodes; `detection:` is handled separately because its node is created on demand. What
## weapons hit — the hurtbox — is not a doc key: it is fitted to the model (_bake_hurtbox).
const SHAPE_PATHS: Dictionary = {
	"vision": "VisionRange",
	"movement_radius": "MovementBody",
}

## The SHAPE_PATHS keys a doc may switch OFF — `false`, or the value simply left empty
## (SpecRegistry._check_radius normalises both to 0). The two DETECTION volumes only: the
## physical bodies are not optional, since every piece pushes through the world and every
## piece is shootable, which is why `_check_radius` refuses zero for those two outright.
const REMOVABLE_SHAPE_KEYS: Array[String] = ["vision"]

## `movement:` keys that are a plain float, written straight through.
##
## The chassis knobs are unbounded by default (INF / -INF), so a doc naming neither leaves a
## unit turning and stopping instantly. The two ratios used to be SCENE-ONLY — each of them
## genuinely varies across the roster, which is the whole test for belonging in the schema,
## and `an_mechStrong_transport` carried an out-of-range 1.5 for as long as nothing looked.
const MOVEMENT_FLOATS: Array[String] = [
	"speed",
	"turn_rate",
	"max_acceleration",
	"max_deceleration",
	"min_turn_speed_ratio",
	"reverse_speed_ratio",
]

## `aerial:` keys that are a plain float, written straight onto the Aerial component.
const AERIAL_FLOATS: Array[String] = ["orbit_radius", "orbit_speed"]

## Locomotion properties that moved to Aerial or Docking. A scene written before the move
## still stores them on its Locomotion node, where nothing reads them any more; the sync
## strips them so the only copy is the one the doc writes.
const RETIRED_LOCOMOTION_PROPERTIES: Array[String] = [
	"mode",
	"docks",
	"orbit_radius",
	"orbit_speed",
	"dive_distance",
	"dive_turn_rate_multiplier",
]

## `movement:` keys that name an ENUM MEMBER, mapped through the enum that owns it — named
## in the doc rather than written as the int it compiles to, like every other enum here.
## A `static var` rather than a `const` because an enum reference is not a constant
## expression in GDScript; never written after this line.
static var MOVEMENT_ENUMS: Dictionary = {
	"crush_class": Movement.CrushClass,
}

## gdd faction dir (generic ideology) -> scene faction subdir, for placing
## skeleton scenes. Every faction dir belongs here: a doc under one that is
## missing lands its skeleton in the scene root instead of its faction folder.
const DOC_DIR_TO_SCENE_SUB: Dictionary = {
	"anarchical": "an",
	"colonial": "cl",
	"libertarian": "lb",
	"marxist": "mr",
	"neutral": "nt",
	"technocratic": "tc",
	"theocratic": "th",
}

var registry: RefCounted
var mode: String
## One-off migration switch: regenerate the visual slots the importer does NOT own, i.e.
## values that predate this pass. Off by default, because the standing rule is that a value
## already in a scene is the author's — see visual_defaults.gd's header.
var rebake_visuals: bool = false
var report: Dictionary = {"changed": [], "created": [], "warnings": [], "errors": []}
## doc path -> the scene path a skeleton created for it, waiting to be written into that
## doc's frontmatter. Collected rather than written on the spot so that every gdd doc is
## opened, edited and saved EXACTLY ONCE per run (see _rewrite_docs).
var _pending_scene_writebacks: Dictionary = {}


static func sync_all(
	registry: RefCounted, mode: String, rebake_visuals: bool = false
) -> Dictionary:
	var sync: RefCounted = new()
	sync.registry = registry
	sync.mode = mode
	sync.rebake_visuals = rebake_visuals
	sync._run()
	return sync.report


func _run() -> void:
	# Skeletons first, so every spec has a scene on disk before syncing.
	for id in registry.pieces:
		_ensure_scene(registry.pieces[id])
	for id in registry.projectiles:
		_ensure_projectile_scene(registry.projectiles[id])
	for id in registry.factions:
		_ensure_faction_scene(registry.factions[id])
	for id in registry.status_effects:
		_ensure_status_effect_scene(registry.status_effects[id])
	if not report["errors"].is_empty():
		return
	_rewrite_docs()
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
	## node paths removed this run (`inst` still holds them).
	var removed_nodes: Dictionary = {}


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
	var parent_attr: String = (
		"." if not a_node_path.contains("/") else a_node_path.substr(0, a_node_path.rfind("/"))
	)
	a_ctx.dirty = true
	return (
		a_ctx
		. doc
		. add_node(
			[
				["name", node.name],
				["parent", parent_attr],
				["index", str(node.get_index())],
			],
			{}
		)
	)


## Sets a property when the live value differs from the target. `a_raw` is the
## .tscn literal to write. Nodes created this run always take the write.
func _set_prop(
	a_ctx: Ctx,
	a_node_path: String,
	a_prop: String,
	a_current: Variant,
	a_target: Variant,
	a_raw: String
) -> void:
	if not a_ctx.created_nodes.has(a_node_path) and _values_equal(a_current, a_target):
		return
	var section: Dictionary = _section_for(a_ctx, a_node_path)
	if section.is_empty():
		report["warnings"].append(
			"%s: node %s not found; cannot set %s" % [a_ctx.path, a_node_path, a_prop]
		)
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
	var current: String = (
		String(a_ctx.inst.editor_description) if "editor_description" in a_ctx.inst else ""
	)
	_set_prop(a_ctx, "", "editor_description", current, target, TscnDoc.fmt_string(target))


## Copies the optional `description`/`verbose` spec keys into Commandable's own exported
## fields — the player-facing HUD flavor text (NOT the engine's editor-only
## `editor_description`; see _sync_editor_description for that one). Guarded by `in`
## rather than `is Commandable`, since a "piece" doc's scene root can be a non-Commandable
## Entity (e.g. ExtractionSite). Omitted key -> untouched; a piece with neither key falls back to
## Commandable's own runtime "obnoxious TODO" placeholder rather than being synced here.
func _sync_flavor_text(a_ctx: Ctx, a_spec: Dictionary) -> void:
	if a_spec.has("description") and "description" in a_ctx.inst:
		var target: String = str(a_spec["description"])
		_set_prop(
			a_ctx,
			"",
			"description",
			String(a_ctx.inst.description),
			target,
			TscnDoc.fmt_string(target)
		)
	if a_spec.has("verbose") and "verbose" in a_ctx.inst:
		var target: String = str(a_spec["verbose"])
		_set_prop(
			a_ctx, "", "verbose", String(a_ctx.inst.verbose), target, TscnDoc.fmt_string(target)
		)


## uid for a res:// path: sibling .uid file for scripts, header uid for scenes.
static func _uid_for(path: String) -> String:
	if path.get_extension() == "gd" and FileAccess.file_exists(path + ".uid"):
		return FileAccess.get_file_as_string(path + ".uid").strip_edges()
	if path.get_extension() in ["tscn", "tres"]:
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f != null:
			var header: String = f.get_line()
			f.close()
			var regex: RegEx = RegEx.new()
			regex.compile('uid="([^"]+)"')
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
		{"script": 'ExtResource("%s")' % script_id}
	)
	a_ctx.created_nodes[a_name] = true
	a_ctx.dirty = true


## Points a CollisionShape3D node at a CylinderShape3D of `a_radius`, creating
## the sub_resource (and the node's shape override) as needed.
##
## EVERY doc-governed shape is a cylinder of SHAPE_HEIGHT — one geometry for
## detection volumes and physical bodies alike, so only the radius is authored.
## A shape the file owns outright is edited in place when it is already a
## cylinder; anything else (a box, a sphere) is REPLACED rather than mutated, so
## re-typing one node never silently reshapes another. Shapes shared by several
## nodes are likewise never edited in place — the node gets its own.
func _set_shape_radius(a_ctx: Ctx, a_node_path: String, a_radius: float) -> void:
	var node: Node = a_ctx.inst.get_node_or_null(a_node_path)
	if (
		node is CollisionShape3D
		and node.shape is CylinderShape3D
		and is_equal_approx(node.shape.radius, a_radius)
		and is_equal_approx(node.shape.height, SHAPE_HEIGHT)
		and not a_ctx.created_nodes.has(a_node_path)
	):
		return
	var section: Dictionary = _section_for(a_ctx, a_node_path)
	if section.is_empty():
		report["warnings"].append("%s: no node %s for shape radius" % [a_ctx.path, a_node_path])
		return
	var raw: String = a_ctx.doc.get_prop(section, "shape")
	var regex: RegEx = RegEx.new()
	regex.compile('^SubResource\\("([^"]+)"\\)$')
	var m: RegExMatch = regex.search(raw)
	if m != null and _sub_resource_ref_count(a_ctx, m.get_string(1)) == 1:
		for sub in a_ctx.doc.sections_of("sub_resource"):
			if sub["attrs"].get("id", "") != m.get_string(1):
				continue
			if sub["attrs"].get("type", "") == "CylinderShape3D":
				a_ctx.doc.set_prop(sub, "height", TscnDoc.fmt_float(SHAPE_HEIGHT))
				a_ctx.doc.set_prop(sub, "radius", TscnDoc.fmt_float(a_radius))
				a_ctx.dirty = true
				return
			# Some other shape type, referenced only here: drop it and fall through
			# to a fresh cylinder, leaving no orphan sub_resource behind.
			a_ctx.doc.remove_sub_resource(m.get_string(1))
			break
	var sid: String = a_ctx.doc.add_sub_resource(
		"CylinderShape3D", a_node_path.get_file().to_snake_case(), _cylinder_props(a_radius)
	)
	a_ctx.doc.set_prop(section, "shape", 'SubResource("%s")' % sid)
	a_ctx.dirty = true


## Raw .tscn properties for a doc-governed cylinder shape.
static func _cylinder_props(radius: float) -> Dictionary:
	return {"height": TscnDoc.fmt_float(SHAPE_HEIGHT), "radius": TscnDoc.fmt_float(radius)}


func _sub_resource_ref_count(a_ctx: Ctx, a_id: String) -> int:
	var needle: String = 'SubResource("%s")' % a_id
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


static func _string_name_array_raw(ids: Array) -> String:
	return TscnDoc.fmt_string_name_array(ids)


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

	_rename_legacy_components(ctx)
	_sync_composition(ctx, a_spec)
	_set_prop(
		ctx,
		"",
		"id",
		String(ctx.inst.id),
		String(a_spec["id"]),
		TscnDoc.fmt_string_name(a_spec["id"])
	)
	_sync_editor_description(ctx, a_spec)
	_sync_flavor_text(ctx, a_spec)
	_sync_groups(ctx, a_spec)
	_sync_defense(ctx, a_spec)
	_sync_shapes(ctx, a_spec)
	_sync_movement(ctx, a_spec)
	_strip_retired_locomotion_properties(ctx)
	_sync_aerial(ctx, a_spec)
	_sync_docking(ctx, a_spec)
	_sync_footprint(ctx, a_spec)
	_sync_root_properties(ctx, a_spec)
	_sync_optional_components(ctx, a_spec)

	if _is_removed(a_spec, "weapons"):
		_remove_component(ctx, "Loadout")
	elif a_spec.has("weapons"):
		_sync_weapons(ctx, a_spec)

	# Last, so it measures the model AFTER any doc-governed change to this scene.
	_sync_piece_visuals(ctx, a_spec)

	_close(ctx)


## Adds every component the piece's composition guarantees and its scene lacks
## (SpecComposition). This is what builds a new piece's scene out of its skeleton, and what
## gives an existing one the components a changed doc now implies — a doc that gains
## `footprint:` gains a Structure. Additions only: a guaranteed component the doc stops
## implying is left for the pass that owns its key (see _sync_footprint).
## Give a component that was renamed its new name, in the file and on the live instance.
func _rename_legacy_components(a_ctx: Ctx) -> void:
	for old_name: String in SpecComposition.RENAMED_COMPONENTS:
		var new_name: String = SpecComposition.RENAMED_COMPONENTS[old_name]
		var section: Dictionary = a_ctx.doc.find_node(old_name)
		if section.is_empty() or not a_ctx.doc.find_node(new_name).is_empty():
			continue
		a_ctx.doc.set_header_attr(section, "name", TscnDoc.fmt_string(new_name))
		for child: Dictionary in a_ctx.doc.sections_of("node"):
			var parent: String = String(child["attrs"].get("parent", ""))
			if parent == old_name or parent.begins_with(old_name + "/"):
				a_ctx.doc.set_header_attr(
					child, "parent", TscnDoc.fmt_string(new_name + parent.substr(old_name.length()))
				)
		a_ctx.inst.get_node(old_name).name = new_name
		a_ctx.dirty = true


func _sync_composition(a_ctx: Ctx, a_spec: Dictionary, a_entries: Variant = null) -> void:
	var entries: Array[Dictionary] = (
		a_entries if a_entries != null else SpecComposition.components(a_spec)
	)
	for entry: Dictionary in entries:
		var name: String = entry["name"]
		if a_ctx.inst.get_node_or_null(name) != null or a_ctx.created_nodes.has(name):
			continue
		if entry.has("scene"):
			var scene_id: String = _ensure_ext(
				a_ctx, "PackedScene", SpecComposition.scene_path(entry)
			)
			a_ctx.doc.add_node(
				[["name", name], ["parent", "."], ["instance", 'ExtResource("%s")' % scene_id]], {}
			)
			if SpecComposition.is_mobile(a_spec):
				_write_instance_overrides(a_ctx, name, entry.get("mobile_props", {}))
		else:
			var props: Dictionary = (entry.get("props", {}) as Dictionary).duplicate()
			if entry.has("script"):
				props["script"] = (
					'ExtResource("%s")'
					% _ensure_ext(a_ctx, "Script", SpecComposition.script_path(entry))
				)
			a_ctx.doc.add_node(
				[["name", name], ["type", entry["type"]], ["parent", "."]],
				props,
				str(entry.get("after", ""))
			)
		a_ctx.created_nodes[name] = true
		a_ctx.dirty = true


## Raw property overrides on a component instance: "." is the instance root, anything else a
## node inside it — which the instance must then be editable for Godot to keep.
func _write_instance_overrides(a_ctx: Ctx, a_instance: String, a_overrides: Dictionary) -> void:
	for child: String in a_overrides:
		var props: Dictionary = a_overrides[child]
		if child == ".":
			var section: Dictionary = a_ctx.doc.find_node(a_instance)
			for key: String in props:
				a_ctx.doc.set_prop(section, key, props[key])
		else:
			a_ctx.doc.add_node([["name", child], ["parent", a_instance]], props)
			a_ctx.doc.ensure_editable(a_instance)


## The piece's DERIVED groups, written onto its own root (SpecSchema.derived_groups). Today
## the base scenes supply the same groups, so this changes no resolved scene; it is what lets
## step 4 of the composition rework remove those bases without losing a group ~33 call sites
## read. Groups the derivation does not own — an identity group like "shelter" — are left as
## authored.
func _sync_groups(a_ctx: Ctx, a_spec: Dictionary) -> void:
	var root: Dictionary = a_ctx.doc.root_node()
	var authored: Array[String] = []
	var regex: RegEx = RegEx.create_from_string('"([^"]+)"')
	for found: RegExMatch in regex.search_all(str(root["attrs"].get("groups", ""))):
		authored.append(found.get_string(1))
	var kept: Array[String] = authored.filter(
		func(g: String) -> bool: return not SpecSchema.DERIVED_GROUPS.has(g)
	)
	var wanted: Array[String] = SpecSchema.derived_groups(a_spec)
	var groups: Array[String] = wanted + kept
	if groups == authored:
		return
	var quoted: PackedStringArray = []
	for group: String in groups:
		quoted.append('"%s"' % group)
	a_ctx.doc.set_header_attr(root, "groups", "[%s]" % ", ".join(quoted))
	a_ctx.dirty = true


## `hp` / `armour` / `frame` onto the Defense component, when the piece has one.
func _sync_defense(a_ctx: Ctx, a_spec: Dictionary) -> void:
	var defense: Node = a_ctx.inst.get_node_or_null("Defense")
	if defense == null:
		return
	if a_spec.has("hp"):
		_set_prop(
			a_ctx,
			"Defense",
			"hp_max",
			defense.hp_max,
			float(a_spec["hp"]),
			TscnDoc.fmt_float(float(a_spec["hp"]))
		)
	if a_spec.has("armour"):
		var armour: int = Defense.ArmourType[str(a_spec["armour"])]
		_set_prop(a_ctx, "Defense", "armour_type", defense.armour_type, armour, str(armour))
	if a_spec.has("frame"):
		var frame: int = Defense.FrameType[str(a_spec["frame"])]
		_set_prop(a_ctx, "Defense", "frame_type", defense.frame_type, frame, str(frame))


## The five radii: two DETECTION volumes, the counterpart of `stealth:`, and the two
## physical bodies — what the piece pushes through the world with (nav footprint /
## avoidance radius) and what weapons can lock onto.
##
## Only DetectionRange is created on demand here; composition supplies the others, and leaves
## out a VisionRange the doc switched off. Detecting is a rare, deliberate capability.
func _sync_shapes(a_ctx: Ctx, a_spec: Dictionary) -> void:
	for key: String in SHAPE_PATHS:
		if not a_spec.has(key):
			continue
		var radius: float = float(a_spec[key])
		# Taking a volume AWAY removes its node rather than writing a cylinder of radius
		# nothing: a shape that can never overlap anything is a detector in the inspector and
		# not one in the game. Composition leaves it out of a new scene for the same reason.
		if radius <= 0.0 and REMOVABLE_SHAPE_KEYS.has(key):
			_remove_component(a_ctx, SHAPE_PATHS[key])
		elif _library_id(a_spec, key) != "":
			_set_shape_resource(
				a_ctx, SHAPE_PATHS[key], SpecGenerators.shape_path(_library_id(a_spec, key))
			)
		else:
			_set_shape_radius(a_ctx, SHAPE_PATHS[key], radius)
	if a_spec.has("detection"):
		_sync_detection_range(a_ctx, float(a_spec["detection"]), _library_id(a_spec, "detection"))


## The shape-library id a doc key named (SpecRegistry._resolve_shape_key), or "".
static func _library_id(a_spec: Dictionary, a_key: String) -> String:
	return str(a_spec.get("_shape_ids", {}).get(a_key, ""))


## The `movement:` nest onto the navigated Locomotion component.
##
## Driven by the two tables above rather than by a ladder of `if m.has(...)`, because every
## branch did the same thing and the only content was which doc key went to which property
## (~/.claude/CLAUDE.md §1.2). `docks` is the one that is not a number and stays written out.
func _sync_movement(a_ctx: Ctx, a_spec: Dictionary) -> void:
	if not (a_spec.get("movement") is Dictionary):
		return
	var movement: Node = a_ctx.inst.get_node_or_null("Locomotion")
	if not (movement is Movement):
		report["warnings"].append(
			"%s: has movement: but no navigated Locomotion (structures don't move)" % a_ctx.path
		)
		return
	var m: Dictionary = a_spec["movement"]
	for key: String in MOVEMENT_FLOATS:
		if m.has(key):
			var value: float = float(m[key])
			_set_prop(a_ctx, "Locomotion", key, movement.get(key), value, TscnDoc.fmt_float(value))
		else:
			_clear_movement_prop(a_ctx, key)
	for key: String in MOVEMENT_ENUMS:
		if m.has(key):
			var value: int = MOVEMENT_ENUMS[key][str(m[key])]
			_set_prop(a_ctx, "Locomotion", key, movement.get(key), value, str(value))


## A `movement:` float the doc does not name falls back to the component default — for the
## chassis knobs that is INF / -INF, "turns and stops instantly", which is what the header of
## MOVEMENT_FLOATS promises. Without this a key dropped from the doc left its old value in the
## scene for good (a foot unit that used to carry an acceleration kept it), so the doc no
## longer said what the unit does.
func _clear_movement_prop(a_ctx: Ctx, a_key: String) -> void:
	var section: Dictionary = a_ctx.doc.find_node("Locomotion")
	if section.is_empty() or not a_ctx.doc.has_prop(section, a_key):
		return
	a_ctx.doc.remove_prop(section, a_key)
	a_ctx.dirty = true


## Strip the properties a Locomotion node carried before flight and docking left it.
func _strip_retired_locomotion_properties(a_ctx: Ctx) -> void:
	var section: Dictionary = a_ctx.doc.find_node("Locomotion")
	if section.is_empty():
		return
	for property: String in RETIRED_LOCOMOTION_PROPERTIES:
		if a_ctx.doc.has_prop(section, property):
			a_ctx.doc.remove_prop(section, property)
			a_ctx.dirty = true


## `aerial:` onto the Aerial component, which composition created; a piece whose doc no longer
## flies loses it. Presence is the capability, as for every identity component.
func _sync_aerial(a_ctx: Ctx, a_spec: Dictionary) -> void:
	if not (a_spec.get("aerial") is Dictionary):
		_remove_component(a_ctx, "Aerial")
		return
	var a: Dictionary = a_spec["aerial"]
	var aerial: Node = _live_node(a_ctx, "Aerial")
	if a.has("mode"):
		var mode: int = Movement.Mode[str(a["mode"])]
		_set_prop(a_ctx, "Aerial", "mode", aerial.mode if aerial != null else -1, mode, str(mode))
	for key: String in AERIAL_FLOATS:
		if a.has(key):
			var value: float = float(a[key])
			_set_prop(
				a_ctx,
				"Aerial",
				key,
				aerial.get(key) if aerial != null else INF,
				value,
				TscnDoc.fmt_float(value)
			)


## `docking:` — presence only. The component carries no authored values.
func _sync_docking(a_ctx: Ctx, a_spec: Dictionary) -> void:
	if not bool(a_spec.get("docking", false)):
		_remove_component(a_ctx, "Docking")


## The `footprint:` onto the Structure component, creating it on a piece whose base has none
## (a mobile piece that also claims cells — the two-form piece) and removing it again when the
## doc drops the key. Only a Structure this file DECLARES (a section with a type) is removed:
## an override section of the base's Structure is left alone, since the node is inherited.
func _sync_footprint(a_ctx: Ctx, a_spec: Dictionary) -> void:
	if not a_spec.has("footprint"):
		if a_ctx.doc.find_node("Structure").get("attrs", {}).has("type"):
			_remove_component(a_ctx, "Structure")
		return
	_ensure_component(a_ctx, "Structure", "Node", SCRIPT_STRUCTURE)
	var structure: Node = _live_node(a_ctx, "Structure")
	var target: Vector2i = Vector2i(int(a_spec["footprint"][0]), int(a_spec["footprint"][1]))
	_set_prop(
		a_ctx,
		"Structure",
		"dimensions",
		structure.dimensions if structure != null else Vector2i.ZERO,
		target,
		"Vector2i(%d, %d)" % [target.x, target.y]
	)


## The keys that belong to the ROOT node rather than to any component.
##
## A family member's `infrastructure:` is TEMPLATE data — what the piece grants once it is built
## as another piece — so it is never written here: Commandable.infrastructure is credited to
## whichever commander owns the node, and a neutral building (or one a garrison captured) must
## grant nothing. It is published through families.json instead.
func _sync_root_properties(a_ctx: Ctx, a_spec: Dictionary) -> void:
	for key: String in ["infrastructure", "occupancy_size"]:
		if key == "infrastructure" and a_spec.has("family"):
			continue
		if a_spec.has(key) and key in a_ctx.inst:
			var value: int = int(a_spec[key])
			_set_prop(a_ctx, "", key, a_ctx.inst.get(key), value, str(value))


## The components a piece may or may not carry. A `removed:` key takes the component OUT,
## which is why each pair is an if/elif rather than two independent tests.
func _sync_optional_components(a_ctx: Ctx, a_spec: Dictionary) -> void:
	# ONE Production component runs both lists: a research job is an ordinary job in the global
	# queue that completes by granting an upgrade instead of spawning a unit
	# (gdd/systems/macroeconomics/upgrades.md), so `researches:` extends what it produces.
	if _is_removed(a_spec, "trains"):
		_remove_component(a_ctx, "Production")
	elif a_spec.has("trains") or a_spec.has("researches"):
		_sync_id_list_component(
			a_ctx,
			"Production",
			"Node",
			SCRIPT_PRODUCTION,
			"producible_types",
			a_spec.get("trains", []) + a_spec.get("researches", [])
		)
	if _is_removed(a_spec, "builds"):
		_remove_component(a_ctx, "Builds")
	elif a_spec.has("builds"):
		_sync_id_list_component(
			a_ctx, "Builds", "Node", SCRIPT_BUILDS, "buildable_types", a_spec["builds"]
		)
	if a_spec.has("repairs"):
		_sync_flag_component(a_ctx, "Repairs", "Node", SCRIPT_REPAIRS, bool(a_spec["repairs"]))
	if a_spec.has("stealth"):
		_sync_flag_component(a_ctx, "Stealth", "Node", SCRIPT_STEALTH, bool(a_spec["stealth"]))
	for key: String in IDENTITY_COMPONENTS:
		if a_spec.has(key):
			_sync_flag_component(
				a_ctx,
				IDENTITY_COMPONENTS[key][0],
				"Node",
				IDENTITY_COMPONENTS[key][1],
				bool(a_spec[key])
			)
	if a_spec.has("beacon_range"):
		_sync_beacon_range(a_ctx, a_spec["beacon_range"])
	_sync_ability_groups(a_ctx, a_spec)
	if a_spec.has("garrison"):
		_sync_garrison(a_ctx, a_spec["garrison"])
	if a_spec.has("deploys"):
		_sync_deploys(a_ctx, a_spec["deploys"])


## repairs: a PRESENCE-ONLY component, whose mere existence is the capability (see
## Repairs). The doc key is a bare bool, so there is no list to reconcile and the two
## import modes never differ here — true creates the node, false removes it, and an
## OMITTED key never touches the scene, exactly like every other spec key. The removal
## itself is _remove_component's, below.
func _sync_flag_component(
	a_ctx: Ctx, a_name: String, a_type: String, a_script: String, a_enabled: bool
) -> void:
	if a_enabled:
		_ensure_component(a_ctx, a_name, a_type, a_script)
		return
	_remove_component(a_ctx, a_name)


## True when the doc turned a component key OFF by naming `false` instead of a collection.
## SpecRegistry normalises that spelling away (see its REMOVABLE_COLLECTION_KEYS), so this
## is the only place downstream that has to know the author had a second way to say it.
static func _is_removed(spec: Dictionary, key: String) -> bool:
	return (spec.get("_remove", []) as Array).has(key)


## THE removal path. Every component the importer can create is removed through here, so
## that "create it, then remove it, and the bytes come back" is a property of ONE function
## rather than of five near-copies. TscnDoc.remove_node supplies the other half by taking
## the resource entries the node orphaned with it (see its header).
##
## Removal only reaches a node this .tscn owns outright. A component inherited from a base
## scene cannot be deleted by a text override, so that case is reported the same way an
## inherited weapon is rather than silently doing nothing.
func _remove_component(a_ctx: Ctx, a_name: String) -> void:
	if a_ctx.inst.get_node_or_null(a_name) == null and not a_ctx.created_nodes.has(a_name):
		return
	if a_ctx.doc.find_node(a_name).is_empty():
		report["warnings"].append(
			"%s: %s comes from a base scene; cannot remove via text override" % [a_ctx.path, a_name]
		)
		return
	a_ctx.doc.remove_node(a_name)
	a_ctx.created_nodes.erase(a_name)
	a_ctx.removed_nodes[a_name] = true
	a_ctx.dirty = true


## The `ability_groups:` block — the abilities this piece can use and the charge pools they
## share. Removed again when a doc drops the key, so retiring a building's last ability
## takes its (now meaningless) charge store with it.
##
## Both charge figures are written out even when the doc omits them, so the scene states
## the pool a piece actually gets rather than leaving the reader to know the defaults.
##
## Seconds are converted to TICKS here, as every other time in this schema is, so nothing
## downstream has to know which unit the doc used.
func _sync_ability_groups(a_ctx: Ctx, a_spec: Dictionary) -> void:
	var declared: bool = (
		a_spec.has("ability_groups")
		and (a_spec["ability_groups"] is Array)
		and not (a_spec["ability_groups"] as Array).is_empty()
	)
	_sync_flag_component(a_ctx, "Abilities", "Node", SCRIPT_ABILITIES, declared)
	if not declared:
		return
	var parts: Array = []
	for group: Dictionary in a_spec["ability_groups"]:
		var grants: Array = []
		for ability in group["grants"]:
			grants.append(TscnDoc.fmt_string_name(str(ability)))
		var max_charges: int = maxi(1, int(group.get("max_charges", Abilities.DEFAULT_MAX_CHARGES)))
		(
			parts
			. append(
				(
					'{ "initial_charges": %d, "max_charges": %d, "cooldown_ticks": %d, "grants": [%s] }'
					% [
						clampi(int(group.get("initial_charges", max_charges)), 0, max_charges),
						max_charges,
						maxi(1, TimeUtils.ticks_from_seconds(float(group["cooldown"]))),
						", ".join(grants),
					]
				)
			)
		)
	var raw: String = "Array[Dictionary]([%s])" % ", ".join(parts)
	var node: Node = a_ctx.inst.get_node_or_null("Abilities")
	var current: Variant = node.groups if node != null else null
	# Compared as TEXT rather than as values: a Dictionary read back off the instance does
	# not compare equal to the literal that produced it, so a value check would rewrite the
	# scene every run.
	var section: Dictionary = _section_for(a_ctx, "Abilities")
	if not section.is_empty() and a_ctx.doc.get_prop(section, "groups") != raw:
		a_ctx.doc.set_prop(section, "groups", raw)
		a_ctx.dirty = true


## `deploys:` — the Deployable component: its two transition times, converted to TICKS here
## as every time in this schema is, and whether a deploy may be called off. `false` removes it.
func _sync_deploys(a_ctx: Ctx, a_value: Variant) -> void:
	if not (a_value is Dictionary):
		_sync_flag_component(a_ctx, "Deployable", "Node", SCRIPT_DEPLOYABLE, false)
		return
	_ensure_component(a_ctx, "Deployable", "Node", SCRIPT_DEPLOYABLE)
	var node: Node = a_ctx.inst.get_node_or_null("Deployable")
	for pair: Array in [["deploy_ticks", "time"], ["undeploy_ticks", "undeploy_time"]]:
		var ticks: int = maxi(1, TimeUtils.ticks_from_seconds(float(a_value[pair[1]])))
		_set_prop(
			a_ctx,
			"Deployable",
			pair[0],
			node.get(pair[0]) if node != null else -1,
			ticks,
			str(ticks)
		)
	var is_cancellable: bool = bool(a_value["cancellable"])
	_set_prop(
		a_ctx,
		"Deployable",
		"is_cancellable",
		node.is_cancellable if node != null else not is_cancellable,
		is_cancellable,
		"true" if is_cancellable else "false"
	)


## `beacon_range: 20` — the persistent bombardable bubble this piece projects (see
## BeaconRange). A plain radius, like `detection:`, and like it the component is created on
## demand rather than living on the base scene: spotting for artillery is a rare,
## deliberate capability. `false`/0 removes it.
func _sync_beacon_range(a_ctx: Ctx, a_value: Variant) -> void:
	if a_value is bool or float(a_value) <= 0.0:
		_sync_flag_component(a_ctx, "BeaconRange", "Node", SCRIPT_BEACON_RANGE, false)
		return
	_ensure_component(a_ctx, "BeaconRange", "Node", SCRIPT_BEACON_RANGE)
	var node: Node = a_ctx.inst.get_node_or_null("BeaconRange")
	var current: float = node.radius if node != null else -1.0
	_set_prop(
		a_ctx, "BeaconRange", "radius", current, float(a_value), TscnDoc.fmt_float(float(a_value))
	)


## The `garrison:` block — the Garrison component and its two independent halves: WHO may
## enter (three occupancy bitmasks) and HOW MUCH room there is (`capacity`, which counts
## OCCUPANCY rather than heads — see each piece's `occupancy_size`).
##
## The masks are authored as enum-name LISTS and assembled into bitmasks here, because a
## raw `occupiable_frames = 1` in a doc says nothing to a reader and everything to a bug.
## `closed: true` clears all three at once — the CLOSED HOLD (Garrison.is_closed), filled
## only by capture, deposit or scenario authoring. It says nothing about the other
## direction: `releasable` is whether occupants may be ordered OUT, and a closed hold
## releases by default (the Compound takes nobody by order and still lets its Servants out).
##
## Only keys the doc actually names are written, like every other scalar here, so a doc
## that sets capacity alone leaves the scene's authored masks untouched.
func _sync_garrison(a_ctx: Ctx, a_g: Variant) -> void:
	if a_g is bool:
		_sync_flag_component(a_ctx, "Garrison", "Node", SCRIPT_GARRISON, bool(a_g))
		return
	if not (a_g is Dictionary):
		return
	var g: Dictionary = a_g
	_ensure_component(a_ctx, "Garrison", "Node", SCRIPT_GARRISON)
	var node: Node = a_ctx.inst.get_node_or_null("Garrison")
	if g.has("capacity"):
		var cap: int = int(g["capacity"])
		_set_prop(
			a_ctx, "Garrison", "capacity", node.capacity if node != null else -1, cap, str(cap)
		)
	for flag: String in ["bunker", "preserve_occupants", "releasable", "captures"]:
		if g.has(flag):
			var v: bool = bool(g[flag])
			_set_prop(
				a_ctx,
				"Garrison",
				flag,
				node.get(flag) if node != null else null,
				v,
				"true" if v else "false"
			)
	if g.has("range_bonus"):
		var rb: float = float(g["range_bonus"])
		_set_prop(
			a_ctx,
			"Garrison",
			"range_bonus",
			node.range_bonus if node != null else -1.0,
			rb,
			TscnDoc.fmt_float(rb)
		)
	_sync_reach_by_piece(a_ctx, node, g)
	_sync_occupiable_ids(a_ctx, node, g)
	_sync_sentence_length(a_ctx, node, g)
	# A closed hold is every mask cleared; validation already refused it alongside any
	# occupancy list, so the two branches can never both apply.
	if bool(g.get("closed", false)):
		for prop: String in ["occupiable_frames", "occupiable_armours", "occupiable_movements"]:
			_set_prop(a_ctx, "Garrison", prop, node.get(prop) if node != null else -1, 0, "0")
		return
	_sync_occupancy_mask(a_ctx, node, g, "frames", "occupiable_frames", GARRISON_FRAME_BITS)
	_sync_occupancy_mask(a_ctx, node, g, "armours", "occupiable_armours", GARRISON_ARMOUR_BITS)
	_sync_occupancy_mask(
		a_ctx, node, g, "movements", "occupiable_movements", GARRISON_MOVEMENT_BITS
	)


## The `pieces:` ALLOWLIST — which named pieces this host admits, on top of the masks. An
## empty list is meaningful (it lifts the restriction), so absence is what leaves the scene
## alone, exactly as for the masks.
func _sync_occupiable_ids(a_ctx: Ctx, a_node: Node, a_g: Dictionary) -> void:
	if not a_g.has("pieces"):
		return
	var target: Array = []
	for id in a_g["pieces"]:
		target.append(StringName(str(id)))
	var current: Array = []
	if a_node != null:
		for t in a_node.occupiable_ids:
			current.append(t)
	_set_prop(a_ctx, "Garrison", "occupiable_ids", current, target, _string_name_array_raw(target))


## The `reach_by_piece:` mapping — the reach one occupant piece fires out with, keyed by id,
## already resolved to radii by the registry. Written as a typed Dictionary literal; compared
## by content so a re-run is a no-op.
func _sync_reach_by_piece(a_ctx: Ctx, a_node: Node, a_g: Dictionary) -> void:
	if not a_g.has("reach_by_piece"):
		return
	var target: Dictionary = {}
	var ids: Array = (a_g["reach_by_piece"] as Dictionary).keys()
	ids.sort()
	var parts: Array = []
	for id in ids:
		var reach: float = float(a_g["reach_by_piece"][id])
		target[StringName(str(id))] = reach
		parts.append("%s: %s" % [TscnDoc.fmt_string_name(str(id)), TscnDoc.fmt_float(reach)])
	var current: Dictionary = {}
	if a_node != null:
		for id in a_node.reach_by_piece:
			current[StringName(id)] = float(a_node.reach_by_piece[id])
	var is_unchanged := func(k: Variant) -> bool:
		return current.has(k) and is_equal_approx(current[k], target[k])
	var same: bool = current.size() == target.size() and target.keys().all(is_unchanged)
	_set_prop(
		a_ctx,
		"Garrison",
		"reach_by_piece",
		target if same else current,
		target,
		"Dictionary[StringName, float]({%s})" % ", ".join(parts)
	)


## The `sentence_length:` key — how many seconds a deposited captive serves before this
## garrison consumes it. Naming it (a positive number) is what makes the garrison a prison
## (Garrison.can_intern), replacing the old `interns:` conversion marker — this is still the
## one garrison key that changes which COMMANDS apply to the host.
func _sync_sentence_length(a_ctx: Ctx, a_node: Node, a_g: Dictionary) -> void:
	if not a_g.has("sentence_length"):
		return
	var seconds: float = float(a_g["sentence_length"])
	_set_prop(
		a_ctx,
		"Garrison",
		"sentence_length",
		a_node.sentence_length if a_node != null else -1.0,
		seconds,
		TscnDoc.fmt_float(seconds)
	)


## Enum-name bits for the three occupancy masks. Spelled out here rather than read off
## Garrison.FRAME_BITS et al because those are keyed by enum VALUE and the doc names its
## entries; keep the two in step if either enum grows a member.
const GARRISON_FRAME_BITS: Dictionary = {"BIO": 1 << 0, "MECH": 1 << 1}
const GARRISON_ARMOUR_BITS: Dictionary = {"LIGHT": 1 << 0, "MEDIUM": 1 << 1, "STRONG": 1 << 2}
const GARRISON_MOVEMENT_BITS: Dictionary = {
	"GROUNDED": 1 << 0, "HOVERING": 1 << 1, "FLYING": 1 << 2
}


## Assemble one occupancy mask from a list of enum names. An EMPTY list is meaningful —
## it clears that mask — so absence, not emptiness, is what leaves the scene alone.
func _sync_occupancy_mask(
	a_ctx: Ctx, a_node: Node, a_g: Dictionary, a_key: String, a_prop: String, a_bits: Dictionary
) -> void:
	if not a_g.has(a_key):
		return
	var mask: int = 0
	for name in a_g[a_key]:
		mask |= int(a_bits.get(str(name), 0))
	_set_prop(
		a_ctx, "Garrison", a_prop, a_node.get(a_prop) if a_node != null else -1, mask, str(mask)
	)


## The DetectionRange volume — what this piece sees stealthed units with.
##
## Unlike VisionRange and AggroRange it is NOT on the commandable base scene, because
## detecting is a rare deliberate capability rather than something every piece has. So the
## node is created here when a doc first asks for one. `disabled = true` matches the
## authored detectors: the shape is query geometry that DetectionRange scans with, never a
## live collider.
func _sync_detection_range(a_ctx: Ctx, a_radius: float, a_shape_id: String) -> void:
	# A zero radius is the documented opt-out, so it REMOVES the volume rather than writing
	# a cylinder of radius nothing: a shape that can never overlap anything is a detector in
	# the inspector and not one in the game, which is the worse of the two lies.
	if a_radius <= 0.0:
		_remove_component(a_ctx, "DetectionRange")
		return
	if (
		a_ctx.inst.get_node_or_null("DetectionRange") == null
		and not a_ctx.created_nodes.has("DetectionRange")
	):
		a_ctx.doc.add_node(
			[
				["name", "DetectionRange"],
				["type", "CollisionShape3D"],
				["parent", "."],
				["groups", '["debug_shape_detection_range"]']
			],
			{"disabled": "true"}
		)
		a_ctx.created_nodes["DetectionRange"] = true
		a_ctx.dirty = true
	_set_shape_resource(a_ctx, "DetectionRange", SpecGenerators.shape_path(a_shape_id))


## trains/builds: an id-list export on a component that may need creating.
func _sync_id_list_component(
	a_ctx: Ctx, a_name: String, a_type: String, a_script: String, a_prop: String, a_ids: Array
) -> void:
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

	var scene_weapons: Dictionary = {}  # name -> Weapon node
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
				report["warnings"].append(
					(
						"%s: weapon %s comes from a base scene; cannot remove via text override"
						% [a_ctx.path, wname]
					)
				)
			else:
				a_ctx.doc.remove_node(wpath)
				a_ctx.dirty = true
				report["warnings"].append(
					"%s: removed weapon %s (not in spec; full mode)" % [a_ctx.path, wname]
				)


func _sync_one_weapon(a_ctx: Ctx, a_name: String, a_w: Dictionary, a_node: Node) -> void:
	var wpath: String = "Loadout/%s" % a_name
	if a_node == null and not a_ctx.created_nodes.has(wpath):
		var script_id: String = _ensure_ext(a_ctx, "Script", SCRIPT_WEAPON)
		a_ctx.doc.add_node(
			[["name", a_name], ["type", "Node3D"], ["parent", "Loadout"]],
			{"script": 'ExtResource("%s")' % script_id}
		)
		a_ctx.created_nodes[wpath] = true
		a_ctx.dirty = true

	var created: bool = a_ctx.created_nodes.has(wpath)
	var cur_split: int = a_node.split_time_ticks if a_node != null else -1
	var cur_reload: int = a_node.reload_time_ticks if a_node != null else -1
	var cur_clip: int = a_node.clip_size if a_node != null else -1
	var cur_mask: int = a_node.target_mask if a_node != null else -1
	var cur_charged: bool = a_node.charged if a_node != null else false
	var cur_turret: bool = a_node.turret if a_node != null else false
	var cur_turret_rate: float = a_node.turret_turn_rate if a_node != null else -1.0
	var cur_range_origin: int = a_node.range_origin if a_node != null else -1

	# `charged: true` marks a weapon that cannot reload in the field — it empties and stays
	# empty until an airfield recharges it (see Weapon.charged). Written whenever the key is
	# present, false included, so turning it off in the doc turns it off in the scene; an
	# omitted key leaves whatever the scene has, like every other weapon property here.
	if a_w.has("charged"):
		var charged: bool = bool(a_w["charged"])
		_set_prop(a_ctx, wpath, "charged", cur_charged, charged, "true" if charged else "false")

	# `turret: true` makes the weapon aim on its own yaw instead of the body's (see
	# Weapon.turret); written whenever the key is present, false included, like `charged`.
	# `turret_turn_rate` is degrees per second on both sides.
	if a_w.has("turret"):
		var is_turret: bool = bool(a_w["turret"])
		_set_prop(a_ctx, wpath, "turret", cur_turret, is_turret, "true" if is_turret else "false")
	if a_w.has("turret_turn_rate"):
		var rate: float = float(a_w["turret_turn_rate"])
		_set_prop(a_ctx, wpath, "turret_turn_rate", cur_turret_rate, rate, TscnDoc.fmt_float(rate))

	# `range_from:` names where reach is measured from (Weapon.RangeOrigin); written whenever
	# the key is present, `hull` included, like `turret`.
	if a_w.has("range_from"):
		var origin: int = SpecRegistry.RANGE_FROM[str(a_w["range_from"])]
		_set_prop(a_ctx, wpath, "range_origin", cur_range_origin, origin, str(origin))

	# The doc authors SECONDS (`split_time:`); the scene property is TICKS
	# (`split_time_ticks`). The two are deliberately spelled differently — they used to share
	# a name and differ by a factor of 30, which is the failure CLAUDE.md §2.3 names.
	if a_w.has("split_time"):
		var ticks: int = TimeUtils.ticks_from_seconds(float(a_w["split_time"]))
		_set_prop(a_ctx, wpath, "split_time_ticks", cur_split, ticks, str(ticks))
	if a_w.has("reload_time"):
		var ticks: int = TimeUtils.ticks_from_seconds(float(a_w["reload_time"]))
		_set_prop(a_ctx, wpath, "reload_time_ticks", cur_reload, ticks, str(ticks))
	if a_w.has("startup_time"):
		var ticks: int = TimeUtils.ticks_from_seconds(float(a_w["startup_time"]))
		var cur_startup: int = a_node.startup_time_ticks if a_node != null else -1
		_set_prop(a_ctx, wpath, "startup_time_ticks", cur_startup, ticks, str(ticks))
	if a_w.has("clip_size"):
		_set_prop(
			a_ctx, wpath, "clip_size", cur_clip, int(a_w["clip_size"]), str(int(a_w["clip_size"]))
		)

	if a_w.has("projectile"):
		var proj_spec: Dictionary = registry.projectiles[str(a_w["projectile"])]
		var proj_path: String = str(proj_spec["scene"])
		var cur_path: String = (
			a_node.projectile_scene.resource_path
			if (a_node != null and a_node.projectile_scene != null)
			else ""
		)
		if created or cur_path != proj_path:
			var pid: String = _ensure_ext(a_ctx, "PackedScene", proj_path)
			var section: Dictionary = _section_for(a_ctx, wpath)
			a_ctx.doc.set_prop(section, "projectile_scene", 'ExtResource("%s")' % pid)
			a_ctx.doc.set_prop(section, "melee_damage", "0.0")
			a_ctx.dirty = true
	else:
		if a_w.has("melee_damage"):
			var cur: float = a_node.melee_damage if a_node != null else -1.0
			_set_prop(
				a_ctx,
				wpath,
				"melee_damage",
				cur,
				float(a_w["melee_damage"]),
				TscnDoc.fmt_float(float(a_w["melee_damage"]))
			)
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


## reach: <shape id> -> one range shape; reach: {ground: <id>, air: <id>} -> split shapes.
## Existing node names are respected; missing shapes are created. Every range node ends up
## pointing at the shared library resource (SpecGenerators.shape_path), never at a cylinder
## of its own — that is what makes a bucket's radius one edit for every weapon in it.
func _sync_reach(a_ctx: Ctx, a_wpath: String, a_reach: Variant, a_node: Node) -> void:
	var has_ground: bool = a_node != null and a_node.get_node_or_null("AttackRangeGround") != null
	var has_air: bool = a_node != null and a_node.get_node_or_null("AttackRangeAir") != null
	var has_single: bool = a_node != null and a_node.get_node_or_null("AttackRange") != null

	if a_reach is Dictionary:
		var ground: String = SpecGenerators.shape_path(
			str(a_reach.get("ground", a_reach.get("air", "")))
		)
		var air: String = SpecGenerators.shape_path(
			str(a_reach.get("air", a_reach.get("ground", "")))
		)
		if has_ground or has_air:
			if has_ground:
				_set_shape_resource(a_ctx, a_wpath + "/AttackRangeGround", ground)
			if has_air:
				_set_shape_resource(a_ctx, a_wpath + "/AttackRangeAir", air)
		elif has_single and not _declares_node(a_ctx, a_wpath + "/AttackRange"):
			# An inherited node cannot be removed (CLAUDE.md §An inherited node can be neither
			# removed nor repointed), so only a locally declared one is split below.
			report["warnings"].append(
				(
					(
						"%s: %s inherits one AttackRange but spec wants split "
						+ "ground/air reach — split the shapes in the base scene first"
					)
					% [a_ctx.path, a_wpath]
				)
			)
		else:
			if has_single:
				a_ctx.doc.remove_node(a_wpath + "/AttackRange")
				a_ctx.removed_nodes[a_wpath + "/AttackRange"] = true
			_create_range_shape(a_ctx, a_wpath, "AttackRangeGround", ground)
			_create_range_shape(a_ctx, a_wpath, "AttackRangeAir", air)
	else:
		var shape: String = SpecGenerators.shape_path(str(a_reach))
		if has_ground or has_air:
			if has_ground:
				_set_shape_resource(a_ctx, a_wpath + "/AttackRangeGround", shape)
			if has_air:
				_set_shape_resource(a_ctx, a_wpath + "/AttackRangeAir", shape)
		elif has_single:
			_set_shape_resource(a_ctx, a_wpath + "/AttackRange", shape)
		else:
			_create_range_shape(a_ctx, a_wpath, "AttackRange", shape)


## Whether this scene file DECLARES the node, rather than overriding one it inherits.
func _declares_node(a_ctx: Ctx, a_node_path: String) -> bool:
	var attrs: Dictionary = a_ctx.doc.find_node(a_node_path).get("attrs", {})
	return attrs.has("type") or attrs.has("instance")


## Points a CollisionShape3D node at a shared shape resource, dropping the per-scene
## sub_resource it used to own once nothing else names it.
func _set_shape_resource(a_ctx: Ctx, a_node_path: String, a_shape_path: String) -> void:
	var node: Node = a_ctx.inst.get_node_or_null(a_node_path)
	if (
		node is CollisionShape3D
		and node.shape != null
		and node.shape.resource_path == a_shape_path
		and not a_ctx.created_nodes.has(a_node_path)
	):
		return
	var section: Dictionary = _section_for(a_ctx, a_node_path)
	if section.is_empty():
		report["warnings"].append(
			"%s: no node %s for shape %s" % [a_ctx.path, a_node_path, a_shape_path]
		)
		return
	var raw: String = a_ctx.doc.get_prop(section, "shape")
	var regex: RegEx = RegEx.new()
	regex.compile('^SubResource\\("([^"]+)"\\)$')
	var m: RegExMatch = regex.search(raw)
	var eid: String = _ensure_ext(a_ctx, _library_shape_class(a_shape_path), a_shape_path)
	a_ctx.doc.set_prop(section, "shape", 'ExtResource("%s")' % eid)
	# Counted AFTER the write, so the reference just replaced is not counted as a user.
	if m != null and _sub_resource_ref_count(a_ctx, m.get_string(1)) == 0:
		a_ctx.doc.remove_sub_resource(m.get_string(1))
	a_ctx.dirty = true


## The class of the library shape generated at `a_shape_path`, read from its doc.
func _library_shape_class(a_shape_path: String) -> String:
	var id: String = a_shape_path.get_file().get_basename()
	if registry != null and registry.shapes.has(id):
		return SpecGenerators.shape_class(registry.shapes[id])
	return "CylinderShape3D"


func _create_range_shape(a_ctx: Ctx, a_wpath: String, a_name: String, a_shape_path: String) -> void:
	var eid: String = _ensure_ext(a_ctx, _library_shape_class(a_shape_path), a_shape_path)
	a_ctx.doc.add_node(
		[
			["name", a_name],
			["type", "CollisionShape3D"],
			["parent", a_wpath],
			["groups", '["debug_shape_attack_range"]']
		],
		{"visible": "false", "shape": 'ExtResource("%s")' % eid, "disabled": "true"}
	)
	a_ctx.created_nodes[a_wpath + "/" + a_name] = true
	a_ctx.dirty = true


# --------------------------------------------------------------------------- #
# Projectiles
# --------------------------------------------------------------------------- #
func _sync_projectile(a_spec: Dictionary) -> void:
	if not a_spec.has("scene"):
		# Unreachable in practice: _ensure_projectile_scene resolves (or creates)
		# a scene for every projectile, and a failure there aborts before sync.
		report["warnings"].append("projectile '%s' has no scene: — skipped" % a_spec["id"])
		return
	var ctx: Ctx = _open(a_spec["scene"])
	if ctx == null:
		return
	if not (ctx.inst is Entity):
		report["warnings"].append("%s: root is not an Entity — skipped" % ctx.path)
		ctx.inst.free()
		return

	_sync_composition(ctx, a_spec, SpecComposition.EMISSION_COMPONENTS)
	_sync_editor_description(ctx, a_spec)
	_sync_payload(ctx, a_spec)

	if a_spec.has("blast"):
		_set_blast_shape(ctx, SpecGenerators.shape_path(_library_id(a_spec, "blast")))
	var payload: Node = _live_node(ctx, "Payload")
	var scene_hitscan: bool = payload.hitscan if payload != null else false
	_sync_blast_presence(ctx, bool(a_spec.get("hitscan", scene_hitscan)))

	if _is_removed(a_spec, "status_effects"):
		_remove_component(ctx, "EffectApplicator")
	elif a_spec.has("status_effects"):
		_sync_status_effects(ctx, a_spec["status_effects"])

	_sync_projectile_visuals(ctx, a_spec)
	_sync_phases(ctx, a_spec)
	_strip_retired_emission_properties(ctx)

	_close(ctx)


## `damage` / `damage_type` / `hitscan` onto the emission's Payload component. A Payload made this
## run has no live counterpart, so it takes every value the doc states.
func _sync_payload(a_ctx: Ctx, a_spec: Dictionary) -> void:
	var payload: Node = _live_node(a_ctx, "Payload")
	if a_spec.has("damage"):
		var damage: float = float(a_spec["damage"])
		_set_prop(
			a_ctx,
			"Payload",
			"base_damage",
			payload.base_damage if payload != null else INF,
			damage,
			TscnDoc.fmt_float(damage)
		)
	if a_spec.has("damage_type"):
		var damage_type: int = Damage.Type[str(a_spec["damage_type"])]
		_set_prop(
			a_ctx,
			"Payload",
			"damage_type",
			payload.damage_type if payload != null else -1,
			damage_type,
			str(damage_type)
		)
	if a_spec.has("hitscan"):
		var hitscan: bool = bool(a_spec["hitscan"])
		_set_prop(
			a_ctx,
			"Payload",
			"hitscan",
			payload.hitscan if payload != null else not hitscan,
			hitscan,
			"true" if hitscan else "false"
		)
	if a_spec.has("bio_ground_aim"):
		var aims: bool = bool(a_spec["bio_ground_aim"])
		_set_prop(
			a_ctx,
			"Payload",
			"bio_ground_aim",
			payload.bio_ground_aim if payload != null else not aims,
			aims,
			"true" if aims else "false"
		)


## A hitscan emission lands on the one piece it was fired at, so it has no blast volume and no
## HitShape; any other emission's HitShape IS its blast (Payload.has_blast). A `disabled` flag
## left from when a hitscan shot inherited a shape it could not remove is stripped.
func _sync_blast_presence(a_ctx: Ctx, a_is_hitscan: bool) -> void:
	if a_is_hitscan:
		_remove_component(a_ctx, "HitShape")
		return
	var section: Dictionary = a_ctx.doc.find_node("HitShape")
	if not section.is_empty() and a_ctx.doc.has_prop(section, "disabled"):
		a_ctx.doc.remove_prop(section, "disabled")
		a_ctx.dirty = true


## The doc's phases as EmissionPhase children of the root, in run order. A phase the doc no
## longer names is removed; a list whose order changed is rebuilt, since run order IS tree order.
func _sync_phases(a_ctx: Ctx, a_spec: Dictionary) -> void:
	var phases: Array[Dictionary] = EmissionPhases.expand(a_spec)
	var wanted: Array[String] = []
	wanted.assign(phases.map(func(p: Dictionary) -> String: return str(p["name"])))
	var existing: Array[String] = []
	existing.assign(
		(
			a_ctx
			. inst
			. get_children()
			. filter(func(c: Node) -> bool: return c is EmissionPhase)
			. map(func(c: Node) -> String: return str(c.name))
		)
	)
	var kept: Array[String] = existing.filter(func(n: String) -> bool: return wanted.has(n))
	var is_in_order: bool = kept == wanted.slice(0, kept.size())
	for node_name: String in existing:
		if not is_in_order or not wanted.has(node_name):
			_remove_component(a_ctx, node_name)
	for phase: Dictionary in phases:
		_sync_one_phase(a_ctx, phase)


func _sync_one_phase(a_ctx: Ctx, a_phase: Dictionary) -> void:
	var path: String = str(a_phase["name"])
	var node: Node = _live_node(a_ctx, path)
	if node == null and not a_ctx.created_nodes.has(path):
		var script_id: String = _ensure_ext(a_ctx, "Script", SCRIPT_EMISSION_PHASE)
		a_ctx.doc.add_node(
			[["name", path], ["type", "Node3D"], ["parent", "."]],
			{"script": 'ExtResource("%s")' % script_id}
		)
		a_ctx.created_nodes[path] = true
		a_ctx.dirty = true
	var defaults: EmissionPhase = EmissionPhase.new()
	var visuals: Array[NodePath] = []
	for role: Variant in a_phase["visual_roles"]:
		if a_ctx.inst.get_node_or_null(str(role)) != null or a_ctx.created_nodes.has(str(role)):
			visuals.append(NodePath(str(role)))
	var values: Dictionary = a_phase.duplicate()
	values["visuals"] = visuals
	for property: String in PHASE_PROPERTIES:
		var current: Variant = node.get(property) if node != null else defaults.get(property)
		if node == null and _values_equal(current, values[property]):
			continue
		_set_prop(
			a_ctx, path, property, current, values[property], _phase_literal(values[property])
		)
	defaults.free()
	_sync_phase_emit(a_ctx, path, str(a_phase["emits"]))


## An `emits:` phase's EventSpawnEmission child, pointed at the emission it names.
func _sync_phase_emit(a_ctx: Ctx, a_phase_path: String, a_emission_id: String) -> void:
	var path: String = "%s/%s" % [a_phase_path, PHASE_EMIT_NODE]
	if a_emission_id == "":
		_remove_component(a_ctx, path)
		return
	var scene_path: String = str(registry.projectiles[a_emission_id]["scene"])
	var node: Node = _live_node(a_ctx, path)
	if node == null and not a_ctx.created_nodes.has(path):
		var script_id: String = _ensure_ext(a_ctx, "Script", SCRIPT_SPAWN_EMISSION)
		a_ctx.doc.add_node(
			[["name", PHASE_EMIT_NODE], ["type", "Sprite3D"], ["parent", a_phase_path]],
			{"script": 'ExtResource("%s")' % script_id}
		)
		a_ctx.created_nodes[path] = true
		a_ctx.dirty = true
	var current: String = (
		node.emission_scene.resource_path if node != null and node.emission_scene != null else ""
	)
	if a_ctx.created_nodes.has(path) or current != scene_path:
		var scene_id: String = _ensure_ext(a_ctx, "PackedScene", scene_path)
		a_ctx.doc.set_prop(
			_section_for(a_ctx, path), "emission_scene", 'ExtResource("%s")' % scene_id
		)
		a_ctx.dirty = true


## The live node at `a_path`, owned or INHERITED — null when it was created this run (it has
## no live counterpart) or removed this run (the live instance still holds it). An inherited
## node is written through an override section, never re-declared: a second node of the same
## name is the duplicate that segfaults at teardown (see CLAUDE.md). An emission scene can
## inherit another emission's phases — recruit_bullet.tscn inherits irregular_bullet.tscn.
func _live_node(a_ctx: Ctx, a_path: String) -> Node:
	var is_removed: bool = a_ctx.removed_nodes.keys().any(
		func(removed: String) -> bool: return a_path == removed or a_path.begins_with(removed + "/")
	)
	if a_ctx.created_nodes.has(a_path) or is_removed:
		return null
	return a_ctx.inst.get_node_or_null(a_path)


static func _phase_literal(value: Variant) -> String:
	if value is bool:
		return "true" if value else "false"
	if value is int:
		return str(value)
	if value is float:
		return TscnDoc.fmt_float(value)
	var paths: PackedStringArray = []
	for path: NodePath in value:
		paths.append('NodePath("%s")' % path)
	return "Array[NodePath]([%s])" % ", ".join(paths)


func _strip_retired_emission_properties(a_ctx: Ctx) -> void:
	var section: Dictionary = a_ctx.doc.find_node("")
	if section.is_empty():
		return
	for property: String in RETIRED_EMISSION_PROPERTIES:
		if a_ctx.doc.get_prop(section, property) != "":
			a_ctx.doc.remove_prop(section, property)
			a_ctx.dirty = true


## The projectile's BLAST: an aoe_* library shape on its HitShape.
##
## This is what makes a projectile an area weapon, and it governs damage and status effects
## ALIKE — Payload.apply resolves the entities the hit shape overlaps ONCE and then
## both damages that set and seeds its EffectApplicators with it, so the two cannot drift.
##
## The HitShape's TRANSFORM is reset to identity alongside the shape, deliberately: a scene
## that scales that node would make a bucket smaller than the library says, and resetting makes
## a bucket mean the same world size in every emission.
func _set_blast_shape(a_ctx: Ctx, a_shape_path: String) -> void:
	var node: Node = a_ctx.inst.get_node_or_null("HitShape")
	if node == null:
		report["warnings"].append("%s: has blast: but no HitShape node" % a_ctx.path)
		return
	_set_shape_resource(a_ctx, "HitShape", a_shape_path)
	if (
		(node as Node3D).transform.is_equal_approx(Transform3D.IDENTITY)
		and not a_ctx.created_nodes.has("HitShape")
	):
		return
	a_ctx.doc.set_prop(
		_section_for(a_ctx, "HitShape"),
		"transform",
		"Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)"
	)
	a_ctx.dirty = true


## An emission's status_effects: instanced status-effect scenes under
## EffectApplicator, matched by scene path. Embedded (non-instanced) effect
## nodes are opaque to the doc layer — warned, never touched.
func _sync_status_effects(a_ctx: Ctx, a_effect_ids: Array) -> void:
	var want: Dictionary = {}  # scene path -> effect id
	for id in a_effect_ids:
		var spec: Dictionary = registry.status_effects[str(id)]
		want[str(spec["scene"])] = str(id)

	var applicator: Node = a_ctx.inst.get_node_or_null("EffectApplicator")
	if applicator == null and not a_ctx.created_nodes.has("EffectApplicator"):
		var script_id: String = _ensure_ext(a_ctx, "Script", SCRIPT_EFFECT_APPLICATOR)
		a_ctx.doc.add_node(
			[["name", "EffectApplicator"], ["type", "Sprite3D"], ["parent", "."]],
			{"script": 'ExtResource("%s")' % script_id}
		)
		a_ctx.created_nodes["EffectApplicator"] = true
		a_ctx.dirty = true

	var have: Dictionary = {}  # scene path -> child name
	if applicator != null:
		for child in applicator.get_children():
			if child.scene_file_path != "":
				have[child.scene_file_path] = String(child.name)
			elif child is StatusEffect:
				(
					report["warnings"]
					. append(
						(
							"%s: embedded status effect %s is not doc-governable (extract it to a scene)"
							% [a_ctx.path, child.name]
						)
					)
				)

	for scene_path in want:
		if have.has(scene_path):
			continue
		var eid: String = _ensure_ext(a_ctx, "PackedScene", scene_path)
		a_ctx.doc.add_node(
			[
				["name", str(want[scene_path]).to_pascal_case()],
				["parent", "EffectApplicator"],
				["instance", 'ExtResource("%s")' % eid]
			],
			{}
		)
		a_ctx.dirty = true

	if mode == "full":
		for scene_path in have:
			if want.has(scene_path):
				continue
			var child_path: String = "EffectApplicator/%s" % have[scene_path]
			if a_ctx.doc.find_node(child_path).is_empty():
				report["warnings"].append(
					"%s: %s comes from a base scene; cannot remove" % [a_ctx.path, child_path]
				)
			else:
				a_ctx.doc.remove_node(child_path)
				a_ctx.dirty = true
				report["warnings"].append(
					(
						"%s: removed status effect %s (not in spec; full mode)"
						% [a_ctx.path, have[scene_path]]
					)
				)


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
		_set_prop(
			ctx,
			"",
			"faction_name",
			ctx.inst.faction_name,
			str(a_spec["title"]),
			TscnDoc.fmt_string(str(a_spec["title"]))
		)

	if a_spec.has("starts_with"):
		var unit_scenes: Array = []
		for ref in a_spec["starts_with"]:
			unit_scenes.append(str(registry.pieces[str(ref)]["scene"]))

		var cur_units: Array = []
		for packed in ctx.inst.starting_units:
			cur_units.append(packed.resource_path if packed != null else "")
		if cur_units != unit_scenes:
			var parts: Array = []
			for path in unit_scenes:
				parts.append('ExtResource("%s")' % _ensure_ext(ctx, "PackedScene", path))
			var root: Dictionary = _section_for(ctx, "")
			ctx.doc.set_prop(root, "starting_units", "Array[PackedScene]([%s])" % ", ".join(parts))
			ctx.dirty = true

	if a_spec.has("sanctions"):
		_sync_sanctions(ctx, a_spec)

	_close(ctx)


## Sync a faction's sanction GRID from its `sanctions:` list of sanction-doc ids.
##
## Each doc is one FAMILY — a chain of cells running down one column, `levels` in order,
## each continuing (and superseding) the one above it. Together with the docs' `column`
## and each level's `tier`, that is the whole grid: this pass writes tier, column, parent,
## cost, both tiers of copy and the behaviour flags onto the scene's SanctionUnlock /
## Sanction sub-resources, and rebuilds `sanction_unlocks` in doc order.
##
## WHAT STAYS IN THE SCENE is the payload — `Sanction.event_scene` and the bot's aiming
## knobs (targeting, effect_radius, min_targets). A sanction's behaviour is an event
## scene, which is not a value anyone could type into YAML; the doc carries the numbers
## and the prose, and the doc body carries the human-readable spec for the mechanic.
##
## A cell the doc names and the scene lacks is CREATED, pointed at sanction_stub.tscn.
## That keeps the sanction grid doc-first like every other kind here — write the markdown, run
## the importer, get a playable (if inert) cell — and a stub is the honest state for an
## sanction whose event has not been written. Leaving `event_scene` null instead would
## arm a button that never disarms.
func _sync_sanctions(a_ctx: Ctx, a_spec: Dictionary) -> void:
	var cells: Array = _grid_cells(a_spec)
	if cells.is_empty():
		return

	# Existing unlock sub_resource ids, keyed by the snake_cased sanction_name they carry,
	# so a doc level finds the cell it belongs to however the array is ordered.
	var unlock_ids: Dictionary = _unlock_sub_ids(a_ctx)
	if unlock_ids.is_empty() and not a_ctx.inst.sanction_unlocks.is_empty():
		report["warnings"].append(
			"%s: cannot match sanction_unlocks to sub_resources — left untouched" % a_ctx.path
		)
		return

	var order: Array = []  # unlock sub_resource ids, in doc order
	var by_key: Dictionary = {}  # level key -> unlock sub_resource id
	for cell: Dictionary in cells:
		var key: String = str(cell["title"]).to_snake_case()
		var unlock_id: String = unlock_ids.get(key, "")
		if unlock_id == "":
			unlock_id = _create_sanction_cell(a_ctx, cell)
			if unlock_id == "":
				return
		by_key[key] = unlock_id
		order.append(unlock_id)
		_write_sanction_cell(a_ctx, unlock_id, cell, by_key)

	_rewrite_unlock_array(a_ctx, order)


## Flatten the faction's sanction docs into grid cells, in the order the faction lists
## them. Each carries its family's column, its own tier/copy/flags, and the KEY of the
## level it continues (blank for a family head) — which is what makes `parent` a chain
## within a doc rather than something every level has to name.
func _grid_cells(a_spec: Dictionary) -> Array:
	var cells: Array = []
	for oid in a_spec["sanctions"]:
		var doc: Dictionary = registry.abilities.get(str(oid), {})
		if doc.is_empty():
			(
				report["errors"]
				. append(
					(
						"%s [%s]: sanctions names '%s' but no kind: AbilityDefinition doc of that name exists"
						% [a_spec["_doc_path"], a_spec["id"], str(oid)]
					)
				)
			)
			return []
		var parent_key: String = ""
		for level_index: int in (doc["levels"] as Array).size():
			var level: Dictionary = doc["levels"][level_index]
			var title: String = str(level["title"])
			var cell: Dictionary = level.duplicate(true)
			cell["title"] = title
			cell["column"] = int(doc["column"])
			# Which ABILITY this cell grants, and at what level. Defaults to the family's own id
			# at the cell's position — true for every family whose cells are simply its tiers.
			# A level may name its own (`ability:` / `ability_level:`) for the compound case,
			# where one cell grants a different ability from the family it sits in.
			# PASSIVITY IS THE ABILITY'S, not the cell's: every level of a passive ability is
			# passive, so it is read from the doc's top level and stamped onto each cell here.
			# Only written when the doc declares it, like every other optional key.
			if doc.has("passive"):
				cell["passive"] = bool(doc["passive"])
			cell["ability"] = str(level.get("ability", oid))
			cell["ability_level"] = int(level.get("ability_level", level_index + 1))
			cell["parent_key"] = parent_key
			cell["_doc"] = doc
			cells.append(cell)
			parent_key = title.to_snake_case()
	return cells


## unlock sub_resource id -> normalized sanction_name, read off the live instance in the
## same element order the text array declares, so the two cannot drift.
func _unlock_sub_ids(a_ctx: Ctx) -> Dictionary:
	var element_ids: Array = _unlock_array_ids(a_ctx)
	if element_ids.size() != a_ctx.inst.sanction_unlocks.size():
		return {}
	var out: Dictionary = {}
	for i in element_ids.size():
		var unlock: SanctionUnlock = a_ctx.inst.sanction_unlocks[i]
		if unlock == null or unlock.sanction == null:
			continue
		out[String(unlock.sanction.sanction_name).to_snake_case()] = element_ids[i]
	return out


## The SubResource ids named by the scene text's sanction_unlocks array, in order.
func _unlock_array_ids(a_ctx: Ctx) -> Array:
	var root: Dictionary = _section_for(a_ctx, "")
	var raw: String = a_ctx.doc.get_prop(root, "sanction_unlocks")
	var regex := RegEx.new()
	regex.compile('SubResource\\("([^"]+)"\\)')
	var ids: Array = []
	for m: RegExMatch in regex.search_all(raw):
		ids.append(m.get_string(1))
	return ids


## Create the Sanction + SanctionUnlock sub_resource pair for a cell the doc declares and
## the scene lacks. The payload is the stub, which is what an unimplemented sanction
## should be; swap `event_scene` in the scene once the real event exists.
func _create_sanction_cell(a_ctx: Ctx, a_cell: Dictionary) -> String:
	var sanction_script: String = _ensure_ext(a_ctx, "Script", SCRIPT_SANCTION)
	var unlock_script: String = _ensure_ext(a_ctx, "Script", SCRIPT_SANCTION_UNLOCK)
	var stub: String = _ensure_ext(a_ctx, "PackedScene", SANCTION_STUB_SCENE)
	var hint: String = str(a_cell["title"]).to_snake_case()
	var sanction_id: String = (
		a_ctx
		. doc
		. add_sub_resource(
			"Resource",
			"sanction_%s" % hint,
			{
				"script": 'ExtResource("%s")' % sanction_script,
				"sanction_name": TscnDoc.fmt_string(str(a_cell["title"])),
				"event_scene": 'ExtResource("%s")' % stub,
			}
		)
	)
	var unlock_id: String = (
		a_ctx
		. doc
		. add_sub_resource(
			"Resource",
			"unlock_%s" % hint,
			{
				"script": 'ExtResource("%s")' % unlock_script,
				"sanction": 'SubResource("%s")' % sanction_id,
			}
		)
	)
	a_ctx.dirty = true
	report["created"].append(
		"%s: sanction cell '%s' (payload: stub)" % [a_ctx.path, a_cell["title"]]
	)
	return unlock_id


## Write one cell's doc-governed fields onto its unlock and the Sanction it wraps.
func _write_sanction_cell(
	a_ctx: Ctx, a_unlock_id: String, a_cell: Dictionary, a_by_key: Dictionary
) -> void:
	var unlock: Dictionary = _sub_section(a_ctx, a_unlock_id)
	if unlock.is_empty():
		return
	_set_sub_prop(a_ctx, unlock, "tier", str(int(a_cell["tier"])))
	_set_sub_prop(a_ctx, unlock, "column", str(int(a_cell["column"])))
	if a_cell.has("cost"):
		_set_sub_prop(a_ctx, unlock, "dominion_cost", str(int(a_cell["cost"])))
	var parent_key: String = str(a_cell["parent_key"])
	if parent_key == "":
		# A family head. Clearing rather than skipping matters: a level promoted to the top
		# of its doc would otherwise keep pointing at the cell that used to precede it.
		if a_ctx.doc.has_prop(unlock, "parent"):
			a_ctx.doc.remove_prop(unlock, "parent")
			a_ctx.dirty = true
	elif a_by_key.has(parent_key):
		_set_sub_prop(a_ctx, unlock, "parent", 'SubResource("%s")' % a_by_key[parent_key])

	var sanction_id: String = _sub_ref(a_ctx, unlock, "sanction")
	if sanction_id == "":
		report["warnings"].append(
			"%s: unlock '%s' has no sanction sub_resource" % [a_ctx.path, a_cell["title"]]
		)
		return
	var sanction: Dictionary = _sub_section(a_ctx, sanction_id)
	if sanction.is_empty():
		return
	_set_sub_prop(a_ctx, sanction, "sanction_name", TscnDoc.fmt_string(str(a_cell["title"])))
	_set_sub_prop(
		a_ctx, sanction, "ability_id", TscnDoc.fmt_string_name(str(a_cell.get("ability", "")))
	)
	_set_sub_prop(a_ctx, sanction, "ability_level", str(int(a_cell.get("ability_level", 1))))
	if a_cell.has("description"):
		_set_sub_prop(
			a_ctx,
			sanction,
			"description",
			TscnDoc.fmt_string(_render_placeholders(str(a_cell["description"])))
		)
	if a_cell.has("verbose"):
		_set_sub_prop(
			a_ctx,
			sanction,
			"verbose_description",
			TscnDoc.fmt_string(_render_placeholders(str(a_cell["verbose"])))
		)
	if a_cell.has("cooldown"):
		_set_sub_prop(
			a_ctx, sanction, "cooldown_duration", TscnDoc.fmt_float(float(a_cell["cooldown"]))
		)
	for flag: String in ["needs_vision", "needs_target", "passive"]:
		if a_cell.has(flag):
			_set_sub_prop(a_ctx, sanction, flag, "true" if bool(a_cell[flag]) else "false")
	if a_cell.has("kill_bounty"):
		_set_sub_prop(
			a_ctx, sanction, "kill_bounty_fraction", TscnDoc.fmt_float(float(a_cell["kill_bounty"]))
		)
	if a_cell.has("payloads"):
		_set_sub_prop(a_ctx, sanction, "payloads", _payloads_literal(a_cell["payloads"]))


## The `payloads:` list as an Array[Dictionary] literal. Ids and ints only — see
## Sanction.payloads for why no PackedScene goes in here.
func _payloads_literal(a_payloads: Variant) -> String:
	var parts: Array = []
	for entry: Variant in a_payloads if a_payloads is Array else []:
		if not (entry is Dictionary):
			continue
		(
			parts
			. append(
				(
					'{ "piece": %s, "count": %d }'
					% [
						TscnDoc.fmt_string_name(str(entry.get("piece", ""))),
						maxi(1, int(entry.get("count", 1))),
					]
				)
			)
		)
	return "Array[Dictionary]([%s])" % ", ".join(parts)


## `{{ piece_id }}` -> that piece's title. Resolved HERE, at import, so the scene carries
## finished prose: the game does no lookup, and renaming a piece re-renders every sanction
## description that mentions it on the next run. Unknown ids were already rejected in
## validation, so anything still unresolved here is left alone rather than blanked.
func _render_placeholders(a_text: String) -> String:
	return SpecGenerators.render_placeholders(registry, a_text)


## The [sub_resource] section with `a_id`, or {}.
func _sub_section(a_ctx: Ctx, a_id: String) -> Dictionary:
	for section: Dictionary in a_ctx.doc.sections_of("sub_resource"):
		if str(section["attrs"].get("id", "")) == a_id:
			return section
	report["warnings"].append("%s: sub_resource '%s' not found" % [a_ctx.path, a_id])
	return {}


## The SubResource id a property points at, or "".
func _sub_ref(a_ctx: Ctx, a_section: Dictionary, a_prop: String) -> String:
	var regex := RegEx.new()
	regex.compile('SubResource\\("([^"]+)"\\)')
	var m: RegExMatch = regex.search(a_ctx.doc.get_prop(a_section, a_prop))
	return m.get_string(1) if m != null else ""


## Property write on a sub_resource, skipped when the text already says exactly that.
## Compares RAW TEXT rather than live values (as _set_prop does for nodes) because a
## sub-resource has no addressable node to read a current value back from.
func _set_sub_prop(a_ctx: Ctx, a_section: Dictionary, a_prop: String, a_raw: String) -> void:
	if a_ctx.doc.get_prop(a_section, a_prop) == a_raw:
		return
	a_ctx.doc.set_prop(a_section, a_prop, a_raw)
	a_ctx.dirty = true


## Rewrite `sanction_unlocks` to exactly the cells the docs declare, in doc order.
## FULL MODE DROPS a scene cell no doc names — the same rule every other collection
## follows, and the reason the README warns that a cell added to the scene alone
## disappears on the next import. Incremental mode keeps the strays on the end.
func _rewrite_unlock_array(a_ctx: Ctx, a_order: Array) -> void:
	var final_order: Array = a_order.duplicate()
	if mode == "incremental":
		for existing in _unlock_array_ids(a_ctx):
			if not final_order.has(existing):
				final_order.append(existing)
	var parts: Array = []
	for unlock_id in final_order:
		parts.append('SubResource("%s")' % unlock_id)
	var root: Dictionary = _section_for(a_ctx, "")
	var raw: String = (
		'Array[ExtResource("%s")]([%s])'
		% [_ensure_ext(a_ctx, "Script", SCRIPT_SANCTION_UNLOCK), ", ".join(parts)]
	)
	if a_ctx.doc.get_prop(root, "sanction_unlocks") == raw:
		return
	a_ctx.doc.set_prop(root, "sanction_unlocks", raw)
	a_ctx.dirty = true


# --------------------------------------------------------------------------- #
# Skeleton scenes (the "design a Mutalisk in markdown" flow)
# --------------------------------------------------------------------------- #
## Pieces: a bare root of the class the composition derives, carrying its id.
## _sync_composition then adds every component the doc implies, so a mobile piece, a fixture,
## a two-form piece and a bodiless one are all built the same way.
##
## A declared `scene:` wins (and is created in place when the file is missing); otherwise
## the path is inferred from the doc's faction dir + id and written back into the
## frontmatter.
func _ensure_scene(a_spec: Dictionary) -> void:
	var is_structure: bool = not a_spec.has("movement")
	if a_spec.has("scene"):
		var declared: String = _missing_declared_scene(a_spec)
		if declared != "":
			_write_skeleton(declared, _piece_root_body(a_spec))
		return

	var dir: String = "res://scenes/entities/%s" % ("structures" if is_structure else "units")
	var sub: String = _faction_subdir(a_spec)
	if sub != "":
		dir = dir.path_join(sub)
	var path: String = dir.path_join(str(a_spec["id"]) + ".tscn")
	if FileAccess.file_exists(path):
		report["errors"].append(
			(
				(
					"%s [%s]: wants a new scene at %s but the file already exists — "
					+ "link it explicitly with scene: or rename"
				)
				% [a_spec["_doc_path"], a_spec["id"], path]
			)
		)
		return
	if not _write_skeleton(path, _piece_root_body(a_spec)):
		return
	a_spec["scene"] = path
	_pending_scene_writebacks[str(a_spec["_doc_path"])] = path


## Projectiles: same mechanics, an Entity root with its hit shape, grouped into the
## faction subdir of whichever doc introduced them. Inline projectiles (hoisted
## from a weapon's `projectile: {...}` dict) have no doc of their own — their
## `_doc_path` is the OWNING piece's doc, which already has its own `scene:` —
## so the resolved path is kept in the in-memory spec only.
func _ensure_projectile_scene(a_spec: Dictionary) -> void:
	if a_spec.has("scene"):
		var declared: String = _missing_declared_scene(a_spec)
		if declared != "":
			_write_skeleton(declared, _projectile_root_body(a_spec))
		return

	var dir: String = "res://scenes/entities/projectiles"
	var sub: String = _faction_subdir(a_spec)
	if sub != "":
		dir = dir.path_join(sub)
	var path: String = dir.path_join(str(a_spec["id"]) + ".tscn")
	if FileAccess.file_exists(path):
		# An inline projectile has no frontmatter to persist scene: into, so every
		# run recomputes this same deterministic path from the (stable) projectile
		# id — a file already here just means a previous run created it. Adopt it
		# silently and let _sync_projectile update its contents like any other
		# scene, so re-running stays a no-op when nothing changed. A doc-backed
		# projectile would instead have short-circuited above via its persisted
		# scene: field, so for one of those this really is a name collision.
		if not a_spec.get("_inline", false):
			report["errors"].append(
				(
					(
						"%s [%s]: wants a new scene at %s but the file already "
						+ "exists — link it explicitly with scene: or rename"
					)
					% [a_spec["_doc_path"], a_spec["id"], path]
				)
			)
			return
		a_spec["scene"] = path
		return
	if not _write_skeleton(path, _projectile_root_body(a_spec)):
		return
	a_spec["scene"] = path
	if not a_spec.get("_inline", false):
		_pending_scene_writebacks[str(a_spec["_doc_path"])] = path


## Factions: a bare Faction-scripted root. _sync_faction then fills in
## faction_name, starting_units and sanctions exactly as it
## would for a hand-authored scene, so a new faction needs no manual scene work.
func _ensure_faction_scene(a_spec: Dictionary) -> void:
	var path: String = _missing_declared_scene(a_spec)
	if path != "":
		_write_skeleton(path, _script_root_body(a_spec, SCRIPT_FACTION, "1_fac"))


## Status effects: a bare StatusEffect-scripted root. The doc is registration
## only (it makes the id referenceable and enumerable), and there is no
## _sync_status_effect — so this skeleton is a genuinely inert placeholder, to be
## specialised in the editor by swapping in the effect's own script.
func _ensure_status_effect_scene(a_spec: Dictionary) -> void:
	var path: String = _missing_declared_scene(a_spec)
	if path != "":
		_write_skeleton(path, _script_root_body(a_spec, SCRIPT_STATUS_EFFECT, "1_fx"))


## The spec's DECLARED `scene:` path when it needs creating, else "". Nothing is
## inferred here and callers write nothing back — the doc already holds the path.
func _missing_declared_scene(a_spec: Dictionary) -> String:
	if not a_spec.has("scene"):
		return ""
	var path: String = str(a_spec["scene"])
	return "" if FileAccess.file_exists(path) else path


## Skeleton body for a piece: its derived root, its script and id, and nothing else.
func _piece_root_body(a_spec: Dictionary) -> Array:
	var script: String = SpecComposition.root_script(a_spec)
	var body: Array = [
		'[ext_resource type="Script" uid="%s" path="%s" id="1_root"]' % [_uid_for(script), script],
		"",
		'[node name="%s" type="CharacterBody3D"]' % str(a_spec["id"]).to_pascal_case(),
	]
	var props: Dictionary = SpecComposition.root_props(a_spec)
	for key: String in props:
		body.append("%s = %s" % [key, props[key]])
	body.append('script = ExtResource("1_root")')
	body.append("id = %s" % TscnDoc.fmt_string_name(str(a_spec["id"])))
	return body


## Skeleton body for an emission: an Entity root, a hit shape for the blast pass to fill (or
## the presence pass to remove from a hitscan shot), and its Ownership. Locomotion, Payload, phases
## and visuals are the sync's.
func _projectile_root_body(a_spec: Dictionary) -> Array:
	return [
		(
			'[ext_resource type="Script" uid="%s" path="%s" id="1_root"]'
			% [_uid_for(SpecComposition.SCRIPT_ENTITY), SpecComposition.SCRIPT_ENTITY]
		),
		(
			'[ext_resource type="Script" uid="%s" path="%s" id="2_own"]'
			% [_uid_for(SpecComposition.SCRIPT_OWNERSHIP), SpecComposition.SCRIPT_OWNERSHIP]
		),
		"",
		'[node name="%s" type="CharacterBody3D"]' % str(a_spec["id"]).to_pascal_case(),
		"collision_layer = 0",
		"collision_mask = 2",
		'script = ExtResource("1_root")',
		"",
		'[node name="HitShape" type="CollisionShape3D" parent="."]',
		"",
		'[node name="Ownership" type="Node" parent="."]',
		'script = ExtResource("2_own")',
	]


## Skeleton body for the kinds whose root is a plain Node carrying a script
## (factions, status effects) rather than an inherited base scene.
func _script_root_body(a_spec: Dictionary, a_script: String, a_res_id: String) -> Array:
	return [
		(
			'[ext_resource type="Script" uid="%s" path="%s" id="%s"]'
			% [_uid_for(a_script), a_script, a_res_id]
		),
		"",
		'[node name="%s" type="Node"]' % str(a_spec["id"]).to_pascal_case(),
		'script = ExtResource("%s")' % a_res_id,
	]


## The scene subdir for the faction dir a doc lives in ("" for factionless docs).
func _faction_subdir(a_spec: Dictionary) -> String:
	for doc_dir in DOC_DIR_TO_SCENE_SUB:
		if str(a_spec["_doc_path"]).contains("/factions/%s/" % doc_dir):
			return DOC_DIR_TO_SCENE_SUB[doc_dir]
	return ""


## Writes one skeleton .tscn: mints a UID, wraps `a_body` (the sections below
## the header) in a gd_scene header, creates any missing directories, and
## registers the UID so other scenes can reference it by uid immediately.
## Reports the creation and returns true when the file lands.
func _write_skeleton(a_path: String, a_body: Array) -> bool:
	var uid_int: int = ResourceUID.create_id()
	var uid: String = ResourceUID.id_to_text(uid_int)
	var lines: Array = ['[gd_scene load_steps=2 format=3 uid="%s"]' % uid, ""]
	lines.append_array(a_body)
	lines.append("")
	DirAccess.make_dir_recursive_absolute(a_path.get_base_dir())
	var f: FileAccess = FileAccess.open(a_path, FileAccess.WRITE)
	if f == null:
		report["errors"].append("cannot create %s" % a_path)
		return false
	f.store_string("\n".join(lines))
	f.close()
	if ResourceUID.has_id(uid_int):
		ResourceUID.set_id(uid_int, a_path)
	else:
		ResourceUID.add_id(uid_int, a_path)
	report["created"].append(a_path)
	return true


# --------------------------------------------------------------------------- #
# The gdd docs (the ONE pass that writes to them)
# --------------------------------------------------------------------------- #
## Rewrites every spec doc's frontmatter: the canonical key order, plus a `scene:`
## line for any doc whose skeleton was just inferred.
##
## ONE VISIT PER DOC, deliberately. gdd/ is an Obsidian vault under Sync, so the importer
## rewriting a doc races the editor exactly as the task file does — and a second visit
## doubles that window for no gain. Docs whose bytes do not change are not written at all,
## which is what makes a second import run a no-op here as it is everywhere else.
func _rewrite_docs() -> void:
	var seen: Dictionary = {}
	for id in registry.specs:
		var spec: Dictionary = registry.specs[id]
		# An INLINE emission has no doc of its own — its `_doc_path` is the piece that
		# declares it, which is rewritten under its own id.
		if bool(spec.get("_inline", false)):
			continue
		var path: String = str(spec["_doc_path"])
		if seen.has(path):
			continue
		seen[path] = true
		_rewrite_doc(path, str(_pending_scene_writebacks.get(path, "")))


## One doc: insert the resolved `scene:` when there is one, put the frontmatter in
## canonical order, and save only if that changed any bytes.
func _rewrite_doc(a_path: String, a_scene_path: String) -> void:
	var text: String = FileAccess.get_file_as_string(a_path)
	if text.is_empty():
		report["warnings"].append("cannot read %s" % a_path)
		return
	var updated: String = text
	if not a_scene_path.is_empty():
		updated = _with_scene_line(a_path, updated, a_scene_path)
	updated = SpecSchema.reorder_frontmatter(updated)
	if updated == text:
		return
	var f: FileAccess = FileAccess.open(a_path, FileAccess.WRITE)
	if f == null:
		report["warnings"].append("cannot write back to %s" % a_path)
		return
	f.store_string(updated)
	f.close()
	report["changed"].append(a_path)


## Inserts `scene: <path>` into the doc's frontmatter, after the title: line (or the
## kind: line when the doc has no title). The reorder pass then puts it where the
## canonical order wants it; this only has to land somewhere legal.
func _with_scene_line(a_path: String, a_text: String, a_scene_path: String) -> String:
	var lines: PackedStringArray = a_text.split("\n")
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
		if line.begins_with("title:") or (line.begins_with("kind:") and insert_at == -1):
			insert_at = i + 1
	if insert_at == -1:
		report["warnings"].append("%s: could not write scene: back into frontmatter" % a_path)
		return a_text
	var out: Array = []
	for i in lines.size():
		if i == insert_at:
			out.append("scene: %s" % a_scene_path)
		out.append(lines[i])
	return "\n".join(out)


# --------------------------------------------------------------------------- #
# Generated visual defaults
# --------------------------------------------------------------------------- #
## Fills the visual slots a scene has left empty — a placeholder model, a selection shape,
## an HP bar — from what the piece IS and how big its model measures.
##
## Unlike every other _sync_* above, these are NOT doc-governed: the doc says nothing about
## them, and the source of truth is the art. What that costs, and why a baked value is
## never overwritten once present, is visual_defaults.gd's header; this half only writes.
func _sync_piece_visuals(a_ctx: Ctx, a_spec: Dictionary) -> void:
	var visual_class: int = VisualDefaults.classify_piece(
		_piece_frame_type(a_ctx, a_spec),
		_piece_movement_mode(a_ctx, a_spec),
		a_ctx.inst.has_node("Structure")
	)
	var footprint: Vector2i = _piece_footprint(a_ctx, a_spec)
	var measurement: Dictionary = VisualMeasure.measure(a_ctx.inst)
	if SpecSchema.wants_no_visual(a_spec):
		# The `has_mesh_visual` waiver REMOVES as well as refuses — the MeshVisual itself, and
		# with it any model. A pass that only declines converges from one direction: clearing
		# the key puts a model back, but adding it would leave the old one in place forever and
		# the scene would stop meaning what the doc says.
		_remove_component(a_ctx, VisualMeasure.MESH_VISUAL_PATH)
	elif VisualMeasure.needs_placeholder_mesh(a_ctx.inst, measurement):
		measurement = _bake_placeholder_mesh(
			a_ctx,
			visual_class,
			footprint,
			VisualMeasure.MESH_VISUAL_PATH,
			VisualMeasure.PLACEHOLDER_NODE
		)
	_bake_selection_shape(a_ctx, visual_class, measurement, footprint)
	_bake_hurtbox(
		a_ctx,
		visual_class,
		measurement,
		footprint,
		a_spec.has("footprint") or a_ctx.inst.has_node("Structure")
	)
	_bake_hp_bar(a_ctx, measurement)
	_keep_hurtbox_editable(a_ctx)


## A projectile's two visual states. The in-flight mesh is unconditional — a projectile
## nobody can see is never intentional. The post-impact one is EARNED: it is generated only
## where the projectile actually persists past the hit or carries a blast, because a bullet
## that vanishes on contact wanting no impact puff is a legitimate authoring choice and not
## a gap. Projectiles have no MeshVisual and no ground to stand on, so both hang off the
## root unlifted. A state already filled by art of another kind — a tracer beam, an impact
## particle effect — wants no stand-in either.
func _sync_projectile_visuals(a_ctx: Ctx, a_spec: Dictionary) -> void:
	if SpecSchema.wants_no_visual(a_spec):
		for node_name: String in [
			VisualMeasure.IN_FLIGHT_MESH_NODE, VisualMeasure.POST_IMPACT_MESH_NODE
		]:
			_remove_component(a_ctx, node_name)
		return
	var visual_class: int = VisualDefaults.classify_projectile(EmissionPhases.first_motion(a_spec))
	if (
		a_ctx.inst.get_node_or_null(VisualMeasure.IN_FLIGHT_MESH_NODE) == null
		and not VisualMeasure.has_tracer_beam(a_ctx.inst)
	):
		_bake_placeholder_mesh(
			a_ctx, visual_class, Vector2i.ONE, ".", VisualMeasure.IN_FLIGHT_MESH_NODE
		)
	if (
		_projectile_persists(a_ctx, a_spec)
		and a_ctx.inst.get_node_or_null(VisualMeasure.POST_IMPACT_MESH_NODE) == null
		and not VisualMeasure.has_impact_effect(a_ctx.inst)
	):
		_bake_placeholder_mesh(
			a_ctx,
			visual_class,
			Vector2i.ONE,
			".",
			VisualMeasure.POST_IMPACT_MESH_NODE,
			VisualDefaults.impact_burst_mesh()
		)


## Adds the class's stand-in model and returns the measurement it implies, so the selection
## shape and HP bar can be sized against a model that is not on disk yet.
##
## Always a NEW SIBLING node, never a re-instance of an inherited `Model`: Godot cannot
## repoint an inherited scene instance at a different PackedScene, and doing so leaks the
## node and segfaults the process during engine teardown (see CLAUDE.md). Grounded pieces
## are lifted half their height so they stand ON the ground — every Godot primitive is
## centred on its own origin — and projectiles are not, having no ground to stand on.
## `a_descriptor` overrides the class's own mesh, for the one slot that does not want it —
## a projectile's impact burst, which must not look like the shell that caused it.
func _bake_placeholder_mesh(
	a_ctx: Ctx,
	a_visual_class: int,
	a_footprint: Vector2i,
	a_parent_path: String,
	a_node_name: String,
	a_descriptor: Dictionary = {}
) -> Dictionary:
	var empty: Dictionary = {
		"has_mesh": false,
		"mesh_count": 0,
		"size": Vector3.ZERO,
		"top": 0.0,
		"is_placeholder": false,
	}
	if a_parent_path != "." and a_ctx.inst.get_node_or_null(a_parent_path) == null:
		report["warnings"].append(
			"%s: no %s node — cannot add a placeholder model" % [a_ctx.path, a_parent_path]
		)
		return empty
	var descriptor: Dictionary = (
		a_descriptor
		if not a_descriptor.is_empty()
		else VisualDefaults.placeholder_mesh(a_visual_class, a_footprint)
	)
	var size: Vector3 = VisualDefaults.placeholder_size(descriptor)
	var is_grounded: bool = not VisualDefaults.is_projectile_class(a_visual_class)
	var mesh_id: String = a_ctx.doc.add_sub_resource(
		String(descriptor["type"]), "placeholder", _raw_props(descriptor["props"])
	)
	var props: Dictionary = {
		"mesh": 'SubResource("%s")' % mesh_id,
		"metadata/%s" % VisualMeasure.STAMP_MESH:
		TscnDoc.fmt_string(String(VisualDefaults.CLASS_NAMES[a_visual_class])),
	}
	if is_grounded:
		props["transform"] = TscnDoc.fmt_transform(
			Transform3D(Basis.IDENTITY, Vector3(0.0, size.y / 2.0, 0.0))
		)
	a_ctx.doc.add_node(
		[["name", a_node_name], ["type", "MeshInstance3D"], ["parent", a_parent_path]], props
	)
	var full_path: String = (
		a_node_name if a_parent_path == "." else "%s/%s" % [a_parent_path, a_node_name]
	)
	a_ctx.created_nodes[full_path] = true
	a_ctx.dirty = true
	return {
		"has_mesh": true,
		"mesh_count": 1,
		"size": size,
		"top": size.y if is_grounded else size.y / 2.0,
		"is_placeholder": true,
	}


## The click target. Skipped entirely unless the slot is CLEARED — a scene that already
## carries a shape carries somebody's decision, whether they typed it or accepted ours.
func _bake_selection_shape(
	a_ctx: Ctx, a_visual_class: int, a_measurement: Dictionary, a_footprint: Vector2i
) -> void:
	if not _wants_bake(
		VisualMeasure.selection_is_cleared(a_ctx.inst), VisualMeasure.selection_is_owned(a_ctx.inst)
	):
		return
	var descriptor: Dictionary = VisualDefaults.selection_shape(
		a_visual_class, a_measurement["size"], a_footprint
	)
	var section: Dictionary = _section_for(a_ctx, VisualMeasure.SELECTION_SHAPE_PATH)
	if section.is_empty():
		report["warnings"].append(
			(
				"%s: no %s node — cannot size selection"
				% [a_ctx.path, VisualMeasure.SELECTION_SHAPE_PATH]
			)
		)
		return
	_drop_orphan_shape(a_ctx, section)
	var shape_id: String = a_ctx.doc.add_sub_resource(
		String(descriptor["type"]), "selection", _raw_props(descriptor["props"])
	)
	a_ctx.doc.set_prop(section, "shape", 'SubResource("%s")' % shape_id)
	a_ctx.doc.set_prop(
		section,
		"metadata/%s" % VisualMeasure.STAMP_SELECTION,
		TscnDoc.fmt_string(String(descriptor["type"]))
	)
	a_ctx.dirty = true


## The hurtbox: its shape, and its height above the origin so it stands on the piece's base.
## ONLY for a hurtbox with no shape at all. Unlike the other visual slots, `--rebake-visuals`
## does not widen this: an existing hurtbox shape is never replaced, whoever put it there
## (Alex, 2026-10-06).
func _bake_hurtbox(
	a_ctx: Ctx,
	a_visual_class: int,
	a_measurement: Dictionary,
	a_footprint: Vector2i,
	a_is_fixture: bool
) -> void:
	if not VisualMeasure.hurtbox_is_cleared(a_ctx.inst):
		return
	var descriptor: Dictionary = VisualDefaults.hurtbox_shape(
		a_visual_class,
		a_measurement["size"],
		float(a_measurement["top"]),
		a_footprint,
		a_is_fixture
	)
	var section: Dictionary = _section_for(a_ctx, VisualMeasure.HURTBOX_SHAPE_PATH)
	if section.is_empty():
		report["warnings"].append(
			"%s: no %s node — cannot fit a hurtbox" % [a_ctx.path, VisualMeasure.HURTBOX_SHAPE_PATH]
		)
		return
	_drop_orphan_shape(a_ctx, section)
	var shape_id: String = a_ctx.doc.add_sub_resource(
		String(descriptor["type"]), "hurtbox", _raw_props(descriptor["props"])
	)
	a_ctx.doc.set_prop(section, "shape", 'SubResource("%s")' % shape_id)
	a_ctx.doc.set_prop(
		section,
		"transform",
		TscnDoc.fmt_transform(
			Transform3D(Basis.IDENTITY, Vector3(0.0, float(descriptor["center_y"]), 0.0))
		)
	)
	a_ctx.doc.set_prop(
		section,
		"metadata/%s" % VisualMeasure.STAMP_HURTBOX,
		TscnDoc.fmt_string(String(descriptor["type"]))
	)
	a_ctx.dirty = true


## A fitted hurtbox overrides a node INSIDE the Hurtbox component instance, and the editor drops
## such an override on its next save unless the scene marks the instance editable — it did, to
## the Matilda, on the first save after the fit. Asked of every scene carrying one, not only on
## the run that fits it, so a scene fitted before this existed is repaired too.
func _keep_hurtbox_editable(a_ctx: Ctx) -> void:
	if a_ctx.doc.find_node(VisualMeasure.HURTBOX_SHAPE_PATH).is_empty():
		return
	var parent: String = VisualMeasure.HURTBOX_SHAPE_PATH.get_base_dir()
	if a_ctx.doc.sections_of("editable").any(
		func(section: Dictionary) -> bool: return section["attrs"].get("path", "") == parent
	):
		return
	a_ctx.doc.ensure_editable(parent)
	a_ctx.dirty = true


## The HP bar's size and position. Skipped unless the slot is CLEARED (an origin of exactly
## zero — see VisualMeasure.hp_bar_is_cleared).
##
## The scene stores a Sprite3D SCALE, not a width, so the world width the rules produce is
## converted here — at the boundary, from the sprite's own texture, expressed once. Only
## the x scale and the origin are written: y and z carry the bar's authored thickness and
## are none of this pass's business.
func _bake_hp_bar(a_ctx: Ctx, a_measurement: Dictionary) -> void:
	if not _wants_bake(
		VisualMeasure.hp_bar_is_cleared(a_ctx.inst), VisualMeasure.hp_bar_is_owned(a_ctx.inst)
	):
		return
	var bar: Node3D = a_ctx.inst.get_node_or_null(VisualMeasure.HP_BAR_PATH) as Node3D
	var scale_per_unit: float = VisualMeasure.hp_bar_scale_per_world_unit(a_ctx.inst)
	if bar == null or scale_per_unit <= 0.0:
		report["warnings"].append(
			"%s: no measurable HP bar fill — bar left as authored" % a_ctx.path
		)
		return
	var width: float = VisualDefaults.hp_bar_width(VisualMeasure.model_width(a_measurement))
	var authored: Vector3 = bar.transform.basis.get_scale()
	var basis: Basis = Basis.from_scale(Vector3(width * scale_per_unit, authored.y, authored.z))
	var origin: Vector3 = VisualDefaults.hp_bar_origin(float(a_measurement["top"]))
	var section: Dictionary = _section_for(a_ctx, VisualMeasure.HP_BAR_PATH)
	if section.is_empty():
		return
	a_ctx.doc.set_prop(section, "transform", TscnDoc.fmt_transform(Transform3D(basis, origin)))
	a_ctx.doc.set_prop(
		section, "metadata/%s" % VisualMeasure.STAMP_HP_BAR, TscnDoc.fmt_float(width)
	)
	a_ctx.dirty = true


## Whether a visual slot should be written. Normally only an EMPTY one is — a value already
## in a scene is the author's, and clearing it is the only thing that asks for a fresh bake.
## `rebake_visuals` widens that to any value this importer did not put there, which is the
## migration for scenes that predate the pass; a value it DID bake, edited since, stays put
## either way.
func _wants_bake(a_is_cleared: bool, a_is_owned: bool) -> bool:
	return a_is_cleared or (rebake_visuals and not a_is_owned)


## Drops the sub_resource a node's `shape` points at when this file owns it outright and
## nothing else references it, so a rebake REPLACES the old shape rather than leaving it
## behind to inflate load_steps. A shape shared with another node is left alone — retyping
## one node must never silently reshape another.
func _drop_orphan_shape(a_ctx: Ctx, a_section: Dictionary) -> void:
	var raw: String = a_ctx.doc.get_prop(a_section, "shape")
	var regex: RegEx = RegEx.new()
	regex.compile('^SubResource\\("([^"]+)"\\)$')
	var match_result: RegExMatch = regex.search(raw)
	if match_result != null and _sub_resource_ref_count(a_ctx, match_result.get_string(1)) == 1:
		a_ctx.doc.remove_sub_resource(match_result.get_string(1))
		a_ctx.dirty = true


## Descriptor props (typed values, from the pure rules module) -> .tscn literals.
static func _raw_props(props: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: String in props:
		out[key] = TscnDoc.fmt_value(props[key])
	return out


## The spec's value where the doc names one, else the scene's — the doc's write has not
## reached the live instance yet, so classifying off the instance alone would use the
## piece's PREVIOUS frame or mode on the run that changed it.
func _piece_frame_type(a_ctx: Ctx, a_spec: Dictionary) -> int:
	if a_spec.has("frame"):
		return Defense.FrameType[str(a_spec["frame"])]
	var defense: Node = a_ctx.inst.get_node_or_null("Defense")
	return defense.frame_type if defense != null else Defense.FrameType.BIO


func _piece_movement_mode(a_ctx: Ctx, a_spec: Dictionary) -> int:
	if a_spec.get("aerial") is Dictionary and (a_spec["aerial"] as Dictionary).has("mode"):
		return Movement.Mode[str(a_spec["aerial"]["mode"])]
	var aerial: Aerial = a_ctx.inst.get_node_or_null("Aerial") as Aerial
	return aerial.mode if aerial != null else Movement.Mode.GROUNDED


func _piece_footprint(a_ctx: Ctx, a_spec: Dictionary) -> Vector2i:
	if a_spec.has("footprint"):
		return Vector2i(int(a_spec["footprint"][0]), int(a_spec["footprint"][1]))
	var structure: Node = a_ctx.inst.get_node_or_null("Structure")
	return structure.dimensions if structure != null else Vector2i.ONE


## Whether the projectile is still THERE after it lands — the condition that earns it a
## post-impact visual. Either it lingers as a damage field, or it went off with a blast
## wide enough to be worth showing.
func _projectile_persists(_a_ctx: Ctx, a_spec: Dictionary) -> bool:
	if a_spec.has("blast") and float(a_spec["blast"]) > 0.0:
		return true
	var later: Array[Dictionary] = EmissionPhases.expand(a_spec).slice(1)
	return later.any(
		func(p: Dictionary) -> bool:
			return (
				is_inf(float(p["lifespan_seconds"]))
				or TimeUtils.ticks_from_seconds(float(p["lifespan_seconds"])) > 1
			)
	)
