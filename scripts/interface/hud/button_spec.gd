class_name ButtonSpec

#region Properties
var control: String
var text: String
#endregion

#region Lifecycle
func _init(
	a_control: String,
	a_text: String
):
	control = a_control
	text = a_text
#endregion

#region Public API
## Spec for a registry Tool button, pulling its HUD label from Tool so the label
## is defined once (in the Tool registry) rather than duplicated in the grid.
static func for_tool(a_command_name: String) -> ButtonSpec:
	return ButtonSpec.new(a_command_name, Tool.label_for(a_command_name))

static func create_button_from_spec(a_spec: ButtonSpec) -> Button:
	var ret: Button = Button.new()
	ret.text = a_spec.text
	ret.name = a_spec.control
	ret.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ret.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	# clean up passing of binding
	ret.connect("pressed", func(): ret.get_parent().get_parent().get_parent()._on_control_button_pressed(ret.name))
	return ret
#endregion
