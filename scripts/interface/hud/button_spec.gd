class_name ButtonSpec

#region Properties
var control: String
var text: String
## Tooltip shown normally.
var simple_tooltip: String
## Tooltip shown while the "ui_verbose" action (Alt) is held. Empty = same as simple.
var verbose_tooltip: String
#endregion

#region Lifecycle
func _init(
	a_control: String,
	a_text: String,
	a_simple_tooltip: String = "",
	a_verbose_tooltip: String = ""
):
	control = a_control
	text = a_text
	simple_tooltip = a_simple_tooltip
	verbose_tooltip = a_verbose_tooltip
#endregion

#region Public API
static func create_button_from_spec(a_spec: ButtonSpec) -> Button:
	var ret: VerboseTooltipButton = VerboseTooltipButton.new()
	ret.text = a_spec.text
	ret.name = a_spec.control
	# VerboseTooltipButton renders its own popup (see that class), so we don't set
	# the built-in tooltip_text here — just hand it both variants.
	ret.simple_tooltip = a_spec.simple_tooltip
	ret.verbose_tooltip = a_spec.verbose_tooltip
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
