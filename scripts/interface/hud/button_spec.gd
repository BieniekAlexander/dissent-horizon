class_name ButtonSpec

#region Properties
var control: String
var text: String
## Tooltip shown normally.
var simple_tooltip: String
## Tooltip shown while the "ui_verbose" action (/) is held. Empty = same as simple.
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
## TODO: EVERY LABEL OF FIVE CHARACTERS OR MORE IS CLIPPED at the cell width the 6-column
## grid gives it — "Attack" draws as "Attac", "Defend" as "Defe", "Evacuate" as "Evac". The
## remedy is a decision rather than a fix (shrink the font to fit, wrap to two lines, or make
## short labels an authoring rule), so nothing is chosen here. Seen by rendering the card
## offscreen; see gdd/deferred.md and CLAUDE.md §Seeing the HUD without a screen.
static func create_button_from_spec(spec: ButtonSpec) -> Button:
	var ret: VerboseTooltipButton = VerboseTooltipButton.new()
	ret.text = spec.text
	# Named before the tooltips are assigned: an empty tooltip is reported by name, and
	# "command_land" identifies the offender where an unnamed Button does not.
	ret.name = spec.control
	# VerboseTooltipButton renders its own popup (see that class), so we don't set
	# the built-in tooltip_text here — just hand it both variants.
	#
	# `{{ action }}` placeholders in the copy resolve HERE, against the live InputMap
	# (see InputPrompt) — the same treatment dialog pages and the help overlay get, so a
	# tooltip says the key the player would actually press rather than a hardcoded one.
	ret.simple_tooltip = InputPrompt.format(spec.simple_tooltip)
	ret.verbose_tooltip = InputPrompt.format(spec.verbose_tooltip)
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

	# The persistent resource bars preview a hovered purchase's effect (see
	# gdd/systems/ux/ui/economy-bars.md §Hover previews) — they read the hover through the
	# controller rather than each wiring its own mouse_entered/exited, since a bar has no
	# reason to know about individual grid buttons.
	ret.mouse_entered.connect(func():
		var controller: RTSController = _find_rts_controller(ret)
		if controller != null:
			controller.hovered_command_button = ret
	)
	ret.mouse_exited.connect(func():
		var controller: RTSController = _find_rts_controller(ret)
		# Only clear OUR OWN hover: a fast mouse move can enter the next button before this
		# one's exit is processed, and clearing unconditionally would erase that button's
		# claim instead of this one's.
		if controller != null and controller.hovered_command_button == ret:
			controller.hovered_command_button = null
	)

	# A grid button's RIGHT-click is unspent, and a standing order is a variant of the same
	# action the left-click performs — buy this, but keep buying it — so it costs no key.
	#
	# Connected to the `gui_input` SIGNAL rather than overriding _gui_input: that virtual is
	# BaseButton's, and a script override would replace the press handling the left click
	# depends on. The signal is emitted alongside it.
	ret.gui_input.connect(func(event: InputEvent):
		var button_event := event as InputEventMouseButton
		if button_event == null or button_event.button_index != MOUSE_BUTTON_RIGHT \
				or not button_event.pressed:
			return
		var controller: RTSController = _find_rts_controller(ret)
		if controller != null:
			ret.accept_event()
			controller._on_control_button_alternate_pressed(ret.name)
	)
	return ret

## Walks up from a HUD node to the RTSController that owns the HUD, or null.
static func _find_rts_controller(node: Node) -> RTSController:
	var current: Node = node
	while current != null:
		if current is RTSController:
			return current as RTSController
		current = current.get_parent()
	return null
#endregion
