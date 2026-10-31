extends Node3D

## ONE HEADLESS SELF-PLAY MATCH: two bots, one map, one seed, one JSON result.
##
## The training harness the bot roadmap asks for (gdd/systems/ai/bot-roadmap.md §The training
## harness) needs two things before it can measure anything — a seeded simulation, and a way
## to run a match with parameters that are NOT the shipped tiers. This is the second: it
## boots a skirmish as a SPECTATOR session (both slots forced to bots), overrides each
## brain's live `BotDifficulty` from a config file, runs the match to a verdict, and writes
## what happened as JSON.
##
## **It never edits the tier table.** `BotDifficulty.for_tier` stays as authored and is the
## STARTING POINT for each slot; the config's `config` block overrides fields on the live
## object afterwards. An experiment that mutated the tiers would be measuring a build rather
## than a parameter set, and could not be run two-at-a-time.
##
## Run:
##   godot --headless --path . --fixed-fps 30 tools/selfplay/run_match.tscn -- \
##       config=/abs/path/match.json out=/abs/path/result.json
##
## `--fixed-fps 30` is what makes it fast: it detaches the main loop from wall time, so one
## iteration is one physics tick and the match runs at whatever the CPU can do (~15-25x real
## time on a modest machine) instead of at 30 ticks per wall second. It is NOT optional in a
## batch — without it a 20-minute match takes 20 minutes.
##
## Schemas, termination rules and known limits: gdd/systems/ai/selfplay-harness.md

#region Defaults
## The match these defaults describe, when the config names nothing: a 20-simulated-minute
## Colonial mirror on the shipped skirmish map.
const DEFAULT_SCENARIO: String = "res://scenes/scenarios/skirmish.tscn"
const DEFAULT_FACTION: String = "res://scenes/factions/colonial.tscn"
const DEFAULT_MAX_SIMULATED_SECONDS: float = 1200.0
## A hung match must not eat a batch's budget. Wall-clock, deliberately: the thing it guards
## against (a deadlocked navmesh, an infinite await) is exactly the thing that stops the tick
## counter from advancing, so a tick-based cap cannot catch it.
const DEFAULT_MAX_WALL_SECONDS: float = 900.0
const DEFAULT_SAMPLE_INTERVAL_SECONDS: float = 10.0
## Physics frames to let the scenario boot before the verdict logic starts looking. The
## opening force is deferred to NavManager.navmesh_ready, so every commander genuinely owns
## nothing for the first frames — see Scenario._player_has_deployed for the same problem.
const BOOT_GRACE_TICKS: int = 120
## Seeds tried, from `map_seed` upward, before a generated-map match gives up.
const MAP_SEED_ATTEMPTS: int = 20
#endregion

## Counts every error the match raises; see match_error_log.gd.
const MatchErrorLog: GDScript = preload("res://tools/selfplay/match_error_log.gd")

#region Arguments
var _config_path: String = ""
var _out_path: String = ""
#endregion

#region State
var _config: Dictionary = {}
var _scenario: Scenario
## Per slot index: whether that commander has ever owned anything (arms its elimination).
var _deployed: Array[bool] = []
## Per slot index: whether that commander has ever held a BASE — a structure or a purchase
## on its production queue. Arms the second half of the defeat rule, and is latched
## separately for the same reason Scenario latches it separately: a slot that has not yet
## been given one must not be judged by it.
var _based: Array[bool] = []
## Per slot index: the tick it first owned something, -1 until then.
var _deployed_tick: Array[int] = []
var _samples: Array = []
## Per slot: piece id -> {instance id -> true} for every piece seen in any sample. What the
## slot PRODUCED over the match, which no single sample's counts can give (a unit born and
## killed between two samples is still counted if a sample caught it; one that was not is
## missed, so this is a floor at the sample interval, not a census).
var _instances_seen: Array = []
var _wall_start_usec: int = 0
## Registered first thing in _ready, so it sees every error the match itself raises.
var _errors: Logger = MatchErrorLog.new()
## The generated map's seed when the config asked for one, -1 for the scenario's own map.
var _played_map_seed: int = -1
## `replay_path` in the config: where the match's recording is written when it ends, as a KEPT
## replay (ReplayRecorder.write_kept) the start screen lists. A generated map is carried as a
## skirmish recipe in the header (SkirmishLauncher), which is what rebuilds it on playback, so a
## config the recipe cannot express — swapped starts, a symmetric map, a per-slot override —
## is refused up front rather than recorded as a replay that drifts. Empty: no recording.
var _replay_path: String = ""
#endregion

## The project setting that puts RVO avoidance on worker threads. Forced OFF for a harness
## process — see _force_single_threaded_avoidance.
const AVOIDANCE_THREADS_SETTING: String = (
	"navigation/avoidance/thread_model/" + "avoidance_use_multiple_threads"
)


## Take avoidance off its worker threads FOR THIS PROCESS. `project.godot` now sets the same
## thing for every run, so this only guards a checkout whose project settings were changed:
## multi-threaded avoidance plays a different match in every process
## (selfplay-harness.md §Determinism).
func _force_single_threaded_avoidance() -> void:
	ProjectSettings.set_setting(AVOIDANCE_THREADS_SETTING, false)


func _ready() -> void:
	OS.add_logger(_errors)
	_force_single_threaded_avoidance()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("config="):
			_config_path = arg.substr("config=".length())
		elif arg.begins_with("out="):
			_out_path = arg.substr("out=".length())
	_run.call_deferred()


func _run() -> void:
	_wall_start_usec = Time.get_ticks_usec()
	if not _load_config():
		_fail("could not read config: %s" % _config_path)
		return

	var playback_path: String = str(_config.get("replay_to_play", ""))
	if playback_path != "":
		var playback_error: String = _prepare_playback(playback_path)
		if playback_error != "":
			_fail(playback_error)
			return
	else:
		var match_error: String = _prepare_match()
		if match_error != "":
			_fail(match_error)
			return

	add_child(_scenario)
	if playback_path == "":
		# The brains exist now (Scenario._ready attaches one per Bot) and have not thought yet —
		# BotBrain builds its managers on the first think — so this is the moment to hand each
		# one its parameters. A playback's bots re-derive theirs from the recording's seed.
		var inject_error: String = _inject_configs()
		if inject_error != "":
			_fail(inject_error)
			return
	_strip_spectator_hud()

	_deployed.resize(_scenario.player_slots.size())
	_based.resize(_scenario.player_slots.size())
	_deployed_tick.resize(_scenario.player_slots.size())
	_deployed_tick.fill(-1)

	await _run_match()


