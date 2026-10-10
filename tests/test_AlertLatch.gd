extends GutTest

## WHEN A POLLED STATE ALERT SPEAKS.
##
## Run with:
## godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_AlertLatch.gd -gexit
##
## Why: gdd/systems/ux/ui/alerts.md §State alerts.


func test_it_waits_for_the_state_to_hold() -> void:
	var latch := AlertLatch.new(10, 0)
	assert_false(latch.update(true, 0))
	assert_false(latch.update(true, 9))
	assert_true(latch.update(true, 10))


func test_a_flicker_shorter_than_sustain_never_speaks() -> void:
	var latch := AlertLatch.new(10, 0)
	latch.update(true, 0)
	latch.update(false, 5)
	assert_false(latch.update(true, 12), "the clock restarted at 12, not 0")


func test_it_reminds_while_the_state_holds() -> void:
	var latch := AlertLatch.new(0, 30)
	assert_true(latch.update(true, 0))
	assert_false(latch.update(true, 29))
	assert_true(latch.update(true, 30))
	assert_false(latch.update(true, 31))


func test_no_repeat_means_once_per_episode() -> void:
	var latch := AlertLatch.new(0, 0)
	assert_true(latch.update(true, 0))
	assert_false(latch.update(true, 1000))
	latch.update(false, 1001)
	assert_true(latch.update(true, 1002), "a new episode speaks again")
