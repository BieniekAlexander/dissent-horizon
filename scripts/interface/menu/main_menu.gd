class_name MainMenu
extends Control

## The title screen: one PAGE at a time, chosen by `page`. The main page leads to every other —
## Campaign, Arcade (not built: greyed out, marked WIP), Skirmish, Replays, Options — and Quit
## closes the application. Every other page has a Back button, and Escape is the same as Back:
## a campaign's page goes back to CAMPAIGN, every other page to MAIN.
## gdd/systems/ux/ui/menus.md.
##
## CAMPAIGN lists the campaigns: the Prologue, and the challenge series (not built: greyed out,
## marked WIP). PROLOGUE lists that campaign's missions. The list is DATA — `scenarios`, an array
## of ScenarioEntry — rather than one hand-wired button per scene: adding a mission is filling two
## fields on a new array row in the inspector, and a row with a title but no scene yet is shown
## greyed out and marked WIP. Buttons are duplicated from %ButtonTemplate, a hidden node in the
## same scene, so restyling every button is editing ONE node. Above the list, the mission
## DIFFICULTY the chosen mission is opened at (Scenario.mission_difficulty).
##
## SKIRMISH is the SkirmishLobby. MULTIPLAYER hosts or joins a lobby by address
## (MultiplayerConnect) and hands it to the same SkirmishLobby, networked. REPLAYS lists every
## replay under `user://replays/`, newest first; a replay this build cannot play is listed all
## the same and refused, with the reason, when chosen
## (gdd/systems/commands/recording-and-replay.md §Watching). OPTIONS holds the master volume
## (unsaved) and the alert jump key's scope (GameSettings, saved).
##
## Every transition goes through the SceneManager autoload, which is also what a scenario uses
## to come BACK here — one description of what changing scene means, including clearing the
## tree-wide pause.

#region Constants
enum Page { MAIN, CAMPAIGN, PROLOGUE, SKIRMISH, MULTIPLAYER, REPLAYS, OPTIONS, SAVES }

## The main page's buttons, in order: [name, label, page it opens (or -1), enabled].
const MAIN_ENTRIES: Array = [
	["Campaign", "Campaign", Page.CAMPAIGN, true],
	["LoadGame", "Load Game", Page.SAVES, true],
	["Arcade", "Arcade (WIP)", -1, false],
	["Skirmish", "Skirmish", Page.SKIRMISH, true],
	["Multiplayer", "Multiplayer", Page.MULTIPLAYER, true],
	["Replays", "Replays", Page.REPLAYS, true],
	["Options", "Options", Page.OPTIONS, true],
	["Quit", "Quit", -1, true],
]
## The Campaign page's buttons, in order: [name, label, page it opens (or -1), enabled].
const CAMPAIGN_ENTRIES: Array = [
	["Prologue", "Prologue", Page.PROLOGUE, true],
	["Challenges", "Challenges (WIP)", -1, false],
]
## Each page's parent page: where its Back button and Escape lead. Absent means MAIN.
const PARENT_PAGES: Dictionary = {
	Page.PROLOGUE: Page.CAMPAIGN,
}
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
## The Prologue's missions, in the order their buttons appear. An entry with a title but no
## scene is shown greyed out and marked WIP; one with neither is skipped and reported (see
## ScenarioEntry).
@export var scenarios: Array[ScenarioEntry] = []

## Where the replay panel looks. A test points it elsewhere before the menu enters the tree.
var replay_directory: String = ReplayFile.DIRECTORY
## Where the Load Game page looks. A test points it elsewhere before the menu enters the tree.
var save_directory: String = SaveGame.DIRECTORY
## The Load Game page: built in code. gdd/systems/commands/saved-games.md §Menus.
var saves_panel: SavesPanel = null

## The page on screen.
var page: Page = Page.MAIN
## The difficulty a mission opens at, as picked on the Prologue page. MEDIUM until the player
## picks: the middle tier is what a mission is first written and tuned against.
var campaign_difficulty: Scenario.MissionDifficulty = Scenario.MissionDifficulty.MEDIUM