## The scenario the config describes, built and not yet in the tree, or the reason it could not
## be. BEFORE the node enters the tree: Scenario._ready seeds the simulation from rng_seed and
## builds one commander per slot, so both have to be settled first.
func _prepare_match() -> String:
	var scenario_path: String = _config.get("scenario", DEFAULT_SCENARIO)
	var packed := load(scenario_path) as PackedScene
	if packed == null:
		return "could not load scenario: %s" % scenario_path
	_scenario = packed.instantiate() as Scenario
	if _scenario == null:
		return "scene root is not a Scenario: %s" % scenario_path
	_scenario.rng_seed = int(_config.get("seed", 0))
	var slot_error: String = _configure_slots()
	if slot_error != "":
		return slot_error
	var map_error: String = _apply_generated_map()
	if map_error != "":
		return map_error
	var swap_error: String = _apply_start_point_swap()
	if swap_error != "":
		return swap_error
	return _prepare_recording()


## `replay_to_play` in the config: play the recording at `a_path` back instead of a match, as
## the start screen would (ReplayLibrary.prepare_playback), so the result reports the first tick
## whose digest differed from the recording's — the harness's check that a recording still
## reproduces its match. A playback takes no slot configuration: its bots are the recording's.
func _prepare_playback(a_path: String) -> String:
	var built: Dictionary = ReplayLibrary.prepare_playback(a_path)
	if built.has("refusal"):
		return "replay_to_play: %s" % built["refusal"]
	_scenario = built["scenario"] as Scenario
	_played_map_seed = int(_scenario.skirmish_recipe.get("map_seed", -1))
	return ""


## Arm the recording the config asks for (`replay_path`): a generated map goes into the header
## as the skirmish recipe that regenerates it. Nothing to arm without the key; an authored map is
## rebuilt from the header's scene path and needs no recipe.
func _prepare_recording() -> String:
	_replay_path = str(_config.get("replay_path", ""))
	if _replay_path == "":
		return ""
	if bool(_config.get("swap_start_points", false)) or bool(_config.get("map_symmetric", false)):
		return "replay_path: a skirmish recipe carries neither swapped starts nor a symmetric map"
	for wanted: Variant in _config.get("slots", []):
		for key: String in [
			"config", "combat_model", "starting_energy", "starting_dominion", "disabled_jobs"
		]:
			if (wanted as Dictionary).has(key):
				return "replay_path: a skirmish recipe cannot carry a slot's %s" % key
	if _played_map_seed < 0:
		return ""
	var players: Array = []
	for slot: PlayerSlot in _scenario.player_slots:
		(
			players
			. append(
				{
					"faction": slot.faction.resource_path,
					"team": slot.alliance,
					"is_bot": true,
					"difficulty": int(slot.difficulty),
				}
			)
		)
	_scenario.skirmish_recipe = {
		"version": SkirmishLauncher.RECIPE_VERSION,
		"players": players,
		"map_seed": _played_map_seed,
		"rng_seed": _scenario.rng_seed,
	}
	return ""


#region Configuration
func _load_config() -> bool:
	if _config_path.is_empty() or not FileAccess.file_exists(_config_path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_config_path))
	if not (parsed is Dictionary):
		return false
	_config = parsed as Dictionary
	return true


## Force every slot to a bot of the configured faction, replacing the scene's authored slots
## with copies so the .tscn's own sub-resources are never mutated (they are shared per load,
## and a run that edited them would leave the scene changed for anything else in the process).
##
## The human slot is what makes skirmish.tscn a PLAYABLE map rather than a test fixture, so
## overriding it here — instead of authoring a second scene — is what keeps the harness
## measuring the same map the player plays.
func _configure_slots() -> String:
	var slot_configs: Array = _config.get("slots", [])
	if slot_configs.size() != _scenario.player_slots.size():
		return (
			"config names %d slots; %s has %d"
			% [
				slot_configs.size(),
				_config.get("scenario", DEFAULT_SCENARIO),
				_scenario.player_slots.size()
			]
		)
	var faction_path: String = _config.get("faction", DEFAULT_FACTION)
	var faction := load(faction_path) as PackedScene
	if faction == null:
		return "could not load faction: %s" % faction_path

	var slots: Array[PlayerSlot] = []
	for i: int in _scenario.player_slots.size():
		var slot: PlayerSlot = _scenario.player_slots[i].duplicate()
		slot.is_bot = true
		slot.faction = faction
		var wanted: Dictionary = slot_configs[i]
		var tier: Variant = _tier_from_name(wanted.get("difficulty", "MEDIUM"))
		if tier == null:
			return (
				"slot %d: unknown difficulty %s (expected one of %s)"
				% [i, wanted.get("difficulty"), ", ".join(PlayerSlot.Difficulty.keys())]
			)
		slot.difficulty = tier
		if wanted.has("starting_energy"):
			slot.starting_energy = int(wanted["starting_energy"])
		if wanted.has("starting_dominion"):
			slot.starting_dominion = int(wanted["starting_dominion"])
		# BotBrain jobs this slot leaves unscheduled (PlayerSlot.disabled_bot_jobs), for an A/B
		# of a job against its absence; an unknown name fails the boot as it does for a scene.
		if wanted.has("disabled_jobs"):
			var names: Array[StringName] = []
			for name: Variant in wanted["disabled_jobs"]:
				names.append(StringName(str(name)))
			slot.disabled_bot_jobs = names
		slots.append(slot)
	_scenario.player_slots = slots
	return ""


func _tier_from_name(a_name: Variant) -> Variant:
	var key: String = str(a_name).to_upper()
	if not PlayerSlot.Difficulty.keys().has(key):
		return null
	return PlayerSlot.Difficulty[key]


## The single think interval BotDifficulty had before each kind of decision got its own period
## (2026-09-26), in physics ticks. The archived configs and generators under results/ still
## name it, so it is read as "every period set to this many ticks" rather than refused.
const RETIRED_THINK_INTERVAL_KEY: String = "think_interval_ticks"


