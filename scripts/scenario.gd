class_name Scenario
extends Node3D

## Emitted after the local player has become a different commander (see play_as). The HUD
## rig re-binds to it.
signal local_player_changed(a_commander: Commander)

#region Configuration
## The participants in this scenario, in commander-id order starting at 1 — the
## neutral world commander at id 0 is implicit and not a slot. Each slot builds one
## Commander (a Bot, or the human player.tscn rig) fielding its faction at its
## difficulty. A session with no human slot is a spectator session. Replaces the old
## commander_count / human_commander_id / passive_bot_ids trio.
@export var player_slots: Array[PlayerSlot] = []

## THE SESSION'S START SEED — the one number the whole simulation's pseudo-randomness is
## derived from, so the same scenario run twice produces the same match.
##
## Applied by seed_simulation() at the top of _ready, before any commander, entity or
## trigger exists, so nothing can draw before it lands.
##
## Named `rng_seed` rather than `seed` because `seed()` is a @GlobalScope function: a member
## called `seed` would shadow it, and seed_simulation() has to call it.
##
## A FIXED default is deliberate. Reproducibility is the point — a scenario that wants a
## different match authors a different number here, and a caller that wants a random one
## (a future skirmish menu, a batch of tuning runs) sets it before the node enters the tree,
## which is exactly what tools/selfplay/run_match.gd does.
@export var rng_seed: int = 0

## Whether this session may show debug information at all (see DebugMode). Off by default so a
## shipped scenario never offers it; a development scenario turns it on.
@export var debug_allowed: bool = false
#endregion

#region Properties
## PHYSICS TICKS since the session began. Was `frame`, which named neither its unit nor
## its dimension and collided with two other senses of the word in this project — the
## chassis `frame_type` and the renderer's frames. Seconds are had through TimeUtils.
var tick: int = 0

## Latches on the first game_over, so whichever end-of-session verdict lands first (an
## authored EventWinLose, every objective completing, or the implicit elimination loss
## below) is the one that stands.
var _game_over_seen: bool = false

## Arms the implicit elimination loss: set the first frame the local player owns anything,
## and never cleared. Until then "owns nothing" is the OPENING state, not a defeat —
## Skirmish._spawn_initial_entities defers its opening force to NavManager.navmesh_ready, so
## every commander genuinely owns nothing for the first frames of a match, and an unarmed
## check would lose the game before it started.
##
## It also makes the rule self-disabling where it should be: a spectator session, or a
## scripted scenario whose player is handed their first unit by a trigger, simply never arms
## it, so no opt-out flag is needed.
var _player_has_deployed: bool = false

## Arms the SECOND half of the elimination rule — no structures and no production is a
## defeat — and it needs its own latch rather than sharing `_player_has_deployed`. A mission
## that opens with units and asks the player to build their base owns no structure for its
## first minutes; arming the base rule off "owns anything" would lose that scenario on frame
## one. Set the first frame the player has a base to lose, and never cleared, so a player who
## never had one is only ever judged by the older owns-nothing rule. A slot still holding its
## command-centre drop (Deployment) is that case: before the drop it loses only by losing
## every unit.
var _player_has_had_base: bool = false

## Built in _ready() from player_slots: id 0 = neutral Commander, then one Commander
## per slot (ids 1..N) — the human rig (scenes/player.tscn) for a non-bot slot, a Bot
## otherwise. Indexed by commander id (entities resolve owners via commanders[id]).
var commanders: Array = []

## THE MAP THIS SCENARIO PLAYS ON. Every scenario has one, as its child named `Map` — that is
## the contract a generated map scene is built to: its root IS the Map, so instancing it here
## satisfies this (see tools/map_generation).
@onready var map: Map = $Map
#endregion