@onready var _title_label: Label = %Title
@onready var _main_page: VBoxContainer = %MainPage
@onready var _campaign_list: VBoxContainer = %CampaignList
@onready var _buttons: Control = %Buttons
@onready var _button_template: Button = %ButtonTemplate
@onready var _replay_list: VBoxContainer = %ReplayList
@onready var _replay_status: Label = %ReplayStatus
@onready var _lobby: SkirmishLobby = %SkirmishLobby
@onready var _volume: HSlider = %Volume
@onready var _jump_scope: OptionButton = %JumpScope
@onready var _difficulty: OptionButton = %Difficulty
## The Multiplayer page: built in code, like the lobby it leads to.
var _multiplayer: MultiplayerConnect = null

@onready var _pages: Dictionary = {
	Page.MAIN: %MainPage,
	Page.CAMPAIGN: %CampaignPage,
	Page.PROLOGUE: %ProloguePage,
	Page.SKIRMISH: %SkirmishPage,
	Page.REPLAYS: %ReplaysPage,
	Page.OPTIONS: %OptionsPage,
}
#endregion


#region Lifecycle
func _ready() -> void:
	_refresh_title()
	_build_main_page()
	_build_campaign_page()
	_build_buttons()
	_build_replay_list()
	for each: Page in [Page.CAMPAIGN, Page.PROLOGUE, Page.REPLAYS, Page.OPTIONS]:
		(_pages[each] as Control).add_child(_back_button(parent_page(each)))
	_lobby.back_requested.connect(show_page.bind(Page.MAIN))
	_build_multiplayer_page()
	_build_saves_page()
	var bus: int = AudioServer.get_bus_index(MASTER_BUS)
	_volume.value = db_to_linear(AudioServer.get_bus_volume_db(bus)) if bus >= 0 else 1.0
	_volume.value_changed.connect(_on_volume_changed)
	_build_jump_scope()
	_build_difficulty_picker()
	show_page(Page.MAIN)


func _unhandled_input(a_event: InputEvent) -> void:
	if page != Page.MAIN and a_event.is_action_pressed(&"ui_cancel") and not _lobby.is_launching():
		# Leaving the lobby closes a networked one rather than abandoning its connection.
		if page == Page.SKIRMISH:
			_lobby.leave()
		else:
			show_page(parent_page(page))
		get_viewport().set_input_as_handled()


#endregion


#region Public API
## Show `a_page` and hide the others, focusing its first button for keyboard and gamepad.
func show_page(a_page: Page) -> void:
	page = a_page
	for each: Page in _pages:
		(_pages[each] as Control).visible = each == a_page
	if a_page == Page.SAVES and saves_panel != null:
		saves_panel.refresh()
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


## The page Back and Escape lead to from `a_page`.
func parent_page(a_page: Page) -> Page:
	return PARENT_PAGES.get(a_page, Page.MAIN)


## The Campaign page's button called `a_name` ("Prologue", "Challenges"), or null.
func campaign_button(a_name: String) -> Button:
	return _campaign_list.get_node_or_null(a_name) as Button


## The Prologue's mission button labels, top to bottom. The testable view of what the Prologue
## page offers, without reaching into the node tree.
func button_labels() -> Array[String]:
	var labels: Array[String] = []
	for button: Button in _scenario_buttons():
		labels.append(button.text)
	return labels


## Open `entry`'s scene at `campaign_difficulty`, replacing the whole tree. Reports and does
## nothing when the entry names no scene, or when the swap itself is refused.
func open(a_entry: ScenarioEntry) -> void:
	if a_entry == null or not a_entry.is_valid():
		push_error("MainMenu: asked to open an entry with no scene; ignoring.")
		return
	var root: Node = a_entry.scene.instantiate()
	if root is Scenario:
		(root as Scenario).mission_difficulty = campaign_difficulty
	SceneManager.go_to_node(root)


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


