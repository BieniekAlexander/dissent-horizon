extends Node3D

## Boots a mesh-terrain test scenario headlessly and checks that the baked surface is
## actually playable: the navmesh builds, the Skirmish rig deploys structures and units onto
## it, and a unit ordered across the map gets there.
##
## Run with:
## godot --headless res://tools/terrain_meshes/verify_scene.tscn -- <res://scene.tscn> [move_x]
## [move_z]
##
## Needs a real main loop (not `godot -s`) because the game's autoloads — DamageTable,
## SceneManager — only exist for a scene main loop, and Scenario touches them on the way up.

## Physics ticks to let a unit travel before giving up on it.
const MOVE_TIMEOUT_TICKS: int = 3000
## How close to the ordered point counts as arrived, in world units.
const ARRIVAL_EPSILON: float = 3.0

var _scene_path: String = ""
var _move_target := Vector3(30.0, 0.0, -30.0)
var _scenario: Node = null
var _map: Map = null
var _failures: PackedStringArray = PackedStringArray()
var _probe: PackedFloat32Array = PackedFloat32Array()
var _probe_expect: String = "connected"


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 1:
		push_error("usage: verify_scene.tscn -- <res://scene.tscn> [move_x] [move_z]")
		get_tree().quit(2)
		return
	_scene_path = args[0]
	if args.size() >= 3:
		_move_target = Vector3(float(args[1]), 0.0, float(args[2]))
	var probe_at: int = args.find("--probe")
	if probe_at >= 0 and args.size() >= probe_at + 6:
		for i: int in 4:
			_probe.append(float(args[probe_at + 1 + i]))
		_probe_expect = args[probe_at + 5]
	_run.call_deferred()


func _run() -> void:
	print("=== %s ===" % _scene_path)
	var packed: PackedScene = load(_scene_path)
	if packed == null:
		_fail("scene failed to load")
		return _finish()
	_scenario = packed.instantiate()
	add_child(_scenario)
	await get_tree().physics_frame

	_map = _scenario.get_node_or_null("Map") as Map
	if _map == null:
		_fail("no Map node")
		return _finish()

	await _report_terrain()
	await _report_navmesh()
	await _report_forces()
	await _report_movement()
	_report_probe()
	_finish()


## The baked heightfield as the game sees it, via TerrainGrid — the layer that decides
## passability, so this is what the navmesh is built from.
func _report_terrain() -> void:
	var data: TerrainData = _map.terrain_data
	var grid: TerrainGrid = _map.terrain_grid
	if data == null or grid == null:
		_fail("no terrain_data / terrain_grid")
		return
	var gw: int = grid.grid_width()
	var gd: int = grid.grid_depth()
	var passable: int = 0
	var steep: int = 0
	var lo: float = INF
	var hi: float = -INF
	for z: int in gd:
		for x: int in gw:
			var cell := Vector2i(x, z)
			if grid.is_passable(cell):
				passable += 1
			if data.cell_height_spread(cell) > TerrainGrid.MAX_SLOPE_DIFF:
				steep += 1
	for h: float in data.heights:
		lo = minf(lo, h)
		hi = maxf(hi, h)
	print(
		(
			"terrain   : %dx%d cells | passable %d | steep %d | height %.2f..%.2f"
			% [gw, gd, passable, steep, lo, hi]
		)
	)
	if passable == 0:
		_fail("no passable cells — nothing could ever move")


func _report_navmesh() -> void:
	var nav: NavManager = _map.nav_manager
	if nav == null:
		_fail("no NavManager")
		return
	var waited: int = 0
	while not nav.is_ready() and waited < 600:
		await get_tree().physics_frame
		waited += 1
	if not nav.is_ready():
		_fail("navmesh never became ready (%d ticks)" % waited)
		return
	var polys: int = nav.base_polygon_count()
	print("navmesh   : ready after %d ticks | base mesh %d polygons" % [waited, polys])
	if polys == 0:
		_fail("navmesh baked zero polygons")


func _report_forces() -> void:
	# Skirmish defers deployment to navmesh_ready; give it frames to land.
	for _i: int in 60:
		await get_tree().physics_frame
	var commanders: Array = _scenario.get("commanders")
	if commanders == null or commanders.is_empty():
		_fail("no commanders")
		return
	for commander: Node in commanders:
		var units: int = 0
		var structures: int = 0
		for child: Node in commander.get_children():
			if child is Entity:
				if child.is_in_group("structure"):
					structures += 1
				elif child.is_in_group("unit"):
					units += 1
		print("commander %s: %d structures, %d units" % [commander.get("id"), structures, units])
	var player: Node = _scenario.call("local_player")
	if player == null:
		_fail("no local player commander")
		return
	if _owned_units(player).is_empty():
		_fail("player deployed no units onto the surface")


