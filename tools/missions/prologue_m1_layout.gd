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
const POWER_CELL: String = "res://scenes/entities/tokens/nt/nt_powerCell.tscn"
const BATTERY_RACK: String = "res://scenes/entities/structures/nt/nt_batteryRack.tscn"

## Commander ids, in slot order.
const PLAYER: int = 1
const ALLY: int = 2
const ENEMY: int = 3

## The bot brain jobs a scripted commander keeps: what it perceives (fields, sight of the map,
## the trend of its army's value), never anything that orders a unit.
const PERCEPTION_JOBS: Array[StringName] = [&"fields", &"scout_sight", &"momentum"]

## Wave labels: what each wave's ScenarioTactic watches.
const ALLY_WAVE: StringName = &"prologue_m1_ally_wave"
const ENEMY_WAVE: StringName = &"prologue_m1_enemy_wave"
## First wave a few seconds in, so the lane is already a fight when the player looks; then
## every 45 s (ConditionTimer COUNTDOWN resolves this once per cycle).
const WAVE_SECONDS: String = "10 + min(fires, 1) * 35"
## Irregulars garrisoned in each starting Safehouse.
const SAFEHOUSE_GARRISON: int = 3
## The player's Irregulars held in each prison Compound, freed when it falls.
const PRISONERS: int = 3
## Recruits holding the skirmish clearing.
const OUTPOST_RECRUITS: int = 3

## Positions are (along, across) in MissionLane's frame, whose origin is the main corridor's
## centre: it runs along ±40 and is ±9 across. The other regions are the terrain tool's REGIONS
## (tools/missions/prologue_m1_terrain.gd). A 4x4 building is grid-aligned, so it spans about
## ±2.8 along and across.
##
## The route: START (the player's Warlord) → WEST, north → NORTH (the prison Compounds) → EAST
## PASSAGE → SKIRMISH (the Recruits) → SOUTH PASSAGE → MAIN, beside the ally's Safehouses.
const PLAYER_START := Vector2(-60, -27)
## The two prison Compounds in NORTH, the enemy's: their prisons are switched off, so the player's
## Irregulars inside serve no sentence and wait to be freed.
const PRISON_COMPOUNDS: Array[Vector2] = [Vector2(-65, 53), Vector2(-53, 53)]
## Hazards around each prison Compound, as GRID offsets (world x, z) from its centre, so they sit
## against its 4x4 footprint whatever its rotation in the lane frame: the blasts are small
## (racks 2.5, cells 1), and only reach the Compound from beside it. Racks are 1x1 structures, so
## their offsets are cell centres.
const RACK_OFFSETS: Array[Vector2] = [Vector2(2.5, -0.5), Vector2(-2.5, 0.5)]
const CELL_OFFSETS: Array[Vector2] = [Vector2(2.6, 1.4), Vector2(-2.6, -1.4), Vector2(0.5, 2.6)]
## The Recruits' clearing in SKIRMISH, which they defend.
const OUTPOST := Vector2(-22, 48)

## THE RESCUE, in the WEST corridor (its centre line at along -61, ±11 wide). When the
## player walks north into AMBUSH_TRIGGER, the ally's RESCUERS appear ahead of them and the enemy's
## AMBUSHERS further north, and the two attack each other; a reveal shows the player the fight,
## since the ally does not share its vision. The trigger's south edge (centre - radius) is where
## the player arrives: AMBUSH_TRIGGER's is about 14 from where the fight settles, just past the
## Warlord's reach of 12, so it gets a shot or two off at most. Once the ambushers are dead the
## rescuers push north into STRIKE_TRIGGER, which ends the fight's reveal, sends STRIKERS at them,
## and reveals where the Clippers hit. Positions are first guesses, not tuned.
const AMBUSH_TRIGGER := Vector2(-61, 14)
const AMBUSH_TRIGGER_RADIUS: float = 10.0
const RESCUERS: int = 9
const RESCUERS_AT := Vector2(-61, 9)
const AMBUSHERS: int = 5
const AMBUSHERS_AT := Vector2(-61, 26)
const FIGHT_REVEAL_AT := Vector2(-61, 17)
const FIGHT_REVEAL_RADIUS: float = 12.0
const FIGHT_REVEAL: StringName = &"prologue_m1_fight_reveal"
const STRIKE_TRIGGER := Vector2(-61, 34)
const STRIKE_TRIGGER_RADIUS: float = 6.0
const STRIKERS: int = 2
const STRIKERS_AT := Vector2(-50, 58)
const STRIKE_REVEAL_RADIUS: float = 10.0
const STRIKE_REVEAL: StringName = &"prologue_m1_strike_reveal"
const RESCUE_GROUP: StringName = &"prologue_m1_rescuers"
const AMBUSH_GROUP: StringName = &"prologue_m1_ambushers"
const STRIKE_GROUP: StringName = &"prologue_m1_strikers"
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
	for at: Vector2 in PRISON_COMPOUNDS:
		_prison(root, at)

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
	_outpost(manager)
	_rescue(manager)

	_save(root)
	get_tree().quit(0)


