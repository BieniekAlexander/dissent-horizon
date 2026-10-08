extends GutTest

## Where a weapon's reach is measured from (Weapon.RangeOrigin): from the wielder's footprint,
## or from the centre of the orbit it flies — and what fighting from an orbit does to an Attack.
## Rules: gdd/systems/combat/range-buckets.md §Where a reach is measured from.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_RangeOrigin.gd -gexit
##
## Every piece is a fake, and every distance is read against the harness weapon's REACH.

const SpecRegistry := preload("res://tools/spec_import/spec_registry.gd")

const REACH: float = 6.0
const GUNSHIP: Dictionary = {"aerial": true, "flying": true, "weapon": {"ground": REACH}}
const SOLDIER: Dictionary = {"speed": 2.0, "vision": 8.0}
const OWN: int = 7
const ENEMY: int = 8

## Where the aircraft circles, and well away from it, where the aircraft itself flies.
const ORBIT_CENTRE: Vector3 = Vector3.ZERO
const AWAY: Vector3 = Vector3(5.0 * REACH, 0.0, 0.0)


func before_each() -> void:
	Fog._fogs_by_commander.clear()


func after_each() -> void:
	Fog._fogs_by_commander.clear()


func _commander(a_id: int) -> Commander:
	var commander := Commander.new()
	commander.id = a_id
	add_child_autofree(commander)
	return commander


func _piece(a_options: Dictionary, a_commander_id: int, a_at: Vector3) -> Actor:
	var piece := FakePieces.make(a_options) as Actor
	add_child_autofree(piece)
	piece.ownership.commander = _commander(a_commander_id)
	piece.global_position = a_at
	return piece


## An aircraft flying at AWAY, circling ORBIT_CENTRE, its weapon measuring from `a_origin`.
func _aircraft(a_origin: Weapon.RangeOrigin = Weapon.RangeOrigin.ORBIT) -> Actor:
	var aircraft: Actor = _piece(GUNSHIP, OWN, AWAY)
	_weapon(aircraft).range_origin = a_origin
	aircraft.aerial.set_anchor(ORBIT_CENTRE)
	return aircraft


func _weapon(a_piece: Actor) -> Weapon:
	return a_piece.weapon_inventory.get_weapons()[0]


func _attack(a_target: Actor) -> Attack:
	return Attack.new(CommandMessage.new(null, a_target, null))


func test_a_hull_weapon_has_no_orbit_origin() -> void:
	var aircraft := _aircraft(Weapon.RangeOrigin.HULL)
	assert_null(_weapon(aircraft).orbit_origin(aircraft))
	assert_false(aircraft.fights_from_orbit())


func test_an_orbit_weapon_measures_from_the_orbit_centre() -> void:
	var aircraft := _aircraft()
	assert_eq(_weapon(aircraft).orbit_origin(aircraft), ORBIT_CENTRE)
	assert_true(aircraft.fights_from_orbit())


func test_an_orbit_weapon_on_a_piece_that_does_not_orbit_measures_from_its_hull() -> void:
	var soldier: Actor = _piece({"speed": 2.0, "weapon": {"ground": REACH}}, OWN, AWAY)
	_weapon(soldier).range_origin = Weapon.RangeOrigin.ORBIT
	assert_null(_weapon(soldier).orbit_origin(soldier))
	assert_false(soldier.fights_from_orbit())


func test_in_range_means_the_range_shape_at_the_orbit_centre_touches_the_hurtbox() -> void:
	var aircraft := _aircraft()
	var near_centre: Actor = _piece(SOLDIER, ENEMY, ORBIT_CENTRE + Vector3(REACH, 0, 0))
	var near_aircraft: Actor = _piece(SOLDIER, ENEMY, AWAY + Vector3(1.0, 0, 0))
	await wait_physics_frames(2)
	assert_true(
		SU.is_in_attack_range(_weapon(aircraft), aircraft, near_centre), "reached from the centre"
	)
	assert_false(
		SU.is_in_attack_range(_weapon(aircraft), aircraft, near_aircraft),
		"however close to the aircraft itself"
	)


func test_a_hull_weapon_still_measures_from_its_wielder() -> void:
	var aircraft := _aircraft(Weapon.RangeOrigin.HULL)
	var near_aircraft: Actor = _piece(SOLDIER, ENEMY, AWAY + Vector3(1.0, 0, 0))
	await wait_physics_frames(2)
	assert_true(SU.is_in_attack_range(_weapon(aircraft), aircraft, near_aircraft))


