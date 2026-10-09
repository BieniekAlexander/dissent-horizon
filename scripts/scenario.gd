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

## HOW THIS SCENARIO ENDS — gdd/systems/scenario-scripting/objectives-and-completion.md §Win
## conditions.
##   NONE      — it runs indefinitely; nothing implicit ever ends it.
##   MISSION   — the authored triggers decide (EventWinLose, objectives), plus the implicit
##               wipe-out loss for the local player below.
##   HEGEMONY  — a commander is removed from the match when it loses every command centre,
##               once it has placed one; the local player wins when every rival is gone.
## The default is MISSION so an authored scenario keeps the behaviour it was written against;
## every skirmish scene sets HEGEMONY.
enum WinCondition { NONE, MISSION, HEGEMONY }
@export var win_condition: WinCondition = WinCondition.MISSION

## HEGEMONY opens by showing every player every shelter: vision of this radius (world units)
## around each one, for SHELTER_REVEAL_SECONDS, after which the fog closes again and what
## remains is the remembered image of each shelter (the fog-of-war snapshot every seen fixture
## leaves). Shelter positions are meant to be known from the start while spawn points are not —
## gdd/systems/terrain-and-navigation/map-generation.md §Shelters. The radius takes in a 3x3
## shelter and its residents milling around it.
const SHELTER_REVEAL_RADIUS: float = 6.0
const SHELTER_REVEAL_SECONDS: float = 5.0
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

## A commander has just been removed from the match (HEGEMONY). The self-play harness reads
## the verdict off this and Scenario.is_eliminated.
signal commander_eliminated(a_commander_id: int)

## The match's event log: every summary and statistic of this match reads it, never the game.
## Null in the editor.
var match_log: MatchLog = null

## Per commander id: whether it has placed a command centre yet, which is what ARMS the
## HEGEMONY rule for it — before the drop lands every commander owns no centre, and that is
## the opening, not a defeat. Never cleared.
var _hegemony_armed: Dictionary = {}

## Where players' orders enter the simulation, at the start of each tick. Null in the editor
## and before _ready. gdd/systems/commands/recording-and-replay.md §The order stream.
var order_stream: OrderStream = null
## Records this match (or, in playback, checks it against its recording). Null in the editor
## and before _ready.
var recorder: ReplayRecorder = null
## A recording to PLAY BACK instead of a match to play: set before the scenario enters the tree,
## and it takes the seed and the orders from the recording. Null for a live match.
var replay_to_play: ReplayFile = null

## Every piece that has entered play this session, by spawn serial (Entity.spawn_serial) — how
## a recorded order names a piece. Kept for a piece's whole life, garrisoned (off the tree)
## included, which is why it is a lookup rather than a scan of the "piece" group; entries for
## freed pieces stay and read as null. UNTYPED values: a freed piece fails a typed lookup.
var _pieces_by_serial: Dictionary = {}
## The serial the next piece entering play takes; serials start at 1, so 0 means "none".
var _next_spawn_serial: int = 1

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
	# reproducible if it is seeded ahead of every consumer. A playback plays its recording's seed.
	if replay_to_play != null:
		rng_seed = int(replay_to_play.header.get("seed", rng_seed))
	seed_simulation()
	PurchaseTransaction.reset_ids()
	# The viewed fog is a static, so a spectator session or a replay's view switch would
	# otherwise carry into the next session: every session opens on its own player's view.
	Fog.active_commander_id = -1
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
	order_stream = OrderStream.new(self)
	add_child(order_stream)
	recorder = ReplayRecorder.new(self)
	add_child(recorder)
	if replay_to_play != null:
		recorder.verify_against(replay_to_play)
		order_stream.play_back(ReplayRecorder.orders_of(replay_to_play))
	else:
		recorder.begin()

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
			var bot: Bot = slot.commander as Bot
			bot.consider_structures = slot.consider_structures
			bot.consider_units = slot.consider_units
			_attach_brain(bot, slot.difficulty, slot.is_bot, _personality_config(slot))
			bot.get_node("BotBrain").disabled_jobs = slot.disabled_bot_jobs

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

	# Typed Entity (not Actor): commander/default_commander_id are Entity-level, and
	# the "piece" group holds features such as ExtractionSite as well as Actors.
	for entity: Entity in get_tree().get_nodes_in_group("piece"):
		entity.commander = commanders[entity.default_commander_id]

	# Extension point: subclasses (e.g. Skirmish) spawn each slot's faction-defined
	# opening force here. Deliberately AFTER the owner-assignment loop above —
	# dynamically-spawned entities default to commander_id 0, so spawning earlier
	# would let that loop reset them to the neutral commander. Map.add_entities sets
	# their owner directly, and being placed after the loop keeps it.
	# The event log starts before the opening force spawns, so nothing the match does is missed.
	_create_match_log()

	_spawn_initial_entities()

	# HEGEMONY: every player is shown every shelter for the opening seconds.
	_reveal_shelters_at_start()

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

	# A playback is watched, not played: its keys, its banner, and a HUD for looking.
	if is_playback():
		_create_replay_viewer()

	# In-world debug visualisation of the active bot's internals, one category at a time,
	# gated on the debug view + the bot-view toggle. See BotDebugOverlay.
	_create_bot_debug_overlay()

	if Engine.is_editor_hint():
		set_physics_process(false)


