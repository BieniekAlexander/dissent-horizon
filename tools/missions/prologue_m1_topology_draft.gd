extends SceneTree

## A DRAFT of prologue mission 1's reworked topology, read from Alex's level sketch
## (`SKETCH`, 2026-10-21; gdd/tasks.md T-126). The sketch is the source: this classifies its
## pixels into elevation levels, water and cliffs and builds terrain from them. It writes NEW
## files only — the draft terrain, its surface mesh and a map-only preview scene — and never
## touches the mission's own terrain or scene, which are hand-made and primary. It refuses to
## overwrite its own outputs too, so a draft someone has since edited by hand is never lost;
## pass `-- --overwrite` to rebuild it deliberately.
##
##   godot --headless --path . -s res://tools/missions/prologue_m1_topology_draft.gd
##
## Reading the sketch:
## - The five elevation swatches and two water swatches of its legend are the palette
##   (`LEVEL_COLORS`, `DEEP_COLOR`). Light water is painted translucently, so it is recognised by
##   its blue rather than its exact colour, and its red tells which ground it lies on.
## - Every body of water lies in level 1. Light water painted over level 3 marks a waterfall
##   down a level change, which map processing cannot express yet (a body has one surface
##   level), so it is built as dry level 3 for now. TODO — waterfalls, when water can fall
##   between levels (Alex, 2026-10-21: skip them until then).
## - TODO — the sketch has no lithium ponds yet; Alex wants some later, not important to this
##   mission.
## - Long black strokes are cliffs: corners near one keep a steep step even between adjacent
##   levels. Short ones — lettering, a dashed box — are marks (`MIN_CLIFF_STROKE_PX`).
## - Everything else — Alex's piece marks, letters, boxes and arrows — is ignored: each corner
##   takes the majority terrain class around it, so a mark is filled in from what it sits on.
##
## Levels become heights LEVEL_STEP apart, then the field is box-blurred twice: a one-level
## step grades to a walkable ramp, a two-level step stays steeper than
## TerrainGrid.MAX_SLOPE_DIFF.

const SKETCH: String = "res://gdd/campaigns/01-prologue/m1_topology_sketch.png"
const OUT_TRES: String = "res://resources/terrain/prologue_m1_draft_terrain.tres"
const OUT_MESH: String = "res://resources/terrain/prologue_m1_draft_terrain_surface.res"
const OUT_SCENE: String = "res://scenes/scenarios/prologue/m1_topology_draft_map.tscn"
const TILE_CATALOG: String = "res://resources/terrain/tile_catalog.tres"
const SURFACE_SHADER: String = "res://scripts/rendering/shaders/terrain_surface.gdshader"

## The sketch's map rectangle, in its pixels (the legend sits to its right).
const SKETCH_RECT := Rect2(3, 15, 1335, 1010)
## World units per sketch pixel. Alex, 2026-10-21: features about 50% bigger than the first
## draft's (0.257, a map 343 units across); then cut by about a third the next day, once pieces
## on it showed how sparse that was.
const SCALE: float = 0.172

## Height between adjacent levels. With the blur below, one level grades at about 0.36 per
## cell along an axis (0.51 diagonally) and two levels at about 0.72: under and over
## TerrainGrid.MAX_SLOPE_DIFF (tan 30 deg, 0.577) respectively.
const LEVEL_STEP: float = 1.8
## Box-blur radius in corners, applied twice; one pass of CLIFF_BLUR_RADIUS near a cliff.
const BLUR_RADIUS: int = 2
const CLIFF_BLUR_RADIUS: int = 1
## How near a black pixel a corner counts as on a cliff, in sketch pixels.
const CLIFF_REACH_PX: int = 4
## A black stroke spanning less than this, in sketch pixels, is lettering or a dash, not a cliff.
const MIN_CLIFF_STROKE_PX: int = 60
## How far round a corner its terrain class is voted on, in sketch pixels, and how far the
## search widens when a mark covers all of that.
const VOTE_RADIUS_PX: int = 5
const VOTE_RADIUS_MAX_PX: int = 24

## Water beds, relative to the ground they lie in, and the one water level above that ground.
## Deep is more than WaterBasin.WADE_DEPTH under the level, shallow less.
const DEEP_BED: float = -2.4
const SHALLOW_BED: float = -0.75
const WATER_LEVEL: float = -0.3
## A water patch smaller than this, in corners, is a stray brush mark and stays dry.
const MIN_WATER_CORNERS: int = 20