func test_it_picks_up_targets_around_the_orbit_centre_not_itself() -> void:
	var aircraft := _aircraft()
	var near_centre: Actor = _piece(SOLDIER, ENEMY, ORBIT_CENTRE)
	_piece(SOLDIER, ENEMY, AWAY + Vector3(1.0, 0, 0))
	await wait_physics_frames(2)
	var pickup: MoveCommand = aircraft.get_aggro_near_position()
	assert_true(pickup is Attack)
	assert_eq(pickup.message.target, near_centre)


func test_an_attack_never_steers_it() -> void:
	var aircraft := _aircraft()
	var target: Actor = _piece(SOLDIER, ENEMY, ORBIT_CENTRE + Vector3(3.0 * REACH, 0, 0))
	await wait_physics_frames(2)
	var order := _attack(target)
	assert_false(order.should_move(aircraft), "moving would close nothing")
	assert_null(order.orbit_anchor(aircraft), "it keeps the circuit it is flying")


func test_an_aircraft_measuring_from_its_hull_still_flies_at_its_target() -> void:
	var aircraft := _aircraft(Weapon.RangeOrigin.HULL)
	var target: Actor = _piece(SOLDIER, ENEMY, ORBIT_CENTRE)
	await wait_physics_frames(2)
	var order := _attack(target)
	assert_true(order.should_move(aircraft))
	assert_eq(order.orbit_anchor(aircraft), order.message.position)


func test_attacking_leaves_its_orbit_centre_where_it_was() -> void:
	var aircraft := _aircraft()
	var target: Actor = _piece(SOLDIER, ENEMY, ORBIT_CENTRE + Vector3(REACH, 0, 0))
	await wait_physics_frames(2)
	aircraft.update_commands(_attack(target))
	for _i: int in 5:
		aircraft.command_receiver._process_commands()
	assert_true(aircraft.current_command() is Attack, "fixture: still attacking")
	assert_eq(aircraft.aerial.anchor(), ORBIT_CENTRE)


func test_a_target_that_leaves_the_range_shape_is_let_go() -> void:
	var aircraft := _aircraft()
	var target: Actor = _piece(SOLDIER, ENEMY, ORBIT_CENTRE)
	await wait_physics_frames(2)
	var order := _attack(target)
	order.message.persist = true
	assert_eq(order.get_updated_state(aircraft), order, "held while in reach")
	target.global_position = ORBIT_CENTRE + Vector3(3.0 * REACH, 0, 0)
	await wait_physics_frames(2)
	assert_null(order.get_updated_state(aircraft), "even an ordered attack: it cannot chase")


# --- The doc key ---------------------------------------------------------------------


func _range_from_errors(a_value: String, a_aerial: Variant) -> Array:
	var registry := SpecRegistry.new()
	var spec: Dictionary = {"_doc_path": "doc.md", "id": "plane"}
	if a_aerial != null:
		spec["aerial"] = a_aerial
	registry._validate_range_from(spec, "gun", a_value)
	return registry.errors


func test_range_from_orbit_is_accepted_on_a_flying_piece() -> void:
	assert_eq(_range_from_errors("orbit", {"mode": "FLYING"}), [])
	assert_eq(_range_from_errors("hull", null), [], "hull suits anything")


func test_range_from_orbit_is_refused_on_a_piece_with_no_orbit() -> void:
	assert_eq(_range_from_errors("orbit", null).size(), 1, "a ground piece")
	assert_eq(_range_from_errors("orbit", {"mode": "HOVERING"}).size(), 1, "a hovering one")


func test_an_unknown_range_from_is_refused() -> void:
	assert_eq(_range_from_errors("muzzle", {"mode": "FLYING"}).size(), 1)


# --- What is drawn -------------------------------------------------------------------


func test_its_attack_ring_is_drawn_at_the_orbit_centre_at_its_reach() -> void:
	var aircraft := _aircraft()
	var ring: HighlightShape = EntityRanges.shape_for(aircraft, EntityRanges.Kind.ATTACK)
	assert_eq(ring.center, VU.in_xz(ORBIT_CENTRE), "where the reach is measured from")
	assert_almost_eq(ring.radius, REACH, 0.001, "not widened by a body that plays no part")


