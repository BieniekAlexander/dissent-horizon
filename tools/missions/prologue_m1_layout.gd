extends Node

## Lays down prologue mission 1's scene ONCE, from the 2026-10-18 setup
## (gdd/campaigns/01-prologue/01-pervasive-mechanics.md §Setup), so the first iteration starts
## from something that plays. After that the SCENE is the primary and is edited in the editor:
## this refuses to overwrite it, and a change made here instead of there is a change lost. Run it
## again only to start over, after deleting the scene by hand.
##
##   godot --headless --path . res://tools/missions/prologue_m1_layout.tscn
##
## Run as a MAIN SCENE, not via --script, so the autoloads exist before the piece scripts
## compile (as tools/generate_test_scenarios.gd does). Pieces are instanced with edit state so
## the pack stores only what a placement changed (tests/test_DerivedGroupsStayOnPieces.gd).
##
## The terrain is not made here: tools/missions/prologue_m1_terrain.gd is its primary.

const OUT_SCENE: String = "res://scenes/scenarios/prologue/m1_pervasive_mechanics.tscn"
const TERRAIN: String = "res://resources/terrain/prologue_m1_terrain.tres"
const SURFACE: String = "res://resources/terrain/prologue_m1_terrain_surface.res"
const SURFACE_SHADER: String = "res://scripts/rendering/shaders/terrain_surface.gdshader"

const ANARCHICAL: String = "res://scenes/factions/anarchical.tscn"
const COLONIAL: String = "res://scenes/factions/colonial.tscn"
const WARLORD: String = "res://scenes/entities/units/an/an_bioMedium_dominionGen.tscn"
const IRREGULAR: String = "res://scenes/entities/units/an/an_bioLight_builder.tscn"
const RECRUIT: String = "res://scenes/entities/units/cl/cl_bioLight_antiLight.tscn"
const CLIPPER: String = "res://scenes/entities/units/cl/cl_aircraftLight_antiLight.tscn"
const WATCH_TOWER: String = "res://scenes/entities/structures/cl/cl_defense_antiLight.tscn"
const COMPOUND: String = "res://scenes/entities/structures/cl/cl_infrastructure.tscn"
const BUILDING_SQUARE: String = "res://scenes/entities/structures/nt/nt_building_square.tscn"

## Commander ids, in slot order.
const PLAYER: int = 1
const ALLY: int = 2
const ENEMY: int = 3

## Wave labels: what each wave's ScenarioTactic watches.
const ALLY_WAVE: StringName = &"prologue_m1_ally_wave"
const ENEMY_WAVE: StringName = &"prologue_m1_enemy_wave"
## First wave a few seconds in, so the lane is already a fight when the player looks; then
## every 45 s (ConditionTimer COUNTDOWN resolves this once per cycle).
const WAVE_SECONDS: String = "10 + min(fires, 1) * 35"
## Irregulars garrisoned in each starting Safehouse.
const SAFEHOUSE_GARRISON: int = 3

## Positions are (along, across) in lane coordinates (MissionLane): along runs west → east over
## about ±40; the flat corridor is ±9 across, between the hills. A 4x4 building is grid-aligned,
## so it spans about ±2.8 along and across the lane.
const PLAYER_START := Vector2(-19, 0)
const ALLY_SAFEHOUSES: Array[Vector2] = [Vector2(-30, 4.5), Vector2(-30, -4.5), Vector2(-36, 0)]
const ALLY_WAVE_SPAWN := Vector2(-25, 0)
const WATCH_TOWERS: Array[Vector2] = [Vector2(26, 5), Vector2(26, -5), Vector2(31, 0)]
const COMPOUNDS: Array[Vector2] = [Vector2(35, 4.5), Vector2(35, -4.5)]
const ENEMY_WAVE_SPAWN := Vector2(22, 0)
## Where each side's waves assault: the other side's statics.
const ALLY_WAVE_TARGET := Vector2(28, 0)
const ENEMY_WAVE_TARGET := Vector2(-30, 0)

var _counts: Dictionary = {}


