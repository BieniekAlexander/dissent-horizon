class_name SkirmishLauncher
extends RefCounted
## TURNS A SKIRMISH RECIPE INTO A MATCH: map-generation parameters from the player count and
## alliances, a generated map, and the skirmish scenario around it with one slot per player, set
## to HEGEMONY — ready to hand to SceneManager.go_to_node, not yet in the tree.
##
## A recipe (SkirmishSetup.recipe) is everything the match is built from, so the lobby and a
## replay build the same match from the same dictionary: the replay header carries it
## (Scenario.skirmish_recipe), and ReplayLibrary.prepare_playback rebuilds through here.
##
## Generation is the slow part (seconds to tens of seconds) and is PURE (MapGenerator touches no
## scene), so it is split out to run off the main thread: `generate` is safe on a worker,
## `build` must run on the main thread. `launch` does both in one call, blocking.
## gdd/systems/ux/ui/menus.md §Skirmish.

#region Constants
const RECIPE_VERSION: int = 1
## The scenario a skirmish is built in: its root script (Skirmish), HUD rig, trigger host and the
## template PlayerSlot every player copies (starting energy, difficulty). Its authored map is
## replaced.
const TEMPLATE_SCENARIO: String = "res://scenes/scenarios/skirmish.tscn"
## Where the generated terrain is written; GeneratedMapWriter.build_map saves it before use.
const TERRAIN_PATH: String = "user://skirmish/generated_terrain.tres"
## Seeds tried, from the recipe's, before giving up on a setup.
const MAP_SEED_ATTEMPTS: int = 8
## The play-size range the generator has for two starts, scaled by √(starts / 2) so each player
## keeps about the same area. TODO: untuned — map-generation.md §Parameters has only the 2-start
## range.
const BASE_PLAY_SIZE_MIN: int = 100
const BASE_PLAY_SIZE_MAX: int = 120
#endregion


#region Public API
## The generator's parameters for `a_recipe`: one alliance per team (a teamless player is a team
## of one), every alliance given as many starts as the largest team has players, and the map
## sized by the number of starts. Uneven teams leave some of a smaller team's starts empty —
## the generator gives every alliance the same count.
static func params_for(a_recipe: Dictionary) -> MapGenerationParams:
	var sizes: Dictionary = _alliance_sizes(a_recipe)
	var alliance_count: int = sizes.size()
	var per_alliance: int = 1
	for size: int in sizes.values():
		per_alliance = maxi(per_alliance, size)
	var params: MapGenerationParams = GeneratedMapWriter.new().default_params(
		alliance_count * per_alliance
	)
	params.alliance_count = alliance_count
	params.starts_per_alliance = per_alliance
	var scale: float = sqrt(float(alliance_count * per_alliance) / 2.0)
	params.play_size_min = Vector2i.ONE * roundi(BASE_PLAY_SIZE_MIN * scale)
	params.play_size_max = Vector2i.ONE * roundi(BASE_PLAY_SIZE_MAX * scale)
	return params


## Generate the map for `a_recipe`: the recipe's seed, then the next ones, until one is valid.
## `{map: GeneratedMap, seed: int}`, or `{refusal}`. Pure — safe on a worker thread, given
## params built on the main thread (`params_for` loads piece scenes).
static func generate(a_recipe: Dictionary, a_params: MapGenerationParams) -> Dictionary:
	var first: int = int(a_recipe["map_seed"])
	for offset: int in MAP_SEED_ATTEMPTS:
		var generated: GeneratedMap = MapGenerator.generate(a_params, first + offset)
		if generated.is_valid():
			return {"map": generated, "seed": first + offset}
	return {"refusal": "No valid map for this setup in %d tries." % MAP_SEED_ATTEMPTS}


