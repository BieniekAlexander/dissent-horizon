class_name ScenarioDialogView
extends CanvasLayer

## The pop-up window a scenario raises, and the corner button that opens the pause menu.
##
## A ScenarioDialog raised by an EventShowDialog shows one page, dismissed with the acknowledge
## button, which is what releases the scripted simulation hold. Requests QUEUE: two triggers can
## fire on the same frame, and a tutorial that silently dropped the second instruction would be
## worse than one that shows them in order.
##
## The corner button reads "Briefing" in a scenario with objectives and "How to Play" in one
## without, and opens the pause menu on that tab (PauseMenu). It lives here rather than on the
## pause menu because the menu's layer is hidden whenever the menu is closed.
##
## Built in code rather than authored as a scene, matching how the rest of this game's
## runtime HUD is assembled (RTSController's sanction bar, Scenario's spectator panel) — and
## because it has to exist for scenarios that ship no player rig at all.
##
## PROCESS_MODE_ALWAYS throughout: the whole point of a paused dialog is that its buttons
## still work while the simulation is stopped.

#region Constants
## CanvasLayer ordering. Above the RTSController's HUD (layer 0) — a dialog that stops the
## world must not be drawn under the command grid.
const LAYER: int = 10

## Floor only, and width only. The panel's actual size comes from the page inside it: the
## DialogPage is a container, so its stacked title/body/extras report a minimum size and the
## PanelContainer grows to exactly that. A fixed height here would be wrong for every page —
## too tall for a one-liner, too short for a control reference.
const PANEL_MIN_WIDTH: float = 320.0

## Largest fraction of the screen height the page area may take before it starts scrolling
## instead of growing. Stretch-to-fit with no ceiling is worse than a fixed height: a long
## enough page pushes the acknowledge button off the bottom of the screen, and a dialog that
## holds the simulation and cannot be dismissed is unrecoverable.
const MAX_PAGE_HEIGHT_RATIO: float = 0.7
const PANEL_MARGIN: int = 20
const BUTTON_MIN_SIZE: Vector2 = Vector2(180.0, 36.0)

## The corner button, anchored top-right, far enough in from the edge to clear the elapsed-time
## readout's digits in the corner (scenes/interface/scenario_timer.tscn).
const BRIEFING_BUTTON_SIZE: Vector2 = Vector2(96.0, 32.0)
const BRIEFING_BUTTON_MARGIN: Vector2 = Vector2(72.0, 8.0)
const BRIEFING_BUTTON_TEXT: String = "Briefing"
const HOW_TO_PLAY_BUTTON_TEXT: String = "How to Play"

const PANEL_BG: Color = Color(0.08, 0.09, 0.11, 0.94)
const PANEL_BORDER: Color = Color(1.0, 0.85, 0.15, 0.85)
#endregion

#region Signals
## Emitted after the player acknowledges an event dialog and it leaves the queue.
signal dialog_dismissed(dialog: ScenarioDialog)
#endregion

#region Properties
var _root: Control
var _panel: PanelContainer
## Where the current DialogPage instance is parented.
var _page_frame: ScrollContainer
var _button: Button
## The optional second choice, shown only when the dialog on screen declares one.
var _secondary_button: Button
var _briefing_button: VerboseTooltipButton

## Event dialogs waiting to be shown, oldest first. The head is the one on screen.
var _queue: Array[ScenarioDialog] = []

## The manager whose objectives decide the corner button's label; null until bound.
var _manager: ScenarioTriggerManager = null
#endregion


#region Lifecycle
func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_refresh()


## Listen to a trigger manager's dialog requests. Called by Scenario after both nodes exist;
## idempotent so a re-wire can't double-queue every dialog.
func bind(a_manager: ScenarioTriggerManager) -> void:
	if not a_manager.dialog_requested.is_connected(_on_dialog_requested):
		a_manager.dialog_requested.connect(_on_dialog_requested)
		a_manager.objectives_changed.connect(_refresh)
	_manager = a_manager
	_refresh()


#endregion


#region Public API — event dialogs
## The event dialog currently on screen, or null when none is queued.
func current_dialog() -> ScenarioDialog:
	return _queue[0] if not _queue.is_empty() else null


func is_showing() -> bool:
	return not _queue.is_empty()


func queued_count() -> int:
	return _queue.size()


## Acknowledge the dialog on screen, as if the player clicked the button. The entry point for
## tests and for any future "advance on keypress" binding.
func acknowledge_current() -> void:
	var dialog: ScenarioDialog = current_dialog()
	if dialog == null:
		return
	if _submit_resolution(dialog, false):
		return
	# Drop it from the queue BEFORE acknowledging: acknowledging releases a simulation hold
	# and can synchronously run listeners that raise the next dialog, and those must find a
	# queue that no longer contains this one.
	_queue.remove_at(0)
	dialog.acknowledge()
	_refresh()
	dialog_dismissed.emit(dialog)