## Override each brain's live BotDifficulty from its slot's `config` block.
##
## The field set is read off a fresh BotDifficulty rather than listed here, so a new knob is
## searchable the moment it exists — the harness is not a second place to maintain the
## parameter list. An UNKNOWN key is a hard failure: a search whose parameter was silently
## ignored reports a result for an experiment it did not run.
func _inject_configs() -> String:
	var slot_configs: Array = _config.get("slots", [])
	for i: int in _scenario.player_slots.size():
		var overrides: Dictionary = (
			((slot_configs[i] as Dictionary).get("config", {}) as Dictionary).duplicate()
		)
		var brain: BotBrain = _brain_for_slot(i)
		if brain == null:
			return "slot %d has no BotBrain to configure" % i
		# `combat_model`: a path to a trainer export this slot values purchases by, instead of
		# the shipped resources/bots/combat_model.json — so a candidate model can be played
		# against the shipped one in the same match (macro-learning.md §1).
		var model_path: String = str((slot_configs[i] as Dictionary).get("combat_model", ""))
		if model_path != "":
			var model: CombatModel = CombatModel.from_file(model_path)
			if model == null:
				return "slot %d: no combat model at %s" % [i, model_path]
			brain.bot.combat_model = model
		if overrides.is_empty():
			continue
		var config: BotDifficulty = BotDifficulty.for_tier(brain.difficulty)
		if overrides.has(RETIRED_THINK_INTERVAL_KEY):
			# One think interval for everything, as the archived studies meant it.
			config.set_all_periods(
				float(overrides[RETIRED_THINK_INTERVAL_KEY]) / TimeUtils.ticks_per_second()
			)
			overrides.erase(RETIRED_THINK_INTERVAL_KEY)
		var error: String = config.apply_overrides(overrides)
		if error != "":
			return "slot %d: %s" % [i, error]
		brain.set_config(config)
	return ""


func _brain_for_slot(a_index: int) -> BotBrain:
	var commander: Commander = _scenario.player_slots[a_index].commander
	if commander == null:
		return null
	return commander.get_node_or_null("BotBrain") as BotBrain


func _all_nodes(a_root: Node) -> Array[Node]:
	var found: Array[Node] = [a_root]
	for child: Node in a_root.get_children():
		found.append_array(_all_nodes(child))
	return found


## The spectator HUD repaints a BBCode label on every resource change, for nobody: this is
## headless and there is no watcher. Freeing it is worth ~15% of the run and changes no
## simulation state.
func _strip_spectator_hud() -> void:
	var hud: Node = _scenario.get_node_or_null("SpectatorHUD")
	if hud != null:
		hud.free()


## MEASUREMENT INFRASTRUCTURE, not a rule of the game: exchange which start point each slot
## deploys at, when the config says `"swap_start_points": true`.
##
## WHY IT EXISTS. A slot index and a start POSITION are confounded in every match this
## harness has ever run: Skirmish._start_points sorts the markers by name and hands the
## first to slot 0, so slot 0 is always the same corner of the map. Deploy order, commander
## id and think order track the slot index too, so a corpus in which one slot wins more
## cannot say whether the map, or the engine's ordering, produced it. Running the same seeds
## with the assignment exchanged separates them: a bias that FOLLOWS THE POSITION implicates
## the map, one that stays with the slot index does not.
##
## It swaps the markers' TRANSFORMS rather than their names, so nothing that resolves a node
## by path or name sees a different scene — the only thing that changes is where each marker
## is. Done before the scenario enters the tree (Skirmish._spawn_initial_entities reads them
## from _ready onward), and on the instantiated copy, so the authored .tscn is untouched.
##
## Two slots is all this reverses. A three-slot scenario would need a permutation rather than
## a flag, and nothing has needed one.
## `map_seed` in the config replaces the scenario's own Map with one MapGenerator makes from
## that seed — a skirmish on a random map, as the menu would start one. A rejected seed is
## retried at the next seed, and the seed actually played is recorded in the result.
## `map_symmetric: true` beside it mirrors the map through its centre — the training control
## of map-generation.md §Symmetric maps.
func _apply_generated_map() -> String:
	if not _config.has("map_seed"):
		return ""
	var writer := GeneratedMapWriter.new()
	var params: MapGenerationParams = writer.default_params(_scenario.player_slots.size())
	params.symmetric = bool(_config.get("map_symmetric", false))
	var first_seed: int = int(_config["map_seed"])
	var generated: GeneratedMap = null
	for offset: int in MAP_SEED_ATTEMPTS:
		generated = MapGenerator.generate(params, first_seed + offset)
		if generated.is_valid():
			break
	if not generated.is_valid():
		return "map_seed %d: no valid map in %d seeds" % [first_seed, MAP_SEED_ATTEMPTS]
	_played_map_seed = generated.generation_seed
	var terrain_path: String = "user://selfplay_map_%d_terrain.tres" % _played_map_seed
	var map: Map = writer.build_map(generated, terrain_path)
	if map == null:
		return "map_seed %d: could not write terrain to %s" % [_played_map_seed, terrain_path]
	var old_map: Node = _scenario.get_node_or_null(GeneratedMapWriter.MAP_NODE_NAME)
	if old_map != null:
		_scenario.remove_child(old_map)
		old_map.free()
	GeneratedMapWriter.adopt(_scenario, map)
	return ""


func _apply_start_point_swap() -> String:
	if not bool(_config.get("swap_start_points", false)):
		return ""
	var points: Array[Node3D] = _start_point_markers()
	if points.size() < 2:
		return "swap_start_points: found %d start-point markers, need at least 2" % points.size()
	if points.size() > 2:
		return "swap_start_points: %d markers is a permutation, not a swap" % points.size()
	var first: Transform3D = points[0].transform
	points[0].transform = points[1].transform
	points[1].transform = first
	return ""


## The scenario's start-point markers, in the SAME order Skirmish._start_points resolves
## them — by String name, not StringName, because StringName's < is hash order. Walks the
## instantiated tree rather than asking the SceneTree for the group, because the scenario is
## not in the tree yet.
func _start_point_markers() -> Array[Node3D]:
	var points: Array[Node3D] = []
	for node: Node in _all_nodes(_scenario):
		var spatial := node as Node3D
		if spatial != null and spatial.is_in_group(Skirmish.START_POINT_GROUP):
			points.append(spatial)
	points.sort_custom(func(a: Node3D, b: Node3D) -> bool: return String(a.name) < String(b.name))
	return points


#endregion


#region The match
func _run_match() -> void:
	var max_sim_seconds: float = float(
		_config.get("max_simulated_seconds", DEFAULT_MAX_SIMULATED_SECONDS)
	)
	var max_wall_seconds: float = float(_config.get("max_wall_seconds", DEFAULT_MAX_WALL_SECONDS))
	var sample_interval: float = float(
		_config.get("sample_interval_seconds", DEFAULT_SAMPLE_INTERVAL_SECONDS)
	)
	var sample_every_ticks: int = maxi(1, TimeUtils.ticks_from_seconds(sample_interval))
	var max_ticks: int = TimeUtils.ticks_from_seconds(max_sim_seconds)
	if _scenario.replay_to_play != null:
		max_ticks = mini(max_ticks, _scenario.replay_to_play.length_ticks())

	var outcome: String = "stalemate"
	var winner: int = -1
	var next_sample_tick: int = 0

	while true:
		await get_tree().physics_frame
		var tick: int = _scenario.tick

		if tick >= next_sample_tick:
			_samples.append(_sample(tick))
			_dump_state(tick)
			next_sample_tick = tick + sample_every_ticks

		_arm_deployment(tick)
		if tick > BOOT_GRACE_TICKS:
			var eliminated: Array[int] = _eliminated_slots()
			if eliminated.size() >= _scenario.player_slots.size():
				outcome = "mutual_elimination"
				break
			if eliminated.size() > 0:
				outcome = "elimination"
				winner = _surviving_slot(eliminated)
				break

		if tick >= max_ticks:
			outcome = "stalemate"
			break
		if _wall_seconds() >= max_wall_seconds:
			outcome = "wall_clock_cap"
			break

	_samples.append(_sample(_scenario.tick))
	_emit(outcome, winner)