## Terrain classes. Levels are 1–5.
const DEEP: int = 6
const SHALLOW_LOW: int = 7  # over level 1
const SHALLOW_HIGH: int = 8  # over level 3
const CLIFF: int = 254
const MARK: int = 255

## The legend's swatches, lowest level first.
const LEVEL_COLORS: Array[Color] = [
	Color8(175, 206, 140),
	Color8(200, 206, 140),
	Color8(206, 187, 140),
	Color8(206, 164, 140),
	Color8(206, 151, 140),
]
const DEEP_COLOR := Color8(124, 139, 200)
## How near a swatch a pixel must be to count as that level; antialiased mark edges fall
## outside it and are ignored.
const SWATCH_TOLERANCE: float = 0.05

## Where Alex's sketch marks things, in its pixels: drawn into readouts and probes. Placement
## only — no piece is put in any scene.
const MARKERS: Array = [
	["S", "start", 40, 995],
	["1", "rendezvous with the allies", 285, 905],
	["2", "first Compounds to destroy", 40, 750],
	["3", "garrison building", 135, 785],
	["W", "tower-guarded base entrance (warning)", 405, 662],
	["5", "SAM sites, then the transport", 920, 175],
	["6", "sneak-in landing", 690, 985],
	["7", "Compounds round the base", 1165, 880],
	["8", "Citadel", 1220, 680],
	["A", "allied base", 178, 110],
	["E", "enemy base (north-east)", 1255, 190],
	["B", "enemy base (south)", 875, 898],
]

var _overwrite: bool = false
var _classes := PackedByteArray()
var _sketch_size := Vector2i.ZERO


func _initialize() -> void:
	_overwrite = "--overwrite" in OS.get_cmdline_user_args()
	for path: String in [OUT_TRES, OUT_MESH, OUT_SCENE]:
		if FileAccess.file_exists(path) and not _overwrite:
			push_error("topology draft: %s exists; pass -- --overwrite to rebuild it" % path)
			quit(1)
			return
	if not _read_sketch():
		quit(1)
		return
	var data := TerrainData.new()
	data.play_size = _play_size()
	data.catalog = load(TILE_CATALOG) as TerrainTileCatalog
	var dims: Vector2i = data.dimensions
	var corner_class := PackedByteArray()
	var on_cliff := PackedByteArray()
	_classify_corners(dims, corner_class, on_cliff)
	var waters: Array[Dictionary] = _water_bodies(dims, corner_class)
	var targets: PackedFloat32Array = _targets(corner_class)
	var heights: PackedFloat32Array = _blur(_blur(targets, dims), dims)
	var sharp: PackedFloat32Array = _blur(targets, dims, CLIFF_BLUR_RADIUS)
	for k: int in heights.size():
		if on_cliff[k] == 1:
			heights[k] = sharp[k]
	data.heights = heights
	print(
		(
			"draft: play_size %s, corner grid %s, %d water bodies"
			% [data.play_size, dims, waters.size()]
		)
	)

	var mesh := ArrayMesh.new()
	TerrainMeshGrid.write_heights(mesh, dims, heights)
	if ResourceSaver.save(mesh, OUT_MESH) != OK or ResourceSaver.save(data, OUT_TRES) != OK:
		push_error("topology draft: could not save the terrain")
		quit(1)
		return
	data.heights = heights
	_write_scene(waters, heights, dims, data)
	print("wrote %s, %s and %s" % [OUT_TRES, OUT_MESH, OUT_SCENE])
	quit(0 if _verify_rebake_is_noop(heights) else 1)


#region Reading the sketch
## Classify every sketch pixel once.
func _read_sketch() -> bool:
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(SKETCH))
	if image == null:
		push_error("topology draft: cannot read %s" % SKETCH)
		return false
	image.convert(Image.FORMAT_RGB8)
	_sketch_size = image.get_size()
	_classes.resize(_sketch_size.x * _sketch_size.y)
	for y: int in _sketch_size.y:
		for x: int in _sketch_size.x:
			_classes[y * _sketch_size.x + x] = classify(image.get_pixel(x, y))
	_demote_short_strokes()
	return true


