class_name MainMenu
extends Control

## The title screen: one PAGE at a time, chosen by `page`. The main page leads to every other —
## Campaign, Arcade (not built: greyed out, marked WIP), Skirmish, Replays, Options — and Quit
## closes the application. Every other page has a Back button, and Escape is the same as Back.
## gdd/systems/ux/ui/menus.md.
##
## CAMPAIGN lists the authored missions. The list is DATA — `scenarios`, an array of
## ScenarioEntry — rather than one hand-wired button per scene: adding a mission is filling two
## fields on a new array row in the inspector. Buttons are duplicated from %ButtonTemplate, a
## hidden node in the same scene, so restyling every button is editing ONE node.
##
## SKIRMISH is the SkirmishLobby. REPLAYS lists every replay under `user://replays/`, newest
## first; a replay this build cannot play is listed all the same and refused, with the reason,
## when chosen (gdd/systems/commands/recording-and-replay.md §Watching). OPTIONS holds the master
## volume (unsaved) and the alert jump key's scope (GameSettings, saved).
##
## Every transition goes through the SceneManager autoload, which is also what a scenario uses
## to come BACK here — one description of what changing scene means, including clearing the
## tree-wide pause.

#region Constants
enum Page { MAIN, CAMPAIGN, SKIRMISH, REPLAYS, OPTIONS }

## The main page's buttons, in order: [name, label, page it opens (or -1), enabled].
const MAIN_ENTRIES: Array = [
	["Campaign", "Campaign", Page.CAMPAIGN, true],
	["Arcade", "Arcade (WIP)", -1, false],
	["Skirmish", "Skirmish", Page.SKIRMISH, true],
	["Replays", "Replays", Page.REPLAYS, true],
	["Options", "Options", Page.OPTIONS, true],
	["Quit", "Quit", -1, true],
]
const MASTER_BUS: StringName = &"Master"
#endregion

#region Properties
@export_category("Title")
## The heading. Exported so the screen can be retitled without touching the scene tree.
@export var title: String = "Dissent Horizon":
	set(value):
		title = value
		_refresh_title()

@export_category("Scenarios")
## The campaign's missions, in the order their buttons appear. An entry with no scene is
## skipped and reported (see ScenarioEntry).
@export var scenarios: Array[ScenarioEntry] = []

## Where the replay panel looks. A test points it elsewhere before the menu enters the tree.
var replay_directory: String = ReplayFile.DIRECTORY

## The page on screen.
var page: Page = Page.MAIN

@onready var _title_label: Label = %Title
@onready var _main_page: VBoxContainer = %MainPage
@onready var _buttons: Control = %Buttons
@onready var _button_template: Button = %ButtonTemplate
@onready var _replay_list: VBoxContainer = %ReplayList
@onready var _replay_status: Label = %ReplayStatus
@onready var _lobby: SkirmishLobby = %SkirmishLobby
@onready var _volume: HSlider = %Volume
@onready var _jump_scope: OptionButton = %JumpScope
@onready var _pages: Dictionary = {
	Page.MAIN: %MainPage,
	Page.CAMPAIGN: %CampaignPage,
	Page.SKIRMISH: %SkirmishPage,
	Page.REPLAYS: %ReplaysPage,
	Page.OPTIONS: %OptionsPage,
}
#endregion


#region Lifecycle
func _ready() -> void:
	_refresh_title()
	_build_main_page()
	_build_buttons()
	_build_replay_list()
	for each: Page in [Page.CAMPAIGN, Page.REPLAYS, Page.OPTIONS]:
		(_pages[each] as Control).add_child(_back_button())
	_lobby.back_requested.connect(show_page.bind(Page.MAIN))
	var bus: int = AudioServer.get_bus_index(MASTER_BUS)
	_volume.value = db_to_linear(AudioServer.get_bus_volume_db(bus)) if bus >= 0 else 1.0
	_volume.value_changed.connect(_on_volume_changed)
	_build_jump_scope()
	show_page(Page.MAIN)


func _unhandled_input(a_event: InputEvent) -> void:
	if page != Page.MAIN and a_event.is_action_pressed(&"ui_cancel") and not _lobby.is_launching():
		show_page(Page.MAIN)
		get_viewport().set_input_as_handled()


#endregion


#region Public API
## Show `a_page` and hide the others, focusing its first button for keyboard and gamepad.
func show_page(a_page: Page) -> void:
	page = a_page
	for each: Page in _pages:
		(_pages[each] as Control).visible = each == a_page
	if a_page == Page.REPLAYS:
		_build_replay_list()
	var first: Button = _first_button(_pages[a_page])
	if first != null and first.is_visible_in_tree():
		first.grab_focus()


## The main page's button labels, top to bottom.
func main_labels() -> Array[String]:
	var labels: Array[String] = []
	for child: Node in _main_page.get_children():
		if child is Button:
			labels.append((child as Button).text)
	return labels


## The main page's button called `a_name` ("Campaign", "Arcade", …), or null.
func main_button(a_name: String) -> Button:
	return _main_page.get_node_or_null(a_name) as Button


