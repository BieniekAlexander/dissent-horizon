class_name SpecSchema
extends RefCounted

## The SHAPE of a spec doc: what nests under what, in which order, and how the
## authored shape maps onto the flat names the rest of the importer carries.
##
## Two jobs, deliberately in one file because they are one decision read twice:
##
##   * [b]normalize[/b] lifts the authored nests onto the internal keys the
##     registry, the rules and the scene sync already use, and refuses the flat
##     spellings they replaced. It is the ONE place the doc vocabulary and the
##     code vocabulary meet — see gdd/systems/authoring/spec-importer.md §The doc's shape.
##   * [b]reorder_frontmatter[/b] rewrites a doc's frontmatter into the canonical
##     order. Order is NEVER a validation failure; a doc out of order imports
##     normally and is rewritten in place by the pass that already writes docs.
##
## The rewrite is held to three constraints, which are step 0's contract in a
## different file format:
##   * IDEMPOTENT — reordering an already-ordered doc changes no bytes.
##   * TOTAL, IN BOTH DIRECTIONS — an unknown key is never dropped; it sorts to
##     the end of its own level, where it is visible rather than lost.
##   * COMMENT- AND VALUE-PRESERVING — whole key blocks move; values are never
##     re-serialised, so block scalars, wikilinks and flow collections round-trip
##     byte for byte.
##
## Anything the rewrite does not understand (a level whose indentation is
## irregular, a sequence item whose first key would end up behind a comment) is
## left EXACTLY as authored rather than guessed at. Leaving a doc unordered costs
## nothing; corrupting one costs a file.

const SpecFrontmatter := preload("res://tools/spec_import/frontmatter.gd")

## Sub-keys are indented by two spaces, matching every nest already in the roster.
const INDENT_STEP: int = 2

# --------------------------------------------------------------------------- #
# Canonical order
# --------------------------------------------------------------------------- #
## The canonical TOP-LEVEL key order, read top to bottom — this constant is its source of
## truth:
## identity, flavor, the build transaction, the three value nests, the
## discriminating component keys, the root-node properties, presentation, then
## the keys that belong to the kinds which are not game pieces.
##
## `exceptions:` sits last of the piece keys on purpose: it is commentary on the
## numbers above it, and it is the only block whose entries are prose.
const TOP_LEVEL_ORDER: Array = [
	# Identity — what the file is.
	"kind",
	"title",
	"scene",
	"editor_description",
	"commandable",
	"family",
	# Flavor, then the macroeconomic transaction.
	"flavor",
	"build",
	# The three value nests.
	"defense",
	"senses",
	"body",
	# The discriminating component keys — one key per component, deliberately flat.
	"movement",
	"aerial",
	"docking",
	"footprint",
	"weapons",
	"trains",
	"researches",
	"builds",
	"variants",
	"garrison",
	"deploys",
	"abilities",
	"repairs",
	"stealth",
	"beacon",
	"shelter",
	"extraction_site",
	"extractor",
	"plants_beacons",
	# Root-node properties: neither belongs to a component.
	"infrastructure",
	"occupancy_size",
	# Presentation and meta.
	"ui",
	"exceptions",
	# Emissions (today's `kind: projectile`): the payload, then the flat motion shorthand,
	# then the phase list that replaces the shorthand when present.
	"damage",
	"damage_type",
	"blast",
	"status_effects",
	"speed",
	"trajectory",
	"hitscan",
	"bio_ground_aim",
	"phases",
	# Faction docs.
	"starts_with",
	"sanctions",
	# Ability docs: what the ability IS, then the dominion unlock route it may
	# have (`column`/`levels`). Neither kind is a game piece, so the component
	# rule has nothing to say about them.
	"passive",
	"hud_button",
	"command",
	"range",
	"cast_by",
	"reveals",
	"valence",
	"emits",
	"column",
	"levels",
	# Upgrade docs: what the research changes.
	"modifies",
	# Shape-library docs: a bare radius.
	"radius",
]

