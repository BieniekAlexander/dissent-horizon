class_name SkirmishLobby
extends VBoxContainer
## THE SKIRMISH SETUP SCREEN: how many players, each one's faction and team, whether the first
## slot is the player or a bot (unticked, the player watches), and Play. Placeholder visuals,
## built in code; the state is a SkirmishSetup, which this only draws and edits.
##
## Play freezes the setup into a recipe, generates the map on a worker thread — it takes seconds
## — and hands the built scenario to SceneManager. The match is always HEGEMONY for now.
## gdd/systems/ux/ui/menus.md §Skirmish.
##
## NETWORKED (attach): the setup is the LobbyLink's. The host edits it as on one machine, marks
## slots OPEN for other players and sets the input delay; a joiner sees it, and may only take a
## free open slot. Play is the host's, and starts every peer: each generates the map from the
## recipe and enters the match from its own seat (NetMatch.build_scenario).
## gdd/systems/ux/ui/menus.md §Multiplayer.

#region Signals
## The Back button: the menu returns to its main page.
signal back_requested
## A networked lobby ended without a match — refused, or the host left — and why.
signal lobby_left(a_reason: String)
#endregion

#region Constants
const ROW_LABEL_WIDTH: float = 90.0
const CONTROL_WIDTH: float = 170.0
## The most input delay the host may set: past a second the match is unplayable anyway.
const MAX_INPUT_DELAY_MS: float = 1000.0
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

## The networked lobby this draws, or null on one machine.
var link: LobbyLink = null
## The Play message a networked match is being built from while its map generates.
var _pending_launch: Dictionary = {}
var _delay_row: HBoxContainer
var _delay_ms: SpinBox
## The host has typed a delay, so the measured one no longer replaces it.
var _is_delay_set_by_hand: bool = false
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
	_rows.columns = 5
	_rows.add_theme_constant_override("h_separation", 10)
	add_child(_rows)

	_delay_row = HBoxContainer.new()
	_delay_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var delay_label := Label.new()
	delay_label.text = "Input delay (ms)"
	_delay_row.add_child(delay_label)
	_delay_ms = SpinBox.new()
	_delay_ms.name = "InputDelay"
	_delay_ms.min_value = 0.0
	_delay_ms.max_value = MAX_INPUT_DELAY_MS
	_delay_ms.tooltip_text = "How long an order waits before it applies, on every machine."
	_delay_ms.value_changed.connect(func(_v: float) -> void: _is_delay_set_by_hand = true)
	_delay_row.add_child(_delay_ms)
	_delay_row.visible = false
	add_child(_delay_row)

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
	_back.pressed.connect(leave)
	buttons.add_child(_back)
	_play = _button("Play", "Play")
	_play.pressed.connect(_on_play_pressed)
	buttons.add_child(_play)
	add_child(buttons)

	refresh()


func _process(_a_delta: float) -> void:
	if link != null:
		link.poll()
		_show_measured_delay()
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
## Draw `a_link`'s lobby: its setup, edited by the host and watched by a joiner, until Play,
## a refusal or Back. Null returns the lobby to one machine.
func attach(a_link: LobbyLink) -> void:
	link = a_link
	_is_delay_set_by_hand = false
	_pending_launch = {}
	if link != null:
		if link.setup != null:
			setup = link.setup
		link.changed.connect(_on_link_changed)
		link.started.connect(_on_link_started)
		link.refused.connect(_on_link_refused)
	else:
		setup = SkirmishSetup.new()
	refresh()


## Leave: a networked lobby is closed, its match transport with it.
func leave() -> void:
	if link != null:
		var was: LobbyLink = link
		attach(null)
		was.close()
		was.close_transport()
	back_requested.emit()


func is_networked() -> bool:
	return link != null


func is_host() -> bool:
	return link == null or link.is_host()


## Redraw every control from `setup`.
func refresh() -> void:
	if _rows == null:
		return
	if is_networked() and link.setup == null:
		_show_connecting()
		return
	_player_count.select(setup.player_count() - SkirmishSetup.MIN_PLAYERS)
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for i: int in setup.player_count():
		_add_row(i)
	var problems: PackedStringArray = setup.problems()
	_status.text = "\n".join(problems)
	_play.visible = is_host()
	_play.disabled = (
		not problems.is_empty() or is_launching() or (is_networked() and not link.can_start())
	)
	_delay_row.visible = is_networked() and is_host()
	_set_editable(not is_launching() and is_host())
	if is_networked() and setup.player_count() > 0:
		_status.text = "\n".join(problems + PackedStringArray([_members_line()]))


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
	if not _pending_launch.is_empty():
		_finish_networked_launch(a_generated["map"])
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

	if is_networked():
		_rows.add_child(_seat_cell(a_slot))
	elif a_slot == 0:
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
			_edited()
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
			_edited()
	)
	_rows.add_child(team)

	# A bot's difficulty; disabled on the player's own slot, which no bot plays.
	var difficulty := OptionButton.new()
	difficulty.name = "Difficulty%d" % (a_slot + 1)
	difficulty.custom_minimum_size = Vector2(CONTROL_WIDTH * 0.7, 0.0)
	for name: String in PlayerSlot.Difficulty.keys():
		difficulty.add_item(name.capitalize(), PlayerSlot.Difficulty[name])
	difficulty.select(difficulty.get_item_index(setup.difficulty_of(a_slot)))
	difficulty.set_meta(&"human", not setup.is_bot(a_slot))
	difficulty.tooltip_text = "Bot difficulty" if setup.is_bot(a_slot) else "You play this slot"
	difficulty.item_selected.connect(
		func(i: int) -> void:
			setup.set_difficulty(a_slot, difficulty.get_item_id(i) as PlayerSlot.Difficulty)
			_edited()
	)
	_rows.add_child(difficulty)