#region Lifecycle
func _ready() -> void:
	# FIRST, before anything that could draw: the simulation's pseudo-randomness is only
	# reproducible if it is seeded ahead of every consumer.
	seed_simulation()
	_create_debug_mode()
	_ensure_lighting()
	if map == null:
		push_error(
			(
				"%s has no Map child: a scenario plays on a map, and every system here " % name
				+ "resolves it as $Map. Instance a map scene under this node."
			)
		)
		return

	_build_commanders()

	var players_node = Node3D.new()
	players_node.name = "Players"
	add_child(players_node, true)
	players_node.set_owner(self)

	for commander in commanders:
		players_node.add_child(commander)
		commander.set_owner(self)

	# Every slot's commander is a Bot and gets a brain, configured with its slot's difficulty
	# and switched off for a human slot. Done in a second pass (after the commanders are in
	# the tree) so the brain attaches to a live bot.
	for slot: PlayerSlot in player_slots:
		if slot.commander is Bot:
			_attach_brain(slot.commander as Bot, slot.difficulty, slot.is_bot)

	# Create a Fog node for each bot commander so it tracks its own exploration.
	# The human player already has a Fog in player.tscn (watching_commander_id = -1).
	_create_bot_fogs()

	var has_view_camera: bool = false
	for commander: Commander in commanders:  # setting camera
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

	# Typed Entity (not Commandable): commander/default_commander_id are Entity-level, and
	# the "piece" group holds features such as ExtractionSite as well as Actors.
	for entity: Entity in get_tree().get_nodes_in_group("piece"):
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
	event_manager.scenario_completed.connect(_on_scenario_completed)

	# Scenario-driven HUD: acknowledge pop-ups and the objective checklist. Owned here rather
	# than by the player rig because they belong to the SCENARIO — a spectator or test session
	# has no RTSController but can still be running a scripted sequence.
	_create_scenario_hud(event_manager)

	# In-world debug visualisation of the active bot's internals (scout coverage, …),
	# gated on hold-Spacebar + the bot-view toggle. See BotDebugOverlay.
	_create_bot_debug_overlay()

	if Engine.is_editor_hint():
		set_physics_process(false)


func _physics_process(_a_delta: float) -> void:
	tick += 1
	_check_player_eliminated()
	# $Map.nav_region.bake_navigation_mesh(false)


#endregion


#region Elimination
## The implicit loss every scenario gets for free: owning no units and no structures is a
## defeat — and so, since the self-play corpus made the cost of the narrower rule visible, is
## being left with no structures and nothing in production while a straggler survives (see
## Commander.has_production_base). Both come with no trigger to author and no row in the
## objective checklist. Deliberately not
## a FAILURE-scoped GlobalTrigger — it applies to every scenario including plain skirmishes,
## it needs no authoring, and telling the player "don't lose everything" is noise.
##
## POLLED rather than driven off the ON_DEATH bus, for two reasons. Entity._on_death runs
## BEFORE its queue_free() takes effect, so a count taken there is off by one; and a
## commander can lose its last entity without any death at all — a capture puts a unit into
## an enemy garrison, and Garrison orphans occupants out of the tree.
## A death-only hook would silently miss both. The poll costs one filtered get_children() on
## a single commander, and stops entirely once a verdict has landed.
func _check_player_eliminated() -> void:
	if _game_over_seen:
		return
	var player: Commander = local_player()
	if player == null:
		return  # spectator session: nobody to eliminate
	var in_play: bool = player.has_anything_in_play()
	var has_base: bool = player.has_production_base()
	_player_has_deployed = _player_has_deployed or in_play
	_player_has_had_base = _player_has_had_base or has_base
	# TWO rules, ORed, and the second is the one added with the harness's verdict (see
	# Commander.has_production_base): losing everything is a defeat, and so is losing every
	# structure and every purchase while units survive. Each is armed by its own latch, so a
	# scenario that never gives the player a base is never judged by the base rule.
	if (_player_has_deployed and not in_play) or (_player_has_had_base and not has_base):
		_on_game_over(false)


## The local human's Commander, or null in a spectator session (no human slot, so
## RTSController.PLAYER_COMMANDER_ID stayed at its 0 default).
func local_player() -> Commander:
	var pid: int = RTSController.PLAYER_COMMANDER_ID
	if pid < 1 or pid >= commanders.size():
		return null
	return commanders[pid]