## Sub-key order within a nest, keyed by the parent key. A SEQUENCE's parent key
## orders the keys inside each of its items (`weapons` orders a weapon entry),
## since a sequence's own order is data and is never touched.
##
## A parent absent from this table leaves its children exactly as authored —
## `exceptions:` is the case that matters, its keys being rule ids rather than a
## fixed set.
const NESTED_ORDER: Dictionary = {
	"flavor": ["description", "verbose"],
	"build": ["cost", "time", "requires", "completes_as"],
	"cost": ["energy", "infrastructure", "dominion"],
	"defense": ["hp", "armour", "frame"],
	"senses": ["vision", "detection"],
	"body": ["radius"],
	"movement":
	[
		"speed",
		"turn_rate",
		"max_acceleration",
		"max_deceleration",
		"crush_class",
		"min_turn_speed_ratio",
		"reverse_speed_ratio"
	],
	"aerial": ["mode", "orbit_radius", "orbit_speed"],
	"garrison":
	[
		"capacity",
		"frames",
		"armours",
		"movements",
		"closed",
		"releasable",
		"bunker",
		"preserve_occupants",
		"captures",
		"range_bonus",
		"reach_by_piece",
		"pieces",
		"sentence_length"
	],
	"weapons":
	[
		"name",
		"emits",
		"melee_damage",
		"melee_damage_type",
		"split_time",
		"reload_time",
		"startup_time",
		"clip_size",
		"charged",
		"self_destruct",
		"turret",
		"turret_turn_rate",
		"range_from",
		"reach",
		"hits"
	],
	# An INLINE emission, written where the weapon fires it. `id`/`title`/`scene`
	# come first for the same reason they do at top level; the rest is the
	"emits":
	[
		# emission order above.
		"id",
		"title",
		"scene",
		"damage",
		"damage_type",
		"blast",
		"status_effects",
		"speed",
		"trajectory",
		"hitscan",
		"bio_ground_aim",
		"phases"
	],
	# One phase of an emission, in the order it is read: how it moves, what ends it, what it does.
	"phases":
	["name", "motion", "ends_on_arrival", "lifespan", "impact_mask", "payload", "emits", "visuals"],
	"motion":
	[
		"preset",
		"speed",
		"gravity",
		"launch_pitch",
		"turn_rate",
		"launch_speed_ratio",
		"acceleration",
		"min_speed",
		"jitter",
		"jitter_frequency"
	],
	"reach": ["ground", "air"],
	"deploys": ["time", "undeploy_time", "cancellable"],
	"abilities": ["max_charges", "initial_charges", "cooldown", "grants"],
	"ui": ["grid", "active_grid", "context_grid", "factions", "tooltip", "verbose"],
	"levels":
	[
		"title",
		"tier",
		"cost",
		"cooldown",
		"description",
		"verbose",
		"needs_vision",
		"needs_target",
		"kill_bounty",
		"ability",
		"ability_level",
		"payloads"
	],
	"payloads": ["piece", "count"],
}

# --------------------------------------------------------------------------- #
# The doc shape -> the internal shape
# --------------------------------------------------------------------------- #
## Each nest, as {authored sub-key: the internal key it becomes}. The internal
## names are the flat ones the importer already carries, so nesting the docs
## moved no code — see the class docs for why that seam is here and only here.
const NESTS: Dictionary = {
	"flavor": {"description": "description", "verbose": "verbose"},
	"build":
	{"cost": "cost", "time": "build_time", "requires": "requires", "completes_as": "completes_as"},
	"defense": {"hp": "hp", "armour": "armour", "frame": "frame"},
	"senses": {"vision": "vision", "detection": "detection"},
	"body": {"radius": "movement_radius"},
}

## Top-level keys that are renamed rather than nested: {authored: internal}.
const RENAMES: Dictionary = {
	"abilities": "ability_groups",  # the `_groups` suffix described the YAML, not the component
	"beacon": "beacon_range",  # a bare radius, so the `_range` suffix was noise
}

## Keys that no longer exist at all, and what replaces each. Refused rather than
## ignored, for the reason the retired flat spellings are: a doc still naming one
## believes it is configuring something.
const RETIRED: Dictionary = {
	"bombards":
	"abilities: — a battery is an ability with a per-use `emits:`, not a component of its own",
	"visual":
	(
		"exceptions: {has_mesh_visual: <why>} — the opt-out from a model is a waiver, "
		+ "so it goes STALE when the piece grows art"
	),
	"spotting":
	(
		"abilities: — grant `spot`; calling a firing solution is an ability like any "
		+ "other, not a marker component"
	),
}

## Nested keys that no longer exist, keyed by their doc path, and what replaces each.
const RETIRED_NESTED: Dictionary = {
	"senses.aggro":
	"aggro is derived from weapon reach at runtime (RangeShapes), so remove the key",
	"body.target":
	"retired — the hurtbox is fitted to the model by the importer, so remove the key",
	"body.hurtbox":
	(
		"retired — the hurtbox is fitted to the model by the importer (generated-visual-defaults"
		+ ".md §The hurtbox), so remove the key"
	),
}

