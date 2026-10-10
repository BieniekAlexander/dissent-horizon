class_name DebugPanel
extends PanelContainer

## The debug menu: who the player is (or nobody, spectating), the playback speed while playing,
## each bot's difficulty, every commander's energy and dominion, the piece spawner's card, and
## the upgrade card that grants or revokes the player's upgrades.
## Up exactly while the debug view is (DebugMode.is_active()), and while up it replaces the
## top-right HUD, whose nodes are named in `hidden_while_up`. A button folds it to its title
## bar. See gdd/systems/ux/ui/debug-mode.md.
##
## The LAYOUT is authored, in scenes/interface/debug_panel.tscn, and instanced into the
## player HUD; this script fills the rows the session decides (commanders, factions, pieces).

## The world's commander id. Neutral is the world, not a seat, so it is never listed.
const NEUTRAL_ID: int = 0
## The player setting's entry for playing nobody (Scenario.spectate). An id no commander can
## have, since the option's ids are commander ids.
const SPECTATOR_ID: int = Commander.NUM_MAX_COMMANDERS
const SPECTATOR_LABEL: String = "Spectator"
## Text on the fold button while the body is shown, and while it is folded.
const FOLD_TEXT: String = "–"
const UNFOLD_TEXT: String = "+"
## A spawner card drawn as a picture: big enough to tell one animal or tree from another,
## small enough that a faction's roster still flows several to a row.
const PIECE_ICON_SIZE: Vector2 = Vector2(40, 40)
## Wide enough for a seven-digit stockpile without the field scrolling.
const RESOURCE_FIELD_WIDTH: float = 72.0

## The HUD nodes this panel stands in for while it is up (the objective checklist, the
## command-error line). Paths are relative to this node.
@export var hidden_while_up: Array[NodePath] = []
## The same, for top-right HUD the SCENARIO owns rather than the player rig, found by group.
@export var hidden_groups_while_up: Array[StringName] = [ScenarioTimer.GROUP]

@onready var _body: Control = %Body
@onready var _fold_button: Button = %FoldButton
@onready var _player_option: OptionButton = %PlayerOption
@onready var _playback_controls: PlaybackControls = %PlaybackControls
@onready var _piece_card: Control = %PieceCard
@onready var _bot_rows: VBoxContainer = %BotRows
@onready var _resource_rows: VBoxContainer = %ResourceRows
@onready var _faction_option: OptionButton = %FactionOption
@onready var _piece_list: VBoxContainer = %PieceList
@onready var _upgrade_list: HFlowContainer = %UpgradeList

var _controller: RTSController = null
var _scenario: Scenario = null
var _entries: Array = []
var _factions: Array[String] = []
## Whether the panel was up last frame. Shown and hidden on the edge, so the HUD it replaces
## is only touched when that changes.
var _is_up: bool = false
## What each hidden HUD node's visibility was when the panel came up, to give back, by
## instance id.
var _restored_visibility: Dictionary = {}
## The commander id the local player STARTED as, read one frame in (the scenario assigns it in
## its own _ready). Kept because the card opens on that seat's faction even after a play_as.
var _starting_player_id: int = NEUTRAL_ID
## Whether the card has opened yet: the player's faction is chosen on the first opening only,
## so a faction browsed since stays put.
var _has_opened: bool = false
## Whether the playback controls have their clock yet: the HUD is built before the scenario's
## trigger manager, which owns it.
var _is_clock_bound: bool = false


func _ready() -> void:
	visible = false
	if Engine.is_editor_hint():
		return
	# Readable while a scripted beat has paused the world, like the rest of the HUD.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_controller = _find_controller()
	_scenario = Scenario.of(self)
	_entries = DebugRoster.load_entries()
	_factions = DebugRoster.factions(_entries)
	_fold_button.pressed.connect(_toggle_fold)
	_player_option.item_selected.connect(_on_player_selected)
	_faction_option.item_selected.connect(
		func(_i: int) -> void:
			_build_pieces()
			_build_upgrades()
	)
	for faction: String in _factions:
		_faction_option.add_item(faction.capitalize())
	if _scenario != null:
		_scenario.local_player_changed.connect(func(_c: Commander) -> void: _build_players())
	# Deferred: this panel is built with the player rig, before Scenario has attached the
	# commanders' brains.
	_build_players.call_deferred()
	_build_bots.call_deferred()
	_build_resources.call_deferred()
	_remember_starting_player.call_deferred()
	_build_pieces()
	_build_upgrades()