## Turn every black stroke whose bounding box spans less than MIN_CLIFF_STROKE_PX into a mark.
func _demote_short_strokes() -> void:
	var w: int = _sketch_size.x
	var seen := PackedByteArray()
	seen.resize(_classes.size())
	for start: int in _classes.size():
		if seen[start] == 1 or _classes[start] != CLIFF:
			continue
		var members: Array[int] = []
		var frontier: Array[int] = [start]
		seen[start] = 1
		var lo := Vector2i(start % w, start / w)
		var hi := lo
		while not frontier.is_empty():
			var k: int = frontier.pop_back()
			members.append(k)
			var x: int = k % w
			var y: int = k / w
			lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
			hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					var nx: int = x + dx
					var ny: int = y + dy
					if nx < 0 or ny < 0 or nx >= w or ny >= _sketch_size.y:
						continue
					var nk: int = ny * w + nx
					if seen[nk] == 0 and _classes[nk] == CLIFF:
						seen[nk] = 1
						frontier.append(nk)
		if maxi(hi.x - lo.x, hi.y - lo.y) < MIN_CLIFF_STROKE_PX:
			for k: int in members:
				_classes[k] = MARK


## A pixel's terrain class, or CLIFF, or MARK for anything that is not terrain.
static func classify(a_color: Color) -> int:
	if maxf(a_color.r, maxf(a_color.g, a_color.b)) < 0.3:
		return CLIFF
	if minf(a_color.r, minf(a_color.g, a_color.b)) > 0.75:
		return MARK
	if _distance(a_color, DEEP_COLOR) < 0.12:
		return DEEP
	if a_color.b > 0.65 and a_color.g > 0.7:
		return SHALLOW_HIGH if a_color.r > 0.7 else SHALLOW_LOW
	var best: int = MARK
	var best_distance: float = SWATCH_TOLERANCE
	for k: int in LEVEL_COLORS.size():
		var d: float = _distance(a_color, LEVEL_COLORS[k])
		if d < best_distance:
			best_distance = d
			best = k + 1
	return best


static func _distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func _class_at(a_x: int, a_y: int) -> int:
	return _classes[
		clampi(a_y, 0, _sketch_size.y - 1) * _sketch_size.x + clampi(a_x, 0, _sketch_size.x - 1)
	]


## Each corner's terrain class (the majority round it) and whether it lies on a cliff line.
func _classify_corners(
	a_dims: Vector2i, a_class: PackedByteArray, a_cliff: PackedByteArray
) -> void:
	a_class.resize(a_dims.x * a_dims.y)
	a_cliff.resize(a_dims.x * a_dims.y)
	var half: Vector2 = Vector2(a_dims - Vector2i.ONE) * 0.5
	for j: int in a_dims.y:
		for i: int in a_dims.x:
			var px: Vector2 = lane_to_sketch(world_to_lane(Vector2(i - half.x, j - half.y)))
			var k: int = j * a_dims.x + i
			a_class[k] = _vote(roundi(px.x), roundi(px.y))
			a_cliff[k] = 1 if _near_cliff(roundi(px.x), roundi(px.y)) else 0


func _vote(a_x: int, a_y: int) -> int:
	var radius: int = VOTE_RADIUS_PX
	while radius <= VOTE_RADIUS_MAX_PX:
		var tally: Dictionary = {}
		for dy: int in range(-radius, radius + 1, 2):
			for dx: int in range(-radius, radius + 1, 2):
				var c: int = _class_at(a_x + dx, a_y + dy)
				if c != MARK and c != CLIFF:
					tally[c] = int(tally.get(c, 0)) + 1
		if not tally.is_empty():
			var best: int = 1
			var most: int = -1
			for c: int in tally:
				if int(tally[c]) > most:
					most = tally[c]
					best = c
			return best
		radius *= 2
	return 1


func _near_cliff(a_x: int, a_y: int) -> bool:
	for dy: int in range(-CLIFF_REACH_PX, CLIFF_REACH_PX + 1):
		for dx: int in range(-CLIFF_REACH_PX, CLIFF_REACH_PX + 1):
			if _class_at(a_x + dx, a_y + dy) == CLIFF:
				return true
	return false


#endregion


#region The map's frame
## The play rectangle, in diamonds (TerrainData.play_size: x its on-screen height, y its width).
static func _play_size() -> Vector2i:
	var extent: Vector2 = _lane_extent()
	return Vector2i(roundi(extent.y / sqrt(2.0)), roundi(extent.x / sqrt(2.0)))


