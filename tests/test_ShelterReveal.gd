extends GutTest

## HEGEMONY opens by showing every player every shelter for a few seconds (Scenario.
## _reveal_shelters_at_start). What is checked here is WHAT gets revealed and WHEN the rule
## applies; the vision source itself is EventRevealRegion.spawn_vision, whose sizing and lifespan
## test_EventRevealRegion covers, and the fog it clears is test_ScoutVision's.


## A fixture at `a_xz`, carrying a Shelter component when `a_shelter`.
func _fixture(a_xz: Vector2, a_shelter: bool) -> Node3D:
	var piece := Node3D.new()
	piece.add_to_group("fixture")
	if a_shelter:
		var shelter := Shelter.new()
		shelter.name = "Shelter"
		piece.add_child(shelter)
	add_child_autofree(piece)
	piece.global_position = Vector3(a_xz.x, 0.0, a_xz.y)
	return piece


func test_every_shelter_and_only_shelters_are_revealed() -> void:
	_fixture(Vector2(10.0, 4.0), true)
	_fixture(Vector2(-20.0, 7.0), true)
	_fixture(Vector2(3.0, 3.0), false)  # an extractor, a building: not a shelter
	var points: Array[Vector2] = Scenario.shelter_points(get_tree())
	assert_eq(points.size(), 2)
	assert_true(points.has(Vector2(10.0, 4.0)))
	assert_true(points.has(Vector2(-20.0, 7.0)))


func test_only_a_hegemony_match_reveals_anything() -> void:
	_fixture(Vector2(10.0, 4.0), true)
	var scenario: Scenario = autofree(Scenario.new())
	scenario.win_condition = Scenario.WinCondition.MISSION
	assert_eq(scenario._reveal_shelters_at_start(), [] as Array[Commandable], "a mission decides")
	scenario.win_condition = Scenario.WinCondition.NONE
	assert_eq(scenario._reveal_shelters_at_start(), [] as Array[Commandable])

