class_name SkirmishLobby
extends VBoxContainer
## THE SKIRMISH SETUP SCREEN: how many players, each one's faction and team, whether the first
## slot is the player or a bot (unticked, the player watches), and Play. Placeholder visuals,
## built in code; the state is a SkirmishSetup, which this only draws and edits.
##
## Play freezes the setup into a recipe, generates the map on a worker thread — it takes seconds
## — and hands the built scenario to SceneManager. The match is always HEGEMONY for now.
## gdd/systems/ux/ui/menus.md §Skirmish.

#region Signals
## The Back button: the menu returns to its main page.
signal back_requested
#endregion

#region Constants
const ROW_LABEL_WIDTH: float = 90.0
const CONTROL_WIDTH: float = 170.0
#endregion

#region Properties
var setup: SkirmishSetup = SkirmishSetup.new()

var _player_count: OptionButton
var _rows: GridContainer
var _status: Label
var _play: Button
var _back: Button
var _human: CheckBox

var _thread: Thread = null
var _pending_recipe: Dictionary = {}
#endregion


#region Lifecycle
func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var heading := Label.new()
	heading.text = "Skirmish"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 26)
	add_child(heading)

	var count_row := HBoxContainer.new()
	count_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var count_label := Label.new()
	count_label.text = "Players"
	count_row.add_child(count_label)
	_player_count = OptionButton.new()
	_player_count.name = "PlayerCount"
	for n: int in range(SkirmishSetup.MIN_PLAYERS, SkirmishSetup.MAX_PLAYERS + 1):
		_player_count.add_item(str(n), n)
	_player_count.item_selected.connect(_on_player_count_selected)
	count_row.add_child(_player_count)
	add_child(count_row)

	_rows = GridContainer.new()
	_rows.name = "Rows"
	_rows.columns = 4
	_rows.add_theme_constant_override("h_separation", 10)
	add_child(_rows)

	_status = Label.new()
	_status.name = "Status"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(420.0, 0.0)
	_status.add_theme_color_override("font_color", Color(0.9, 0.55, 0.45))
	add_child(_status)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	_back = _button("Back", "Back")
	_back.pressed.connect(func() -> void: back_requested.emit())
	buttons.add_child(_back)
	_play = _button("Play", "Play")
	_play.pressed.connect(play)
	buttons.add_child(_play)
	add_child(buttons)

	refresh()


func _process(_a_delta: float) -> void:
	if _thread == null or _thread.is_alive():
		return
	var generated: Dictionary = _thread.wait_to_finish()
	_thread = null
	_finish_launch(generated)


func _exit_tree() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null


#endregion


#region Public API
## Redraw every control from `setup`.
func refresh() -> void:
	if _rows == null:
		return
	_player_count.select(setup.player_count() - SkirmishSetup.MIN_PLAYERS)
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for i: int in setup.player_count():
		_add_row(i)
	var problems: PackedStringArray = setup.problems()
	_status.text = "\n".join(problems)
	_play.disabled = not problems.is_empty() or is_launching()
	_set_editable(not is_launching())


## Start the match: freeze the setup and generate its map off the main thread. Ignored while a
## launch is already running or the setup cannot be played.
func play() -> void:
	if is_launching() or not setup.can_play():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_pending_recipe = setup.recipe(rng)
	var params: MapGenerationParams = SkirmishLauncher.params_for(_pending_recipe)
	_thread = Thread.new()
	_thread.start(SkirmishLauncher.generate.bind(_pending_recipe, params))
	_status.text = "Generating map…"
	refresh()
	_status.text = "Generating map…"


func is_launching() -> bool:
	return _thread != null


#endregion


#region Internal
func _finish_launch(a_generated: Dictionary) -> void:
	if a_generated.has("refusal"):
		refresh()
		_status.text = a_generated["refusal"]
		return
	var built: Dictionary = SkirmishLauncher.build(_pending_recipe, a_generated["map"])
	if built.has("refusal"):
		refresh()
		_status.text = built["refusal"]
		return
	SceneManager.go_to_node(built["scenario"])


func _add_row(a_slot: int) -> void:
	var label := Label.new()
	label.text = "Player %d" % (a_slot + 1)
	label.custom_minimum_size = Vector2(ROW_LABEL_WIDTH, 0.0)
	label.add_theme_color_override("font_color", Entity.TEAM_COLOR_MAP.get(a_slot + 1, Color.WHITE))
	_rows.add_child(label)

	if a_slot == 0:
		_human = CheckBox.new()
		_human.name = "HumanSlot"
		_human.text = "You"
		_human.tooltip_text = "Untick to make this slot a bot and watch the match."
		_human.button_pressed = setup.human_plays_first_slot
		_human.focus_mode = Control.FOCUS_NONE
		_human.toggled.connect(_on_human_toggled)
		_rows.add_child(_human)
	else:
		var bot := Label.new()
		bot.text = "Bot"
		_rows.add_child(bot)

	var faction := OptionButton.new()
	faction.name = "Faction%d" % (a_slot + 1)
	faction.custom_minimum_size = Vector2(CONTROL_WIDTH, 0.0)
	var choices: Array[String] = [SkirmishSetup.RANDOM]
	choices.append_array(SkirmishSetup.FACTIONS)
	for i: int in choices.size():
		faction.add_item(SkirmishSetup.faction_title(choices[i]), i)
		faction.set_item_metadata(i, choices[i])
	faction.select(choices.find(setup.faction_of(a_slot)))
	faction.item_selected.connect(
		func(i: int) -> void:
			setup.set_faction(a_slot, str(faction.get_item_metadata(i)))
			refresh()
	)
	_rows.add_child(faction)

	var team := OptionButton.new()
	team.name = "Team%d" % (a_slot + 1)
	team.custom_minimum_size = Vector2(CONTROL_WIDTH * 0.7, 0.0)
	team.add_item("No team", SkirmishSetup.NO_TEAM)
	for t: int in range(1, PlayerSlot.NUM_TEAMS + 1):
		team.add_item("Team %d" % t, t)
	team.select(team.get_item_index(setup.team_of(a_slot)))
	team.item_selected.connect(
		func(i: int) -> void:
			setup.set_team(a_slot, team.get_item_id(i))
			refresh()
	)
	_rows.add_child(team)


func _on_player_count_selected(a_index: int) -> void:
	setup.set_player_count(_player_count.get_item_id(a_index))
	refresh()


func _on_human_toggled(a_on: bool) -> void:
	setup.human_plays_first_slot = a_on
	refresh()


func _set_editable(a_on: bool) -> void:
	_player_count.disabled = not a_on
	_back.disabled = not a_on
	for child: Node in _rows.get_children():
		if child is BaseButton:
			(child as BaseButton).disabled = not a_on


func _button(a_name: String, a_text: String) -> Button:
	var button := Button.new()
	button.name = a_name
	button.text = a_text
	button.custom_minimum_size = Vector2(160.0, 44.0)
	return button
#endregion
