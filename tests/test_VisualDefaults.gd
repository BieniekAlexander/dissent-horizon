extends GutTest

## The pure half of the generated-visuals pass: classification and the arithmetic that
## turns a measured model into a placeholder mesh, a selection shape and an HP bar.
##
## Worth testing on its own because none of it needs a scene — the module takes numbers and
## returns descriptors, so every boundary (the click-target floor, the bar's minimum width,
## a degenerate footprint) is reachable without booting the engine.

const VisualDefaults := preload("res://tools/spec_import/visual_defaults.gd")
const VisualMeasure := preload("res://tools/spec_import/visual_measure.gd")
const SpecSchema := preload("res://tools/spec_import/schema.gd")

## A model roughly the size of the roster's infantry, and one roughly the size of its
## vehicles — the two ends the floors and ratios are pitched between.
const INFANTRY_SIZE: Vector3 = Vector3(0.40, 1.00, 0.40)
const VEHICLE_SIZE: Vector3 = Vector3(1.40, 0.60, 2.10)


# --------------------------------------------------------------------------- #
# Classification
# --------------------------------------------------------------------------- #
func test_grounded_frames_split_bio_from_mech() -> void:
	assert_eq(
		VisualDefaults.classify_piece(Defense.FrameType.BIO, Movement.Mode.GROUNDED, false),
		VisualDefaults.VisualClass.BIO_UNIT
	)
	assert_eq(
		VisualDefaults.classify_piece(Defense.FrameType.MECH, Movement.Mode.GROUNDED, false),
		VisualDefaults.VisualClass.MECH_UNIT
	)


## The deliberate precedence: what a placeholder says first is "this thing flies".
func test_aerial_beats_frame_for_both_frames() -> void:
	for mode: int in [Movement.Mode.FLYING, Movement.Mode.HOVERING]:
		for frame: int in [Defense.FrameType.BIO, Defense.FrameType.MECH]:
			assert_eq(
				VisualDefaults.classify_piece(frame, mode, false),
				VisualDefaults.VisualClass.AERIAL_UNIT,
				"frame %d at mode %d is aerial" % [frame, mode]
			)


func test_structure_beats_frame_and_mode() -> void:
	assert_eq(
		VisualDefaults.classify_piece(Defense.FrameType.MECH, Movement.Mode.FLYING, true),
		VisualDefaults.VisualClass.STRUCTURE
	)


## Every motion preset's first phase, expanded the way the importer does it.
func _preset_phases() -> Dictionary:
	var EmissionPhases: GDScript = load("res://tools/spec_import/emission_phases.gd")
	var phases: Dictionary = {}
	for preset: String in EmissionPhase.PRESETS:
		phases[preset] = EmissionPhases.first_motion({"trajectory": preset, "speed": 10})
	return phases


func test_every_motion_preset_maps_to_its_own_class() -> void:
	var seen: Array = []
	var phases: Dictionary = _preset_phases()
	for preset: String in phases:
		var visual_class: int = VisualDefaults.classify_projectile(phases[preset])
		assert_true(
			VisualDefaults.is_projectile_class(visual_class),
			"%s maps to a projectile class" % preset
		)
		assert_false(seen.has(visual_class), "%s is distinct" % preset)
		seen.append(visual_class)
	assert_eq(seen.size(), EmissionPhase.PRESETS.size())


## Piece classes must NOT be mistaken for projectile ones — the report groups on this.
func test_piece_classes_are_not_projectile_classes() -> void:
	for visual_class: int in [
		VisualDefaults.VisualClass.BIO_UNIT,
		VisualDefaults.VisualClass.MECH_UNIT,
		VisualDefaults.VisualClass.AERIAL_UNIT,
		VisualDefaults.VisualClass.STRUCTURE
	]:
		assert_false(VisualDefaults.is_projectile_class(visual_class))


# --------------------------------------------------------------------------- #
# Placeholder meshes
# --------------------------------------------------------------------------- #
func test_every_class_has_a_placeholder_of_a_primitive_type() -> void:
	for visual_class: int in VisualDefaults.VisualClass.values():
		var mesh: Dictionary = VisualDefaults.placeholder_mesh(visual_class, Vector2i.ONE)
		assert_true(
			String(mesh["type"]).ends_with("Mesh"),
			"%s placeholder is a mesh type" % VisualDefaults.CLASS_NAMES[visual_class]
		)
		assert_false(
			(mesh["props"] as Dictionary).is_empty(),
			"%s placeholder is dimensioned" % VisualDefaults.CLASS_NAMES[visual_class]
		)