## The map's (along, across) extent in world units.
static func _lane_extent() -> Vector2:
	return SKETCH_RECT.size * SCALE


## A sketch pixel's (along, across): along east from the west edge, across north from the south.
static func sketch_to_lane(a_px: Vector2) -> Vector2:
	return Vector2(a_px.x - SKETCH_RECT.position.x, SKETCH_RECT.end.y - a_px.y) * SCALE


static func lane_to_sketch(a_lane: Vector2) -> Vector2:
	return Vector2(SKETCH_RECT.position.x + a_lane.x / SCALE, SKETCH_RECT.end.y - a_lane.y / SCALE)


## The Map-local world XZ of a lane position: the lane frame turned 45 degrees onto the grid,
## centred on the play rectangle, as MissionLane does for the shipped map.
static func lane_to_world(a_lane: Vector2) -> Vector2:
	var centre: Vector2 = _lane_extent() * 0.5
	var t: float = (a_lane.x - centre.x) * sqrt(2.0)
	var s: float = -(a_lane.y - centre.y) * sqrt(2.0)
	return Vector2((s + t) * 0.5, (s - t) * 0.5)


static func world_to_lane(a_world: Vector2) -> Vector2:
	var centre: Vector2 = _lane_extent() * 0.5
	return (
		Vector2((a_world.x - a_world.y) / sqrt(2.0), -(a_world.x + a_world.y) / sqrt(2.0)) + centre
	)


#endregion


#region Heights and water
static func level_height(a_level: int) -> float:
	return (a_level - 1) * LEVEL_STEP


static func _is_water(a_class: int) -> bool:
	return a_class == DEEP or a_class == SHALLOW_LOW


func _targets(a_class: PackedByteArray) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(a_class.size())
	for k: int in a_class.size():
		var c: int = a_class[k]
		if c == DEEP:
			out[k] = level_height(1) + DEEP_BED
		elif c == SHALLOW_LOW:
			out[k] = level_height(1) + SHALLOW_BED
		elif c == SHALLOW_HIGH:
			out[k] = level_height(3)
		else:
			out[k] = level_height(c)
	return out


## Group water corners into bodies: 4-connected patches. A patch too small to be meant is dried
## out, in place, back to level 1.
func _water_bodies(a_dims: Vector2i, a_class: PackedByteArray) -> Array[Dictionary]:
	var bodies: Array[Dictionary] = []
	var seen := PackedByteArray()
	seen.resize(a_class.size())
	for start: int in a_class.size():
		if seen[start] == 1 or not _is_water(a_class[start]):
			continue
		var members: Array[int] = []
		var frontier: Array[int] = [start]
		seen[start] = 1
		while not frontier.is_empty():
			var k: int = frontier.pop_back()
			members.append(k)
			var i: int = k % a_dims.x
			var j: int = k / a_dims.x
			for step: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
				var ni: int = i + step.x
				var nj: int = j + step.y
				if ni < 0 or nj < 0 or ni >= a_dims.x or nj >= a_dims.y:
					continue
				var nk: int = nj * a_dims.x + ni
				if seen[nk] == 0 and _is_water(a_class[nk]):
					seen[nk] = 1
					frontier.append(nk)
		if members.size() < MIN_WATER_CORNERS:
			for k: int in members:
				a_class[k] = 1
			continue
		bodies.append({"members": members})
	return bodies


#endregion


#region Blur
## One separable box blur of radius `a_radius`, clamped at the grid's edges.
func _blur(
	a_in: PackedFloat32Array, a_dims: Vector2i, a_radius: int = BLUR_RADIUS
) -> PackedFloat32Array:
	var tmp := PackedFloat32Array()
	tmp.resize(a_in.size())
	var out := PackedFloat32Array()
	out.resize(a_in.size())
	var width: float = 2.0 * a_radius + 1.0
	for j: int in a_dims.y:
		for i: int in a_dims.x:
			var sum: float = 0.0
			for d: int in range(-a_radius, a_radius + 1):
				sum += a_in[j * a_dims.x + clampi(i + d, 0, a_dims.x - 1)]
			tmp[j * a_dims.x + i] = sum / width
	for j: int in a_dims.y:
		for i: int in a_dims.x:
			var sum: float = 0.0
			for d: int in range(-a_radius, a_radius + 1):
				sum += tmp[clampi(j + d, 0, a_dims.y - 1) * a_dims.x + i]
			out[j * a_dims.x + i] = sum / width
	return out