## internal key -> the DOC path that now carries it. Read both ways: a doc still
## naming the internal key is a hard error that names the new path, and every
## message that mentions a key spells it the way the author writes it.
const DOC_KEY: Dictionary = {
	"description": "flavor.description",
	"verbose": "flavor.verbose",
	"cost": "build.cost",
	"build_time": "build.time",
	"requires": "build.requires",
	"completes_as": "build.completes_as",
	"hp": "defense.hp",
	"armour": "defense.armour",
	"frame": "defense.frame",
	"vision": "senses.vision",
	"detection": "senses.detection",
	"movement_radius": "body.radius",
	"ability_groups": "abilities",
	"beacon_range": "beacon",
}

## What a built piece stands up as once construction finishes. STRUCTURE is the
## default in the literal sense: it is what every piece in the roster does today,
## so the key changes nothing until a doc authors it.
const COMPLETES_AS: Array = ["STRUCTURE", "UNIT"]
const DEFAULT_COMPLETES_AS: String = "STRUCTURE"


## How a key is spelled in a doc — its nest path where it has one, else itself.
static func doc_key(internal: String) -> String:
	return str(DOC_KEY.get(internal, internal))


## Whether the piece answers to orders. Read by derived_groups.
##
## DERIVED off the same discriminators that decide the role, the groups and the root body:
## a doc declaring a body is commandable, a doc declaring a payload is not. `commandable:`
## is therefore an OVERRIDE and never a declaration, and an authored value always wins —
## including a redundant one, which is permitted and silent.
##
## A doc satisfying NEITHER discriminator has no answer here, and false is a fallback rather
## than a claim; it becomes a loud import error under composition-rework §The discriminating
## keys. Why: gdd/systems/authoring/spec-importer.md §The doc's shape.
static func is_commandable(spec: Dictionary) -> bool:
	if spec.has("commandable"):
		return bool(spec["commandable"])
	if spec.has("footprint") or spec.has("movement"):
		return true
	return false


## The keys only an emission has. An `Entity` doc naming any of them is an emission: a piece put
## into the world by an emitter and moved by its phase list (composition-rework §The name).
const EMISSION_KEYS: Array[String] = [
	"phases",
	"speed",
	"trajectory",
	"damage",
	"damage_type",
	"blast",
	"hitscan",
	"bio_ground_aim",
	"status_effects"
]


static func is_emission(spec: Dictionary) -> bool:
	return EMISSION_KEYS.any(func(key: String) -> bool: return spec.has(key))


## Whether the piece claims terrain-grid cells — a FIXTURE in the settled vocabulary
## (piece-vocabulary.md). Derived from `footprint:` alone, which is the component that
## registers cells; code tests this facet, never a doc kind.
static func is_fixture(spec: Dictionary) -> bool:
	return spec.has("footprint")


## The groups the importer owns and derives. Any other group on a scene is authored.
## A family's name is also the group its members carry, so it is derived too (see `family`).
const DERIVED_GROUPS: Array[String] = ["piece", "unit", "fixture", "structure", "neutral_building"]

## The closed set of values `family:` may take. A family is a named set of pieces that gameplay
## and map generation enumerate or recognise as one thing (every neutral building) without
## matching on ids. Its name doubles as the group the members carry on their scene root, and
## the members are published in resources/generated/families.json. A member is also a TEMPLATE
## (see SpecRegistry._validate_family): its `infrastructure:` is published there, never written to
## the scene root, so the piece grants nothing merely by standing on the map.
## Every entry must also be in DERIVED_GROUPS (tests/test_PieceFamilies pins that).
const FAMILIES: Array[String] = ["neutral_building"]


## A piece's groups, in the order they are written (the nouns are piece-vocabulary.md's): every
## piece is a "piece"; one that only moves AND takes orders is a "unit" — what the group's
## readers (movement routing, aggro) mean by it; one that only claims cells is a "fixture", the
## group grid registration and footprint reach read; and a fixture that takes orders is also a
## "structure". A two-form piece gets none of the last three here — the form it stands up in
## decides, and Entity moves it between them when it switches (composition-rework §Step 1).
static func derived_groups(spec: Dictionary) -> Array[String]:
	var groups: Array[String] = ["piece"]
	var is_mobile: bool = spec.has("movement")
	if is_mobile and not is_fixture(spec) and is_commandable(spec):
		groups.append("unit")
	elif is_fixture(spec) and not is_mobile:
		groups.append("fixture")
		if is_commandable(spec):
			groups.append("structure")
	var family: String = str(spec.get("family", ""))
	if FAMILIES.has(family):
		groups.append(family)
	return groups


