extends GutTest

## THE CLOCK'S OPENING PRIOR (BotFirstContact; gdd/systems/ai/objective-selection.md §The
## opening prior): how soon the unseen enemy's opening force could arrive, from the map's size,
## the start placement parameters and the fastest ground unit the enemy starts with.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_BotFirstContact.gd -gexit

const SQUARE: Rect2 = Rect2(-60.0, -60.0, 120.0, 120.0)


func test_two_starts_stand_twice_the_rings_mean_radius_apart() -> void:
	var params := MapGenerationParams.new()
	params.start_min_center_fraction = 0.25
	params.start_edge_margin_cells = 10.0
	params.start_separation_diagonal_fraction = 0.25
	# Ring from 30 to 50 of the centre: mean 40, so 80 apart; the floor is 0.25 × 169.7 = 42.
	assert_almost_eq(BotFirstContact.separation(SQUARE, params), 80.0, 1e-6)


func test_the_separation_floor_holds_on_a_map_whose_ring_is_tight() -> void:
	var params := MapGenerationParams.new()
	params.start_min_center_fraction = 0.05
	params.start_edge_margin_cells = 50.0
	params.start_separation_diagonal_fraction = 0.5
	# Ring from 6 to 10: 16 apart, under the floor of 0.5 × 169.7.
	assert_almost_eq(BotFirstContact.separation(SQUARE, params), 0.5 * SQUARE.size.length(), 1e-6)


func test_the_estimate_is_the_separation_at_the_fastest_ground_speed() -> void:
	var params := MapGenerationParams.new()
	params.start_min_center_fraction = 0.25
	params.start_edge_margin_cells = 10.0
	params.start_separation_diagonal_fraction = 0.25
	assert_almost_eq(BotFirstContact.estimate_seconds(SQUARE, params, 4.0), 20.0, 1e-6)
	assert_eq(BotFirstContact.estimate_seconds(SQUARE, params, 0.0), INF, "nobody walks")
	assert_eq(BotFirstContact.estimate_seconds(Rect2(), params, 4.0), INF, "no map")


func _scene(a_speed: float, a_flies: bool) -> PackedScene:
	var root := Node3D.new()
	var movement := Movement.new()
	movement.name = "Locomotion"
	movement.speed = a_speed
	root.add_child(movement)
	movement.owner = root
	if a_flies:
		var aerial := Node.new()
		aerial.name = "Aerial"
		root.add_child(aerial)
		aerial.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	return scene


func test_the_fastest_ground_speed_ignores_aircraft_and_empty_slots() -> void:
	var scenes: Array = [_scene(3.0, false), _scene(9.0, true), null, _scene(4.5, false)]
	assert_almost_eq(BotFirstContact.fastest_ground_speed(scenes), 4.5, 1e-9)
	assert_eq(BotFirstContact.fastest_ground_speed([_scene(9.0, true)]), 0.0, "only aircraft")
	assert_eq(BotFirstContact.fastest_ground_speed([]), 0.0)