## The campaign's button labels, top to bottom. The testable view of what the campaign page
## offers, without reaching into the node tree.
func button_labels() -> Array[String]:
	var labels: Array[String] = []
	for button: Button in _scenario_buttons():
		labels.append(button.text)
	return labels


## Open `entry`'s scene, replacing the whole tree. Reports and does nothing when the entry
## names no scene, or when the swap itself is refused.
func open(a_entry: ScenarioEntry) -> void:
	if a_entry == null or not a_entry.is_valid():
		push_error("MainMenu: asked to open an entry with no scene; ignoring.")
		return
	SceneManager.go_to_packed(a_entry.scene)


## The replay panel's rows, top to bottom (newest first). Empty when there are no replays.
func replay_labels() -> Array[String]:
	var labels: Array[String] = []
	for child: Node in _replay_list.get_children():
		if child is Button and not child.is_queued_for_deletion():
			labels.append((child as Button).text)
	return labels


## Why the last replay chosen could not be played, or "".
func replay_refusal() -> String:
	return _replay_status.text


## Play the replay at `a_path`; show the refusal instead when it cannot be played.
func open_replay(a_path: String) -> void:
	_replay_status.text = SceneManager.play_replay(a_path)


func lobby() -> SkirmishLobby:
	return _lobby


#endregion


#region Internal
func _build_main_page() -> void:
	for entry: Array in MAIN_ENTRIES:
		var button: Button = _button_template.duplicate()
		button.name = entry[0]
		button.text = entry[1]
		button.visible = true
		button.disabled = not entry[3]
		if not entry[3]:
			button.tooltip_text = "Not built yet."
		elif entry[0] == "Quit":
			button.pressed.connect(SceneManager.quit_game)
		else:
			button.pressed.connect(show_page.bind(entry[2]))
		_main_page.add_child(button)


func _back_button() -> Button:
	var button: Button = _button_template.duplicate()
	button.name = "Back"
	button.text = "Back"
	button.visible = true
	button.pressed.connect(show_page.bind(Page.MAIN))
	return button


## One button per replay file, newest first; a line saying there are none when there are none.
func _build_replay_list() -> void:
	for child: Node in _replay_list.get_children():
		_replay_list.remove_child(child)
		child.queue_free()
	_replay_status.text = ""
	var entries: Array[Dictionary] = ReplayLibrary.entries(replay_directory)
	if entries.is_empty():
		var none := Label.new()
		none.text = "No replays yet. Every match records one."
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_replay_list.add_child(none)
		return
	for entry: Dictionary in entries:
		var button: Button = _button_template.duplicate()
		button.name = "Replay_%s" % String(entry["file"]).validate_node_name()
		button.text = ReplayLibrary.label_for(entry)
		button.visible = true
		button.pressed.connect(open_replay.bind(entry["path"]))
		_replay_list.add_child(button)


## Every live scenario button — the template is hidden and excluded, so this is exactly the
## set the player can press.
func _scenario_buttons() -> Array[Button]:
	var out: Array[Button] = []
	if _buttons == null:
		return out
	for child: Node in _buttons.get_children():
		var button := child as Button
		if button != null and button != _button_template:
			out.append(button)
	return out


## One button per valid entry, in authored order.
func _build_buttons() -> void:
	for button: Button in _scenario_buttons():
		button.queue_free()

	for i: int in scenarios.size():
		var entry: ScenarioEntry = scenarios[i]
		if entry == null or not entry.is_valid():
			push_error("MainMenu: scenario entry %d names no scene; skipping it." % (i + 1))
			continue
		var button: Button = _button_template.duplicate()
		button.name = "Scenario%d" % (i + 1)
		button.text = entry.button_text()
		button.visible = true
		button.pressed.connect(open.bind(entry))
		_buttons.add_child(button)

	if scenarios.is_empty():
		push_warning("MainMenu: no scenarios authored, so the title screen goes nowhere.")


func _first_button(a_root: Node) -> Button:
	for child: Node in a_root.get_children():
		var button := child as Button
		if button != null and button.visible and not button.disabled:
			return button
		var nested: Button = _first_button(child)
		if nested != null:
			return nested
	return null


## The jump key's scope, one item per GameSettings.AlertJumpScope, saved when changed.
func _build_jump_scope() -> void:
	_jump_scope.clear()
	_jump_scope.add_item("Negative alerts only", GameSettings.AlertJumpScope.NEGATIVE)
	_jump_scope.add_item("All alerts", GameSettings.AlertJumpScope.ALL)
	_jump_scope.select(_jump_scope.get_item_index(GameSettings.alert_jump_scope()))
	_jump_scope.item_selected.connect(
		func(i: int) -> void: GameSettings.set_alert_jump_scope(_jump_scope.get_item_id(i))
	)


## The jump-scope control, for a test.
func jump_scope_control() -> OptionButton:
	return _jump_scope


func _on_volume_changed(a_value: float) -> void:
	var bus: int = AudioServer.get_bus_index(MASTER_BUS)
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(a_value, 0.0001)))


func _refresh_title() -> void:
	# The setter fires while the scene is still loading, before @onready has resolved.
	if _title_label == null:
		return
	_title_label.text = title
#endregion