## Whether the doc names at least one key that gives a piece a body or a sense: a footprint,
## movement, or vision. A doc with none is prose carrying the marker, or a piece whose author
## forgot the key that makes it anything — both refused (composition-rework §The
## discriminating keys).
static func has_discriminator(spec: Dictionary) -> bool:
	return spec.has("footprint") or spec.has("movement") or spec.has("vision")


## Whether the doc opts out of the default model, by waiving `has_mesh_visual`.
static func wants_no_visual(spec: Dictionary) -> bool:
	var declared: Variant = spec.get("exceptions")
	return declared is Dictionary and (declared as Dictionary).has("has_mesh_visual")


# --------------------------------------------------------------------------- #
# Normalisation
# --------------------------------------------------------------------------- #
## Rewrites `a_spec` IN PLACE from the authored shape to the internal one, and
## returns the complaints (unprefixed; the caller attaches the doc and id).
##
## The retired flat spellings are refused rather than accepted as aliases, for
## the reason `ui.label` and a stray `id:` are: a doc that still says `hp:`
## believes it is setting hit points, and silently reading it would let the two
## spellings disagree for as long as nobody looked.
static func normalize(spec: Dictionary) -> Array:
	var errors: Array = []
	for internal: String in DOC_KEY:
		if spec.has(internal):
			errors.append("`%s:` is now `%s:`" % [internal, DOC_KEY[internal]])
			spec.erase(internal)
	for retired: String in RETIRED:
		if spec.has(retired):
			errors.append("`%s:` is retired — use %s" % [retired, RETIRED[retired]])
			spec.erase(retired)
	for nest: String in NESTS:
		_lift_nest(spec, nest, errors)
	for authored: String in RENAMES:
		if spec.has(authored):
			spec[RENAMES[authored]] = spec[authored]
			spec.erase(authored)
	_normalize_weapons(spec, errors)
	_check_new_keys(spec, errors)
	return errors


## One nest, flattened onto its internal keys. An unknown sub-key is a hard error
## rather than a skipped line — the same whitelist rule `movement:` follows, and
## for the same reason: an ignored key reads as authority it does not have.
static func _lift_nest(spec: Dictionary, nest: String, errors: Array) -> void:
	if not spec.has(nest):
		return
	var value: Variant = spec[nest]
	spec.erase(nest)
	var members: Dictionary = NESTS[nest]
	if not (value is Dictionary):
		errors.append("%s must be a mapping of %s" % [nest, members.keys()])
		return
	for key in value as Dictionary:
		var path: String = "%s.%s" % [nest, key]
		if RETIRED_NESTED.has(path):
			errors.append("`%s:` is retired — %s" % [path, RETIRED_NESTED[path]])
			continue
		if not members.has(str(key)):
			errors.append("unknown %s key '%s' (expected one of %s)" % [nest, key, members.keys()])
			continue
		spec[members[str(key)]] = (value as Dictionary)[key]


## `weapons[].projectile` -> `weapons[].emits`: a DOC-key rename only. The class
## and the scene property it writes are untouched, so the internal name stays
## `projectile` and this is the only place the two spellings meet.
static func _normalize_weapons(spec: Dictionary, errors: Array) -> void:
	if not (spec.get("weapons") is Array):
		return
	for entry in spec["weapons"] as Array:
		if not (entry is Dictionary):
			continue
		var weapon: Dictionary = entry
		var where: String = str(weapon.get("name", "?"))
		if weapon.has("projectile"):
			errors.append("weapon '%s': `projectile:` is now `emits:`" % where)
			weapon.erase("projectile")
		if weapon.has("emits"):
			weapon["projectile"] = weapon["emits"]
			weapon.erase("emits")