func _process(_a_delta: float) -> void:
	_show_for_mode()
	var is_up: bool = DebugMode.is_active()
	if is_up:
		_sync_upgrade_buttons()
	if is_up == _is_up:
		return
	_is_up = is_up
	visible = is_up
	if is_up and not _has_opened:
		_has_opened = true
		_select_player_faction()
	var hidden: Array[CanvasItem] = []
	for path: NodePath in hidden_while_up:
		var node: CanvasItem = get_node_or_null(path) as CanvasItem
		if node != null:
			hidden.append(node)
	for group: StringName in hidden_groups_while_up:
		for node: Node in get_tree().get_nodes_in_group(group):
			if node is CanvasItem:
				hidden.append(node as CanvasItem)
	for node: CanvasItem in hidden:
		if is_up:
			_restored_visibility[node.get_instance_id()] = node.visible
			node.visible = false
		else:
			node.visible = _restored_visibility.get(node.get_instance_id(), true)


## What differs between playing and spectating: the playback speed is the spectator panel's
## while spectating, and the piece card places nothing from a look-only HUD.
func _show_for_mode() -> void:
	var is_spectating: bool = _controller != null and _controller.is_look_only
	_playback_controls.visible = not is_spectating
	# Hides the upgrade card with it, which shares its scroll: no seat, nobody to upgrade.
	_piece_card.visible = not is_spectating
	if not _is_clock_bound and _scenario != null and _scenario.trigger_manager() != null:
		_playback_controls.bind(_scenario.trigger_manager().simulation_clock)
		_is_clock_bound = true


#region Rows
## Spectator, then one entry per commander 1..N; the selected one is who the player is.
func _build_players() -> void:
	_player_option.clear()
	_player_option.add_item(SPECTATOR_LABEL, SPECTATOR_ID)
	for commander: Commander in _commanders():
		if commander.id != NEUTRAL_ID:
			_player_option.add_item("Commander %d" % commander.id, commander.id)
	var player: Commander = _scenario.local_player() if _scenario != null else null
	var player_id: int = player.id if player != null else SPECTATOR_ID
	_player_option.select(_player_option.get_item_index(player_id))


## A commander becomes the player (Scenario.play_as) and Spectator detaches it
## (Scenario.spectate). A choice the scenario refuses snaps the picker back to who the player is.
func _on_player_selected(a_index: int) -> void:
	var id: int = _player_option.get_item_id(a_index)
	if _scenario == null:
		return
	var is_changed: bool = _scenario.spectate() if id == SPECTATOR_ID else _scenario.play_as(id)
	if not is_changed:
		_build_players()


## A difficulty picker per commander that has a bot.
func _build_bots() -> void:
	for child: Node in _bot_rows.get_children():
		child.queue_free()
	for commander: Commander in _commanders():
		var brain: BotBrain = (commander as Bot).brain() if commander is Bot else null
		if brain == null:
			continue
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "Commander %d" % commander.id
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var picker := OptionButton.new()
		for tier: String in PlayerSlot.Difficulty.keys():
			picker.add_item(tier.capitalize(), PlayerSlot.Difficulty[tier])
		picker.select(picker.get_item_index(brain.difficulty))
		var id: int = commander.id
		picker.item_selected.connect(
			func(a_index: int) -> void:
				_scenario.set_bot_difficulty(id, picker.get_item_id(a_index))
		)
		row.add_child(picker)
		_bot_rows.add_child(row)


