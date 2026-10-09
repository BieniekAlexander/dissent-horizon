class_name SpectatorPanel
extends Control

## The watcher's buttons, in the command grid's place: a look-only HUD
## (RTSController.is_look_only) has no orders to give, so the slot the grid fills in a match
## holds what a spectator can do instead — choose whose view is drawn and, in a replay, pause and
## set the speed. gdd/systems/ux/ui/hud-layout.md §The look-only HUD.
##
## A view is which commander's Fog is displayed (Fog.active_commander_id), never the local
## player: the simulation reads that (Scenario's implicit elimination rule), and a playback must
## judge its match as the recording did.

## Columns of the button grid — half the command grid's, so a label has room.
const COLUMNS: int = 3
## The view that shows everything: no fog, every piece drawn.
const VIEW_EVERYTHING: int = -2

var _scenario: Scenario = null
var _grid: GridContainer
## View id -> its button, for marking the one on screen.
var _view_buttons: Dictionary = {}
var _pause_button: Button = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var border := ColorRect.new()
	border.name = "Border"
	border.color = Color(0.35, 0.35, 0.35, 1.0)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchored after it is added, never before (hud-layout.md §A Control built in code…).
	add_child(border)
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grid = GridContainer.new()
	_grid.name = "Buttons"
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	border.add_child(_grid)
	_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	_build()


## Offer `a_scenario`'s views, and its replay controls when it plays a recording back.
func bind(a_scenario: Scenario) -> void:
	_scenario = a_scenario
	_build()


func _process(_a_delta: float) -> void:
	_refresh()


#region Public API
## The labels on the buttons, in grid order.
func button_labels() -> Array[String]:
	var out: Array[String] = []
	if _grid != null:
		for child: Node in _grid.get_children():
			out.append((child as Button).text)
	return out


## The views on offer: everything, then each commander with a Fog of its own (an omniscient
## slot keeps none, and has no view to show).
func views() -> Array[int]:
	var out: Array[int] = [VIEW_EVERYTHING]
	if _scenario != null:
		for commander: Commander in _scenario.commanders:
			if commander.id > 0 and Fog.for_commander(commander.id) != null:
				out.append(commander.id)
	return out


## Draw `a_view` (a commander id, or VIEW_EVERYTHING).
func show_view(a_view: int) -> void:
	Fog.active_commander_id = a_view
	_refresh()


## How a view's button reads: "No fog", "Bot 2", "Player 1".
func view_label(a_view: int) -> String:
	if a_view == VIEW_EVERYTHING:
		return "No fog"
	var commander: Commander = _scenario.commander_by_id(a_view) if _scenario != null else null
	var is_bot: bool = commander == null or _scenario.is_bot_slot(commander)
	return "%s %d" % ["Bot" if is_bot else "Player", a_view]


#endregion


#region Internal
func _build() -> void:
	if _grid == null:
		return
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_view_buttons.clear()
	_pause_button = null
	for view: int in views():
		var button: Button = _button(view_label(view), show_view.bind(view))
		button.tooltip_text = "Draw the map as this commander sees it"
		if view == VIEW_EVERYTHING:
			button.tooltip_text = "Draw every piece, with no fog"
		_view_buttons[view] = button
	if _scenario != null and _scenario.is_playback():
		_pause_button = _button("Pause", _on_replay.bind(&"toggle_pause"))
		_button("Slower", _on_replay.bind(&"step_speed", -1))
		_button("Faster", _on_replay.bind(&"step_speed", 1))
	_refresh()


func _button(a_text: String, a_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = a_text
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0.0, 36.0)
	button.pressed.connect(a_pressed)
	_grid.add_child(button)
	return button


## A replay control: the viewer's own method, so the keys and the buttons are one control.
func _on_replay(a_method: StringName, a_argument: Variant = null) -> void:
	var viewer: ReplayViewer = _viewer()
	if viewer == null:
		return
	if a_argument == null:
		viewer.call(a_method)
	else:
		viewer.call(a_method, a_argument)
	_refresh()


func _viewer() -> ReplayViewer:
	return _scenario.get_node_or_null("ReplayViewer") as ReplayViewer if _scenario != null else null


func _refresh() -> void:
	var active: int = Fog.active_commander_id
	if active == -1:
		active = RTSController.PLAYER_COMMANDER_ID
	for view: int in _view_buttons:
		(_view_buttons[view] as Button).disabled = view == active
	if _pause_button != null:
		var viewer: ReplayViewer = _viewer()
		_pause_button.text = "Resume" if viewer != null and viewer.is_paused() else "Pause"
#endregion
