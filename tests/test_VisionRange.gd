extends GutTest

## Where a piece's vision stands, and when it sees: a BODY vision rides on its piece and always
## sees; an ORBIT vision stands at the centre of its piece's orbit and sees only while the piece
## holds it — on a sortie, only on station.
## Rules: gdd/systems/combat/range-buckets.md §Vision from the orbit.
##
## Run with:
##   python3 tools/gut_shards/gut_shards.py VisionRange


class FakeMap:
	extends Map
	var area: PlayArea = null

	func play_area() -> PlayArea:
		return area

	func terrain_height_at(_a_world_xz: Vector2) -> float:
		return 0.0


const HALF: Vector2 = Vector2(20.0, 20.0)
const STATION: Vector3 = Vector3(5.0, 0.0, 0.0)
const HOME: Vector3 = Vector3(-30.0, 0.0, 0.0)
const ANCHOR: Vector3 = Vector3(-4.0, 0.0, 7.0)
const STATION_SECONDS: float = 1.0
const AIRCRAFT: Dictionary = {"aerial": true, "flying": true, "vision": 8.0}

var _map: FakeMap


func before_each() -> void:
	_map = autofree(FakeMap.new())
	_map.area = PlayArea.axis_aligned(Vector2.ZERO, HALF)


func _piece(a_options: Dictionary, a_origin: VisionRange.Origin) -> Actor:
	var piece: Actor = FakePieces.unit(a_options)
	(piece.get_node("VisionRange") as VisionRange).origin = a_origin
	add_child_autofree(piece)
	return piece


func _vision(a_piece: Actor) -> VisionRange:
	return a_piece.vision_range_shape as VisionRange


func test_a_body_vision_always_sees() -> void:
	var piece: Actor = _piece({"speed": 2.0, "vision": 8.0}, VisionRange.Origin.BODY)
	assert_true(piece.grants_vision())
	assert_false(_vision(piece).top_level, "it rides on its piece")


func test_an_orbit_vision_on_a_piece_that_does_not_orbit_is_blind() -> void:
	var piece: Actor = _piece({"speed": 2.0, "vision": 8.0}, VisionRange.Origin.ORBIT)
	assert_false(piece.grants_vision())


func test_an_orbit_vision_stands_at_the_orbit_centre() -> void:
	var piece: Actor = _piece(AIRCRAFT, VisionRange.Origin.ORBIT)
	piece.global_position = Vector3(10.0, 0.0, -3.0)
	piece.aerial.set_anchor(ANCHOR)
	_vision(piece)._physics_process(0.0)
	assert_true(piece.grants_vision())
	assert_eq(VU.in_xz(_vision(piece).global_position), VU.in_xz(ANCHOR))


func test_an_orbit_vision_on_a_sortie_is_blind_in_transit() -> void:
	var piece: Actor = _piece(AIRCRAFT, VisionRange.Origin.ORBIT)
	piece.global_position = HOME
	var sortie: Sortie = Sortie.launch(piece, _map, HOME, STATION, STATION_SECONDS)
	sortie.set_physics_process(false)
	assert_false(piece.grants_vision(), "inbound")
	piece.global_position = STATION
	sortie._physics_process(0.0)
	assert_eq(sortie.phase, Sortie.Phase.ON_STATION)
	assert_true(piece.grants_vision(), "on station")
	_vision(piece)._physics_process(0.0)
	assert_eq(VU.in_xz(_vision(piece).global_position), VU.in_xz(STATION))
	sortie._leave(piece)
	assert_false(piece.grants_vision(), "outbound")
