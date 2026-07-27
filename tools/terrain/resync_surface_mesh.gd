extends SceneTree

## Rewrite a map's brushable SURFACE MESH from its `TerrainData.heights`, so the two agree
## again and `Map.bake_terrain_from_mesh` becomes a no-op instead of a demolition.
##
##   godot --headless --path . -s res://tools/terrain/resync_surface_mesh.gd -- \
##     res://resources/terrain/mesh_plateau_terrain.tres
##
## Pass no path and it REPORTS on every terrain resource it can find and changes nothing.
##
## WHY THIS IS NEEDED. `<map>.tres`'s `heights` and `<map>_surface.res`'s vertex Y are the same
## surface twice (CLAUDE.md §Regenerating data). `Map.sync_source_mesh_heights` keeps them in
## step while the editor is open, but it mutates the ArrayMesh IN MEMORY and never saves it —
## the `.res` on disk is only written by `Map.create_terrain_mesh`, which lays down a FLAT
## grid. So a map sculpted after its surface was created ships a hilly `.tres` and a flat
## `.res`, looks wrong in the viewport, and FLATTENS the moment anyone rebakes. This puts the
## mesh back where the heights say it should be.
##
## HEIGHTS ARE TREATED AS PRIMARY here, which is the right way round for a brush- or
## generator-authored map. For a map whose surface was MODELLED elsewhere the mesh is primary
## and this tool is the wrong direction — rebake instead.
##
## Nothing is written unless a path is given, and a rewrite is followed by the same
## rebake-is-a-no-op check `make_symmetric_terrain.gd` ends with.

const TERRAIN_DIR: String = "res://resources/terrain"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		_report_all()
		quit(0)
		return
	quit(0 if _resync(args[0]) else 1)


## Read-only survey: for every terrain resource with a surface mesh beside it, how far a
## rebake would move the heightfield. Anything non-zero is a map one click from flattening.
func _report_all() -> void:
	print("(no path given — reporting only, nothing written)")
	var dir := DirAccess.open(TERRAIN_DIR)
	if dir == null:
		return
	for name: String in dir.get_files():
		if not name.ends_with(".tres") or name.ends_with("_shape.tres"):
			continue
		var tres: String = "%s/%s" % [TERRAIN_DIR, name]
		var mesh_path: String = tres.get_basename() + "_surface.res"
		if not ResourceLoader.exists(mesh_path):
			continue
		var data: TerrainData = ResourceLoader.load(tres, "", ResourceLoader.CACHE_MODE_IGNORE)
		var mesh: Mesh = ResourceLoader.load(mesh_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if data == null or mesh == null:
			continue
		print("%-46s rebake would move heights by %.6f" % [name, _rebake_residual(data, mesh)])


func _resync(a_tres: String) -> bool:
	var data: TerrainData = ResourceLoader.load(a_tres, "", ResourceLoader.CACHE_MODE_IGNORE)
	if data == null:
		push_error("resync_surface_mesh: cannot load %s" % a_tres)
		return false
	var dims: Vector2i = data.dimensions
	if data.heights.size() != dims.x * dims.y:
		push_error("resync_surface_mesh: %s has %d heights, expected %d — refusing to guess"
			% [a_tres, data.heights.size(), dims.x * dims.y])
		return false

	var mesh_path: String = a_tres.get_basename() + "_surface.res"
	var before: float = INF
	if ResourceLoader.exists(mesh_path):
		var old: Mesh = ResourceLoader.load(mesh_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if old != null:
			before = _rebake_residual(data, old)
	print("%s: %dx%d corners, rebake residual BEFORE %s"
		% [a_tres.get_file(), dims.x, dims.y, "n/a" if is_inf(before) else "%.6f" % before])

	var mesh := ArrayMesh.new()
	TerrainMeshGrid.write_heights(mesh, dims, data.heights)
	var err: int = ResourceSaver.save(mesh, mesh_path)
	if err != OK:
		push_error("resync_surface_mesh: could not save %s (%d)" % [mesh_path, err])
		return false
	print("wrote %s (aabb %s)" % [mesh_path.get_file(), mesh.get_aabb()])

	# The check that makes the result trustworthy: re-read from DISK and bake.
	var fresh_data: TerrainData = ResourceLoader.load(a_tres, "", ResourceLoader.CACHE_MODE_IGNORE)
	var fresh_mesh: Mesh = ResourceLoader.load(mesh_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var after: float = _rebake_residual(fresh_data, fresh_mesh)
	print("rebake residual AFTER  %.9f   <- must be 0" % after)
	return after == 0.0


## How far baking `a_mesh` would move `a_data.heights`. Operates on a COPY, so the caller's
## resource is untouched.
func _rebake_residual(a_data: TerrainData, a_mesh: Mesh) -> float:
	var before: PackedFloat32Array = a_data.heights.duplicate()
	var probe: TerrainData = a_data.duplicate(false)
	probe.bake_source_mesh(a_mesh)
	if probe.heights.size() != before.size():
		return INF
	var worst: float = 0.0
	for i: int in before.size():
		worst = maxf(worst, absf(before[i] - probe.heights[i]))
	return worst
