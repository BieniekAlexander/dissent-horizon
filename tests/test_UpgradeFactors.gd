extends GutTest

## UPGRADE FACTORS: the multiplicative modifier effects — hit points, rearm speed and ability
## recharge speed (gdd/systems/macroeconomics/upgrades.md §What an upgrade can change).
##
## Every upgrade here is a fixture written into UpgradeCatalog's table, never a shipped doc.

const TOUGH: StringName = &"fake_tough"
const BIO_TOUGH: StringName = &"fake_bio_tough"
const QUICK_REARM: StringName = &"fake_quick_rearm"
const QUICK_COOLDOWN: StringName = &"fake_quick_cooldown"
const HARDY: StringName = &"fake_hardy"
const PLANE: StringName = &"fake_plane"
const GUN: StringName = &"fake_gun"
const SHELL: StringName = &"fake_shell"
const COOLDOWN_TICKS: int = 13

var _saved_entries: Dictionary
var _commander: Commander


func before_each() -> void:
	_saved_entries = UpgradeCatalog._entries.duplicate(true)
	UpgradeCatalog._entries[TOUGH] = {"modifies": [{"piece": String(HARDY), "hp_factor": 1.25}]}
	UpgradeCatalog._entries[BIO_TOUGH] = {"modifies": [{"frame": "BIO", "hp_factor": 1.2}]}
	UpgradeCatalog._entries[QUICK_REARM] = {
		"modifies": [{"piece": String(PLANE), "rearm_rate_factor": 2.0}]
	}
	UpgradeCatalog._entries[QUICK_COOLDOWN] = {
		"modifies": [{"piece": String(GUN), "ability": String(SHELL), "cooldown_rate_factor": 1.3}]
	}
	_commander = _make_commander(1)


func after_each() -> void:
	UpgradeCatalog._entries = _saved_entries


func _make_commander(a_id: int) -> Commander:
	var commander := Commander.new()
	commander.id = a_id
	add_child_autofree(commander)
	return commander


## A piece owned by `a_commander`; ownership is assigned directly, as test_Upgrades does.
func _owned(a_options: Dictionary, a_id: StringName, a_commander: Commander = null) -> Actor:
	var piece: Actor = FakePieces.make(a_options)
	piece.id = a_id
	add_child_autofree(piece)
	piece.ownership.commander = a_commander if a_commander != null else _commander
	return piece


# --- Hit points -----------------------------------------------------------------


func test_a_hit_point_upgrade_raises_the_maximum_and_the_hit_points_of_a_fielded_unit() -> void:
	var unit: Actor = _owned({"hp": 100.0, "frame": Defense.FrameType.MECH}, HARDY)
	unit.defense.hp = 60.0
	_commander.complete_upgrade(TOUGH)
	assert_almost_eq(unit.defense.hp_max, 125.0, 0.001)
	assert_almost_eq(unit.defense.hp, 75.0, 0.001, "the fraction of health is kept")
	assert_almost_eq(unit.defense.authored_hp_max(), 100.0, 0.001, "the doc value is kept")


func test_a_unit_joining_an_upgraded_commander_starts_at_the_raised_maximum() -> void:
	_commander.complete_upgrade(TOUGH)
	var unit: Actor = _owned({"hp": 100.0, "frame": Defense.FrameType.MECH}, HARDY)
	assert_almost_eq(unit.defense.hp_max, 125.0, 0.001)
	assert_almost_eq(unit.defense.hp, 125.0, 0.001)


func test_a_hit_point_upgrade_leaves_other_pieces_alone() -> void:
	var other: Actor = _owned({"hp": 100.0, "frame": Defense.FrameType.MECH}, &"other")
	_commander.complete_upgrade(TOUGH)
	assert_almost_eq(other.defense.hp_max, 100.0, 0.001)


func test_a_frame_upgrade_reaches_every_unit_of_that_frame_and_no_structure() -> void:
	var bio_unit: Actor = _owned({"hp": 100.0, "frame": Defense.FrameType.BIO}, &"a")
	var mech_unit: Actor = _owned({"hp": 100.0, "frame": Defense.FrameType.MECH}, &"b")
	var bio_structure: Actor = _owned(
		{"hp": 100.0, "frame": Defense.FrameType.BIO, "structure": true}, &"c"
	)
	_commander.complete_upgrade(BIO_TOUGH)
	assert_almost_eq(bio_unit.defense.hp_max, 120.0, 0.001)
	assert_almost_eq(mech_unit.defense.hp_max, 100.0, 0.001, "another frame is untouched")
	assert_almost_eq(bio_structure.defense.hp_max, 100.0, 0.001, "a structure is not a unit")


