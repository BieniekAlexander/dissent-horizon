class_name Scenario
extends Node3D

#region Configuration
## The participants in this scenario, in commander-id order starting at 1 — the
## neutral world commander at id 0 is implicit and not a slot. Each slot builds one
## Commander (a Bot, or the human player.tscn rig) fielding its faction at its
## difficulty. A session with no human slot is a spectator session. Replaces the old
## commander_count / human_commander_id / passive_bot_ids trio.
@export var player_slots: Array[PlayerSlot] = []
#endregion

#region Properties
var frame: int = 0

## Built in _ready() from player_slots: id 0 = neutral Commander, then one Commander
## per slot (ids 1..N) — the human rig (scenes/player.tscn) for a non-bot slot, a Bot
## otherwise. Indexed by commander id (entities resolve owners via commanders[id]).
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

	# Every Bot gets a brain, configured with its slot's difficulty. Done in a second
	# pass (after the commanders are in the tree) so the brain attaches to a live bot.
	for slot: PlayerSlot in player_slots:
		if slot.commander is Bot:
			_attach_brain(slot.commander as Bot, slot.difficulty)

	# Create a Fog node for each bot commander so it tracks its own exploration.
	# The human player already has a Fog in player.tscn (watching_commander_id = -1).
	_create_bot_fogs()

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
		_setup_spectator_hud()
		_init_spectator_fog()

	# Typed Entity (not Commandable): commander/default_commander_id are Entity-level,
	# and the "commandable" group now also holds non-commandable owned entities such
	# as Deposit. fog.gd / minimap.gd already iterate this group as Entity.
	for entity: Entity in get_tree().get_nodes_in_group("commandable"):
		entity.commander = commanders[entity.default_commander_id]

	# Extension point: subclasses (e.g. Skirmish) spawn each slot's faction-defined
	# opening force here. Deliberately AFTER the owner-assignment loop above —
	# dynamically-spawned entities default to commander_id 0, so spawning earlier
	# would let that loop reset them to the neutral commander. Map.add_entities sets
	# their owner directly, and being placed after the loop keeps it.
	_spawn_initial_entities()

	# Frame the player's starting position: buildings if any, else units.
	_center_player_camera_on_starting_entities()

	var event_manager := _ensure_trigger_manager()
	event_manager.message_requested.connect(_on_scenario_message)
	event_manager.game_over.connect(_on_game_over)

	# In-world debug visualisation of the active bot's internals (scout coverage, …),
	# gated on hold-Spacebar + the bot-view toggle. See BotDebugOverlay.
	_create_bot_debug_overlay()

	if Engine.is_editor_hint():
		set_physics_process(false)

func _physics_process(delta: float) -> void:
	frame += 1
	# $Map.nav_region.bake_navigation_mesh(false)
#endregion

#region Private helpers
## Hook for subclasses to spawn each player slot's opening force at runtime. Base
## Scenario authors its starting entities directly in the scene tree, so this is a
## no-op; Skirmish overrides it to build each slot's structure + units from its
## faction. Called from _ready (see the call site for ordering constraints).
func _spawn_initial_entities() -> void:
	pass


## Construct the commander list from player_slots. id 0 is always the neutral world
## commander; each slot then builds commander id 1..N — the human rig
## (scenes/player.tscn) for a non-bot slot, a Bot otherwise — and the slot's faction
## is propagated onto it. Publishes the local human's id to RTSController so
## fog/minimap/commandable adopt the right viewpoint (PLAYER_COMMANDER_ID < 1 means
## a spectator session with no local human).
func _build_commanders() -> void:
	commanders = []

	var neutral := Commander.new()  # id 0 = neutral / world
	neutral.id = 0
	commanders.append(neutral)

	# Default to spectator; the first human slot (if any) claims the local viewpoint.
	RTSController.PLAYER_COMMANDER_ID = 0

	for i: int in player_slots.size():
		var slot: PlayerSlot = player_slots[i]
		var id: int = i + 1
		var c: Commander
		if slot.is_bot:
			c = Bot.new()
		else:
			c = load("res://scenes/player.tscn").instantiate()
			if RTSController.PLAYER_COMMANDER_ID < 1:
				RTSController.PLAYER_COMMANDER_ID = id
		c.id = id
		# Apply the slot's starting resources. Set before the commander enters the
		# tree; Commander's resource fields are plain (not @onready) so this sticks.
		c.ore = slot.starting_ore
		c.dominion = slot.starting_dominion
		# Propagate the slot's faction onto its commander. Commander._ready instances
		# it for the starting structure + ordnances. A null slot faction leaves the
		# commander's own default in place (e.g. the one player.tscn ships with).
		if slot.faction != null:
			c.faction_scene = slot.faction
		slot.commander = c
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


