extends Node

## Lays prologue mission 1's pieces onto the DRAFT topology (tools/missions/
## prologue_m1_topology_draft.gd), from the marks on Alex's sketch
## (gdd/campaigns/01-prologue/m1_topology_sketch.png, 2026-10-21; gdd/tasks.md T-126), so the
## map's scale can be judged with real pieces on it. Writes a NEW scenario scene only; the
## mission's own scene is untouched. It refuses to overwrite its output, so a layout someone
## has since edited by hand is never lost: delete the scene by hand to lay it down again.
##
##   godot --headless --path . res://tools/missions/prologue_m1_draft_layout.tscn
##
## Run as a MAIN SCENE, not via --script, so the autoloads exist before the piece scripts
## compile (as tools/missions/prologue_m1_layout.gd does). Pieces are instanced with edit state
## so the pack stores only what a placement changed.
##
## The sketch's legend for pieces: white is neutral, yellow allied, red enemy; small white boxes
## are neutral buildings, large boxes base areas, T a Watch Tower, S a SAM site, C a Compound,
## small circles units, the star the Citadel. Its two-way arrow is where the waves meet; the
## enemy's waves spawn beside the Citadel (Alex, 2026-10-21).

const Draft = preload("res://tools/missions/prologue_m1_topology_draft.gd")

const OUT_SCENE: String = "res://scenes/scenarios/prologue/m1_draft_layout.tscn"
const DRAFT_MAP: String = "res://scenes/scenarios/prologue/m1_topology_draft_map.tscn"

const ANARCHICAL: String = "res://scenes/factions/anarchical.tscn"
const COLONIAL: String = "res://scenes/factions/colonial.tscn"
const WARLORD: String = "res://scenes/entities/units/an/an_bioMedium_dominionGen.tscn"
const IRREGULAR: String = "res://scenes/entities/units/an/an_bioLight_builder.tscn"
const RAVEN: String = "res://scenes/entities/units/an/an_aircraftLight_transport.tscn"
const RECRUIT: String = "res://scenes/entities/units/cl/cl_bioLight_antiLight.tscn"
const CLIPPER: String = "res://scenes/entities/units/cl/cl_aircraftLight_antiLight.tscn"
const STRONGHOLD: String = "res://scenes/entities/structures/an/an_commandCenter.tscn"
const REDOUBT: String = "res://scenes/entities/structures/an/an_barracks.tscn"
const SAFEHOUSE: String = "res://scenes/entities/structures/an/an_infrastructure.tscn"
const WATCH_TOWER: String = "res://scenes/entities/structures/cl/cl_defense_antiLight.tscn"
const SAM_SITE: String = "res://scenes/entities/structures/cl/cl_defense_antiAircraft.tscn"
const COMPOUND: String = "res://scenes/entities/structures/cl/cl_infrastructure.tscn"
const CITADEL: String = "res://scenes/entities/structures/cl/cl_commandCenter.tscn"
const BARRACKS: String = "res://scenes/entities/structures/cl/cl_barracks.tscn"
const SKY_PORT: String = "res://scenes/entities/structures/cl/cl_airField.tscn"
const BUILDING_SQUARE: String = "res://scenes/entities/structures/nt/nt_building_square.tscn"
const BUILDING_LONG: String = "res://scenes/entities/structures/nt/nt_building_long.tscn"
const BUILDING_SHACK: String = "res://scenes/entities/structures/nt/nt_building_shack.tscn"

## Commander ids, in slot order.
const PLAYER: int = 1
const ALLY: int = 2
const ENEMY: int = 3
## The bot brain jobs a scripted commander keeps (see prologue_m1_layout.gd _slot).
const PERCEPTION_JOBS: Array[StringName] = [&"fields", &"scout_sight", &"momentum"]