func test_hit_point_factors_stack_whatever_order_they_arrive_in() -> void:
	var unit: Actor = _owned({"hp": 100.0, "frame": Defense.FrameType.BIO}, HARDY)
	_commander.complete_upgrade(BIO_TOUGH)
	_commander.complete_upgrade(TOUGH)
	assert_almost_eq(unit.defense.hp_max, 150.0, 0.001, "1.25 x 1.2")


func test_a_piece_captured_by_a_commander_without_the_upgrade_loses_it() -> void:
	var unit: Actor = _owned({"hp": 100.0, "frame": Defense.FrameType.MECH}, HARDY)
	_commander.complete_upgrade(TOUGH)
	unit.defense.hp = 100.0
	unit.ownership.commander = _make_commander(2)
	assert_almost_eq(unit.defense.hp_max, 100.0, 0.001)
	assert_almost_eq(unit.defense.hp, 80.0, 0.001, "the fraction of health is kept")


func test_the_old_commanders_later_research_no_longer_reaches_a_captured_piece() -> void:
	var unit: Actor = _owned({"hp": 100.0, "frame": Defense.FrameType.MECH}, HARDY)
	unit.ownership.commander = _make_commander(2)
	_commander.complete_upgrade(TOUGH)
	assert_almost_eq(unit.defense.hp_max, 100.0, 0.001)


# --- Ability recharge -----------------------------------------------------------


func _gun() -> Actor:
	return _owned(
		{
			"structure": true,
			"abilities": [{"grants": [SHELL], "cooldown_ticks": COOLDOWN_TICKS}],
		},
		GUN
	)


func _recharge_ticks(a_pool: Abilities) -> int:
	a_pool.spend(SHELL)
	var ticks: int = 0
	while not a_pool.is_ready(SHELL) and ticks < COOLDOWN_TICKS * 2:
		a_pool._physics_process(0.0)
		ticks += 1
	return ticks


func test_an_unupgraded_pool_takes_its_whole_cooldown() -> void:
	assert_eq(_recharge_ticks(_gun().get_node("Abilities") as Abilities), COOLDOWN_TICKS)


func test_a_recharge_upgrade_speeds_the_pool_by_its_rate() -> void:
	var pool: Abilities = _gun().get_node("Abilities") as Abilities
	_commander.complete_upgrade(QUICK_COOLDOWN)
	# 13 cooldown ticks at 1.3 a tick: ten ticks.
	assert_eq(_recharge_ticks(pool), 10)


func test_the_recharge_countdown_reads_in_real_ticks_under_an_upgrade() -> void:
	var pool: Abilities = _gun().get_node("Abilities") as Abilities
	_commander.complete_upgrade(QUICK_COOLDOWN)
	pool.spend(SHELL)
	assert_eq(pool.recharge_remaining(SHELL), 10)


# --- Rearm ----------------------------------------------------------------------

const AIRFIELD: Dictionary = {
	"structure": true, "production": true, "docking_bay": {"pads": 1, "runways": 1}
}
const AIRCRAFT: Dictionary = {
	"aerial": true,
	"docking": true,
	"vision": 8.0,
	"weapon": {"ground": 6.0, "clip_size": 4, "charged": true, "reload_ticks": 40}
}


## Ticks a docked, empty aircraft of `a_id` takes to refill at a fresh airfield.
func _rearm_ticks(a_id: StringName) -> int:
	var field: Actor = _owned(AIRFIELD, &"fake_field")
	field.build_progress = 1.0
	var plane: Actor = _owned(AIRCRAFT, a_id)
	assert_true((field.get_node("Production") as Production)._spawn_on_pad(field, plane), "parked")
	var weapon: Weapon = plane.weapon_inventory.get_weapons()[0]
	for _i: int in weapon.clip_size:
		weapon.consume_round()
	var ticks: int = 0
	while weapon.ammo() < weapon.clip_size and ticks < 100:
		field.docking_bay.tick_recharge()
		ticks += 1
	return ticks


func test_a_rearm_upgrade_refills_its_aircraft_at_its_rate() -> void:
	_commander.complete_upgrade(QUICK_REARM)
	assert_eq(_rearm_ticks(PLANE), 20, "40 reload ticks at twice the rate")


func test_a_rearm_upgrade_leaves_other_aircraft_at_the_bay_rate() -> void:
	_commander.complete_upgrade(QUICK_REARM)
	assert_eq(_rearm_ticks(&"other_plane"), 40)
