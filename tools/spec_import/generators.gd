class_name SpecGenerators
extends RefCounted

## Writes the generated artifacts derived from the spec registry:
##   scripts/generated/entity_ids.gd         — EntityIds consts (pieces)
##   scripts/generated/status_effect_ids.gd  — StatusEffectIds consts
##   resources/generated/technology.json     — cost / build time / requires
##   resources/generated/tools.json          — build/train tool registry
##   resources/generated/abilities.json      — the ability definitions
##   resources/generated/upgrades.json       — the upgrade definitions (what each one modifies)
##   resources/generated/debug_roster.json   — every placeable piece, for the debug spawner
##   resources/generated/families.json       — piece families and their members' template data
##   resources/generated/shapes/<id>.tres    — the shape library (see generate_shapes)
## Everything is emitted in alphabetical id order (per user convention — ids are
## named so alphabetical grouping is meaningful). All files carry AUTO-GENERATED
## headers; hand edits belong in the gdd docs, not here.

const SpecSchema := preload("res://tools/spec_import/schema.gd")

const ENTITY_IDS_PATH: String = "res://scripts/generated/entity_ids.gd"
const STATUS_EFFECT_IDS_PATH: String = "res://scripts/generated/status_effect_ids.gd"
const TECHNOLOGY_PATH: String = "res://resources/generated/technology.json"
const TOOLS_PATH: String = "res://resources/generated/tools.json"
const ABILITIES_PATH: String = "res://resources/generated/abilities.json"
const UPGRADES_PATH: String = "res://resources/generated/upgrades.json"
const DEBUG_ROSTER_PATH: String = "res://resources/generated/debug_roster.json"
const FAMILIES_PATH: String = "res://resources/generated/families.json"
## Where the debug roster looks for piece scenes that no spec names.
const ENTITY_SCENES_DIR: String = "res://scenes/entities"
## A scene folder's faction code → the faction name (a ControlBinding.Faction member, lower
## case). The fallback for a piece whose doc names no faction, and the only source for a scene
## no doc names — see gdd/systems/ux/ui/debug-mode.md §The piece spawner.
const FOLDER_FACTIONS: Dictionary = {
	"nt": "neutral",
	"tc": "technocracy",
	"an": "anarchists",
	"cl": "colonial",
	"lb": "libertarian",
	"mr": "marxist",
	"th": "theocratic",
}
## The faction a scene is listed under when its folder names none.
const DEFAULT_ROSTER_FACTION: String = "neutral"
const SHAPES_DIR: String = "res://resources/generated/shapes"


## Writes every artifact. Returns the list of written paths.
static func generate_all(registry: RefCounted) -> Array:
	var written: Array = []
	written.append(_write(ENTITY_IDS_PATH, entity_ids_text(registry)))
	written.append(_write(STATUS_EFFECT_IDS_PATH, status_effect_ids_text(registry)))
	written.append(_write(TECHNOLOGY_PATH, technology_json(registry)))
	written.append(_write(TOOLS_PATH, tools_json(registry)))
	written.append(_write(ABILITIES_PATH, abilities_json(registry)))
	written.append(_write(UPGRADES_PATH, upgrades_json(registry)))
	written.append(_write(DEBUG_ROSTER_PATH, debug_roster_json(registry)))
	written.append(_write(FAMILIES_PATH, families_json(registry)))
	return written


# --------------------------------------------------------------------------- #
# The shape library
# --------------------------------------------------------------------------- #
## The generated resource a shape-library id loads as.
static func shape_path(id: String) -> String:
	return "%s/%s.tres" % [SHAPES_DIR, id]


## Writes one CylinderShape3D resource per shape-library doc, and deletes any generated shape
## whose doc is gone. Returns {"written": [paths], "removed": [paths]}.
##
## Separate from generate_all because it has to run BEFORE the scene sync, not after: the
## sync points range nodes at these files and then instantiates the scenes it touched, and a
## scene naming a resource that does not exist yet fails to load.
static func generate_shapes(registry: RefCounted) -> Dictionary:
	var written: Array = []
	var ids: Array = registry.shapes.keys()
	ids.sort()
	for id: String in ids:
		written.append(_write(shape_path(id), shape_tres_text(registry.shapes[id])))
	var removed: Array = []
	var dir: DirAccess = DirAccess.open(SHAPES_DIR)
	if dir != null:
		for file: String in dir.get_files():
			if file.get_extension() == "tres" and not registry.shapes.has(file.get_basename()):
				dir.remove(file)
				removed.append("%s/%s" % [SHAPES_DIR, file])
	return {"written": written, "removed": removed}


## The shape's class, as its doc's `kind:` names it.
static func shape_class(spec: Dictionary) -> String:
	return str(spec.get("kind", "CylinderShape3D"))


static func shape_tres_text(spec: Dictionary) -> String:
	var props: String = "radius = %s\n" % TscnDoc.fmt_float(float(spec["radius"]))
	if shape_class(spec) == "CylinderShape3D":
		props = (
			(
				"height = %s\n"
				% TscnDoc.fmt_float(float(spec.get("height", SpecSceneSync.SHAPE_HEIGHT)))
			)
			+ props
		)
	return (
		'[gd_resource type="%s" format=3]\n\n' % shape_class(spec)
		+ "; AUTO-GENERATED by tools/spec_import from %s.\n" % spec["_doc_path"]
		+ "; Do not edit by hand — edit the gdd doc and re-run the importer.\n\n"
		+ "[resource]\n"
		+ props
	)


