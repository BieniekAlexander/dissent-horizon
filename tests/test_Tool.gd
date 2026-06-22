extends GutTest

## Phase 1 of the command_tool consolidation: Tool is the single registry, and
## the derived lookups stay in sync with command_tool_map. These lock the new API
## before command_context_parser / command_grid / bot migrate onto it (Phase 2).

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
	assert_eq(t.category, Tool.Category.BUILD)

func test_for_name_unknown_is_null() -> void:
	assert_null(Tool.for_name("command_tool_nope"))

func test_for_type_reverse_lookup() -> void:
	var t: Tool = Tool.for_type(Entity.Type.AN_UNIT_WARLORD)
	assert_not_null(t)
	assert_eq(t.command_name, "command_tool_warlord")

func test_for_type_unknown_is_null() -> void:
	assert_null(Tool.for_type(Entity.Type.UNDEFINED))

func test_label_for() -> void:
	assert_eq(Tool.label_for("command_tool_warlord"), "Warlord")
	assert_eq(Tool.label_for("command_tool_nope"), "", "unknown name → empty label")

func test_build_tool_names_are_the_structures_in_order() -> void:
	assert_eq(Tool.build_tool_names(), [
		"command_tool_dwelling",
		"command_tool_mine",
		"command_tool_redoubt",
		"command_tool_lab",
		"command_tool_compound",
		"command_tool_armory",
	])

func test_train_tool_names_are_the_units_in_order() -> void:
	assert_eq(Tool.train_tool_names(), [
		"command_tool_technician",
		"command_tool_irregular",
		"command_tool_warlord",
		"command_tool_vanguard",
	])

func test_build_and_train_partition_the_registry() -> void:
	# Every tool is in exactly one category, and together they cover the registry.
	var total: int = Tool.build_tool_names().size() + Tool.train_tool_names().size()
	assert_eq(total, Tool.command_tool_map.size(), "build + train == all tools")

# --- HUD grid placement + collision review (Phase 3) -----------------------

func test_cell_index_is_row_major() -> void:
	assert_eq(Tool.cell_index(Vector2i(0, 0)), 0)
	assert_eq(Tool.cell_index(Vector2i(1, 0)), 1)
	assert_eq(Tool.cell_index(Vector2i(0, 1)), Tool.grid_width)
	assert_eq(Tool.cell_index(Vector2i(2, 1)), Tool.grid_width + 2)

func test_position_in_bounds() -> void:
	assert_true(Tool.position_in_bounds(Vector2i(0, 0)))
	assert_true(Tool.position_in_bounds(Vector2i(Tool.grid_width - 1, Tool.grid_height - 1)))
	assert_false(Tool.position_in_bounds(Vector2i(-1, 0)))
	assert_false(Tool.position_in_bounds(Vector2i(Tool.grid_width, 0)))
	assert_false(Tool.position_in_bounds(Vector2i(0, Tool.grid_height)))

func test_all_tool_positions_in_bounds() -> void:
	# Hard invariant: every tool must fit the grid, else command_grid can't place it.
	assert_eq(Tool.out_of_bounds_positions(), [], "all tool grid positions valid")

## Review gate: any grid-cell overlap between tools that could appear together
## (control_context AND faction both intersect) must be listed here, having been
## reviewed and judged acceptable. A NEW unlisted collision fails this test —
## review it, then either move a tool's grid_position or acknowledge it here.
const _ACKNOWLEDGED_COLLISIONS: Array = [
	# technician + warlord share (1,2); both TRAIN + ANARCHISTS. Acceptable while
	# no single structure trains both (they come from different producers).
	"command_tool_technician + command_tool_warlord @ (1, 2)",
]

func test_grid_collisions_are_all_acknowledged() -> void:
	assert_eq(Tool.grid_collisions(), _ACKNOWLEDGED_COLLISIONS,
		"unreviewed grid collision(s) — move a tool or add to _ACKNOWLEDGED_COLLISIONS")