## The scenario for `a_recipe` on `a_map`, not yet in the tree, or `{refusal}`. Main thread.
## `a_recipe` is stored on the scenario with `map_seed` set to the seed actually played, so a
## replay regenerates this map on its first try.
static func build(a_recipe: Dictionary, a_map: GeneratedMap) -> Dictionary:
	var root: Node = (load(TEMPLATE_SCENARIO) as PackedScene).instantiate()
	var scenario := root as Scenario
	if scenario == null or scenario.player_slots.is_empty():
		root.free()
		return {"refusal": "The skirmish template is not a scenario with a slot to copy."}
	DirAccess.make_dir_recursive_absolute(TERRAIN_PATH.get_base_dir())
	# The writer places pieces from the scenes it loaded while filling in piece facts, so a fresh
	# one is primed the same way before it builds.
	var writer := GeneratedMapWriter.new()
	writer.apply_piece_facts(MapGenerationParams.new())
	var map: Map = writer.build_map(a_map, TERRAIN_PATH)
	if map == null:
		scenario.free()
		return {"refusal": "Could not write the generated terrain to %s." % TERRAIN_PATH}

	var template: PlayerSlot = scenario.player_slots[0]
	var slots: Array[PlayerSlot] = []
	for player: Dictionary in a_recipe["players"]:
		# Duplicated, never edited: the template is the .tscn's shared sub-resource.
		var slot := template.duplicate() as PlayerSlot
		slot.faction = load(str(player["faction"])) as PackedScene
		slot.alliance = int(player["team"])
		slot.is_bot = bool(player["is_bot"])
		slots.append(slot)
	scenario.player_slots = slots
	scenario.rng_seed = int(a_recipe["rng_seed"])
	scenario.win_condition = Scenario.WinCondition.HEGEMONY

	_assign_starts(map, a_map, Scenario.alliance_indices(slots))
	var old: Node = scenario.get_node_or_null(GeneratedMapWriter.MAP_NODE_NAME)
	if old != null:
		scenario.remove_child(old)
		old.free()
	GeneratedMapWriter.adopt(scenario, map)

	var played: Dictionary = a_recipe.duplicate(true)
	played["map_seed"] = a_map.generation_seed
	scenario.skirmish_recipe = played
	return {"scenario": scenario}


## Generate and build in one blocking call — for a replay, which has no lobby to wait in.
static func launch(a_recipe: Dictionary) -> Dictionary:
	var refusal: String = recipe_refusal(a_recipe)
	if refusal != "":
		return {"refusal": refusal}
	var generated: Dictionary = generate(a_recipe, params_for(a_recipe))
	if generated.has("refusal"):
		return generated
	return build(a_recipe, generated["map"])


## Why `a_recipe` cannot be built, or "".
static func recipe_refusal(a_recipe: Dictionary) -> String:
	if int(a_recipe.get("version", -1)) != RECIPE_VERSION:
		return "a skirmish recipe from another version"
	var players: Variant = a_recipe.get("players")
	if not (players is Array) or (players as Array).size() < SkirmishSetup.MIN_PLAYERS:
		return "a skirmish recipe with too few players"
	for player: Variant in players:
		if not (player is Dictionary) or not ResourceLoader.exists(str(player.get("faction", ""))):
			return "a skirmish recipe naming a faction this build does not have"
	return ""


#endregion


#region Internal
## alliance index → how many players it has.
static func _alliance_sizes(a_recipe: Dictionary) -> Dictionary:
	var slots: Array = []
	for player: Dictionary in a_recipe["players"]:
		var slot := PlayerSlot.new()
		slot.alliance = int(player["team"])
		slots.append(slot)
	var sizes: Dictionary = {}
	for index: int in Scenario.alliance_indices(slots):
		sizes[index] = int(sizes.get(index, 0)) + 1
	return sizes


## Give slot i the start marker Skirmish deploys it at. Skirmish pairs slots with start markers
## sorted by name, so the marker each slot is meant to have is renamed `StartPoint<i+1>`, and a
## start no slot takes (an uneven team's spare) is removed. The generator numbers alliances from
## 0 exactly as Scenario.alliance_indices does, so alliance a's slots take alliance a's starts.
static func _assign_starts(
	a_map: Map, a_generated: GeneratedMap, a_alliances: PackedInt32Array
) -> void:
	var markers: Array[Node] = []
	for i: int in a_generated.starts.size():
		markers.append(a_map.get_node_or_null("StartPoint%d" % (i + 1)))
	var taken: Dictionary = {}
	var chosen: Array[Node] = []
	for slot: int in a_alliances.size():
		for j: int in a_generated.starts.size():
			if not taken.has(j) and a_generated.starts[j].alliance == a_alliances[slot]:
				taken[j] = true
				chosen.append(markers[j])
				break
	# Two passes so a rename never collides with a marker still holding that name.
	for j: int in markers.size():
		if markers[j] == null:
			continue
		if taken.has(j):
			markers[j].name = "Unassigned%d" % j
		else:
			a_map.remove_child(markers[j])
			markers[j].free()
	for slot: int in chosen.size():
		if chosen[slot] != null:
			chosen[slot].name = "StartPoint%d" % (slot + 1)
#endregion
