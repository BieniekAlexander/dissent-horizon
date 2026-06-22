extends GutTest

## Tool registry + tool-specific lookups. The shared grid placement / collision
## review (now on ControlBinding) is covered by test_ControlBinding.gd.

func test_registry_is_populated() -> void:
	assert_eq(Tool.command_tool_map.size(), 10, "10 tools in the registry")

func test_each_entry_key_matches_its_command_name() -> void:
	# The dict key and the Tool's own command_name must agree (no within-file drift).
	for key in Tool.command_tool_map:
		var t: Tool = Tool.command_tool_map[key]
		assert_eq(t.command_name, key, "key %s == Tool.command_name" % key)

func test_for_name_returns_the_tool() -> void:
	var t: Tool = Tool.for_name("command_tool_dwelling")
	assert_not_null(t)
	assert_eq(t.type, Entity.Type.TC_STRUCTURE_DWELLING)
	assert_eq(t.label, "Dwelling")
	assert_eq(t.control_context, ControlBinding.ControlContext.BUILD)

func test_for_name_unknown_is_null() -> void:
	assert_null(Tool.for_name("command_tool_nope"))

func test_for_type_reverse_lookup() -> void:
	var t: Tool = Tool.for_type(Entity.Type.AN_UNIT_WARLORD)
	assert_not_null(t)
	assert_eq(t.command_name, "command_tool_warlord")

func test_for_type_unknown_is_null() -> void:
	assert_null(Tool.for_type(Entity.Type.UNDEFINED))

func test_tool_faction_mask_is_its_faction() -> void:
	# Tool overrides ControlBinding's all-factions default with its real faction.
	assert_eq(Tool.for_name("command_tool_dwelling").faction_mask(), Tool.Faction.TECHNOCRACY)
	assert_eq(Tool.for_name("command_tool_redoubt").faction_mask(), Tool.Faction.ANARCHISTS)

func _names(tools: Array) -> Array:
	return tools.map(func(t: Tool): return t.command_name)

func test_build_context_tools_are_the_structures_in_order() -> void:
	assert_eq(_names(Tool.tools_in_context(ControlBinding.ControlContext.BUILD)), [
		"command_tool_dwelling",
		"command_tool_mine",
		"command_tool_redoubt",
		"command_tool_lab",
		"command_tool_compound",
		"command_tool_armory",
	])

func test_train_context_tools_are_the_units_in_order() -> void:
	assert_eq(_names(Tool.tools_in_context(ControlBinding.ControlContext.TRAIN)), [
		"command_tool_technician",
		"command_tool_irregular",
		"command_tool_warlord",
		"command_tool_vanguard",
	])

func test_build_and_train_partition_the_registry() -> void:
	# Every tool is in exactly one of BUILD/TRAIN, together covering the registry.
	var total: int = Tool.tools_in_context(ControlBinding.ControlContext.BUILD).size() \
		+ Tool.tools_in_context(ControlBinding.ControlContext.TRAIN).size()
	assert_eq(total, Tool.command_tool_map.size(), "build + train == all tools")

func test_act_context_has_no_registry_tools() -> void:
	# ACT is for verb commands (move/attack/…), which aren't registry Tools.
	assert_eq(Tool.tools_in_context(ControlBinding.ControlContext.ACT), [])
