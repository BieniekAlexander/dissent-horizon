extends GutTest

## A navigation agent or obstacle paused with the world is taken out of the server's avoidance and
## put back on resume, which changes what it solves afterwards: a hold of any length would play a
## different match. Both components are kept running through holds.
## gdd/systems/commands/netplay.md §Rules (a hold changes nothing but timing).


func test_the_navigation_agent_is_never_paused() -> void:
	var agent: Node = autofree(
		(load("res://scenes/components/navigation_agent.tscn") as PackedScene).instantiate()
	)
	assert_eq(agent.process_mode, Node.PROCESS_MODE_ALWAYS)


func test_the_avoidance_obstacle_is_never_paused() -> void:
	var obstacle: Node = autofree(
		(load("res://scenes/components/avoidance_obstacle.tscn") as PackedScene).instantiate()
	)
	assert_eq(obstacle.process_mode, Node.PROCESS_MODE_ALWAYS)