## Latch each slot the first tick it owns anything. Until then "owns nothing" is the OPENING
## state and not a defeat — the same rule Scenario._player_has_deployed encodes for the human
## player, restated here because a SPECTATOR session never reaches it:
## Scenario._check_player_eliminated returns early when local_player() is null, so nothing in
## the engine adjudicates a bot-versus-bot match. That is the harness's job.
func _arm_deployment(a_tick: int) -> void:
	for i: int in _scenario.player_slots.size():
		var commander: Commander = _scenario.player_slots[i].commander
		if commander == null:
			continue
		if not _deployed[i] and commander.has_anything_in_play():
			_deployed[i] = true
			_deployed_tick[i] = a_tick
		if not _based[i] and commander.has_production_base():
			_based[i] = true


## WHEN A SIDE IS BEATEN, and it is the same rule the shipped game adjudicates for the human
## player (Scenario._check_player_eliminated): owning nothing at all, OR holding no structure
## and no purchase on the production queue. See Commander.has_production_base.
##
## The second clause is what this harness was getting wrong. Before it, elimination required
## owning NOTHING, so a slot reduced to zero structures and one surviving unit rode the cap
## and the match was filed as a stalemate — 23 of the 61 stalemates in the 2026-09-05 corpus,
## the largest single distortion in the measurements. The verdict is what the training
## objective is computed from, so a wrong verdict is a wrong gradient.
func _eliminated_slots() -> Array[int]:
	var out: Array[int] = []
	# Under HEGEMONY the scenario itself removes a commander (Scenario._check_hegemony runs in
	# a spectator session too); the harness only reads the verdict. The rules below are the
	# MISSION-era adjudication, kept for a scenario authored without a win condition.
	if _scenario.win_condition == Scenario.WinCondition.HEGEMONY:
		for i: int in _scenario.player_slots.size():
			var commander: Commander = _scenario.player_slots[i].commander
			if commander != null and commander.is_eliminated:
				out.append(i)
		return out
	for i: int in _scenario.player_slots.size():
		var commander: Commander = _scenario.player_slots[i].commander
		if _deployed[i] and (commander == null or not commander.has_anything_in_play()):
			out.append(i)
		elif _based[i] and (commander == null or not commander.has_production_base()):
			out.append(i)
	return out


func _surviving_slot(a_eliminated: Array[int]) -> int:
	for i: int in _scenario.player_slots.size():
		if not a_eliminated.has(i):
			return i
	return -1


#endregion


#region Measurement
## One sample of both sides, at `a_tick`. Everything here is a COUNT or an ENERGY VALUE,
## because energy-equivalent is the currency the bot's own decisions are priced in
## (bot-roadmap.md §The currency is ENERGY-EQUIVALENT) — a series in the same units as the
## decision is a series that can be read against it.
func _sample(a_tick: int) -> Dictionary:
	var slots: Array = []
	for i: int in _scenario.player_slots.size():
		var slot: Dictionary = _slot_sample(_scenario.player_slots[i].commander)
		slot["brain"] = _brain_sample(_brain_for_slot(i))
		slot["jobs"] = _job_totals(_brain_for_slot(i))
		_note_instances(i, _scenario.player_slots[i].commander)
		slots.append(slot)
	var sample: Dictionary = {
		"tick": a_tick,
		"simulated_seconds": TimeUtils.seconds_from_ticks(a_tick),
		# Wall time so far, so two samples give the wall cost per tick of the window between.
		"wall_seconds": _wall_seconds(),
		"digest": SimulationDigest.of(_scenario),
		"slots": slots,
	}
	if bool(_config.get("nav_probe", false)) and slots.size() >= 2:
		sample["nav"] = _nav_probe()
	return sample


## THE NAVIGATION PROBE (`nav_probe: true`): can the first two slots' homes reach each other
## at all — the SMALL-class path on every navmesh layer, and a flood fill over the terrain
## grid's passable cells, which says whether a failed path is the map's (no passable route)
## or the mesh's (a route the cells allow that the mesh does not carry).
func _nav_probe() -> Dictionary:
	var brains: Array = [_brain_for_slot(0), _brain_for_slot(1)]
	for brain: BotBrain in brains:
		if brain == null or brain.bot == null or brain.bot.map == null:
			return {}
	var map: Map = (brains[0] as BotBrain).bot.map
	var from: Vector3 = (brains[0] as BotBrain).bot.home_centroid()
	var to: Vector3 = (brains[1] as BotBrain).bot.home_centroid()
	if from == Vector3.ZERO or to == Vector3.ZERO or map.nav_region == null:
		return {}
	var nav_map: RID = map.nav_region.get_navigation_map()
	var layers: Dictionary = {}
	for layer: int in [1, 2, 4, 1 << 30]:
		var path: PackedVector3Array = NavigationServer3D.map_get_path(
			nav_map, from, to, true, layer
		)
		var gap: float = -1.0
		if not path.is_empty():
			gap = VU.in_xz(path[path.size() - 1]).distance_to(VU.in_xz(to))
		layers[str(layer)] = {"points": path.size(), "end_gap": snappedf(gap, 0.1)}
	# The same query with the polygon budget lifted: Godot's A* stops after
	# path_search_max_polygons (4096 by default) and returns the path to the nearest polygon it
	# reached, which on a one-quad-per-cell mesh is a partial path for a long walk.
	var params := NavigationPathQueryParameters3D.new()
	params.map = nav_map
	params.start_position = from
	params.target_position = to
	params.path_search_max_polygons = 0
	var result := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(params, result)
	var unlimited: PackedVector3Array = result.path
	layers["unlimited"] = {
		"points": unlimited.size(),
		"end_gap":
		(
			snappedf(VU.in_xz(unlimited[unlimited.size() - 1]).distance_to(VU.in_xz(to)), 0.1)
			if not unlimited.is_empty()
			else -1.0
		),
	}
	return {
		"from": _xz(from),
		"to": _xz(to),
		"layers": layers,
		"cells_connect": _cells_connect(map, from, to),
		"broken_links": _broken_links(map, nav_map, from, to),
	}


