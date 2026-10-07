extends GutTest

## CRUSH IS LETHALITY (gdd/systems/ai/ontology.md §Affordances, decided 2026-10-06): a unit
## that outsizes another kills it on contact, so BotTargeting retargets a crusher the way it
## retargets a shooter — and the order it issues is the controls' own run-over, a Move AT the
## target (BotActuator.move_at), which follows it. Before this the truck was never a
## targeting candidate (no weapon), so it ran over only what it happened to drive through, and
## stood beside infantry it could have flattened (observed 2026-10-06 on main).


class StubPiece:
	extends Commandable

	static func make() -> StubPiece:
		var piece := StubPiece.new()
		for pair: Array in [
			["Ownership", Ownership.new()],
			["AvoidanceObstacle", NavigationObstacle3D.new()],
			["Veterancy", Veterancy.new()],
			["Hurtbox", StaticBody3D.new()]
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


## A Bot whose physics overlap is a list: everything above it — the candidate filter, the
## signals, the order — is the real targeting.
class StubBot:
	extends Bot
	var enemies: Array = []

	func visible_enemies_near(_a_position: Vector3, _a_radius: float) -> Array:
		return enemies

	func is_suicide_aoe_unit(_a_unit: Commandable) -> bool:
		return false


class RecordingActuator:
	extends BotActuator
	var attacks: Array = []
	var run_overs: Array = []  # [{"units": Array, "target": Entity}]

	func attack(a_units: Array, a_target: Entity, _a_persist: bool = true) -> void:
		attacks.append({"units": a_units.duplicate(), "target": a_target})

	func move_at(a_units: Array, a_target: Entity) -> void:
		run_overs.append({"units": a_units.duplicate(), "target": a_target})


var _scenario: Scenario
var _bot: StubBot
var _foe: Commander
var _act: RecordingActuator
var _targeting: BotTargeting


func before_each() -> void:
	_scenario = autofree(Scenario.new()) as Scenario
	_bot = _commander(StubBot.new(), 1) as StubBot
	_foe = _commander(Commander.new(), 2)
	_scenario.commanders = [_bot, _foe]
	_act = RecordingActuator.new(null)
	_targeting = BotTargeting.new(_bot, _act)


func _commander(a_commander: Commander, a_id: int) -> Commander:
	a_commander.id = a_id
	a_commander.initialize(null, _scenario)
	add_child_autofree(a_commander)
	return a_commander


## A piece of `a_owner` at `a_at` moving in crush class `a_class`, with 100 HP.
func _mover(a_owner: Commander, a_at: Vector3, a_class: Movement.CrushClass) -> Commandable:
	var piece: StubPiece = StubPiece.make()
	a_owner.add_child(piece)
	piece.ownership.commander = a_owner
	piece.global_position = a_at
	var movement := autofree(Movement.new()) as Movement
	movement.crush_class = a_class
	piece.movement = movement
	var defense := autofree(Defense.new()) as Defense
	defense.hp_max = 100.0
	defense.hp = 100.0
	piece.defense = defense
	piece.hurtbox.collision_layer |= CollisionLayers.Mask.TARGETABLE_GROUND
	return piece


func _truck(a_at: Vector3 = Vector3.ZERO) -> Commandable:
	return _mover(_bot, a_at, Movement.CrushClass.LARGE)


func _infantry(a_at: Vector3) -> Commandable:
	return _mover(_foe, a_at, Movement.CrushClass.TINY)


func test_an_unarmed_crusher_is_sent_to_run_over_infantry_in_reach() -> void:
	var truck: Commandable = _truck()
	var soldier: Commandable = _infantry(Vector3(3.0, 0.0, 0.0))
	_bot.enemies = [soldier]
	_targeting.tick()
	assert_eq(_act.attacks, [], "nothing to shoot with")
	assert_eq(_act.run_overs.size(), 1, "one run-over")
	assert_eq(_act.run_overs[0]["units"], [truck])
	assert_eq(_act.run_overs[0]["target"], soldier)


func test_a_crusher_ignores_what_it_cannot_crush() -> void:
	_truck()
	var tank: Commandable = _mover(_foe, Vector3(3.0, 0.0, 0.0), Movement.CrushClass.LARGE)
	_bot.enemies = [tank]
	_targeting.tick()
	assert_eq(_act.run_overs, [], "an equal class is not run over")


func test_a_run_over_in_progress_is_a_held_engagement() -> void:
	# The claim and the current target both see the run-over, so the truck is not released
	# and re-ordered every think, and a second candidate must clear the switch margin.
	var truck: Commandable = _truck()
	var soldier: Commandable = _infantry(Vector3(3.0, 0.0, 0.0))
	_bot.enemies = [soldier]
	_targeting.tick()
	var cmd := MoveCommand.new(CommandMessage.new(null, soldier, null, soldier.global_position))
	truck.update_commands(cmd)
	assert_eq(_targeting._current_target(truck), soldier, "the run-over's target is current")
	_targeting.tick()
	assert_eq(_act.run_overs.size(), 1, "not re-issued while it stands")
	assert_true(_targeting.claims.owns(truck, BotTargeting.CLAIM_OWNER), "and the claim is held")


func test_a_crush_scores_as_a_decisive_matchup() -> void:
	var truck: Commandable = _truck()
	var soldier: Commandable = _infantry(Vector3(3.0, 0.0, 0.0))
	assert_eq(
		BotTargeting.effectiveness_signal(truck, soldier), BotTargeting.CRUSH_EFFECTIVENESS_SIGNAL
	)
	assert_gt(BotTargeting.CRUSH_EFFECTIVENESS_SIGNAL, 1.0, "above a neutral shot")
	var tank: Commandable = _mover(_foe, Vector3(3.0, 0.0, 0.0), Movement.CrushClass.LARGE)
	assert_eq(BotTargeting.effectiveness_signal(truck, tank), 0.0, "and nothing without a gun")
