extends Node

## One-off generator for the example TestScenario scenes. Building a full scenario .tscn by
## hand (map node tree, embedded heightmap, player slots, placed entities, expectation +
## condition sub-resources) is error-prone, so we assemble each scene programmatically and
## pack it to a real .tscn the user can then OPEN AND EDIT in the Godot editor.
##
## Run once (re-run to regenerate) as a MAIN SCENE so the project's autoloads (DamageTable,
## …) are registered before the entity scripts compile — running via `--script` compiles
## those deps before autoloads exist and corrupts the saved entities (attributes_list → null):
##   godot --headless res://tools/generate_test_scenarios.tscn
##
## It does NOT add anything to the running tree — it builds orphan node trees, sets owners,
## packs and saves, so no entity _ready/auto-init side effects fire.

const ANARCHICAL: String = "res://scenes/factions/anarchical.tscn"
const KAMIKAZE: String = "res://scenes/entities/units/an/kamikaze.tscn"
const IRREGULAR: String = "res://scenes/entities/units/an/irregular.tscn"
const TECHNICIAN: String = "res://scenes/entities/units/an/technician.tscn"

const OUT_DIR: String = "res://scenes/scenarios/test"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_generate_kamikaze_cluster()
	_generate_kamikaze_no_cluster()
	_generate_scout_coverage()
	print("[generate_test_scenarios] done")
	get_tree().quit()


# ─── SCENE 1: kamikaze attacks a cluster ─────────────────────────────────────

func _generate_kamikaze_cluster() -> void:
	var root := TestScenario.new()
	root.name = "TestKamikazeCluster"
	root.max_ticks = 600
	root.player_slots = [
		_slot(PlayerSlot.Difficulty.MEDIUM, 1000),   # commander 1: the bot under test
		_slot(PlayerSlot.Difficulty.PASSIVE, 0),      # commander 2: inert target irregulars
	]
	root.add_child(_flat_map(20))

	# The bot's drone, just off the cluster (within its vision of ~5).
	_place(root, KAMIKAZE, 1, Vector2(0, 3))
	# A tight knot of 7 irregulars within ~1.3 of the origin — inside the ~2-unit blast.
	for p: Vector2 in _ring_points(Vector2.ZERO, 1.0, 6):
		_place(root, IRREGULAR, 2, p)
	_place(root, IRREGULAR, 2, Vector2.ZERO)

	var check := ConditionUnitHasCommand.new()
	check.commander_id = 1
	check.unit_type = EntityIds.KAMIKAZE
	check.command_name = "Attack"
	check.quantifier = ConditionUnitHasCommand.Quantifier.ANY
	root.expectations = [
		_expect("kamikaze attacks the cluster within 300 ticks", check, 300),
	]

	_save(root, "test_kamikaze_cluster.tscn")


# ─── SCENE 2: spread irregulars — kamikaze should NOT be committed ───────────

func _generate_kamikaze_no_cluster() -> void:
	var root := TestScenario.new()
	root.name = "TestKamikazeNoCluster"
	root.max_ticks = 1200
	root.player_slots = [
		_slot(PlayerSlot.Difficulty.MEDIUM, 1000),   # commander 1: the bot under test
		_slot(PlayerSlot.Difficulty.PASSIVE, 0),      # commander 2: inert, scattered irregulars
	]
	root.add_child(_flat_map(28))

	# The bot's drone, alone at the centre.
	_place(root, KAMIKAZE, 1, Vector2.ZERO)
	# Irregulars scattered to the far edges — no two close enough to share a blast, and all
	# well outside the drone's ~5-unit engagement range, so there's no worthwhile run and
	# nothing for the drone to auto-aggro. The bot should simply leave it alone.
	for p: Vector2 in [Vector2(11, 11), Vector2(-11, 11), Vector2(11, -11), Vector2(-11, -11)]:
		_place(root, IRREGULAR, 2, p)

	var check := ConditionUnitHasNoCommandFor.new()
	check.commander_id = 1
	check.unit_type = EntityIds.KAMIKAZE
	check.ticks = 300  # 10 physics seconds command-free
	root.expectations = [
		_expect("kamikaze stays command-free for 10s against spread irregulars", check, 900),
	]

	_save(root, "test_kamikaze_no_cluster.tscn")


# ─── SCENE 3: lone unit scouts the whole map ─────────────────────────────────

