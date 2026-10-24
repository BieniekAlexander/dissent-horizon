extends SceneTree

## Times what a terrain Paint stroke costs per mouse motion as the map grows — the current
## per-cell tile-type path and a prototype of the proposed splat weight layer
## (gdd/systems/terrain-and-navigation/terrain-paint.md). A benchmark, not a test: nothing is
## asserted, the numbers are printed for a human to read.
##
## Usage (needs a real renderer for the texture-upload numbers to mean anything):
##   godot --path . --rendering-driver opengl3 -s tools/terrain_paint_bench/terrain_paint_bench.gd \
##       -- [--sizes=79,120,200] [--reps=7] [--texels=4]
##
## Every map is a synthetic TerrainData built here (noise heights, all-default materials), so
## the bench never depends on authored content.

const CATALOG_PATH: String = "res://resources/terrain/tile_catalog.tres"
const MATERIAL_PATH: String = "res://scripts/rendering/shaders/terrain_surface.gdshader"
## Brush radii, in cells, for the splat prototype: a small touch-up and a broad fill.
const BRUSH_RADII: Array[int] = [4, 16]

var _sizes: Array[int] = [79, 120, 200]
var _reps: int = 7
var _texels: int = 4


func _initialize() -> void:
	_parse_args()
	print(
		(
			"terrain_paint_bench: renderer=%s sizes=%s reps=%d texels/cell=%d"
			% [RenderingServer.get_current_rendering_driver_name(), str(_sizes), _reps, _texels]
		)
	)
	# Give the renderer a frame to come up before anything is uploaded.
	await process_frame
	for size: int in _sizes:
		_bench_size(size)
	quit()


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--sizes="):
			_sizes.clear()
			for s: String in arg.trim_prefix("--sizes=").split(","):
				_sizes.append(int(s))
		elif arg.begins_with("--reps="):
			_reps = int(arg.trim_prefix("--reps="))
		elif arg.begins_with("--texels="):
			_texels = int(arg.trim_prefix("--texels="))


func _bench_size(size: int) -> void:
	var td: TerrainData = _make_terrain(size)
	var gw: int = td.grid_width()
	var gd: int = td.grid_depth()
	print(
		"\n== play_size %d (grid %d x %d cells, %d corners) ==" % [size, gw, gd, td.heights.size()]
	)

	# --- Current path: Paint stamps tile_types, then Map.rebuild_terrain_mesh() rebuilds the
	# whole HeightmapMeshGenerator mesh and re-pushes every terrain uniform. ---
	var gen := HeightmapMeshGenerator.new()
	gen.terrain_data_override = td
	var sm := ShaderMaterial.new()
	sm.shader = load(MATERIAL_PATH)
	gen.material = sm
	root.add_child(gen)
	gen.shape = td.to_height_shape()
	var center := Vector2i(gw / 2, gd / 2)
	var stroke := _median_ms(
		func() -> void:
			_stamp_tiles(td, center, 1, 4)
			gen.build()
	)
	print("  current stroke step (stamp + full mesh rebuild): %7.2f ms" % stroke)
	print(
		(
			"    of which cell_data_texture():                  %7.2f ms"
			% _median_ms(func() -> void: td.cell_data_texture())
		)
	)
	print(
		(
			"    of which height_texture() (mipmapped):         %7.2f ms"
			% _median_ms(func() -> void: TerrainShading.height_texture(td))
		)
	)
	gen.queue_free()

	# --- Proposed: a per-texel weight image, painted in place and re-uploaded. ---
	var tw: int = gw * _texels
	var th: int = gd * _texels
	var bytes := PackedByteArray()
	bytes.resize(tw * th * 4)
	for i: int in range(0, bytes.size(), 4):
		bytes[i] = 255  # layer 0 (R) owns everything to start
	var image := Image.create_from_data(tw, th, false, Image.FORMAT_RGBA8, bytes)
	var tex := ImageTexture.create_from_image(image)
	print(
		(
			"  weight image: %d x %d texels, %.1f MB per RGBA8 image (4 layers)"
			% [tw, th, bytes.size() / 1048576.0]
		)
	)
	for r: int in BRUSH_RADII:
		var stamp := _median_ms(func() -> void: _stamp_weights(bytes, tw, th, center, r, 2))
		var upload := _median_ms(
			func() -> void:
				image.set_data(tw, th, false, Image.FORMAT_RGBA8, bytes)
				tex.update(image)
		)
		print(
			(
				"  splat stroke step, radius %2d cells: stamp %7.2f ms + upload %7.2f ms"
				% [r, stamp, upload]
			)
		)
	print(
		(
			"  stroke-start undo snapshot (duplicate):          %7.2f ms"
			% _median_ms(func() -> void: bytes.duplicate())
		)
	)
	var png_path: String = OS.get_user_data_dir().path_join("paint_bench_%d.png" % size)
	var save := _median_ms(func() -> void: image.save_png(png_path), 3)
	print(
		(
			"  save as PNG: %7.2f ms, %.0f KB on disk (one uniform layer; a painted map is larger)"
			% [save, FileAccess.get_file_as_bytes(png_path).size() / 1024.0]
		)
	)
	DirAccess.remove_absolute(png_path)


