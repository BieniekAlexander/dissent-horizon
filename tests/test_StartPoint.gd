extends GutTest

## Tests for StartPoint — the start marker's column: drawn in its own colour, and hidden in a
## running game, where the slot's starting units stand on it.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_StartPoint.gd \
##     -gdir=res://tests/none -gexit


func _marker() -> StartPoint:
	var scene := load("res://scenes/scenarios/start_point.tscn") as PackedScene
	var marker := scene.instantiate() as StartPoint
	add_child_autofree(marker)
	return marker


func test_the_column_is_hidden_in_a_running_game() -> void:
	assert_false((_marker().get_node("Column") as MeshInstance3D).visible)


func test_the_column_takes_the_marker_colour() -> void:
	var marker: StartPoint = _marker()
	marker.color = Color.ORANGE
	var column := marker.get_node("Column") as MeshInstance3D
	var material := column.material_override as StandardMaterial3D
	assert_eq(material.albedo_color, Color.ORANGE)


func test_a_marker_is_a_start_point() -> void:
	assert_true(_marker().is_in_group(Skirmish.START_POINT_GROUP))
