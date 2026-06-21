class_name Scenario
extends Node3D

#region Configuration
## Total commanders including the neutral world commander at id 0. The skirmish
## therefore has (commander_count - 1) playable factions, ids 1 .. count-1.
@export var commander_count: int = 3

## Which commander id the local human controls. Set to 0 (or any value < 1) for a
## spectator session: no human rig is created, every faction is a Bot, and the
## player just watches the bots fight. The human can be any id >= 1.
@export var human_commander_id: int = 1

## Bot commander ids that are created but left inert (the "do nothing"
## convenience). A passive bot still gets a BotBrain; its think loop is disabled.
## Handy for isolating a single bot while developing/tuning the AI.
@export var passive_bot_ids: Array[int] = []
#endregion

#region Properties
var frame: int = 0

## Built in _ready() from the control config above: id 0 = neutral Commander,
## human_commander_id = the human rig (scenes/player.tscn), every other id = Bot.
var commanders: Array = []

@onready var map: Map = $Map
#endregion

#region Lifecycle
func _ready() -> void:
	_build_commanders()

	var players_node = Node3D.new()
	players_node.name = "Players"
	add_child(players_node, true)
	players_node.set_owner(self)

	for commander in commanders:
		players_node.add_child(commander)
		commander.set_owner(self)
		# Every Bot (i.e. every non-human, non-neutral commander) gets a brain.
		if commander is Bot:
			_attach_brain(commander)

	var has_view_camera: bool = false
	for commander: Commander in commanders: # setting camera
		if commander.has_node("Camera"):
			commander.get_node("Camera").make_current()
			var camera: Node3D = commander.get_node("Camera")
			camera.look_at(Vector3.ZERO)
			# camera.rotate_x(deg_to_rad(180))
			has_view_camera = true

	# Spectator: no human rig means no Camera became current, so the viewport
	# shows the empty background. Give the watcher a free pan/zoom camera framed
	# on the map.
	if not has_view_camera:
		_setup_spectator_camera()

	# Typed Entity (not Commandable): commander/default_commander_id are Entity-level,
	# and the "commandable" group now also holds non-commandable owned entities such
	# as Deposit. fog.gd / minimap.gd already iterate this group as Entity.
	for entity: Entity in get_tree().get_nodes_in_group("commandable"):
		entity.commander = commanders[entity.default_commander_id]

	# Frame the player's starting position: buildings if any, else units.
	_center_player_camera_on_starting_entities()

	var event_manager := get_node_or_null("ScenarioTriggerManager") as ScenarioTriggerManager
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
## Construct the commander list from the control config. id 0 is always the
## neutral world commander; the configured human id (if >= 1) gets the human rig
## from scenes/player.tscn; every other id is a Bot. Also publishes the human id
## to RTSController so fog/minimap/commandable adopt the right local viewpoint
## (PLAYER_COMMANDER_ID < 1 in spectator mode means "no local human").
func _build_commanders() -> void:
	RTSController.PLAYER_COMMANDER_ID = human_commander_id
	commanders = []
	for o: int in range(commander_count):
		var c: Commander
		if o >= 1 and o == human_commander_id:
			c = load("res://scenes/player.tscn").instantiate()
		elif o == 0:
			c = Commander.new()  # neutral / world
		else:
			c = Bot.new()
		c.id = o
		commanders.append(c)


## Create a free-flying spectator camera when there is no human rig (spectator
## sessions). Mirrors the player camera's orthographic 45° framing (see
## scenes/player.tscn) and centers on the map. RTSCamera3D drives its own pan /
## zoom / rotate from input, so the watcher can move around with no controller.
func _setup_spectator_camera() -> void:
	var cam := RTSCamera3D.new()
	cam.name = "SpectatorCamera"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 15.0
	cam.far = 1000.0
	# RTSCamera3D._init() binds the zoom callables from `projection`, but that
	# runs before we set it here, so bind the orthographic variants explicitly.
	cam.zoom_in = cam.zoom_in_orthogonal
	cam.zoom_out = cam.zoom_out_orthogonal
	# Same tilted basis + height as scenes/player.tscn's Camera (45° downward).
	cam.transform = Transform3D(
		Vector3(1, 0, 0),
		Vector3(0, -0.7071067, 0.7071067),
		Vector3(0, -0.7071067, -0.7071067),
		Vector3(0, 20, 20)
	)
	add_child(cam)
	cam.set_owner(self)
	cam.make_current()
	# Orient the camera at the map centre. The authored basis above is only a
	# starting vantage; the human camera path likewise relies on look_at() to
	# actually point at the ground (flat maps put world origin near the middle).
	cam.look_at(Vector3.ZERO)


## Give a Bot its decision/tick layer. Passive bots (listed in passive_bot_ids)
## still get a brain so the structure is uniform; it just stays inert.
func _attach_brain(bot: Bot) -> void:
	var brain := BotBrain.new()
	brain.name = "BotBrain"
	brain.active = not passive_bot_ids.has(bot.id)
	bot.add_child(brain)
	brain.set_owner(self)


## Move the player's camera so the view centers on the centroid of the player's
## buildings at game start.  If the player has no buildings, centers on the
## centroid of the player's units instead.  If the player owns neither, the
## camera is left where it is.
func _center_player_camera_on_starting_entities() -> void:
	# Spectator (or otherwise no human rig): there is no player camera to center.
	var pid: int = RTSController.PLAYER_COMMANDER_ID
	if pid < 1 or pid >= commanders.size():
		return
	var player: Commander = commanders[pid]
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


## Called when a ScenarioTriggerManager child emits message_requested.
## Connect the HUD notification UI here once one exists.
func _on_scenario_message(text: String) -> void:
	print("[Scenario] ", text)


## Called when a ScenarioTriggerManager child emits game_over.
func _on_game_over(won: bool) -> void:
	print("[Scenario] Game over — player %s" % ("wins" if won else "loses"))
	# TODO: show win/lose screen and pause or return to menu.
#endregion


# TODO: unused function
#func purge() -> void:
#	if has_node("Players"):
#		$Players.queue_free()
