extends GutTest

## SpatialIndex — the pieces' hurtboxes on a grid, which the decide pass reads instead of the
## physics server. Its answer is SU.entities_within's: hurtbox layer in the mask, vertical span
## overlapping the query, footprint within the radius — in serial order and uncapped.
## gdd/systems/commands/the-simulation-step.md §The spatial index.

const OWN: int = 1
const FOE: int = 2
## The scan radius every query here uses.
const RADIUS: float = 6.0

var _index: SpatialIndex = null
var _next_serial: int = 1


func before_each() -> void:
	_index = SpatialIndex.new()
	_next_serial = 1


func _commander(a_id: int) -> Commander:
	var commander := Commander.new()
	commander.id = a_id
	add_child_autofree(commander)
	return commander


func _piece(a_commander: Commander, a_at: Vector3) -> Actor:
	var piece := FakePieces.unit()
	add_child_autofree(piece)
	piece.set_physics_process(false)
	piece.ownership.commander = a_commander
	piece.global_position = a_at
	piece.spawn_serial = _next_serial
	_next_serial += 1
	return piece


func _scan_shape(a_height: float = 2.0) -> CylinderShape3D:
	var shape := CylinderShape3D.new()
	shape.radius = RADIUS
	shape.height = a_height
	return shape


func _hostiles_of(a_scanner: Actor, a_pieces: Array, a_height: float = 2.0) -> Array[Entity]:
	_index.rebuild(a_pieces)
	return _index.entities_within(
		a_scanner.hull(),
		_scan_shape(a_height),
		a_scanner.global_position,
		CollisionLayers.hostile_mask(
			CollisionLayers.TARGETABLE_ANY, a_scanner.allied_commander_ids()
		),
		[a_scanner.hurtbox.get_rid()]
	)


func test_an_enemy_in_range_is_found_and_an_ally_is_not() -> void:
	var own := _commander(OWN)
	var scanner := _piece(own, Vector3.ZERO)
	var ally := _piece(own, Vector3(2, 0, 0))
	var enemy := _piece(_commander(FOE), Vector3(3, 0, 0))
	assert_eq(_hostiles_of(scanner, [scanner, ally, enemy]), [enemy] as Array[Entity])


func test_an_enemy_out_of_range_is_not_found() -> void:
	var scanner := _piece(_commander(OWN), Vector3.ZERO)
	var far := _piece(_commander(FOE), Vector3(RADIUS + 3.0, 0, 0))
	assert_eq(_hostiles_of(scanner, [scanner, far]), [] as Array[Entity])


## A short scan volume ignores what flies over it, as the physics query did.
func test_the_scan_keeps_its_height() -> void:
	var scanner := _piece(_commander(OWN), Vector3.ZERO)
	var above := _piece(_commander(FOE), Vector3(2, 20, 0))
	assert_eq(_hostiles_of(scanner, [scanner, above]), [] as Array[Entity])
	assert_eq(_hostiles_of(scanner, [scanner, above], 100.0), [above] as Array[Entity])


## Every match, in serial order: a crowd cannot fill a cap and hide the one that matters.
func test_a_crowd_comes_back_whole_and_in_serial_order() -> void:
	var scanner := _piece(_commander(OWN), Vector3.ZERO)
	var foe := _commander(FOE)
	var crowd: Array = []
	for i: int in 14:
		crowd.append(_piece(foe, Vector3(cos(TAU * i / 14.0), 0, sin(TAU * i / 14.0)) * 3.0))
	var found: Array[Entity] = _hostiles_of(scanner, [scanner] + crowd)
	assert_eq(found.size(), crowd.size())
	var serials: Array = found.map(func(e: Entity) -> int: return e.spawn_serial)
	var sorted: Array = serials.duplicate()
	sorted.sort()
	assert_eq(serials, sorted)


