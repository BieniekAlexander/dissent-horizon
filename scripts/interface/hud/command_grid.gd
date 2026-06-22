extends GridContainer

## Data-driven command grid: a Tool.grid_width × Tool.grid_height grid of cells.
## Tool buttons place themselves at their Tool.grid_position (from the registry);
## the verb-command buttons below carry their own fixed positions. Several buttons
## landing in one cell stack inside that cell's BoxContainer — see
## Tool.grid_collisions() for reviewing when that overlap is actually a problem.

#region Lifecycle
func _ready() -> void:
	columns = Tool.grid_width

	# Verb commands aren't registry Tools, so their cells are defined here:
	# [command_name, label, grid cell].
	var verb_buttons: Array = [
		["command_ability", "Build", Vector2i(2, 0)],
		["command_attack_move", "Attack", Vector2i(0, 1)],
		["command_stop", "Stop", Vector2i(1, 1)],
		["command_defend", "Defend", Vector2i(2, 1)],
		["command_evacuate", "Evacuate", Vector2i(3, 1)],
		["command_launch", "Radiate", Vector2i(4, 1)],
		["command_land", "Land", Vector2i(0, 2)],
	]

	# One BoxContainer cell per grid slot, row-major (index = y*width + x). The
	# GridContainer lays its children out in this order via `columns`.
	var cells: Array = []
	for i in Tool.grid_width * Tool.grid_height:
		var cell := BoxContainer.new()
		add_child(cell)
		cell.custom_minimum_size = Vector2(60, 60)
		cell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cells.append(cell)

	# Verb commands (fixed positions above).
	for entry: Array in verb_buttons:
		_place_button(cells, ButtonSpec.new(entry[0], entry[1]), entry[2])

	# Tools (positions sourced from the Tool registry).
	for tool: Tool in Tool.command_tool_map.values():
		_place_button(cells, ButtonSpec.for_tool(tool.command_name), tool.grid_position)
#endregion

#region Private helpers
func _place_button(cells: Array, spec: ButtonSpec, grid_cell: Vector2i) -> void:
	if not Tool.position_in_bounds(grid_cell):
		push_error("command_grid: '%s' has out-of-bounds grid cell %s" % [spec.control, grid_cell])
		return
	var b: Button = ButtonSpec.create_button_from_spec(spec)
	b.custom_minimum_size = Vector2(60, 60)
	cells[Tool.cell_index(grid_cell)].add_child(b)
#endregion