## In a HEGEMONY scenario, give every player commander a short look at every shelter on the map
## (SHELTER_REVEAL_RADIUS / _SECONDS). Nothing for any other win condition: a mission decides for
## itself what its player knows. Returns the vision sources spawned, for a test to inspect.
func _reveal_shelters_at_start() -> Array[Actor]:
	var spawned: Array[Actor] = []
	if win_condition != WinCondition.HEGEMONY or map == null:
		return spawned
	var points: Array[Vector2] = shelter_points(get_tree())
	for slot: PlayerSlot in player_slots:
		if slot.commander == null:
			continue
		for point: Vector2 in points:
			var source: Actor = EventRevealRegion.spawn_vision(
				slot.commander, map, point, SHELTER_REVEAL_RADIUS, SHELTER_REVEAL_SECONDS
			)
			if source != null:
				spawned.append(source)
	return spawned


## Where every shelter on the map stands, in world XZ: each fixture carrying a Shelter component.
static func shelter_points(a_tree: SceneTree) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for node: Node in a_tree.get_nodes_in_group("fixture"):
		var piece := node as Node3D
		if piece != null and piece.has_node("Shelter"):
			points.append(VU.in_xz(piece.global_position))
	return points


## A playback speed is the engine's global, so it would otherwise outlive this session. Leaving a
## match also keeps its recording, ended or not.
func _exit_tree() -> void:
	PlaybackSpeed.reset()
	if recorder != null:
		recorder.write_autosave()


## Debug mode just changed the simulation in a way no player order can: the recording ends here
## and is kept as an invalid replay. gdd/systems/commands/recording-and-replay.md §Debug mode.
func note_debug_change(a_reason: String) -> void:
	if recorder != null:
		recorder.invalidate(a_reason)


func _physics_process(_a_delta: float) -> void:
	tick += 1
	_check_eliminations()
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
## The implicit end this scenario's win_condition gives for free, polled every tick.
func _check_eliminations() -> void:
	match win_condition:
		WinCondition.MISSION:
			_check_player_eliminated()
		WinCondition.HEGEMONY:
			_check_hegemony()
		_:
			pass  # NONE: nothing implicit


## Whether commander `a_commander_id` has been removed from the match (HEGEMONY).
func is_eliminated(a_commander_id: int) -> bool:
	if a_commander_id < 1 or a_commander_id >= commanders.size():
		return false
	var commander: Commander = commanders[a_commander_id]
	return commander != null and commander.is_eliminated


