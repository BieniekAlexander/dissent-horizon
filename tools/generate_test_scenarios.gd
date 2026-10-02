extends Node

## One-off generator for the example SimulationScenario scenes. Building a full scenario .tscn by
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
## The kamikaze drone. The piece was re-keyed `kamikaze` -> `an_aircraftLight_antiMech`
## when ids took the `<faction>_<role>` form; "Kamikaze" survives as its doc `title`, which
## is why the scenarios below still read that way. Its old scene is gone with the old id.
const KAMIKAZE: String = "res://scenes/entities/units/an/an_aircraftLight_antiMech.tscn"
const IRREGULAR: String = "res://scenes/entities/units/an/an_bioLight_builder.tscn"
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
	var root := SimulationScenario.new()
	root.name = "TestKamikazeCluster"
	root.max_ticks = 600
	root.player_slots = [
		_slot(PlayerSlot.Difficulty.MEDIUM, 1000),  # commander 1: the bot under test
		_slot(PlayerSlot.Difficulty.PASSIVE, 0),  # commander 2: inert target irregulars
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
	check.unit_type = EntityIds.AN_AIRCRAFT_LIGHT_ANTI_MECH
	check.command_name = "Attack"
	check.quantifier = ConditionUnitHasCommand.Quantifier.ANY
	root.expectations = [
		_expect("kamikaze attacks the cluster within 300 ticks", check, 300),
	]

	_save(root, "test_kamikaze_cluster.tscn")


# ─── SCENE 2: spread irregulars — kamikaze should NOT be committed ───────────


func _generate_kamikaze_no_cluster() -> void:
	var root := SimulationScenario.new()
	root.name = "TestKamikazeNoCluster"
	root.max_ticks = 1200
	root.player_slots = [
		_slot(PlayerSlot.Difficulty.MEDIUM, 1000),  # commander 1: the bot under test
		_slot(PlayerSlot.Difficulty.PASSIVE, 0),  # commander 2: inert, scattered irregulars
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
	check.unit_type = EntityIds.AN_AIRCRAFT_LIGHT_ANTI_MECH
	check.ticks = 300  # 10 physics seconds command-free
	root.expectations = [
		_expect("kamikaze stays command-free for 10s against spread irregulars", check, 900),
	]

	_save(root, "test_kamikaze_no_cluster.tscn")


# ─── SCENE 3: lone unit scouts the whole map ─────────────────────────────────


func _generate_scout_coverage() -> void:
	var root := SimulationScenario.new()
	root.name = "TestScoutCoverage"
	root.max_ticks = 3200
	# One bot, no economy (energy 0) so its lone unit is free to scout rather than build.
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


func _slot(a_difficulty: PlayerSlot.Difficulty, a_energy: int) -> PlayerSlot:
	var slot := PlayerSlot.new()
	slot.is_bot = true
	slot.faction = load(ANARCHICAL)
	slot.difficulty = a_difficulty
	slot.starting_energy = a_energy
	slot.starting_dominion = 0
	return slot


func _expect(
	a_description: String, a_condition: Condition, a_deadline_ticks: int
) -> SimulationExpectation:
	var e := SimulationExpectation.new()
	e.description = a_description
	e.condition = a_condition
	e.deadline_ticks = a_deadline_ticks
	return e


## Instantiate `scene_path` under `root` as a placed scenario entity owned by commander
## `commander_id`, at world XZ `xz` (terrain is flat at y = 0).
func _place(a_root: Node, a_scene_path: String, a_commander_id: int, a_xz: Vector2) -> void:
	var inst := (load(a_scene_path) as PackedScene).instantiate()
	inst.default_commander_id = a_commander_id
	a_root.add_child(inst)
	(inst as Node3D).position = Vector3(a_xz.x, 0.0, a_xz.y)


## A flat Map of `a_cells` × `a_cells` navigable cells.
##
## Delegates to SimArena, which builds the same thing for spec-driven runs. Two callers, one
## arena: a second copy of this scaffolding would drift the moment either side changed.
func _flat_map(a_cells: int) -> Map:
	return SimArena.flat_map(a_cells)


func _ring_points(a_center: Vector2, a_radius: float, a_count: int) -> Array:
	var points: Array = []
	for k: int in a_count:
		var ang: float = TAU * float(k) / float(a_count)
		points.append(a_center + Vector2(cos(ang), sin(ang)) * a_radius)
	return points


# ─── PACK + SAVE ─────────────────────────────────────────────────────────────


func _save(a_root: Node, a_file_name: String) -> void:
	_own_recursive(a_root, a_root)
	var packed := PackedScene.new()
	var err: int = packed.pack(a_root)
	if err != OK:
		push_error("pack failed for %s: %d" % [a_file_name, err])
		return
	var path: String = "%s/%s" % [OUT_DIR, a_file_name]
	err = ResourceSaver.save(packed, path)
	if err != OK:
		push_error("save failed for %s: %d" % [path, err])
		return
	print("[generate_test_scenarios] wrote ", path)


## Set owner = root on every node so pack() includes it. Recurse only into nodes we built;
## stop at instanced subtrees (scene_file_path != "") so they save as instance references.
func _own_recursive(a_node: Node, a_root: Node) -> void:
	for child: Node in a_node.get_children():
		child.owner = a_root
		if child.scene_file_path == "":
			_own_recursive(child, a_root)
