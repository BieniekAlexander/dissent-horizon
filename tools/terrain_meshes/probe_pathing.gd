extends Node3D

## Attributes non-linear movement to its actual cause, by measuring the two independently:
##
##   PATH BENDING  — A* returned a bent polyline. Shows up as path_excess > 1: the navigation
##                   path itself is longer than the straight line. This is the navmesh /
##                   corridor problem (see NavManager's "DO NOT merge cells" note).
##   BODY VEER     — the path is straight but the body bows off it. Shows up as a large
##                   max_offset. This is RVO avoidance (see Movement.update_avoidance_priority).
##
## Two runs per invocation: one with the unit ISOLATED (teleported far from every neighbour,
## so RVO has nobody to avoid) and one left in its starting cluster. If the isolated run is
## already bent, the cause is not avoidance.
##
##   godot --headless res://tools/terrain_meshes/probe_pathing.tscn -- <scene> ax az bx bz

const TICKS: int = 3000
const ARRIVE: float = 2.0

var _scene: String
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _map: Map
var _scenario: Node


func _ready() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	_scene = a[0]
	_from = Vector3(float(a[1]), 0.0, float(a[2]))
	_to = Vector3(float(a[3]), 0.0, float(a[4]))
	_run.call_deferred()


func _run() -> void:
	_scenario = (load(_scene) as PackedScene).instantiate()
	add_child(_scenario)
	for _i: int in 120:
		await get_tree().physics_frame
	_map = _scenario.get_node("Map") as Map

	var units: Array = _player_units()
	if units.size() < 2:
		print("need at least 2 player units, found %d" % units.size())
		get_tree().quit(2)
		return

	print("=== %s : (%.0f, %.0f) -> (%.0f, %.0f) ===" % [
		_scene, _from.x, _from.z, _to.x, _to.z])

	# ISOLATED: park every other unit far away so RVO has nobody to react to.
	var subject: Commandable = units[0]
	var parked: Array = []
	for i: int in range(1, units.size()):
		parked.append(units[i])
		units[i].global_position = Vector3(_from.x + 300.0 + i * 4.0, 0.0, _from.z + 300.0)
	await _measure(subject, "isolated ")

	# CLUSTERED: bring them back next to the subject, standing still.
	for i: int in parked.size():
		var p: Commandable = parked[i]
		p.global_position = _snap(_from + Vector3(cos(i * 1.6) * 2.0, 0.0, sin(i * 1.6) * 2.0))
	await get_tree().physics_frame
	await _measure(subject, "clustered")

	get_tree().quit(0)


func _measure(a_unit: Commandable, a_label: String) -> void:
	a_unit.global_position = _snap(_from)
	a_unit.update_commands(null)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var goal: Vector3 = _snap(_to)
	a_unit.update_commands(MoveCommand.new(CommandMessage.new(_map, null, null, goal)))

	var path := PackedVector3Array()
	var trail := PackedVector3Array()
	var ticks: int = 0
	while ticks < TICKS:
		await get_tree().physics_frame
		ticks += 1
		if path.is_empty() and a_unit.movement != null:
			path = a_unit.movement.current_path()
		trail.append(a_unit.global_position)
		if _xz(a_unit.global_position).distance_to(_xz(goal)) <= ARRIVE:
			break

	var straight: float = _xz(_snap(_from)).distance_to(_xz(goal))
	var path_len: float = _polyline_length(path)
	var walked: float = _polyline_length(trail)
	var max_off: float = 0.0
	for p: Vector3 in trail:
		max_off = maxf(max_off, _distance_to_polyline(_xz(p), path))

	print("%s | straight %6.1f | A* path %6.1f (x%.3f, %d pts) | walked %6.1f (x%.3f) | max body offset from path %5.2f | %d ticks" % [
		a_label, straight,
		path_len, path_len / maxf(straight, 0.001), path.size(),
		walked, walked / maxf(straight, 0.001),
		max_off, ticks])


func _player_units() -> Array:
	var player: Node = _scenario.call("local_player")
	var out: Array = []
	if player == null:
		return out
	for c: Node in player.get_children():
		if c is Commandable and c.is_in_group("unit") and not c.is_queued_for_deletion():
			out.append(c)
	return out


func _snap(a_p: Vector3) -> Vector3:
	var s: Vector3 = _map.nearest_navmesh_point(Vector3(a_p.x, 0.0, a_p.z))
	s.y = _map.terrain_height_at(Vector2(s.x, s.z))
	return s


func _xz(a_v: Vector3) -> Vector2:
	return Vector2(a_v.x, a_v.z)


func _polyline_length(a_pts: PackedVector3Array) -> float:
	var total: float = 0.0
	for i: int in range(1, a_pts.size()):
		total += _xz(a_pts[i]).distance_to(_xz(a_pts[i - 1]))
	return total


## Perpendicular distance from a point to the polyline, in XZ.
func _distance_to_polyline(a_p: Vector2, a_pts: PackedVector3Array) -> float:
	if a_pts.size() < 2:
		return 0.0
	var best: float = INF
	for i: int in range(1, a_pts.size()):
		var a: Vector2 = _xz(a_pts[i - 1])
		var b: Vector2 = _xz(a_pts[i])
		var ab: Vector2 = b - a
		var t: float = 0.0 if ab.length_squared() == 0.0 \
			else clampf((a_p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, a_p.distance_to(a + ab * t))
	return best
