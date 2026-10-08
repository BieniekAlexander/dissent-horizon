extends GutTest

## The belief rules of CommanderBlackboard, driven through update() against a stub commander
## whose vision is supplied rather than derived. Until now these rules ran in no test: every
## bot test seeded belief with _upsert and never aged it, so the three things the blackboard
## actually decides — when a unit belief lapses, when a structure belief is dropped, and
## whether a piece is still believed — were covered only by the code's own comments.
##
## This is the regression net the world-model's TrackTable inherits (gdd/systems/ai/
## world-model.md §L1): every rule below is one the table keeps, and a test here that goes
## red when the table lands is a rule the table broke.


## A Commander whose fog is a list: what it sees now, and where it has vision. The blackboard
## reads nothing else of it but the clock.
class StubCommander:
	extends Commander
	var seen: Array = []
	var clear_at: Array[Vector3] = []
	var now: float = 0.0

	func visible_enemies() -> Array:
		return seen

	func has_vision_at(a_world_pos: Vector3) -> bool:
		return clear_at.any(func(p: Vector3) -> bool: return p.distance_to(a_world_pos) < 0.5)

	func seconds_elapsed() -> float:
		return now


class StubPiece:
	extends Actor

	static func make(a_is_structure: bool) -> StubPiece:
		var piece := StubPiece.new()
		for pair: Array in [
			["Ownership", Ownership.new()],
			["AvoidanceObstacle", NavigationObstacle3D.new()],
			["Veterancy", Veterancy.new()]
		]:
			var node: Node = pair[1]
			node.name = pair[0]
			piece.add_child(node)
		if a_is_structure:
			var structure := Fixture.new()
			structure.name = "Fixture"
			piece.add_child(structure)
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


const FAR: Vector3 = Vector3(40.0, 0.0, 0.0)

var _commander: StubCommander
var _board: CommanderBlackboard


func before_each() -> void:
	_commander = StubCommander.new()
	_commander.id = 1
	add_child_autofree(_commander)
	_board = CommanderBlackboard.new(_commander)


func _piece(a_is_structure: bool, a_at: Vector3) -> Actor:
	var piece: StubPiece = StubPiece.make(a_is_structure)
	add_child_autofree(piece)
	piece.global_position = a_at
	return piece


## One update with `a_pieces` in sight, at time `a_now`.
func _see(a_pieces: Array, a_now: float) -> void:
	_commander.seen = a_pieces
	_commander.now = a_now
	_board.update()


## One update seeing nothing, at time `a_now`, with vision over `a_clear` positions.
func _look(a_clear: Array[Vector3], a_now: float) -> void:
	_commander.seen = []
	_commander.clear_at = a_clear
	_commander.now = a_now
	_board.update()


# ─── SIGHTING ────────────────────────────────────────────────────────────────


func test_a_piece_in_sight_is_believed_at_where_it_stands() -> void:
	var unit: Actor = _piece(false, FAR)
	_see([unit], 10.0)
	var entries: Array = _board.believed()
	assert_eq(entries.size(), 1)
	var entry: CommanderBlackboard.Entry = entries[0]
	assert_eq(entry.last_known_location, FAR)
	assert_eq(entry.last_seen_time, 10.0)
	assert_false(entry.is_structure)
	assert_true(_board.believes(unit.get_instance_id()))


func test_a_re_sighting_refreshes_the_place_and_the_time_without_a_second_entry() -> void:
	var unit: Actor = _piece(false, FAR)
	_see([unit], 10.0)
	unit.global_position = FAR + Vector3(5.0, 0.0, 0.0)
	_see([unit], 20.0)
	assert_eq(_board.believed().size(), 1, "one piece, one belief")
	var entry: CommanderBlackboard.Entry = _board.believed()[0]
	assert_eq(entry.last_known_location, FAR + Vector3(5.0, 0.0, 0.0))
	assert_eq(entry.last_seen_time, 20.0)


func test_a_structure_and_a_unit_are_filed_as_such() -> void:
	_see([_piece(true, FAR), _piece(false, -FAR)], 0.0)
	assert_eq(_board.believed_structures().size(), 1)
	assert_eq(_board.believed_units().size(), 1)


# ─── A UNIT BELIEF LAPSES ON TIME ────────────────────────────────────────────


func test_a_unit_out_of_sight_stays_believed_inside_the_expiry_window() -> void:
	var unit: Actor = _piece(false, FAR)
	_see([unit], 0.0)
	_look([], CommanderBlackboard.BLACKBOARD_EXPIRATION - 1.0)
	assert_true(_board.believes(unit.get_instance_id()), "still inside the window")


