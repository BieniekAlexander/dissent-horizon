class_name MainMenu
extends Control

## The title screen: a heading, and one button per authored scenario that swaps the whole
## scene tree for that scenario when clicked.
##
## The scenario list is DATA — `scenarios`, an array of ScenarioEntry — rather than one
## hand-wired button per scene. Adding a mission is then filling two fields on a new array
## row in the inspector: no new node, no signal to connect, no edit to this script. The same
## reason PlayerSlot is a list of resources rather than a fixed set of exports.
##
## Buttons are duplicated from %ButtonTemplate, a hidden node in the same scene, rather than
## built in code — so restyling every button is editing ONE node in the inspector instead of
## editing a function. Same idiom as ObjectiveView's %RowTemplate.
##
## Every transition goes through the SceneManager autoload, which is also what a scenario
## uses to come BACK here (its pause menu, or a victory dialog's return button) — one
## description of what changing scene means, including clearing the tree-wide pause.
##
## Ordering and unlocking are not modelled: every authored entry is available from the first
## launch.
##
## Below the scenarios, the REPLAY PANEL lists every replay under `user://replays/`, newest
## first, autosaves and kept ones alike; choosing one plays it, and a replay this build cannot
## play is listed all the same and refused, with the reason, when chosen.
## gdd/systems/commands/recording-and-replay.md §Watching.

#region Properties
@export_category("Title")
## The heading. Exported so the screen can be retitled without touching the scene tree.
@export var title: String = "Dissent Horizon":
	set(value):
		title = value
		_refresh_title()

@export_category("Scenarios")
## The scenarios offered, in the order their buttons appear. An entry with no scene is
## skipped and reported (see ScenarioEntry).
@export var scenarios: Array[ScenarioEntry] = []

## Where the replay panel looks. A test points it elsewhere before the menu enters the tree.
var replay_directory: String = ReplayFile.DIRECTORY

@onready var _title_label: Label = %Title
@onready var _buttons: Control = %Buttons
@onready var _button_template: Button = %ButtonTemplate
@onready var _replay_list: VBoxContainer = %ReplayList
@onready var _replay_status: Label = %ReplayStatus
#endregion


#region Lifecycle
func _ready() -> void:
	_refresh_title()
	_build_buttons()
	_build_replay_list()


#endregion


#region Public API
## The button labels currently on screen, top to bottom. The testable view of what this
## screen is offering, without reaching into the node tree.
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
	# Through SceneManager rather than get_tree().change_scene_to_packed: every transition in
	# the game goes through one place, which is what makes "return to the main menu" mean the
	# same thing here, in the pause menu, and on a victory dialog. SceneManager reports its own
	# failures.
	SceneManager.go_to_packed(a_entry.scene)


## The replay panel's rows, top to bottom (newest first). Empty when there are no replays.
func replay_labels() -> Array[String]:
	var labels: Array[String] = []
	for child: Node in _replay_list.get_children():
		if child is Button:
			labels.append((child as Button).text)
	return labels


## Why the last replay chosen could not be played, or "".
func replay_refusal() -> String:
	return _replay_status.text


## Play the replay at `a_path`; show the refusal instead when it cannot be played.
func open_replay(a_path: String) -> void:
	_replay_status.text = SceneManager.play_replay(a_path)


#endregion


#region Internal
## One button per replay file, newest first; a line saying there are none when there are none.
func _build_replay_list() -> void:
	for child: Node in _replay_list.get_children():
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

	# Keyboard and gamepad need somewhere to start; without this the screen opens with nothing
	# focused and the arrow keys do nothing until the player clicks.
	var first: Array[Button] = _scenario_buttons()
	if not first.is_empty():
		first[0].grab_focus()


func _refresh_title() -> void:
	# The setter fires while the scene is still loading, before @onready has resolved.
	if _title_label == null:
		return
	_title_label.text = title
#endregion