## HEGEMONY: every non-neutral commander is judged, not only the local player, because a
## rival's removal is what the player's WIN is made of. A commander is armed the first tick
## it owns a command centre and eliminated the first armed tick it owns none; eliminating it
## frees its pieces (Commander.eliminate). The local player then loses when it is eliminated,
## and wins when it is armed and every rival is gone — a session with no rival never wins.
func _check_hegemony() -> void:
	if _game_over_seen:
		return
	for commander: Variant in commanders:
		var c: Commander = commander as Commander
		if c == null or c.id == 0 or c.is_eliminated:
			continue
		if c.owns_command_centre():
			_hegemony_armed[c.id] = true
		elif _hegemony_armed.get(c.id, false):
			c.eliminate()
			commander_eliminated.emit(c.id)
	var player: Commander = local_player()
	if player == null:
		_check_last_standing()
		return
	if player.is_eliminated:
		_on_game_over(false)
	elif _hegemony_armed.get(player.id, false) and _rivals() > 0 and _rivals_standing() == 0:
		_on_game_over(true)


## A spectator session's HEGEMONY end: once two or more commanders have deployed and only one
## is left standing, the match is over and it is the winner. Ending it records the verdict
## and shows the summary; it stops nothing, and the self-play harness still adjudicates.
func _check_last_standing() -> void:
	if _hegemony_armed.size() < 2:
		return
	var standing: Array = _standing_commanders()
	if standing.size() == 1:
		end_match((standing[0] as Commander).id)


## Non-neutral commanders not yet eliminated.
func _standing_commanders() -> Array:
	return commanders.filter(
		func(c: Variant) -> bool:
			return (
				c is Commander and (c as Commander).id != 0 and not (c as Commander).is_eliminated
			)
	)


## Non-neutral commanders other than the local player.
func _rivals() -> int:
	var player: Commander = local_player()
	var count: int = 0
	for commander: Variant in commanders:
		var c: Commander = commander as Commander
		if c != null and c.id != 0 and c != player:
			count += 1
	return count


func _rivals_standing() -> int:
	var player: Commander = local_player()
	var count: int = 0
	for commander: Variant in commanders:
		var c: Commander = commander as Commander
		if c != null and c.id != 0 and c != player and not c.is_eliminated:
			count += 1
	return count


## MISSION's implicit loss, for the local player only.
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


## Seed every generator the simulation draws from, from this scenario's `rng_seed`: `SU.rng`
## for gameplay, and Godot's GLOBAL generator, which authored `Expression`s draw from and which
## cannot be redirected (gdd/systems/ai/selfplay-harness.md §Determinism). Touches no node, so the
## rule can be tested on a bare instance.
func seed_simulation() -> void:
	SU.rng.seed = rng_seed
	seed(rng_seed ^ _GLOBAL_STREAM_SALT)


#endregion

#region Private helpers
## The key/fill sun pair a scenario gets when it authors no light of its own. Ambient light is
## not part of it: that is the project's default Environment, which applies wherever a scene
## has no WorldEnvironment. See gdd/systems/ux/aesthetics/lighting.md.
## The scenario HUD's pause menu; authored layout, instanced in _create_scenario_hud.
const PAUSE_MENU_SCENE: PackedScene = preload("res://scenes/menu/pause_menu.tscn")
const MATCH_SUMMARY_SCENE: PackedScene = preload("res://scenes/interface/match_summary.tscn")
## The end-of-match summary's canvas layer: above ScenarioDialogView's 10, below the pause
## menu's 20, so the way out of the scenario stays on top of it.
const MATCH_SUMMARY_LAYER: int = 15
## The scenario HUD's elapsed-time readout; authored layout, instanced in _create_scenario_hud.
const SCENARIO_TIMER_SCENE: PackedScene = preload("res://scenes/interface/scenario_timer.tscn")
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


## Where slot `a_index` (0-based) starts, as a replay's header records it: the start point's
## name and its XZ position, or empty when this scenario places its slots by authoring rather
## than at start points. Skirmish fills it. Informational: a playback re-derives the start from
## the scene, as the match did.
func slot_start_point(_a_index: int) -> Dictionary:
	return {}


