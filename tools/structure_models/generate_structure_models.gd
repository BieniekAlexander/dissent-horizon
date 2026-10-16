extends Node

## Builds the Colonial and neutral structure models (StructureModels) and writes each as an
## ArrayMesh to assets/meshes/entities/structures/<id>.res, which the piece's MeshVisual
## instances as its `Model`.
##
## Run with:
##   godot --headless --path . res://tools/structure_models/generate_structure_models.tscn
## Add `-- --check` to measure and report without writing anything. It runs as a scene rather
## than with `-s` because a bare script cannot see the project's autoloads, which the piece
## scripts it reaches name (see tools/run_import.gd).
##
## Every model is measured against the obstruction budget first (ObstructionMeasure), and if
## ANY is over it — or reaches past its footprint — NOTHING is written: the run fails, naming
## the worst view of each offender.
##
## Everything it measures against is read from where the game keeps it, never retyped: each
## footprint from the piece scene's Fixture, the figure from the reference infantry's hurtbox,
## the camera's elevation from RTSCamera3D.
##
## The .res files are generated: edit StructureModels and rerun, never the meshes.

#region Constants
const OUTPUT_DIR: String = "res://assets/meshes/entities/structures/"
## Where the environmental tokens' models go (StructureModels.token_catalog).
const TOKEN_OUTPUT_DIR: String = "res://assets/meshes/entities/tokens/"
const SPEC_ROOT: String = "res://gdd/"

## The figure the budget protects: the Colonial Recruit, the game's baseline infantry.
const REFERENCE_INFANTRY: StringName = EntityIds.CL_BIO_LIGHT_ANTI_LIGHT

## The most of a figure behind a structure that the structure's model may hide.
const MAX_HIDDEN_FRACTION: float = 0.5

## Camera yaws tried, evenly round the circle. The player turns the camera freely; 15°
## steps include the default 45° and catch any model's worst side.
const YAW_COUNT: int = 24

## How far a generated model may reach past its footprint, in world units: rounding only. A
## model is built inside its footprint so that it stands on exactly the cells it claims.
const OVERHANG_TOLERANCE: float = 0.001
#endregion


func _ready() -> void:
	var is_check_only: bool = "--check" in OS.get_cmdline_user_args()
	var spec_scenes: Dictionary = _spec_scenes(SPEC_ROOT)
	var figure: CylinderShape3D = _hurtbox(spec_scenes[REFERENCE_INFANTRY])
	var elevation: float = asin(RTSCamera3D.initial_position().normalized().y)
	print(
		(
			"Obstruction budget: %d%% of a %s (r %.2f, h %.2f) at %.0f° elevation, %d yaws"
			% [
				MAX_HIDDEN_FRACTION * 100.0,
				REFERENCE_INFANTRY,
				figure.radius,
				figure.height,
				rad_to_deg(elevation),
				YAW_COUNT
			]
		)
	)
	var catalog: Dictionary = StructureModels.catalog()
	var results: Array[Dictionary] = []
	for id: StringName in catalog:
		var result: Dictionary = _build_and_measure(
			id, spec_scenes[id], catalog[id], figure, elevation
		)
		print(_report_line(result))
		results.append(result)
	# A token's extents are authored in its catalog entry; it claims no cells and is itself
	# figure-sized, so only the overhang check applies.
	var tokens: Dictionary = StructureModels.token_catalog()
	for id: StringName in tokens:
		var entry: Dictionary = tokens[id]
		var result: Dictionary = _build_and_measure(
			id, spec_scenes[id], entry["build"], figure, elevation, entry["half"]
		)
		result["is_token"] = true
		print(_report_line(result))
		results.append(result)
	if results.any(_is_refused):
		push_error("Structure models failed their checks; nothing was written.")
		get_tree().quit(1)
		return
	get_tree().quit(OK if is_check_only else _write(results))


## One piece's model, built by `build` on its footprint, and how it measures:
## `{id, footprint, triangle_count, worst, overhang, mesh}`.
func _build_and_measure(
	id: StringName,
	scene_path: String,
	build: Callable,
	figure: CylinderShape3D,
	elevation: float,
	half_override: Vector2 = Vector2.ZERO
) -> Dictionary:
	var footprint: Vector2 = (
		half_override * 2.0
		if half_override != Vector2.ZERO
		else Vector2(_footprint(scene_path)) * Map.CELL_SIZE
	)
	var parts: Dictionary = build.call(footprint * 0.5)
	var triangles: PackedVector3Array = StructureModels.all_triangles(parts)
	return {
		"id": id,
		"footprint": footprint,
		"triangle_count": triangles.size() / 3,
		"worst":
		ObstructionMeasure.worst_case(
			triangles, footprint, figure.radius, figure.height, elevation, YAW_COUNT
		),
		"overhang": _overhang(triangles, footprint * 0.5),
		"mesh": StructureModels.to_mesh(parts),
	}