func test_structure_placeholder_takes_the_authored_footprint() -> void:
	var mesh: Dictionary = VisualDefaults.placeholder_mesh(
		VisualDefaults.VisualClass.STRUCTURE, Vector2i(6, 4)
	)
	var size: Vector3 = mesh["props"]["size"]
	assert_almost_eq(size.x, 6.0 * VisualDefaults.CELL_SIZE, 0.001)
	assert_almost_eq(size.z, 4.0 * VisualDefaults.CELL_SIZE, 0.001)
	assert_almost_eq(size.y, VisualDefaults.STRUCTURE_PLACEHOLDER_HEIGHT, 0.001)


## A scene that never set `dimensions` must not produce a zero-size box.
func test_degenerate_footprint_falls_back_to_one_cell() -> void:
	var mesh: Dictionary = VisualDefaults.placeholder_mesh(
		VisualDefaults.VisualClass.STRUCTURE, Vector2i.ZERO
	)
	var size: Vector3 = mesh["props"]["size"]
	assert_almost_eq(size.x, VisualDefaults.CELL_SIZE, 0.001)
	assert_almost_eq(size.z, VisualDefaults.CELL_SIZE, 0.001)


## The descriptor is handed out fresh: a caller that edits one must not corrupt the table
## every later caller reads.
func test_placeholder_descriptors_are_not_shared() -> void:
	var first: Dictionary = VisualDefaults.placeholder_mesh(
		VisualDefaults.VisualClass.BIO_UNIT, Vector2i.ONE
	)
	first["props"]["radius"] = 99.0
	var second: Dictionary = VisualDefaults.placeholder_mesh(
		VisualDefaults.VisualClass.BIO_UNIT, Vector2i.ONE
	)
	assert_ne(second["props"]["radius"], 99.0)


# --------------------------------------------------------------------------- #
# Selection shape
# --------------------------------------------------------------------------- #
func test_small_models_get_the_minimum_click_target() -> void:
	var shape: Dictionary = VisualDefaults.selection_shape(
		VisualDefaults.VisualClass.BIO_UNIT, INFANTRY_SIZE, Vector2i.ONE
	)
	assert_eq(shape["type"], "CylinderShape3D")
	assert_almost_eq(float(shape["props"]["radius"]), VisualDefaults.MIN_CLICK_RADIUS, 0.001)


func test_large_models_outgrow_the_floor_and_track_the_mesh() -> void:
	var shape: Dictionary = VisualDefaults.selection_shape(
		VisualDefaults.VisualClass.MECH_UNIT, VEHICLE_SIZE, Vector2i.ONE
	)
	# The LARGER horizontal axis, so a long hull stays clickable turned side-on.
	assert_almost_eq(float(shape["props"]["radius"]), VEHICLE_SIZE.z / 2.0, 0.001)
	assert_gt(float(shape["props"]["radius"]), VisualDefaults.MIN_CLICK_RADIUS)


func test_selection_height_never_collapses() -> void:
	var flat: Vector3 = Vector3(2.0, 0.01, 2.0)
	var shape: Dictionary = VisualDefaults.selection_shape(
		VisualDefaults.VisualClass.AERIAL_UNIT, flat, Vector2i.ONE
	)
	assert_almost_eq(float(shape["props"]["height"]), VisualDefaults.MIN_CLICK_HEIGHT, 0.001)


## The footprint wins over the mesh for structures: an overhanging roof must not become
## clickable ground.
func test_structure_selection_uses_the_footprint_not_the_mesh() -> void:
	var overhanging: Vector3 = Vector3(9.0, 3.0, 9.0)
	var shape: Dictionary = VisualDefaults.selection_shape(
		VisualDefaults.VisualClass.STRUCTURE, overhanging, Vector2i(2, 2)
	)
	assert_eq(shape["type"], "BoxShape3D")
	var size: Vector3 = shape["props"]["size"]
	assert_almost_eq(size.x, 2.0 * VisualDefaults.CELL_SIZE, 0.001)
	assert_almost_eq(size.z, 2.0 * VisualDefaults.CELL_SIZE, 0.001)
	assert_almost_eq(size.y, overhanging.y, 0.001)


func test_selection_shapes_are_always_trivial_primitives() -> void:
	const TRIVIAL: Array = ["CylinderShape3D", "BoxShape3D", "SphereShape3D", "CapsuleShape3D"]
	for visual_class: int in VisualDefaults.VisualClass.values():
		var shape: Dictionary = VisualDefaults.selection_shape(
			visual_class, VEHICLE_SIZE, Vector2i.ONE
		)
		assert_has(
			TRIVIAL,
			shape["type"],
			"%s selection shape is trivial" % VisualDefaults.CLASS_NAMES[visual_class]
		)


