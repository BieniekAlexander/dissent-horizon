extends GutTest

## The minimap's map layer gathers the neutral fixtures it colours from Map.structure_cell_map,
## and must survive a key that has been freed without leaving the map — a freed object cannot
## be assigned to a typed variable, so the read has to check validity first.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_MinimapFixtures.gd -gexit

const CELLS: Array = [Vector2i(1, 1), Vector2i(1, 2)]


func _fixture(a_commander_id: int) -> Entity:
	var fixture: Entity = FakePieces.feature()
	add_child_autofree(fixture)
	if a_commander_id != 0:
		var commander := Commander.new()
		commander.id = a_commander_id
		add_child_autofree(commander)
		fixture.ownership.commander = commander
	return fixture


func test_it_keeps_the_live_neutral_fixtures() -> void:
	var neutral := _fixture(0)
	var owned := _fixture(3)
	var found: Dictionary = Minimap.neutral_fixtures({neutral: CELLS, owned: CELLS})
	assert_eq(found.keys(), [neutral])
	assert_eq(found[neutral], CELLS)


func test_a_freed_fixture_left_in_the_map_is_skipped() -> void:
	var gone := Entity.new()
	var cell_map: Dictionary = {gone: CELLS}
	gone.free()
	var neutral := _fixture(0)
	cell_map[neutral] = CELLS
	assert_eq(Minimap.neutral_fixtures(cell_map).keys(), [neutral], "and no error raised")