# --------------------------------------------------------------------------- #
# What a run REMOVES
# --------------------------------------------------------------------------- #
## The id const files, paired with the registry collection each is generated from and the
## `class_name` hand-written code reaches them through.
const ID_FILES: Array[Array] = [
	[ENTITY_IDS_PATH, "EntityIds", "pieces"],
	[STATUS_EFFECT_IDS_PATH, "StatusEffectIds", "status_effects"],
]


## The ids a generated const file declares TODAY, as {id: CONST_NAME}.
##
## Read back out of the FILE rather than remembered from a previous run, because the file on
## disk is what hand-written code last compiled against — and that, not some earlier
## registry, is what a removal breaks. A file that does not exist yet declares nothing, so a
## first run removes nothing.
static func declared_ids(path: String) -> Dictionary:
	var out: Dictionary = {}
	if not FileAccess.file_exists(path):
		return out
	var regex := RegEx.new()
	regex.compile('^const\\s+([A-Za-z0-9_]+)\\s*:=\\s*&"([^"]+)"')
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		var m: RegExMatch = regex.search(line)
		if m != null:
			out[m.get_string(2)] = m.get_string(1)
	return out


## Every const this run is about to DROP, as one entry per id file:
## {"path": String, "scope": String, "ids": Array, "consts": Array}, both lists sorted and
## parallel. Files that lose nothing are omitted, so an ordinary run reports nothing.
##
## WHY THIS EXISTS. The generators rebuild the id files WHOLESALE from the registry, so a
## piece whose doc is gone simply stops being emitted — which is the removal behaviour we
## want, and which on its own is completely silent. But a dropped const is not a warning in
## the code that referenced it: it is a PARSE error in every file still naming it, and a
## test file that does not parse is dropped from the GUT run while the run still reports
## green (CLAUDE.md §A skipped test file is invisible). Four files, two of them tests, sat
## broken exactly that way after `tc_barracks`, `tc_lab`, `tc_armory` and `kamikaze` left
## the docs. So the run says what it took away, while somebody is still looking at it.
##
## MUST BE CALLED BEFORE `generate_all`, which overwrites the evidence.
static func pending_removals(registry: RefCounted) -> Array:
	var out: Array = []
	for spec: Array in ID_FILES:
		var kept: Dictionary = {}
		# Registry keys may be StringName; the file gives Strings. Normalise rather than
		# relying on the two hashing alike.
		for id: Variant in (registry.get(spec[2]) as Dictionary).keys():
			kept[String(id)] = true
		var removal: Dictionary = removal_for(spec[0], spec[1], kept)
		if not removal.is_empty():
			out.append(removal)
	return out


## The removal one id file is facing: what `path` declares today that `a_kept` — the ids the
## docs still define, as a set of Strings — no longer does. `{}` when it loses nothing.
##
## Split out from `pending_removals` so the diff can be exercised against a scratch file;
## the caller supplies the paths, which are otherwise fixed by ID_FILES.
static func removal_for(path: String, scope: String, a_kept: Dictionary) -> Dictionary:
	var declared: Dictionary = declared_ids(path)
	var gone: Array = []
	for id: String in declared:
		if not a_kept.has(id):
			gone.append(id)
	if gone.is_empty():
		return {}
	gone.sort()
	var consts: Array = []
	for id: String in gone:
		consts.append(declared[id])
	return {"path": path, "scope": scope, "ids": gone, "consts": consts}


static func entity_ids_text(registry: RefCounted) -> String:
	var out: String = _gd_header("game-piece id constants")
	out += "class_name EntityIds\n\n"
	out += "## One StringName const per game piece defined in the gdd docs. Reference\n"
	out += "## pieces through these in hand-written code (typo-safe, autocompletes);\n"
	out += "## scenes and data files store the raw StringName.\n\n"
	var ids: Array = registry.pieces.keys()
	ids.sort()
	for id in ids:
		out += 'const %s := &"%s"\n' % [String(id).to_snake_case().to_upper(), id]
	return out


static func status_effect_ids_text(registry: RefCounted) -> String:
	var out: String = _gd_header("status-effect id constants")
	out += "class_name StatusEffectIds\n\n"
	out += "## One StringName const per registered status effect (kind: status_effect\n"
	out += "## docs). The id maps to the effect scene referenced by projectiles.\n\n"
	var ids: Array = registry.status_effects.keys()
	ids.sort()
	for id in ids:
		out += 'const %s := &"%s"\n' % [String(id).to_snake_case().to_upper(), id]
	if ids.is_empty():
		out += "# (no status effects registered yet)\n"
	return out