## Everything below is in the sketch's pixels.
const PLAYER_START := Vector2(40, 995)
## Neutral building lots: [centre x, centre y, width, height] of each small white box.
const BUILDING_LOTS: Array = [
	[435, 128, 42, 50],
	[515, 130, 85, 42],
	[148, 247, 56, 57],
	[145, 335, 59, 91],
	[1048, 435, 36, 36],
	[1096, 437, 31, 40],
	[1119, 523, 40, 79],
	[452, 766, 44, 45],
	[494, 776, 25, 26],
	[136, 786, 49, 39],
	[222, 802, 64, 36],
	[262, 864, 54, 28],
	[267, 998, 26, 48],
	[1299, 998, 58, 44],
	[1215, 1000, 74, 40],
	[173, 1009, 23, 21],
]
const WATCH_TOWERS: Array = [
	[1179, 55],
	[1138, 130],
	[855, 512],
	[767, 607],
	[377, 644],
	[435, 677],
	[630, 688],
	[760, 730],
	[718, 903],
	[702, 985],
]
const SAM_SITES: Array = [
	[912, 134], [936, 216], [711, 357], [877, 442], [1000, 467], [888, 630], [533, 644]
]
const COMPOUNDS: Array = [
	[363, 458],
	[356, 506],
	[25, 730],
	[53, 762],
	[1292, 777],
	[1249, 803],
	[1306, 885],
	[1305, 946],
	[1081, 945],
	[1031, 960],
]
## Enemy squads: [centre x, centre y, how many].
const ENEMY_SQUADS: Array = [[812, 132, 3], [270, 757, 3], [400, 932, 3]]
const ALLY_SQUAD := Vector3(262, 900, 6)
const CITADEL_AT := Vector2(1222, 676)
## Base areas: the box's corners, and what stands in it.
const ENEMY_BASE_NORTH := Rect2(1209, 99, 92, 184)
const ENEMY_BASE_SOUTH := Rect2(782, 804, 184, 186)
const ALLY_BASE := Rect2(75, 43, 205, 132)
## The transports beside the SAM sites at beat 5, the ally's until the sites fall.
const RAVENS: Array = [[862, 160], [868, 200], [858, 240]]
## The waves: the arrow's allied end, and beside the Citadel.
const ALLY_WAVE_SPAWN := Vector2(300, 190)
const ENEMY_WAVE_SPAWN := Vector2(1150, 690)

## Building lots are filled at about this spacing, in world units, up to LOT_CAP buildings.
const LOT_SPACING: float = 6.0
const LOT_CAP: int = 6

const ALLY_WAVE: StringName = &"prologue_m1_ally_wave"
const ENEMY_WAVE: StringName = &"prologue_m1_enemy_wave"
const RAVEN_GROUP: StringName = &"prologue_m1_ravens"

var _counts: Dictionary = {}
var _terrain: TerrainData