## A player slot. The bots are SCRIPTED ONLY: everything the ally and enemy do is the mission's
## scripting, so every brain job that ACTS is switched off (PlayerSlot.disabled_bot_jobs) and only
## PERCEPTION_JOBS run — a tactic steers through its bot's senses. PASSIVE alone is not that: a
## passive brain still masses and defends its base, which sent the outpost Recruits after the
## freed prisoners beside the enemy's Compounds (found 2026-10-18). Derived from BotBrain.JOB_NAMES
## so a job added later starts off here too.
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


## An enemy Compound in NORTH holding PRISONERS of the player's Irregulars, its prison switched off
## (OccupantDominionGenerator.is_disabled, on its DominionGenerator node — an override inside the
## instance, so the instance is made editable), with power cells and battery racks against it.
## Destroying it frees the prisoners back to the player (Garrison: a dead host's captives return
## to their own commander). The Compound is snapped to whole cells first, so the hazard offsets
## land on the cells beside its footprint.
func _prison(a_root: Node, a_at: Vector2) -> void:
	var compound: Node3D = _place(a_root, COMPOUND, ENEMY, a_at, "PrisonCompound")
	compound.position = Vector3(roundf(compound.position.x), 0.0, roundf(compound.position.z))
	a_root.set_editable_instance(compound, true)
	(compound.get_node("DominionGenerator") as OccupantDominionGenerator).is_disabled = true
	var prisoners := EventSpawnEntities.new()
	prisoners.name = "Prisoners"
	prisoners.commander_id = PLAYER
	prisoners.entity_scenes = [load(IRREGULAR) as PackedScene]
	prisoners.count_expression = str(PRISONERS)
	prisoners.garrison_host = compound as Actor
	compound.add_child(prisoners)
	for offset: Vector2 in RACK_OFFSETS:
		_place_at(a_root, BATTERY_RACK, compound.position + Vector3(offset.x, 0.0, offset.y))
	for offset: Vector2 in CELL_OFFSETS:
		_place_at(a_root, POWER_CELL, compound.position + Vector3(offset.x, 0.0, offset.y))


## A neutral piece at Map-local world position `a_world`.
func _place_at(a_root: Node, a_scene: String, a_world: Vector3) -> void:
	var piece: Node3D = _place(a_root, a_scene, 0, Vector2.ZERO)
	piece.position = a_world


## OUTPOST_RECRUITS of the enemy's Recruits holding the SKIRMISH clearing: spawned at the start (an
## unconditional trigger) and ordered to Defend it — the game's own Defend command, so they hold
## the ground and engage what comes into it.
func _outpost(a_manager: Node) -> void:
	var trigger := GlobalTrigger.new()
	trigger.name = "RecruitOutpost"
	a_manager.add_child(trigger)
	var spawn := EventSpawnEntities.new()
	spawn.name = "Spawn"
	spawn.commander_id = ENEMY
	spawn.entity_scenes = [load(RECRUIT) as PackedScene]
	spawn.count_expression = str(OUTPOST_RECRUITS)
	trigger.add_child(spawn)
	spawn.position = MissionLane.to_world(OUTPOST.x, OUTPOST.y)
	var orders := EventIssueCommand.new()
	orders.name = "Orders"
	spawn.add_child(orders)
	var defend := EventCommandPoint.new()
	defend.name = "Defend"
	defend.command_type = "defend"
	orders.add_child(defend)
	defend.position = Vector3.ZERO