## The three keys the nesting pass introduced. Each is validated here rather than
## in SpecRegistry._validate_piece because each applies to every kind that has a
## body, and none of them has a consumer yet — see the README's schema section.
static func _check_new_keys(spec: Dictionary, errors: Array) -> void:
	if spec.has("commandable") and not (spec["commandable"] is bool):
		(
			errors
			. append(
				"commandable must be true or false (it is an OVERRIDE of the derivation, not a declaration)"
			)
		)
	if spec.has("completes_as"):
		var completes: String = str(spec["completes_as"])
		if not COMPLETES_AS.has(completes):
			errors.append("build.completes_as '%s' must be one of %s" % [completes, COMPLETES_AS])


# --------------------------------------------------------------------------- #
# The canonical-order rewrite
# --------------------------------------------------------------------------- #
## Returns `a_text` with its frontmatter block rewritten into canonical order.
## A document with no frontmatter, or an unclosed fence, comes back unchanged.
static func reorder_frontmatter(text: String) -> String:
	var lines: PackedStringArray = text.split("\n")
	if lines.size() == 0 or lines[0].strip_edges() != "---":
		return text
	var fence_end: int = -1
	for i in range(1, lines.size()):
		var stripped: String = lines[i].strip_edges()
		if stripped == "---" or stripped == "...":
			fence_end = i
			break
	if fence_end == -1:
		return text
	var body: Array = []
	for i in range(1, fence_end):
		body.append(lines[i])
	var out: Array = [lines[0]]
	out.append_array(_reorder_level(body, 0, ""))
	for i in range(fence_end, lines.size()):
		out.append(lines[i])
	return "\n".join(out)


## One MAPPING level, at exactly `a_indent`. Returns the level's lines reordered,
## or the lines untouched when the level is not a shape this understands.
static func _reorder_level(lines: Array, indent: int, parent_key: String) -> Array:
	var order: Array = NESTED_ORDER.get(parent_key, []) if parent_key != "" else TOP_LEVEL_ORDER
	var blocks: Array = []
	# Blank and comment lines waiting for the key they introduce. A key's own TRAILING
	# blanks never reach here — _absorb_body keeps those with their block.
	var pending: Array = []
	var i: int = 0
	while i < lines.size():
		var line: String = str(lines[i])
		var stripped: String = line.strip_edges()
		var line_indent: int = _indent_of(line)
		if stripped == "" or (stripped.begins_with("#") and line_indent <= indent):
			pending.append(line)
			i += 1
			continue
		if line_indent != indent:
			return lines  # irregular indentation: leave the level exactly as authored
		var content: String = line.substr(line_indent)
		if content.begins_with("- ") or content == "-":
			return lines  # a sequence, not a mapping — handled by _reorder_sequence
		var colon: int = SpecFrontmatter.key_colon(content)
		if colon == -1:
			return lines
		var block: Dictionary = {
			"key": _unquote(content.substr(0, colon).strip_edges()),
			"trivia": pending,
			"lines": [line],
			"orig": blocks.size(),
		}
		pending = []
		i = _absorb_body(lines, i + 1, indent, block["lines"])
		blocks.append(block)
	if blocks.is_empty():
		return lines
	for block: Dictionary in blocks:
		_reorder_block_body(block, indent)
	blocks.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var ra: int = _rank(str(a["key"]), order)
			var rb: int = _rank(str(b["key"]), order)
			return int(a["orig"]) < int(b["orig"]) if ra == rb else ra < rb
	)
	var out: Array = []
	for block: Dictionary in blocks:
		out.append_array(block["trivia"])
		out.append_array(block["lines"])
	out.append_array(pending)  # trailing trivia belongs to no key
	return out


## Consumes one key's body: every following line indented deeper than the key, plus
## the blank lines between them. Returns the index of the first line that is not
## part of it.
##
## `a_take_same_indent_items` is what separates the two callers. A KEY may own a
## sequence written at its own indent (YAML allows it and two docs in the roster do
## it), so it takes those; a sequence ITEM must not, or the first item would swallow
## every item after it.
static func _absorb_body(
	lines: Array, start: int, indent: int, out: Array, take_same_indent_items: bool = true
) -> int:
	var i: int = start
	var pending: Array = []
	while i < lines.size():
		var line: String = str(lines[i])
		var stripped: String = line.strip_edges()
		if stripped == "":
			pending.append(line)
			i += 1
			continue
		var line_indent: int = _indent_of(line)
		var content: String = line.substr(line_indent)
		var belongs: bool = (
			line_indent > indent
			or (
				take_same_indent_items
				and line_indent == indent
				and (content.begins_with("- ") or content == "-")
			)
		)
		if not belongs:
			break
		out.append_array(pending)
		pending = []
		out.append(line)
		i += 1
	# Trailing blank lines stay with THIS block: inside a block scalar they are the
	# value's own paragraph breaks, and moving them to the next key would tear one apart.
	out.append_array(pending)
	return i


