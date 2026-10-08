@tool
class_name PieceFamilies
extends RefCounted

## Named sets of pieces (`family:` in a spec doc) and the TEMPLATE data of their members, read from
## the generated resources/generated/families.json — so gameplay and map generation enumerate
## "every neutral building" without matching on ids, and read a member's price without
## instantiating its scene.
##
## @tool because the map-generator dock (an editor plugin) reads it, and a non-tool script's
## statics do not run in the editor.
##
## Two ways to ask, for two situations:
##   * a NODE in the world: `node.is_in_group(PieceFamilies.NEUTRAL_BUILDING)` — the importer writes
##     the family's name as a group on every member's scene root.
##   * an ID or a whole family: members() / is_member() / template() here.
##
## A template's `infrastructure` is what the piece grants once BUILT AS ANOTHER PIECE
## (an_infrastructure
## takes it from its variant). It is deliberately absent from the member's own scene, whose
## Actor.infrastructure stays 0: a neutral or garrison-captured building grants nothing.

const FAMILIES_JSON_PATH: String = "res://resources/generated/families.json"

## The neutral buildings — every `nt_building_*`. Also the group name on their roots.
const NEUTRAL_BUILDING: StringName = &"neutral_building"


## One member's spec numbers, as the importer resolved them from its doc.
class Template:
	extends RefCounted
	var id: StringName
	var family: StringName
	var scene_path: String
	## The doc's title — what the HUD calls this form.
	var title: String
	## Grid cells, as Structure.dimensions.
	var footprint: Vector2i
	var hp: float
	var energy_cost: int
	var build_time_ticks: int
	## What a piece built from this template provides (>0) or consumes (<0).
	var infrastructure: int

	func load_scene() -> PackedScene:
		return load(scene_path) as PackedScene


## The parsed families.json: family -> Array[StringName] of member ids (alphabetical, the
## generator's order), and piece id -> Template.
class Table:
	extends RefCounted
	var members: Dictionary = {}
	var templates: Dictionary = {}


## Lazily loaded, then cached — the file only changes when the importer runs.
static var _table: Table = null


## Every member id of `a_family`, or an empty array for an unknown family.
static func members(a_family: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(_loaded().members.get(a_family, []))
	return out


## Every member's template, in members() order.
static func templates_of(a_family: StringName) -> Array[Template]:
	var out: Array[Template] = []
	for id: StringName in members(a_family):
		out.append(_loaded().templates[id])
	return out


## `a_id`'s template, or null when the piece belongs to no family (null means "no template
## data", never "free").
static func template(a_id: StringName) -> Template:
	return _loaded().templates.get(a_id)


## Whether the piece id is a member of `a_family`.
static func is_member(a_id: StringName, a_family: StringName) -> bool:
	var found: Template = template(a_id)
	return found != null and found.family == a_family


## families.json text as a Table; an unparseable text yields an empty one (and an error).
static func parse(a_text: String) -> Table:
	var table := Table.new()
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(a_text) == OK else null
	if not (parsed is Dictionary):
		push_error("PieceFamilies: cannot parse %s — run the spec importer" % FAMILIES_JSON_PATH)
		return table
	var families: Dictionary = (parsed as Dictionary).get("families", {})
	for family: String in families:
		var ids: Array[StringName] = []
		for id: Variant in families[family]:
			ids.append(StringName(str(id)))
		table.members[StringName(family)] = ids
	var templates: Dictionary = (parsed as Dictionary).get("templates", {})
	for id: String in templates:
		var entry: Dictionary = templates[id]
		var built: Template = Template.new()
		built.id = StringName(id)
		built.family = StringName(str(entry["family"]))
		built.scene_path = str(entry["scene"])
		built.title = str(entry.get("title", id))
		built.footprint = Vector2i(int(entry["footprint"][0]), int(entry["footprint"][1]))
		built.hp = float(entry["hp"])
		built.energy_cost = int(entry["energy_cost"])
		built.build_time_ticks = int(entry["build_time_ticks"])
		built.infrastructure = int(entry["infrastructure"])
		table.templates[StringName(id)] = built
	return table


static func _loaded() -> Table:
	if _table == null:
		_table = parse(FileAccess.get_file_as_string(FAMILIES_JSON_PATH))
	return _table