## Take the secondary option on the dialog on screen, as if the player clicked its second
## button. Same queue-then-resolve ordering as acknowledge_current, and for the same reason:
## resolving can synchronously raise the next dialog, which must not find this one still
## queued.
func choose_secondary_current() -> void:
	var dialog: ScenarioDialog = current_dialog()
	if dialog == null or not dialog.has_secondary():
		return
	if _submit_resolution(dialog, true):
		return
	_queue.remove_at(0)
	dialog.choose_secondary()
	_refresh()
	dialog_dismissed.emit(dialog)


## Resolve `a_dialog` as an order on the scenario's stream, so a replay resolves it on the same
## tick (recording-and-replay.md §Watching). False outside a scenario, where the caller resolves
## it at once. The window closes when the order lands (_on_dialog_resolved).
func _submit_resolution(a_dialog: ScenarioDialog, a_is_secondary: bool) -> bool:
	var stream: OrderStream = OrderStream.of(self)
	if stream == null or a_dialog.serial == 0:
		return false
	var scenario: Scenario = Scenario.of(self)
	var player: Commander = scenario.local_player() if scenario != null else null
	stream.submit(
		PlayerOrder.new(
			PlayerOrder.Kind.DIALOG,
			player.id if player != null else 0,
			{"dialog": a_dialog.serial, "secondary": a_is_secondary}
		)
	)
	return true


## Whether this view is in a scenario playing a recording back.
func _is_playback() -> bool:
	var stream: OrderStream = OrderStream.of(self) if is_inside_tree() else null
	return stream != null and stream.is_playback()


## `a_dialog` was resolved, by whatever route — a click here, a recorded order, a script. Drop it
## if it is still queued; a click resolved here has already been dropped.
func _on_dialog_resolved(a_dialog: ScenarioDialog) -> void:
	if not _queue.has(a_dialog):
		return
	_queue.erase(a_dialog)
	_refresh()
	dialog_dismissed.emit(a_dialog)


#endregion


#region Public API — the corner button
## The corner button's label: Briefing while the scenario has shown an objective, How to Play
## otherwise.
func menu_button_text() -> String:
	var has_objectives: bool = (
		_manager != null and not _manager.visible_objective_triggers().is_empty()
	)
	return BRIEFING_BUTTON_TEXT if has_objectives else HOW_TO_PLAY_BUTTON_TEXT


## What the corner button does: open the pause menu on Briefing or How to Play, or close it.
func open_pause_menu() -> void:
	var menu := get_tree().get_first_node_in_group(PauseMenu.GROUP) as PauseMenu
	if menu == null:
		return
	if menu.is_open():
		menu.close()
		return
	var is_briefing: bool = menu_button_text() == BRIEFING_BUTTON_TEXT
	menu.open_on(PauseMenu.Tab.BRIEFING if is_briefing else PauseMenu.Tab.HOW_TO_PLAY)


#endregion


#region Request handling
func _on_dialog_requested(a_dialog: ScenarioDialog) -> void:
	if a_dialog == null or a_dialog.is_acknowledged():
		return
	if not a_dialog.has_page():
		# Nothing to draw. Resolve it rather than queueing a blank window, so its simulation
		# hold is still released.
		a_dialog.acknowledge()
		return
	_queue.append(a_dialog)
	a_dialog.acknowledged.connect(_on_dialog_resolved.bind(a_dialog))
	_refresh()


#endregion


#region UI
func _build_ui() -> void:
	_root = Control.new()
	_root.name = "DialogRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The panel itself takes clicks; the rest of the screen stays live so the player can keep
	# looking around (and, during a paused beat, keep giving orders) while a dialog is up.
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.custom_minimum_size = Vector2(PANEL_MIN_WIDTH, 0.0)
	# Shrink to the content rather than filling the centring container.
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_panel.add_theme_stylebox_override("panel", _panel_style())
	# Count the open window as blocking UI, so a click or a wheel notch aimed at the dialog
	# doesn't also reach the world behind it (selection, edge pan, camera zoom all consult
	# RTSController.pointer_over_blocking_ui). That test gates on is_visible_in_tree, and
	# _root is hidden whenever no dialog is up, so a closed dialog blocks nothing.
	_panel.add_to_group(RTSController.SELECTION_BLOCKING_UI_GROUP)
	center.add_child(_panel)

	var margin := MarginContainer.new()
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, PANEL_MARGIN)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	# The current DialogPage instance is parented here, and freed when the view moves on.
	#
	# A ScrollContainer so an over-long page scrolls rather than growing without limit. With
	# horizontal scrolling DISABLED it still reports the page's WIDTH as a minimum, so the panel
	# keeps sizing itself to the page's content_width; only the height is capped, by
	# _fit_page_height.
	_page_frame = ScrollContainer.new()
	_page_frame.name = "PageFrame"
	_page_frame.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page_frame.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	column.add_child(_page_frame)

	# Both choices share one centred row. The secondary sits to the LEFT of the primary, so the
	# button that keeps you where you are stays under the cursor in the same place whether or
	# not a dialog offers a way out.
	var choice_row := HBoxContainer.new()
	choice_row.name = "Choices"
	choice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	choice_row.add_theme_constant_override("separation", 12)
	column.add_child(choice_row)

	_secondary_button = Button.new()
	_secondary_button.name = "Secondary"
	_secondary_button.custom_minimum_size = BUTTON_MIN_SIZE
	_secondary_button.visible = false
	_secondary_button.pressed.connect(choose_secondary_current)
	choice_row.add_child(_secondary_button)

	_button = Button.new()
	_button.name = "Acknowledge"
	_button.custom_minimum_size = BUTTON_MIN_SIZE
	_button.pressed.connect(_on_primary_pressed)
	choice_row.add_child(_button)

	_build_briefing_button()