## An energy and a dominion field per commander but the world. A field shows the live amount
## until it is focused; Enter or leaving it sets the commander to what it holds.
func _build_resources() -> void:
	for child: Node in _resource_rows.get_children():
		child.queue_free()
	for commander: Commander in _commanders():
		if commander.id == NEUTRAL_ID:
			continue
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "Commander %d" % commander.id
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		row.add_child(_resource_field(commander, &"energy"))
		row.add_child(_resource_field(commander, &"dominion"))
		_resource_rows.add_child(row)


## A digits-only field bound to `a_commander`'s `a_resource` ("energy" or "dominion").
func _resource_field(a_commander: Commander, a_resource: StringName) -> LineEdit:
	var field := LineEdit.new()
	field.custom_minimum_size = Vector2(RESOURCE_FIELD_WIDTH, 0.0)
	field.tooltip_text = String(a_resource).capitalize()
	field.text = str(a_commander.get(a_resource))
	field.text_changed.connect(
		func(a_text: String) -> void:
			var digits: String = digits_only(a_text)
			if digits != a_text:
				var caret: int = field.caret_column - (a_text.length() - digits.length())
				field.text = digits
				field.caret_column = maxi(caret, 0)
	)
	var apply: Callable = func() -> void:
		set_resource(a_commander, a_resource, field.text)
		field.text = str(a_commander.get(a_resource))
	field.text_submitted.connect(
		func(_a_text: String) -> void:
			apply.call()
			# Give the keyboard back to the game: a focused field swallows every hotkey.
			field.release_focus()
	)
	field.focus_exited.connect(apply)
	# Live while nobody is typing in it, so the field reads what the economy bars do.
	a_commander.resources_changed.connect(
		func() -> void:
			if is_instance_valid(field) and not field.has_focus():
				field.text = str(a_commander.get(a_resource))
	)
	return field


## `a_text` with every character that is not a digit removed.
static func digits_only(a_text: String) -> String:
	var out: String = ""
	for character: String in a_text:
		if character >= "0" and character <= "9":
			out += character
	return out


## Set `commander`'s `resource` ("energy" or "dominion") to the number `text` holds, through
## its one write-point so every listener hears it. Empty text changes nothing.
static func set_resource(commander: Commander, resource: StringName, text: String) -> void:
	var digits: String = digits_only(text)
	if commander == null or digits.is_empty():
		return
	var delta: int = int(digits) - int(commander.get(resource))
	if resource == &"energy":
		commander.add_energy(delta)
	elif resource == &"dominion":
		commander.add_dominion(delta)


func _remember_starting_player() -> void:
	_starting_player_id = RTSController.PLAYER_COMMANDER_ID


## The first time debug mode opens, the piece card shows the faction the player STARTED as.
## Read at opening rather than at game start: by then a skirmish has deployed, and its
## starting force is as good a witness as the Faction's own list. A spectator has no seat, and
## the card stays where it is.
func _select_player_faction() -> void:
	if (
		_scenario == null
		or _starting_player_id <= NEUTRAL_ID
		or _starting_player_id >= _scenario.commanders.size()
	):
		return
	var player: Commander = _scenario.commanders[_starting_player_id]
	if player == null:
		return
	var faction: String = DebugRoster.faction_of_scenes(_entries, _scene_paths_of(player))
	var index: int = _factions.find(faction)
	if index < 0 or index == _faction_option.selected:
		return
	_faction_option.select(index)
	_build_pieces()
	_build_upgrades()


## The scenes that say which faction `a_commander` plays: its faction's starting units, then
## whatever pieces it already owns.
static func _scene_paths_of(a_commander: Commander) -> Array:
	var paths: Array = []
	if a_commander.faction != null:
		for scene: PackedScene in a_commander.faction.starting_units:
			if scene != null:
				paths.append(scene.resource_path)
	for child: Node in a_commander.get_children():
		if child is Entity and child.scene_file_path != "":
			paths.append(child.scene_file_path)
	return paths


