extends Node3D

## Measures NAVMESH PATH BENDING across a scenario, with no simulation at all: it queries
## NavigationServer3D directly, so it isolates A*/funnel behaviour from RVO, unit speed and
## terrain following entirely.
##
## Reproduces the methodology recorded in CLAUDE.md ("over every 5-tile diagonal move whose
## straight line is fully walkable"): sample many start points, fire a fixed-length move at a
## range of headings, keep only those whose straight line is entirely over passable ground,
## and report how far the returned polyline exceeds that straight line.
##
##   godot --headless res://tools/terrain_meshes/probe_path_bend.tscn -- <scene> [length]

const SAMPLES_PER_AXIS: int = 9
const HEADINGS: int = 16
## A path longer than its straight line by more than this counts as BENT.
const BENT_THRESHOLD: float = 1.005

var _scene: String
var _length: float = 5.0
var _dump_heading: float = -1.0


func _ready() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	_scene = a[0]
	if a.size() >= 2:
		_length = float(a[1])
	if a.size() >= 3:
		_dump_heading = float(a[2])
	_run.call_deferred()


func _run() -> void:
	add_child((load(_scene) as PackedScene).instantiate())
	for _i: int in 120:
		await get_tree().physics_frame
	var map: Map = get_node("Scenario/Map") if has_node("Scenario/Map") else _find_map(self)
	var nav_map: RID = map.nav_region.get_navigation_map()
	var grid: TerrainGrid = map.terrain_grid

	# Dump mode: print one path's waypoints as perpendicular offsets from the straight line,
	# which is what distinguishes "the navmesh returned a zigzag" from "the follower zigzags
	# along a straight polyline".
	if _dump_heading >= 0.0:
		var d := Vector2(cos(deg_to_rad(_dump_heading)), sin(deg_to_rad(_dump_heading)))
		var f := Vector2(0.0, 0.0)
		var t: Vector2 = f + d * _length
		var pts: PackedVector3Array = NavigationServer3D.map_get_path(
			nav_map, _v3(map, f), _v3(map, t), true)
		print("=== path for heading %.0f deg, length %.1f: %d waypoints ===" % [
			_dump_heading, _length, pts.size()])
		print("  %5s | %8s | %8s | %s" % ["i", "along", "offset", "step heading err"])
		var axis: Vector2 = d
		var perp := Vector2(-d.y, d.x)
		for i: int in pts.size():
			var q := Vector2(pts[i].x, pts[i].z) - f
			var err: String = ""
			if i > 0:
				var seg: Vector2 = Vector2(pts[i].x, pts[i].z) - Vector2(pts[i-1].x, pts[i-1].z)
				if seg.length() > 0.0001:
					err = "%7.2f deg" % rad_to_deg(absf(seg.angle_to(d)))
			print("  %5d | %8.3f | %8.3f | %s" % [i, q.dot(axis), q.dot(perp), err])
		get_tree().quit(0)
		return

	var by_heading: Dictionary = {}
	var excesses: PackedFloat32Array = PackedFloat32Array()
	var bent: int = 0
	var total: int = 0
	var worst: float = 1.0
	var worst_desc: String = ""

	var half: float = 45.0
	for iz: int in SAMPLES_PER_AXIS:
		for ix: int in SAMPLES_PER_AXIS:
			var sx: float = -half + 2.0 * half * float(ix) / float(SAMPLES_PER_AXIS - 1)
			var sz: float = -half + 2.0 * half * float(iz) / float(SAMPLES_PER_AXIS - 1)
			for h: int in HEADINGS:
				var angle: float = TAU * float(h) / float(HEADINGS)
				var from := Vector2(sx, sz)
				var to: Vector2 = from + Vector2(cos(angle), sin(angle)) * _length
				if not _line_is_walkable(map, grid, from, to):
					continue
				var path: PackedVector3Array = NavigationServer3D.map_get_path(
					nav_map, _v3(map, from), _v3(map, to), true)
				if path.size() < 2:
					continue
				var straight: float = from.distance_to(to)
				var length: float = 0.0
				for i: int in range(1, path.size()):
					length += Vector2(path[i].x, path[i].z).distance_to(
						Vector2(path[i - 1].x, path[i - 1].z))
				# The endpoints resolve onto the mesh, so compare against the RESOLVED span.
				var resolved: float = Vector2(path[0].x, path[0].z).distance_to(
					Vector2(path[path.size() - 1].x, path[path.size() - 1].z))
				if resolved < 0.001:
					continue
				var excess: float = length / resolved
				total += 1
				excesses.append(excess)
				if excess > BENT_THRESHOLD:
					bent += 1
				var deg: int = int(round(rad_to_deg(angle)))
				if not by_heading.has(deg):
					by_heading[deg] = [0, 0, 0.0]
				by_heading[deg][0] += 1
				if excess > BENT_THRESHOLD:
					by_heading[deg][1] += 1
				by_heading[deg][2] += excess
				if excess > worst:
					worst = excess
					worst_desc = "(%.0f, %.0f) heading %d deg" % [sx, sz, deg]

	var mean: float = 0.0
	for e: float in excesses:
		mean += e
	mean = mean / maxf(float(total), 1.0)

	print("=== %s | move length %.1f ===" % [_scene, _length])
	print("samples %d | bent %d (%.1f%%) | mean excess %.2f%% | worst %.1f%% at %s" % [
		total, bent, 100.0 * bent / maxf(float(total), 1.0),
		100.0 * (mean - 1.0), 100.0 * (worst - 1.0), worst_desc])
	print("per heading:")
	var headings: Array = by_heading.keys()
	headings.sort()
	for deg: int in headings:
		var row: Array = by_heading[deg]
		print("  %4d deg | n=%4d | bent %5.1f%% | mean excess %5.2f%%" % [
			deg, row[0], 100.0 * row[1] / maxf(float(row[0]), 1.0),
			100.0 * (row[2] / maxf(float(row[0]), 1.0) - 1.0)])
	get_tree().quit(0)


## True when every cell the straight line crosses is passable — so a bent result is the
## navmesh's doing and not an obstacle legitimately in the way.
func _line_is_walkable(a_map: Map, a_grid: TerrainGrid, a_from: Vector2, a_to: Vector2) -> bool:
	var steps: int = int(ceil(a_from.distance_to(a_to) * 4.0))
	for i: int in steps + 1:
		var p: Vector2 = a_from.lerp(a_to, float(i) / float(steps))
		if not a_grid.is_passable(a_map.world_to_grid(p)):
			return false
	return true


func _v3(a_map: Map, a_p: Vector2) -> Vector3:
	return Vector3(a_p.x, a_map.terrain_height_at(a_p), a_p.y)


func _find_map(a_node: Node) -> Map:
	if a_node is Map:
		return a_node as Map
	for c: Node in a_node.get_children():
		var m: Map = _find_map(c)
		if m != null:
			return m
	return null