## Build a CanvasLayer HUD that shows one resource panel per non-neutral
## commander, plus a fog-toggle row so the spectator can switch perspectives.
## Called only in spectator mode (no human rig).
func _setup_spectator_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SpectatorHUD"
	add_child(layer)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(8.0, 8.0)
	layer.add_child(vbox)

	# ── Fog toggle row ──
	var fog_row := HBoxContainer.new()
	fog_row.name = "FogToggleRow"
	fog_row.add_theme_constant_override("separation", 6)
	vbox.add_child(fog_row)

	var no_fog_btn := Button.new()
	no_fog_btn.name = "FogBtn_NoFog"
	no_fog_btn.text = "No Fog"
	no_fog_btn.custom_minimum_size = Vector2(80.0, 28.0)
	fog_row.add_child(no_fog_btn)

	for commander: Commander in commanders:
		if commander.id == 0 or not commander is Bot:
			continue
		var btn := Button.new()
		btn.name = "FogBtn_%d" % commander.id
		btn.text = "Bot %d POV" % commander.id
		btn.custom_minimum_size = Vector2(100.0, 28.0)
		fog_row.add_child(btn)

	# Wire button callbacks now that all buttons exist.
	_wire_spectator_fog_buttons(fog_row)
	_refresh_spectator_fog_buttons(fog_row)

	vbox.add_child(HSeparator.new())

	# ── Per-commander resource labels ──
	for commander: Commander in commanders:
		if commander.id == 0:
			continue
		var label := RichTextLabel.new()
		label.name = "CommanderLabel_%d" % commander.id
		label.custom_minimum_size = Vector2(260.0, 85.0)
		vbox.add_child(label)
		_refresh_spectator_label(label, commander)
		commander.resources_changed.connect(_refresh_spectator_label.bind(label, commander))


func _wire_spectator_fog_buttons(fog_row: HBoxContainer) -> void:
	var no_fog_btn: Button = fog_row.get_node("FogBtn_NoFog")
	no_fog_btn.pressed.connect(func() -> void:
		Fog.active_commander_id = -2
		_refresh_spectator_fog_buttons(fog_row)
	)
	for commander: Commander in commanders:
		if commander.id == 0 or not commander is Bot:
			continue
		var btn: Button = fog_row.get_node("FogBtn_%d" % commander.id)
		var cid: int = commander.id
		btn.pressed.connect(func() -> void:
			Fog.active_commander_id = cid
			_refresh_spectator_fog_buttons(fog_row)
		)


func _refresh_spectator_fog_buttons(fog_row: HBoxContainer) -> void:
	var active_id: int = Fog.active_commander_id
	var no_fog_btn: Button = fog_row.get_node_or_null("FogBtn_NoFog") as Button
	if no_fog_btn != null:
		no_fog_btn.disabled = (active_id == -2)
	for commander: Commander in commanders:
		if commander.id == 0 or not commander is Bot:
			continue
		var btn: Button = fog_row.get_node_or_null("FogBtn_%d" % commander.id) as Button
		if btn != null:
			btn.disabled = (active_id == commander.id)


## Repaint one commander's spectator resource panel.
func _refresh_spectator_label(label: RichTextLabel, commander: Commander) -> void:
	label.text = (
		"Commander %d:\n\tore: %s\n\tvigor: %s\n\tdominion: %s" % [
			commander.id,
			commander.ore,
			"%s/%s" % [commander.vigor_required, commander.vigor_provided],
			commander.dominion,
		]
	)


## Set the initial active fog for spectator sessions: default to the first bot's
## perspective so entity visibility is immediately meaningful.
func _init_spectator_fog() -> void:
	for commander: Commander in commanders:
		if commander.id != 0 and commander is Bot:
			Fog.active_commander_id = commander.id
			return


## Create and attach a Fog node for each bot commander so every AI tracks its
## own exploration state. The human player already has a Fog in player.tscn
## (with watching_commander_id = -1, the default).
func _create_bot_fogs() -> void:
	for commander: Commander in commanders:
		if commander.id == 0 or not commander is Bot:
			continue
		# No mesh/material: fog is drawn by the terrain shader now (fog.gd hides its own plane),
		# so a bot's Fog node exists only to track that commander's exploration state.
		var fog: Fog = Fog.new()
		fog.watching_commander_id = commander.id
		fog.name = "Fog"
		commander.add_child(fog)
		fog.set_owner(self)


## The scenario's event host. Both commander ordnances and scripted triggers run
## their AbstractEvents through it (manager.add_child(event) + event.execute). An
## authored scenario includes one carrying its GlobalTriggers; a scene without
## scripted events (e.g. a skirmish) has none, so we create an empty host here —
## otherwise the bots' (and player's) ordnances would have nowhere to run and
## silently no-op. Idempotent: returns the existing node when the scene has one.
func _ensure_trigger_manager() -> ScenarioTriggerManager:
	var existing := get_node_or_null("ScenarioTriggerManager") as ScenarioTriggerManager
	if existing != null:
		return existing
	var manager := ScenarioTriggerManager.new()
	manager.name = "ScenarioTriggerManager"
	add_child(manager)
	manager.set_owner(self)
	return manager


## Create the bot debug overlay (one per session). It self-gates on the debug_info action
## and the bot-view toggle, so it's harmless to always add — it draws nothing until both
## gates open. Placed at the scenario origin so its world-space markers align.
func _create_bot_debug_overlay() -> void:
	var overlay := BotDebugOverlay.new()
	overlay.name = "BotDebugOverlay"
	overlay.scenario = self
	add_child(overlay)
	overlay.set_owner(self)


## Give a Bot its decision/tick layer, carrying its slot's difficulty. A PASSIVE bot
## still gets a brain (so the structure is uniform); its think loop is just disabled,
## leaving it inert. Other tiers are stored on the brain but behave identically for now.
func _attach_brain(bot: Bot, difficulty: PlayerSlot.Difficulty) -> void:
	var brain := BotBrain.new()
	brain.name = "BotBrain"
	brain.difficulty = difficulty
	brain.active = difficulty != PlayerSlot.Difficulty.PASSIVE
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
