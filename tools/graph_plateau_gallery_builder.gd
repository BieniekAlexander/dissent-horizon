extends RefCounted

## Builds the GraphPlateauHeightmapGenerator gallery: bakes a grid of variations
## into a single scene, saves each variation's generator + heightmap .tres, and
## writes a stats README.  Kept as a plain RefCounted (no EditorScript) so it can
## run both from the editor wrapper and from a headless harness/test.
##
## Preload and call:  GalleryBuilder.new().build()

const OUTPUT_DIR: String = "res://resources/graph_plateau_batch"
const FIXED_SEED: int = 7
const HEIGHT_STEP: float = 1.0
const RAMP_RUN: int = 4
const RAMP_HALF_WIDTH: float = 2.5
const COLS: int = 3

const REGION_COUNTS: Array = [8, 14, 22]
const HEIGHT_LEVELS: Array = [3, 4, 5]


## Generate everything.  Returns { scene_path, ok, entries }.
func build() -> Dictionary:
	_ensure_output_dir()

	# Match the project map's extent so baked shapes are drop-in for Map.height_map.
	var map_shape: HeightMapShape3D = load("res://resources/map.tres")
	var w: int = map_shape.map_width
	var d: int = map_shape.map_depth
	var spacing: float = float(maxi(w, d)) + 8.0

	var root := Node3D.new()
	root.name = "GraphPlateauGallery"

	var entries: Array = []
	var i: int = 0
	for rc: int in REGION_COUNTS:
		for hl: int in HEIGHT_LEVELS:
			var col: int = i % COLS
			var row: int = i / COLS
			var origin := Vector3(col * spacing, 0.0, row * spacing)
			entries.append(_bake_one(root, rc, hl, w, d, origin))
			i += 1

	var rows: int = int(ceil(float(entries.size()) / COLS))
	_add_lighting_and_camera(root, spacing, COLS, rows)

	var packed := PackedScene.new()
	packed.pack(root)
	var scene_path: String = OUTPUT_DIR + "/graph_plateau_gallery.tscn"
	var err: int = ResourceSaver.save(packed, scene_path)
	root.free()
	if err != OK:
		push_error("GalleryBuilder: failed to save scene (error %d)" % err)

	_write_readme(entries)
	return {"scene_path": scene_path, "ok": err == OK, "entries": entries}


## Generate one variation: save its generator + baked shape, add a labelled mesh
## tile to the gallery, and return its stats.
func _bake_one(root: Node3D, rc: int, hl: int, w: int, d: int, origin: Vector3) -> Dictionary:
	var gen := GraphPlateauHeightmapGenerator.new()
	gen.width = w
	gen.depth = d
	gen.region_count = rc
	gen.height_levels = hl
	gen.height_step = HEIGHT_STEP
	gen.ramp_run = RAMP_RUN
	gen.ramp_half_width = RAMP_HALF_WIDTH
	gen.seed = FIXED_SEED

	var data: PackedFloat32Array = gen.generate()

	var shape := HeightMapShape3D.new()
	shape.map_width = w
	shape.map_depth = d
	shape.map_data = data

	var tag: String = "rc%d_hl%d" % [rc, hl]
	ResourceSaver.save(gen, OUTPUT_DIR + "/gp_%s.tres" % tag)
	ResourceSaver.save(shape, OUTPUT_DIR + "/hm_%s.tres" % tag)

	# Build the visual mesh with the canonical HeightmapMeshGenerator, off-tree.
	var mesh_gen := HeightmapMeshGenerator.new()
	mesh_gen.shape = shape
	mesh_gen.build()
	var mesh: ArrayMesh = mesh_gen.mesh
	mesh_gen.free()

	var tile := MeshInstance3D.new()
	tile.name = "tile_%s" % tag
	tile.mesh = mesh
	tile.position = origin
	root.add_child(tile)
	tile.owner = root

	var stats: Dictionary = _stats(data, w, d)
	var label := Label3D.new()
	label.name = "label_%s" % tag
	label.text = "rc=%d hl=%d\n%d%% pass" % [rc, hl, stats["passable_pct"]]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = origin + Vector3(0.0, float(hl) * HEIGHT_STEP + 4.0, 0.0)
	label.modulate = Color.WHITE if stats["connected"] else Color.RED
	root.add_child(label)
	label.owner = root

	return {
		"region_count": rc,
		"height_levels": hl,
		"tag": tag,
		"passable_pct": stats["passable_pct"],
		"flat_pct": stats["flat_pct"],
		"connected": stats["connected"],
	}


