extends GutTest

## The HP bar's fill must drain rightward from a FIXED left edge.
##
## Regression guard: the fill used to be shrunk with the node's scale and re-anchored
## with the node's position. Both are model-transform writes, and a billboarded
## Sprite3D keeps its translation in WORLD space while turning the quad to face the
## camera — so the fill slid diagonally off the bar as damage accumulated. The
## geometry now lives in the sprite's own 2D plane (region_rect + offset), which the
## billboard carries along, and the node transform is left alone entirely.

var _unit: Node
var _fill: Sprite3D
var _width: float


func before_each() -> void:
	_unit = FakePieces.unit({"hp": 80.0})
	add_child_autofree(_unit)   # in-tree so _ready wires hp_changed
	_fill = _unit.get_node("HPBar/HPBarFill")
	_width = _fill.texture.get_size().x


func _damage_to(a_fraction: float) -> void:
	var defense: Node = _unit.get_node("Defense")
	defense.apply_damage(defense.hp - defense.hp_max * a_fraction)


## Left edge of the quad, in texture pixels: a centred region shifted by offset.
func _left_edge() -> float:
	return -_fill.region_rect.size.x / 2.0 + _fill.offset.x


func test_left_edge_never_moves_as_damage_accumulates() -> void:
	for step in range(10, -1, -1):
		_damage_to(step / 10.0)
		assert_almost_eq(_left_edge(), -_width / 2.0, 0.001,
			"left edge stays put at %d%% health" % (step * 10))


func test_width_tracks_the_health_fraction() -> void:
	for step in range(10, -1, -1):
		_damage_to(step / 10.0)
		assert_almost_eq(_fill.region_rect.size.x, _width * step / 10.0, 0.001,
			"fill width at %d%% health" % (step * 10))


func test_node_transform_is_never_touched() -> void:
	# The actual regression: any write here is a world-space move the billboard
	# does not rotate with.
	for step in range(10, -1, -1):
		_damage_to(step / 10.0)
		assert_eq(_fill.position, Vector3.ZERO, "position untouched at %d%%" % (step * 10))
		assert_eq(_fill.scale, Vector3.ONE, "scale untouched at %d%%" % (step * 10))


func test_full_health_shows_the_whole_bar_unshifted() -> void:
	_damage_to(1.0)
	assert_almost_eq(_fill.region_rect.size.x, _width, 0.001)
	assert_almost_eq(_fill.offset.x, 0.0, 0.001)