## {id: {"cost": {...}, "build_time_ticks": int, "requires": [...]}} for every
## piece with economy data (a cost: key). Pieces without cost are not buildable.
static func technology_json(registry: RefCounted) -> String:
	# Upgrades are priced, timed and gated exactly as pieces are — a research is a purchase in
	# the same queue — so they share the table. Ids share one namespace, so they cannot collide.
	var ids: Array = registry.pieces.keys() + registry.upgrades.keys()
	ids.sort()
	var table: Dictionary = {}
	for id in ids:
		var spec: Dictionary = (
			registry.pieces[id] if registry.pieces.has(id) else registry.upgrades[id]
		)
		if not spec.has("cost"):
			continue
		var cost: Dictionary = spec["cost"] if spec["cost"] is Dictionary else {}
		var requires: Array = []
		for r in spec.get("requires", []):
			requires.append(str(r))
		table[id] = {
			"cost":
			{
				"energy": int(cost.get("energy", 0)),
				"infrastructure": int(cost.get("infrastructure", 0)),
				"dominion": int(cost.get("dominion", 0)),
			},
			"build_time_ticks": TimeUtils.ticks_from_seconds(float(spec.get("build_time", 0))),
			"requires": requires,
		}
	return (
		_json_header("technology (cost / build time / prerequisites)")
		+ JSON.stringify(table, "\t")
		+ "\n"
	)


## {command_name: {"id", "scene", "label", "grid", "context", "factions",
## "tooltip", "verbose"}} for every piece with a ui: key. context is how the piece is
## acquired — see _is_built. `label` is the doc's `title`; the two tooltip tiers are
## synthesized from the doc's stats unless `ui.tooltip` / `ui.verbose` override them
## (spec-importer.md).
static func tools_json(registry: RefCounted) -> String:
	return (
		_json_header("build/train tool registry")
		+ JSON.stringify(tools_table(registry), "\t")
		+ "\n"
	)


## {"families": {family: [member ids]}, "templates": {member id: {...}}} for every piece
## naming a `family:`. A member is a TEMPLATE — a piece whose own price, build time and
## infrastructure are what a DIFFERENT piece takes when it is built from it (`variants:`), or what
## converting it costs — so its numbers live here, readable without instantiating its scene, and
## its scene's `infrastructure` stays 0 (see SpecSceneSync._sync_root_properties). Read through
## PieceFamilies. Members are alphabetical, like every generated list.
static func families_json(registry: RefCounted) -> String:
	var ids: Array = registry.pieces.keys()
	ids.sort()
	var families: Dictionary = {}
	var templates: Dictionary = {}
	for id in ids:
		var spec: Dictionary = registry.pieces[id]
		if not spec.has("family") or not spec.has("scene"):
			continue
		var family: String = str(spec["family"])
		if not families.has(family):
			families[family] = []
		families[family].append(str(id))
		var cost: Dictionary = spec["cost"] if spec["cost"] is Dictionary else {}
		templates[str(id)] = {
			"family": family,
			"scene": str(spec["scene"]),
			"title": piece_title(spec),
			"footprint": [int(spec["footprint"][0]), int(spec["footprint"][1])],
			"hp": float(spec.get("hp", 0)),
			"energy_cost": int(cost.get("energy", 0)),
			"build_time_ticks": TimeUtils.ticks_from_seconds(float(spec.get("build_time", 0))),
			"infrastructure": int(spec.get("infrastructure", 0)),
		}
	return (
		_json_header("piece families")
		+ JSON.stringify({"families": families, "templates": templates}, "\t")
		+ "\n"
	)


## The tools.json table itself. `require_scene` false keeps pieces the scene sync has yet to
## give a scene, which will have a button once it has — the grid review wants those too.
static func tools_table(registry: RefCounted, require_scene: bool = true) -> Dictionary:
	var ids: Array = registry.pieces.keys()
	ids.sort()
	var producers: Dictionary = _producers_by_trainee(registry)
	var table: Dictionary = {}
	for id in ids:
		var spec: Dictionary = registry.pieces[id]
		if not spec.has("ui") or not (spec["ui"] is Dictionary):
			continue
		var ui: Dictionary = spec["ui"]
		if require_scene and not spec.has("scene"):
			continue  # a tool needs a scene to place/train
		var factions: Array = []
		for f in ui.get("factions", []):
			factions.append(str(f))
		table["command_tool_%s" % id] = {
			"id": id,
			"scene": str(spec.get("scene", "")),
			"label": piece_title(spec),
			"grid": [int(ui["grid"][0]), int(ui["grid"][1])] if ui.has("grid") else [0, 0],
			"context": "BUILD" if _is_built(spec, producers) else "TRAIN",
			"factions": factions,
			"tooltip": str(ui.get("tooltip", tool_tooltip(spec, _is_built(spec, producers)))),
			"verbose": str(ui.get("verbose", tool_verbose_tooltip(registry, spec))),
			"producers": producers.get(id, []),
			# A PRODUCER's cell in row 0 of the PRODUCTION card — the radio button that picks whose
			# training the card is showing. Empty for everything that is not a producer.
			"context_grid": _ability_grid(spec, "context_grid"),
			"needs_docking": _needs_docking(spec),
		}
		if spec.has("variants"):
			var variant_ids: Array = []
			for variant: Variant in spec["variants"]:
				variant_ids.append(str(variant))
			table["command_tool_%s" % id]["variants"] = variant_ids
	# RESEARCH buttons. An upgrade is a TRAIN tool with no scene: it sits on its researching
	# structure's production card, and finishing it spawns nothing (Production._complete_research).
	var upgrade_ids: Array = registry.upgrades.keys()
	upgrade_ids.sort()
	for id in upgrade_ids:
		var spec: Dictionary = registry.upgrades[id]
		if not (spec.get("ui") is Dictionary):
			continue
		var ui: Dictionary = spec["ui"]
		var factions: Array = []
		for f in ui.get("factions", []):
			factions.append(str(f))
		table["command_tool_%s" % id] = {
			"id": id,
			"scene": "",
			"upgrade": true,
			"label": piece_title(spec),
			"grid": [int(ui["grid"][0]), int(ui["grid"][1])] if ui.has("grid") else [0, 0],
			"context": "TRAIN",
			"factions": factions,
			"tooltip": str(ui.get("tooltip", upgrade_tooltip(spec))),
			"verbose": str(ui.get("verbose", upgrade_verbose_tooltip(registry, spec))),
			"producers": producers.get(id, []),
			"context_grid": [],
			"needs_docking": false,
		}
	return table