## Whether this session plays a recording back rather than a match (replay_to_play).
func is_playback() -> bool:
	return replay_to_play != null


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
	if not missing.is_empty():
		var message: String = (
			(
				"%s: player slot(s) %s have no faction configured. Every slot must name one — "
				% [name, str(missing)]
			)
			+ "a commander's faction is scenario configuration and has no default."
		)
		push_error(message)
		assert(false, message)
	var unknown_jobs: Dictionary = _unknown_bot_job_slots()
	if not unknown_jobs.is_empty():
		var message: String = (
			"%s: player slot(s) %s switch off bot jobs that do not exist (BotBrain.JOB_NAMES)."
			% [name, str(unknown_jobs)]
		)
		push_error(message)
		assert(false, message)
	var unresolved: Dictionary = _unresolved_personality_slots()
	if not unresolved.is_empty():
		var message: String = (
			"%s: player slot(s) %s name a bot personality or override that does not resolve."
			% [name, str(unresolved)]
		)
		push_error(message)
		assert(false, message)


## Slot numbers (1-based commander ids) → the `disabled_bot_jobs` names no BotBrain job has.
## Pure, so it can be tested directly; _validate_player_slots does the reporting.
func _unknown_bot_job_slots() -> Dictionary:
	var unknown: Dictionary = {}
	for i: int in player_slots.size():
		var slot: PlayerSlot = player_slots[i]
		if slot == null:
			continue
		var names: Array = slot.disabled_bot_jobs.filter(
			func(job: StringName) -> bool: return not BotBrain.JOB_NAMES.has(job)
		)
		if not names.is_empty():
			unknown[i + 1] = names
	return unknown


## Slot numbers (1-based commander ids) → why their `personality` or `config_overrides`
## cannot be applied: an id the roster lacks, or a key that names no BotDifficulty field.
## Pure, so it can be tested directly; _validate_player_slots does the reporting.
func _unresolved_personality_slots() -> Dictionary:
	var unresolved: Dictionary = {}
	for i: int in player_slots.size():
		var slot: PlayerSlot = player_slots[i]
		if slot == null:
			continue
		var error: String = _personality_error(slot, BotDifficulty.new())
		if error != "":
			unresolved[i + 1] = error
	return unresolved


## Apply the slot's personality and overrides onto `a_config`; "" or the first failure.
func _personality_error(a_slot: PlayerSlot, a_config: BotDifficulty) -> String:
	if a_slot.personality != "":
		var error: String = bot_roster().apply(a_slot.personality, a_config)
		if error != "":
			return error
	return a_config.apply_overrides(a_slot.config_overrides)


## The parameters a slot's bot plays by when the slot names a personality or overrides —
## the tier's vector with those applied — or null when it names neither, so the brain keeps
## the tier's own config. Validation has already refused anything that cannot apply.
func _personality_config(a_slot: PlayerSlot) -> BotDifficulty:
	if a_slot.personality == "" and a_slot.config_overrides.is_empty():
		return null
	var config: BotDifficulty = BotDifficulty.for_tier(a_slot.difficulty)
	var error: String = _personality_error(a_slot, config)
	assert(error == "", error)
	return config


## The roster the slots' personalities name, loaded on first use. A test assigns
## `_loaded_bot_roster` a fixture instead.
var _loaded_bot_roster: BotRoster = null


func bot_roster() -> BotRoster:
	if _loaded_bot_roster == null:
		_loaded_bot_roster = BotRoster.load_default()
	return _loaded_bot_roster


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
## commander, plus a fog-toggle row so the spectator can switch perspectives and a picker
## for which category of the viewed bot's signals the debug overlay draws.
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

	# ── Bot debug overlay category (shown only while the debug view is up) ──
	var category_bar := BotDebugCategoryBar.new()
	category_bar.name = "BotDebugCategoryBar"
	vbox.add_child(category_bar)
	# ── Debug view fog: lifted, or as the viewed bot sees it (also only while the view is up) ──
	var debug_fog_row := DebugFogRow.new()
	debug_fog_row.name = "DebugFogRow"
	vbox.add_child(debug_fog_row)

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
		var refresh: Callable = _refresh_spectator_label.bind(label, commander)
		commander.resources_changed.connect(refresh)
		# The connection's object is this Scenario, not the label, so Godot does not drop it
		# when the label is freed — and a commander outlives its HUD (a harness frees the HUD;
		# a structure withdraws infrastructure on PREDELETE), so cut it as the label leaves.
		label.tree_exiting.connect(_disconnect_spectator_label.bind(commander, refresh))


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