func _generate_scout_coverage() -> void:
	var root := TestScenario.new()
	root.name = "TestScoutCoverage"
	root.max_ticks = 3200
	# One bot, no economy (ore 0) so its lone unit is free to scout rather than build.
	root.player_slots = [_slot(PlayerSlot.Difficulty.MEDIUM, 0)]
	# Map sized so a single unit, seeing only its true ~5-unit vision radius, can still
	# sweep every scout point within the 3000-tick budget — yet wider than that radius, so
	# it must travel to the corners rather than seeing everything from spawn.
	root.add_child(_flat_map(16))

	# A single fast unit at centre.
	_place(root, TECHNICIAN, 1, Vector2.ZERO)

	var check := ConditionScoutCoverage.new()
	check.commander_id = 1
	check.minimum_fraction = 1.0
	root.expectations = [
		_expect("every scout point seen at least once within 3000 ticks", check, 3000),
	]

	_save(root, "test_scout_coverage.tscn")


# ─── BUILDERS ────────────────────────────────────────────────────────────────

func _slot(difficulty: PlayerSlot.Difficulty, ore: int) -> PlayerSlot:
	var slot := PlayerSlot.new()
	slot.is_bot = true
	slot.faction = load(ANARCHICAL)
	slot.difficulty = difficulty
	slot.starting_ore = ore
	slot.starting_dominion = 0
	return slot


func _expect(description: String, condition: Condition, deadline_ticks: int) -> TestExpectation:
	var e := TestExpectation.new()
	e.description = description
	e.condition = condition
	e.deadline_ticks = deadline_ticks
	return e


## Instantiate `scene_path` under `root` as a placed scenario entity owned by commander
## `commander_id`, at world XZ `xz` (terrain is flat at y = 0).
func _place(root: Node, scene_path: String, commander_id: int, xz: Vector2) -> void:
	var inst := (load(scene_path) as PackedScene).instantiate()
	inst.default_commander_id = commander_id
	root.add_child(inst)
	(inst as Node3D).position = Vector3(xz.x, 0.0, xz.y)


## A flat Map with `cells`×`cells` navigable cells, matching the node layout Map expects
## ($NavigationRegion/Body/Shape) and a HeightMapShape3D of all-zero heights.
func _flat_map(cells: int) -> Map:
	var corners: int = cells + 1
	var hs := HeightMapShape3D.new()
	hs.map_width = corners
	hs.map_depth = corners
	var data := PackedFloat32Array()
	data.resize(corners * corners)
	hs.map_data = data

	var m := Map.new()
	m.name = "Map"

	var nav := NavigationRegion3D.new()
	nav.name = "NavigationRegion"
	nav.add_to_group("navigation_mesh_source_group", true)
	nav.navigation_mesh = NavigationMesh.new()

	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = CollisionLayers.Mask.TERRAIN
	body.collision_mask = 0
	nav.add_child(body)

	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	shape.shape = hs
	body.add_child(shape)

	m.add_child(nav)

	var pins := Node3D.new()
	pins.name = "HeightPins"
	m.add_child(pins)

	m.height_map = hs
	return m


func _ring_points(center: Vector2, radius: float, count: int) -> Array:
	var points: Array = []
	for k: int in count:
		var ang: float = TAU * float(k) / float(count)
		points.append(center + Vector2(cos(ang), sin(ang)) * radius)
	return points


# ─── PACK + SAVE ─────────────────────────────────────────────────────────────

func _save(root: Node, file_name: String) -> void:
	_own_recursive(root, root)
	var packed := PackedScene.new()
	var err: int = packed.pack(root)
	if err != OK:
		push_error("pack failed for %s: %d" % [file_name, err])
		return
	var path: String = "%s/%s" % [OUT_DIR, file_name]
	err = ResourceSaver.save(packed, path)
	if err != OK:
		push_error("save failed for %s: %d" % [path, err])
		return
	print("[generate_test_scenarios] wrote ", path)


## Set owner = root on every node so pack() includes it. Recurse only into nodes we built;
## stop at instanced subtrees (scene_file_path != "") so they save as instance references.
func _own_recursive(node: Node, root: Node) -> void:
	for child: Node in node.get_children():
		child.owner = root
		if child.scene_file_path == "":
			_own_recursive(child, root)