func _ready() -> void:
	if ResourceLoader.exists(OUT_SCENE):
		push_error(
			(
				"prologue_m1_layout: %s exists and is now the primary; delete it by hand to start over"
				% OUT_SCENE
			)
		)
		get_tree().quit(1)
		return
	var root := Scenario.new()
	root.name = "PrologueMission1"
	root.win_condition = Scenario.WinCondition.MISSION
	root.debug_allowed = true
	root.player_slots = [
		_slot(false, ANARCHICAL, 1, true),
		_slot(true, ANARCHICAL, 1, false),
		_slot(true, COLONIAL, 2, true),
	]
	root.add_child(_map())

	_place(root, WARLORD, PLAYER, PLAYER_START, "Warlord")
	for at: Vector2 in ALLY_SAFEHOUSES:
		_safehouse(root, at)
	for at: Vector2 in WATCH_TOWERS:
		_place(root, WATCH_TOWER, ENEMY, at, "WatchTower")
	for at: Vector2 in COMPOUNDS:
		_place(root, COMPOUND, ENEMY, at, "Compound")

	var manager := ScenarioTriggerManager.new()
	manager.name = "ScenarioTriggerManager"
	root.add_child(manager)
	_wave(
		manager,
		"AllyWaves",
		ALLY,
		[IRREGULAR, IRREGULAR, IRREGULAR, WARLORD, WARLORD],
		ALLY_WAVE,
		ALLY_WAVE_SPAWN
	)
	_wave(
		manager,
		"EnemyWaves",
		ENEMY,
		[RECRUIT, RECRUIT, RECRUIT, CLIPPER, CLIPPER],
		ENEMY_WAVE,
		ENEMY_WAVE_SPAWN
	)
	_assault(manager, "AllyWaveTactic", ALLY_WAVE, ALLY_WAVE_TARGET)
	_assault(manager, "EnemyWaveTactic", ENEMY_WAVE, ENEMY_WAVE_TARGET)

	_save(root)
	get_tree().quit(0)


## A player slot. Bots are PASSIVE: everything the ally and enemy do is the mission's scripting.
func _slot(a_is_bot: bool, a_faction: String, a_team: int, a_shares_vision: bool) -> PlayerSlot:
	var slot := PlayerSlot.new()
	slot.is_bot = a_is_bot
	slot.faction = load(a_faction)
	slot.alliance = a_team
	slot.difficulty = PlayerSlot.Difficulty.PASSIVE
	slot.starting_energy = 0
	slot.starting_dominion = 0
	slot.shares_vision_with_allies = a_shares_vision
	return slot


## The Map, drawing the tool-made terrain through a TerrainSurface (the brushable path); its
## collision shape is derived from terrain_data at load, so the Shape node is left empty.
func _map() -> Map:
	var map := Map.new()
	map.name = "Map"
	map.terrain_data = load(TERRAIN) as TerrainData
	map.terrain_source_mesh = load(SURFACE) as Mesh
	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion"
	region.navigation_mesh = NavigationMesh.new()
	region.add_to_group("navigation_mesh_source_group", true)
	map.add_child(region)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = CollisionLayers.Mask.TERRAIN
	body.collision_mask = 0
	region.add_child(body)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	body.add_child(shape)
	var surface := TerrainSurface.new()
	surface.name = "TerrainSurface"
	var material := ShaderMaterial.new()
	material.shader = load(SURFACE_SHADER) as Shader
	surface.material = material
	body.add_child(surface)
	return map


