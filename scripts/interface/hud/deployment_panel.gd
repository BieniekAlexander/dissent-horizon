class_name DeploymentPanel
extends Control

## The deployment drops as HUD buttons: the command-centre drop, then the extractor drops.
##
## Its own panel rather than the ability bar or the ORDNANCE card, because the drops have no
## caster for those to find and are gone once spent — see starting-formations.md §Presentation
## and targeting. RTSController builds it while the local player holds a drop and frees it with
## the last one; this panel only draws the Deployment it is handed and asks the controller to
## arm a drop. Plain buttons for now — PLANNED: it is meant to frame the opening phase visually.

const BUTTON_SIZE: Vector2 = Vector2(180, 40)
## Below the top-centre sanction bar, which it would otherwise sit on.
const TOP_MARGIN: float = 56.0
## Drawn over the button of the drop that is armed, so the player can see what a right-click lands.
const ARMED_MODULATE: Color = Color(0.72, 0.94, 0.97)

## Drop -> [label, the action whose binding the button names].
const DROPS: Dictionary = {
	Deployment.Drop.COMMAND_CENTRE: ["Drop command centre", "deploy_command_centre"],
	Deployment.Drop.EXTRACTOR: ["Drop extractor", "deploy_extractor"],
}

var controller: RTSController = null
var deployment: Deployment = null

## Drop -> Button.
var _buttons: Dictionary = {}
var _row: HBoxContainer = null


func _ready() -> void:
	name = "DeploymentPanel"
	add_to_group(RTSController.SELECTION_BLOCKING_UI_GROUP)
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	for drop: Deployment.Drop in DROPS:
		var button := Button.new()
		button.custom_minimum_size = BUTTON_SIZE
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: controller.arm_drop(drop))
		row.add_child(button)
		_buttons[drop] = button
	_row = row


func _process(_a_delta: float) -> void:
	refresh()


## Redraw every button from the deployment: its remaining charges, whether it can be pressed
## yet, and whether it is the one armed.
func refresh() -> void:
	if deployment == null or controller == null:
		return
	for drop: Deployment.Drop in _buttons:
		var button: Button = _buttons[drop]
		var count: int = deployment.charges(drop)
		var label: String = DROPS[drop][0]
		var key: String = InputPrompt.action_text(DROPS[drop][1])
		button.text = "%s ×%d [%s]" % [label, count, key] if count > 1 else "%s [%s]" % [label, key]
		# The command centre goes first; until it lands the extractor drops are shown, empty.
		button.visible = count > 0 or drop == Deployment.Drop.EXTRACTOR
		button.disabled = count <= 0
		button.tooltip_text = "Needs the command centre down first." if button.disabled else ""
		button.modulate = ARMED_MODULATE if controller.armed_drop() == drop else Color.WHITE
	# Sized to the row and centred on the anchor, so the panel's rect — what blocks world clicks
	# — is exactly the buttons, however the labels have changed width.
	var extent: Vector2 = _row.get_combined_minimum_size()
	offset_left = -extent.x * 0.5
	offset_right = extent.x * 0.5
	offset_top = TOP_MARGIN
	offset_bottom = TOP_MARGIN + extent.y