## Every pair of doc-authored buttons that would share a grid cell while both can be on
## screen — tools and producer-context buttons, reviewed by ControlBinding.grid_collisions,
## the same rule the HUD's collision test applies. Built from THIS run's docs, never from
## the Tool registry, which still holds the previous run's tools.json. One readable line per
## collision naming the docs to edit; empty when the grid is clean.
##
## Verbs and ability buttons are not reviewed here: verbs are authored in code, and neither
## can share a context with a tool (ACT against BUILD/TRAIN). tests/test_ControlBinding
## reviews the whole grid, those included.
static func grid_collisions(registry: RefCounted) -> Array:
	var tools: Array = []
	var table: Dictionary = tools_table(registry, false)
	for command_name: String in table:
		tools.append(Tool.from_entry(command_name, table[command_name], null))
	var docs: Dictionary = {}
	for tool: Tool in tools:
		var spec: Dictionary = registry.pieces.get(
			String(tool.type), registry.upgrades.get(String(tool.type), {})
		)
		var path: String = str(spec.get("_doc_path", tool.type))
		docs[tool.command_name] = path
		docs[ProducerContextBinding.PREFIX + String(tool.type)] = path + " (ui.context_grid)"
	var out: Array = []
	for collision: String in ControlBinding.grid_collisions(
		tools + ProducerContextBinding.from_tools(tools)
	):
		var names: PackedStringArray = collision.split(" @ ")[0].split(" + ")
		out.append(
			(
				"%s — move one: %s, %s"
				% [collision, docs.get(names[0], names[0]), docs.get(names[1], names[1])]
			)
		)
	return out


## [{id, label, faction, scene, is_fixture, producers, tool}] — every piece that can stand in
## the world on its own: units, structures and features. Tokens are left out (their emitter,
## caster or lifespan is what makes one mean anything), and so are abstract bases (no scene).
##
## A scene no doc names is listed too, from the groups and id its own file carries, unless its
## id is a documented piece's: the id is how every registry finds a piece, so it would run
## under that piece's name. Separate from tools.json, whose entries surface on real cards.
static func debug_roster_json(registry: RefCounted) -> String:
	var ids: Array = registry.pieces.keys()
	ids.sort()
	var producers: Dictionary = _producers_by_trainee(registry)
	var tracked_scenes: Dictionary = {}
	var entries: Array = []
	for id in ids:
		var spec: Dictionary = registry.pieces[id]
		if not spec.has("scene"):
			continue
		tracked_scenes[str(spec["scene"])] = true
		var is_fixture: bool = SpecSchema.is_fixture(spec)
		if not is_fixture and (not SpecSchema.is_commandable(spec) or SpecSchema.is_emission(spec)):
			continue
		var ui: Dictionary = spec["ui"] if spec.get("ui") is Dictionary else {}
		var factions: Array = ui.get("factions", [])
		(
			entries
			. append(
				{
					"id": str(id),
					"label": piece_title(spec),
					"faction":
					(
						str(factions[0])
						if not factions.is_empty()
						else folder_faction(str(spec["scene"]))
					),
					"scene": str(spec["scene"]),
					"is_fixture": is_fixture,
					"producers": producers.get(str(id), []),
					"tool": "command_tool_%s" % id if spec.has("ui") else "",
				}
			)
		)
	for path: String in _scene_paths(ENTITY_SCENES_DIR):
		if tracked_scenes.has(path):
			continue
		var entry: Dictionary = untracked_roster_entry(path, FileAccess.get_file_as_string(path))
		if not entry.is_empty() and not registry.pieces.has(entry["id"]):
			entries.append(entry)
	return JSON.stringify(entries, "\t") + "\n"


## The roster entry for an undocumented scene, read from its ROOT node's text, or {} when it is
## not a placeable piece: no id (an abstract base), or in neither the "unit" nor the
## "fixture" group (a token, an emission, a component).
static func untracked_roster_entry(path: String, text: String) -> Dictionary:
	var root_end: int = text.find("\n[node", text.find("[node") + 1)
	var root: String = text.substr(0, root_end if root_end >= 0 else text.length())
	var groups_at: int = root.find("groups=[")
	var groups: String = (
		root.substr(groups_at, root.find("]", groups_at) - groups_at) if groups_at >= 0 else ""
	)
	var is_fixture: bool = groups.contains('"fixture"')
	if not is_fixture and not groups.contains('"unit"'):
		return {}
	var id_match: RegExMatch = RegEx.create_from_string('(?m)^id = &"([^"]+)"').search(root)
	if id_match == null:
		return {}
	return {
		"id": id_match.get_string(1),
		"label": path.get_file().get_basename(),
		"faction": folder_faction(path),
		"scene": path,
		"is_fixture": is_fixture,
		"producers": [],
		"tool": "",
	}


