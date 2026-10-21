extends GutTest

## THE LEASH (Alex, 2026-10-19, SC2-style): a piece that takes up an attack on its own — idle
## aggro, or answering fire — may stray Attack.LEASH_DISTANCE from where it stood; past that it
## drops the target and walks back. An attack it was ORDERED into has no leash.

const UNIT: Dictionary = {"speed": 2.0, "vision": 8.0, "weapon": {"ground": 6.0}}


func _pair() -> Array[Actor]:
	var hunter := FakePieces.make(UNIT) as Actor
	add_child_autofree(hunter)
	var prey := FakePieces.make(UNIT) as Actor
	add_child_autofree(prey)
	return [hunter, prey]


func _leashed_attack(a_prey: Actor, a_origin: Vector3) -> Attack:
	var message := CommandMessage.new(null, a_prey, null)
	message.persist = false
	message.leash_origin = a_origin
	return Attack.new(message)


func test_within_the_leash_the_chase_goes_on() -> void:
	var pair: Array[Actor] = _pair()
	pair[0].global_position = Vector3(4, 0, 0)
	var attack: Attack = _leashed_attack(pair[1], Vector3.ZERO)
	assert_false(attack.has_left_leash(pair[0]), "4 from where it stood")


func test_past_the_leash_it_walks_back_to_where_it_stood() -> void:
	var pair: Array[Actor] = _pair()
	pair[0].global_position = Vector3(5.5, 0, 0)
	var attack: Attack = _leashed_attack(pair[1], Vector3(0, 0, 0))
	assert_true(attack.has_left_leash(pair[0]))
	var next: Variant = attack.get_updated_state(pair[0])
	assert_true(next is MoveCommand and not (next is Attack), "a plain walk, the target dropped")
	assert_eq((next as MoveCommand).message.world_position, Vector3.ZERO, "back to its spot")


func test_an_ordered_attack_has_no_leash() -> void:
	var pair: Array[Actor] = _pair()
	pair[0].global_position = Vector3(50, 0, 0)
	var attack := Attack.new(CommandMessage.new(null, pair[1], null))
	assert_false(attack.has_left_leash(pair[0]))


func test_a_piece_that_cannot_move_is_never_leashed() -> void:
	var pair: Array[Actor] = _pair()
	pair[0].global_position = Vector3(9, 0, 0)
	pair[0].movement = null
	pair[0].locomotion_component = null
	var attack: Attack = _leashed_attack(pair[1], Vector3.ZERO)
	assert_false(attack.has_left_leash(pair[0]))


func test_idle_aggro_and_retaliation_leash_to_where_the_piece_stands() -> void:
	var pair: Array[Actor] = _pair()
	pair[0].global_position = Vector3(3, 0, 1)
	var attack: Attack = Attack.new(CommandMessage.new(null, pair[1], null))
	pair[0]._leash_to_here(attack)
	assert_eq(attack.message.leash_origin, Vector3(3, 0, 1))


func test_a_copied_message_keeps_its_leash() -> void:
	var message := CommandMessage.new(null, null, null, Vector3(1, 0, 1))
	message.leash_origin = Vector3(2, 0, 2)
	assert_eq(CommandMessage.deep_copy(message).leash_origin, Vector3(2, 0, 2))