## The rescue sequence (see AMBUSH_TRIGGER): two triggers and three tactics.
func _rescue(a_manager: Node) -> void:
	var ambush := GlobalTrigger.new()
	ambush.name = "RescueAmbush"
	ambush.conditions = [_units_in(PLAYER, "AmbushRegion")]
	a_manager.add_child(ambush)
	_region(ambush, "AmbushRegion", AMBUSH_TRIGGER, AMBUSH_TRIGGER_RADIUS)
	_spawn(ambush, "Rescuers", ALLY, IRREGULAR, RESCUERS, RESCUERS_AT, RESCUE_GROUP)
	_spawn(ambush, "Ambushers", ENEMY, RECRUIT, AMBUSHERS, AMBUSHERS_AT, AMBUSH_GROUP)
	_reveal(ambush, "RevealFight", FIGHT_REVEAL_AT, FIGHT_REVEAL_RADIUS, FIGHT_REVEAL)

	var strike := GlobalTrigger.new()
	strike.name = "RescueStrike"
	strike.conditions = [_units_in(ALLY, "StrikeRegion")]
	strike.prerequisites = [ambush]
	a_manager.add_child(strike)
	_region(strike, "StrikeRegion", STRIKE_TRIGGER, STRIKE_TRIGGER_RADIUS)
	var end_fight := EventEndReveal.new()
	end_fight.name = "EndFightReveal"
	end_fight.reveal_label = FIGHT_REVEAL
	strike.add_child(end_fight)
	_spawn(strike, "Strikers", ENEMY, CLIPPER, STRIKERS, STRIKERS_AT, STRIKE_GROUP)
	_reveal(strike, "RevealStrike", STRIKE_TRIGGER, STRIKE_REVEAL_RADIUS, STRIKE_REVEAL)

	# The rescuers fight the ambushers while any stand, then push north up the corridor.
	var still_fighting := ConditionGroupCount.new()
	still_fighting.group = AMBUSH_GROUP
	still_fighting.comparison = ConditionGroupCount.Comparison.AT_LEAST
	still_fighting.count = 1
	var rescuers: ScenarioTactic = _assault(a_manager, "RescuerTactic", RESCUE_GROUP, AMBUSHERS_AT)
	(rescuers.get_child(0) as TacticRule).condition = still_fighting
	_add_assault_rule(rescuers, "PushNorth", STRIKE_TRIGGER)
	_assault(a_manager, "AmbusherTactic", AMBUSH_GROUP, RESCUERS_AT)
	_assault(a_manager, "StrikerTactic", STRIKE_GROUP, STRIKE_TRIGGER)


## "Any of `a_commander`'s units inside the region `a_region` under the trigger".
func _units_in(a_commander: int, a_region: String) -> ConditionUnitsInRegion:
	var condition := ConditionUnitsInRegion.new()
	condition.commander_id = a_commander
	condition.check = ConditionUnitsInRegion.Check.ANY_INSIDE
	condition.region_shape_path = NodePath(a_region)
	return condition


## A round region under `a_trigger` at lane position `a_at`. Round, because the lane runs at 45°
## to the grid and a cylinder looks the same from any angle.
func _region(a_trigger: Node3D, a_name: String, a_at: Vector2, a_radius: float) -> void:
	var region := CollisionShape3D.new()
	region.name = a_name
	var cylinder := CylinderShape3D.new()
	cylinder.radius = a_radius
	cylinder.height = 4.0
	region.shape = cylinder
	a_trigger.add_child(region)
	region.position = MissionLane.to_world(a_at.x, a_at.y)


## `a_count` of `a_scene` for `a_commander` at lane position `a_at`, labelled `a_group`.
func _spawn(
	a_trigger: Node,
	a_name: String,
	a_commander: int,
	a_scene: String,
	a_count: int,
	a_at: Vector2,
	a_group: StringName
) -> void:
	var spawn := EventSpawnEntities.new()
	spawn.name = a_name
	spawn.commander_id = a_commander
	spawn.entity_scenes = [load(a_scene) as PackedScene]
	spawn.count_expression = str(a_count)
	spawn.spawn_groups = [a_group]
	a_trigger.add_child(spawn)
	spawn.position = MissionLane.to_world(a_at.x, a_at.y)


## A standing reveal for the player at lane position `a_at`, named `a_label` so it can be ended.
func _reveal(
	a_trigger: Node, a_name: String, a_at: Vector2, a_radius: float, a_label: StringName
) -> void:
	var reveal := EventRevealRegion.new()
	reveal.name = a_name
	reveal.clears_fog = true
	reveal.commander_id = PLAYER
	reveal.radius = a_radius
	reveal.reveal_label = a_label
	a_trigger.add_child(reveal)
	reveal.position = MissionLane.to_world(a_at.x, a_at.y)


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
func _assault(
	a_manager: Node, a_name: String, a_group: StringName, a_target: Vector2
) -> ScenarioTactic:
	var tactic := ScenarioTactic.new()
	tactic.name = a_name
	tactic.unit_group = a_group
	a_manager.add_child(tactic)
	_add_assault_rule(tactic, "Assault", a_target)
	return tactic


## Append a rule to `a_tactic` assaulting lane position `a_target`. Rules are tried in order, so a
## rule added after a conditional one is what the squad does once that condition stops holding.
func _add_assault_rule(a_tactic: ScenarioTactic, a_name: String, a_target: Vector2) -> void:
	var rule := TacticRule.new()
	rule.name = a_name
	rule.action = TacticRule.Action.ASSAULT
	a_tactic.add_child(rule)
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