## Order one unit across the map and watch whether it actually gets there. This is the check
## that the navmesh is not merely non-empty but connected and standable-on.
func _report_movement() -> void:
	var player: Node = _scenario.call("local_player")
	if player == null:
		return
	var units: Array = _owned_units(player)
	if units.is_empty():
		return
	var unit: Commandable = units[0]
	var start: Vector3 = unit.global_position
	var goal := Vector3(
		_move_target.x,
		_map.terrain_height_at(Vector2(_move_target.x, _move_target.z)),
		_move_target.z
	)

	var message := CommandMessage.new(_map, null, null, goal)
	unit.update_commands(MoveCommand.new(message))

	var ticks: int = 0
	var best: float = INF
	var path_length: float = 0.0
	var previous: Vector3 = start
	var trace: PackedStringArray = PackedStringArray()
	while ticks < MOVE_TIMEOUT_TICKS:
		await get_tree().physics_frame
		ticks += 1
		var here: Vector3 = unit.global_position
		path_length += Vector2(here.x - previous.x, here.z - previous.z).length()
		previous = here
		best = minf(best, Vector2(here.x - goal.x, here.z - goal.z).length())
		if ticks % 300 == 0:
			trace.append("t%d:%.1f" % [ticks, best])
		if best <= ARRIVAL_EPSILON:
			break

	var end_pos: Vector3 = unit.global_position
	var travelled: float = Vector2(end_pos.x - start.x, end_pos.z - start.z).length()
	var ordered: float = Vector2(goal.x - start.x, goal.z - start.z).length()
	# The navmesh's own nearest point to the goal: if the goal is inside a structure footprint
	# or off the surface, the unit CANNOT reach it and the shortfall is the map's, not a bug.
	var reachable: Vector3 = _map.nearest_navmesh_point(goal)
	var goal_offset: float = Vector2(reachable.x - goal.x, reachable.z - goal.z).length()
	print(
		(
			"movement  : %s from (%.1f, %.1f) -> ordered (%.1f, %.1f)"
			% [unit.id, start.x, start.z, goal.x, goal.z]
		)
	)
	print(
		(
			"            travelled %.1f of %.1f units in %d ticks | closest approach %.2f"
			% [travelled, ordered, ticks, best]
		)
	)
	print("            terrain-following Y: start %.2f, end %.2f" % [start.y, end_pos.y])
	# Walked distance vs the straight line. A detour ratio well over 1 is the evidence that
	# the unit went AROUND an obstacle rather than through where one should have been.
	print(
		(
			"            walked %.1f units for a %.1f straight line (detour x%.2f)"
			% [path_length, ordered, path_length / maxf(ordered, 0.001)]
		)
	)
	print("            remaining-distance trace: %s" % " ".join(trace))
	print(
		(
			"            nearest navmesh point to goal is %.2f away | nav finished %s | idle %s"
			% [
				goal_offset,
				unit.movement.is_navigation_finished() if unit.movement != null else "n/a",
				unit.command_receiver.is_idle()
			]
		)
	)
	# Judge against what is actually reachable — a goal 8 units inside a building is not a
	# movement failure, and scoring it as one would make the harness lie.
	var allowed: float = ARRIVAL_EPSILON + goal_offset
	if best > allowed:
		_fail(
			"unit did not reach its ordered point (closest %.2f, needed <= %.2f)" % [best, allowed]
		)


## Whether the navigation map can path from `from` to `to`. Used to ask structural questions
## of the baked surface — e.g. that a vertical-walled plateau's top is an ISLAND, reachable
## by nothing on the ground.
func _navmesh_connects(a_from: Vector3, a_to: Vector3) -> bool:
	var nav_map: RID = _map.nav_region.get_navigation_map()
	if not nav_map.is_valid():
		return false
	var path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, a_from, a_to, true)
	if path.is_empty():
		print("            (path query returned nothing)")
		return false
	var landed: Vector3 = path[path.size() - 1]
	var gap: float = Vector2(landed.x - a_to.x, landed.z - a_to.z).length()
	# A partial path — one that stops short — is how Godot reports "as close as I could get",
	# which looks identical to "unreachable" unless the shortfall is printed.
	print("            (path: %d points, ends %.1f from the target)" % [path.size(), gap])

	# Same query with a raised polygon budget. Godot's default search cap is low relative to a
	# one-quad-per-cell navmesh, and when A* exhausts it the server returns a PARTIAL path
	# rather than an error — indistinguishable from "unreachable" unless you look.
	var params := NavigationPathQueryParameters3D.new()
	params.map = nav_map
	params.start_position = a_from
	params.target_position = a_to
	params.path_search_max_polygons = 1 << 20
	var result := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(params, result)
	var big: PackedVector3Array = result.path
	if not big.is_empty():
		var last: Vector3 = big[big.size() - 1]
		print(
			(
				"            (budget 1M: %d points, ends %.1f from the target)"
				% [big.size(), Vector2(last.x - a_to.x, last.z - a_to.z).length()]
			)
		)
	return gap <= 2.0


## Optional CLI probe: `--probe ax az bx bz expect` where expect is "connected" or "isolated".
func _report_probe() -> void:
	if _probe.is_empty():
		return
	var a := Vector3(_probe[0], 0.0, _probe[1])
	var b := Vector3(_probe[2], 0.0, _probe[3])
	a.y = _map.terrain_height_at(Vector2(a.x, a.z))
	b.y = _map.terrain_height_at(Vector2(b.x, b.z))
	var connected: bool = _navmesh_connects(a, b)
	print(
		(
			"probe     : (%.0f, %.0f) y=%.2f -> (%.0f, %.0f) y=%.2f | %s (expected %s)"
			% [
				a.x,
				a.z,
				a.y,
				b.x,
				b.z,
				b.y,
				"connected" if connected else "isolated",
				_probe_expect
			]
		)
	)
	if (_probe_expect == "connected") != connected:
		_fail(
			(
				"probe expected %s but the navmesh reports %s"
				% [_probe_expect, "connected" if connected else "isolated"]
			)
		)


func _owned_units(a_commander: Node) -> Array:
	var out: Array = []
	for child: Node in a_commander.get_children():
		if (
			child is Commandable
			and child.is_in_group("unit")
			and not child.is_queued_for_deletion()
		):
			out.append(child)
	return out


func _fail(a_reason: String) -> void:
	_failures.append(a_reason)


func _finish() -> void:
	if _failures.is_empty():
		print("RESULT: PASS\n")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			print("FAILURE: %s" % f)
		print("RESULT: FAIL\n")
		get_tree().quit(1)