## A piece off the tree (garrisoned, say) is not indexed.
func test_only_pieces_in_the_tree_are_indexed() -> void:
	var scanner := _piece(_commander(OWN), Vector3.ZERO)
	var gone := _piece(_commander(FOE), Vector3(2, 0, 0))
	var parent: Node = gone.get_parent()
	parent.remove_child(gone)
	assert_eq(_hostiles_of(scanner, [scanner, gone]), [] as Array[Entity])
	parent.add_child(gone)


## Only masks a Hurtbox carries are the index's to answer; the root body's are not.
func test_it_answers_hurtbox_masks_only() -> void:
	assert_true(SpatialIndex.answers(CollisionLayers.TARGETABLE_ANY))
	assert_true(SpatialIndex.answers(CollisionLayers.Mask.LIBERATABLE))
	assert_false(SpatialIndex.answers(CollisionLayers.Mask.STEALTH))
	assert_false(SpatialIndex.answers(CollisionLayers.Mask.MOVEMENT_OBSTRUCTION))


# --- Updating in place -------------------------------------------------------------------


func _hostiles_after_update(a_scanner: Actor, a_pieces: Array) -> Array[Entity]:
	_index.update(a_pieces)
	return _index.entities_within(
		a_scanner.hull(),
		_scan_shape(),
		a_scanner.global_position,
		CollisionLayers.hostile_mask(
			CollisionLayers.TARGETABLE_ANY, a_scanner.allied_commander_ids()
		),
		[a_scanner.hurtbox.get_rid()]
	)


func test_a_piece_that_moves_is_found_where_it_now_stands() -> void:
	var scanner := _piece(_commander(OWN), Vector3.ZERO)
	var enemy := _piece(_commander(FOE), Vector3(40, 0, 0))
	assert_eq(_hostiles_after_update(scanner, [scanner, enemy]), [] as Array[Entity])
	enemy.global_position = Vector3(3, 0, 0)
	assert_eq(_hostiles_after_update(scanner, [scanner, enemy]), [enemy] as Array[Entity])
	enemy.global_position = Vector3(40, 0, 0)
	assert_eq(_hostiles_after_update(scanner, [scanner, enemy]), [] as Array[Entity])


func test_a_piece_no_longer_in_play_is_dropped() -> void:
	var scanner := _piece(_commander(OWN), Vector3.ZERO)
	var enemy := _piece(_commander(FOE), Vector3(3, 0, 0))
	assert_eq(_hostiles_after_update(scanner, [scanner, enemy]).size(), 1)
	assert_eq(_hostiles_after_update(scanner, [scanner]), [] as Array[Entity])


## A change of side moves no Hurtbox, but its layers are re-read every update.
func test_a_capture_is_seen_without_a_move() -> void:
	var own := _commander(OWN)
	var scanner := _piece(own, Vector3.ZERO)
	var enemy := _piece(_commander(FOE), Vector3(3, 0, 0))
	assert_eq(_hostiles_after_update(scanner, [scanner, enemy]).size(), 1)
	enemy.ownership.commander = own
	assert_eq(_hostiles_after_update(scanner, [scanner, enemy]), [] as Array[Entity])


## A Hurtbox resized in place (live tuning) is measured again though it did not move.
func test_a_resized_hurtbox_is_measured_again() -> void:
	var scanner := _piece(_commander(OWN), Vector3.ZERO)
	var enemy := _piece(_commander(FOE), Vector3(RADIUS + 2.0, 0, 0))
	assert_eq(_hostiles_after_update(scanner, [scanner, enemy]), [] as Array[Entity])
	var shape: CylinderShape3D = (
		(enemy.hurtbox.get_node("HurtboxShape") as CollisionShape3D).shape.duplicate()
	)
	shape.radius = 3.0
	(enemy.hurtbox.get_node("HurtboxShape") as CollisionShape3D).shape = shape
	assert_eq(_hostiles_after_update(scanner, [scanner, enemy]), [enemy] as Array[Entity])
