extends GutTest

## The Colonial carrier's errands, after 2026-10-06: a truck that took one prisoner and drove
## home every time, and turned for the Compound when it carried nothing but its own Servant.
## Three rules fix that and each is pinned here:
##   • a deposit is worth its load SCALED BY HOW FULL the cage is (BotOpportunist.deposit_value),
##     so a part-load prefers to keep filling — the discount the gatherer's comment promised
##     and the code did not apply;
##   • only CAPTIVES are cargo (Garrison.captive_count); the truck's own side riding in the
##     cage is not something to bank;
##   • a contact errand is a move AT the prey (BotActuator.move_at), which follows it, rather
##     than a move to where it stood.


class StubPiece:
	extends Actor

	static func make() -> StubPiece:
		var piece := StubPiece.new()
		for pair: Array in [
			["Ownership", Ownership.new()],
			["AvoidanceObstacle", NavigationObstacle3D.new()],
			["Veterancy", Veterancy.new()],
			["Orders", Orders.new()]
		]:
			var node: Node = pair[1]
			node.name = pair[0]
			piece.add_child(node)
		var bar := Node3D.new()
		bar.name = "HPBar"
		var fill := Sprite3D.new()
		fill.name = "HPBarFill"
		bar.add_child(fill)
		piece.add_child(bar)
		return piece

	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
		command_receiver.initialize(self)


const WORTH: float = BotOpportunist.PRISONER_VALUE

# ─── DEPOSIT VALUATION ───────────────────────────────────────────────────────


func test_an_empty_cage_is_worth_nothing_to_bank() -> void:
	assert_eq(BotOpportunist.deposit_value(0, 3, false), 0.0)


func test_a_part_load_is_discounted_by_how_empty_the_cage_still_is() -> void:
	# One of three: a third of a load, so a third of the prisoner's worth. The old code paid
	# the full 60 here, which beat every capture more than a few units away.
	assert_almost_eq(BotOpportunist.deposit_value(1, 3, false), WORTH * (1.0 / 3.0), 0.001)
	assert_almost_eq(BotOpportunist.deposit_value(2, 3, false), 2.0 * WORTH * (2.0 / 3.0), 0.001)


func test_a_full_load_earns_the_bonus() -> void:
	assert_almost_eq(
		BotOpportunist.deposit_value(3, 3, true),
		3.0 * WORTH * BotOpportunist.FULL_LOAD_BONUS,
		0.001
	)


func test_banking_grows_with_the_load_so_filling_up_is_never_worse() -> void:
	var one: float = BotOpportunist.deposit_value(1, 3, false)
	var two: float = BotOpportunist.deposit_value(2, 3, false)
	var three: float = BotOpportunist.deposit_value(3, 3, true)
	assert_true(one < two and two < three, "monotone in the load")


func test_a_part_load_yields_to_a_nearby_capture() -> void:
	# The behaviour the discount is for: with one prisoner aboard, a neutral prey (no cost
	# entry, so worth exactly PRISONER_VALUE) a short drive away outranks going home.
	var deposit: float = BotOpportunist.deposit_value(1, 3, false)
	var capture_nearby: float = WORTH - ContactOpportunity.TRAVEL_COST_PER_UNIT * 10.0
	assert_true(capture_nearby > deposit, "ten units away: capture first")
	var capture_far: float = WORTH - ContactOpportunity.TRAVEL_COST_PER_UNIT * 25.0
	assert_true(capture_far < deposit, "twenty-five units away: bank what you have")


# ─── WHAT COUNTS AS CARGO ────────────────────────────────────────────────────


func _commander(a_id: int) -> Commander:
	var c := Commander.new()
	c.id = a_id
	add_child_autofree(c)
	return c


func _piece_of(a_owner: Commander) -> Actor:
	var piece: StubPiece = StubPiece.make()
	a_owner.add_child(piece)
	piece.ownership.commander = a_owner
	return piece


func test_only_captives_count_as_cargo() -> void:
	var us: Commander = _commander(1)
	var them: Commander = _commander(2)
	var truck: Actor = _piece_of(us)
	var cage := Garrison.new()
	cage.name = "Garrison"
	truck.add_child(cage)
	var servant: Actor = _piece_of(us)
	var prisoner: Actor = _piece_of(them)
	# Ridden and captured respectively; the garrison's own admission is not under test.
	cage._garrisoned = [servant, prisoner]
	assert_eq(cage.garrisoned_count(), 2, "guards the fixture")
	assert_eq(cage.captive_count(), 1, "the Servant is the truck's own side")


# ─── A CONTACT ERRAND FOLLOWS ITS PREY ───────────────────────────────────────


func test_move_at_names_the_target_and_remembers_where_it_stood() -> void:
	var us: Commander = _commander(1)
	var them: Commander = _commander(2)
	var truck: Actor = _piece_of(us)
	var prey: Actor = _piece_of(them)
	prey.global_position = Vector3(30.0, 0.0, 0.0)
	var act := BotActuator.new(autofree(Map.new()) as Map)
	act.move_at([truck], prey)
	var cmd: MoveCommand = truck.current_command()
	assert_not_null(cmd, "a move was issued")
	assert_eq(cmd.message.target, prey, "aimed at the piece, so it follows it")
	assert_eq(cmd.message.world_position, Vector3(30.0, 0.0, 0.0), "and where it was at issue")
	prey.global_position = Vector3(40.0, 0.0, 0.0)
	assert_eq(cmd.message.position, Vector3(40.0, 0.0, 0.0), "the destination moved with it")


func test_a_contact_opportunity_moves_at_its_prey() -> void:
	var us: Commander = _commander(1)
	var them: Commander = _commander(2)
	var truck: Actor = _piece_of(us)
	var prey: Actor = _piece_of(them)
	prey.global_position = Vector3(30.0, 0.0, 0.0)
	var act := BotActuator.new(autofree(Map.new()) as Map)
	ContactOpportunity.new(truck, prey, WORTH, "capture").execute(act)
	var cmd: MoveCommand = truck.current_command()
	assert_not_null(cmd)
	assert_eq(cmd.message.target, prey)
