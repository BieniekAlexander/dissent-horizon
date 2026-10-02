extends GutTest

## LevelConstraints: integer levels under difference constraints, as pass 6 assigns terraces.


func test_an_unconstrained_group_takes_its_wanted_level() -> void:
	var system := LevelConstraints.new(1, 5)
	assert_eq(system.solve(PackedInt32Array([3])), PackedInt32Array([3]))


func test_a_wanted_level_out_of_range_is_clamped() -> void:
	var system := LevelConstraints.new(2, 5)
	assert_eq(system.solve(PackedInt32Array([9, -2])), PackedInt32Array([5, 0]))


func test_neighbours_stay_within_their_weight() -> void:
	var system := LevelConstraints.new(2, 5)
	system.within(0, 1, 1)
	var levels: PackedInt32Array = system.solve(PackedInt32Array([0, 5]))
	assert_lte(absi(levels[0] - levels[1]), 1)


func test_a_chain_carries_a_fixed_level_along_it() -> void:
	# 0 is fixed at 0 and each link allows one step, so 3 can rise at most three.
	var system := LevelConstraints.new(4, 5)
	system.fix(0, 0)
	for group: int in 3:
		system.within(group, group + 1, 1)
	var levels: PackedInt32Array = system.solve(PackedInt32Array([0, 5, 5, 5]))
	assert_eq(levels, PackedInt32Array([0, 1, 2, 3]))


func test_apart_holds_two_groups_at_least_their_drop_apart() -> void:
	var system := LevelConstraints.new(2, 5)
	system.apart(0, 1, 2, 4)
	var levels: PackedInt32Array = system.solve(PackedInt32Array([2, 2]))
	assert_between(levels[0] - levels[1], 2, 4)


## A cliff on a cut whose sides are also joined the short way round cannot be steeper than the
## way round can climb: that is the system pass 6 drops a cliff from.
func test_a_drop_the_way_round_cannot_climb_is_infeasible() -> void:
	var system := LevelConstraints.new(3, 5)
	system.within(0, 2, 1)
	system.within(2, 1, 1)
	var before: int = system.mark()
	system.apart(0, 1, 3, 4)
	assert_false(system.is_feasible())
	system.rollback(before)
	assert_true(system.is_feasible())
	system.apart(0, 1, 2, 4)
	assert_true(system.is_feasible())


func test_an_infeasible_system_solves_to_nothing() -> void:
	var system := LevelConstraints.new(1, 5)
	system.fix(0, 2)
	system.fix(0, 3)
	assert_eq(system.solve(PackedInt32Array([2])), PackedInt32Array())