## Untyped commander: it may already be freed by the time its label leaves the tree.
func _disconnect_spectator_label(a_commander: Variant, a_refresh: Callable) -> void:
	if not is_instance_valid(a_commander):
		return
	var commander: Commander = a_commander
	if commander.resources_changed.is_connected(a_refresh):
		commander.resources_changed.disconnect(a_refresh)


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
		# An omniscient slot (a decision simulation's) gets no Fog at all: Entity.is_visible_to
		# and Commander.has_vision_at answer true for a commander with none, which is the one
		# honest way to hand a bot the whole arena without touching the perception code.
		if _is_omniscient(commander):
			continue
		# No mesh/material: fog is drawn by the terrain shader now (fog.gd hides its own plane),
		# so a bot's Fog node exists only to track that commander's exploration state.
		var fog: Fog = Fog.new()
		fog.watching_commander_id = commander.id
		fog.name = "Fog"
		commander.add_child(fog)
		fog.set_owner(self)


## Whether `a_commander`'s slot asked for no fog (PlayerSlot.omniscient, a simulation lever).
func _is_omniscient(a_commander: Commander) -> bool:
	for slot: PlayerSlot in player_slots:
		if slot != null and slot.commander == a_commander:
			return slot.omniscient
	return false


## The scenario's event host. Both commander sanctions and scripted triggers run
## their AbstractEvents through it (manager.add_child(event) + event.execute). An
## authored scenario includes one carrying its GlobalTriggers; a scene without
## scripted events (e.g. a skirmish) has none, so we create an empty host here —
## otherwise the bots' (and player's) sanctions would have nowhere to run and
## silently no-op. Idempotent: returns the existing node when the scene has one.
## This scenario's trigger host, or null before _ready made it.
func trigger_manager() -> ScenarioTriggerManager:
	return get_node_or_null("ScenarioTriggerManager") as ScenarioTriggerManager


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

	# The elapsed-time readout: here and not in the player rig, so a spectator sees it too.
	var timer_layer := CanvasLayer.new()
	timer_layer.name = "ScenarioTimerLayer"
	add_child(timer_layer)
	var timer: ScenarioTimer = SCENARIO_TIMER_SCENE.instantiate()
	timer_layer.add_child(timer)
	timer.bind(self, a_event_manager.simulation_clock)

	# By group rather than by path, so the panel can be moved anywhere in the rig without this
	# needing to know where it ended up.
	for node: Node in get_tree().get_nodes_in_group(ObjectiveView.GROUP):
		(node as ObjectiveView).bind(a_event_manager)

	# The pause menu: here and not in the player rig, so a spectator can leave, and set playback
	# speed, as a player can.
	var pause_menu: PauseMenu = PAUSE_MENU_SCENE.instantiate()
	add_child(pause_menu)
	pause_menu.bind(a_event_manager)
	pause_menu.bind_match_log(match_log)


## The replay viewer: the keys and the banner a playback is watched through (ReplayViewer).
func _create_replay_viewer() -> void:
	var viewer := ReplayViewer.new()
	viewer.name = "ReplayViewer"
	add_child(viewer)
	viewer.bind(self, trigger_manager().simulation_clock)


## Start the match's event log (MatchLog). Not in the editor, which plays no match.
func _create_match_log() -> void:
	if Engine.is_editor_hint():
		return
	match_log = MatchLog.new()
	match_log.name = "MatchLog"
	add_child(match_log)
	match_log.begin(self)


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
##
## `a_config` is the slot's personality (see _personality_config), applied over the tier when
## given; null plays the tier alone.
func _attach_brain(
	a_bot: Bot,
	a_difficulty: PlayerSlot.Difficulty,
	a_is_active: bool,
	a_config: BotDifficulty = null
) -> void:
	var brain := BotBrain.new()
	brain.name = "BotBrain"
	brain.active = a_is_active
	brain.set_difficulty(a_difficulty)
	if a_config != null:
		brain.set_config(a_config)
	# Its own stream, from the match seed and its id: reproducible from the seed, and never
	# shared with the other bot or with the simulation's draws.
	brain.seed_randomness(rng_seed, a_bot.id)
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
		var entity := node as Actor
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
	if recorder != null:
		recorder.write_autosave()
	var player: Commander = local_player()
	if a_won:
		end_match(player.id if player != null else -1)
	else:
		var rivals: Array = _standing_commanders().filter(
			func(c: Variant) -> bool: return c != player
		)
		end_match((rivals[0] as Commander).id if rivals.size() == 1 else -1)
	# TODO: the rest of a win/lose screen — pausing, a way back to the menu. gdd/tasks.md T-080.