## The always-on-screen toggle, in its own full-rect Control so it anchors to the corner
## independently of the centred panel.
func _build_briefing_button() -> void:
	var anchor := Control.new()
	anchor.name = "BriefingAnchor"
	anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	_briefing_button = VerboseTooltipButton.new()
	_briefing_button.name = "BriefingButton"
	_briefing_button.text = BRIEFING_BUTTON_TEXT
	_briefing_button.simple_tooltip = "Open the pause menu: the briefing and How to Play"
	_briefing_button.verbose_tooltip = (
		"Open the pause menu on the Briefing (the objectives so far, in detail) or on How to "
		+ "Play (the game's help notes, the ones shown here highlighted).\nThe game waits "
		+ "while it is open, except in a networked match; press the button again to close it."
	)
	_briefing_button.custom_minimum_size = BRIEFING_BUTTON_SIZE
	_briefing_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_briefing_button.offset_left = -(BRIEFING_BUTTON_SIZE.x + BRIEFING_BUTTON_MARGIN.x)
	_briefing_button.offset_top = BRIEFING_BUTTON_MARGIN.y
	_briefing_button.offset_right = -BRIEFING_BUTTON_MARGIN.x
	_briefing_button.offset_bottom = BRIEFING_BUTTON_MARGIN.y + BRIEFING_BUTTON_SIZE.y
	_briefing_button.pressed.connect(open_pause_menu)
	anchor.add_child(_briefing_button)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = PANEL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	return style


## The primary button acknowledges the dialog on screen.
func _on_primary_pressed() -> void:
	acknowledge_current()


#endregion


#region Rendering
## Put the dialog on screen, or hide the panel when none is queued.
func _refresh() -> void:
	if _root == null:
		return

	_briefing_button.text = menu_button_text()

	var dialog: ScenarioDialog = current_dialog()
	if dialog != null:
		_show_page(dialog.page)
		_secondary_button.visible = dialog.has_secondary()
		_secondary_button.text = dialog.secondary_text
		_button.text = _acknowledge_text_of_current_page()
		# A playback resolves each dialog on the tick the recording did, never on a click here.
		var is_playback: bool = _is_playback()
		_button.disabled = is_playback
		_secondary_button.disabled = is_playback
		_root.visible = true
		if not is_playback:
			_button.grab_focus()
		return

	_secondary_button.visible = false
	_button.disabled = false
	_clear_page()
	_root.visible = false


## Instantiate `scene` into the page frame, replacing whatever was there. The view owns page
## instances for exactly as long as they are on screen.
func _show_page(a_scene: PackedScene) -> void:
	_clear_page()
	if a_scene == null:
		return
	_page_frame.add_child(a_scene.instantiate())
	_fit_page_height.call_deferred()


## Size the page area to the page, up to MAX_PAGE_HEIGHT_RATIO of the screen.
##
## Deferred by a frame on purpose: the body is a wrapping RichTextLabel, and its height is
## only knowable once it has been laid out at its actual width. Asking immediately after
## add_child reports zero.
func _fit_page_height() -> void:
	var page := _current_page_instance() as Control
	if page == null or _page_frame == null:
		return
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	var wanted: float = page.get_combined_minimum_size().y
	var ceiling: float = viewport.get_visible_rect().size.y * MAX_PAGE_HEIGHT_RATIO
	_page_frame.custom_minimum_size.y = minf(wanted, ceiling)


func _clear_page() -> void:
	if _page_frame == null:
		return
	for child: Node in _page_frame.get_children():
		_page_frame.remove_child(child)
		child.queue_free()


## The button label for the page on screen, falling back to the DialogPage default when the
## scene root isn't one (a page can be any Control).
func _acknowledge_text_of_current_page() -> String:
	var page := _current_page_instance() as DialogPage
	return page.resolved_acknowledge_text() if page != null else "Continue"


## The live page instance, or null when nothing is displayed. Exposed for tests, which assert
## on the page that actually got built rather than on the scene reference.
func current_page_instance() -> Node:
	return _current_page_instance()


func _current_page_instance() -> Node:
	if _page_frame == null or _page_frame.get_child_count() == 0:
		return null
	return _page_frame.get_child(0)
#endregion
