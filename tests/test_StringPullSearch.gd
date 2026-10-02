extends GutTest

## WHICH WAYPOINT THE PATH STRAIGHTENING STEERS AT, and how many line tests it pays to find it.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_StringPullSearch.gd -gexit
##
## Movement.pulled_waypoint_index is given a line test as a callable, so these drive it with a
## table of which waypoints are in sight and count the tests it asks for. The cost is the point:
## it used to search back from the far end of the whole path, paying one line test per waypoint
## whenever the destination was out of sight — around an obstacle A* returns about one waypoint
## per cell, so that was the path's length in tests, every recheck. Why:
## gdd/systems/terrain-and-navigation/navigation-and-pathing.md
## §Path straightening.


## A line test answering from `a_visible`, counting how often it is asked.
class Sight:
	var visible: Array
	var asked: int = 0

	func _init(a_visible: Array) -> void:
		visible = a_visible

	func is_reachable(a_index: int) -> bool:
		asked += 1
		return visible[a_index]


func test_the_destination_in_sight_costs_one_test() -> void:
	var sight := Sight.new([true, false, true, false, true])
	assert_eq(Movement.pulled_waypoint_index(5, 1, 3, sight.is_reachable), 4)
	assert_eq(sight.asked, 1)


func test_out_of_sight_it_takes_the_furthest_visible_waypoint_within_reach() -> void:
	# Waypoint 2 is out of sight, 3 comes back into view past it: the search finds 3, which a
	# search forward from the next waypoint would have stopped short of.
	var sight := Sight.new([true, true, false, true, false, true, false])
	assert_eq(Movement.pulled_waypoint_index(7, 1, 4, sight.is_reachable), 3)


func test_waypoints_past_the_reach_are_never_tested() -> void:
	# 100 waypoints, the destination out of sight, reach ending at waypoint 10.
	var visible: Array = []
	for i: int in 100:
		visible.append(i != 99)
	var sight := Sight.new(visible)
	assert_eq(Movement.pulled_waypoint_index(100, 0, 10, sight.is_reachable), 10)
	assert_eq(sight.asked, 2, "the destination, then the furthest candidate — not the whole path")


func test_waypoints_already_passed_are_not_considered() -> void:
	# Only waypoint 1, behind the agent's next one, is in sight: steering back at it is the
	# wasted motion this rules out.
	var sight := Sight.new([false, true, false, false, false, false])
	assert_eq(Movement.pulled_waypoint_index(6, 3, 4, sight.is_reachable), -1)


func test_nothing_in_sight_answers_none() -> void:
	var sight := Sight.new([true, false, false, false])
	assert_eq(
		Movement.pulled_waypoint_index(4, 1, 3, sight.is_reachable),
		-1,
		"the caller then steers at the agent's own next waypoint"
	)


func test_an_empty_path_answers_none_without_testing() -> void:
	var sight := Sight.new([])
	assert_eq(Movement.pulled_waypoint_index(0, 0, 0, sight.is_reachable), -1)
	assert_eq(sight.asked, 0)