# --------------------------------------------------------------------------- #
# HP bar
# --------------------------------------------------------------------------- #
func test_bar_width_is_two_thirds_of_a_wide_model() -> void:
	var width: float = VisualDefaults.hp_bar_width(6.0)
	assert_almost_eq(width, 6.0 * VisualDefaults.HP_BAR_WIDTH_RATIO, 0.001)


func test_bar_width_floors_on_narrow_models() -> void:
	# An infantryman: two thirds of 0.4 is below the floor, so the floor wins.
	assert_almost_eq(
		VisualDefaults.hp_bar_width(INFANTRY_SIZE.x), VisualDefaults.HP_BAR_MIN_WIDTH, 0.001
	)


func test_bar_width_never_exceeds_a_model_it_floors_under() -> void:
	# Above the floor the bar is always narrower than the model it belongs to — the
	# regression the 2/3 ratio exists to prevent.
	for width: float in [1.0, 2.0, 4.0, 6.0]:
		assert_lt(
			VisualDefaults.hp_bar_width(width), width, "bar narrower than a %.1f-wide model" % width
		)


func test_bar_clears_the_top_of_the_model() -> void:
	var origin: Vector3 = VisualDefaults.hp_bar_origin(2.0)
	assert_gt(origin.y, 2.0, "bar sits above the model top")
	assert_almost_eq(origin.y, 2.0 + VisualDefaults.HP_BAR_CLEARANCE, 0.001)


## Zero is the CLEARED sentinel, so a real model must never derive it.
func test_bar_origin_is_never_the_zero_vector() -> void:
	for top: float in [0.0, 0.5, 2.0, 4.0]:
		assert_ne(
			VisualDefaults.hp_bar_origin(top),
			Vector3.ZERO,
			"model top %.1f derives a non-zero origin" % top
		)


# --------------------------------------------------------------------------- #
# Mirrored constants
# --------------------------------------------------------------------------- #
## The module mirrors Map.CELL_SIZE rather than importing it (referencing Map from the
## importer drags in the terrain stack). Pin the two so the mirror cannot drift.
func test_cell_size_matches_the_engine() -> void:
	assert_almost_eq(VisualDefaults.CELL_SIZE, Map.CELL_SIZE, 0.0001)


# --------------------------------------------------------------------------- #
# Placeholder extents
# --------------------------------------------------------------------------- #
## Every placeholder must report a real bounding size — the selection shape and HP bar of
## a piece with no art are derived from it, so a zero here silently makes both degenerate.
func test_every_placeholder_reports_a_positive_size() -> void:
	for visual_class: int in VisualDefaults.VisualClass.values():
		var mesh: Dictionary = VisualDefaults.placeholder_mesh(visual_class, Vector2i.ONE)
		var size: Vector3 = VisualDefaults.placeholder_size(mesh)
		var label: String = VisualDefaults.CLASS_NAMES[visual_class]
		assert_gt(size.x, 0.0, "%s placeholder has width" % label)
		assert_gt(size.y, 0.0, "%s placeholder has height" % label)
		assert_gt(size.z, 0.0, "%s placeholder has depth" % label)


func test_placeholder_size_reads_each_primitive_correctly() -> void:
	assert_eq(
		VisualDefaults.placeholder_size(
			{"type": "BoxMesh", "props": {"size": Vector3(1.0, 2.0, 3.0)}}
		),
		Vector3(1.0, 2.0, 3.0)
	)
	assert_eq(
		VisualDefaults.placeholder_size(
			{"type": "CapsuleMesh", "props": {"radius": 0.5, "height": 2.0}}
		),
		Vector3(1.0, 2.0, 1.0)
	)
	# A cone: the wider end sets the width.
	assert_eq(
		VisualDefaults.placeholder_size(
			{
				"type": "CylinderMesh",
				"props": {"top_radius": 0.0, "bottom_radius": 0.25, "height": 1.0}
			}
		),
		Vector3(0.5, 1.0, 0.5)
	)


## An impact burst that looks like the shell that caused it marks nothing.
func test_impact_burst_differs_from_every_trajectory_mesh() -> void:
	var burst: Dictionary = VisualDefaults.impact_burst_mesh()
	assert_gt(VisualDefaults.placeholder_size(burst).y, 0.0, "the burst is dimensioned")
	var phases: Dictionary = _preset_phases()
	for preset: String in phases:
		var in_flight: Dictionary = VisualDefaults.placeholder_mesh(
			VisualDefaults.classify_projectile(phases[preset]), Vector2i.ONE
		)
		assert_ne(
			VisualDefaults.placeholder_size(in_flight),
			VisualDefaults.placeholder_size(burst),
			"%s's burst is distinguishable from its shell" % preset
		)