## The faction a scene's folder code names, or DEFAULT_ROSTER_FACTION.
static func folder_faction(path: String) -> String:
	return FOLDER_FACTIONS.get(path.get_base_dir().get_file(), DEFAULT_ROSTER_FACTION)


## Every .tscn under `dir`, recursively, sorted.
static func _scene_paths(dir: String) -> Array[String]:
	var out: Array[String] = []
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() == "tscn":
			out.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		out.append_array(_scene_paths(dir.path_join(sub)))
	out.sort()
	return out


## {ability_id: {"title", "description", "verbose", "passive", "hud_button", "global_alert",
## "command", "emits", "dominion"}} — one entry per kind: AbilityDefinition doc.
##
## THE ABILITY DEFINITION AT RUNTIME. What a piece can do is on the piece
## (`Abilities`, from `abilities:`); what an ability IS is here, so a free ability
## has a home that is not the sanction grid. `dominion` says whether the sanction grid is where
## it comes from, which is the only thing "sanction" now means.
##
## The per-CELL copy of a dominion-unlocked ability is not repeated here: it belongs
## to one level and is already baked onto that cell's Sanction in the faction scene.
## `description` / `verbose` therefore carry the ability's own words, which only an
## ability with no cells needs.
static func abilities_json(registry: RefCounted) -> String:
	var ids: Array = registry.abilities.keys()
	ids.sort()
	var table: Dictionary = {}
	for id in ids:
		var spec: Dictionary = registry.abilities[id]
		var emits: String = str(spec.get("emits", ""))
		table[id] = {
			"title": piece_title(spec),
			"description": render_placeholders(registry, str(spec.get("description", ""))),
			"verbose": render_placeholders(registry, str(spec.get("verbose", ""))),
			"passive": bool(spec.get("passive", false)),
			"hud_button": bool(spec.get("hud_button", false)),
			# EVERY commander is told when anyone owns a piece that casts it, sees its charge count
			# down, and hears it ready and launched — never where. gdd/systems/ux/ui/alerts.md
			# §Global alerts.
			"global_alert": bool(spec.get("global_alert", false)),
			"command": str(spec.get("command", "")),
			# HOW FAR from the target point the ability may be used. Per ability rather than one
			# constant for all of them — see AbilityCatalog.range_of for why that mattered.
			"range": float(spec.get("range", AbilityDefinition.DEFAULT_RANGE)),
			# HOW MANY selected casters fire it with no modifier held. SINGLE unless the doc says
			# otherwise — see AbilityCatalog.cast_arity_of for why that is the right default.
			"cast_by": str(spec.get("cast_by", "SINGLE")),
			# The reach its card paints on hover, as an EntityRanges.Kind name. "" for an ability
			# with no shape to show, which is most of them.
			"reveals": str(spec.get("reveals", "")),
			# Good or bad for whoever carries it — the accent on its info card. NEUTRAL unsaid.
			"valence": str(spec.get("valence", "NEUTRAL")),
			"emits":
			(
				emits
				if emits.begins_with("res://")
				else str(registry.specs.get(emits, {}).get("scene", ""))
			),
			"dominion": spec.has("levels"),
			# THE ORDNANCE CARD'S LAYOUT. `grid` is the cell the ability's button occupies and
			# `factions` is what lets two factions' ordnances share one cell honestly (see
			# ControlBinding.grid_collisions) — the same two keys a tool authors, in the same `ui:`
			# block, so the grid has ONE vocabulary rather than one per kind of doc.
			"grid": _ability_grid(spec, "grid"),
			# A SECOND cell, on the ACTIVE card, for an ability that is both an order to a selected
			# piece and a strike the commander calls in — see the Bombard.
			"active_grid": _ability_grid(spec, "active_grid"),
			"factions": _ui(spec).get("factions", []),
			# The LEVEL TITLES, because a dominion-unlocked ability is armed as its cell's own
			# command and each level has its own name ("Scan 1", "Scan 2") — so one ability is up
			# to three command names sharing one cell, of which supersession keeps exactly one
			# live. Titles rather than command names: the name is DERIVED from the title by
			# Sanction.command_name_for, and deriving it twice is how the two would drift.
			"levels": _level_titles(registry, spec),
		}
	return _json_header("ability definitions") + JSON.stringify(table, "\t") + "\n"


