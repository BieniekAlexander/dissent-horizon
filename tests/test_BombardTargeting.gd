extends GutTest

## "May this commander drop a shell here?" — the rule the whole Colonial bombardment
## system turns on. A Bombard's reach is not distance but VISION BY PROXY: it can hit
## anywhere on the map, provided its own side is spotting the ground.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_BombardTargeting.gd -gexit

const UNIT: Dictionary = FakePieces.PLAIN

const OWN: int = 1
const FOE: int = 2

var _commanders: Dictionary = {}


func before_each() -> void:
	_commanders = {}


func _commander(a_id: int) -> Commander:
	if not _commanders.has(a_id):
		var commander := Commander.new()
		commander.id = a_id
		add_child_autofree(commander)
		_commanders[a_id] = commander
	return _commanders[a_id]


func _at(a_xz: Vector2) -> Vector3:
	return Vector3(a_xz.x, 0.0, a_xz.y)


## A beacon owned by `commander_id`, standing at `xz`.
func _beacon(a_commander_id: int, a_xz: Vector2) -> Beacon:
	var piece: Entity = Beacon.SCENE.instantiate()
	add_child_autofree(piece)
	piece.top_level = true
	piece.ownership.commander = _commander(a_commander_id)
	piece.global_position = _at(a_xz)
	return Beacon.of(piece)


## A real unit carrying a BeaconRange of `radius`, owned by `commander_id`, at `xz`.
## Built from a shipped scene rather than a bare Commandable: the class hard-requires a
## scene rig (HP bar, AvoidanceObstacle, Ownership) a hand-built node cannot supply.
func _range_carrier(a_commander_id: int, a_xz: Vector2, a_radius: float) -> Commandable:
	var unit: Commandable = FakePieces.unit(UNIT)
	_commander(a_commander_id).add_child(unit)
	autofree(unit)
	unit.top_level = true
	unit.ownership.commander = _commander(a_commander_id)
	unit.global_position = _at(a_xz)
	var beacon_range := BeaconRange.new()
	beacon_range.name = "BeaconRange"
	beacon_range.radius = a_radius
	unit.add_child(beacon_range)
	return unit


# --- Nothing spotted ------------------------------------------------------------


func test_unspotted_ground_cannot_be_bombarded() -> void:
	assert_false(BombardTargeting.is_spotted(_commander(OWN), _at(Vector2(50, 50))))


func test_a_null_commander_spots_nothing() -> void:
	# Unlike Sanction.can_target, there is no "no rig" fallback here: a strike with no
	# commander behind it has no side to be spotting for it.
	assert_false(BombardTargeting.is_spotted(null, Vector3.ZERO))


# --- Beacons --------------------------------------------------------------------


func test_a_beacon_spots_the_ground_it_stands_on() -> void:
	_beacon(OWN, Vector2(20, 20))
	assert_true(BombardTargeting.is_spotted(_commander(OWN), _at(Vector2(20, 20))))


func test_a_beacon_spots_a_small_area_around_itself() -> void:
	# A player clicking a beacon is aiming at a target BESIDE it, not at the marker.
	_beacon(OWN, Vector2(20, 20))
	var just_inside: Vector2 = Vector2(20, 20 + Beacon.STRIKE_RADIUS - 0.1)
	var just_outside: Vector2 = Vector2(20, 20 + Beacon.STRIKE_RADIUS + 0.1)
	assert_true(BombardTargeting.is_spotted(_commander(OWN), _at(just_inside)))
	assert_false(BombardTargeting.is_spotted(_commander(OWN), _at(just_outside)))


func test_an_enemy_beacon_spots_nothing_for_you() -> void:
	_beacon(FOE, Vector2(20, 20))
	assert_false(
		BombardTargeting.is_spotted(_commander(OWN), _at(Vector2(20, 20))),
		"a firing solution belongs to the side that placed it"
	)


