extends GutTest

## The environmental pieces in a BOOTED scenario, where the stepper, the physics world and the
## importer-composed scenes are all real: a destroyed power cell's blast arrives after its fuse,
## takes the cell beside it with it (the cascade) and hurts the unit standing there; a fuel
## cartridge is collected by walking a unit onto it. Rules:
## gdd/systems/combat/environmental-pieces.md.
##
## Scenes are loaded inside the tests, never preloaded at file scope (CLAUDE.md).
##
## Run with:
##   godot --headless --fixed-fps 30 -s addons/gut/gut_cmdln.gd \
##     -gtest=res://tests/test_EnvironmentalPiecesInPlay.gd -gexit

const HARNESS: String = "res://scenes/harnesses/test_kamikaze_cluster.tscn"
const CELL_SCENE: String = "res://scenes/entities/tokens/nt/nt_powerCell.tscn"
const CARTRIDGE_SCENE: String = "res://scenes/entities/tokens/nt/nt_fuelCartridge.tscn"
const SOLDIER_SCENE: String = "res://scenes/entities/units/nt/nt_bioLight_terrestrial.tscn"
const SEED: int = 7
const NEUTRAL: int = 0
const OWN: int = 1
## A corner of the harness map clear of its authored pieces.
const SITE: Vector2 = Vector2(4.0, 4.0)
## The blast's fuse — its first phase's lifespan (0.25 s) — in physics frames.
const FUSE_FRAMES: int = 8
## Fuse plus the payout phase, with room for the second cell's own fuse.
const CASCADE_FRAMES: int = 90
const CARTRIDGE_ENERGY: int = 500

var _scenario: Scenario


func before_each() -> void:
	gut.error_tracker.disabled = true
	_scenario = (load(HARNESS) as PackedScene).instantiate() as Scenario
	_scenario.rng_seed = SEED
	await get_tree().process_frame
	add_child(_scenario)
	await _frames(2)


func after_each() -> void:
	_scenario.free()
	await get_tree().process_frame
	gut.error_tracker.disabled = false


func _frames(a_count: int) -> void:
	for _i: int in a_count:
		await get_tree().physics_frame


func _spawn(a_scene: String, a_xz: Vector2, a_commander_id: int) -> Entity:
	var piece := (load(a_scene) as PackedScene).instantiate() as Entity
	_scenario.map.add_entity(piece, a_xz, _scenario.commanders[a_commander_id])
	return piece


func test_a_destroyed_cell_takes_the_cell_beside_it_and_hurts_the_unit_between() -> void:
	var first: Entity = _spawn(CELL_SCENE, SITE, NEUTRAL)
	var second: Entity = _spawn(CELL_SCENE, SITE + Vector2(1.0, 0.0), NEUTRAL)
	var soldier: Entity = _spawn(SOLDIER_SCENE, SITE + Vector2(0.5, 0.7), OWN)
	await _frames(2)
	assert_true(first.is_inside_tree() and second.is_inside_tree(), "both cells stand")
	var hp_before: float = soldier.defense.hp
	first.kill()
	await _frames(FUSE_FRAMES - 3)
	assert_true(is_instance_valid(second), "the second cell stands through the fuse")
	await _frames(CASCADE_FRAMES)
	assert_false(is_instance_valid(second), "the blast took the second cell")
	assert_true(
		not is_instance_valid(soldier) or soldier.defense.hp < hp_before,
		"the soldier between them was hurt"
	)


func test_a_unit_on_a_cartridge_collects_its_energy() -> void:
	var soldier: Entity = _spawn(SOLDIER_SCENE, SITE, OWN)
	await _frames(2)
	var token: Entity = _spawn(CARTRIDGE_SCENE, VU.in_xz(soldier.global_position), NEUTRAL)
	var before: int = _scenario.commanders[OWN].energy
	await _frames(3)
	assert_eq(_scenario.commanders[OWN].energy, before + CARTRIDGE_ENERGY)
	assert_false(is_instance_valid(token), "the cartridge is gone")
