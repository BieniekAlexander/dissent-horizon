extends GutTest

## Tool registry + tool-specific lookups. The registry is BUILT FROM GENERATED
## DATA (resources/generated/tools.json, derived from the gdd piece docs by the
## spec importer), so these tests pin the loading contract — key/name agreement,
## id lookups, context partitioning — rather than a hardcoded roster list, which
## now lives in the docs. The shared grid placement / collision review (on
## ControlBinding) is covered by test_ControlBinding.gd.

func test_registry_is_populated_from_generated_data() -> void:
	# The exact size is doc-governed; a sane lower bound catches a broken load
	# (an empty registry) without re-pinning the roster here.
	assert_gt(Tool.command_tool_map.size(), 10, "registry loads from tools.json")

func test_registry_matches_tools_json() -> void:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://resources/generated/tools.json"))
	assert_true(parsed is Dictionary)
	assert_eq(Tool.command_tool_map.size(), (parsed as Dictionary).size())
	for command_name in parsed:
		var t: Tool = Tool.for_name(command_name)
		assert_not_null(t, "registry has %s" % command_name)
		if t != null:
			assert_eq(String(t.type), str(parsed[command_name]["id"]))

func test_each_entry_key_matches_its_command_name() -> void:
	# The dict key and the Tool's own command_name must agree (no drift).
	for key in Tool.command_tool_map:
		var t: Tool = Tool.command_tool_map[key]
		assert_eq(t.command_name, key, "key %s == Tool.command_name" % key)

func test_command_name_convention_is_command_tool_id() -> void:
	for key in Tool.command_tool_map:
		var t: Tool = Tool.command_tool_map[key]
		assert_eq(t.command_name, "command_tool_%s" % t.type)

func test_for_name_returns_the_tool() -> void:
	# Asked of whatever build tool the docs currently define, not of a named piece. This
	# test used to pin `tc_armory`; when that doc was deleted the EntityIds const went with
	# it, which is a PARSE error — so GUT dropped this whole file and still reported the run
	# green (CLAUDE.md §A skipped test file is invisible). The lookup contract is the
	# subject, and it holds for every entry.
	var entry: Tool = _a_build_tool()
	var t: Tool = Tool.for_name(entry.command_name)
	assert_not_null(t)
	assert_eq(t, entry, "for_name hands back the registry's own Tool")
	assert_eq(t.control_context, ControlBinding.ControlContext.BUILD)
	assert_false(t.label.is_empty(), "and it carries a display label")


func test_the_button_label_is_the_doc_title_not_the_id() -> void:
	# The regression this pins: the grid used to read a separate ui.label, so a doc whose
	# label was still the raw id put "an_commandCenter" on the button while its title
	# said "Stronghold". There is one display name now, and it is the title.
	assert_eq(Tool.for_name("command_tool_an_commandCenter").label, "Stronghold")


func test_every_tool_carries_a_simple_tooltip() -> void:
	# No build/train button reaches the player undescribed — VerboseTooltipButton would
	# replace a blank one with its TODO placeholder and push an error.
	for key in Tool.command_tool_map:
		var t: Tool = Tool.command_tool_map[key]
		assert_false(t.simple_tooltip.is_empty(), "%s has a tooltip" % key)


func test_the_tooltip_tiers_say_what_the_piece_costs_and_what_it_is() -> void:
	# Synthesized from the same doc the rest of the import reads (see
	# SpecGenerators.tool_tooltip), so a rebalanced piece re-describes itself.
	# Over the WHOLE registry rather than one named piece: synthesis is a property of every
	# entry, and pinning one piece is what left this file unparseable when that piece was
	# deleted. `technology.json` supplies the cost the tooltip should be quoting — a second
	# generated artifact derived from the same doc, so the two agreeing is a real check.
	var technology: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://resources/generated/technology.json")) as Dictionary
	for key: String in Tool.command_tool_map:
		var t: Tool = Tool.command_tool_map[key]
		assert_string_contains(t.simple_tooltip, t.label, "%s names the piece" % key)
		var energy: int = int(technology.get(String(t.type), {}).get("cost", {}).get("energy", 0))
		if energy > 0:
			assert_string_contains(t.simple_tooltip, "%d energy" % energy, "%s quotes its cost" % key)
		# The verbose tier opens with the simple line and then goes on.
		assert_true(t.verbose_tooltip.begins_with(t.simple_tooltip), "%s: verbose extends simple" % key)
		assert_gt(t.verbose_tooltip.length(), t.simple_tooltip.length(), "%s: and says more" % key)


