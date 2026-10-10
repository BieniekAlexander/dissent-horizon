extends GutTest

## THE MATCH'S ALERTS: WHO IS TOLD WHAT, AND WHETHER THEY ARE TOLD WHERE.
##
## Run with:
## godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_AlertCenter.gd -gexit
##
## An AlertCenter bound to hand-built commanders (no scenario), fed occurrences and polled by
## hand at ticks the test sets. Pieces are FakePieces; the superweapon is a fake ability that
## authors `global_alert: true`, so nothing here depends on the shipped Cryogenic Implosion.
## Why: gdd/systems/ux/ui/alerts.md.

const OWN: int = 1
const FOE: int = 2
const ALLY: int = 3
const SUPERWEAPON: StringName = &"test_superweapon"

var _center: AlertCenter
var _commanders: Array = []
var _raised: Array[Alert] = []
var _presented: Array[Alert] = []


func before_each() -> void:
	Fog._fogs_by_commander.clear()
	FakePieces.install_ability(SUPERWEAPON, {"title": "Doom Ray", "global_alert": true})
	_commanders = [null]
	for id: int in [OWN, FOE, ALLY]:
		var c := Commander.new()
		c.id = id
		add_child_autofree(c)
		_commanders.append(c)
	(_commanders[OWN] as Commander).set_alliance(1, (1 << OWN) | (1 << ALLY))
	(_commanders[ALLY] as Commander).set_alliance(1, (1 << OWN) | (1 << ALLY))
	(_commanders[FOE] as Commander).set_alliance(2, 1 << FOE)
	_center = AlertCenter.new()
	add_child_autofree(_center)
	_center.bind_commanders(_commanders)
	_center.set_tick(0)
	_raised.clear()
	_presented.clear()
	_center.alert_raised.connect(func(a: Alert) -> void: _raised.append(a))
	_center.alert_presented.connect(func(a: Alert) -> void: _presented.append(a))


func after_each() -> void:
	FakePieces.restore_abilities()
	Fog._fogs_by_commander.clear()


func _piece(a_options: Dictionary, a_owner: int, a_at: Vector3 = Vector3.ZERO) -> Actor:
	var piece := FakePieces.make(a_options) as Actor
	add_child_autofree(piece)
	piece.ownership.commander = _commanders[a_owner]
	piece.global_position = a_at
	return piece


func _hit(a_victim: Actor, a_by: int) -> void:
	a_victim.last_hit_by_commander_id = a_by
	_center.report_occurrence(Entity.EntityOccurrence.ON_RECEIVE_DAMAGE, a_victim)


func _of(a_alerts: Array[Alert], a_type: AlertCatalog.Type) -> Array[Alert]:
	return a_alerts.filter(func(a: Alert) -> bool: return a.type == a_type)


# --- Under attack -----------------------------------------------------------------------


func test_an_enemy_hit_tells_the_owner_where() -> void:
	var unit := _piece(FakePieces.SOLDIER, OWN, Vector3(5.0, 0.0, 7.0))
	_hit(unit, FOE)
	assert_eq(_presented.size(), 1)
	var alert: Alert = _presented[0]
	assert_eq(alert.type, AlertCatalog.Type.UNITS_ATTACKED)
	assert_eq(alert.viewer_id, OWN)
	assert_true(alert.has_position)
	assert_eq(alert.xz(), Vector2(5.0, 7.0))


func test_a_structure_hit_is_the_base_under_attack() -> void:
	_hit(_piece(FakePieces.BUILDING, OWN), FOE)
	assert_eq(_presented[0].type, AlertCatalog.Type.STRUCTURES_ATTACKED)


func test_own_and_allied_fire_is_not_an_attack() -> void:
	var unit := _piece(FakePieces.SOLDIER, OWN)
	_hit(unit, OWN)
	_hit(unit, ALLY)
	assert_eq(_raised.size(), 0)


func test_an_unattributed_hit_is_an_attack() -> void:
	_hit(_piece(FakePieces.SOLDIER, OWN), -1)
	assert_eq(_raised.size(), 1)


func test_a_neutral_piece_has_nobody_to_tell() -> void:
	var piece := FakePieces.make(FakePieces.SOLDIER) as Actor
	add_child_autofree(piece)
	_hit(piece, FOE)
	assert_eq(_raised.size(), 0)