func test_a_unit_out_of_sight_lapses_once_the_window_has_passed() -> void:
	var unit: Actor = _piece(false, FAR)
	_see([unit], 0.0)
	_look([], CommanderBlackboard.BLACKBOARD_EXPIRATION + 1.0)
	assert_false(_board.believes(unit.get_instance_id()))
	assert_eq(_board.believed(), [])


func test_a_unit_belief_does_not_lapse_while_it_keeps_being_seen() -> void:
	var unit: Actor = _piece(false, FAR)
	_see([unit], 0.0)
	_see([unit], CommanderBlackboard.BLACKBOARD_EXPIRATION - 1.0)
	_look([], CommanderBlackboard.BLACKBOARD_EXPIRATION + 1.0)
	assert_true(_board.believes(unit.get_instance_id()), "the clock runs from the LAST sighting")


func test_a_unit_belief_is_not_dropped_by_seeing_its_spot_empty() -> void:
	# The blackboard's own rule today: a unit may simply have moved on, so vision of the spot
	# says nothing. Disproving a unit belief is Bot.belief_is_disproved's question, asked of
	# the objective rather than of the table (bot-engagement-fixes.md §What this does NOT
	# explain leaves whether the table should drop it as an open question).
	var unit: Actor = _piece(false, FAR)
	_see([unit], 0.0)
	_look([FAR], 1.0)
	assert_true(_board.believes(unit.get_instance_id()))


func test_a_unit_killed_in_sight_is_dropped_at_once() -> void:
	# The bot watched it die. Kept for the full window, every enemy it killed counted toward
	# the army it believed it faced — measured 2026-10-07 at two to four times the real one.
	var unit: Actor = _piece(false, FAR)
	_see([unit], 0.0)
	var id: int = unit.get_instance_id()
	unit.free()
	_look([FAR], 0.2)
	assert_false(_board.believes(id))


func test_a_unit_that_dies_out_of_sight_is_still_believed() -> void:
	var unit: Actor = _piece(false, FAR)
	_see([unit], 0.0)
	_look([], 1.0)  # it has walked out of view
	var id: int = unit.get_instance_id()
	unit.free()
	_look([], 2.0)
	assert_true(_board.believes(id), "nobody saw it go: the belief stands")


# ─── A STRUCTURE BELIEF IS DROPPED ONLY BY LOOKING ──────────────────────────


func test_a_structure_out_of_sight_is_believed_indefinitely() -> void:
	var structure: Actor = _piece(true, FAR)
	_see([structure], 0.0)
	_look([], CommanderBlackboard.BLACKBOARD_EXPIRATION * 10.0)
	assert_true(_board.believes(structure.get_instance_id()), "structures do not move")


func test_a_structure_is_dropped_when_its_spot_is_in_vision_and_it_is_not_there() -> void:
	var structure: Actor = _piece(true, FAR)
	_see([structure], 0.0)
	_look([FAR], 1.0)
	assert_false(_board.believes(structure.get_instance_id()), "seen gone")


func test_a_structure_still_in_sight_at_its_spot_is_kept() -> void:
	var structure: Actor = _piece(true, FAR)
	_see([structure], 0.0)
	_commander.clear_at = [FAR]
	_see([structure], 1.0)
	assert_true(_board.believes(structure.get_instance_id()))


func test_a_structure_is_dropped_by_vision_not_by_its_node_being_freed() -> void:
	# THE FOG-HONEST HALF. The node is gone and the bot has not looked: it goes on believing.
	# Then it looks, and the belief goes. The table never asks is_instance_valid — a bot that
	# knew a building fell before any unit could see the spot was the leak world-model.md
	# §The fog boundary lists third.
	var structure: Actor = _piece(true, FAR)
	_see([structure], 0.0)
	var id: int = structure.get_instance_id()
	structure.free()
	_look([], 1.0)
	assert_true(_board.believes(id), "not looked: still believed, whatever happened to the node")
	_look([FAR], 2.0)
	assert_false(_board.believes(id), "looked, and it is not there")


func test_vision_elsewhere_drops_nothing() -> void:
	var structure: Actor = _piece(true, FAR)
	_see([structure], 0.0)
	_look([-FAR], 1.0)
	assert_true(_board.believes(structure.get_instance_id()))


# ─── BELIEVES ────────────────────────────────────────────────────────────────


func test_an_unknown_id_is_not_believed() -> void:
	assert_false(_board.believes(12345))