func test_a_structure_builds_and_a_unit_trains() -> void:
	# The verb follows the CONTEXT, for every tool — a rule, rather than two pieces that
	# happen to demonstrate it today.
	for t: Tool in Tool.tools_in_context(ControlBinding.ControlContext.BUILD):
		assert_string_contains(t.simple_tooltip, "Build ", "%s is built" % t.command_name)
	for t: Tool in Tool.tools_in_context(ControlBinding.ControlContext.TRAIN):
		if t.is_upgrade:
			assert_string_contains(t.simple_tooltip, "Research ", "%s is researched" % t.command_name)
		else:
			assert_string_contains(t.simple_tooltip, "Train ", "%s is trained" % t.command_name)

func test_for_name_unknown_is_null() -> void:
	assert_null(Tool.for_name("command_tool_nope"))

func test_for_id_reverse_lookup() -> void:
	var t: Tool = Tool.for_id(EntityIds.AN_BIO_MEDIUM_DOMINION_GEN)
	assert_not_null(t)
	assert_eq(t.command_name, "command_tool_an_bioMedium_dominionGen")

func test_for_id_unknown_is_null() -> void:
	assert_null(Tool.for_id(&"no_such_piece"))

func test_tool_faction_mask_comes_from_doc_ui_factions() -> void:
	# Tool overrides ControlBinding's all-factions default with the doc's
	# ui.factions grouping (UI-layout metadata, not a gameplay gate).
	# tc_bioLight_builder rather than the deleted tc_armory: the technocracy has no
	# structures left, and what this pins is that a doc's ui.factions reaches faction_mask
	# at all — one non-default mask is enough to show it.
	assert_eq(Tool.for_name("command_tool_tc_bioLight_builder").faction_mask(), Tool.Faction.TECHNOCRACY)
	assert_eq(Tool.for_name("command_tool_an_commandCenter").faction_mask(), Tool.Faction.ANARCHISTS)

func test_contexts_derive_from_piece_kind() -> void:
	# Structures are placed (BUILD), units are trained (TRAIN).
	assert_eq(Tool.for_name("command_tool_an_barracks").control_context, ControlBinding.ControlContext.BUILD)
	assert_eq(Tool.for_name("command_tool_cl_bioLight_antiLight").control_context, ControlBinding.ControlContext.TRAIN)

func test_build_and_train_partition_the_registry() -> void:
	# Every tool is in exactly one of BUILD/TRAIN, together covering the registry.
	var total: int = Tool.tools_in_context(ControlBinding.ControlContext.BUILD).size() \
		+ Tool.tools_in_context(ControlBinding.ControlContext.TRAIN).size()
	assert_eq(total, Tool.command_tool_map.size(), "build + train == all tools")

func test_act_context_has_no_registry_tools() -> void:
	# ACT is for verb commands (move/attack/…), which aren't registry Tools.
	assert_eq(Tool.tools_in_context(ControlBinding.ControlContext.ACT), [])


## Any one build tool from the live registry — whichever the docs currently define.
##
## Tests here pin the LOADING CONTRACT, never the roster (CLAUDE.md §A unit test does not
## assert facts about authored content); the roster lives in the gdd docs and is expected
## to change under them.
func _a_build_tool() -> Tool:
	var tools: Array = Tool.tools_in_context(ControlBinding.ControlContext.BUILD)
	assert_false(tools.is_empty(), "the registry has build tools")
	return tools[0]