func test_every_hit_is_raised_but_a_burst_is_presented_once() -> void:
	var unit := _piece(FakePieces.SOLDIER, OWN)
	for i: int in 5:
		_center.set_tick(i)
		_hit(unit, FOE)
	assert_eq(_raised.size(), 5, "the game keeps track of every one")
	assert_eq(_presented.size(), 1, "the player is told once")


func test_damage_records_the_attackers_side() -> void:
	# The real path: Entity.receive_damage writes last_hit_by_commander_id before the
	# occurrence fires, so the listener can tell friendly fire from an attack.
	var victim := _piece(FakePieces.SOLDIER, OWN)
	var shooter := _piece(FakePieces.SOLDIER, FOE)
	victim.receive_damage(Damage.new(1.0, Damage.Type.LEAD), shooter)
	assert_eq(victim.last_hit_by_commander_id, FOE)
	victim.receive_damage(Damage.new(1.0, Damage.Type.LEAD), null)
	assert_eq(victim.last_hit_by_commander_id, -1)


# --- Stealth ----------------------------------------------------------------------------


func test_a_detected_stealth_unit_tells_its_enemies() -> void:
	var sneak := _piece(FakePieces.SOLDIER.merged({"stealth": true}), FOE)
	var stealth := sneak.get_node("Stealth") as Stealth
	stealth.state = Stealth.State.REVEALED
	_center.report_occurrence(Entity.EntityOccurrence.ON_EXIT_STEALTH, sneak)
	var told: Array = _of(_raised, AlertCatalog.Type.STEALTH_DETECTED).map(
		func(a: Alert) -> int: return a.viewer_id
	)
	told.sort()
	assert_eq(told, [OWN, ALLY], "its enemies, never its own side")
	assert_true(_raised[0].has_position)


func test_a_stealth_unit_unhidden_by_a_fight_is_not_a_detection() -> void:
	var sneak := _piece(FakePieces.SOLDIER.merged({"stealth": true}), FOE)
	(sneak.get_node("Stealth") as Stealth).state = Stealth.State.UNSTEALTHED
	_center.report_occurrence(Entity.EntityOccurrence.ON_EXIT_STEALTH, sneak)
	assert_eq(_raised.size(), 0)


func test_stealth_reports_its_transitions() -> void:
	var sneak := _piece(FakePieces.SOLDIER.merged({"stealth": true}), FOE)
	var seen: Array = []
	sneak.entity_occurrence.connect(func(o: int, _s: Entity) -> void: seen.append(o))
	var stealth := sneak.get_node("Stealth") as Stealth
	# The piece ticks its own Stealth each physics frame (Actor._update_state); a detector
	# stamps reveal() each frame it overlaps. One stamp, then none.
	stealth.reveal()
	await wait_physics_frames(1)
	assert_eq(seen, [Entity.EntityOccurrence.ON_EXIT_STEALTH], "found")
	await wait_physics_frames(Stealth.REVEAL_FRESH_FRAMES + 3)
	assert_eq(seen.back(), Entity.EntityOccurrence.ON_ENTER_STEALTH, "lost again")
	assert_eq(seen.size(), 2, "one occurrence per crossing, not per tick")


# --- States -----------------------------------------------------------------------------


func test_floating_energy_is_told_after_it_holds() -> void:
	(_commanders[OWN] as Commander).energy = AlertCenter.FLOAT_MIN_ENERGY * 2
	_center.poll()
	assert_eq(_of(_raised, AlertCatalog.Type.ENERGY_FLOATING).size(), 0, "not yet")
	_center.set_tick(AlertCatalog.sustain_ticks(AlertCatalog.Type.ENERGY_FLOATING))
	_center.poll()
	var floating: Array[Alert] = _of(_raised, AlertCatalog.Type.ENERGY_FLOATING)
	assert_eq(floating.size(), 1)
	assert_eq(floating[0].viewer_id, OWN)
	assert_false(floating[0].has_position, "a state is nowhere")