func _add_lighting_and_camera(root: Node3D, spacing: float, cols: int, rows: int) -> void:
	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.rotation_degrees = Vector3(-55.0, -40.0, 0.0)
	light.light_energy = 1.1
	root.add_child(light)
	light.owner = root

	var center := Vector3((cols - 1) * spacing * 0.5, 0.0, (rows - 1) * spacing * 0.5)
	var cam := Camera3D.new()
	cam.name = "GalleryCamera"
	cam.position = center + Vector3(0.0, spacing * 1.6, spacing * 1.8)
	cam.rotation_degrees = Vector3(-42.0, 0.0, 0.0)
	cam.current = true
	root.add_child(cam)
	cam.owner = root


# --- Stats (mirrors TerrainGrid passability: corner spread > 0.5 = impassable) ---

func _stats(data: PackedFloat32Array, w: int, d: int) -> Dictionary:
	var gw: int = w - 1
	var gh: int = d - 1
	var passable := PackedByteArray()
	passable.resize(gw * gh)
	var pass_count: int = 0
	var flat_count: int = 0
	for z: int in gh:
		for x: int in gw:
			var h00: float = data[z * w + x]
			var h10: float = data[z * w + x + 1]
			var h01: float = data[(z + 1) * w + x]
			var h11: float = data[(z + 1) * w + x + 1]
			var hi: float = maxf(maxf(h00, h10), maxf(h01, h11))
			var lo: float = minf(minf(h00, h10), minf(h01, h11))
			if (hi - lo) <= 0.5:
				passable[z * gw + x] = 1
				pass_count += 1
			if is_equal_approx(hi, lo):
				flat_count += 1

	var seen := PackedByteArray()
	seen.resize(gw * gh)
	var components: int = 0
	for z: int in gh:
		for x: int in gw:
			if passable[z * gw + x] == 1 and seen[z * gw + x] == 0:
				components += 1
				var stack: Array = [Vector2i(x, z)]
				seen[z * gw + x] = 1
				while not stack.is_empty():
					var c: Vector2i = stack.pop_back()
					for dir: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
						var nx: int = c.x + dir.x
						var nz: int = c.y + dir.y
						if nx >= 0 and nx < gw and nz >= 0 and nz < gh \
								and passable[nz * gw + nx] == 1 and seen[nz * gw + nx] == 0:
							seen[nz * gw + nx] = 1
							stack.append(Vector2i(nx, nz))

	var total: int = gw * gh
	return {
		"passable_pct": roundi(100.0 * pass_count / total),
		"flat_pct": roundi(100.0 * flat_count / total),
		"connected": components <= 1,
	}


func _ensure_output_dir() -> void:
	var abs_path: String = ProjectSettings.globalize_path(OUTPUT_DIR)
	var err: int = DirAccess.make_dir_recursive_absolute(abs_path)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("GalleryBuilder: could not create %s (error %d)" % [abs_path, err])


func _write_readme(entries: Array) -> void:
	var abs_path: String = ProjectSettings.globalize_path(OUTPUT_DIR + "/README.md")
	var f: FileAccess = FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		push_error("GalleryBuilder: could not write README.md")
		return

	f.store_string("# Graph Plateau Gallery\n\n")
	f.store_string("Generated by `tools/generate_graph_plateau_gallery.gd` (Ctrl+Shift+X).\n\n")
	f.store_string("Open `graph_plateau_gallery.tscn` to review all variations in 3D.\n")
	f.store_string("Each variation has a generator (`gp_*.tres`, editable params) and a baked\n")
	f.store_string("heightmap (`hm_*.tres`, drop onto `Map.height_map`).\n\n")
	f.store_string("Fixed: seed=%d, height_step=%.1f, ramp_run=%d, ramp_half_width=%.1f.\n\n" % [
		FIXED_SEED, HEIGHT_STEP, RAMP_RUN, RAMP_HALF_WIDTH
	])
	f.store_string("| Variation | region_count | height_levels | passable | flat/buildable | connected |\n")
	f.store_string("|-----------|-------------|--------------|----------|----------------|-----------|\n")
	for e: Dictionary in entries:
		f.store_string("| hm_%s | %d | %d | %d%% | %d%% | %s |\n" % [
			e["tag"], e["region_count"], e["height_levels"],
			e["passable_pct"], e["flat_pct"], "yes" if e["connected"] else "**NO**"
		])
	f.close()
