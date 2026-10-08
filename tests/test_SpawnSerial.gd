extends GutTest

## Every piece takes a spawn serial on first entering play, the same on every run of a seed — how
## a recorded order names a piece. gdd/systems/commands/recording-and-replay.md §The order stream.

## A small scenario the test boots as a harness; what it contains does not matter, only that
## two boots of it agree.
const HARNESS: String = "res://scenes/scenarios/test/test_kamikaze_cluster.tscn"
const BOOT_TICKS: int = 5


func test_serials_count_up_from_one_and_name_the_piece() -> void:
	var scenario := Scenario.new()
	var first := autofree(Entity.new()) as Entity
	var second := autofree(Entity.new()) as Entity
	assert_eq(scenario.register_piece(first), 1)
	assert_eq(scenario.register_piece(second), 2)
	assert_same(scenario.piece_by_serial(2), second)
	assert_null(scenario.piece_by_serial(3), "no piece has taken it yet")
	scenario.free()


func test_a_freed_piece_reads_as_none() -> void:
	var scenario := Scenario.new()
	var piece := Entity.new()
	var serial: int = scenario.register_piece(piece)
	piece.free()
	assert_null(scenario.piece_by_serial(serial))
	scenario.free()


## The property replay rests on: the same scenario numbers the same pieces the same way.
func test_two_boots_of_one_scenario_number_their_pieces_alike() -> void:
	var first: Array = await _serials_of_a_boot()
	var second: Array = await _serials_of_a_boot()
	assert_gt(first.size(), 0, "the harness has pieces")
	assert_eq(second, first)


## [serial, id, node name] for every numbered piece of one boot of the harness, by serial.
func _serials_of_a_boot() -> Array:
	gut.error_tracker.disabled = true
	var scenario := (load(HARNESS) as PackedScene).instantiate() as Scenario
	add_child(scenario)
	for _i: int in BOOT_TICKS:
		await get_tree().physics_frame
	var rows: Array = []
	for node: Node in get_tree().get_nodes_in_group("piece"):
		var piece := node as Entity
		if piece != null and scenario.is_ancestor_of(piece):
			rows.append([piece.spawn_serial, String(piece.id), String(piece.name)])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	scenario.free()
	await get_tree().physics_frame
	gut.error_tracker.disabled = false
	var serials: Array = rows.map(func(row: Array) -> int: return row[0])
	assert_false(serials.has(0), "every piece in play is numbered")
	return rows
