extends Node

## HUD preview harness for the sanction sanction grid: builds player.tscn standalone against
## the Colonial faction, gives it one caster of each kind, walks part of the sanction grid,
## and opens the unlock menu — states a real scenario only reaches after minutes of play.
##
## THE CASTERS ARE WHAT MAKE THE DEPLOY BAR VISIBLE AT ALL: a bar button is shown only once
## the commander owns a piece that can use the ability, so a harness with no pieces renders
## an empty bar and says nothing about it. The Bombard is here for the other half — a free
## ability with `hud_button: true`, which is the case the bar used to be unable to draw.
## Render it with:
##   godot res://tools/sanction_menu_preview.tscn \
##     --write-movie /tmp/ord.png --fixed-fps 30 --quit-after 20 --resolution 1400x790
## See CLAUDE.md "Seeing the HUD without a screen".

const PLAYER: PackedScene = preload("res://scenes/player.tscn")
const COLONIAL: PackedScene = preload("res://scenes/factions/colonial.tscn")
## One caster per bar case: the Citadel casts the dominion-unlocked family below, the
## Bombard grants the free `bombard` ability.
const CASTERS: Array[String] = [
	"res://scenes/entities/structures/cl/cl_commandCenter.tscn",
	"res://scenes/entities/structures/cl/cl_defense_antiStructure.tscn",
]


func _ready() -> void:
	var player: Commander = PLAYER.instantiate() as Commander
	player.faction_scene = COLONIAL
	add_child(player)
	for path: String in CASTERS:
		var piece: Commandable = (load(path) as PackedScene).instantiate() as Commandable
		player.add_child(piece)
		piece.ownership.commander = player
		piece.build_progress = 1.0
	_drive(player)


func _drive(a_player: Commander) -> void:
	# The controller defers _setup_commander_sanctions out of its own _ready.
	await get_tree().process_frame
	await get_tree().process_frame
	a_player.dominion = 10000
	var sanction_grid: SanctionGrid = a_player.sanction_grid
	# Take a whole family plus one toll cell: that leaves the menu showing every state
	# at once — owned, superseded, buyable, parent-locked and tier-locked.
	for wanted: String in ["Scan 1", "Promotion", "Scan 2"]:
		for entry: SanctionGrid.Entry in sanction_grid.entries:
			if entry.sanction.sanction_name == wanted:
				prints("unlock", wanted, sanction_grid.try_unlock(entry))
	var controller: RTSController = a_player.get_node("Controller") as RTSController
	controller.toggle_sanction_menu()
	await get_tree().process_frame
	# The blocking-UI rects: each must cover its own buttons and nothing else.
	for node: Node in get_tree().get_nodes_in_group(RTSController.SELECTION_BLOCKING_UI_GROUP):
		if (node as Control).is_visible_in_tree() and node.name in ["Row", "Panel"]:
			prints("blocking rect", node.name, (node as Control).get_global_rect())
