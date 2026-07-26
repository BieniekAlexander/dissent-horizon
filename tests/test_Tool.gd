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
	var t: Tool = Tool.for_name("command_tool_dwelling")
	assert_not_null(t)
	assert_eq(t.type, EntityIds.DWELLING)
	assert_eq(t.label, "Dwelling")
	assert_eq(t.control_context, ControlBinding.ControlContext.BUILD)

func test_for_name_unknown_is_null() -> void:
	assert_null(Tool.for_name("command_tool_nope"))

func test_for_id_reverse_lookup() -> void:
	var t: Tool = Tool.for_id(EntityIds.WARLORD)
	assert_not_null(t)
	assert_eq(t.command_name, "command_tool_warlord")

func test_for_id_unknown_is_null() -> void:
	assert_null(Tool.for_id(&"no_such_piece"))

func test_tool_faction_mask_comes_from_doc_ui_factions() -> void:
	# Tool overrides ControlBinding's all-factions default with the doc's
	# ui.factions grouping (UI-layout metadata, not a gameplay gate).
	assert_eq(Tool.for_name("command_tool_dwelling").faction_mask(), Tool.Faction.TECHNOCRACY)
	assert_eq(Tool.for_name("command_tool_stronghold").faction_mask(), Tool.Faction.ANARCHISTS)

func test_contexts_derive_from_piece_kind() -> void:
	# Structures are placed (BUILD), units are trained (TRAIN).
	assert_eq(Tool.for_name("command_tool_barracks").control_context, ControlBinding.ControlContext.BUILD)
	assert_eq(Tool.for_name("command_tool_recruit").control_context, ControlBinding.ControlContext.TRAIN)

func test_build_and_train_partition_the_registry() -> void:
	# Every tool is in exactly one of BUILD/TRAIN, together covering the registry.
	var total: int = Tool.tools_in_context(ControlBinding.ControlContext.BUILD).size() \
		+ Tool.tools_in_context(ControlBinding.ControlContext.TRAIN).size()
	assert_eq(total, Tool.command_tool_map.size(), "build + train == all tools")

func test_act_context_has_no_registry_tools() -> void:
	# ACT is for verb commands (move/attack/…), which aren't registry Tools.
	assert_eq(Tool.tools_in_context(ControlBinding.ControlContext.ACT), [])
