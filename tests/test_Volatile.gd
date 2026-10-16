extends GutTest

## A VOLATILE piece throws its blast where it died: once, unattributed, and only on a death
## (expiring leaves nothing). The fuse and the cascade are the emission's own phases, so they
## are not driven here. Rules: gdd/systems/combat/environmental-pieces.md §Hazards.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Volatile.gd -gexit

const NEUTRAL: int = 0
const OWN: int = 1


## Answers what a dying feature asks of its map; nothing here is registered on a grid.
class StubMap:
	extends Map

	func terrain_height_at(_a_world_xz: Vector2) -> float:
		return 0.0

	func remove_structure(_a_entity: Entity, _a_rebuild_nav: bool = true) -> void:
		pass


var _map: Map
var _commanders: Dictionary = {}


func before_each() -> void:
	_map = StubMap.new()
	_commanders = {}


func after_each() -> void:
	_map.free()


func _commander(a_id: int) -> Commander:
	if not _commanders.has(a_id):
		var commander := Commander.new()
		commander.id = a_id
		add_child_autofree(commander)
		_commanders[a_id] = commander
	return _commanders[a_id]


## A neutral hazard at `a_at`, armed with a fake blast (or none).
func _hazard(a_at: Vector3, a_blast: PackedScene) -> Entity:
	var piece: Entity = FakePieces.feature({"hp": 100.0})
	var volatile := Volatile.new()
	volatile.name = "Volatile"
	volatile.blast_scene = a_blast
	piece.add_child(volatile)
	piece.initialize(_map, _commander(NEUTRAL))
	autofree(piece)
	piece.global_position = a_at
	return piece


## The emissions a commander holds — a blast is put into play under the hazard's owner.
func _blasts_of(a_commander: Commander) -> Array:
	return a_commander.get_children().filter(
		func(n: Node) -> bool: return n is Entity and (n as Entity).id == &"fake_shell"
	)


func test_destroying_a_hazard_throws_its_blast_where_it_stood() -> void:
	var at := Vector3(3.0, 0.0, 4.0)
	var hazard: Entity = _hazard(at, FakePieces.emission_scene())
	hazard.kill()
	var blasts: Array = _blasts_of(_commander(NEUTRAL))
	assert_eq(blasts.size(), 1, "one blast")
	var blast: Entity = blasts[0]
	autofree(blast)
	assert_almost_eq(blast.global_position, at, Vector3.ONE * 0.01, "where the hazard stood")


func test_the_blast_is_unattributed() -> void:
	var hazard: Entity = _hazard(Vector3.ZERO, FakePieces.emission_scene())
	hazard.kill()
	var blast: Entity = _blasts_of(_commander(NEUTRAL))[0]
	autofree(blast)
	assert_null(Payload.of(blast).from, "nobody is credited with what the blast does")


func test_a_hazard_blasts_once() -> void:
	var hazard: Entity = _hazard(Vector3.ZERO, FakePieces.emission_scene())
	hazard.kill()
	Volatile.of(hazard)._on_host_occurrence(Entity.EntityOccurrence.ON_DEATH, hazard)
	var blasts: Array = _blasts_of(_commander(NEUTRAL))
	for blast: Node in blasts:
		autofree(blast)
	assert_eq(blasts.size(), 1, "a second death notice throws nothing")


func test_expiring_is_not_dying() -> void:
	var hazard: Entity = _hazard(Vector3.ZERO, FakePieces.emission_scene())
	hazard.expire()
	assert_eq(_blasts_of(_commander(NEUTRAL)).size(), 0, "leaving play quietly throws nothing")


func test_a_hazard_with_no_blast_dies_quietly() -> void:
	var hazard: Entity = _hazard(Vector3.ZERO, null)
	hazard.kill()
	assert_eq(_blasts_of(_commander(NEUTRAL)).size(), 0)
	assert_true(hazard.is_queued_for_deletion(), "it still dies")