func test_a_hull_weapons_ring_still_surrounds_its_wielder() -> void:
	var aircraft := _aircraft(Weapon.RangeOrigin.HULL)
	var ring: HighlightShape = EntityRanges.shape_for(aircraft, EntityRanges.Kind.ATTACK)
	assert_eq(ring.center, aircraft.xz_position)


func test_the_gunship_events_area_is_its_reach() -> void:
	var event := EventGunship.new()
	autofree(event)
	event.gunship_scene = FakePieces.scene_of(GUNSHIP)
	assert_almost_eq(event.area_radius(), REACH, 0.001)


func test_a_sanction_draws_its_events_area_over_its_own_number() -> void:
	var event := EventGunship.new()
	event.gunship_scene = FakePieces.scene_of(GUNSHIP)
	var packed := PackedScene.new()
	packed.pack(event)
	event.free()
	var sanction := Sanction.new()
	sanction.effect_radius = 2.0 * REACH
	sanction.event_scene = packed
	assert_almost_eq(sanction.area_radius(), REACH, 0.001, "the event's derived area")
	var plain := Sanction.new()
	plain.effect_radius = 2.0 * REACH
	assert_eq(plain.area_radius(), 2.0 * REACH, "with nothing to ask, its own")


func test_a_sanction_stating_no_area_draws_none() -> void:
	assert_eq(Sanction.new().area_radius(), 0.0, "no default circle the ability does not cover")


func test_the_bot_still_scores_clusters_for_a_sanction_stating_no_area() -> void:
	assert_eq(BotSanction._cluster_radius(Sanction.new()), BotSanction.UNSTATED_CLUSTER_RADIUS)


func _orbit_spec(a_aerial: Dictionary) -> Dictionary:
	return {
		"_doc_path": "doc.md",
		"id": "plane",
		"aerial": a_aerial,
		"weapons":
		[{"name": "gun", "range_from": "orbit", "_reach_radii": {"ground": 12.0, "air": 18.0}}]
	}


func test_its_orbit_radius_is_its_ground_reach() -> void:
	var registry := SpecRegistry.new()
	var spec: Dictionary = _orbit_spec({"mode": "FLYING"})
	registry._derive_orbit_radius(spec)
	assert_eq(registry.errors, [])
	assert_eq(spec["aerial"]["orbit_radius"], 12.0, "the circle it flies is the one it fires into")


func test_an_authored_orbit_radius_beside_it_is_refused() -> void:
	var registry := SpecRegistry.new()
	registry._derive_orbit_radius(_orbit_spec({"mode": "FLYING", "orbit_radius": 6.0}))
	assert_eq(registry.errors.size(), 1)


func test_a_hull_weapon_leaves_the_orbit_radius_alone() -> void:
	var registry := SpecRegistry.new()
	var spec: Dictionary = _orbit_spec({"mode": "FLYING", "orbit_radius": 6.0})
	spec["weapons"][0]["range_from"] = "hull"
	registry._derive_orbit_radius(spec)
	assert_eq(registry.errors, [])
	assert_eq(spec["aerial"]["orbit_radius"], 6.0)


func test_orbit_speed_names_a_speed_class() -> void:
	var registry := SpecRegistry.new()
	registry.speeds = {"SLOW": 2.0, "FAST": 9.0}
	registry.pieces = {
		"named": {"_doc_path": "a.md", "id": "named", "aerial": {"orbit_speed": "FAST"}},
		"number": {"_doc_path": "b.md", "id": "number", "aerial": {"orbit_speed": 9.0}},
	}
	registry._resolve_speed_classes()
	assert_eq(registry.pieces["named"]["aerial"]["orbit_speed"], 9.0)
	assert_eq(registry.errors.size(), 1, "a number where a class belongs is refused")


func test_the_mortars_area_is_one_shells_blast() -> void:
	var shell := Entity.new()
	shell.name = "Shell"
	var hit := CollisionShape3D.new()
	hit.name = "HitShape"
	var sphere := SphereShape3D.new()
	sphere.radius = 3.0
	hit.shape = sphere
	shell.add_child(hit)
	hit.owner = shell
	var packed := PackedScene.new()
	packed.pack(shell)
	shell.free()
	var event := EventMortarBarrage.new()
	autofree(event)
	event.projectile_scene = packed
	assert_almost_eq(event.area_radius(), 3.0, 0.001)
