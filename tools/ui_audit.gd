extends SceneTree

## VISUAL AUDIT — a REPORT, not a gate.
##
## Answers the three questions no test covers: does this piece have anything to look at,
## is it still wearing the importer's stand-in, and do its selection shape and HP bar
## comport with the model they belong to. Run:
##   godot --headless -s res://tools/ui_audit.gd
##
## Shares its measuring and its rules with the importer (visual_measure.gd,
## visual_defaults.gd), so "this piece has no visual" means the same thing in the thing
## that fixes it and the thing that lists it. Nothing is added to the SceneTree: instances
## are walked with hand-composed transforms, so no _ready fires.
##
## The three slot states this prints are worth keeping straight:
##   generated — the importer baked it and nobody has touched it since
##   tuned     — the importer baked it and a human has since changed the value
##   authored  — a value that was never the importer's, so the importer will not
##               regenerate it. CLEARING it is what asks for a fresh bake.

const VisualDefaults := preload("res://tools/spec_import/visual_defaults.gd")
const VisualMeasure := preload("res://tools/spec_import/visual_measure.gd")

const PIECE_DIRS: Array = [
	"res://scenes/entities/units",
	"res://scenes/entities/structures",
]
const PROJECTILE_DIR: String = "res://scenes/entities/projectiles"

## How far a baked HP-bar width may drift from its stamp before it counts as hand-tuned.
## Generous, because the width round-trips through a Sprite3D scale and back.
const WIDTH_DRIFT_EPSILON: float = 0.01


func _init() -> void:
	var pieces: Array = []
	for dir: String in PIECE_DIRS:
		for path: String in _scenes_under(dir):
			var row: Dictionary = _measure_piece(path)
			if not row.is_empty():
				pieces.append(row)
	var projectiles: Array = []
	for path: String in _scenes_under(PROJECTILE_DIR):
		var row: Dictionary = _measure_projectile(path)
		if not row.is_empty():
			projectiles.append(row)
	_report(pieces, projectiles)
	quit()