#endregion

#region Determinism
## Salt mixed into the seed handed to Godot's GLOBAL generator, so the two streams below
## start from different places rather than running in lockstep off one number. The value is
## the golden-ratio constant used as a bit-mixer everywhere; nothing depends on which
## constant it is, only that it is fixed.
const _GLOBAL_STREAM_SALT: int = 0x9E3779B9


## Seed every generator the simulation draws from, from this scenario's `rng_seed`.
##
## TWO generators, and the split is forced rather than chosen:
##
##   * `SU.rng` is the gameplay generator — hitscan spread, Wander, the unit-placement
##     scatter, a mortar barrage's muzzle offsets. Everything that can be routed is.
##   * Godot's GLOBAL generator is what `Expression` gives an authored scenario expression
##     ("15 + randi_range(0, 10)"), and it cannot be redirected — see ScenarioExpression.
##     Seeding it is the only way that draw becomes replayable.
##
## Public and callable on a bare instance so the rule can be tested without booting a map:
## it touches no node and no scene state.
func seed_simulation() -> void:
	SU.rng.seed = rng_seed
	seed(rng_seed ^ _GLOBAL_STREAM_SALT)


#endregion

#region Private helpers
## The key/fill sun pair a scenario gets when it authors no light of its own. Ambient light is
## not part of it: that is the project's default Environment, which applies wherever a scene
## has no WorldEnvironment. See gdd/systems/ux/aesthetics/lighting.md.
const DEFAULT_LIGHTING_SCENE: String = "res://scenes/environment/default_lighting.tscn"


## Add the default lighting rig unless the scenario (or its map) already carries a sun. A
## scenario that lights itself keeps exactly what it authored.
func _ensure_lighting() -> void:
	if not find_children("*", "DirectionalLight3D", true, false).is_empty():
		return
	var rig: Node = (load(DEFAULT_LIGHTING_SCENE) as PackedScene).instantiate()
	add_child(rig)


## Hook for subclasses to spawn each player slot's opening force at runtime. Base
## Scenario authors its starting entities directly in the scene tree, so this is a
## no-op; Skirmish overrides it to build each slot's structure + units from its
## faction. Called from _ready (see the call site for ordering constraints).
func _spawn_initial_entities() -> void:
	pass


## Whether each slot opens with units and a command-centre drop rather than a base — see
## Deployment. Off here because most scenarios place their bases by authoring; Skirmish turns
## it on, and every Skirmish deploys this way.
func uses_deferred_deployment() -> bool:
	return false


## Slot numbers (1-based commander ids) whose faction is missing — either the slot
## itself is an empty array row, or it names no faction. Pure and side-effect free so
## it can be tested directly; _validate_player_slots does the reporting.
func _missing_faction_slots() -> Array[int]:
	var missing: Array[int] = []
	for i: int in player_slots.size():
		var slot: PlayerSlot = player_slots[i]
		if slot == null or slot.faction == null:
			missing.append(i + 1)
	return missing


## Every player slot MUST name a faction: it is the single source of truth for what
## that commander fields (starting units, sanction grid, and so the command centre it drops), and
## there is no default left to fall back on. Reports every offending slot at once so
## an author fixes them in one pass rather than one boot per slot.
##
## push_error AND assert, deliberately. `assert()` is compiled out of release export
## templates, so on its own it would let a misconfigured scenario ship silently to
## players — the exact failure mode of an editor-only check. push_error survives into
## the exported build's log; the assert additionally halts a debug/editor run at the
## point of the mistake instead of letting a factionless commander boot.
func _validate_player_slots() -> void:
	var missing: Array[int] = _missing_faction_slots()
	if missing.is_empty():
		return
	var message: String = (
		(
			"%s: player slot(s) %s have no faction configured. Every slot must name one — "
			% [name, str(missing)]
		)
		+ "a commander's faction is scenario configuration and has no default."
	)
	push_error(message)
	assert(false, message)


