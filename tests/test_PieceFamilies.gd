extends GutTest

## Piece families (`family:`) and `variants:` — the importer's validation and derivation of them,
## the generated families.json / tools.json they publish, and the runtime readers
## (PieceFamilies, Tool.variants). Every registry here is built from fixtures; the shipped data is
## only checked for CONSISTENCY with the mechanic (a member's scene agrees with its template),
## never for what it says.

const SpecGenerators := preload("res://tools/spec_import/generators.gd")
const SpecSchema := preload("res://tools/spec_import/schema.gd")

const FAMILY: String = "neutral_building"
const SMALL: Dictionary = {
	"kind": "Entity",
	"family": FAMILY,
	"scene": "res://x/small.tscn",
	"footprint": [2, 2],
	"defense": {"hp": 600},
	"infrastructure": 50,
	"build": {"cost": {"energy": 500}, "time": 20}
}
const WIDE: Dictionary = {
	"kind": "Entity",
	"family": FAMILY,
	"scene": "res://x/wide.tscn",
	"footprint": [3, 5],
	"defense": {"hp": 1000},
	"infrastructure": 75,
	"build": {"cost": {"energy": 800}, "time": 25}
}
const HOST: Dictionary = {
	"kind": "Entity",
	"scene": "res://x/host.tscn",
	"senses": {"vision": "eyes"},
	"variants": ["small", "wide"],
	"ui": {"grid": [0, 0]}
}
const SHAPES: Dictionary = {"kind": "ShapeLibrary", "shapes": {"eyes": {"radius": 5}}}


func before_all() -> void:
	# Loading a scene can log engine warnings (a stale shape uid) the FIRST time; do it here so
	# GUT does not blame the test that happens to load it first.
	for template: PieceFamilies.Template in PieceFamilies.templates_of(
		PieceFamilies.NEUTRAL_BUILDING
	):
		template.load_scene()


func _registry(a_docs: Dictionary) -> RefCounted:
	var docs: Array = [{"path": "res://gdd/x/shapes.md", "data": SHAPES}]
	for id: String in a_docs:
		docs.append({"path": "res://gdd/x/%s.md" % id, "data": a_docs[id].duplicate(true)})
	var registry: RefCounted = SpecRegistry.new()
	registry.build(docs)
	return registry


func _assert_refused(a_docs: Dictionary, a_fragment: String) -> void:
	var errors: Array = _registry(a_docs).errors
	assert_true(
		errors.any(func(e: String) -> bool: return e.contains(a_fragment)),
		"refused with '%s': %s" % [a_fragment, errors]
	)


#region Validation
func test_a_valid_family_and_host_import_cleanly() -> void:
	assert_eq(_registry({"small": SMALL, "wide": WIDE, "host": HOST}).errors, [])


func test_an_unknown_family_is_refused() -> void:
	var bad: Dictionary = SMALL.duplicate(true)
	bad["family"] = "not_a_family"
	_assert_refused({"small": bad}, "is not one of")


func test_a_family_member_must_be_a_structure() -> void:
	var bad: Dictionary = {"kind": "Entity", "family": FAMILY, "movement": {"speed": "BRISK"}}
	var errors: Array = _registry({"small": bad}).errors
	assert_true(
		errors.any(func(e: String) -> bool: return e.contains("family members must be structures")),
		"a mobile family member is refused: %s" % [errors]
	)


func test_a_variant_naming_no_piece_is_refused() -> void:
	var host: Dictionary = HOST.duplicate(true)
	host["variants"] = ["small", "ghost"]
	_assert_refused({"small": SMALL, "host": host}, "unknown piece 'ghost'")


func test_a_variant_outside_every_family_is_refused() -> void:
	var loner: Dictionary = SMALL.duplicate(true)
	loner.erase("family")
	_assert_refused({"small": loner, "wide": WIDE, "host": HOST}, "has no family:")


func test_a_variant_that_is_not_a_structure_is_refused() -> void:
	var unit: Dictionary = {"kind": "Entity", "movement": {"speed": "BRISK"}}
	var host: Dictionary = HOST.duplicate(true)
	host["variants"] = ["unit"]
	_assert_refused({"unit": unit, "host": host}, "has no footprint:")


func test_an_empty_variant_list_is_refused() -> void:
	var host: Dictionary = HOST.duplicate(true)
	host["variants"] = []
	_assert_refused({"small": SMALL, "host": host}, "non-empty list")


func test_authoring_a_value_the_first_variant_supplies_is_refused() -> void:
	var host: Dictionary = HOST.duplicate(true)
	host["footprint"] = [1, 1]
	_assert_refused({"small": SMALL, "wide": WIDE, "host": host}, "is taken from the first variant")


func test_a_variant_may_not_have_variants_of_its_own() -> void:
	var nested: Dictionary = SMALL.duplicate(true)
	nested["variants"] = ["wide"]
	_assert_refused({"small": nested, "wide": WIDE, "host": HOST}, "variants of its own")


#endregion


#region Derivation
func test_the_host_takes_its_numbers_from_the_first_variant() -> void:
	var host: Dictionary = _registry({"small": SMALL, "wide": WIDE, "host": HOST}).pieces["host"]
	assert_eq(host["footprint"], [2, 2])
	assert_eq(host["hp"], 600)
	assert_eq(host["cost"], {"energy": 500})
	assert_eq(host["build_time"], 20)
	assert_eq(host["infrastructure"], 50)


