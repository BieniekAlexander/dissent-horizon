extends GridContainer

#region Lifecycle
func _ready() -> void:
	columns = 5

	var grid_containers: Array = [
		[ButtonSpec.new("command_tool_outpost", "Outpost")],
		[ButtonSpec.new("command_tool_dwelling", "Dwelling")],
		[ButtonSpec.new("command_ability", "Build"), ButtonSpec.new("command_tool_mine", "Mine")],
		[ButtonSpec.new("command_tool_lab", "Lab")],
		[],
		[ButtonSpec.new("command_attack_move", "Attack"), ButtonSpec.new("command_tool_compound", "Compound")],
		[ButtonSpec.new("command_stop", "Stop"), ButtonSpec.new("command_tool_armory", "Armory")],
		[ButtonSpec.new("command_tool_turret", "Turret")],
		[ButtonSpec.new("command_evacuate", "Evacuate")],
		[ButtonSpec.new("command_launch", "Radiate")],
		[],
		[ButtonSpec.new("command_tool_warlord", "Warlord"), ButtonSpec.new("command_tool_technician", "Techie")],
		[ButtonSpec.new("command_tool_irregular", "Irregular")],
		[ButtonSpec.new("command_tool_vanguard", "Vanguard")],
		[],
	].map(
		func(a: Array):
			var grid_container = BoxContainer.new()
			add_child(grid_container)
			grid_container.custom_minimum_size = Vector2(60, 60)
			grid_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			grid_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER

			for item in a:
				var b: Button = ButtonSpec.create_button_from_spec(item)
				b.custom_minimum_size = Vector2(60, 60)
				grid_container.add_child(b)

			return grid_container
	)

	# TODO instantiate the buttons and their dimensions
	# Grid container with 5 columns, make 15 containers, each which will have a positioned button
#endregion