# --------------------------------------------------------------------------- #
# Hurtbox
# --------------------------------------------------------------------------- #
func _hurtbox(
	a_class: int,
	a_size: Vector3,
	a_top: float,
	a_cells: Vector2i = Vector2i.ONE,
	a_fixture: bool = false
) -> Dictionary:
	return VisualDefaults.hurtbox_shape(a_class, a_size, a_top, a_cells, a_fixture)


func test_a_bio_unit_takes_a_cylinder_around_its_model() -> void:
	var shape: Dictionary = _hurtbox(VisualDefaults.VisualClass.BIO_UNIT, INFANTRY_SIZE, 1.0)
	assert_eq(shape["type"], "CylinderShape3D")
	assert_almost_eq(float(shape["props"]["radius"]), 0.2, 0.0001)
	assert_almost_eq(float(shape["props"]["height"]), 1.0, 0.0001)


func test_a_mech_unit_takes_a_box_of_its_model() -> void:
	var shape: Dictionary = _hurtbox(VisualDefaults.VisualClass.MECH_UNIT, VEHICLE_SIZE, 0.6)
	assert_eq(shape["type"], "BoxShape3D")
	assert_eq(shape["props"]["size"], VEHICLE_SIZE)


func test_an_aircraft_takes_a_cylinder() -> void:
	var shape: Dictionary = _hurtbox(VisualDefaults.VisualClass.AERIAL_UNIT, VEHICLE_SIZE, 0.5)
	assert_eq(shape["type"], "CylinderShape3D")
	assert_almost_eq(float(shape["props"]["radius"]), 1.05, 0.0001, "the wider side, halved")


func test_a_fixture_takes_its_footprint_not_its_mesh() -> void:
	var overhanging := Vector3(5.0, 2.0, 5.0)
	var shape: Dictionary = _hurtbox(
		VisualDefaults.VisualClass.STRUCTURE, overhanging, 2.0, Vector2i(4, 3), true
	)
	assert_eq(shape["type"], "BoxShape3D")
	assert_eq(shape["props"]["size"], Vector3(4.0, 2.0, 3.0))


func test_it_stands_on_the_origin_and_never_reaches_below_it() -> void:
	# A model whose mesh dips below the origin (an aircraft's belly) is cut off at the base.
	var shape: Dictionary = _hurtbox(VisualDefaults.VisualClass.BIO_UNIT, Vector3(1, 1, 1), 0.7)
	assert_almost_eq(float(shape["props"]["height"]), 0.7, 0.0001)
	assert_almost_eq(float(shape["center_y"]), 0.35, 0.0001, "bottom at the origin")
	# One that floats above it starts where the model does.
	var raised: Dictionary = _hurtbox(VisualDefaults.VisualClass.BIO_UNIT, Vector3(1, 1, 1), 1.5)
	assert_almost_eq(
		float(raised["center_y"]) - float(raised["props"]["height"]) / 2.0, 0.5, 0.0001
	)


func test_a_sliver_of_a_model_stays_hittable() -> void:
	var shape: Dictionary = _hurtbox(VisualDefaults.VisualClass.BIO_UNIT, Vector3.ZERO, 0.0)
	assert_eq(float(shape["props"]["radius"]), VisualDefaults.MIN_HURTBOX_RADIUS)
	assert_eq(float(shape["props"]["height"]), VisualDefaults.MIN_HURTBOX_HEIGHT)


func _with_hurtbox(a_shape: Shape3D, a_stamped: bool) -> Node3D:
	var root: Node3D = autofree(Node3D.new())
	var hurtbox: StaticBody3D = StaticBody3D.new()
	hurtbox.name = "Hurtbox"
	root.add_child(hurtbox)
	var node: CollisionShape3D = CollisionShape3D.new()
	node.name = "HurtboxShape"
	node.shape = a_shape
	if a_stamped:
		node.set_meta(VisualMeasure.STAMP_HURTBOX, "CylinderShape3D")
	hurtbox.add_child(node)
	return root


func test_an_empty_hurtbox_is_the_ask_for_a_fit() -> void:
	assert_true(VisualMeasure.hurtbox_is_cleared(_with_hurtbox(null, false)))
	assert_false(VisualMeasure.hurtbox_is_cleared(_with_hurtbox(CylinderShape3D.new(), false)))


func test_the_hurtbox_doc_key_is_retired() -> void:
	var spec: Dictionary = {"body": {"radius": 0.3, "hurtbox": 0.4}}
	var errors: Array = SpecSchema.normalize(spec)
	assert_true(
		errors.any(func(e: String) -> bool: return e.contains("fitted to the model")),
		"refused, saying where the hurtbox comes from now: %s" % [errors]
	)