## `{{ piece_id }}` -> that piece's title. Resolved at IMPORT, so both the faction scene and
## abilities.json carry finished prose: the game does no lookup, and renaming a piece
## re-renders every sanction description that mentions it on the next run. Unknown ids were
## already rejected in validation, so anything still unresolved here is left alone rather than
## blanked.
##
## Shared by the scene sync (which bakes it onto each Sanction) and by abilities.json (which
## carries the same copy for the ORDNANCE button). It was only in the scene sync until the
## card grew buttons, and the copy that reached them still had literal braces in it.
static func render_placeholders(registry: RefCounted, text: String) -> String:
	if not text.contains("{{"):
		return text
	var regex := RegEx.new()
	regex.compile("\\{\\{\\s*([A-Za-z0-9_]+)\\s*\\}\\}")
	var out: String = text
	for m: RegExMatch in regex.search_all(text):
		var spec: Dictionary = registry.specs.get(m.get_string(1), {})
		var title: String = str(spec.get("title", "")) if not spec.is_empty() else ""
		if title != "":
			out = out.replace(m.get_string(0), title)
	return out


## The `ui:` block of a doc, or an empty one.
static func _ui(spec: Dictionary) -> Dictionary:
	var ui: Variant = spec.get("ui", {})
	return ui if ui is Dictionary else {}


## The ability's authored cell as [x, y], or [] when it has none — a LOCAL ability draws no
## ORDNANCE button and needs no cell.
static func _ability_grid(spec: Dictionary, key: String) -> Array:
	var g: Variant = _ui(spec).get(key, [])
	return [int(g[0]), int(g[1])] if g is Array and g.size() == 2 else []


## Each unlock level, in authored order: its title and its own two tiers of copy. Empty for
## an ability with no dominion route.
##
## The COPY is per level and not per ability, which is why it is repeated here rather than
## taken from the ability's own `description`. A levelled ability's words belong to the level
## — "Scan 2" reveals more ground than "Scan 1" and says so — so an ORDNANCE button has to
## follow whichever level is in play. The ability's own description is left for the abilities
## that have no levels at all.
static func _level_titles(registry: RefCounted, spec: Dictionary) -> Array:
	var out: Array = []
	for level in spec.get("levels", []):
		if level is Dictionary:
			(
				out
				. append(
					{
						"title": str(level.get("title", "")),
						"description":
						render_placeholders(registry, str(level.get("description", ""))),
						"verbose": render_placeholders(registry, str(level.get("verbose", ""))),
					}
				)
			)
	return out


## Whether this piece carries any CHARGED weapon — one that cannot reload in the field and
## must be recharged at an airfield's DockingBay (see Weapon.charged).
##
## Derived rather than authored so it cannot drift from the weapon list it describes, and
## carried on the tool so the HUD can warn about docking capacity without instantiating
## the unit scene every frame to go looking for its Loadout.
static func _needs_docking(spec: Dictionary) -> bool:
	for w in spec.get("weapons", []):
		if w is Dictionary and bool(w.get("charged", false)):
			return true
	return false


## trainee id -> the sorted ids of every structure whose `trains:` names it.
##
## This is the grid collision review's separator for TRAIN buttons (see
## ControlBinding.actor_ids): the barracks' infantry and the airfield's aircraft can share
## cell (0, 1) because no one selection is ever asked to draw both, and knowing that is
## what keeps every faction's training row inside six columns without a wall of
## hand-written acknowledgements. Derived rather than authored — a `trains:` edit re-derives
## it, so it cannot drift from the roster it describes.
static func _producers_by_trainee(registry: RefCounted) -> Dictionary:
	var out: Dictionary = {}
	var producer_ids: Array = registry.pieces.keys()
	producer_ids.sort()
	for producer_id in producer_ids:
		for trainee in (
			registry.pieces[producer_id].get("trains", [])
			+ registry.pieces[producer_id].get("researches", [])
		):
			var trainee_id: String = str(trainee)
			if not out.has(trainee_id):
				out[trainee_id] = []
			out[trainee_id].append(str(producer_id))
	return out


# --------------------------------------------------------------------------- #
# Piece copy (button label + the two tooltip tiers)
# --------------------------------------------------------------------------- #
## A piece's user-facing display name: its authored `title`, or the raw id when the
## doc has none. SpecRegistry warns about the latter — an id on a button is a piece
## whose copy hasn't been written yet, and it should look like one.
static func piece_title(spec: Dictionary) -> String:
	var title: String = str(spec.get("title", "")).strip_edges()
	return title if not title.is_empty() else str(spec["id"])


## Whether a piece is BUILT rather than trained. A fixture is built — construction is a grid
## occupation — unless a producer's `trains:` names it: a piece with both a footprint and
## movement that is trained stands up mobile and deploys later (composition-rework.md
## §Which form a piece spawns in). Derived from the docs, never from a kind.
static func _is_built(spec: Dictionary, producers: Dictionary) -> bool:
	return SpecSchema.is_fixture(spec) and not producers.has(str(spec["id"]))


## Tier one: what this button makes and what it costs, in one line.
static func tool_tooltip(spec: Dictionary, is_built: bool) -> String:
	var verb: String = "Build" if is_built else "Train"
	var seconds: float = float(spec.get("build_time", 0))
	return "%s %s — %s, %s" % [verb, piece_title(spec), _cost_phrase(spec), _seconds(seconds)]


