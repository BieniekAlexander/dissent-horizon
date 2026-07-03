class_name CommandGrid
extends GridContainer

## Data-driven command grid. EVERY button is a ControlBinding placed at its
## grid_position: verb commands are the plain ControlBindings in _VERB_BINDINGS
## below (no entity payload); tool buttons come from the Tool registry. bindings()
## is the single source the grid builds from — and the same set the collision
## review (ControlBinding.grid_collisions) is checked against in tests.
##
## Buttons that land in the same cell stack in that cell's BoxContainer; whether
## that overlap is a real problem is reviewed by ControlBinding.grid_collisions().

## Verb commands — plain ControlBindings (ACT context, no entity payload).
## _init args: command_name, label, grid_position, control_context.
static var _VERB_BINDINGS: Array = [
	ControlBinding.new("command_ability", "Build", Vector2i(2, 0), ControlBinding.ControlContext.ACT),
	ControlBinding.new("command_attack_move", "Attack", Vector2i(0, 1), ControlBinding.ControlContext.ACT),
	ControlBinding.new("command_stop", "Stop", Vector2i(1, 1), ControlBinding.ControlContext.ACT),
	ControlBinding.new("command_defend", "Defend", Vector2i(2, 1), ControlBinding.ControlContext.ACT),
	ControlBinding.new("command_evacuate", "Evacuate", Vector2i(3, 1), ControlBinding.ControlContext.ACT),
	ControlBinding.new("command_launch", "Radiate", Vector2i(4, 1), ControlBinding.ControlContext.ACT),
	ControlBinding.new("command_land", "Land", Vector2i(0, 2), ControlBinding.ControlContext.ACT),
]

## SELECT-context commands — shown only when nothing is selected. These don't
## act on a unit; the controller intercepts them in _on_control_button_pressed
## to select the least-recently-selected idle combat / builder unit.
static var _SELECT_BINDINGS: Array = [
	ControlBinding.new(RTSController.CMD_SELECT_IDLE_COMBAT, "Idle Army", Vector2i(0, 0), ControlBinding.ControlContext.SELECT),
	ControlBinding.new(RTSController.CMD_SELECT_IDLE_BUILDER, "Idle Builder", Vector2i(1, 0), ControlBinding.ControlContext.SELECT),
]

## Every binding in the grid, in placement order: verb commands, the
## nothing-selected selectors, then tools.
static func bindings() -> Array:
	return _VERB_BINDINGS + _SELECT_BINDINGS + Tool.command_tool_map.values()

#region Lifecycle
func _ready() -> void:
	columns = ControlBinding.grid_width

	# One BoxContainer cell per grid slot, row-major (index = y*width + x). The
	# GridContainer lays its children out in this order via `columns`.
	var cells: Array = []
	for i in ControlBinding.grid_width * ControlBinding.grid_height:
		var cell := BoxContainer.new()
		add_child(cell)
		# custom_minimum_size is the floor; EXPAND_FILL lets the cells grow to
		# divide up whatever rect the grid is given so the grid scales to fit
		# inside its border rather than sitting at a fixed pixel size.
		cell.custom_minimum_size = Vector2(60, 60)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cells.append(cell)

	for binding: ControlBinding in bindings():
		_place_button(cells, binding)
#endregion

#region Private helpers
func _place_button(cells: Array, binding: ControlBinding) -> void:
	if not ControlBinding.position_in_bounds(binding.grid_position):
		push_error("CommandGrid: '%s' has out-of-bounds grid cell %s" % [binding.command_name, binding.grid_position])
		return
	var b: Button = ButtonSpec.create_button_from_spec(ButtonSpec.new(binding.command_name, binding.label))
	b.custom_minimum_size = Vector2(60, 60)
	# Fill the cell so buttons scale with the grid instead of staying pinned to
	# their 60x60 floor.
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cells[ControlBinding.cell_index(binding.grid_position)].add_child(b)
#endregion