## Walk the cell route the flood fill found and test the navmesh between each consecutive pair
## of cell centres: a pair the cells join and the mesh does not is where the mesh is cut.
static func _broken_links(a_map: Map, a_nav_map: RID, a_from: Vector3, a_to: Vector3) -> Array:
	var route: Array = _cell_route(a_map, a_from, a_to)
	var broken: Array = []
	for i: int in range(route.size() - 1):
		var a: Vector2i = route[i]
		var b: Vector2i = route[i + 1]
		var wa: Vector3 = a_map.grid_to_world(a)
		var wb: Vector3 = a_map.grid_to_world(b)
		var path: PackedVector3Array = NavigationServer3D.map_get_path(a_nav_map, wa, wb, true)
		var gap: float = INF
		if not path.is_empty():
			gap = VU.in_xz(path[path.size() - 1]).distance_to(VU.in_xz(wb))
		if gap > 0.6:
			(
				broken
				. append(
					{
						"a": [a.x, a.y],
						"b": [b.x, b.y],
						"a_xz": _xz(wa),
						"b_xz": _xz(wb),
						"gap": snappedf(gap, 0.1) if gap != INF else -1.0,
						"h_a": snappedf(a_map.terrain_height_at(VU.in_xz(wa)), 0.01),
						"h_b": snappedf(a_map.terrain_height_at(VU.in_xz(wb)), 0.01),
						"a_passable": a_map.terrain_grid.is_passable(a),
						"b_passable": a_map.terrain_grid.is_passable(b),
						"chunk_a":
						[a.x / NavManager.CHUNK_SIZE_CELLS, a.y / NavManager.CHUNK_SIZE_CELLS],
						"chunk_b":
						[b.x / NavManager.CHUNK_SIZE_CELLS, b.y / NavManager.CHUNK_SIZE_CELLS],
					}
				)
			)
			if broken.size() >= 6:
				break
	return broken


## The 4-connected passable cell route from `a_from` to `a_to` the flood fill finds, or [].
static func _cell_route(a_map: Map, a_from: Vector3, a_to: Vector3) -> Array:
	var grid: TerrainGrid = a_map.terrain_grid
	var start: Variant = _nearest_passable(grid, a_map.world_to_grid(VU.in_xz(a_from)))
	var goal: Variant = _nearest_passable(grid, a_map.world_to_grid(VU.in_xz(a_to)))
	if start == null or goal == null:
		return []
	var parent: Dictionary = {start: null}
	var queue: Array = [start]
	var head: int = 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		if cell == goal:
			break
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if parent.has(next) or not grid.is_passable(next):
				continue
			parent[next] = cell
			queue.append(next)
	if not parent.has(goal):
		return []
	var route: Array = []
	var walk: Variant = goal
	while walk != null:
		route.push_front(walk)
		walk = parent[walk]
	return route


## Breadth-first over 4-connected passable cells from the cell nearest `a_from` to the one
## nearest `a_to` (each snapped to its nearest passable cell within a few rings).
static func _cells_connect(a_map: Map, a_from: Vector3, a_to: Vector3) -> Dictionary:
	var grid: TerrainGrid = a_map.terrain_grid
	var start: Variant = _nearest_passable(grid, a_map.world_to_grid(VU.in_xz(a_from)))
	var goal: Variant = _nearest_passable(grid, a_map.world_to_grid(VU.in_xz(a_to)))
	if start == null or goal == null:
		return {"connected": false, "reason": "no passable cell near an end"}
	var seen: Dictionary = {start: true}
	var queue: Array = [start]
	var head: int = 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		if cell == goal:
			return {
				"connected": true,
				"visited": seen.size(),
				"start": [start.x, start.y],
				"goal": [goal.x, goal.y]
			}
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if seen.has(next) or not grid.is_passable(next):
				continue
			seen[next] = true
			queue.append(next)
	return {
		"connected": false,
		"visited": seen.size(),
		"start": [start.x, start.y],
		"goal": [goal.x, goal.y]
	}


static func _nearest_passable(a_grid: TerrainGrid, a_cell: Vector2i) -> Variant:
	for ring: int in 8:
		for dx: int in range(-ring, ring + 1):
			for dz: int in range(-ring, ring + 1):
				var cell: Vector2i = a_cell + Vector2i(dx, dz)
				if a_grid.is_passable(cell):
					return cell
	return null


func _note_instances(a_slot: int, a_commander: Commander) -> void:
	while _instances_seen.size() <= a_slot:
		_instances_seen.append({})
	if a_commander == null:
		return
	var seen: Dictionary = _instances_seen[a_slot]
	for child: Node in a_commander.get_children():
		var entity := child as Actor
		if entity == null or entity.is_queued_for_deletion():
			continue
		var by_id: Dictionary = seen.get(String(entity.id), {})
		by_id[entity.get_instance_id()] = true
		seen[String(entity.id)] = by_id


## Distinct pieces of each id slot `a_slot` fielded over the match (see _instances_seen).
func _produced_by_id(a_slot: int) -> Dictionary:
	var out: Dictionary = {}
	if a_slot < _instances_seen.size():
		for id: String in _instances_seen[a_slot]:
			out[id] = (_instances_seen[a_slot][id] as Dictionary).size()
	return out


func _slot_sample(a_commander: Commander) -> Dictionary:
	if a_commander == null:
		return {}
	var units: Array = []
	var structures: Array = []
	var extractors: int = 0
	var income_structures: int = 0
	for child: Node in a_commander.get_children():
		var entity := child as Actor
		if entity == null or entity.is_queued_for_deletion():
			continue
		if entity.has_node("Fixture"):
			structures.append(entity)
			if entity.has_node("EnergyExtractor"):
				income_structures += 1
				if entity.is_built:
					extractors += 1
		else:
			units.append(entity)
	return {
		"energy": a_commander.energy,
		"dominion": a_commander.dominion,
		"army_energy_value": _army_energy_value(a_commander, units),
		"unit_count": units.size(),
		"structure_count": structures.size(),
		"extractor_count": extractors,
		# BUILT and BUILDING alike. `extractor_count` is an INCOME index (only a finished
		# extractor extracts), but the opening question is about when the bot COMMITS to income,
		# and a commitment is visible the moment the site is claimed — which is also what
		# BotEconomy._owned_income_structure_count counts against income_structure_target.
		"income_structure_count": income_structures,
		# How many owned units are of a UTILITY type — the series
		# BotProduction._utility_demand_for is answerable against. Only a Bot can classify a
		# type (it needs the build previews), so a non-bot slot reports -1 rather than 0, which
		# would read as a real measurement of none.
		"utility_unit_count": _utility_unit_count(a_commander, units),
		# WHAT the slot owns, by piece id: the instrument for "the bots only make infantry" and
		# "the war factory is rarely built", which counts alone cannot show.
		"structures_by_id": _count_by_id(structures),
		# Units in a garrison are off the tree and absent from every count above; this is
		# where they went.
		"bunkered_units": _bunkered_count(structures),
		"units_by_id": _count_by_id(units),
	}


