extends GutTest

## A Mine built on a Deposit leaves BOTH remembered as fog-of-war snapshots at the same
## grid cell (the neutral Deposit and the enemy Mine are each a "foreign structure").
## CommanderBlackboard._suppress_overlapping_snapshots collapses each cell to one visible
## image, with a Deposit yielding to the Mine overlaid on it.

var _cmdr: Commander
var _bb: CommanderBlackboard
var _sprites: Array[Sprite3D] = []


func before_each() -> void:
	_cmdr = Commander.new()
	_bb = CommanderBlackboard.new(_cmdr)
	_sprites = []


func after_each() -> void:
	for s: Sprite3D in _sprites:
		s.free()
	_cmdr.free()


## Build a visible snapshot at `cell` and register it under a unique key.
func _snapshot(cell: Vector2i, is_deposit: bool, id: int) -> CommanderBlackboard.Snapshot:
	var node := Sprite3D.new()
	node.visible = true
	_sprites.append(node)
	var snap := CommanderBlackboard.Snapshot.new()
	snap.structure_id = id
	snap.cell = cell
	snap.is_deposit = is_deposit
	snap.node = node
	_bb._snapshots["%d:%s" % [id, cell]] = snap
	return snap


func test_mine_snapshot_hides_the_deposit_on_the_same_cell() -> void:
	var deposit := _snapshot(Vector2i(4, 4), true, 1)
	var mine := _snapshot(Vector2i(4, 4), false, 2)
	_bb._suppress_overlapping_snapshots()
	assert_false(deposit.node.visible, "deposit snapshot should hide under the mine")
	assert_true(mine.node.visible, "mine snapshot should remain visible")


func test_deposit_alone_stays_visible() -> void:
	var deposit := _snapshot(Vector2i(4, 4), true, 1)
	_bb._suppress_overlapping_snapshots()
	assert_true(deposit.node.visible, "a lone deposit snapshot should stay visible")


func test_snapshots_on_different_cells_both_stay_visible() -> void:
	var a := _snapshot(Vector2i(4, 4), false, 1)
	var b := _snapshot(Vector2i(9, 9), false, 2)
	_bb._suppress_overlapping_snapshots()
	assert_true(a.node.visible, "distinct-cell snapshot A should stay visible")
	assert_true(b.node.visible, "distinct-cell snapshot B should stay visible")


func test_equal_rank_collision_keeps_exactly_one_visible() -> void:
	# Two non-deposit structures somehow on one cell: still collapse to a single image.
	var a := _snapshot(Vector2i(4, 4), false, 1)
	var b := _snapshot(Vector2i(4, 4), false, 2)
	_bb._suppress_overlapping_snapshots()
	var visible_count: int = int(a.node.visible) + int(b.node.visible)
	assert_eq(visible_count, 1, "exactly one of two same-cell snapshots should be visible")