func test_floating_has_hysteresis() -> void:
	var own := _commanders[OWN] as Commander
	own.energy = AlertCenter.FLOAT_MIN_ENERGY
	_center.poll()
	# Just under the line, but above the release level: still floating, so the latch keeps
	# counting rather than restarting.
	own.energy = int(AlertCenter.FLOAT_MIN_ENERGY * 0.9)
	_center.set_tick(AlertCatalog.sustain_ticks(AlertCatalog.Type.ENERGY_FLOATING))
	_center.poll()
	assert_eq(_of(_raised, AlertCatalog.Type.ENERGY_FLOATING).size(), 1)


func test_strained_infrastructure_is_told() -> void:
	var own := _commanders[OWN] as Commander
	own.infrastructure_required = own.infrastructure_provided + 1
	_center.poll()
	_center.set_tick(AlertCatalog.sustain_ticks(AlertCatalog.Type.INFRASTRUCTURE_STRAINED))
	_center.poll()
	assert_eq(_of(_presented, AlertCatalog.Type.INFRASTRUCTURE_STRAINED).size(), 1)


# --- Superweapons -----------------------------------------------------------------------


func _superweapon(a_owner: int, a_built: bool = true) -> Actor:
	var piece := _piece(
		{"structure": true, "abilities": [{"grants": [SUPERWEAPON], "initial_charges": 0}]},
		a_owner,
		Vector3(40.0, 0.0, 40.0)
	)
	if not a_built:
		piece.build_progress = 0.5
	return piece


func _charge(a_piece: Actor, a_charges: int) -> void:
	(a_piece.get_node("Abilities") as Abilities)._charges[0] = a_charges


func test_a_superweapon_begun_is_told_to_everyone_else_without_a_place() -> void:
	_superweapon(FOE, false)
	_center.poll()
	var begun: Array[Alert] = _of(_raised, AlertCatalog.Type.SUPERWEAPON_BEGUN)
	var told: Array = begun.map(func(a: Alert) -> int: return a.viewer_id)
	told.sort()
	assert_eq(told, [OWN, ALLY])
	for alert: Alert in begun:
		assert_false(alert.has_position, "never where")
		assert_eq(alert.about_id, FOE)


func test_a_superweapon_lifecycle() -> void:
	var piece := _superweapon(FOE, false)
	_center.poll()
	piece.build_progress = 1.0
	_center.set_tick(1)
	_center.poll()
	assert_eq(_of(_raised, AlertCatalog.Type.SUPERWEAPON_BUILT).size(), 2, "built, to both others")
	_charge(piece, 1)
	_center.set_tick(2)
	_center.poll()
	var ready: Array[Alert] = _of(_raised, AlertCatalog.Type.SUPERWEAPON_READY)
	assert_eq(ready.size(), 3, "its owner and both others")
	for alert: Alert in ready:
		assert_eq(alert.has_position, alert.viewer_id == FOE, "only its owner is told where")
	_charge(piece, 0)
	_center.set_tick(3)
	_center.poll()
	assert_eq(_of(_raised, AlertCatalog.Type.SUPERWEAPON_LAUNCHED).size(), 2)


func test_a_superweapons_timer_is_listed_for_everyone() -> void:
	var piece := _superweapon(FOE)
	_center.poll()
	var rows: Array[Dictionary] = _center.superweapons()
	assert_eq(rows.size(), 1)
	assert_eq(rows[0]["owner"], FOE)
	assert_eq(rows[0]["title"], "Doom Ray")
	assert_eq(rows[0]["charges"], 0)
	assert_gt(int(rows[0]["remaining_ticks"]), 0, "counting down")
	piece.free()
	_center.set_tick(1)
	_center.poll()
	assert_eq(_center.superweapons().size(), 0, "gone with its caster")
	assert_eq(_of(_raised, AlertCatalog.Type.SUPERWEAPON_LOST).size(), 2)


func test_an_ability_without_a_global_alert_is_not_a_superweapon() -> void:
	FakePieces.install_ability(SUPERWEAPON, {"title": "Doom Ray"})
	_superweapon(FOE)
	_center.poll()
	assert_eq(_center.superweapons().size(), 0)
	assert_eq(_raised.size(), 0)


func test_the_countdown_reads_as_minutes_and_seconds() -> void:
	var row: Dictionary = {"charges": 0, "remaining_ticks": TimeUtils.ticks_from_seconds(133.0)}
	assert_eq(SuperweaponTimers.countdown_text(row), "2:13")
	row["charges"] = 1
	assert_eq(SuperweaponTimers.countdown_text(row), "READY")
