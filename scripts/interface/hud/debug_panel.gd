class_name DebugPanel
extends PanelContainer

## The debug menu: who the player is, each bot's difficulty, and the piece spawner's card.
## Up exactly while the debug view is (DebugMode.is_active()), and while up it replaces the
## top-right HUD, whose nodes are named in `hidden_while_up`. A button folds it to its title
## bar. See gdd/systems/ux/ui/debug-mode.md.
##
## The LAYOUT is authored, in scenes/interface/debug_panel.tscn, and instanced into the
## player HUD; this script fills the rows the session decides (commanders, factions, pieces).

## The label a commander id is listed under. Neutral is the world, not a seat: choosing it
## changes who owns placed pieces and nothing else.
const NEUTRAL_LABEL: String = "Neutral"
const NEUTRAL_ID: int = 0
## Text on the fold button while the body is shown, and while it is folded.
const FOLD_TEXT: String = "–"
const UNFOLD_TEXT: String = "+"

## The HUD nodes this panel stands in for while it is up (the objective checklist, the
## scenario timer, the command-error line). Paths are relative to this node.
@export var hidden_while_up: Array[NodePath] = []

@onready var _body: Control = %Body
@onready var _fold_button: Button = %FoldButton
@onready var _player_option: OptionButton = %PlayerOption
@onready var _bot_rows: VBoxContainer = %BotRows
@onready var _faction_option: OptionButton = %FactionOption
@onready var _piece_list: VBoxContainer = %PieceList

var _controller: RTSController = null
var _scenario: Scenario = null
var _entries: Array = []
var _factions: Array[String] = []
## Whether the panel was up last frame. Shown and hidden on the edge, so the HUD it replaces
## is only touched when that changes.
var _is_up: bool = false
## What each hidden HUD node's visibility was when the panel came up, to give back.
var _restored_visibility: Dictionary = {}
## The commander id the local player STARTED as, read one frame in (the scenario assigns it in
## its own _ready). Kept because the card opens on that seat's faction even after a play_as.
var _starting_player_id: int = NEUTRAL_ID
## Whether the card has opened yet: the player's faction is chosen on the first opening only,
## so a faction browsed since stays put.
var _has_opened: bool = false


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
	_faction_option.item_selected.connect(func(_i: int) -> void: _build_pieces())
	for faction: String in _factions:
		_faction_option.add_item(faction.capitalize())
	if _scenario != null:
		_scenario.local_player_changed.connect(func(_c: Commander) -> void: _build_players())
	# Deferred: this panel is built with the player rig, before Scenario has attached the
	# commanders' brains.
	_build_players.call_deferred()
	_build_bots.call_deferred()
	_remember_starting_player.call_deferred()
	_build_pieces()


func _process(_a_delta: float) -> void:
	var is_up: bool = DebugMode.is_active()
	if is_up == _is_up:
		return
	_is_up = is_up
	visible = is_up
	if is_up and not _has_opened:
		_has_opened = true
		_select_player_faction()
	for path: NodePath in hidden_while_up:
		var node: CanvasItem = get_node_or_null(path) as CanvasItem
		if node == null:
			continue
		if is_up:
			_restored_visibility[path] = node.visible
			node.visible = false
		else:
			node.visible = _restored_visibility.get(path, true)


#region Rows
## One entry per commander 1..N, then Neutral; the selected one is who owns placed pieces.
func _build_players() -> void:
	_player_option.clear()
	for commander: Commander in _commanders():
		if commander.id != NEUTRAL_ID:
			_player_option.add_item("Commander %d" % commander.id, commander.id)
	_player_option.add_item(NEUTRAL_LABEL, NEUTRAL_ID)
	var owner_id: int = RTSController.PLAYER_COMMANDER_ID
	if (
		_controller != null
		and _controller.debug_placement_owner_id != RTSController.DEBUG_OWNER_IS_PLAYER
	):
		owner_id = _controller.debug_placement_owner_id
	_player_option.select(_player_option.get_item_index(owner_id))


## A commander becomes the player (Scenario.play_as); Neutral only takes over placement.
func _on_player_selected(a_index: int) -> void:
	var id: int = _player_option.get_item_id(a_index)
	if id == NEUTRAL_ID:
		_controller.debug_placement_owner_id = NEUTRAL_ID
		return
	_controller.debug_placement_owner_id = RTSController.DEBUG_OWNER_IS_PLAYER
	if _scenario != null:
		_scenario.play_as(id)


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


## The piece's card: its production button's label and tooltips where it has one.
func _piece_button(a_entry: Dictionary) -> VerboseTooltipButton:
	var button := VerboseTooltipButton.new()
	button.name = String(a_entry["id"])
	button.text = a_entry["label"]
	button.focus_mode = Control.FOCUS_NONE
	var tool: Tool = Tool.for_name(a_entry["tool"]) if a_entry["tool"] != "" else null
	button.simple_tooltip = tool.simple_tooltip if tool != null else "Place %s" % a_entry["label"]
	button.verbose_tooltip = tool.verbose_tooltip if tool != null else String(a_entry["scene"])
	button.pressed.connect(func() -> void: _controller.arm_debug_piece(a_entry))
	return button


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
