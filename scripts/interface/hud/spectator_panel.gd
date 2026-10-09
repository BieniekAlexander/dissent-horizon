class_name SpectatorPanel
extends Control

## The watcher's controls, in the command grid's place: a look-only HUD
## (RTSController.is_look_only) has no orders to give, so the slot the grid fills in a match
## holds what a spectator can do instead — choose whose view is drawn, lift the fog over it, and
## set the playback speed. gdd/systems/ux/ui/hud-layout.md §The look-only HUD.
##
## A view is which commander's Fog is displayed (Fog.active_commander_id), never the local
## player: the simulation reads that (Scenario's implicit elimination rule), and a playback must
## judge its match as the recording did.

## Columns of the view buttons — half the command grid's, so a label has room.
const COLUMNS: int = 3
## Room enough for a label, small enough that views, fog and speed share the grid's slot.
const BUTTON_HEIGHT: float = 30.0
const PLAYBACK_CONTROLS_SCENE: PackedScene = preload(
	"res://scenes/interface/playback_controls.tscn"
)

var _scenario: Scenario = null
var _grid: GridContainer
## View id -> its button, for marking the one on screen.
var _view_buttons: Dictionary = {}
var _fog_toggle: CheckButton
var _playback_controls: PlaybackControls
## Whether the playback controls have their clock yet: the HUD is built before the scenario's
## trigger manager, which owns it.
var _is_clock_bound: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var border := ColorRect.new()
	border.name = "Border"
	border.color = Color(0.35, 0.35, 0.35, 1.0)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchored after it is added, never before (hud-layout.md §A Control built in code…).
	add_child(border)
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 4)
	border.add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	_grid = GridContainer.new()
	_grid.name = "Views"
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	column.add_child(_grid)
	_fog_toggle = CheckButton.new()
	_fog_toggle.name = "FogToggle"
	_fog_toggle.text = "Fog of war"
	_fog_toggle.focus_mode = Control.FOCUS_NONE
	_fog_toggle.toggled.connect(func(a_is_shown: bool) -> void: Fog.set_view_lifted(not a_is_shown))
	column.add_child(_fog_toggle)
	_playback_controls = PLAYBACK_CONTROLS_SCENE.instantiate() as PlaybackControls
	column.add_child(_playback_controls)
	_build()


## The fog setting is the spectator's, so it goes with the panel: a player attached again sees
## their own fog.
func _exit_tree() -> void:
	Fog.set_view_lifted(false)


## Offer `a_scenario`'s views, and its playback controls where it offers them.
func bind(a_scenario: Scenario) -> void:
	_scenario = a_scenario
	_build()


func _process(_a_delta: float) -> void:
	_refresh()


#region Public API
## The labels on the view buttons, in grid order.
func button_labels() -> Array[String]:
	var out: Array[String] = []
	if _grid != null:
		for child: Node in _grid.get_children():
			out.append((child as Button).text)
	return out


## The views on offer: each commander with a Fog of its own (an omniscient slot keeps none, and
## has no view to show).
func views() -> Array[int]:
	var out: Array[int] = []
	if _scenario != null:
		for commander: Commander in _scenario.commanders:
			if commander.id > 0 and Fog.for_commander(commander.id) != null:
				out.append(commander.id)
	return out


## Draw `a_view` (a commander id).
func show_view(a_view: int) -> void:
	Fog.active_commander_id = a_view
	_refresh()


## How a view's button reads: "Bot 2", or "Player 1" for a commander nobody's bot is playing.
func view_label(a_view: int) -> String:
	var commander: Bot = _scenario.commander_by_id(a_view) as Bot if _scenario != null else null
	var is_bot: bool = commander == null or commander.is_ai_controlled()
	return "%s %d" % ["Bot" if is_bot else "Player", a_view]


## Show or lift the fog over the view, as a click on the toggle would.
func set_fog_shown(a_is_shown: bool) -> void:
	_fog_toggle.button_pressed = a_is_shown


#endregion


#region Internal
func _build() -> void:
	if _grid == null:
		return
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_view_buttons.clear()
	for view: int in views():
		var button: Button = _button(view_label(view), show_view.bind(view))
		button.tooltip_text = "Draw the map as this commander sees it"
		_view_buttons[view] = button
	_playback_controls.visible = PlaybackControls.is_offered(
		_scenario != null and _scenario.is_playback()
	)
	_refresh()


func _button(a_text: String, a_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = a_text
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0.0, BUTTON_HEIGHT)
	button.pressed.connect(a_pressed)
	_grid.add_child(button)
	return button


func _refresh() -> void:
	var active: int = Fog.active_commander_id
	if active == -1:
		active = RTSController.PLAYER_COMMANDER_ID
	for view: int in _view_buttons:
		(_view_buttons[view] as Button).disabled = view == active
	_refresh_fog_toggle()
	if not _is_clock_bound and _scenario != null and _scenario.trigger_manager() != null:
		_playback_controls.bind(_scenario.trigger_manager().simulation_clock)
		_is_clock_bound = true


## The debug view lifts the fog whatever the spectator chose, so while it is up the toggle reads
## off and is locked; lowering it gives the spectator's own setting back.
func _refresh_fog_toggle() -> void:
	var is_debug_up: bool = DebugMode.is_active()
	_fog_toggle.disabled = is_debug_up
	_fog_toggle.set_pressed_no_signal(not is_debug_up and not Fog.is_view_lifted())
	_fog_toggle.tooltip_text = (
		"The debug view lifts the fog while it is up"
		if is_debug_up
		else "Show the fog as the viewed commander sees it, or lift it to see everything"
	)
#endregion