## The chosen faction's pieces, grouped as DebugRoster.groups lays them out.
func _build_pieces() -> void:
	for child: Node in _piece_list.get_children():
		child.queue_free()
	if _factions.is_empty():
		return
	var faction: String = _factions[maxi(_faction_option.selected, 0)]
	for group: Dictionary in DebugRoster.groups(_entries, faction):
		var title := Label.new()
		title.text = group["title"]
		_piece_list.add_child(title)
		var flow := HFlowContainer.new()
		for entry: Dictionary in group["entries"]:
			flow.add_child(_piece_button(entry))
		_piece_list.add_child(flow)


## The piece's card: its icon (or, with none made, its production button's label) and that
## button's tooltips where it has one — the same face the command card gives it.
func _piece_button(a_entry: Dictionary) -> VerboseTooltipButton:
	var button := VerboseTooltipButton.new()
	button.name = String(a_entry["id"])
	var icon: Texture2D = PieceIcons.for_id(StringName(a_entry["id"]))
	if icon != null:
		button.icon = icon
		button.expand_icon = true
		button.custom_minimum_size = PIECE_ICON_SIZE
	else:
		button.text = a_entry["label"]
	button.focus_mode = Control.FOCUS_NONE
	var tool: Tool = Tool.for_name(a_entry["tool"]) if a_entry["tool"] != "" else null
	button.simple_tooltip = tool.simple_tooltip if tool != null else "Place %s" % a_entry["label"]
	button.verbose_tooltip = tool.verbose_tooltip if tool != null else String(a_entry["scene"])
	button.pressed.connect(func() -> void: _controller.arm_debug_piece(a_entry))
	return button


## One toggle per upgrade of the faction the piece card shows: pressed while the selected player
## owns it. Pressing grants or revokes it outright — no research, no cost.
func _build_upgrades() -> void:
	for child: Node in _upgrade_list.get_children():
		child.queue_free()
	if _factions.is_empty():
		return
	var faction: String = _factions[maxi(_faction_option.selected, 0)]
	for id: StringName in UpgradeCatalog.ids_of_faction(faction):
		var button := Button.new()
		button.name = String(id)
		button.text = UpgradeCatalog.title_of(id)
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		var tool: Tool = Tool.for_name("command_tool_%s" % id)
		button.tooltip_text = tool.verbose_tooltip if tool != null else String(id)
		button.toggled.connect(
			func(a_is_on: bool) -> void:
				set_upgrade(_selected_player(), id, a_is_on)
				_sync_upgrade_buttons()
		)
		_upgrade_list.add_child(button)
	_sync_upgrade_buttons()


## Press each upgrade toggle exactly when the selected player owns it. Polled while the menu is
## up rather than signalled: the player can be swapped and research can finish at any time,
## and a handful of buttons is nothing to check each frame.
func _sync_upgrade_buttons() -> void:
	var player: Commander = _selected_player()
	for button: Node in _upgrade_list.get_children():
		if button is Button and not button.is_queued_for_deletion():
			var is_owned: bool = player != null and player.has_upgrade(StringName(button.name))
			(button as Button).set_pressed_no_signal(is_owned)
			(button as Button).disabled = player == null


## Grant `id` to `commander` when `is_on`, revoke it otherwise. Nothing without a commander.
static func set_upgrade(commander: Commander, id: StringName, is_on: bool) -> void:
	if commander == null:
		return
	if is_on:
		commander.complete_upgrade(id)
	else:
		commander.revoke_upgrade(id)


## The commander the Player setting names: the local player, or null while spectating.
func _selected_player() -> Commander:
	return _scenario.local_player() if _scenario != null else null


#endregion


func _toggle_fold() -> void:
	_body.visible = not _body.visible
	_fold_button.text = FOLD_TEXT if _body.visible else UNFOLD_TEXT
	# Height only: the width is the scene's minimum, so the right edge stays put.
	size = Vector2(size.x, 0.0)


func _commanders() -> Array:
	return _scenario.commanders if _scenario != null else []


func _find_controller() -> RTSController:
	var node: Node = get_parent()
	while node != null and not node is RTSController:
		node = node.get_parent()
	return node as RTSController