## Construct the commander list from player_slots. id 0 is always the neutral world
## commander; each slot then builds commander id 1..N — the human rig
## (scenes/player.tscn) for a non-bot slot, a Bot otherwise — and the slot's faction
## is propagated onto it. Publishes the local human's id to RTSController so
## fog/minimap/commandable adopt the right viewpoint (PLAYER_COMMANDER_ID < 1 means
## a spectator session with no local human).
func _build_commanders() -> void:
	_validate_player_slots()
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
			# The rig's fog tracks THIS commander for good, rather than whoever the player
			# is: debug mode can swap the player (play_as), and every commander keeps its
			# own exploration.
			(c.get_node("Fog") as Fog).watching_commander_id = id
			if RTSController.PLAYER_COMMANDER_ID < 1:
				RTSController.PLAYER_COMMANDER_ID = id
		c.id = id
		# Apply the slot's starting resources. Set before the commander enters the
		# tree; Commander's resource fields are plain (not @onready) so this sticks. A slot
		# that deploys by drop is handed them when its command centre lands instead.
		if uses_deferred_deployment():
			c.deployment = Deployment.new(c, slot.starting_energy, slot.starting_dominion)
		else:
			c.energy = slot.starting_energy
			c.dominion = slot.starting_dominion
		# Propagate the slot's faction onto its commander. Commander._ready instances
		# it for the starting units + sanctions. Unconditional: the slot is the ONLY
		# source of a commander's faction (_validate_player_slots guarantees one), so
		# there is nothing to preserve by skipping a null.
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


func _wire_spectator_fog_buttons(a_fog_row: HBoxContainer) -> void:
	var no_fog_btn: Button = a_fog_row.get_node("FogBtn_NoFog")
	no_fog_btn.pressed.connect(
		func() -> void:
			Fog.active_commander_id = -2
			_refresh_spectator_fog_buttons(a_fog_row)
	)
	for commander: Commander in commanders:
		if commander.id == 0 or not commander is Bot:
			continue
		var btn: Button = a_fog_row.get_node("FogBtn_%d" % commander.id)
		var cid: int = commander.id
		btn.pressed.connect(
			func() -> void:
				Fog.active_commander_id = cid
				_refresh_spectator_fog_buttons(a_fog_row)
		)


func _refresh_spectator_fog_buttons(a_fog_row: HBoxContainer) -> void:
	var active_id: int = Fog.active_commander_id
	var no_fog_btn: Button = a_fog_row.get_node_or_null("FogBtn_NoFog") as Button
	if no_fog_btn != null:
		no_fog_btn.disabled = (active_id == -2)
	for commander: Commander in commanders:
		if commander.id == 0 or not commander is Bot:
			continue
		var btn: Button = a_fog_row.get_node_or_null("FogBtn_%d" % commander.id) as Button
		if btn != null:
			btn.disabled = (active_id == commander.id)


## Repaint one commander's spectator resource panel.
func _refresh_spectator_label(a_label: RichTextLabel, a_commander: Commander) -> void:
	a_label.text = (
		"Commander %d:\n\tenergy: %s\n\tinfrastructure: %s\n\tdominion: %s"
		% [
			a_commander.id,
			a_commander.energy,
			"%s/%s" % [a_commander.infrastructure_required, a_commander.infrastructure_provided],
			a_commander.dominion,
		]
	)


## Set the initial active fog for spectator sessions: default to the first bot's
## perspective so entity visibility is immediately meaningful.
func _init_spectator_fog() -> void:
	for commander: Commander in commanders:
		if commander.id != 0 and commander is Bot:
			Fog.active_commander_id = commander.id
			return


## Create and attach a Fog node for each commander that has none, so every commander
## tracks its own exploration state. The human rig brings its own (player.tscn).
func _create_bot_fogs() -> void:
	for commander: Commander in commanders:
		if commander.id == 0 or commander.has_node("Fog"):
			continue
		# No mesh/material: fog is drawn by the terrain shader now (fog.gd hides its own plane),
		# so a bot's Fog node exists only to track that commander's exploration state.
		var fog: Fog = Fog.new()
		fog.watching_commander_id = commander.id
		fog.name = "Fog"
		commander.add_child(fog)
		fog.set_owner(self)