## Tier two (held verbose key): the full readout — cost, prerequisites, durability,
## infrastructure, what it produces, and what it shoots with.
static func tool_verbose_tooltip(registry: RefCounted, spec: Dictionary) -> String:
	var lines: Array = [tool_tooltip(spec, _is_built(spec, _producers_by_trainee(registry)))]

	var requires: Array = _titles_of(registry, spec.get("requires", []))
	if not requires.is_empty():
		lines.append("Requires: %s" % ", ".join(requires))

	var durability: Array = []
	if spec.has("hp"):
		durability.append("%d HP" % int(spec["hp"]))
	if spec.has("armour"):
		durability.append("%s armour" % str(spec["armour"]).to_lower())
	if spec.has("frame"):
		durability.append("%s frame" % str(spec["frame"]).to_lower())
	if not durability.is_empty():
		lines.append(" · ".join(durability))

	var presence: Array = []
	if spec.has("footprint") and spec["footprint"] is Array and spec["footprint"].size() == 2:
		presence.append("%d×%d cells" % [int(spec["footprint"][0]), int(spec["footprint"][1])])
	if spec.has("movement") and spec["movement"] is Dictionary:
		var movement: Dictionary = spec["movement"]
		var aerial: Variant = spec.get("aerial")
		var mode: String = str(aerial.get("mode", "")) if aerial is Dictionary else "GROUNDED"
		(
			presence
			. append(
				(
					"%s, speed %s"
					% [
						mode.to_lower().replace("_", " "),
						_number(float(movement.get("speed", 0.0))),
					]
				)
			)
		)
	if float(spec.get("vision", 0)) > 0.0:
		presence.append("vision %s" % _number(float(spec["vision"])))
	if not presence.is_empty():
		lines.append(" · ".join(presence))

	# One signed int in the doc: positive provides infrastructure, negative consumes it.
	var infrastructure: int = int(spec.get("infrastructure", 0))
	if infrastructure > 0:
		lines.append("Provides %d infrastructure" % infrastructure)
	elif infrastructure < 0:
		lines.append("Costs %d infrastructure upkeep" % absi(infrastructure))

	var trains: Array = _titles_of(registry, spec.get("trains", []))
	if not trains.is_empty():
		lines.append("Trains: %s" % ", ".join(trains))
	var researches: Array = []
	for ref: Variant in spec.get("researches", []):
		if registry.upgrades.has(str(ref)):
			researches.append(piece_title(registry.upgrades[str(ref)]))
	if not researches.is_empty():
		lines.append("Researches: %s" % ", ".join(researches))
	var builds: Array = _titles_of(registry, spec.get("builds", []))
	if not builds.is_empty():
		lines.append("Builds: %s" % ", ".join(builds))
	if spec.get("repairs", false) == true:
		lines.append("Repairs damaged mechanical units and structures")

	for line in _weapon_lines(registry, spec):
		lines.append(line)

	return "\n".join(lines)


## Tier one for an upgrade: what it researches and what it costs, in one line.
static func upgrade_tooltip(spec: Dictionary) -> String:
	return (
		"Research %s — %s, %s"
		% [piece_title(spec), _cost_phrase(spec), _seconds(float(spec.get("build_time", 0)))]
	)


## Tier two for an upgrade: the one-liner, its description, and what it modifies.
static func upgrade_verbose_tooltip(registry: RefCounted, spec: Dictionary) -> String:
	var lines: Array = [upgrade_tooltip(spec)]
	var description: String = str(spec.get("description", "")).strip_edges()
	if not description.is_empty():
		lines.append(description)
	var requires: Array = _titles_of(registry, spec.get("requires", []))
	if not requires.is_empty():
		lines.append("Requires: %s" % ", ".join(requires))
	for entry: Variant in spec.get("modifies", []):
		if entry is Dictionary:
			lines.append(_modifier_phrase(registry, entry))
	lines.append("Researched once, for every unit it affects; kept if the building is lost")
	return "\n".join(lines)


## What one `modifies:` entry does, as a tooltip line: "drake rearms 100% faster".
static func _modifier_phrase(registry: RefCounted, entry: Dictionary) -> String:
	var who: String
	if entry.has("frame"):
		who = "Every %s unit" % str(entry["frame"])
	else:
		var piece: Dictionary = registry.pieces.get(str(entry.get("piece", "")), {})
		who = piece_title(piece) if not piece.is_empty() else str(entry.get("piece", ""))
	var ability: Dictionary = registry.abilities.get(str(entry.get("ability", "")), {})
	var ability_title: String = (
		piece_title(ability) if not ability.is_empty() else str(entry.get("ability", ""))
	)
	if entry.has("range_metres"):
		return (
			"%s's %s reach becomes %s" % [who, ability_title, _number(float(entry["range_metres"]))]
		)
	if entry.has("hp_factor"):
		return "%s has %s more hit points" % [who, _percent_more(entry["hp_factor"])]
	if entry.has("rearm_rate_factor"):
		return "%s rearms %s faster" % [who, _percent_more(entry["rearm_rate_factor"])]
	if entry.has("cooldown_rate_factor"):
		return (
			"%s's %s recharges %s faster"
			% [who, ability_title, _percent_more(entry["cooldown_rate_factor"])]
		)
	if entry.has("unlocks"):
		return "%s can use %s" % [who, ability_title]
	return who


## A factor as the percentage it adds: 1.25 -> "25%".
static func _percent_more(factor: Variant) -> String:
	return "%s%%" % _number((float(factor) - 1.0) * 100.0)