## Recurses into one key block's body, which is either a nested mapping or a
## sequence whose items are mappings. A block scalar (`key: |`) and an inline
## value are both left alone — there is nothing below them to order.
static func _reorder_block_body(block: Dictionary, _indent: int) -> void:
	var lines: Array = block["lines"]
	if lines.size() < 2:
		return
	var key_line: String = str(lines[0])
	var colon: int = SpecFrontmatter.key_colon(key_line.substr(_indent_of(key_line)))
	if colon == -1:
		return
	var rest: String = key_line.substr(_indent_of(key_line) + colon + 1).strip_edges()
	if rest != "":
		return  # an inline value, or a block scalar — its body is not a mapping
	var body: Array = lines.slice(1)
	var first: int = _first_content(body)
	if first == -1:
		return
	var body_indent: int = _indent_of(str(body[first]))
	var content: String = str(body[first]).substr(body_indent)
	var reordered: Array = (
		_reorder_sequence(body, body_indent, str(block["key"]))
		if (content.begins_with("- ") or content == "-")
		else _reorder_level(body, body_indent, str(block["key"]))
	)
	var out: Array = [key_line]
	out.append_array(reordered)
	block["lines"] = out


## A sequence's ITEM ORDER is data and is never touched; only the keys inside each
## item are reordered. An item whose first key would end up behind a comment, or
## whose dash is not followed by exactly one space, is left as authored.
static func _reorder_sequence(lines: Array, indent: int, parent_key: String) -> Array:
	var out: Array = []
	var item: Array = []
	var i: int = 0
	while i < lines.size():
		var line: String = str(lines[i])
		var stripped: String = line.strip_edges()
		var line_indent: int = _indent_of(line)
		var content: String = line.substr(line_indent)
		var starts_item: bool = (
			stripped != ""
			and line_indent == indent
			and (content.begins_with("- ") or content == "-")
		)
		if starts_item:
			if not item.is_empty():
				out.append_array(_reorder_item(item, indent, parent_key))
			item = [line]
			i = _absorb_body(lines, i + 1, indent, item, false)
			continue
		if item.is_empty():
			out.append(line)  # leading trivia
			i += 1
			continue
		return lines  # something at the item level that is not an item
	if not item.is_empty():
		out.append_array(_reorder_item(item, indent, parent_key))
	return out


static func _reorder_item(item: Array, indent: int, parent_key: String) -> Array:
	var dash_line: String = str(item[0])
	var content: String = dash_line.substr(indent)
	if not content.begins_with("- ") or content.substr(2).begins_with(" "):
		return item
	var content_col: int = indent + INDENT_STEP
	if SpecFrontmatter.key_colon(content.substr(2)) == -1:
		return item  # a scalar item; it has no keys to order
	var virtual: Array = [" ".repeat(content_col) + content.substr(2)]
	virtual.append_array(item.slice(1))
	var reordered: Array = _reorder_level(virtual, content_col, parent_key)
	var head: String = str(reordered[0])
	if head.strip_edges().begins_with("#") or _indent_of(head) != content_col:
		return item  # the dash would land on a comment; leave the item alone
	var out: Array = [" ".repeat(indent) + "- " + head.substr(content_col)]
	out.append_array(reordered.slice(1))
	return out


# --------------------------------------------------------------------------- #
# Small helpers
# --------------------------------------------------------------------------- #
## An unknown key ranks after every known one, and ties are broken by the
## authored position — so unknown keys sort to the END of their level, in the
## order they were written, rather than being dropped or shuffled.
static func _rank(key: String, order: Array) -> int:
	var index: int = order.find(key)
	return index if index != -1 else order.size()


static func _indent_of(line: String) -> int:
	var n: int = 0
	while n < line.length() and line[n] == " ":
		n += 1
	return n


static func _first_content(lines: Array) -> int:
	for i in lines.size():
		var stripped: String = str(lines[i]).strip_edges()
		if stripped != "" and not stripped.begins_with("#"):
			return i
	return -1


static func _unquote(text: String) -> String:
	if (
		(text.begins_with('"') and text.ends_with('"') and text.length() >= 2)
		or (text.begins_with("'") and text.ends_with("'") and text.length() >= 2)
	):
		return text.substr(1, text.length() - 2)
	return text
