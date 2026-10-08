extends GutTest

## A `self_destruct` weapon is its wielder blowing itself up: firing it kills the wielder on
## that tick, and the wielder's death, however it comes, sets off the blast where it stands —
## exactly once. Rule: gdd/systems/combat/aerial-operations/attack-runs.md §A rammer strikes
## its target's top, and is spent on contact. Every piece is a fake (tests/_fake_pieces.gd).


func _wielder(a_self_destruct: bool) -> Actor:
	var commander := Commander.new()
	commander.id = 1
	add_child_autofree(commander)
	var piece := FakePieces.unit({"weapon": {"ground": 0.5, "projectile": true}}) as Actor
	var weapon: Weapon = piece.get_node("Loadout").get_child(0) as Weapon
	weapon.projectile_scene = FakePieces.emission_scene()
	weapon.self_destruct = a_self_destruct
	add_child_autofree(piece)
	piece.ownership.commander = commander
	piece.global_position = Vector3(3.0, 1.5, 4.0)
	return piece


func _weapon(a_piece: Actor) -> Weapon:
	return a_piece.weapon_inventory.get_weapons()[0]


## Emissions launched for `a_commander`: each is parented to the firing commander.
func _emissions(a_commander: Commander) -> Array:
	var is_emission: Callable = func(n: Node) -> bool: return Payload.of(n) != null
	return a_commander.get_children().filter(is_emission)


func test_firing_kills_the_wielder_and_sets_off_one_blast_where_it_is() -> void:
	var piece: Actor = _wielder(true)
	var commander: Commander = piece.commander
	var at: Vector3 = piece.global_position
	var target: Actor = FakePieces.unit()
	add_child_autofree(target)
	_weapon(piece).fire(piece, target)
	assert_true(piece.is_queued_for_deletion(), "the airframe is spent on the tick it strikes")
	var blasts: Array = _emissions(commander)
	assert_eq(blasts.size(), 1, "one blast — nothing flies, nothing goes off twice")
	if blasts.size() == 1:
		assert_almost_eq((blasts[0] as Node3D).global_position, at, Vector3.ONE * 0.01)


func test_a_wielder_killed_otherwise_still_explodes_once() -> void:
	var piece: Actor = _wielder(true)
	var commander: Commander = piece.commander
	piece._fire_entity_occurrence(Entity.EntityOccurrence.ON_DEATH)
	piece._fire_entity_occurrence(Entity.EntityOccurrence.ON_DEATH)
	assert_eq(_emissions(commander).size(), 1, "shot down, it explodes; a second notice does not")


func test_an_ordinary_weapon_does_nothing_at_death() -> void:
	var piece: Actor = _wielder(false)
	var commander: Commander = piece.commander
	piece._fire_entity_occurrence(Entity.EntityOccurrence.ON_DEATH)
	assert_eq(_emissions(commander).size(), 0)
