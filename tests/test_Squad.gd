extends GutTest

## THE SQUAD'S DISPATCH LOOP, which the Bot's military and a mission's ScenarioTactic share:
## a new policy reaches every member, the same policy reaches only a member that went idle
## or joined since, and a member busy with its order is left alone
## (gdd/systems/ai/squads-and-relations.md §Squads).


class StubPiece:
	extends Commandable

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


## Records who it was issued to, and gives each one a standing order so it is not idle.
class RecordingPolicy:
	extends SquadPolicy
	var issued: Array = []  # one entry per call: the members handed over
	var label: String

	func _init(a_label: String) -> void:
		label = a_label

	func issue(a_members: Array) -> void:
		issued.append(a_members.duplicate())
		for unit: Commandable in a_members:
			unit.update_commands(MoveCommand.new(CommandMessage.new(null, null, null, Vector3.ONE)))

	func same_as(a_other: SquadPolicy) -> bool:
		return a_other is RecordingPolicy and (a_other as RecordingPolicy).label == label


var _squad: Squad


func before_each() -> void:
	_squad = Squad.new(&"test")


func _unit() -> Commandable:
	var piece: StubPiece = StubPiece.make()
	add_child_autofree(piece)
	return piece


func test_a_new_policy_reaches_every_member() -> void:
	var a: Commandable = _unit()
	var b: Commandable = _unit()
	_squad.add_all([a, b])
	var policy := RecordingPolicy.new("go")
	_squad.policy = policy
	_squad.tick()
	assert_eq(policy.issued.size(), 1, "one call")
	assert_eq(policy.issued[0].size(), 2, "carrying both")


func test_the_same_policy_reaches_only_a_member_that_went_idle() -> void:
	var a: Commandable = _unit()
	var b: Commandable = _unit()
	_squad.add_all([a, b])
	var policy := RecordingPolicy.new("go")
	_squad.policy = policy
	_squad.tick()
	_squad.policy = RecordingPolicy.new("go")  # the same order, a new object
	_squad.tick()
	assert_eq(policy.issued.size(), 1, "nobody idle, nobody re-ordered")
	a.update_commands(null)
	_squad.tick()
	assert_eq((_squad.policy as RecordingPolicy).issued, [[a]], "only the idle one")


func test_a_member_that_joins_is_ordered_on_the_next_tick_whatever_it_is_doing() -> void:
	var a: Commandable = _unit()
	_squad.add(a)
	var policy := RecordingPolicy.new("go")
	_squad.policy = policy
	_squad.tick()
	var late: Commandable = _unit()
	late.update_commands(MoveCommand.new(CommandMessage.new(null, null, null, Vector3.ZERO)))
	_squad.add(late)
	_squad.tick()
	assert_eq(policy.issued.size(), 2)
	assert_eq(policy.issued[1], [late], "busy, but new to this policy")


func test_a_changed_policy_redirects_a_busy_member() -> void:
	var a: Commandable = _unit()
	_squad.add(a)
	_squad.policy = RecordingPolicy.new("go")
	_squad.tick()
	var other := RecordingPolicy.new("stop")
	_squad.policy = other
	_squad.tick()
	assert_eq(other.issued, [[a]], "a real change of posture reaches everyone")


func test_an_ineligible_member_is_left_alone_and_picked_up_when_eligible_again() -> void:
	var a: Commandable = _unit()
	var claimed: Commandable = _unit()
	_squad.add_all([a, claimed])
	var free: Dictionary = {a: true}
	_squad.eligible = func(unit: Commandable) -> bool: return free.has(unit)
	var policy := RecordingPolicy.new("go")
	_squad.policy = policy
	_squad.tick()
	assert_eq(policy.issued, [[a]], "the claimed member is still a member, just not ours to order")
	free[claimed] = true
	_squad.tick()
	assert_eq(policy.issued[1], [claimed], "released: ordered without waiting to be idle")


func test_a_dead_member_drops_out_as_it_is_read() -> void:
	var a: Commandable = _unit()
	var dead: StubPiece = StubPiece.make()
	add_child(dead)
	_squad.add_all([a, dead])
	dead.free()
	assert_eq(_squad.members(), [a])
	assert_eq(_squad.size(), 1)


func test_absorb_moves_every_member_across() -> void:
	var a: Commandable = _unit()
	var b: Commandable = _unit()
	var other := Squad.new(&"other")
	other.add_all([a, b])
	var moved: Array = _squad.absorb(other)
	assert_eq(moved.size(), 2)
	assert_true(other.is_empty())
	assert_true(_squad.has(a) and _squad.has(b))


func test_the_centroid_is_the_members_mean_and_zero_for_nobody() -> void:
	assert_eq(_squad.centroid(), Vector3.ZERO)
	var a: Commandable = _unit()
	var b: Commandable = _unit()
	a.global_position = Vector3(0.0, 0.0, 0.0)
	b.global_position = Vector3(10.0, 0.0, 0.0)
	_squad.add_all([a, b])
	assert_eq(_squad.centroid(), Vector3(5.0, 0.0, 0.0))


func test_a_commander_lists_the_squads_kept_on_its_behalf() -> void:
	var commander: Commander = autofree(Commander.new())
	var squad: Squad = commander.squads.create(&"wave")
	assert_eq(commander.squads.all(), [squad])
	commander.squads.release(squad)
	assert_eq(commander.squads.count(), 0)
