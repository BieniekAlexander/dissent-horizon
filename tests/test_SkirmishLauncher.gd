extends GutTest

## FROM A SKIRMISH RECIPE TO A MATCH: the map parameters it implies, and which start each
## slot is given. Generation itself is not run here — it takes seconds per map.
##
## Run with:
## godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_SkirmishLauncher.gd -gexit
##
## Why: gdd/systems/ux/ui/menus.md §Skirmish.


func _recipe(a_teams: Array) -> Dictionary:
	var players: Array = []
	for team: int in a_teams:
		players.append({"faction": SkirmishSetup.FACTIONS[0], "team": team, "is_bot": true})
	return {
		"version": SkirmishLauncher.RECIPE_VERSION,
		"players": players,
		"map_seed": 1,
		"rng_seed": 2,
	}


func test_a_free_for_all_is_one_start_per_alliance() -> void:
	var params: MapGenerationParams = SkirmishLauncher.params_for(_recipe([0, 0, 0]))
	assert_eq(params.alliance_count, 3)
	assert_eq(params.starts_per_alliance, 1)


func test_teams_become_alliances_of_their_size() -> void:
	var params: MapGenerationParams = SkirmishLauncher.params_for(_recipe([1, 1, 2, 2]))
	assert_eq(params.alliance_count, 2)
	assert_eq(params.starts_per_alliance, 2)


func test_uneven_teams_take_the_largest_teams_size() -> void:
	var params: MapGenerationParams = SkirmishLauncher.params_for(_recipe([1, 1, 0]))
	assert_eq(params.alliance_count, 2)
	assert_eq(params.starts_per_alliance, 2, "the lone player's alliance has a spare start")


func test_the_map_grows_with_the_number_of_starts() -> void:
	var two: MapGenerationParams = SkirmishLauncher.params_for(_recipe([0, 0]))
	var four: MapGenerationParams = SkirmishLauncher.params_for(_recipe([1, 1, 2, 2]))
	assert_eq(two.play_size_min.x, SkirmishLauncher.BASE_PLAY_SIZE_MIN)
	assert_gt(four.play_size_min.x, two.play_size_min.x)
	assert_gt(four.play_size_max.x, two.play_size_max.x)


func test_a_recipe_from_another_version_is_refused() -> void:
	var recipe: Dictionary = _recipe([0, 0])
	recipe["version"] = -1
	assert_ne(SkirmishLauncher.recipe_refusal(recipe), "")
	assert_eq(SkirmishLauncher.recipe_refusal(_recipe([0, 0])), "")


## A map with `a_alliances.size()` start markers, StartPoint1…, the generator's alliance each.
func _map_with_starts(a_alliances: Array) -> Array:
	var map: Map = autofree(Map.new())
	var generated := GeneratedMap.new()
	for i: int in a_alliances.size():
		var marker := Marker3D.new()
		marker.name = "StartPoint%d" % (i + 1)
		marker.position = Vector3(i, 0, 0)
		map.add_child(marker)
		generated.starts.append(MapStart.at(Vector2(i, 0), a_alliances[i]))
	return [map, generated]


func _start_x(a_map: Map, a_slot: int) -> float:
	return (a_map.get_node("StartPoint%d" % (a_slot + 1)) as Node3D).position.x


func test_each_slot_gets_a_start_of_its_alliance() -> void:
	# Starts 0,1 belong to alliance 0 and 2,3 to alliance 1; the slots alternate teams.
	var built: Array = _map_with_starts([0, 0, 1, 1])
	var map: Map = built[0]
	SkirmishLauncher._assign_starts(map, built[1], PackedInt32Array([0, 1, 0, 1]))
	assert_eq(
		[_start_x(map, 0), _start_x(map, 1), _start_x(map, 2), _start_x(map, 3)],
		[0.0, 2.0, 1.0, 3.0]
	)


func test_a_spare_start_is_removed() -> void:
	var built: Array = _map_with_starts([0, 0, 1, 1])
	var map: Map = built[0]
	SkirmishLauncher._assign_starts(map, built[1], PackedInt32Array([0, 0, 1]))
	assert_eq(map.get_child_count(), 3)
	assert_null(map.get_node_or_null("StartPoint4"))
	assert_eq(_start_x(map, 2), 2.0, "the lone player takes its alliance's first start")


func test_a_replay_header_carries_the_recipe() -> void:
	var scenario := Scenario.new()
	scenario.skirmish_recipe = _recipe([0, 0])
	var header: Dictionary = ReplayFile.header_for(scenario, "v")
	assert_eq(header["skirmish"], scenario.skirmish_recipe)
	scenario.free()


func test_an_authored_scenario_header_has_no_recipe() -> void:
	var scenario := Scenario.new()
	assert_false(ReplayFile.header_for(scenario, "v").has("skirmish"))
	scenario.free()
