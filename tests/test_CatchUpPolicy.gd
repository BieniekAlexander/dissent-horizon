extends GutTest

## CatchUpPolicy — when the engine stops catching up on missed ticks: only once the simulation
## cannot keep real time on average, and back on only with room to spare.

const BUDGET: float = 1.0 / 30.0
## Steps enough for the running average to settle on a steady cost.
const SETTLE_STEPS: int = 300


func _feed(a_policy: CatchUpPolicy, a_fraction: float, a_steps: int = SETTLE_STEPS) -> bool:
	var is_lowered: bool = false
	for _i: int in a_steps:
		is_lowered = a_policy.observe(a_fraction * BUDGET, BUDGET)
	return is_lowered


func test_a_simulation_within_budget_keeps_catching_up() -> void:
	assert_false(_feed(CatchUpPolicy.new(), 0.9))


func test_one_slow_step_is_still_caught_up_on() -> void:
	var policy := CatchUpPolicy.new()
	_feed(policy, 0.5)
	assert_false(policy.observe(10.0 * BUDGET, BUDGET), "a navmesh rebuild's spike")


func test_a_simulation_over_budget_stops_catching_up() -> void:
	var policy := CatchUpPolicy.new()
	assert_true(_feed(policy, 1.5))
	assert_almost_eq(policy.speed_fraction(), 1.0 / 1.5, 0.01, "it runs at the speed it can")


func test_it_resumes_only_with_room_to_spare() -> void:
	var policy := CatchUpPolicy.new()
	_feed(policy, 1.5)
	assert_true(_feed(policy, 0.9), "just under budget is not enough to resume")
	assert_false(_feed(policy, 0.5))


func test_full_speed_reads_as_full_speed() -> void:
	var policy := CatchUpPolicy.new()
	_feed(policy, 0.5)
	assert_eq(policy.speed_fraction(), 1.0)
