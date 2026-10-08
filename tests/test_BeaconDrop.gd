extends GutTest

## The Beacon Drop sanction's beacon: on the ground, standing, blind — and repaired away by an
## enemy that can see it. Rules: gdd/factions/colonial/sanctions/beacon.md, and
## gdd/systems/combat/bombardment.md §Beacons.

const OWN: int = 1
const FOE: int = 2

const EVENT_SCRIPT: Script = preload("res://scripts/scenario/events/event_deploy_beacon.gd")


## Answers the one map question beacon placement asks.
class StubMap:
	extends Map

	func terrain_height_at(_a_world_xz: Vector2) -> float:
		return 0.0


## The two things the event reads off its manager: whose beacon it is, and where it stands.
class StubManager:
	extends ScenarioTriggerManager

	var commanders: Dictionary = {}

	func get_commander(a_id: int) -> Commander:
		return commanders.get(a_id)


var _commanders: Dictionary = {}
var _map: Map
var _manager: StubManager


func before_each() -> void:
	_commanders = {}
	_map = StubMap.new()
	_manager = StubManager.new()
	_manager.map = _map


func after_each() -> void:
	_manager.free()
	_map.free()


func _commander(a_id: int) -> Commander:
	if not _commanders.has(a_id):
		var commander := Commander.new()
		commander.id = a_id
		add_child_autofree(commander)
		_commanders[a_id] = commander
		_manager.commanders[a_id] = commander
	return _commanders[a_id]


func _at(a_xz: Vector2) -> Vector3:
	return Vector3(a_xz.x, 0.0, a_xz.y)


func _piece(a_options: Dictionary, a_commander_id: int, a_xz: Vector2) -> Actor:
	var piece: Actor = FakePieces.make(a_options)
	_commander(a_commander_id).add_child(piece)
	autofree(piece)
	piece.top_level = true
	piece.ownership.commander = _commander(a_commander_id)
	piece.global_position = _at(a_xz)
	return piece


## Drop a beacon for `a_commander_id` at `a_xz`, as the sanction does, and return it.
func _drop(a_commander_id: int, a_xz: Vector2) -> Beacon:
	var event: EventDeployBeacon = EVENT_SCRIPT.new()
	add_child_autofree(event)
	event.global_position = _at(a_xz)
	event.commander_id = a_commander_id
	_commander(a_commander_id)
	event.execute(_manager)
	for node: Node in get_tree().get_nodes_in_group(Beacon.GROUP):
		var beacon: Beacon = Beacon.of(node)
		if beacon != null and not beacon.is_leaving():
			autofree(node)
			return beacon
	return null


# --- Where it lands ------------------------------------------------------------------


## Aimed over a unit, the drop stays on the ground: tagging a unit is Spot's alone.
func test_a_drop_over_an_enemy_tank_stays_on_the_ground() -> void:
	_piece(FakePieces.MACHINE, FOE, Vector2(5, 5))
	var beacon: Beacon = _drop(OWN, Vector2(5, 5))
	assert_not_null(beacon)
	assert_null(beacon.carrier())
	assert_eq(beacon.host().commander_id, OWN)


## Bombards may spend it from anywhere, with no clock to beat.
func test_a_dropped_beacon_is_a_firing_solution() -> void:
	_drop(OWN, Vector2(40, 0))
	assert_true(BombardTargeting.is_spotted(_commander(OWN), _at(Vector2(40, 0))))


func test_a_dropped_beacon_has_no_lifespan() -> void:
	var beacon: Beacon = _drop(OWN, Vector2.ZERO)
	assert_null(beacon.host().get_node_or_null("Lifespan"))


## Blind: no vision node at all, so it never joins the fog's vision sources.
func test_a_dropped_beacon_does_not_see() -> void:
	var beacon: Beacon = _drop(OWN, Vector2.ZERO)
	assert_null(beacon.host().get_node_or_null("VisionRange"))
	assert_false(beacon.host().is_in_group("los"))


func test_a_dropped_beacon_is_stealthed() -> void:
	var beacon: Beacon = _drop(OWN, Vector2.ZERO)
	beacon._physics_process(0.0)
	assert_eq(beacon.host().stealth.state, Stealth.State.STEALTHED)


## The cursor can point at it — which is what lets a repairer be ordered onto it — but the
## player can never select it.
func test_a_beacon_can_be_pointed_at_but_not_selected() -> void:
	var beacon: Beacon = _drop(OWN, Vector2.ZERO)
	var selectable: Selectable = beacon.host().selectable
	assert_not_null(selectable)
	assert_false(selectable.select())


# --- Repaired away -------------------------------------------------------------------


func _repairer(a_commander_id: int) -> Actor:
	return _piece({"speed": 2.0, "repairs": true}, a_commander_id, Vector2(1, 0))


func test_an_enemy_repairer_takes_away_a_beacon_it_can_see() -> void:
	var beacon: Beacon = _drop(OWN, Vector2.ZERO)
	beacon.host().stealth.reveal()
	beacon._physics_process(0.0)
	var repairer: Actor = _repairer(FOE)
	assert_true(Repair.can_repair(repairer, beacon.host()))
	var message := CommandMessage.new(_map, beacon.host())
	Repair.new(message).fulfill_action(repairer)
	assert_true(beacon.is_leaving(), "first touch removes it")


func test_a_stealthed_beacon_cannot_be_repaired_away() -> void:
	var beacon: Beacon = _drop(OWN, Vector2.ZERO)
	beacon._physics_process(0.0)
	assert_false(Repair.can_repair(_repairer(FOE), beacon.host()))


func test_an_owner_does_not_repair_its_own_beacon_away() -> void:
	var beacon: Beacon = _drop(OWN, Vector2.ZERO)
	beacon.host().stealth.reveal()
	beacon._physics_process(0.0)
	assert_false(Repair.can_repair(_repairer(OWN), beacon.host()))


func test_a_beacon_without_a_repairer_is_left_alone() -> void:
	var beacon: Beacon = _drop(OWN, Vector2.ZERO)
	beacon.host().stealth.reveal()
	beacon._physics_process(0.0)
	assert_false(Repair.can_repair(_piece({"speed": 2.0}, FOE, Vector2(1, 0)), beacon.host()))
