class_name ScenarioDialogView
extends CanvasLayer

## The pop-up window, and the HUD help button that opens it on demand.
##
## One panel, two modes, because they are the same window showing the same DialogPage scenes:
##
##  * EVENT mode — a ScenarioDialog raised by an EventShowDialog. One page, dismissed with
##    the acknowledge button, which is what releases the scripted simulation hold. Requests
##    QUEUE: two triggers can fire on the same frame, and a tutorial that silently dropped
##    the second instruction would be worse than one that shows them in order.
##
##  * HELP mode — the player pressed the help button. Flips through the scenario's HelpBook
##    with ◀ / ▶ and closes on a second press of the button. Takes its own simulation hold
##    (REASON_HELP) so reading the controls never costs you the battle.
##
## Event mode takes precedence, and the help button is disabled while a scripted dialog is
## up: a beat that stopped the world to ask something must be answered, and letting the help
## book cover it would strand the player behind a window they can't see.
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
const NAV_BUTTON_MIN_SIZE: Vector2 = Vector2(48.0, 36.0)

## The help toggle, anchored top-right where nothing else lives.
const HELP_BUTTON_SIZE: Vector2 = Vector2(96.0, 32.0)
const HELP_BUTTON_MARGIN: Vector2 = Vector2(12.0, 8.0)
const HELP_BUTTON_TEXT: String = "Help"

const PANEL_BG: Color = Color(0.08, 0.09, 0.11, 0.94)
const PANEL_BORDER: Color = Color(1.0, 0.85, 0.15, 0.85)

const CLOSE_TEXT: String = "Close"
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
var _nav_row: HBoxContainer
## The glyph controls (the two page arrows and the corner help toggle) are
## VerboseTooltipButtons: their labels are symbols, so they need the hover copy. The
## labelled choice buttons below stay plain — their own text is the explanation.
var _prev_button: VerboseTooltipButton
var _next_button: VerboseTooltipButton
var _page_label: Label
var _button: Button
## The optional second choice, shown only when the dialog on screen declares one.
var _secondary_button: Button
var _help_button: VerboseTooltipButton

## Event dialogs waiting to be shown, oldest first. The head is the one on screen.
var _queue: Array[ScenarioDialog] = []

## The scenario's help pages, and where the player is in them. Null book = no help button.
var _book: HelpBook = null
var _help_open: bool = false
var _help_index: int = 0

## Held so the help book can take and release its own simulation hold.
var _clock: SimulationClock = null
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
	_clock = a_manager.simulation_clock


## Give the view the scenario's help pages. Without a book (or with an empty one) the help
## button stays hidden.
func bind_help_book(a_book: HelpBook) -> void:
	_book = a_book
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
	_queue.remove_at(0)
	dialog.choose_secondary()
	_refresh()
	dialog_dismissed.emit(dialog)


#endregion


#region Public API — help book
## Whether the help book is open.
func is_help_open() -> bool:
	return _help_open


## Which page of the book is showing (0-based); -1 when it is closed.
func help_index() -> int:
	return _help_index if _help_open else -1


## Whether the help button is currently offered to the player.
func is_help_available() -> bool:
	return _book != null and not _book.is_empty()


## Open or close the help book — what the HUD button does. Refused while a scripted dialog is
## up, so the book can never cover a beat the player has to answer.
func toggle_help() -> void:
	if _help_open:
		close_help()
	else:
		open_help()


func open_help() -> void:
	if _help_open or not is_help_available() or is_showing():
		return
	_help_open = true
	_help_index = 0
	if _clock != null:
		_clock.hold(SimulationClock.REASON_HELP)
	_refresh()


func close_help() -> void:
	if not _help_open:
		return
	_help_open = false
	if _clock != null:
		_clock.release(SimulationClock.REASON_HELP)
	_refresh()


## Step through the book. Clamped rather than wrapping, so the ends of the book are a place
## you can arrive at instead of a loop you can't tell you're in.
func show_next_help_page() -> void:
	_go_to_help_page(_help_index + 1)


func show_previous_help_page() -> void:
	_go_to_help_page(_help_index - 1)