func _ready() -> void:
	if ResourceLoader.exists(OUT_SCENE):
		push_error("draft layout: %s exists; delete it by hand to lay it down again" % OUT_SCENE)
		get_tree().quit(1)
		return
	var root := Scenario.new()
	root.name = "PrologueMission1Draft"
	root.win_condition = Scenario.WinCondition.NONE
	root.debug_allowed = true
	root.player_slots = [
		_slot(false, ANARCHICAL, 1, true),
		_slot(true, ANARCHICAL, 1, false),
		_slot(true, COLONIAL, 2, true),
	]
	var map: Node = (load(DRAFT_MAP) as PackedScene).instantiate(
		PackedScene.GEN_EDIT_STATE_INSTANCE
	)
	root.add_child(map)
	_terrain = (map as Map).terrain_data

	_place(root, WARLORD, PLAYER, PLAYER_START, "Warlord")
	for lot: Array in BUILDING_LOTS:
		_lot(root, lot)
	for at: Array in WATCH_TOWERS:
		_place(root, WATCH_TOWER, ENEMY, Vector2(at[0], at[1]), "WatchTower")
	for at: Array in SAM_SITES:
		_place(root, SAM_SITE, ENEMY, Vector2(at[0], at[1]), "SamSite")
	for at: Array in COMPOUNDS:
		_place(root, COMPOUND, ENEMY, Vector2(at[0], at[1]), "Compound")
	_place(root, CITADEL, ENEMY, CITADEL_AT, "Citadel")
	_base(root, ENEMY, ENEMY_BASE_NORTH, [BARRACKS, SKY_PORT])
	_base(root, ENEMY, ENEMY_BASE_SOUTH, [BARRACKS, BARRACKS, SKY_PORT])
	_base(root, ALLY, ALLY_BASE, [STRONGHOLD, REDOUBT, REDOUBT, SAFEHOUSE, SAFEHOUSE])
	for squad: Array in ENEMY_SQUADS:
		_squad(root, RECRUIT, ENEMY, Vector2(squad[0], squad[1]), squad[2], "Recruit")
	_squad(root, IRREGULAR, ALLY, Vector2(ALLY_SQUAD.x, ALLY_SQUAD.y), ALLY_SQUAD.z, "Irregular")
	for at: Array in RAVENS:
		var raven: Node3D = _place(root, RAVEN, ALLY, Vector2(at[0], at[1]), "Raven")
		raven.add_to_group(RAVEN_GROUP, true)
		root.set_editable_instance(raven, true)
		(raven.get_node("Aerial") as Aerial).should_start_landed = true

	var manager := ScenarioTriggerManager.new()
	manager.name = "ScenarioTriggerManager"
	root.add_child(manager)
	_waves(manager)

	_seat_on_terrain(root)
	_save(root)
	get_tree().quit(0)


func _slot(a_is_bot: bool, a_faction: String, a_team: int, a_shares_vision: bool) -> PlayerSlot:
	var slot := PlayerSlot.new()
	slot.is_bot = a_is_bot
	slot.faction = load(a_faction)
	slot.alliance = a_team
	slot.difficulty = PlayerSlot.Difficulty.PASSIVE
	if a_is_bot:
		var acting: Array[StringName] = []
		for job: StringName in BotBrain.JOB_NAMES:
			if not PERCEPTION_JOBS.has(job):
				acting.append(job)
		slot.disabled_bot_jobs = acting
	slot.starting_energy = 0
	slot.starting_dominion = 0
	slot.shares_vision_with_allies = a_shares_vision
	return slot


## The Map-local position of a sketch pixel, at height 0 (seated later).
static func _world(a_px: Vector2) -> Vector3:
	var xz: Vector2 = Draft.lane_to_world(Draft.sketch_to_lane(a_px))
	return Vector3(xz.x, 0.0, xz.y)


