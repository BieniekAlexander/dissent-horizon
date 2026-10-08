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
#endregion

## The project setting that puts RVO avoidance on worker threads. Forced OFF for a harness
## process — see _force_single_threaded_avoidance.
const AVOIDANCE_THREADS_SETTING: String = (
	"navigation/avoidance/thread_model/" + "avoidance_use_multiple_threads"
)


## Take avoidance off its worker threads FOR THIS PROCESS — a declaration of intent more than
## a switch: the engine reads it when a navigation map is created, and the world map already
## exists. It is not what makes runs reproducible (synchronous navigation in project.godot
## is) — see selfplay-harness.md §Determinism, which also records why it left override.cfg.
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

	var scenario_path: String = _config.get("scenario", DEFAULT_SCENARIO)
	var packed := load(scenario_path) as PackedScene
	if packed == null:
		_fail("could not load scenario: %s" % scenario_path)
		return
	_scenario = packed.instantiate() as Scenario
	if _scenario == null:
		_fail("scene root is not a Scenario: %s" % scenario_path)
		return

	# BEFORE the node enters the tree: Scenario._ready seeds the simulation from rng_seed and
	# builds one commander per slot, so both have to be settled first.
	_scenario.rng_seed = int(_config.get("seed", 0))
	var slot_error: String = _configure_slots()
	if slot_error != "":
		_fail(slot_error)
		return
	var map_error: String = _apply_generated_map()
	if map_error != "":
		_fail(map_error)
		return
	var swap_error: String = _apply_start_point_swap()
	if swap_error != "":
		_fail(swap_error)
		return

	add_child(_scenario)
	# The brains exist now (Scenario._ready attaches one per Bot) and have not thought yet —
	# BotBrain builds its managers on the first think — so this is the moment to hand each one
	# its parameters.
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
		if overrides.is_empty():
			continue
		var brain: BotBrain = _brain_for_slot(i)
		if brain == null:
			return "slot %d has no BotBrain to configure" % i
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
func _apply_generated_map() -> String:
	if not _config.has("map_seed"):
		return ""
	var writer := GeneratedMapWriter.new()
	var params: MapGenerationParams = writer.default_params(_scenario.player_slots.size())
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
		_note_instances(i, _scenario.player_slots[i].commander)
		slots.append(slot)
	return {
		"tick": a_tick,
		"simulated_seconds": TimeUtils.seconds_from_ticks(a_tick),
		"digest": _state_digest(),
		"slots": slots,
	}


func _note_instances(a_slot: int, a_commander: Commander) -> void:
	while _instances_seen.size() <= a_slot:
		_instances_seen.append({})
	if a_commander == null:
		return
	var seen: Dictionary = _instances_seen[a_slot]
	for child: Node in a_commander.get_children():
		var entity := child as Commandable
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
		var entity := child as Commandable
		if entity == null or entity.is_queued_for_deletion():
			continue
		if entity.has_node("Structure"):
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
	for u: Commandable in a_units:
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
func _brain_sample(a_brain: BotBrain) -> Dictionary:
	if a_brain == null or a_brain.bot == null:
		return {}
	var bot: Bot = a_brain.bot
	var military: BotMilitary = a_brain._military
	var scout: BotScout = a_brain.get_scout()
	var momentum: BotMomentum = a_brain.get_momentum()
	# Exactly the test BotMilitary._objective_for(ATTACK) makes, and it must stay exactly that
	# test: an ATTACK posture with no answer here is silently demoted to MASS, so a bot that
	# has not FOUND the enemy cannot attack it however large its army grows. Reading the live
	# scene here (as this did while the objective was omniscient) would report a committed bot
	# that is in fact massing at home.
	var has_target: bool = (
		bot.nearest_believed_enemy_structure_position() != null
		or bot.nearest_believed_enemy_unit_position(bot.base_centroid()) != null
	)
	return {
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
	}


## How many units `a_structures` hold between them (occupants of any garrison).
func _bunkered_count(a_structures: Array) -> int:
	var total: int = 0
	for s: Commandable in a_structures:
		if s.garrison != null:
			total += s.garrison.occupants().size()
	return total


## Piece id -> how many of them, for a roster line in a sample.
func _count_by_id(a_pieces: Array) -> Dictionary:
	var out: Dictionary = {}
	for piece: Commandable in a_pieces:
		var key: String = String(piece.id)
		out[key] = int(out.get(key, 0)) + 1
	return out


## Summed build cost of `a_units`, the same figure Bot.army_resource_value reports — computed
## here rather than called so a slot that is not a Bot (a human rig, in a scenario this is
## pointed at later) still produces a series instead of nothing.
func _army_energy_value(a_commander: Commander, a_units: Array) -> float:
	var total: float = 0.0
	for unit: Commandable in a_units:
		var spec: TechnologySpec = a_commander.technology_mapping.get(unit.id)
		if spec != null:
			total += spec.energy_cost
	return total


## A short hash of everything the simulation is currently made of — the determinism check's
## whole instrument. Two runs of one seed must produce the same digest at the same tick; the
## first tick at which they differ is where the divergence entered.
##
## SORTED before hashing, and that is the load-bearing part: entity order within a commander
## follows tree order, which is not something the simulation guarantees. An unsorted digest
## would report divergence that is not there.
func _state_digest() -> String:
	return _state_string().sha256_text().substr(0, 16)


## The digest's INPUT, before hashing. Written per sample when the config names a
## `state_dump_path`, because a mismatched digest says only THAT two runs differ — this says
## WHICH entity, which is the whole of a divergence hunt.
func _state_string() -> String:
	var parts: PackedStringArray = []
	for commander: Commander in _scenario.commanders:
		if commander == null:
			continue
		var entities: PackedStringArray = []
		for child: Node in commander.get_children():
			var entity := child as Commandable
			if entity == null or entity.is_queued_for_deletion():
				continue
			var hp: float = entity.defense.hp if entity.defense != null else 0.0
			(
				entities
				. append(
					(
						"%s@%.3f,%.3f,%.3f#%.2f"
						% [
							entity.id,
							entity.global_position.x,
							entity.global_position.y,
							entity.global_position.z,
							hp,
						]
					)
				)
			)
		entities.sort()
		parts.append(
			(
				"c%d:e%d:d%d:%s"
				% [commander.id, commander.energy, commander.dominion, "|".join(entities)]
			)
		)
	return "|".join(parts)


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
	file.store_line("%d %s" % [a_tick, _state_string()])
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
	var result: Dictionary = {
		"ok": true,
		"config_path": _config_path,
		"seed": _scenario.rng_seed,
		"map_seed": _played_map_seed,
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
	}
	_write(result)


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