func multiplayer_page() -> MultiplayerConnect:
	return _multiplayer


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


func _build_campaign_page() -> void:
	for entry: Array in CAMPAIGN_ENTRIES:
		var button: Button = _button_template.duplicate()
		button.name = entry[0]
		button.text = entry[1]
		button.visible = true
		button.disabled = not entry[3]
		if not entry[3]:
			button.tooltip_text = "Not built yet."
		else:
			button.pressed.connect(show_page.bind(entry[2]))
		_campaign_list.add_child(button)


func _build_multiplayer_page() -> void:
	var page_node := VBoxContainer.new()
	page_node.name = "MultiplayerPage"
	_multiplayer = MultiplayerConnect.new()
	_multiplayer.name = "MultiplayerConnect"
	page_node.add_child(_multiplayer)
	_main_page.get_parent().add_child(page_node)
	_pages[Page.MULTIPLAYER] = page_node
	_multiplayer.back_requested.connect(show_page.bind(Page.MAIN))
	_multiplayer.lobby_opened.connect(_open_networked_lobby)
	_lobby.lobby_left.connect(_on_lobby_left)


func _open_networked_lobby(a_link: LobbyLink) -> void:
	_lobby.attach(a_link)
	show_page(Page.SKIRMISH)


func _on_lobby_left(a_reason: String) -> void:
	_multiplayer.show_status(a_reason)
	show_page(Page.MULTIPLAYER)


func _back_button(a_to: Page) -> Button:
	var button: Button = _button_template.duplicate()
	button.name = "Back"
	button.text = "Back"
	button.visible = true
	button.pressed.connect(show_page.bind(a_to))
	return button


## The Load Game page: a heading, the saves (SavesPanel, loading only) and a Back button.
func _build_saves_page() -> void:
	var page_node := VBoxContainer.new()
	page_node.name = "SavesPage"
	page_node.visible = false
	page_node.add_theme_constant_override("separation", 16)
	var heading := Label.new()
	heading.text = "Load Game"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 26)
	page_node.add_child(heading)
	saves_panel = SavesPanel.new()
	saves_panel.name = "SavesPanel"
	saves_panel.directory = save_directory
	page_node.add_child(saves_panel)
	page_node.add_child(_back_button(Page.MAIN))
	_main_page.get_parent().add_child(page_node)
	_pages[Page.SAVES] = page_node


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


## One button per entry, in authored order: a playable entry opens its scene, a WIP one is
## greyed out, and one with nothing to show is skipped and reported.
func _build_buttons() -> void:
	for button: Button in _scenario_buttons():
		button.queue_free()

	for i: int in scenarios.size():
		var entry: ScenarioEntry = scenarios[i]
		if entry == null or not (entry.is_valid() or entry.is_wip()):
			push_error("MainMenu: scenario entry %d names no scene; skipping it." % (i + 1))
			continue
		var button: Button = _button_template.duplicate()
		button.name = "Scenario%d" % (i + 1)
		button.text = entry.button_text()
		button.visible = true
		if entry.is_wip():
			button.disabled = true
			button.tooltip_text = "Not built yet."
		else:
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


## One item per difficulty a player chooses between; the choice is held for this menu only.
func _build_difficulty_picker() -> void:
	_difficulty.clear()
	for tier: Scenario.MissionDifficulty in [
		Scenario.MissionDifficulty.EASY,
		Scenario.MissionDifficulty.MEDIUM,
		Scenario.MissionDifficulty.HARD,
	]:
		_difficulty.add_item(Scenario.MissionDifficulty.find_key(tier).capitalize(), tier)
	_difficulty.select(_difficulty.get_item_index(campaign_difficulty))
	_difficulty.item_selected.connect(
		func(i: int) -> void:
			campaign_difficulty = _difficulty.get_item_id(i) as Scenario.MissionDifficulty
	)


## The difficulty control, for a test.
func difficulty_control() -> OptionButton:
	return _difficulty


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