func test_a_beacon_is_the_thing_a_strike_spends() -> void:
	var beacon := _beacon(OWN, Vector2(20, 20))
	assert_eq(BombardTargeting.source_at(_commander(OWN), _at(Vector2(20, 20))), beacon)


func test_the_nearest_beacon_is_the_one_spent() -> void:
	var far := _beacon(OWN, Vector2(20, 22))
	var near := _beacon(OWN, Vector2(20, 20.5))
	assert_eq(BombardTargeting.source_at(_commander(OWN), _at(Vector2(20, 20))), near)
	assert_true(is_instance_valid(far), "and the other is left standing")


func test_a_dismissed_beacon_stops_spotting() -> void:
	var beacon := _beacon(OWN, Vector2(20, 20))
	beacon.dismiss()
	assert_false(
		BombardTargeting.is_spotted(_commander(OWN), _at(Vector2(20, 20))),
		"queue_free is end-of-frame, so the check must skip a beacon on its way out"
	)


func test_dismiss_announces_itself_once() -> void:
	# Spot listens for this to know its work is done. A shot and an expiry landing on the
	# same frame must not notify twice.
	var beacon := _beacon(OWN, Vector2(0, 0))
	watch_signals(beacon)
	beacon.dismiss()
	beacon.dismiss()
	assert_signal_emit_count(beacon, "spent", 1)


# --- Beacon ranges --------------------------------------------------------------


func test_a_beacon_range_spots_everything_around_its_carrier() -> void:
	_range_carrier(OWN, Vector2(0, 0), 20.0)
	assert_true(BombardTargeting.is_spotted(_commander(OWN), _at(Vector2(19, 0))))
	assert_false(BombardTargeting.is_spotted(_commander(OWN), _at(Vector2(21, 0))))


func test_a_beacon_range_is_measured_on_the_ground() -> void:
	# An aircraft carrying one should spot the ground beneath it, not a sphere around it.
	var carrier := _range_carrier(OWN, Vector2(0, 0), 5.0)
	carrier.global_position = Vector3(0.0, 40.0, 0.0)
	assert_true(BombardTargeting.is_spotted(_commander(OWN), _at(Vector2(4, 0))))


func test_an_enemy_beacon_range_spots_nothing_for_you() -> void:
	_range_carrier(FOE, Vector2(0, 0), 20.0)
	assert_false(BombardTargeting.is_spotted(_commander(OWN), _at(Vector2(5, 0))))


func test_a_beacon_range_is_never_spent() -> void:
	# The persistent half: unlimited strikes, nothing to consume.
	_range_carrier(OWN, Vector2(0, 0), 20.0)
	assert_null(
		BombardTargeting.source_at(_commander(OWN), _at(Vector2(5, 0))),
		"there is nothing for the shot to consume"
	)
	assert_true(
		BombardTargeting.is_spotted(_commander(OWN), _at(Vector2(5, 0))),
		"and it still spots the ground afterwards"
	)


# --- The two together -----------------------------------------------------------


func test_a_permanent_range_is_preferred_over_a_beacon() -> void:
	# The load-bearing ordering: spending a beacon the player walked a Recruit across the
	# map to place, when a free solution already covered the spot, wastes the more
	# expensive of the two resources.
	var beacon := _beacon(OWN, Vector2(5, 0))
	_range_carrier(OWN, Vector2(0, 0), 20.0)
	assert_true(BombardTargeting.is_spotted(_commander(OWN), _at(Vector2(5, 0))))
	assert_null(
		BombardTargeting.source_at(_commander(OWN), _at(Vector2(5, 0))),
		"the covered point spends nothing"
	)
	assert_true(is_instance_valid(beacon), "so the beacon is still standing")


func test_a_beacon_outside_every_range_is_still_spent() -> void:
	var beacon := _beacon(OWN, Vector2(60, 0))
	_range_carrier(OWN, Vector2(0, 0), 20.0)
	assert_eq(BombardTargeting.source_at(_commander(OWN), _at(Vector2(60, 0))), beacon)
