extends GutTest

## The field catalogue the HUD readout and the debug tuning editor share: conversions between
## the running game's value, the doc's and what a person reads, and the rule that a live
## retune keeps the fraction a piece is at (gdd/systems/ux/ui/debug-tuning.md).


func _field(a_scope: PieceField.Scope, a_path: Array) -> PieceField:
	for field: PieceField in PieceFields.of_scope(a_scope):
		if field.doc_path == a_path:
			return field
	fail_test("no %s field at %s" % [a_scope, a_path])
	return null


func _live(a_options: Dictionary) -> Commandable:
	var piece: Commandable = FakePieces.unit(a_options)
	add_child_autofree(piece)
	piece.set_physics_process(false)
	return piece


func test_seconds_round_trip_through_ticks() -> void:
	var split: PieceField = _field(PieceField.Scope.WEAPON, ["split_time"])
	var ticks: int = PieceFields.from_doc(split, 1.5)
	assert_eq(ticks, TimeUtils.ticks_from_seconds(1.5))
	assert_almost_eq(float(PieceFields.to_doc(split, ticks)), 1.5, 0.001)


func test_a_speed_is_written_as_the_class_it_matches() -> void:
	var speed: PieceField = _field(PieceField.Scope.PIECE, ["movement", "speed"])
	var ladder: Dictionary = {"SLOW": 1.5, "FAST": 4.0}
	assert_eq(PieceFields.to_doc(speed, 4.0, ladder), "FAST")
	assert_eq(PieceFields.from_doc(speed, "SLOW", ladder), 1.5)


func test_a_speed_matching_no_class_is_written_as_its_number() -> void:
	var speed: PieceField = _field(PieceField.Scope.PIECE, ["movement", "speed"])
	assert_eq(PieceFields.to_doc(speed, 2.0, {"SLOW": 1.5}), 2.0)


func test_a_speed_is_read_out_as_a_number_never_a_class() -> void:
	var speed: PieceField = _field(PieceField.Scope.PIECE, ["movement", "speed"])
	assert_eq(PieceFields.display(speed, 4.0), "4 u/s")


func test_enums_and_flags_are_names_in_the_doc() -> void:
	var armour: PieceField = _field(PieceField.Scope.PIECE, ["defense", "armour"])
	assert_eq(PieceFields.to_doc(armour, Defense.ArmourType.STRONG), "STRONG")
	assert_eq(PieceFields.from_doc(armour, "MEDIUM"), Defense.ArmourType.MEDIUM)
	var hits: PieceField = _field(PieceField.Scope.WEAPON, ["hits"])
	var both: int = CollisionLayers.Mask.TARGETABLE_GROUND | CollisionLayers.Mask.TARGETABLE_AIR
	assert_eq(PieceFields.from_doc(hits, ["ground", "air"]), both)
	assert_eq(PieceFields.to_doc(hits, CollisionLayers.Mask.TARGETABLE_AIR), ["air"])


func test_a_payload_cadence_is_once_or_seconds() -> void:
	var payload: PieceField = _field(PieceField.Scope.PHASE, ["payload"])
	assert_eq(PieceFields.to_doc(payload, INF), "once")
	assert_eq(PieceFields.from_doc(payload, 0.5), 0.5)
	assert_eq(PieceFields.display(payload, null), "none")


func test_a_library_shape_is_named_by_its_file() -> void:
	var shape := CylinderShape3D.new()
	shape.resource_path = PieceFields.SHAPES_DIR + "fake_bucket.tres"
	assert_eq(PieceFields.shape_id(shape), "fake_bucket")
	assert_eq(PieceFields.shape_id(CylinderShape3D.new()), "", "a piece-local shape has no id")


func test_an_unbounded_value_reads_as_unbounded() -> void:
	var acceleration: PieceField = _field(PieceField.Scope.PIECE, ["movement", "max_acceleration"])
	assert_eq(PieceFields.display(acceleration, INF), "unbounded")


func test_raising_hp_keeps_the_fraction_of_health() -> void:
	var piece: Commandable = _live({"hp": 100.0})
	piece.defense.hp = 50.0
	var hp: PieceField = _field(PieceField.Scope.PIECE, ["defense", "hp"])
	hp.write.call({"node": piece}, 100.0, 150.0)
	assert_eq(piece.defense.hp_max, 150.0)
	assert_eq(piece.defense.hp, 75.0)


func test_a_slowed_unit_keeps_its_slow_when_its_speed_is_retuned() -> void:
	var piece: Commandable = _live({"speed": 4.0})
	var movement: Movement = piece.get_node("Locomotion") as Movement
	movement.speed = 2.0  # half speed, as a slow would leave it
	var speed: PieceField = _field(PieceField.Scope.PIECE, ["movement", "speed"])
	speed.write.call({"node": piece}, 4.0, 6.0)
	assert_almost_eq(movement.speed, 3.0, 0.001)


func test_resizing_a_clip_keeps_the_fraction_loaded() -> void:
	var piece: Commandable = _live({"weapon": {"ground": 5.0, "clip_size": 4}})
	var weapon: Weapon = EntityRanges.first_weapon(piece)
	weapon.fill_clip()
	weapon.consume_round()
	weapon.consume_round()
	weapon.resize_clip(8)
	assert_eq(weapon.ammo(), 4, "half a clip stays half a clip")


func test_retuning_reach_rederives_aggro() -> void:
	var piece: Commandable = _live({"speed": 2.0, "weapon": {"ground": 2.0}})
	var before: float = RangeShapes.radius_of(piece.aggro_shape_ground.shape)
	var reach: PieceField = _field(PieceField.Scope.WEAPON, ["reach", "ground"])
	var longer := CylinderShape3D.new()
	longer.radius = 8.0
	reach.write.call({"node": EntityRanges.first_weapon(piece), "piece": piece}, null, longer)
	assert_gt(RangeShapes.radius_of(piece.aggro_shape_ground.shape), before)


func test_retuning_a_pool_keeps_its_fraction_of_charges() -> void:
	var piece: Commandable = _live(
		{"abilities": [{"grants": [&"fake_ability"], "max_charges": 2, "cooldown_ticks": 60}]}
	)
	var abilities: Abilities = piece.get_node("Abilities") as Abilities
	abilities.retune_pool(0, "max_charges", 4)
	assert_eq(abilities.pool_value(0, "max_charges"), 4)
	assert_eq(abilities.charges_of(&"fake_ability"), 4, "a full pool stays full")


func test_sustained_dps_follows_the_firing_cycle() -> void:
	var tick: int = TimeUtils.ticks_from_seconds(1.0)
	assert_almost_eq(
		Weapon.sustained_damage_per_second(10.0, tick, tick / 2, 1),
		10.0,
		0.01,
		"a reload inside the split never holds the weapon up"
	)
	assert_almost_eq(
		Weapon.sustained_damage_per_second(10.0, tick / 2, tick * 3, 4),
		40.0 / 4.5,
		0.01,
		"four shots half a second apart, then three seconds of reload"
	)
