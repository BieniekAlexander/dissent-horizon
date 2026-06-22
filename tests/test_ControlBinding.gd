extends GutTest

## ControlBinding: the grid placement math + collision review shared by every grid
## command (verbs and Tools). The collision review runs over the WHOLE grid —
## CommandGrid.bindings() (verbs + tools) — so verb↔tool overlaps are reviewed too,
## not just tool↔tool.

func test_cell_index_is_row_major() -> void:
	assert_eq(ControlBinding.cell_index(Vector2i(0, 0)), 0)
	assert_eq(ControlBinding.cell_index(Vector2i(1, 0)), 1)
	assert_eq(ControlBinding.cell_index(Vector2i(0, 1)), ControlBinding.grid_width)
	assert_eq(ControlBinding.cell_index(Vector2i(2, 1)), ControlBinding.grid_width + 2)

func test_position_in_bounds() -> void:
	assert_true(ControlBinding.position_in_bounds(Vector2i(0, 0)))
	assert_true(ControlBinding.position_in_bounds(Vector2i(ControlBinding.grid_width - 1, ControlBinding.grid_height - 1)))
	assert_false(ControlBinding.position_in_bounds(Vector2i(-1, 0)))
	assert_false(ControlBinding.position_in_bounds(Vector2i(ControlBinding.grid_width, 0)))
	assert_false(ControlBinding.position_in_bounds(Vector2i(0, ControlBinding.grid_height)))

func test_base_binding_faction_mask_is_all_factions() -> void:
	# A plain (verb) binding is faction-agnostic: all-ones, so faction can never be
	# what separates it from a tool in the collision review.
	var verb := ControlBinding.new("command_stop", "Stop", Vector2i(1, 1), ControlBinding.ControlContext.ACT)
	assert_eq(verb.faction_mask(), ControlBinding.FACTION_ANY)

func test_all_grid_positions_in_bounds() -> void:
	# Hard invariant across the WHOLE grid: every button must fit, else CommandGrid
	# can't place it.
	assert_eq(ControlBinding.out_of_bounds(CommandGrid.bindings()), [],
		"all grid positions valid")

## Review gate over the whole grid: any cell overlap between bindings that could
## appear together (control_context AND faction_mask both intersect) must be listed
## here, having been reviewed and judged acceptable. A NEW unlisted collision fails
## this test — review it, then move a binding or acknowledge it here. Verb↔tool
## overlaps (e.g. Build/mine, Attack/compound, Stop/armory) are NOT listed: the verb
## is ACT and the tool is BUILD, so they never co-appear.
const _ACKNOWLEDGED_COLLISIONS: Array = [
	# technician + warlord share (1,2); both TRAIN + ANARCHISTS. Acceptable while
	# no single structure trains both (they come from different producers).
	"command_tool_technician + command_tool_warlord @ (1, 2)",
]

func test_grid_collisions_are_all_acknowledged() -> void:
	assert_eq(ControlBinding.grid_collisions(CommandGrid.bindings()), _ACKNOWLEDGED_COLLISIONS,
		"unreviewed grid collision(s) — move a binding or add to _ACKNOWLEDGED_COLLISIONS")