func _on_player_count_selected(a_index: int) -> void:
	setup.set_player_count(_player_count.get_item_id(a_index))
	_edited()


func _on_human_toggled(a_on: bool) -> void:
	setup.human_plays_first_slot = a_on
	_edited()


## The setup changed here: redraw, and in a hosted lobby tell every joiner.
func _edited() -> void:
	refresh()
	if is_networked() and link.is_host():
		link.publish()


#region Networked
## A networked slot's second column: the host's first slot, an OPEN slot (the host ticks it; a
## joiner sees who sits there, or takes it when free), or a bot.
func _seat_cell(a_slot: int) -> Control:
	var peer: int = setup.peer_in(a_slot)
	var mine: bool = peer != 0 and peer == link.local_id
	if a_slot == 0:
		return _label("You" if mine else "Host")
	if link.is_host():
		var open := CheckBox.new()
		open.name = "Open%d" % (a_slot + 1)
		open.text = "Open" if peer == 0 else "Peer %d" % peer
		open.tooltip_text = "Open this slot to another player; closed, a bot plays it."
		open.button_pressed = setup.is_open(a_slot)
		open.focus_mode = Control.FOCUS_NONE
		open.toggled.connect(
			func(a_on: bool) -> void:
				setup.set_open(a_slot, a_on)
				_edited()
		)
		return open
	if not setup.is_open(a_slot):
		return _label("Bot")
	if peer != 0:
		return _label("You" if mine else "Peer %d" % peer)
	var take := Button.new()
	take.name = "Take%d" % (a_slot + 1)
	take.text = "Take"
	take.pressed.connect(link.claim.bind(a_slot))
	take.set_meta(&"joiner_control", true)
	return take


## A joiner the host has not answered yet: nothing to draw but that.
func _show_connecting() -> void:
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_status.text = "Connecting to the host…"
	_play.visible = false
	_delay_row.visible = false
	_player_count.disabled = true


func _label(a_text: String) -> Label:
	var label := Label.new()
	label.text = a_text
	return label


## Who is in the lobby, with each joiner's round trip as the host measures it.
func _members_line() -> String:
	var parts: PackedStringArray = []
	for id: int in link.members():
		var rtt: int = link.round_trip_ms(id)
		var you: String = " (you)" if id == link.local_id else ""
		parts.append("Peer %d%s%s" % [id, you, " — %d ms" % rtt if rtt >= 0 else ""])
	return "In the lobby: " + ", ".join(parts)


## Keep the input delay at what the round trips call for, until the host types one.
func _show_measured_delay() -> void:
	if not link.is_host() or _is_delay_set_by_hand:
		return
	_delay_ms.set_value_no_signal(roundf(link.measured_delay_seconds() * 1000.0))


func _on_play_pressed() -> void:
	if not is_networked():
		play()
		return
	if not link.can_start() or is_launching():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	link.start(setup.recipe(rng), _delay_ms.value / 1000.0)


func _on_link_changed() -> void:
	if link.setup != null:
		setup = link.setup
	refresh()


## Play, on this machine: generate the map from the host's recipe, then build the match.
func _on_link_started(a_launch: Dictionary) -> void:
	_pending_launch = a_launch
	_pending_recipe = a_launch["recipe"]
	var params: MapGenerationParams = SkirmishLauncher.params_for(_pending_recipe)
	_thread = Thread.new()
	_thread.start(SkirmishLauncher.generate.bind(_pending_recipe, params))
	refresh()
	_status.text = "Generating map…"


func _finish_networked_launch(a_map: GeneratedMap) -> void:
	var built: Dictionary = NetMatch.build_scenario(_pending_launch, a_map)
	if built.has("refusal"):
		_on_link_refused(built["refusal"])
		return
	# The lobby's own connection is done; the match transport now belongs to the NetMatch.
	link.close()
	SceneManager.go_to_node(built["scenario"])


func _on_link_refused(a_reason: String) -> void:
	var was: LobbyLink = link
	attach(null)
	if was != null:
		was.close()
		was.close_transport()
	lobby_left.emit(a_reason)


#endregion


func _set_editable(a_on: bool) -> void:
	_player_count.disabled = not a_on
	_back.disabled = is_launching()
	_delay_ms.editable = a_on
	for child: Node in _rows.get_children():
		if child is BaseButton:
			var is_joiner_control: bool = bool(child.get_meta(&"joiner_control", false))
			(child as BaseButton).disabled = (
				is_launching()
				if is_joiner_control
				else not a_on or bool(child.get_meta(&"human", false))
			)


func _button(a_name: String, a_text: String) -> Button:
	var button := Button.new()
	button.name = a_name
	button.text = a_text
	button.custom_minimum_size = Vector2(160.0, 44.0)
	return button
#endregion