## The scenario's event host. Both commander sanctions and scripted triggers run
## their AbstractEvents through it (manager.add_child(event) + event.execute). An
## authored scenario includes one carrying its GlobalTriggers; a scene without
## scripted events (e.g. a skirmish) has none, so we create an empty host here —
## otherwise the bots' (and player's) sanctions would have nowhere to run and
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


## Point the scenario HUD at the trigger manager.
##
## Two different kinds of thing, wired differently on purpose:
##
##  * The acknowledge-dialog window is CREATED here. It is scenario-level — a session with no
##    player rig at all (spectator, a headless test scenario) can still be running scripted
##    beats that raise dialogs — so it can't depend on the HUD existing.
##  * The objective checklist is AUTHORED, instanced into the player HUD
##    (scenes/player.tscn → Controller → ObjectiveView) where it can be positioned and
##    restyled in the editor. This only finds and binds it. A session without a player rig
##    therefore has no checklist, which is the right answer: nobody is reading it.
##
## Both are inert until a trigger raises a dialog or the scenario declares objectives.
func _create_scenario_hud(a_event_manager: ScenarioTriggerManager) -> void:
	var dialog_view := ScenarioDialogView.new()
	dialog_view.name = "ScenarioDialogView"
	add_child(dialog_view)
	dialog_view.set_owner(self)
	dialog_view.bind(a_event_manager)
	# The help book is authored per scenario (a HelpBook child listing DialogPage scenes).
	# A scenario without one simply has no help button.
	dialog_view.bind_help_book(get_node_or_null("HelpBook") as HelpBook)

	# By group rather than by path, so the panel can be moved anywhere in the rig without this
	# needing to know where it ended up.
	for node: Node in get_tree().get_nodes_in_group(ObjectiveView.GROUP):
		(node as ObjectiveView).bind(a_event_manager)

	# Same group lookup for the pause menu, which needs the clock to hold the world while it is
	# up. It ships in the player rig, so a spectator or headless session simply has none — and
	# has no player to want one.
	for node: Node in get_tree().get_nodes_in_group(PauseMenu.GROUP):
		(node as PauseMenu).bind(a_event_manager)


## The node that receives the debug toggle, and the session's debug permission with it. First
## in _ready, so every HUD piece built after it reads this session's permission.
func _create_debug_mode() -> void:
	DebugMode.configure(debug_allowed)
	var debug_mode := DebugMode.new()
	debug_mode.name = "DebugMode"
	add_child(debug_mode)


## Create the bot debug overlay (one per session). It self-gates on DebugMode.is_active()
## and the bot-view toggle, so it's harmless to always add — it draws nothing until both
## gates open. Placed at the scenario origin so its world-space markers align.
func _create_bot_debug_overlay() -> void:
	var overlay := BotDebugOverlay.new()
	overlay.name = "BotDebugOverlay"
	overlay.scenario = self
	add_child(overlay)
	overlay.set_owner(self)


## Give a Bot its decision/tick layer, carrying its slot's difficulty — which selects the
## PARAMETERS it plays by rather than switching branches (see BotDifficulty).
##
## EVERY tier thinks, PASSIVE included. It used to be left inert, and that is not what the
## tier is for: passive means "minimally active, and never attacks", so it builds, trains and
## defends itself while `config.may_attack` keeps it home. An inert commander is scenery.
##
## A human slot's brain is attached too, switched off, so debug mode can hand the slot to it.
func _attach_brain(a_bot: Bot, a_difficulty: PlayerSlot.Difficulty, a_is_active: bool) -> void:
	var brain := BotBrain.new()
	brain.name = "BotBrain"
	brain.active = a_is_active
	brain.set_difficulty(a_difficulty)
	a_bot.add_child(brain)
	brain.set_owner(self)