## Owned units whose type is a utility type (Bot.unit_is_utility), or -1 when the commander
## is not a Bot and cannot be asked.
func _utility_unit_count(a_commander: Commander, a_units: Array) -> int:
	var bot := a_commander as Bot
	if bot == null:
		return -1
	var count: int = 0
	for u: Actor in a_units:
		if bot.unit_is_utility(u.id):
			count += 1
	return count


## What the brain was THINKING at this sample, beside what it owned.
##
## Six numbers, and they are the ones a hysteresis hunt needs: a posture that flips between
## consecutive samples, a scout count that climbs and collapses, an attack objective that
## appears and vanishes are all oscillations you cannot see in an economy series. Set
## `sample_interval_seconds` near the think cadence (0.5) to look for them; leave it at 10 to
## read the match.
##
## Reads the managers directly (`_military`, `get_scout()`) because there is no public
## posture accessor beyond `current_posture()`, and because a HARNESS reading a bot's private
## state is the right side of the actuator rule: it observes, it never issues.
## THE PROFILE: what each of the brain's jobs has cost since the match began — microseconds,
## work units and runs, summed by the scheduler — so a sample series says which job's share
## grows as the match does. Empty when the brain has no scheduler yet.
func _job_totals(a_brain: BotBrain) -> Dictionary:
	if a_brain == null:
		return {}
	var scheduler: BotScheduler = get_tree().get_first_node_in_group(BotScheduler.GROUP)
	if scheduler == null:
		return {}
	var out: Dictionary = {}
	for job: BotJob in scheduler.jobs_of(a_brain):
		out[String(job.name)] = {"usec": job.total_usec, "units": job.total_units, "runs": job.runs}
	return out


func _brain_sample(a_brain: BotBrain) -> Dictionary:
	if a_brain == null or a_brain.bot == null:
		return {}
	var bot: Bot = a_brain.bot
	var military: BotMilitary = a_brain._military
	var scout: BotScout = a_brain.get_scout()
	var momentum: BotMomentum = a_brain.get_momentum()
	var posture: BotPosture = a_brain.get_posture()
	var income: BotIncome = a_brain.get_income()
	# Exactly the test BotMilitary._objective_for(ATTACK) makes, and it must stay exactly that
	# test: an ATTACK posture with no answer here is silently demoted to MASS, so a bot that
	# has not FOUND the enemy cannot attack it however large its army grows. Reading the live
	# scene here (as this did while the objective was omniscient) would report a committed bot
	# that is in fact massing at home.
	var has_target: bool = (
		bot.nearest_believed_enemy_structure_position() != null
		or bot.nearest_believed_enemy_unit_position(bot.base_centroid()) != null
	)
	var sample: Dictionary = {
		"posture":
		BotMilitary.Posture.keys()[military.current_posture()] if military != null else "",
		"has_attack_objective": has_target,
		"believed_enemy_army_value": bot.believed_enemy_army_value(),
		# Alongside the belief's VALUE (units only), the count of believed enemy STRUCTURES —
		# which is what the fog-limited attack objective actually turns on. Without it a sample
		# cannot distinguish "marching on their base" from "walking to where a scout was seen",
		# and those are the two things `has_attack_objective` collapses together.
		"believed_enemy_structures":
		bot.blackboard.believed_structures().size() if bot.blackboard != null else 0,
		"scout_observed_fraction": scout.observed_fraction() if scout != null else 0.0,
		"scouts_out": (scout._scouts as Array).size() if scout != null else 0,
		"momentum_loss_rate": momentum.loss_rate() if momentum != null else 0.0,
		# The posture layer: the held dials (0.5 is neutral), and the economy signals the
		# commitment dial reads — own income and the fog-limited enemy estimate, energy/s.
		"dials": posture.dials() if posture != null else {},
		"income_rate": income.own_rate() if income != null else 0.0,
		"enemy_income_estimate": income.enemy_rate_estimate() if income != null else 0.0,
		"idle_units": bot.get_idle_units().size(),
		# The staging instrument: a release shows as the reserve dropping to 0 while the wave
		# grows by the same count in one sample. The trickle shows as a reserve that never
		# exceeds 0 (gdd/systems/ai/squads-and-relations.md §What started it).
		# The objective the army would actually be sent to — null when the military has no
		# ACTIONABLE belief and demotes to MASS, which `has_attack_objective` (unfiltered,
		# above) cannot tell apart from an army on the march.
		"attack_objective":
		(
			str(military._objective_for(BotMilitary.Posture.ATTACK))
			if military != null and military._objective_for(BotMilitary.Posture.ATTACK) != null
			else ""
		),
		"wave_units": military.wave_size() if military != null else 0,
		"reserve_units": military.reserve_size() if military != null else 0,
		# The attention throttle: orders in hand (negative in debt, null unlimited) and the
		# actions issued so far — their slope is the bot's realised orders per second.
		"attention_balance":
		null if a_brain.attention.is_unlimited() else a_brain.attention.balance(),
		"actions_issued":
		a_brain.get_actuator().actions_issued if a_brain.get_actuator() != null else 0,
		# Where the attention went: orders issued so far, by job.
		"attention_spent_by_job": a_brain.attention_spent_by_job.duplicate(),
		# Why a producer stands idle with energy banked: how many producers are idle, what the
		# savings goal is holding, and what each producible type's unmet need is.
		"producers": bot.get_production_structures().size(),
		"idle_producers": bot.get_idle_production_structures().size(),
		"savings_goal": str(bot.savings.goal()),
		"savings_claim": bot.savings.claim_against(&""),
		"producible_needs": _producible_needs(bot),
	}
	if bool(_config.get("sample_detail", false)):
		sample["detail"] = _detail_sample(a_brain)
	return sample


