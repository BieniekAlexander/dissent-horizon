class_name Scenario
extends Node3D

#region Properties
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

@onready var map: Map = $Map
#endregion

#region Lifecycle
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

	# Typed Entity (not Commandable): commander/default_commander_id are Entity-level,
	# and the "commandable" group now also holds non-commandable owned entities such
	# as Deposit. fog.gd / minimap.gd already iterate this group as Entity.
	for entity: Entity in get_tree().get_nodes_in_group("commandable"):
		entity.commander = commanders[entity.default_commander_id]

	# Frame the player's starting position: buildings if any, else units.
	_center_player_camera_on_starting_entities()

	var event_manager := get_node_or_null("ScenarioEventManager") as ScenarioEventManager
	if event_manager != null:
		event_manager.message_requested.connect(_on_scenario_message)
		event_manager.game_over.connect(_on_game_over)

	if Engine.is_editor_hint():
		set_physics_process(false)

func _physics_process(delta: float) -> void:
	frame += 1
	# $Map.nav_region.bake_navigation_mesh(false)
#endregion

#region Private helpers
## Move the player's camera so the view centers on the centroid of the player's
## buildings at game start.  If the player has no buildings, centers on the
## centroid of the player's units instead.  If the player owns neither, the
## camera is left where it is.
func _center_player_camera_on_starting_entities() -> void:
	var player: Commander = commanders[RTSController.PLAYER_COMMANDER_ID]
	var camera := player.get_node_or_null("Camera") as RTSCamera3D
	if camera == null:
		return

	# Buildings take priority; fall back to units.
	var positions: Array[Vector2] = _player_owned_positions_xz(player, "structure")
	if positions.is_empty():
		positions = _player_owned_positions_xz(player, "unit")
	if positions.is_empty():
		return  # no buildings or units — leave the camera as-is

	var centroid := Vector2.ZERO
	for p: Vector2 in positions:
		centroid += p
	centroid /= float(positions.size())
	camera.center_on(centroid)


## XZ positions of every entity in `group` (e.g. "structure" / "unit") owned by
## `player`.  Empty when the player owns none.
func _player_owned_positions_xz(player: Commander, group: String) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for node: Node in get_tree().get_nodes_in_group(group):
		var entity := node as Commandable
		if entity != null and entity.commander == player:
			result.append(VU.inXZ(entity.global_position))
	return result


## Called when a ScenarioEventManager child emits message_requested.
## Connect the HUD notification UI here once one exists.
func _on_scenario_message(text: String) -> void:
	print("[Scenario] ", text)


## Called when a ScenarioEventManager child emits game_over.
func _on_game_over(won: bool) -> void:
	print("[Scenario] Game over — player %s" % ("wins" if won else "loses"))
	# TODO: show win/lose screen and pause or return to menu.
#endregion


# TODO: unused function
#func purge() -> void:
#	if has_node("Players"):
#		$Players.queue_free()