## Move the player's camera so the view centers on the centroid of the player's
## buildings at game start.  If the player has no buildings, centers on the
## centroid of the player's units instead.  If the player owns neither, the
## camera is left where it is.
func _center_player_camera_on_starting_entities() -> void:
	# Spectator (or otherwise no human rig): there is no player camera to center.
	var player: Commander = local_player()
	if player == null:
		return
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
func _player_owned_positions_xz(a_player: Commander, a_group: String) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for node: Node in get_tree().get_nodes_in_group(a_group):
		var entity := node as Commandable
		if entity != null and entity.commander == a_player:
			result.append(VU.in_xz(entity.global_position))
	return result


## Called when a ScenarioTriggerManager child emits message_requested.
## Connect the HUD notification UI here once one exists.
func _on_scenario_message(a_text: String) -> void:
	print("[Scenario] ", a_text)


## Called when a ScenarioTriggerManager child emits game_over.
func _on_game_over(a_won: bool) -> void:
	if _game_over_seen:
		return
	_game_over_seen = true
	print("[Scenario] Game over — player %s" % ("wins" if a_won else "loses"))
	# TODO: show a win/lose screen and pause, or return to the menu. gdd/deferred.md §2.9.


## Called when every PRIMARY trigger has fired — the scenario's declared work is finished, so
## the session is over and the player has won it.
##
## Routed through _on_game_over rather than duplicating its handling, and _game_over_seen
## keeps whichever arrives first from being overridden: a scenario can ALSO carry an authored
## EventWinLose (s1's Victory trigger does), and a mission whose objectives complete moments
## after a scripted loss must not overwrite the loss with a win.
func _on_scenario_completed() -> void:
	print("[Scenario] All objectives complete.")
	_on_game_over(true)


#endregion


#region Debug control
## The Scenario `a_node` belongs to: its nearest Scenario ancestor, else the running scene
## when that is one. Null outside a scenario (a bare HUD in a test).
static func of(a_node: Node) -> Scenario:
	var node: Node = a_node
	while node != null:
		if node is Scenario:
			return node as Scenario
		node = node.get_parent()
	return a_node.get_tree().current_scene as Scenario if a_node.is_inside_tree() else null


## Switch `a_bot`'s brain on or off. Switching one ON rebuilds it from scratch, keeping its
## difficulty: its claims, build plans and beliefs went stale while it was off.
func set_ai_control(a_bot: Bot, a_is_on: bool) -> void:
	var brain: BotBrain = a_bot.brain()
	if brain == null or brain.active == a_is_on:
		return
	brain.active = false
	if not a_is_on:
		return
	var difficulty: PlayerSlot.Difficulty = brain.difficulty
	a_bot.remove_child(brain)
	brain.queue_free()
	_attach_brain(a_bot, difficulty, true)


## Set the difficulty tier of commander `a_commander_id`'s bot, mid-match.
func set_bot_difficulty(a_commander_id: int, a_tier: PlayerSlot.Difficulty) -> void:
	var bot: Bot = commander_by_id(a_commander_id) as Bot
	if bot != null and bot.brain() != null:
		bot.brain().set_difficulty(a_tier)


## The commander with id `a_commander_id`, or null when there is none.
func commander_by_id(a_commander_id: int) -> Commander:
	if a_commander_id < 0 or a_commander_id >= commanders.size():
		return null
	return commanders[a_commander_id]


## Make the local player commander `a_commander_id` (1..N). The slot left behind is handed
## to its bot and the one taken over has its bot put down. False when there is nothing to
## swap to, or the player already is that commander.
func play_as(a_commander_id: int) -> bool:
	var target: Bot = commander_by_id(a_commander_id) as Bot
	var current: Commander = local_player()
	if a_commander_id < 1 or target == null or current == null or target == current:
		return false
	if current is Bot:
		set_ai_control(current as Bot, true)
	set_ai_control(target, false)
	RTSController.PLAYER_COMMANDER_ID = a_commander_id
	local_player_changed.emit(target)
	return true
#endregion