## End the match with `a_winner_id` the winner, or -1 for none: the event log records it and
## the summary is shown, whether or not the debug view is up. Once; a later call is ignored.
func end_match(a_winner_id: int) -> void:
	if match_log == null or match_log.is_ended():
		return
	match_log.end(a_winner_id)
	_show_match_summary(_match_summary_title(a_winner_id))


## The heading of the end-of-match summary: the verdict as the local player hears it, or the
## winner's name in a spectator session.
func _match_summary_title(a_winner_id: int) -> String:
	var player: Commander = local_player()
	if player != null:
		return "Victory" if a_winner_id == player.id else "Defeat"
	return "Commander %d wins" % a_winner_id if a_winner_id > 0 else "Match over"


func _show_match_summary(a_title: String) -> void:
	var layer := CanvasLayer.new()
	layer.name = "MatchSummaryLayer"
	layer.layer = MATCH_SUMMARY_LAYER
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(centre)
	var view: MatchSummaryView = MATCH_SUMMARY_SCENE.instantiate()
	view.is_closable = true
	centre.add_child(view)
	add_child(layer)
	view.present(match_log, a_title)
	view.closed.connect(layer.queue_free)
	# Save replay, on every end of a match — victory, defeat and a spectator's alike — unless
	# debug mode ended the recording, which would only be refused when played.
	if recorder != null and not recorder.is_invalid:
		var form := ReplaySaveForm.new()
		form.name = "ReplaySaveForm"
		view.add_footer(form)
		form.bind(recorder)


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


## Give `a_piece` the next spawn serial and remember it by that serial. Called once per piece,
## as it first enters the tree, so tree order (scene-placed pieces) and spawn order (everything
## later) fix the numbering, the same on every run of a seed.
## gdd/systems/commands/recording-and-replay.md §The order stream.
func register_piece(a_piece: Entity) -> int:
	var serial: int = _next_spawn_serial
	_next_spawn_serial += 1
	_pieces_by_serial[serial] = a_piece
	return serial


## The live piece with spawn serial `a_serial`, or null when none has it or it has been freed.
func piece_by_serial(a_serial: int) -> Entity:
	var piece: Variant = _pieces_by_serial.get(a_serial)
	return piece as Entity if is_instance_valid(piece) else null


## Switch `a_bot`'s brain on or off. Switching one ON rebuilds it from scratch, keeping its
## difficulty and the parameters it played by (its personality, if the slot named one): its
## claims, build plans and beliefs went stale while it was off.
func set_ai_control(a_bot: Bot, a_is_on: bool) -> void:
	var brain: BotBrain = a_bot.brain()
	if brain == null or brain.active == a_is_on:
		return
	note_debug_change("a bot was switched %s" % ("on" if a_is_on else "off"))
	brain.active = false
	if not a_is_on:
		return
	var difficulty: PlayerSlot.Difficulty = brain.difficulty
	var config: BotDifficulty = brain.config
	a_bot.remove_child(brain)
	brain.queue_free()
	_attach_brain(a_bot, difficulty, true, config)


## Set the difficulty tier of commander `a_commander_id`'s bot, mid-match. The tier's own
## vector replaces whatever the bot played by, a slot personality included: the debug menu is
## asking for the tier, not a retune of the personality.
func set_bot_difficulty(a_commander_id: int, a_tier: PlayerSlot.Difficulty) -> void:
	var bot: Bot = commander_by_id(a_commander_id) as Bot
	if bot != null and bot.brain() != null:
		note_debug_change("a bot's difficulty was changed")
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