## THE DIAGNOSTIC DETAIL (`sample_detail: true`), off by default because it is large: every
## believed enemy structure with the verdict of each filter the attack objective applies to it,
## the military's wave and abandonment state, the economy's construction jobs, spots and
## savings proposals, and the scouts out. It is what a stalemate is read from when the summary
## fields say only that the army stood at home (bot-engagement-fixes.md §An unanswerable threat).
func _detail_sample(a_brain: BotBrain) -> Dictionary:
	var bot: Bot = a_brain.bot
	var military: BotMilitary = a_brain._military
	var economy: BotEconomy = a_brain.get_economy()
	var scout: BotScout = a_brain.get_scout()
	var beliefs: Array = []
	if bot.blackboard != null and military != null:
		var army: Array = military._combat_units(bot.get_units())
		var origin: Vector3 = military._home_anchor_position()
		for entry: CommanderBlackboard.Entry in bot.blackboard.believed_structures():
			var remembered: Variant = entry.entity
			(
				beliefs
				. append(
					{
						"type": str(entry.type),
						"serial": entry.serial,
						"at": _xz(entry.last_known_location),
						"last_seen": entry.last_seen_time,
						"in_view": bot.blackboard.is_in_view(entry.serial),
						"alive":
						is_instance_valid(remembered) and (remembered as Node).is_inside_tree(),
						"can_damage": Bot.any_unit_can_damage(army, entry.entity),
						"abandoned": military._is_abandoned(entry.last_known_location),
						"reachable":
						bot.is_reachable(
							origin, entry.last_known_location, BotMilitary.REACH_TOLERANCE
						),
						"path": _path_detail(bot, origin, entry.last_known_location),
					}
				)
			)
	var units: Array = []
	if bot.blackboard != null:
		for entry: CommanderBlackboard.Entry in bot.blackboard.believed_units():
			units.append({"type": str(entry.type), "at": _xz(entry.last_known_location)})
	var detail: Dictionary = {"believed_structures": beliefs, "believed_units": units}
	if military != null:
		var state: Dictionary = military.debug_state()
		var objective: Variant = state["objective_entity"]
		var abandoned: Array = []
		for entry: Dictionary in state["abandoned_objectives"]:
			abandoned.append({"at": _xz(entry["position"]), "until": entry["until"]})
		detail["military"] = {
			"wave_active": state["wave_active"],
			"wave_value": state["wave_value"],
			"regroup_left": state["regroup_left"],
			"on_objective": state["on_objective"],
			"enemy_estimate": state["enemy_estimate"],
			"objective_type": str((objective as Entity).id) if is_instance_valid(objective) else "",
			"abandoned": abandoned,
			"home": _xz(military._home_anchor_position()),
		}
	if economy != null:
		var jobs: Array = []
		for unit: Actor in bot.get_units():
			if not BotEconomy._is_constructing(unit):
				continue
			var command: MoveCommand = unit.current_command()
			var kind: String = ""
			if command.message != null and command.message.tool != null:
				kind = str(command.message.tool.type)
			(
				jobs
				. append(
					{
						"builder": str(unit.id),
						"type": kind,
						"at": _xz(command.message.position) if command.message != null else [],
						"since": economy._job_started.get(unit.identity_key(), -1.0),
					}
				)
			)
		var spots: Dictionary = economy.debug_spots()
		detail["economy"] = {
			"jobs": jobs,
			"abandoned_spots": (spots["abandoned"] as Array).map(_xz),
			"contested_spots": (spots["contested"] as Array).size(),
			"proposals": bot.savings.proposals(),
			"spot_search": str(economy._spot_search.get("type", "")),
		}
	if scout != null:
		detail["scouts"] = (scout._scouts as Array).filter(is_instance_valid).map(
			func(u: Actor) -> String: return str(u.id)
		)
	var deployment: BotDeployment = a_brain._deployment
	if deployment != null:
		detail["deployment"] = {
			"pending": deployment.is_pending(),
			"best_xz":
			[deployment._best_xz.x, deployment._best_xz.y] if deployment._best_xz != null else null,
			"best_cost": deployment._best_cost,
			"spent": bot.deployment == null or bot.deployment.is_spent(),
		}
	var owned: Array = []
	for unit: Actor in bot.get_units():
		var command: Variant = unit.current_command() if unit.has_command() else null
		(
			owned
			. append(
				{
					"id": str(unit.id),
					"at": _xz(unit.global_position),
					"command": command.get_script().get_global_name() if command != null else "",
					"claim":
					str(a_brain.claims.owner_of(unit)) if a_brain.claims.is_claimed(unit) else "",
				}
			)
		)
	detail["units"] = owned
	return detail


static func _xz(a_position: Vector3) -> Array:
	return [snappedf(a_position.x, 0.1), snappedf(a_position.z, 0.1)]


## Why a belief is or is not reachable: the SMALL-class path from `a_from`, where it ends and how
## far from the target that is, the closest navmesh point to the target, and the target's cell.
static func _path_detail(a_bot: Bot, a_from: Vector3, a_to: Vector3) -> Dictionary:
	if a_bot.map == null or a_bot.map.nav_region == null:
		return {}
	var nav_map: RID = a_bot.map.nav_region.get_navigation_map()
	var path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, a_from, a_to, true)
	var closest: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, a_to)
	var cell: Vector2i = a_bot.map.world_to_grid(VU.in_xz(a_to))
	var grid: TerrainGrid = a_bot.map.terrain_grid
	var out: Dictionary = {
		"points": path.size(),
		"closest_xz": _xz(closest),
		"closest_gap": snappedf(VU.in_xz(closest).distance_to(VU.in_xz(a_to)), 0.1),
		"cell_passable": grid.is_passable(cell),
		"cell_blocked": grid.is_blocked(cell),
		"from_height": snappedf(a_bot.map.terrain_height_at(VU.in_xz(a_from)), 0.1),
		"to_height": snappedf(a_bot.map.terrain_height_at(VU.in_xz(a_to)), 0.1),
	}
	if not path.is_empty():
		var last: Vector3 = path[path.size() - 1]
		out["end_xz"] = _xz(last)
		out["end_gap"] = snappedf(VU.in_xz(last).distance_to(VU.in_xz(a_to)), 0.1)
		out["start_xz"] = _xz(path[0])
		out["start_gap"] = snappedf(VU.in_xz(path[0]).distance_to(VU.in_xz(a_from)), 0.1)
	return out


## For every unit type any owned producer can train: the commander's unmet need for it, and
## whether the bot considers it at all (Bot.may_consider_unit).
func _producible_needs(a_bot: Bot) -> Dictionary:
	var needs: Dictionary = {}
	for s: Actor in a_bot.get_production_structures():
		for t: StringName in s.production.producible_types:
			if needs.has(t):
				continue
			var need: int = a_bot.get_unmet_need(t)
			needs[str(t)] = (
				TechnologySpec.UnmetNeed.keys()[need]
				+ ("" if a_bot.may_consider_unit(t) else "/skipped")
				+ ("" if a_bot.unit_can_attack(t) else "/unarmed")
			)
	return needs


## How many units `a_structures` hold between them (occupants of any garrison).
func _bunkered_count(a_structures: Array) -> int:
	var total: int = 0
	for s: Actor in a_structures:
		if s.garrison != null:
			total += s.garrison.occupants().size()
	return total