func _go_to_help_page(a_index: int) -> void:
	if not _help_open:
		return
	var clamped: int = clampi(a_index, 0, maxi(_book.page_count() - 1, 0))
	if clamped == _help_index:
		return
	_help_index = clamped
	_refresh()


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
	# A scripted dialog outranks the help book; step out of the way rather than stacking.
	if _help_open:
		close_help()
	_queue.append(a_dialog)
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

	_nav_row = HBoxContainer.new()
	_nav_row.name = "Nav"
	_nav_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_nav_row.add_theme_constant_override("separation", 12)
	column.add_child(_nav_row)

	# The two nav arrows and the help toggle are glyphs, so they carry tooltips (the two-tier
	# HUD ones — see VerboseTooltipButton) where the labelled choice buttons below don't: a
	# button reading "Continue" already says what it does, and "<" does not.
	_prev_button = _nav_button("Previous", "<", "Back a page", show_previous_help_page)
	_nav_row.add_child(_prev_button)

	_page_label = Label.new()
	_page_label.name = "PageIndicator"
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.custom_minimum_size = Vector2(80.0, 0.0)
	_nav_row.add_child(_page_label)

	_next_button = _nav_button("Next", ">", "On a page", show_next_help_page)
	_nav_row.add_child(_next_button)

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

	_build_help_button()


## One page-navigation arrow: a glyph button whose meaning lives entirely in its tooltip.
## No verbose tier — there is nothing longer to say about "back a page".
func _nav_button(
	a_name: String, a_glyph: String, a_tooltip: String, a_handler: Callable
) -> VerboseTooltipButton:
	var button := VerboseTooltipButton.new()
	button.name = a_name
	button.text = a_glyph
	button.simple_tooltip = a_tooltip
	button.custom_minimum_size = NAV_BUTTON_MIN_SIZE
	button.pressed.connect(a_handler)
	return button


## The always-on-screen toggle, in its own full-rect Control so it anchors to the corner
## independently of the centred panel.
func _build_help_button() -> void:
	var anchor := Control.new()
	anchor.name = "HelpAnchor"
	anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	_help_button = VerboseTooltipButton.new()
	_help_button.name = "HelpButton"
	_help_button.text = HELP_BUTTON_TEXT
	_help_button.simple_tooltip = "Open the mission's help pages"
	_help_button.verbose_tooltip = (
		"Open the help book: the mission's reference pages, readable at any time.\nThe "
		+ "simulation keeps running behind it — press the button again, or the close "
		+ "button, to put it away."
	)
	_help_button.custom_minimum_size = HELP_BUTTON_SIZE
	_help_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_help_button.offset_left = -(HELP_BUTTON_SIZE.x + HELP_BUTTON_MARGIN.x)
	_help_button.offset_top = HELP_BUTTON_MARGIN.y
	_help_button.offset_right = -HELP_BUTTON_MARGIN.x
	_help_button.offset_bottom = HELP_BUTTON_MARGIN.y + HELP_BUTTON_SIZE.y
	_help_button.pressed.connect(toggle_help)
	anchor.add_child(_help_button)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = PANEL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	return style


## The primary button means "acknowledge" for an event dialog and "close" for the help book.
func _on_primary_pressed() -> void:
	if is_showing():
		acknowledge_current()
	else:
		close_help()


#endregion


#region Rendering
## Put the right page on screen for whatever mode we're in, or hide the panel entirely.
func _refresh() -> void:
	if _root == null:
		return

	_help_button.visible = is_help_available()
	# A scripted dialog must be answered before the book can be opened over it.
	_help_button.disabled = is_showing()
	_help_button.button_pressed = _help_open

	var dialog: ScenarioDialog = current_dialog()
	if dialog != null:
		_show_page(dialog.page)
		_nav_row.visible = false
		_secondary_button.visible = dialog.has_secondary()
		_secondary_button.text = dialog.secondary_text
		_button.text = _acknowledge_text_of_current_page()
		_root.visible = true
		_button.grab_focus()
		return

	# The help book is never a choice between two things; only event dialogs offer a secondary.
	_secondary_button.visible = false

	if _help_open:
		_show_page(_book.page_at(_help_index))
		_nav_row.visible = _book.page_count() > 1
		_page_label.text = "%d / %d" % [_help_index + 1, _book.page_count()]
		_prev_button.disabled = _help_index <= 0
		_next_button.disabled = _help_index >= _book.page_count() - 1
		_button.text = CLOSE_TEXT
		_root.visible = true
		return

	_clear_page()
	_root.visible = false


## Instantiate `scene` into the page frame, replacing whatever was there. The view owns page
## instances for exactly as long as they are on screen.
func _show_page(a_scene: PackedScene) -> void:
	_clear_page()
	if a_scene == null:
		return
	var page: Node = a_scene.instantiate()
	_page_frame.add_child(page)
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
