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
static func create_button_from_spec(a_spec: ButtonSpec) -> Button:
	var ret: Button = Button.new()
	ret.text = a_spec.text
	ret.name = a_spec.control
	ret.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ret.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	# Route the press to the owning RTSController. Walk ancestors rather than
	# assuming a fixed parent depth, so the grid can be nested inside HUD
	# section groups (bottom-right) without breaking the wiring.
	ret.connect("pressed", func():
		var controller: RTSController = _find_rts_controller(ret)
		if controller != null:
			controller._on_control_button_pressed(ret.name)
	)
	return ret

## Walks up from a HUD node to the RTSController that owns the HUD, or null.
static func _find_rts_controller(a_node: Node) -> RTSController:
	var current: Node = a_node
	while current != null:
		if current is RTSController:
			return current as RTSController
		current = current.get_parent()
	return null
#endregion
