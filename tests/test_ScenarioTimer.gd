extends GutTest

## The scenario timer's text format (ScenarioTimer.format_time).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ScenarioTimer.gd -gexit


func test_format_time_hides_hours_under_an_hour() -> void:
	assert_eq(ScenarioTimer.format_time(0), "0:00")
	assert_eq(ScenarioTimer.format_time(65), "1:05")
	assert_eq(ScenarioTimer.format_time(3599), "59:59")


func test_format_time_shows_hours_past_an_hour() -> void:
	assert_eq(ScenarioTimer.format_time(3600), "1:00:00")
	assert_eq(ScenarioTimer.format_time(3661), "1:01:01")