func test_the_first_listed_variant_is_the_default_not_the_first_alphabetically() -> void:
	var host: Dictionary = HOST.duplicate(true)
	host["variants"] = ["wide", "small"]
	var derived: Dictionary = _registry({"small": SMALL, "wide": WIDE, "host": host}).pieces["host"]
	assert_eq(derived["footprint"], [3, 5])
	assert_eq(derived["infrastructure"], 75)


func test_a_host_gets_no_placeholder_price() -> void:
	var registry: RefCounted = _registry(
		{"small": SMALL, "host": HOST.merged({"variants": ["small"]}, true)}
	)
	assert_eq(
		registry.pieces["host"]["cost"],
		{"energy": 500},
		"the variant's price, not the 100-energy default"
	)


func test_a_family_member_carries_its_family_as_a_group() -> void:
	assert_true(SpecSchema.derived_groups({"footprint": [1, 1], "family": FAMILY}).has(FAMILY))
	assert_false(SpecSchema.derived_groups({"footprint": [1, 1]}).has(FAMILY))


func test_every_family_is_a_group_the_importer_owns() -> void:
	for family: String in SpecSchema.FAMILIES:
		assert_true(
			SpecSchema.DERIVED_GROUPS.has(family),
			"%s must be in DERIVED_GROUPS so a stale copy is removed" % family
		)


#endregion


#region Generated data
func test_families_json_lists_members_and_their_templates() -> void:
	var registry: RefCounted = _registry({"small": SMALL, "wide": WIDE, "host": HOST})
	var table: PieceFamilies.Table = PieceFamilies.parse(SpecGenerators.families_json(registry))
	assert_eq(
		table.members[StringName(FAMILY)],
		[&"small", &"wide"] as Array[StringName],
		"alphabetical, and the host is not a member"
	)
	var wide: PieceFamilies.Template = table.templates[&"wide"]
	assert_eq(wide.footprint, Vector2i(3, 5))
	assert_eq(wide.hp, 1000.0)
	assert_eq(wide.energy_cost, 800)
	assert_eq(wide.build_time_ticks, TimeUtils.ticks_from_seconds(25.0))
	assert_eq(wide.infrastructure, 75)
	assert_eq(wide.scene_path, "res://x/wide.tscn")


func test_tools_json_publishes_the_variants_in_order() -> void:
	var registry: RefCounted = _registry({"small": SMALL, "wide": WIDE, "host": HOST})
	var entry: Dictionary = SpecGenerators.tools_table(registry)["command_tool_host"]
	assert_eq(entry["variants"], ["small", "wide"])
	var tool: Tool = Tool.from_entry("command_tool_host", entry, null)
	assert_eq(tool.variants, [&"small", &"wide"] as Array[StringName])


func test_a_tool_without_variants_has_none() -> void:
	var registry: RefCounted = _registry({"small": SMALL.merged({"ui": {"grid": [0, 0]}}, true)})
	var tool: Tool = Tool.from_entry(
		"command_tool_small",
		SpecGenerators.tools_table(registry, false)["command_tool_small"],
		null
	)
	assert_eq(tool.variants, [] as Array[StringName])


#endregion


#region The runtime reader
func test_parse_of_garbage_is_an_empty_table() -> void:
	var table: PieceFamilies.Table = PieceFamilies.parse("{ not json")
	assert_true(table.members.is_empty())
	assert_true(table.templates.is_empty())
	assert_push_error("cannot parse")


func test_an_unknown_piece_has_no_template() -> void:
	assert_null(PieceFamilies.template(&"definitely_not_a_piece"))
	assert_false(PieceFamilies.is_member(&"definitely_not_a_piece", PieceFamilies.NEUTRAL_BUILDING))
	assert_eq(PieceFamilies.members(&"definitely_not_a_family"), [] as Array[StringName])


#endregion


#region The shipped data agrees with the mechanic
## Not a statement about WHAT the pieces are: only that each template describes the scene it
## names, and that a member's scene keeps its infrastructure off the commander's books.
func test_every_shipped_member_scene_agrees_with_its_template() -> void:
	for family: String in SpecSchema.FAMILIES:
		for template: PieceFamilies.Template in PieceFamilies.templates_of(StringName(family)):
			var root: Entity = template.load_scene().instantiate() as Entity
			assert_not_null(root, "%s: scene loads" % template.id)
			assert_eq(root.id, template.id, "%s: the scene carries its own id" % template.id)
			assert_true(root.is_in_group(family), "%s: in group %s" % [template.id, family])
			assert_eq(
				(root.get_node("Fixture") as Fixture).dimensions,
				template.footprint,
				"%s: footprint" % template.id
			)
			assert_eq(
				(root.get_node("Defense") as Defense).hp_max, template.hp, "%s: hp" % template.id
			)
			assert_eq(
				(root as Actor).infrastructure,
				0,
				"%s: a member scene grants no infrastructure by standing on the map" % template.id
			)
			assert_true(PieceFamilies.is_member(template.id, StringName(family)))
			root.free()


func test_every_variant_a_shipped_tool_names_has_a_template() -> void:
	for tool: Tool in Tool.command_tool_map.values():
		for variant: StringName in tool.variants:
			assert_not_null(
				PieceFamilies.template(variant), "%s: variant %s" % [tool.type, variant]
			)
#endregion
