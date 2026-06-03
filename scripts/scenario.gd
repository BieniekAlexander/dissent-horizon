class_name Scenario
extends Node3D


### GAME STATE
var frame: int = 0
@onready var commanders: Array = range(0, 3).map(
	func(o):
		var c = (
			load("res://scenes/player.tscn").instantiate() if o == RTSController.PLAYER_COMMANDER_ID
			else Bot.new() if o > RTSController.PLAYER_COMMANDER_ID
			else Commander.new()
		)
		c.id = o
		return c
)

### GAME WORLD
@onready var map: Map = $Map

### NODE
func _ready() -> void:
	var players_node = Node3D.new()
	players_node.name = "Players"
	add_child(players_node, true)
	players_node.set_owner(self)

	for commander in commanders:
		players_node.add_child(commander)
		commander.set_owner(self)

	for commander: Commander in commanders: # setting camera
		if commander.has_node("Camera"):
			commander.get_node("Camera").make_current()
			var camera: Node3D = commander.get_node("Camera")
			camera.look_at(Vector3.ZERO)
			# camera.rotate_x(deg_to_rad(180))

	for commandable: Commandable in get_tree().get_nodes_in_group("commandable"):
		commandable.commander = commanders[commandable.default_commander_id]

	var event_manager := get_node_or_null("ScenarioEventManager") as ScenarioEventManager
	if event_manager != null:
		event_manager.message_requested.connect(_on_scenario_message)
		event_manager.game_over.connect(_on_game_over)

	if Engine.is_editor_hint():
		set_physics_process(false)

func _physics_process(delta: float) -> void:
	frame += 1
	# $Map.nav_region.bake_navigation_mesh(false)


## Called when a ScenarioEventManager child emits message_requested.
## Connect the HUD notification UI here once one exists.
func _on_scenario_message(text: String) -> void:
	print("[Scenario] ", text)


## Called when a ScenarioEventManager child emits game_over.
func _on_game_over(won: bool) -> void:
	print("[Scenario] Game over — player %s" % ("wins" if won else "loses"))
	# TODO: show win/lose screen and pause or return to menu.


# TODO: unused function
#func purge() -> void:
#	if has_node("Players"):
#		$Players.queue_free()
	