## Instance `a_scene` for `a_commander` at lane position `a_at`, under `a_parent`.
func _place(
	a_parent: Node, a_scene: String, a_commander: int, a_at: Vector2, a_name: String = ""
) -> Node3D:
	var piece := (
		(load(a_scene) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	)
	piece.set("default_commander_id", a_commander)
	var base: String = a_name if not a_name.is_empty() else a_scene.get_file().get_basename()
	_counts[base] = int(_counts.get(base, 0)) + 1
	piece.name = "%s%d" % [base, _counts[base]]
	a_parent.add_child(piece, true)
	piece.position = MissionLane.to_world(a_at.x, a_at.y)
	return piece


## A neutral building that the ally owns as a Safehouse from the first frame, with Irregulars
## inside: two STARTING events parked under it, run in order (ScenarioTriggerManager.
## run_starting_events) — convert it, then fill it.
func _safehouse(a_root: Node, a_at: Vector2) -> void:
	var building: Node3D = _place(a_root, BUILDING_SQUARE, 0, a_at, "Safehouse")
	var convert := EventConvertBuilding.new()
	convert.name = "ConvertToSafehouse"
	convert.commander_id = ALLY
	building.add_child(convert)
	var garrison := EventSpawnEntities.new()
	garrison.name = "StartingGarrison"
	garrison.commander_id = ALLY
	garrison.entity_scenes = [load(IRREGULAR) as PackedScene]
	garrison.count_expression = str(SAFEHOUSE_GARRISON)
	garrison.garrison_host = building as Actor
	building.add_child(garrison)


## A repeating wave: every WAVE_SECONDS, `a_commander` spawns `a_scenes` at `a_spawn`, labelled
## `a_group` for its ScenarioTactic.
func _wave(
	a_manager: Node,
	a_name: String,
	a_commander: int,
	a_scenes: Array,
	a_group: StringName,
	a_spawn: Vector2
) -> void:
	var trigger := GlobalTrigger.new()
	trigger.name = a_name
	trigger.one_shot = false
	var timer := ConditionTimer.new()
	timer.mode = ConditionTimer.Mode.COUNTDOWN
	timer.seconds_expression = WAVE_SECONDS
	trigger.conditions = [timer]
	a_manager.add_child(trigger)
	var spawn := EventSpawnEntities.new()
	spawn.name = "Spawn"
	spawn.commander_id = a_commander
	var scenes: Array[PackedScene] = []
	for path: String in a_scenes:
		scenes.append(load(path) as PackedScene)
	spawn.entity_scenes = scenes
	spawn.count_expression = "1"
	spawn.spawn_groups = [a_group]
	trigger.add_child(spawn)
	spawn.position = MissionLane.to_world(a_spawn.x, a_spawn.y)


## Keep every unit labelled `a_group` assaulting `a_target`, re-engaging when it goes idle.
func _assault(a_manager: Node, a_name: String, a_group: StringName, a_target: Vector2) -> void:
	var tactic := ScenarioTactic.new()
	tactic.name = a_name
	tactic.unit_group = a_group
	a_manager.add_child(tactic)
	var rule := TacticRule.new()
	rule.name = "Assault"
	rule.action = TacticRule.Action.ASSAULT
	tactic.add_child(rule)
	var point := Marker3D.new()
	point.name = "Target"
	rule.add_child(point)
	point.position = MissionLane.to_world(a_target.x, a_target.y)
	rule.point_path = NodePath("Target")


func _save(a_root: Node) -> void:
	_own(a_root, a_root)
	var packed := PackedScene.new()
	if packed.pack(a_root) != OK:
		push_error("prologue_m1_layout: pack failed")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_SCENE.get_base_dir()))
	if ResourceSaver.save(packed, OUT_SCENE) != OK:
		push_error("prologue_m1_layout: save failed")
		get_tree().quit(1)
		return
	print("[prologue_m1_layout] wrote ", OUT_SCENE)


## Own every node by the root so the pack keeps it. An instanced piece's own nodes belong to its
## scene and stay so; only what this builder added under it (the starting events) is the root's.
func _own(a_node: Node, a_root: Node) -> void:
	for child: Node in a_node.get_children():
		if child.owner == null:
			child.owner = a_root
		if child.scene_file_path.is_empty() or child.owner == a_root:
			_own_added(child, a_root)


## Recurse into nodes the builder made, skipping into an instanced piece only for what it added.
func _own_added(a_node: Node, a_root: Node) -> void:
	for child: Node in a_node.get_children():
		if child.owner == null:
			child.owner = a_root
		if child.owner == a_root:
			_own_added(child, a_root)