func _scenes_under(a_dir: String) -> Array:
	var out: Array = []
	var dir: DirAccess = DirAccess.open(a_dir)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var full: String = a_dir + "/" + entry
		if dir.current_is_dir():
			out.append_array(_scenes_under(full))
		elif entry.ends_with(".tscn"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


## Instantiates a scene and returns its 3D root, or null if it has none. Callers decide
## what counts as auditable — the two directories hold different things.
func _open_scene(a_path: String) -> Node3D:
	var packed: PackedScene = load(a_path) as PackedScene
	if packed == null:
		return null
	var root: Node = packed.instantiate()
	if not (root is Node3D):
		if root != null:
			root.free()
		return null
	return root as Node3D


## Skips what is not a game piece: scenery props with no `id` property at all (rocks,
## mountains) and the abstract inheritance bases, whose id is deliberately empty.
func _measure_piece(a_path: String) -> Dictionary:
	var entity: Node3D = _open_scene(a_path)
	if entity == null:
		return {}
	if not ("id" in entity) or String(entity.id).is_empty():
		entity.free()
		return {}
	var defense: Node = entity.get_node_or_null("Defense")
	var movement: Movement = entity.get_node_or_null("Locomotion") as Movement
	var structure: Node = entity.get_node_or_null("Fixture")
	var visual_class: int = VisualDefaults.classify_piece(
		defense.frame_type if defense != null else Defense.FrameType.BIO,
		movement.mode if movement != null else Movement.Mode.GROUNDED,
		structure != null
	)
	var measurement: Dictionary = VisualMeasure.measure(entity)
	var width: float = VisualMeasure.model_width(measurement)
	var row: Dictionary = {
		"id": String(entity.id) if "id" in entity else a_path.get_file(),
		"path": a_path,
		"class": visual_class,
		"width": width,
		"top": measurement["top"],
		"has_mesh": measurement["has_mesh"],
		"is_placeholder": measurement["is_placeholder"],
		"selection": _selection_state(entity),
		"hp_bar": _hp_bar_state(entity, width, measurement["top"]),
	}
	entity.free()
	return row


## Projectiles are keyed by scene name, not by id: an inline projectile hoisted out of a
## weapon's `projectile: {...}` dict has no doc of its own and so carries no id.
func _measure_projectile(a_path: String) -> Dictionary:
	var root: Node3D = _open_scene(a_path)
	if root == null:
		return {}
	if (
		not (root.get_node_or_null("Locomotion") is PhasedLocomotion)
		or a_path.get_file() == "projectile.tscn"
	):
		root.free()
		return {}
	var phases: Array = root.get_children().filter(func(c: Node) -> bool: return c is EmissionPhase)
	var first_phase: Dictionary = {}
	if not phases.is_empty():
		for property: String in [
			"gravity_mps2", "launch_pitch_degrees", "turn_rate_degrees_per_second"
		]:
			first_phase[property] = phases[0].get(property)
	var in_flight: Node = root.get_node_or_null(VisualMeasure.IN_FLIGHT_MESH_NODE)
	var row: Dictionary = {
		"id": "%s/%s" % [a_path.get_base_dir().get_file(), a_path.get_file().get_basename()],
		"path": a_path,
		"class": VisualDefaults.classify_projectile(first_phase),
		"persists":
		phases.slice(1).any(
			func(p: EmissionPhase) -> bool: return p.duration_ticks() < 0 or p.duration_ticks() > 1
		),
		"has_in_flight_mesh": in_flight != null,
		"is_placeholder": in_flight != null and in_flight.has_meta(VisualMeasure.STAMP_MESH),
		"has_post_impact": root.get_node_or_null(VisualMeasure.POST_IMPACT_MESH_NODE) != null,
	}
	root.free()
	return row


## generated / tuned / authored / missing — see the header.
func _selection_state(a_entity: Node3D) -> String:
	var node: CollisionShape3D = (
		a_entity.get_node_or_null(VisualMeasure.SELECTION_SHAPE_PATH) as CollisionShape3D
	)
	if node == null or node.shape == null:
		return "missing"
	if not node.has_meta(VisualMeasure.STAMP_SELECTION):
		return "authored"
	return (
		"generated"
		if node.shape.get_class() == String(node.get_meta(VisualMeasure.STAMP_SELECTION))
		else "tuned"
	)


func _hp_bar_state(a_entity: Node3D, a_model_width: float, a_model_top: float) -> Dictionary:
	var bar: Node3D = a_entity.get_node_or_null(VisualMeasure.HP_BAR_PATH) as Node3D
	var scale_per_unit: float = VisualMeasure.hp_bar_scale_per_world_unit(a_entity)
	if bar == null or scale_per_unit <= 0.0:
		return {"state": "missing", "width": 0.0, "clearance": 0.0}
	var width: float = bar.transform.basis.get_scale().x / scale_per_unit
	var state: String = "authored"
	if bar.transform.origin.is_zero_approx():
		state = "missing"
	elif bar.has_meta(VisualMeasure.STAMP_HP_BAR):
		state = (
			"generated"
			if absf(width - float(bar.get_meta(VisualMeasure.STAMP_HP_BAR))) < WIDTH_DRIFT_EPSILON
			else "tuned"
		)
	return {
		"state": state,
		"width": width,
		"ratio": width / a_model_width if a_model_width > 0.0 else NAN,
		# Negative = the bar sits below the top of its own model, i.e. inside it.
		"clearance": bar.transform.origin.y - a_model_top,
	}


# --------------------------------------------------------------------------- #
# Report
# --------------------------------------------------------------------------- #
func _report(a_pieces: Array, a_projectiles: Array) -> void:
	print(
		(
			"\n=== VISUAL AUDIT — %d pieces, %d projectiles ==="
			% [a_pieces.size(), a_projectiles.size()]
		)
	)
	_report_invisible(a_pieces, a_projectiles)
	_report_placeholders(a_pieces, a_projectiles)
	_report_awaiting_clear(a_pieces)
	_report_proportions(a_pieces)


## The hard invariant: nothing in the game may be invisible. After an import this should be
## empty, and anything in it is a scene the importer could not reach.
func _report_invisible(a_pieces: Array, a_projectiles: Array) -> void:
	var names: Array = []
	for row: Dictionary in a_pieces:
		if not row["has_mesh"]:
			names.append(row["id"])
	for row: Dictionary in a_projectiles:
		if not row["has_in_flight_mesh"]:
			names.append(row["id"])
	_print_section(
		"NOTHING TO LOOK AT",
		names,
		"an import should leave this empty — anything here has no visual at all"
	)


## The question this report exists for: which pieces are still wearing a stand-in.
func _report_placeholders(a_pieces: Array, a_projectiles: Array) -> void:
	var by_class: Dictionary = {}
	for row: Dictionary in a_pieces + a_projectiles:
		if row["is_placeholder"]:
			by_class.get_or_add(row["class"], []).append(row["id"])
	var total: int = 0
	for ids: Array in by_class.values():
		total += ids.size()
	print("\nSTILL ON A GENERATED PLACEHOLDER — %d" % total)
	if total == 0:
		print("  (none — every piece has art of its own)")
		return
	for visual_class: int in VisualDefaults.VisualClass.values():
		if not by_class.has(visual_class):
			continue
		var ids: Array = by_class[visual_class]
		ids.sort()
		print(
			(
				"  %-22s %2d  %s"
				% [VisualDefaults.CLASS_NAMES[visual_class], ids.size(), ", ".join(ids)]
			)
		)


## Values the importer will NOT regenerate, because they were never its. Clearing one is
## what asks for a fresh bake (see visual_defaults.gd) — this is the list of clears to make.
func _report_awaiting_clear(a_pieces: Array) -> void:
	var selection: Array = []
	var bars: Array = []
	for row: Dictionary in a_pieces:
		if row["selection"] == "authored":
			selection.append(row["id"])
		var bar: Dictionary = row["hp_bar"]
		if bar["state"] == "authored":
			bars.append(
				(
					"%s (bar %.2f wide vs model %.2f, sits %+.2f from its top)"
					% [row["id"], bar["width"], row["width"], bar["clearance"]]
				)
			)
	_print_section(
		"HP BAR AWAITING A CLEAR",
		bars,
		"hand-authored transforms — clear the HPBar transform to take the derived one"
	)
	_print_section(
		"SELECTION SHAPE AWAITING A CLEAR",
		selection,
		"hand-authored shapes — clear the shape to take the derived one"
	)


## The proportions themselves, for the pieces where they are worth an eye: anything whose
## bar or click target is wildly out of step with the model it belongs to.
func _report_proportions(a_pieces: Array) -> void:
	var rows: Array = []
	for row: Dictionary in a_pieces:
		var bar: Dictionary = row["hp_bar"]
		if bar["state"] == "missing" or row["width"] <= 0.0:
			continue
		if bar["clearance"] < 0.0 or float(bar.get("ratio", 0.0)) > 1.0:
			rows.append(row)
	print("\nOUT OF STEP WITH THEIR MODEL — %d" % rows.size())
	if rows.is_empty():
		print("  (none)")
		return
	print("  %-34s %6s %6s %6s %7s" % ["id", "model", "barW", "bar/W", "clear"])
	for row: Dictionary in rows:
		var bar: Dictionary = row["hp_bar"]
		print(
			(
				"  %-34s %6.2f %6.2f %6.2f %+7.2f"
				% [
					row["id"],
					row["width"],
					bar["width"],
					float(bar.get("ratio", NAN)),
					bar["clearance"]
				]
			)
		)


func _print_section(a_title: String, a_entries: Array, a_hint: String) -> void:
	print("\n%s — %d" % [a_title, a_entries.size()])
	if a_entries.is_empty():
		print("  (none)")
		return
	print("  (%s)" % a_hint)
	for entry: String in a_entries:
		print("  %s" % entry)