#endregion


#region Output
## A map-only scene: the draft terrain and its water bodies, for previewing and for probes.
## Each body is seeded at the cell over its lowest corner, so the seed is under water; one the
## game's own fill finds holding no water (a stray brush patch on a slope) is left out.
func _write_scene(
	a_waters: Array[Dictionary],
	a_heights: PackedFloat32Array,
	a_dims: Vector2i,
	a_data: TerrainData
) -> void:
	var text: String = (
		"[gd_scene format=3]\n\n"
		+ '[ext_resource type="Script" path="res://scripts/maps/map.gd" id="1_map"]\n'
		+ '[ext_resource type="Resource" path="%s" id="2_data"]\n' % OUT_TRES
		+ '[ext_resource type="ArrayMesh" path="%s" id="3_mesh"]\n' % OUT_MESH
		+ '[ext_resource type="Script" path="res://scripts/maps/terrain/terrain_surface.gd"'
		+ ' id="4_surface"]\n'
		+ '[ext_resource type="Shader" path="%s" id="5_shader"]\n' % SURFACE_SHADER
		+ '[ext_resource type="Script" path="res://scripts/maps/terrain/water_body.gd"'
		+ ' id="6_water"]\n\n'
		+ '[sub_resource type="NavigationMesh" id="NavigationMesh_1"]\n\n'
		+ '[sub_resource type="ShaderMaterial" id="ShaderMaterial_1"]\n'
		+ 'render_priority = 0\nshader = ExtResource("5_shader")\n\n'
		+ '[node name="Map" type="Node3D"]\nscript = ExtResource("1_map")\n'
		+ 'terrain_data = ExtResource("2_data")\nterrain_source_mesh = ExtResource("3_mesh")\n\n'
		+ '[node name="NavigationRegion" type="NavigationRegion3D" parent="."'
		+ ' groups=["navigation_mesh_source_group"]]\n'
		+ 'navigation_mesh = SubResource("NavigationMesh_1")\n\n'
		+ '[node name="Body" type="StaticBody3D" parent="NavigationRegion"]\n'
		+ "collision_layer = 128\ncollision_mask = 0\n\n"
		+ '[node name="Shape" type="CollisionShape3D" parent="NavigationRegion/Body"]\n\n'
		+ '[node name="TerrainSurface" type="MeshInstance3D" parent="NavigationRegion/Body"]\n'
		+ 'script = ExtResource("4_surface")\nmaterial = SubResource("ShaderMaterial_1")\n'
	)
	var written: int = 0
	for n: int in a_waters.size():
		var corner: int = a_waters[n].members[0]
		for k: int in a_waters[n].members:
			if a_heights[k] < a_heights[corner]:
				corner = k
		var seed := Vector2i(
			clampi(corner % a_dims.x, 0, a_dims.x - 2), clampi(corner / a_dims.x, 0, a_dims.y - 2)
		)
		var level: float = level_height(1) + WATER_LEVEL
		if not WaterBasin.fill(a_data, seed, level).is_valid():
			continue
		written += 1
		text += (
			(
				'\n[node name="Water%d" type="Node3D" parent="."]\nscript = ExtResource("6_water")\n'
				% written
			)
			+ "level = %s\nseed_cell = Vector2i(%d, %d)\n" % [level, seed.x, seed.y]
		)
	print("water bodies written: %d of %d" % [written, a_waters.size()])
	var file := FileAccess.open(OUT_SCENE, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## Re-read both artifacts, bake the mesh as Map.bake_terrain_from_mesh would, and require the
## heights back unchanged (CLAUDE.md §Regenerating data).
func _verify_rebake_is_noop(a_expected: PackedFloat32Array) -> bool:
	var data: TerrainData = ResourceLoader.load(OUT_TRES, "", ResourceLoader.CACHE_MODE_IGNORE)
	var mesh: Mesh = ResourceLoader.load(OUT_MESH, "", ResourceLoader.CACHE_MODE_IGNORE)
	if data == null or mesh == null:
		push_error("topology draft: re-load failed")
		return false
	data.bake_source_mesh(mesh)
	var worst: float = 0.0
	for k: int in a_expected.size():
		worst = maxf(worst, absf(data.heights[k] - a_expected[k]))
	print("residual rebaked-vs-computed %.9f   <- must be 0" % worst)
	return worst == 0.0
#endregion
