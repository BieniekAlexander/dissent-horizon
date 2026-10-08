extends Node3D

## Asks the sharpest possible question about unit movement: with ONE unit in genuinely empty
## space, ordered straight at a point, does it actually travel in that direction?
##
## Per physics tick it compares the unit's VELOCITY HEADING against the true bearing from its
## current position to its destination. In an unobstructed space those must agree — a unit
## ordered 45 degrees away should move at exactly 45 degrees, the whole way. Any standing error
## is steering; any oscillation is waypoint chasing.
##
## Deliberately measured instead of path length: a polyline can have the right TOTAL length
## while the unit zigzags along it, and a length ratio averages exactly that away.
##
## Runs against scenes/scenarios/test/nav_straight_line.tscn — an empty scenario with no other
## unit, no structure and no obstacle, so nothing else can be blamed.
##
## godot --headless res://tools/terrain_meshes/probe_velocity_angle.tscn -- [distance]
## [simplify_epsilon]
##
## simplify_epsilon > 0 turns on NavigationAgent3D.simplify_path at that epsilon, so the
## effect of Godot's built-in path simplification can be measured rather than assumed.

const DEFAULT_SCENE := "res://scenes/scenarios/test/nav_straight_line.tscn"
const DEFAULT_UNIT := "res://scenes/entities/units/cl/cl_bioLight_antiLight.tscn"
const HEADINGS: Array[float] = [0.0, 15.0, 30.0, 45.0, 60.0, 75.0, 90.0, 135.0, 200.0, 315.0]
const TICKS: int = 4000
const ARRIVE: float = 1.5
## Ignore the first ticks while the unit accelerates from rest — a velocity of almost zero has
## a meaningless heading.
const MIN_SPEED: float = 0.05

var _distance: float = 40.0
var _unit_path: String = DEFAULT_UNIT
var _simplify: float = 0.0
var _scenario: Node
var _map: Map
var _commander: Commander


func _ready() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() >= 1:
		_distance = float(a[0])
	if a.size() >= 2:
		_simplify = float(a[1])
	_run.call_deferred()


func _run() -> void:
	_scenario = (load(DEFAULT_SCENE) as PackedScene).instantiate()
	add_child(_scenario)
	for _i: int in 60:
		await get_tree().physics_frame
	_map = _scenario.get_node("Map") as Map
	while not _map.nav_manager.is_ready():
		await get_tree().physics_frame
	_commander = _scenario.call("local_player")

	print(
		(
			"=== velocity heading vs true bearing | %s | distance %.0f | simplify_epsilon %.2f ==="
			% [_unit_path.get_file(), _distance, _simplify]
		)
	)
	print(
		(
			"%8s | %8s | %8s | %8s | %8s | %s"
			% ["ordered", "mean err", "max err", "p95 err", "final err", "verdict"]
		)
	)
	for heading: float in HEADINGS:
		await _measure(heading)
	get_tree().quit(0)


func _measure(a_heading_deg: float) -> void:
	var unit: Actor = (load(_unit_path) as PackedScene).instantiate()
	_map.add_entity(unit, Vector2.ZERO, _commander)
	for _i: int in 4:
		await get_tree().physics_frame
	if _simplify > 0.0:
		var agent: NavigationAgent3D = _agent(unit)
		if agent != null:
			agent.simplify_path = true
			agent.simplify_epsilon = _simplify

	var start: Vector2 = _xz(unit.global_position)
	var dir := Vector2(cos(deg_to_rad(a_heading_deg)), sin(deg_to_rad(a_heading_deg)))
	var goal_xz: Vector2 = start + dir * _distance
	var goal := Vector3(goal_xz.x, _map.terrain_height_at(goal_xz), goal_xz.y)
	unit.update_commands(MoveCommand.new(CommandMessage.new(_map, null, null, goal)))

	var errors: PackedFloat32Array = PackedFloat32Array()
	var ticks: int = 0
	var final_err: float = 0.0
	var previous: Vector2 = _xz(unit.global_position)
	while ticks < TICKS:
		await get_tree().physics_frame
		ticks += 1
		var here: Vector2 = _xz(unit.global_position)
		# Measure the ACTUAL displacement rather than a reported velocity field, so whatever
		# the body really did (after avoidance, after move_and_slide) is what gets scored.
		var step: Vector2 = here - previous
		previous = here
		var remaining: Vector2 = goal_xz - here
		if step.length() >= MIN_SPEED and remaining.length() > ARRIVE:
			final_err = rad_to_deg(absf(step.angle_to(remaining)))
			errors.append(final_err)
		if remaining.length() <= ARRIVE:
			break

	unit.queue_free()
	await get_tree().physics_frame

	if errors.is_empty():
		print("%7.0f° | (never moved)" % a_heading_deg)
		return
	var sorted: Array = Array(errors)
	sorted.sort()
	var total: float = 0.0
	for e: float in errors:
		total += e
	var mean: float = total / errors.size()
	var worst: float = sorted[sorted.size() - 1]
	var p95: float = sorted[mini(int(sorted.size() * 0.95), sorted.size() - 1)]
	var verdict: String = "OK" if worst < 2.0 else ("drifts" if worst < 15.0 else "VEERS")
	print(
		(
			"%7.0f° | %7.2f° | %7.2f° | %7.2f° | %8.2f° | %s (%d ticks, %d samples)"
			% [a_heading_deg, mean, worst, p95, final_err, verdict, ticks, errors.size()]
		)
	)


func _agent(a_unit: Actor) -> NavigationAgent3D:
	for child: Node in a_unit.find_children("*", "NavigationAgent3D", true, false):
		return child as NavigationAgent3D
	return null


func _xz(a_v: Vector3) -> Vector2:
	return Vector2(a_v.x, a_v.z)
