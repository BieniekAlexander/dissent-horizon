extends GutTest

## The shot log behind the `hit_rate` simulation check: which emissions a group fired, and which
## of them landed on a target group. Pure bookkeeping over signals, driven here by hand — no
## arena, no flight. See gdd/systems/scenario-scripting/simulation-tests.md §Counting shots.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_SimShotLog.gd -gexit


## A shooter watched by `a_log` as group "A.shooters", and a target in "B.targets".
func _setup(a_roster: SimGroupRoster) -> Array:
	var shooter: Commandable = FakePieces.unit()
	add_child_autofree(shooter)
	var target: Commandable = FakePieces.unit()
	add_child_autofree(target)
	a_roster.add("A.shooters", shooter, "fake_unit")
	a_roster.add("B.targets", target, "fake_unit")
	return [shooter, target]


## Fire one emission from `a_shooter`, landing on `a_victims`, then let it leave the game.
func _fire(a_shooter: Commandable, a_victims: Array, a_settle: bool = true) -> Entity:
	var emission: Entity = FakePieces.emission()
	add_child(emission)
	a_shooter.action_tracker.cue(ActionTracker.CUE_EMITTED, emission)
	Payload.of(emission).paid_out.emit(a_victims)
	if a_settle:
		emission.free()
	else:
		autofree(emission)
	return emission


func _tally(a_roster: SimGroupRoster) -> Vector2i:
	return a_roster.shots.tally("A.shooters", "", a_roster.member_ids("B.targets"))


func test_a_shot_that_lands_on_the_target_group_is_a_hit() -> void:
	var roster := SimGroupRoster.new()
	var pieces: Array = _setup(roster)
	_fire(pieces[0], [pieces[1]])
	_fire(pieces[0], [])
	assert_eq(_tally(roster), Vector2i(1, 2), "one hit of two settled shots")


func test_a_shot_still_in_flight_is_not_counted() -> void:
	var roster := SimGroupRoster.new()
	var pieces: Array = _setup(roster)
	_fire(pieces[0], [], false)
	assert_eq(_tally(roster), Vector2i(0, 0))


func test_a_hit_on_a_piece_since_destroyed_still_counts() -> void:
	var roster := SimGroupRoster.new()
	var pieces: Array = _setup(roster)
	_fire(pieces[0], [pieces[1]])
	(pieces[1] as Node).free()
	assert_eq(_tally(roster), Vector2i(1, 1))


func test_landing_on_someone_else_is_a_miss() -> void:
	var roster := SimGroupRoster.new()
	var pieces: Array = _setup(roster)
	var bystander: Commandable = FakePieces.unit()
	add_child_autofree(bystander)
	_fire(pieces[0], [bystander])
	assert_eq(_tally(roster), Vector2i(0, 1))


func test_hit_rate_is_a_known_check() -> void:
	assert_true(SimSpec.CHECK_ARGUMENTS.has("hit_rate"))
	assert_true(SimCheckLibrary.implemented_names().has("hit_rate"))