## A noise height field on a `size` x `size` play area, every cell the default material.
func _make_terrain(size: int) -> TerrainData:
	var td := TerrainData.new()
	td.play_size = Vector2i(size, size)
	td.catalog = load(CATALOG_PATH)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.03
	var w: int = td.map_width()
	var d: int = td.map_depth()
	var heights := PackedFloat32Array()
	heights.resize(w * d)
	for z: int in d:
		for x: int in w:
			heights[z * w + x] = 8.0 + 4.0 * noise.get_noise_2d(x, z)
	td.heights = heights
	var types := PackedByteArray()
	types.resize(td.grid_width() * td.grid_depth())
	td.tile_types = types
	return td


## What the brush's Paint mode does to tile_types: a disc of `type` at `center`.
func _stamp_tiles(td: TerrainData, center: Vector2i, type: int, r: int) -> void:
	var gw: int = td.grid_width()
	var gd: int = td.grid_depth()
	var types: PackedByteArray = td.tile_types
	for z: int in range(maxi(0, center.y - r), mini(gd, center.y + r + 1)):
		for x: int in range(maxi(0, center.x - r), mini(gw, center.x + r + 1)):
			if Vector2i(x, z).distance_squared_to(center) <= r * r:
				types[z * gw + x] = type
	td.tile_types = types


## A soft disc pushing `channel` toward full weight and renormalising the other three, the
## way a splat brush would. Pure GDScript, so it is the pessimistic case for the stamp.
func _stamp_weights(
	bytes: PackedByteArray, tw: int, th: int, center_cell: Vector2i, r_cells: int, channel: int
) -> void:
	var cx: float = (center_cell.x + 0.5) * _texels
	var cz: float = (center_cell.y + 0.5) * _texels
	var r: float = r_cells * _texels
	for z: int in range(maxi(0, int(cz - r)), mini(th, int(cz + r) + 1)):
		for x: int in range(maxi(0, int(cx - r)), mini(tw, int(cx + r) + 1)):
			var d: float = Vector2(x - cx, z - cz).length() / r
			if d >= 1.0:
				continue
			var strength: float = (1.0 - d * d) * 0.35
			var i: int = (z * tw + x) * 4
			var total: float = 0.0
			for c: int in 4:
				var w: float = bytes[i + c] / 255.0
				w = lerpf(w, 1.0 if c == channel else 0.0, strength)
				bytes[i + c] = int(w * 255.0)
				total += w
			if total <= 0.0:
				bytes[i + channel] = 255


func _median_ms(fn: Callable, reps: int = -1) -> float:
	var n: int = reps if reps > 0 else _reps
	var samples: Array[float] = []
	for i: int in n:
		var t0: int = Time.get_ticks_usec()
		fn.call()
		samples.append((Time.get_ticks_usec() - t0) / 1000.0)
	samples.sort()
	return samples[n / 2]