## `{id: {"title", "faction", "modifies": [{"piece", "ability", "range"}]}}` for every upgrade
## doc — what UpgradeCatalog reads. A `modifies.range` names a library shape in the doc and
## arrives here as that shape's radius, so the runtime reads a number.
static func upgrades_json(registry: RefCounted) -> String:
	var ids: Array = registry.upgrades.keys()
	ids.sort()
	var table: Dictionary = {}
	for id in ids:
		var spec: Dictionary = registry.upgrades[id]
		var modifies: Array = []
		for entry: Variant in spec.get("modifies", []):
			if not (entry is Dictionary):
				continue
			var m: Dictionary = {}
			for key: String in ["piece", "frame", "ability"]:
				if (entry as Dictionary).has(key):
					m[key] = str(entry[key])
			if (entry as Dictionary).has("range_metres"):
				m["range"] = float(entry["range_metres"])
			for key: String in ["hp_factor", "rearm_rate_factor", "cooldown_rate_factor"]:
				if (entry as Dictionary).has(key):
					m[key] = float(entry[key])
			if (entry as Dictionary).has("unlocks"):
				m["unlocks"] = true
			modifies.append(m)
		var ui: Dictionary = spec["ui"] if spec.get("ui") is Dictionary else {}
		var factions: Array = ui.get("factions", [])
		table[id] = {
			"title": piece_title(spec),
			"faction": str(factions[0]) if not factions.is_empty() else "",
			"modifies": modifies,
		}
	return _json_header("upgrade definitions") + JSON.stringify(table, "\t") + "\n"


## "500 energy", "600 energy · 2 dominion", or "free" — every resource the doc charges.
static func _cost_phrase(spec: Dictionary) -> String:
	var cost: Dictionary = spec["cost"] if spec.get("cost") is Dictionary else {}
	var parts: Array = []
	for key in ["energy", "infrastructure", "dominion"]:
		var amount: int = int(cost.get(key, 0))
		if amount != 0:
			parts.append("%d %s" % [amount, key])
	return " · ".join(parts) if not parts.is_empty() else "free"


## One line per weapon: what it does and how far it reaches. Damage comes from the
## referenced projectile (already hoisted to a registry id by this point) or, for a
## melee weapon, from the weapon itself.
static func _weapon_lines(registry: RefCounted, spec: Dictionary) -> Array:
	var lines: Array = []
	if not (spec.get("weapons") is Array):
		return lines
	for w in spec["weapons"]:
		if not (w is Dictionary):
			continue
		var damage: String = ""
		if w.has("projectile") and registry.projectiles.has(str(w["projectile"])):
			var projectile: Dictionary = registry.projectiles[str(w["projectile"])]
			damage = (
				"%s %s"
				% [
					_number(float(projectile.get("damage", 0))),
					str(projectile.get("damage_type", "")).to_lower(),
				]
			)
		elif w.has("melee_damage"):
			damage = (
				"%s %s (melee)"
				% [
					_number(float(w["melee_damage"])),
					str(w.get("melee_damage_type", "")).to_lower(),
				]
			)
		var reach: String = _reach_phrase(w.get("_reach_radii", {}))
		(
			lines
			. append(
				(
					"%s: %s%s"
					% [
						str(w.get("name", "Weapon")),
						damage if not damage.is_empty() else "no damage authored",
						", reach %s" % reach if not reach.is_empty() else "",
					]
				)
			)
		)
	return lines


## A weapon's resolved reach, {layer: radius}: one number when both layers agree.
static func _reach_phrase(radii: Dictionary) -> String:
	var values: Array = radii.values()
	if values.is_empty():
		return ""
	if radii.size() == 2 and is_equal_approx(float(values[0]), float(values[1])):
		return _number(float(values[0]))
	var parts: Array = []
	for key in ["ground", "air"]:
		if radii.has(key):
			parts.append("%s %s" % [_number(float(radii[key])), key])
	return " / ".join(parts)


## The display titles of a list of piece ids, skipping any that don't resolve —
## validation has already failed the import for those, so this never hides a typo.
static func _titles_of(registry: RefCounted, ids: Variant) -> Array:
	var out: Array = []
	if not (ids is Array):
		return out
	for ref in ids:
		var rid: String = str(ref)
		if registry.pieces.has(rid):
			out.append(piece_title(registry.pieces[rid]))
	return out


## Trailing zeros off a doc number: "1.5", "7", "0.8".
static func _number(value: float) -> String:
	return (
		"%d" % int(value) if is_equal_approx(value, floorf(value)) else "%s" % snappedf(value, 0.01)
	)


static func _seconds(value: float) -> String:
	return "%ss" % _number(value)


# --------------------------------------------------------------------------- #
# IO
# --------------------------------------------------------------------------- #
static func _gd_header(what: String) -> String:
	return (
		(
			"## AUTO-GENERATED by tools/spec_import (%s).\n## Do not edit by hand — edit "
			+ "the gdd docs and re-run the importer.\n"
		)
		% what
	)


static func _json_header(_what: String) -> String:
	# JSON has no comments; the marker rides in a reserved "_generated" key? No —
	# consumers iterate keys. The header lives in the sibling .md docs instead;
	# this function exists so a format change stays one-line.
	return ""


static func _write(path: String, text: String) -> String:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("spec_import: cannot write %s" % path)
		return path
	f.store_string(text)
	f.close()
	return path
