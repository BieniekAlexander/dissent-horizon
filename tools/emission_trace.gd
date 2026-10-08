extends Node3D

## Before/after harness for the emission rework (composition-rework.md §Step 2): fires every
## emission scene at a fixed cluster of targets and prints the damage each target took on
## each tick after launch, one line per hit, and where the emission was on every tick. Run it
## before a change and after, and diff the two outputs — an unchanged trace is the acceptance
## criterion.
##
## A probe, not a GUT test: it measures SHIPPED emissions, which are authored content, and
## it needs a live map for the blast queries. Its output is compared against itself.
##
## Run with:
##   godot --headless res://tools/emission_trace.tscn -- [out_path]

const SCENARIO: String = "res://scenes/scenarios/test/nav_straight_line.tscn"
const EMISSION_ROOT: String = "res://scenes/entities/projectiles"
## A target with no weapon, so the cluster never acts on its own.
const TARGET_SCENE: String = "res://scenes/entities/units/an/an_bioLight_builder.tscn"
## Large enough that no emission in the roster kills a target mid-trace; a death would end
## that target's record early and hide every later tick.
const TARGET_HP: float = 1.0e6
const RANGE_METRES: float = 6.0
const LAUNCH_HEIGHT_METRES: float = 1.5
## Offsets of the bystanders from the aimed-at target: one inside any blast in the roster,
## one at the edge of the larger ones, one outside all of them.
const BYSTANDER_OFFSETS: Array[Vector2] = [Vector2(0.0, 0.6), Vector2(1.5, 0.0), Vector2(0.0, 4.0)]
## Long enough for the slowest shell and the longest post-impact field in the roster.
const MAX_TICKS: int = 900
const RNG_SEED: int = 1

var _out_path: String = ""
var _lines: PackedStringArray = []
var _tick: int = 0


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out_path = args[0]
	_run.call_deferred()


func _physics_process(_a_delta: float) -> void:
	_tick += 1


func _run() -> void:
	var scenario: Node = (load(SCENARIO) as PackedScene).instantiate()
	add_child(scenario)
	await get_tree().physics_frame
	var map: Map = scenario.get_node("Map") as Map
	while not map.nav_manager.is_ready():
		await get_tree().physics_frame
	var player: Commander = scenario.call("local_player")
	var enemy: Commander = Commander.new()
	enemy.id = player.id + 1
	scenario.add_child(enemy)
	await get_tree().physics_frame

	for path: String in _emission_scenes(EMISSION_ROOT):
		for aimed_at_ground: bool in [false, true]:
			await _trace(map, player, enemy, path, aimed_at_ground)

	# Hits landing on one tick arrive in physics-query order, which is not behaviour: sort
	# within each emission's trace so only a change in WHAT was hit WHEN shows up in a diff.
	var text: String = "\n".join(_sorted_within_ticks(_lines)) + "\n"
	if _out_path.is_empty():
		print(text)
	else:
		var file: FileAccess = FileAccess.open(_out_path, FileAccess.WRITE)
		file.store_string(text)
		print("emission_trace: %d lines -> %s" % [_lines.size(), _out_path])
	get_tree().quit()


func _trace(
	a_map: Map, a_player: Commander, a_enemy: Commander, a_path: String, a_aimed_at_ground: bool
) -> void:
	var label: String = (
		"%s %s" % [a_path.get_file().get_basename(), "ground" if a_aimed_at_ground else "target"]
	)
	var centre: Vector2 = a_map.play_area().center
	var targets: Array[Actor] = []
	for offset: Vector2 in [Vector2.ZERO] + BYSTANDER_OFFSETS:
		targets.append(_spawn_target(a_map, a_enemy, centre + offset, targets.size(), label))
	await get_tree().physics_frame

	SU.rng.seed = RNG_SEED
	var emission: Entity = (load(a_path) as PackedScene).instantiate() as Entity
	emission.initialize(a_map, a_player)
	var origin_xz: Vector2 = centre - Vector2(RANGE_METRES, 0.0)
	emission.global_position = Vector3(
		origin_xz.x, a_map.terrain_height_at(origin_xz) + LAUNCH_HEIGHT_METRES, origin_xz.y
	)
	for target: Actor in targets:
		target.set_meta(&"trace_launch", _tick)
	Emitter.launch(emission, null, targets[0].global_position if a_aimed_at_ground else targets[0])

	var waited: int = 0
	while is_instance_valid(emission) and waited < MAX_TICKS:
		await get_tree().physics_frame
		waited += 1
		if is_instance_valid(emission):
			var at: Vector3 = emission.global_position
			_lines.append("%s | +%d at (%.3f, %.3f, %.3f)" % [label, waited, at.x, at.y, at.z])
	_lines.append(
		"%s | ends +%s" % [label, str(waited) if not is_instance_valid(emission) else "never"]
	)
	if is_instance_valid(emission):
		emission.queue_free()
	for target: Actor in targets:
		target.queue_free()
	await get_tree().physics_frame


func _spawn_target(
	a_map: Map, a_enemy: Commander, a_xz: Vector2, a_index: int, a_label: String
) -> Actor:
	var target: Actor = (load(TARGET_SCENE) as PackedScene).instantiate() as Actor
	target.initialize(a_map, a_enemy)
	target.global_position = Vector3(a_xz.x, a_map.terrain_height_at(a_xz), a_xz.y)
	target.defense.hp_max = TARGET_HP
	target.defense.hp = TARGET_HP
	var last_hp: Array[float] = [TARGET_HP]
	target.defense.hp_changed.connect(
		func(a_hp: float, _a_hp_max: float) -> void:
			var launch: int = target.get_meta(&"trace_launch", _tick)
			_lines.append(
				"%s | +%d t%d dmg=%.4f" % [a_label, _tick - launch, a_index, last_hp[0] - a_hp]
			)
			last_hp[0] = a_hp
	)
	return target


## Lines grouped by emission (their label, in trace order), each group's damage lines sorted.
static func _sorted_within_ticks(lines: PackedStringArray) -> PackedStringArray:
	var order: Array[String] = []
	var groups: Dictionary = {}
	for line: String in lines:
		var label: String = line.get_slice(" | ", 0)
		if not groups.has(label):
			order.append(label)
			groups[label] = []
		groups[label].append(line)
	var out: PackedStringArray = []
	for label: String in order:
		var group: Array = groups[label]
		var ends: Array = group.filter(func(l: String) -> bool: return l.contains("| ends"))
		var hits: Array = group.filter(func(l: String) -> bool: return not l.contains("| ends"))
		hits.sort_custom(
			func(a: String, b: String) -> bool:
				return _tick_of(a) < _tick_of(b) or (_tick_of(a) == _tick_of(b) and a < b)
		)
		out.append_array(PackedStringArray(hits + ends))
	return out


static func _tick_of(line: String) -> int:
	return int(line.get_slice(" | +", 1).get_slice(" ", 0))


static func _emission_scenes(root: String) -> Array[String]:
	var found: Array[String] = []
	var dir: DirAccess = DirAccess.open(root)
	for sub: String in dir.get_directories():
		found.append_array(_emission_scenes(root.path_join(sub)))
	for file: String in dir.get_files():
		if file.ends_with(".tscn"):
			found.append(root.path_join(file))
	found.sort()
	return found