## Piece id -> how many of them, for a roster line in a sample.
func _count_by_id(a_pieces: Array) -> Dictionary:
	var out: Dictionary = {}
	for piece: Actor in a_pieces:
		var key: String = String(piece.id)
		out[key] = int(out.get(key, 0)) + 1
	return out


## Summed build cost of `a_units`, the same figure Bot.army_resource_value reports — computed
## here rather than called so a slot that is not a Bot (a human rig, in a scenario this is
## pointed at later) still produces a series instead of nothing.
func _army_energy_value(a_commander: Commander, a_units: Array) -> float:
	var total: float = 0.0
	for unit: Actor in a_units:
		var spec: TechnologySpec = a_commander.technology_mapping.get(unit.id)
		if spec != null:
			total += spec.energy_cost
	return total


## Append this tick's full pre-hash state to the configured dump file. Off unless the config
## names one: it is a debugging instrument for hunting a divergence, not part of a result.
func _dump_state(a_tick: int) -> void:
	var path: String = _config.get("state_dump_path", "")
	if path.is_empty():
		return
	var file: FileAccess = (
		FileAccess.open(path, FileAccess.READ_WRITE)
		if FileAccess.file_exists(path)
		else FileAccess.open(path, FileAccess.WRITE)
	)
	if file == null:
		return
	file.seek_end()
	file.store_line("%d %s" % [a_tick, SimulationDigest.state_string(_scenario)])
	file.close()


func _wall_seconds() -> float:
	return float(Time.get_ticks_usec() - _wall_start_usec) / 1_000_000.0


#endregion


#region Result
func _emit(a_outcome: String, a_winner: int) -> void:
	var ticks: int = _scenario.tick
	# The harness's verdict is the match's end (a no-op when the scenario already ended it).
	_scenario.end_match(_scenario.player_slots[a_winner].commander.id if a_winner >= 0 else -1)
	var event_log: String = _write_event_log()
	var replay_written: String = _write_replay()
	var result: Dictionary = {
		"ok": true,
		"config_path": _config_path,
		"seed": _scenario.rng_seed,
		"map_seed": _played_map_seed,
		"map_symmetric": bool(_config.get("map_symmetric", false)),
		"scenario": _config.get("scenario", DEFAULT_SCENARIO),
		"win_condition": Scenario.WinCondition.keys()[_scenario.win_condition],
		"swap_start_points": bool(_config.get("swap_start_points", false)),
		"outcome": a_outcome,
		"winner": a_winner,
		"ticks": ticks,
		"simulated_seconds": TimeUtils.seconds_from_ticks(ticks),
		"wall_seconds": _wall_seconds(),
		"ticks_per_wall_second": float(ticks) / maxf(_wall_seconds(), 0.001),
		"physics_ticks_per_second": TimeUtils.ticks_per_second(),
		"deployed_ticks": _deployed_tick,
		"final_digest": _samples[-1]["digest"] if not _samples.is_empty() else "",
		# A script error is a bug that did not stop the match (no debugger is attached), so
		# a verdict reached through one is reported as not clean rather than as a result.
		"clean": _errors.script_error_count() == 0,
		"errors": _errors.summary(),
		"slots": _result_slots(),
		"samples": _samples,
		"event_log": event_log,
		"replay_path": replay_written,
		"replay_to_play": str(_config.get("replay_to_play", "")),
		# In a playback: the first tick whose digest differed from the recording's, -1 for none.
		"replay_drift_tick":
		_scenario.recorder.first_drift_tick if _scenario.recorder != null else -1,
	}
	_write(result)


## The recording, written as a kept replay at `replay_path` and returned as an absolute path;
## "" when none was asked for or it could not be written. After end_match, so the file holds
## the match's last tick.
func _write_replay() -> String:
	if _replay_path == "" or _scenario.recorder == null:
		return ""
	if _scenario.recorder.write_kept(_replay_path) != OK:
		push_error("run_match: could not write the replay to %s" % _replay_path)
		return ""
	return ProjectSettings.globalize_path(_replay_path)


## Write the match's event log beside the result, as gzipped JSON lines (`<out>.events.jsonl.gz`),
## and return its path; "" when no result file was asked for or it could not be written.
func _write_event_log() -> String:
	if _out_path.is_empty() or _scenario.match_log == null:
		return ""
	var path: String = _out_path.get_basename() + ".events.jsonl.gz"
	if _scenario.match_log.write_gzip(path) != OK:
		push_error("run_match: could not write %s" % path)
		return ""
	return path


## What each slot was PLAYING — the tier it started from and every field of the live
## BotDifficulty it ended up with. Echoed into the result so a JSONL of results is
## self-describing: the next agent reads parameters and outcome from one row, without having
## to keep the config files that produced them.
func _result_slots() -> Array:
	var out: Array = []
	for i: int in _scenario.player_slots.size():
		var slot: PlayerSlot = _scenario.player_slots[i]
		var brain: BotBrain = _brain_for_slot(i)
		var config: Dictionary = {}
		if brain != null and brain.config != null:
			for property: Dictionary in brain.config.get_property_list():
				if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
					config[property["name"]] = brain.config.get(property["name"])
		var actuator: BotActuator = brain.get_actuator() if brain != null else null
		(
			out
			. append(
				{
					"slot": i,
					"commander_id": i + 1,
					"difficulty": PlayerSlot.Difficulty.keys()[slot.difficulty],
					"faction":
					slot.faction.resource_path.get_file().get_basename() if slot.faction else "",
					"config": config,
					# What the slot fielded and what its bot considered, chose, ordered and was
					# refused — the piece-usage audit's input (tools/selfplay/results/piece_usage.py).
					"produced_by_id": _produced_by_id(i),
					"usage": actuator.usage.summary() if actuator != null else {},
				}
			)
		)
	return out


func _fail(a_reason: String) -> void:
	_write(
		{
			"ok": false,
			"error": a_reason,
			"config_path": _config_path,
			"clean": _errors.script_error_count() == 0,
			"errors": _errors.summary(),
		}
	)


## stdout AND a file. The file is what a batch collects; the stdout line is what makes a
## single run readable at a terminal, and it is fenced by markers because Godot writes plenty
## of its own noise around it (NavigationServer warnings, leaked-RID reports at exit).
func _write(a_result: Dictionary) -> void:
	var text: String = JSON.stringify(a_result)
	print("---SELFPLAY-RESULT-BEGIN---")
	print(text)
	print("---SELFPLAY-RESULT-END---")
	if not _out_path.is_empty():
		var file: FileAccess = FileAccess.open(_out_path, FileAccess.WRITE)
		if file == null:
			push_error("run_match: could not write %s" % _out_path)
		else:
			file.store_string(text)
			file.close()
	OS.remove_logger(_errors)
	get_tree().quit(0 if a_result.get("ok", false) else 1)
#endregion