func _place(
	a_parent: Node, a_scene: String, a_commander: int, a_px: Vector2, a_name: String
) -> Node3D:
	var piece := (
		(load(a_scene) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	)
	piece.set("default_commander_id", a_commander)
	_counts[a_name] = int(_counts.get(a_name, 0)) + 1
	piece.name = "%s%d" % [a_name, _counts[a_name]]
	a_parent.add_child(piece, true)
	piece.position = _world(a_px)
	return piece


## A white box's buildings: a small grid at about LOT_SPACING apart, square, long and shack in
## turn, so a box reads as a cluster of buildings of the size it was drawn.
func _lot(a_root: Node, a_lot: Array) -> void:
	var size := Vector2(a_lot[2], a_lot[3]) * Draft.SCALE
	var cols: int = maxi(1, floori(size.x / LOT_SPACING))
	var rows: int = maxi(1, floori(size.y / LOT_SPACING))
	while cols * rows > LOT_CAP:
		if cols >= rows:
			cols -= 1
		else:
			rows -= 1
	var kinds: Array[String] = [BUILDING_SQUARE, BUILDING_LONG, BUILDING_SHACK]
	var n: int = 0
	for r: int in rows:
		for c: int in cols:
			var offset := (
				Vector2((c - (cols - 1) * 0.5) * LOT_SPACING, (r - (rows - 1) * 0.5) * LOT_SPACING)
				/ Draft.SCALE
			)
			_place(
				a_root, kinds[n % kinds.size()], 0, Vector2(a_lot[0], a_lot[1]) + offset, "Building"
			)
			n += 1


## Base structures spread along a base box's long axis.
func _base(a_root: Node, a_commander: int, a_box: Rect2, a_scenes: Array) -> void:
	for k: int in a_scenes.size():
		var f: float = (k + 0.5) / a_scenes.size()
		var at: Vector2 = (
			a_box.position + Vector2(a_box.size.x * f, a_box.size.y * 0.5)
			if a_box.size.x >= a_box.size.y
			else a_box.position + Vector2(a_box.size.x * 0.5, a_box.size.y * f)
		)
		_place(a_root, a_scenes[k], a_commander, at, String(a_scenes[k]).get_file().get_basename())


## `a_count` of a unit in a tight cluster round a sketch point.
func _squad(
	a_root: Node, a_scene: String, a_commander: int, a_px: Vector2, a_count: int, a_name: String
) -> void:
	var cols: int = ceili(sqrt(float(a_count)))
	for k: int in a_count:
		var offset := Vector2(k % cols - (cols - 1) * 0.5, k / cols - (cols - 1) * 0.5) * 1.5
		_place(a_root, a_scene, a_commander, a_px + offset / Draft.SCALE, a_name)


## The lane waves as the mission runs them (gdd/campaigns/01-prologue/01-pervasive-mechanics.md
## §Waves): a side's next wave comes when the other side's units come within half the lane of
## its spawn and none of its last wave lives; when both are spent, both come.
func _waves(a_manager: Node) -> void:
	var half_lane: float = _world(ALLY_WAVE_SPAWN).distance_to(_world(ENEMY_WAVE_SPAWN)) * 0.5
	var ally_scenes: Array = [IRREGULAR, IRREGULAR, IRREGULAR, WARLORD, WARLORD]
	var enemy_scenes: Array = [RECRUIT, RECRUIT, RECRUIT, CLIPPER, CLIPPER]
	var ally := _trigger(a_manager, "AllyWaves", [_spent(ALLY_WAVE), _near(ENEMY)])
	_region(ally, ALLY_WAVE_SPAWN, half_lane)
	_spawn(ally, "Spawn", ALLY, ally_scenes, ALLY_WAVE, ALLY_WAVE_SPAWN)
	var enemy := _trigger(a_manager, "EnemyWaves", [_spent(ENEMY_WAVE), _near(ALLY)])
	_region(enemy, ENEMY_WAVE_SPAWN, half_lane)
	_spawn(enemy, "Spawn", ENEMY, enemy_scenes, ENEMY_WAVE, ENEMY_WAVE_SPAWN)
	var both := _trigger(a_manager, "BothWavesSpent", [_spent(ALLY_WAVE), _spent(ENEMY_WAVE)])
	_spawn(both, "AllySpawn", ALLY, ally_scenes, ALLY_WAVE, ALLY_WAVE_SPAWN)
	_spawn(both, "EnemySpawn", ENEMY, enemy_scenes, ENEMY_WAVE, ENEMY_WAVE_SPAWN)
	_assault(a_manager, "AllyWaveTactic", ALLY_WAVE, ENEMY_WAVE_SPAWN)
	_assault(a_manager, "EnemyWaveTactic", ENEMY_WAVE, ALLY_WAVE_SPAWN)


func _trigger(a_manager: Node, a_name: String, a_conditions: Array) -> GlobalTrigger:
	var trigger := GlobalTrigger.new()
	trigger.name = a_name
	trigger.one_shot = false
	var conditions: Array[Condition] = []
	conditions.assign(a_conditions)
	trigger.conditions = conditions
	a_manager.add_child(trigger)
	return trigger


func _spent(a_group: StringName) -> ConditionGroupCount:
	var c := ConditionGroupCount.new()
	c.group = a_group
	c.comparison = ConditionGroupCount.Comparison.AT_MOST
	c.count = 0
	return c


func _near(a_commander: int) -> ConditionUnitsInRegion:
	var c := ConditionUnitsInRegion.new()
	c.commander_id = a_commander
	c.region_shape_path = NodePath("ApproachRegion")
	return c


func _region(a_trigger: Node, a_px: Vector2, a_radius: float) -> void:
	var region := CollisionShape3D.new()
	region.name = "ApproachRegion"
	var shape := CylinderShape3D.new()
	shape.radius = a_radius
	shape.height = 4.0
	region.shape = shape
	a_trigger.add_child(region)
	region.position = _world(a_px)


func _spawn(
	a_trigger: Node,
	a_name: String,
	a_commander: int,
	a_scenes: Array,
	a_group: StringName,
	a_px: Vector2
) -> void:
	var spawn := EventSpawnEntities.new()
	spawn.name = a_name
	spawn.commander_id = a_commander
	var scenes: Array[PackedScene] = []
	for path: String in a_scenes:
		scenes.append(load(path) as PackedScene)
	spawn.entity_scenes = scenes
	spawn.count_expression = "1"
	spawn.spawn_groups = [a_group]
	a_trigger.add_child(spawn)
	spawn.position = _world(a_px)


func _assault(a_manager: Node, a_name: String, a_group: StringName, a_px: Vector2) -> void:
	var tactic := ScenarioTactic.new()
	tactic.name = a_name
	tactic.unit_group = a_group
	a_manager.add_child(tactic)
	var rule := TacticRule.new()
	rule.name = "Assault"
	rule.action = TacticRule.Action.ASSAULT
	tactic.add_child(rule)
	var target := Marker3D.new()
	target.name = "Target"
	rule.add_child(target)
	target.position = _world(a_px)
	rule.point_path = NodePath("Target")


## Set every piece's height to the draft terrain's surface under it.
func _seat_on_terrain(a_root: Node) -> void:
	var half := Vector2(_terrain.map_width() - 1, _terrain.map_depth() - 1) * 0.5
	for node: Node in a_root.get_children():
		var piece := node as Entity
		if piece == null:
			continue
		var at := Vector2(
			clampf(piece.position.x + half.x, 0.0, half.x * 2.0),
			clampf(piece.position.z + half.y, 0.0, half.y * 2.0)
		)
		var c0 := Vector2i(floori(at.x), floori(at.y))
		var c1 := Vector2i(mini(c0.x + 1, int(half.x * 2.0)), mini(c0.y + 1, int(half.y * 2.0)))
		var f: Vector2 = at - Vector2(c0)
		var top: float = lerpf(
			_terrain.corner_height(c0), _terrain.corner_height(Vector2i(c1.x, c0.y)), f.x
		)
		var bottom: float = lerpf(
			_terrain.corner_height(Vector2i(c0.x, c1.y)), _terrain.corner_height(c1), f.x
		)
		piece.position.y = lerpf(top, bottom, f.y)


func _save(a_root: Node) -> void:
	_own(a_root, a_root)
	var packed := PackedScene.new()
	if packed.pack(a_root) != OK or ResourceSaver.save(packed, OUT_SCENE) != OK:
		push_error("draft layout: could not write %s" % OUT_SCENE)
		get_tree().quit(1)
		return
	print(
		(
			"draft layout: wrote %s with %d pieces"
			% [OUT_SCENE, _counts.values().reduce(func(a, b): return a + b, 0)]
		)
	)


## Own every node the builder added by the root so the pack keeps it; an instanced piece's own
## nodes stay its scene's.
func _own(a_node: Node, a_root: Node) -> void:
	for child: Node in a_node.get_children():
		if child.owner == null:
			child.owner = a_root
		if child.scene_file_path.is_empty():
			_own(child, a_root)
