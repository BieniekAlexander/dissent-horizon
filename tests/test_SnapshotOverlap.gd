extends GutTest

## A Extractor built on an ExtractionSite leaves BOTH remembered as fog-of-war snapshots at the same
## grid cell (the neutral ExtractionSite and the enemy Extractor are each a "foreign structure").
## CommanderBlackboard._suppress_overlapping_snapshots collapses each cell to one visible
## image, with an ExtractionSite yielding to the Extractor overlaid on it.

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
func _snapshot(
	a_cell: Vector2i, a_is_extraction_site: bool, a_id: int
) -> CommanderBlackboard.Snapshot:
	var node := Sprite3D.new()
	node.visible = true
	_sprites.append(node)
	var snap := CommanderBlackboard.Snapshot.new()
	snap.structure_id = a_id
	snap.cell = a_cell
	snap.is_extraction_site = a_is_extraction_site
	snap.node = node
	_bb._snapshots["%d:%s" % [a_id, a_cell]] = snap
	return snap


func test_extractor_snapshot_hides_the_site_on_the_same_cell() -> void:
	var site := _snapshot(Vector2i(4, 4), true, 1)
	var extractor := _snapshot(Vector2i(4, 4), false, 2)
	_bb._suppress_overlapping_snapshots()
	assert_false(site.node.visible, "extraction site snapshot should hide under the extractor")
	assert_true(extractor.node.visible, "extractor snapshot should remain visible")


func test_site_alone_stays_visible() -> void:
	var site := _snapshot(Vector2i(4, 4), true, 1)
	_bb._suppress_overlapping_snapshots()
	assert_true(site.node.visible, "a lone extraction site snapshot should stay visible")


func test_snapshots_on_different_cells_both_stay_visible() -> void:
	var a := _snapshot(Vector2i(4, 4), false, 1)
	var b := _snapshot(Vector2i(9, 9), false, 2)
	_bb._suppress_overlapping_snapshots()
	assert_true(a.node.visible, "distinct-cell snapshot A should stay visible")
	assert_true(b.node.visible, "distinct-cell snapshot B should stay visible")


func test_equal_rank_collision_keeps_exactly_one_visible() -> void:
	# Two non-site structures somehow on one cell: still collapse to a single image.
	var a := _snapshot(Vector2i(4, 4), false, 1)
	var b := _snapshot(Vector2i(4, 4), false, 2)
	_bb._suppress_overlapping_snapshots()
	var visible_count: int = int(a.node.visible) + int(b.node.visible)
	assert_eq(visible_count, 1, "exactly one of two same-cell snapshots should be visible")