## A model is refused for hiding too much or for reaching past its footprint.
func _is_refused(result: Dictionary) -> bool:
	return _is_over_budget(result) or _is_overhanging(result)


func _is_over_budget(result: Dictionary) -> bool:
	if result.get("is_token", false):
		return false
	return result["worst"]["fraction"] > MAX_HIDDEN_FRACTION


func _is_overhanging(result: Dictionary) -> bool:
	return result["overhang"] > OVERHANG_TOLERANCE


func _report_line(result: Dictionary) -> String:
	var worst: Dictionary = result["worst"]
	var notes: PackedStringArray = PackedStringArray()
	if _is_over_budget(result):
		notes.append(
			"OVER BUDGET at yaw %.0f°, figure at %s" % [worst["yaw_degrees"], worst["position"]]
		)
	if _is_overhanging(result):
		notes.append("OUTSIDE ITS FOOTPRINT by %.2f" % result["overhang"])
	var footprint: Vector2 = result["footprint"]
	return (
		"  %-26s %3d×%-3d %4d tris  hides %3d%%  %s"
		% [
			result["id"],
			footprint.x,
			footprint.y,
			result["triangle_count"],
			roundi(worst["fraction"] * 100.0),
			"  ".join(notes)
		]
	)


## How far the model reaches past the footprint of half-extents `half`, in world units.
func _overhang(triangles: PackedVector3Array, half: Vector2) -> float:
	var furthest: float = 0.0
	for v: Vector3 in triangles:
		furthest = maxf(furthest, maxf(absf(v.x) - half.x, absf(v.z) - half.y))
	return furthest


func _write(results: Array[Dictionary]) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TOKEN_OUTPUT_DIR))
	for result: Dictionary in results:
		var directory: String = TOKEN_OUTPUT_DIR if result.get("is_token", false) else OUTPUT_DIR
		var path: String = directory + String(result["id"]) + ".res"
		var error: Error = ResourceSaver.save(result["mesh"], path)
		if error != OK:
			push_error("Could not write %s: %s" % [path, error_string(error)])
			return error
	print("Wrote %d models to %s" % [results.size(), OUTPUT_DIR])
	return OK


## Piece id → its scene path, from every spec doc's `scene:` frontmatter line. A spec's
## FILE NAME is its piece id.
func _spec_scenes(root: String) -> Dictionary:
	var out: Dictionary = {}
	for directory: String in DirAccess.get_directories_at(root):
		out.merge(_spec_scenes(root.path_join(directory)))
	for file: String in DirAccess.get_files_at(root):
		if file.get_extension() != "md":
			continue
		for line: String in FileAccess.get_file_as_string(root.path_join(file)).split("\n"):
			if line.begins_with("scene:"):
				out[StringName(file.get_basename())] = line.trim_prefix("scene:").strip_edges()
				break
	return out


## The footprint a piece scene's Fixture declares, in cells. Read from the packed scene's
## state rather than an instance, so no piece script runs.
func _footprint(scene_path: String) -> Vector2i:
	var state: SceneState = (load(scene_path) as PackedScene).get_state()
	for node: int in range(state.get_node_count()):
		if state.get_node_name(node) != &"Fixture":
			continue
		for property: int in range(state.get_node_property_count(node)):
			if state.get_node_property_name(node, property) == &"dimensions":
				return state.get_node_property_value(node, property)
	return Vector2i.ONE


func _hurtbox(scene_path: String) -> CylinderShape3D:
	var state: SceneState = (load(scene_path) as PackedScene).get_state()
	for node: int in range(state.get_node_count()):
		if state.get_node_name(node) != &"HurtboxShape":
			continue
		for property: int in range(state.get_node_property_count(node)):
			if state.get_node_property_name(node, property) == &"shape":
				return state.get_node_property_value(node, property)
	assert(false, "%s has no hurtbox cylinder" % scene_path)
	return null
