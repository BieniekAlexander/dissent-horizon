extends GutTest

## EVERY ACTUATOR VERB ASKS ITS COMMAND'S PRECONDITION AND COUNTS THE ANSWER. Two verbs
## (interact, garrison_into) used to issue blind and leave the command to drop the order, so
## the piece-usage audit counted an impossible order as ISSUED — a piece the bot could never
## use read as used (gdd/systems/ai/piece-usage-audit.md §Cannot actuate). Pinned here per
## verb, against a unit the command would refuse, so the ledger cannot go blind again.


class StubPiece:
	extends Actor

	static func make() -> StubPiece:
		var piece := StubPiece.new()
		for pair: Array in [
			["Ownership", Ownership.new()],
			["AvoidanceObstacle", NavigationObstacle3D.new()],
			["Veterancy", Veterancy.new()]
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


var _us: Commander
var _act: BotActuator


func before_each() -> void:
	_us = Commander.new()
	_us.id = 1
	add_child_autofree(_us)
	_act = BotActuator.new(autofree(Map.new()) as Map)


func _piece() -> Actor:
	var piece: StubPiece = StubPiece.make()
	_us.add_child(piece)
	piece.ownership.commander = _us
	return piece


## Every outcome recorded for `a_kind`, whatever piece it was about.
func _outcomes(a_kind: String) -> Array:
	var out: Array = []
	var kind: Dictionary = _act.usage._actions.get(a_kind, {})
	for type: String in kind:
		out.append_array((kind[type] as Dictionary).keys())
	return out


func test_an_interact_the_unit_cannot_perform_is_refused_and_counted() -> void:
	var unit: Actor = _piece()  # no Interactor
	var target: Actor = _piece()
	assert_false(_act.interact(unit, target), "nothing to interact with")
	assert_false(unit.has_command(), "and no order was left on the unit")
	assert_eq(_outcomes("interact").size(), 1)
	assert_true(_outcomes("interact")[0].begins_with(BotUsageLog.OUTCOME_REFUSED_PREFIX))


func test_a_garrison_the_host_would_not_admit_is_refused_and_counted() -> void:
	var unit: Actor = _piece()  # cannot move, so no host admits it
	var host: Actor = _piece()  # and has no Garrison anyway
	assert_false(_act.garrison_into(unit, host))
	assert_false(unit.has_command())
	assert_eq(_outcomes("garrison").size(), 1)
	assert_true(_outcomes("garrison")[0].begins_with(BotUsageLog.OUTCOME_REFUSED_PREFIX))


func test_an_attack_with_nothing_to_fire_is_refused_and_counted() -> void:
	var unit: Actor = _piece()
	var target: Actor = _piece()
	_act.attack([unit], target)
	assert_false(unit.has_command())
	assert_eq(_outcomes("attack").size(), 1)
	assert_true(_outcomes("attack")[0].begins_with(BotUsageLog.OUTCOME_REFUSED_PREFIX))


func test_an_issued_order_is_counted_as_issued() -> void:
	var unit: Actor = _piece()
	var target: Actor = _piece()
	_act.move_at([unit], target)
	assert_true(unit.has_command())
	assert_eq(_outcomes("move_at"), [BotUsageLog.OUTCOME_ISSUED])
