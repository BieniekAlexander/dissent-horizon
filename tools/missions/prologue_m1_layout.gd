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
const SAM_SITE: String = "res://scenes/entities/structures/cl/cl_defense_antiAircraft.tscn"
const CITADEL: String = "res://scenes/entities/structures/cl/cl_commandCenter.tscn"
const BARRACKS: String = "res://scenes/entities/structures/cl/cl_barracks.tscn"
const AIRFIELD: String = "res://scenes/entities/structures/cl/cl_airField.tscn"
const RAVEN: String = "res://scenes/entities/units/an/an_aircraftLight_transport.tscn"
const BUILDING_LONG: String = "res://scenes/entities/structures/nt/nt_building_long.tscn"
const BUILDING_SHACK: String = "res://scenes/entities/structures/nt/nt_building_shack.tscn"

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

## Positions are (along, across) in MissionLane's frame, whose origin lies near the west end of
## MAIN, the waves' corridor: MAIN runs along -10..70 and is ±9 across. The other regions are
## the terrain tool's REGIONS (tools/missions/prologue_m1_terrain.gd). A 4x4 building is
## grid-aligned, so it spans about ±2.8 along and across.
##
## The beats, in the order the player meets them (Alex, 2026-10-18):
## 1. THE RESCUE, in WEST: the player walks north into the ally's fight with an ambush.
## 2. THE PRISONS, in NORTH: the ally's squad leads the player to the prison Compounds and waits;
##    the player blows them up with their hazards and gets their Irregulars back.
## 3. THE OUTPOST, in SKIRMISH: a short walk east, the player's first fight, against Recruits
##    holding their ground. The ally's squad stays out of it.
## 4. THE GARRISON, on GARRISON_ROAD: the squad waits by a building; when the player takes cover
##    in it, the squad walks on east and two Clippers fall on it, beyond the building's reach,
##    then turn on the building, where the Warlord shoots them down.
## 5. THE FORK: walking on east reveals the whole fork — the Watch Towers' field east, and the
##    narrow passage south to MAIN, where the waves fight.
const PLAYER_START := Vector2(-60, -27)
## The two prison Compounds in NORTH, the enemy's: their prisons are switched off, so the player's
## Irregulars inside serve no sentence and wait to be freed.
const PRISON_COMPOUNDS: Array[Vector2] = [Vector2(-65, 53), Vector2(-53, 53)]
## Hazards around each prison Compound, as GRID offsets (world x, z) from its centre, so they sit
## against its 4x4 footprint (cell centres ±1.5, edges ±2) whatever its rotation in the lane frame.
## Laid out as ONE CHAIN (Alex, 2026-10-18): shooting any of them sets off all of them. The two
## racks stand side by side on one face, 2 apart, inside each other's 2.5 blast and against the
## Compound; every cell stands within about 1 of a rack or of a cell that is, inside a cell's 1
## blast. Racks are 1x1 structures, so their offsets are cell centres.
const RACK_OFFSETS: Array[Vector2] = [Vector2(2.5, -0.5), Vector2(2.5, 1.5)]
const CELL_OFFSETS: Array[Vector2] = [Vector2(2.5, -1.4), Vector2(2.5, 2.4), Vector2(1.8, 2.3)]
## The south lane's prisons have theirs on the WEST, the side the player comes from (Alex,
## 2026-10-18): the lane runs at 45° to the grid, so a grid-aligned Compound shows a corner to the
## west — grid (-2, +2) — and the chain wraps it. The racks stand one on each face beside that
## corner, 1.4 apart; a cell sits in the corner and one against each face past each rack, each
## 0.9 from a rack — the face cells' blasts are what finish the Compound at once: with them out
## beyond the racks instead, the blasts left it at 66 of 750 and it burned for 8 s.
const WEST_RACK_OFFSETS: Array[Vector2] = [Vector2(-2.5, 1.5), Vector2(-1.5, 2.5)]
const WEST_CELL_OFFSETS: Array[Vector2] = [
	Vector2(-2.4, 2.4), Vector2(-2.4, 0.6), Vector2(-0.6, 2.4)
]
## The Recruits' clearing in SKIRMISH, which they defend.
const OUTPOST := Vector2(-22, 48)
const OUTPOST_GROUP: StringName = &"prologue_m1_outpost"

## THE RESCUE, in the WEST corridor (its centre line at along -61, ±11 wide). When the player
## walks north into AMBUSH_TRIGGER, the ally's RESCUERS appear ahead of them and the enemy's
## AMBUSHERS further north, and the two attack each other; a reveal shows the player the fight,
## since the ally does not share its vision, and goes dark when the ambushers are dead. The
## trigger's south edge (centre - radius) is where the player arrives, which sets how far it
## stands from the fight (the Warlord's reach is 12). Positions are first guesses, not tuned.
const AMBUSH_TRIGGER := Vector2(-61, 4)
const AMBUSH_TRIGGER_RADIUS: float = 10.0
const RESCUERS: int = 9
const RESCUERS_AT := Vector2(-61, 9)
const AMBUSHERS: int = 5
const AMBUSHERS_AT := Vector2(-61, 26)
const FIGHT_REVEAL_AT := Vector2(-61, 17)
const FIGHT_REVEAL_RADIUS: float = 12.0
const FIGHT_REVEAL: StringName = &"prologue_m1_fight_reveal"
const RESCUE_GROUP: StringName = &"prologue_m1_rescuers"
const AMBUSH_GROUP: StringName = &"prologue_m1_ambushers"

## Where the ally's squad waits for the player at the prisons: south of the Compounds, clear of
## their hazards' blasts (the racks throw 2.5).
const PRISON_HOLD := Vector2(-59, 41)
## The building the player takes cover in, neutral until they do, and where the squad waits for
## them: past it, on the side the squad will walk on to.
const GARRISON_HOUSE := Vector2(-2, 50)
const GARRISON_HOUSE_NAME: String = "GarrisonHouse"
const GARRISON_HOLD := Vector2(5, 47)
## Where the squad walks on to once the player is inside, and how far past the squad the Clippers
## appear, measured away from the building. A garrisoned Warlord reaches 12 from the building's
## hull, a Clipper 8 from its target: the squad stands 26 out, and the Clippers fight it from
## beyond, so the Warlord cannot shoot them down before they have killed the squad (Alex,
## 2026-10-18). Two Clippers, CLIPPER_SPACING apart across the line.
const ADVANCE_AT := Vector2(24, 50)
## How close the first of the squad must come to ADVANCE_AT for the Clippers to appear.
const ADVANCE_RADIUS: float = 4.0
const CLIPPERS_PAST_SQUAD: float = 12.0
const CLIPPER_SPACING: float = 8.0
const CLIPPER_GROUP: StringName = &"prologue_m1_clippers"
const ADVANCE_REVEAL_RADIUS: float = 14.0
const ADVANCE_REVEAL: StringName = &"prologue_m1_advance_reveal"
## Walking on east from the building reveals the whole fork.
const FORK_TRIGGER := Vector2(14, 50)
const FORK_TRIGGER_RADIUS: float = 4.0
const FORK_REVEAL_AT := Vector2(25, 47)
const FORK_REVEAL_RADIUS: float = 22.0
## The autosave on the way down the narrow passage from the fork to the main corridor.
const AUTOSAVE_AT := Vector2(22.5, 20)
const AUTOSAVE_RADIUS: float = 3.0
## The Watch Towers' field east of the fork, and the two Compounds behind them that power them.
const FIELD_TOWERS: Array[Vector2] = [
	Vector2(46, 41), Vector2(46, 55), Vector2(51, 45), Vector2(51, 51)
]
const FIELD_COMPOUNDS: Array[Vector2] = [Vector2(60, 44.5), Vector2(60, 51.5)]

## MAIN, where the waves fight: the ally's Safehouses at the west end, the enemy's statics at the
## east end, and the passage from the fork coming in between them, on the ally's side.
const ALLY_SAFEHOUSES: Array[Vector2] = [Vector2(0, 4.5), Vector2(0, -4.5), Vector2(-6, 0)]
const ALLY_WAVE_SPAWN := Vector2(5, 0)
const WATCH_TOWERS: Array[Vector2] = [Vector2(56, 5), Vector2(56, -5), Vector2(61, 0)]
const COMPOUNDS: Array[Vector2] = [Vector2(65, 4.5), Vector2(65, -4.5)]
const ENEMY_WAVE_SPAWN := Vector2(52, 0)
## Where each side's waves assault: the other side's statics.
const ALLY_WAVE_TARGET := Vector2(58, 0)
const ENEMY_WAVE_TARGET := Vector2(0, 0)

## THE SOUTH LANE (Alex, 2026-10-18), along -10..90 and -40..-24 across, joined to MAIN's west
## end by a link. West to east:
## - two more prison Compounds, with the same chain of hazards, each holding a Warlord and 3
##   Irregulars of the player's — 4 occupants, so their garrisons are raised from 3 to 4;
## - a guard post: 4 Recruits and 2 Clippers holding their ground (Defend);
## - three neutral buildings together, and beyond them 12 Recruits in three groups of 4, who
##   attack-move down the lane at the player the moment a player's unit enters the buildings'
##   region;
## - at the lane's end, 3 SAM sites with 2 Compounds among them (2 of the player's Irregulars
##   in each, no hazards — the player brings them down by force). When all three SAM sites are
##   down, 3 Ravens of the player's fly in from off the map and land beside the player.
const SOUTH_PRISONS: Array[Vector2] = [Vector2(8, -32), Vector2(20, -32)]
const SOUTH_PRISON_CAPACITY: int = 4
const LANE_GUARD := Vector2(36, -32)
const LANE_GUARD_GROUP: StringName = &"prologue_m1_lane_guard"
const LANE_BUILDINGS: Array = [
	[BUILDING_SQUARE, Vector2(49, -28)],
	[BUILDING_LONG, Vector2(49, -36)],
	[BUILDING_SHACK, Vector2(55, -32)],
]
const BUILDINGS_TRIGGER := Vector2(51, -32)
const BUILDINGS_TRIGGER_RADIUS: float = 9.0
const CHARGERS_AT: Array[Vector2] = [Vector2(64, -27.5), Vector2(68, -32), Vector2(64, -36.5)]
const CHARGERS_PER_GROUP: int = 4
const CHARGE_GROUP: StringName = &"prologue_m1_chargers"
## Where the charge attack-moves to: down the lane, to its west end.
const CHARGE_TARGET := Vector2(-4, -32)
const SAM_SITES: Array[Vector2] = [Vector2(76, -32), Vector2(85, -26.5), Vector2(86, -37.5)]
const END_COMPOUNDS: Array[Vector2] = [Vector2(80, -28.5), Vector2(80, -35.5)]
const END_COMPOUND_PRISONERS: int = 2
## THE PUSH ON THE BASE (Alex, 2026-10-18): the player loads its army into the Ravens (8 BIO
## each), finds a gap in the enemy's air defences, and destroys enough of the base's Compounds to
## make its defences defective.
##
## Three small enemy OUTPOSTS on the mesa east of the west corridor — the hill country's flat
## top, which no ground unit can reach (prologue_m1_terrain.gd), so only by air. Each has two SAM
## sites and a group of neutral buildings, and one each of: a Barracks, two empty Compounds, a
## Sky Port. Pieces are placed at offsets from the outpost's centre.
const OUTPOSTS: Array = [
	[Vector2(-38, 24), "barracks"],
	[Vector2(-24, 6), "compounds"],
	[Vector2(-36, -16), "airfield"],
]
const OUTPOST_SAMS: Array[Vector2] = [Vector2(6, 5), Vector2(-6, -5)]
const OUTPOST_COMPOUNDS: Array[Vector2] = [Vector2(0, 3.5), Vector2(0, -3.5)]
## A group of neutral buildings around its centre: [scene, offset].
const BUILDING_GROUP: Array = [
	[BUILDING_SQUARE, Vector2(0, 3)],
	[BUILDING_LONG, Vector2(0, -3)],
	[BUILDING_SHACK, Vector2(5, 0)],
]
const OUTPOST_BUILDINGS := Vector2(-8, 3)
## Two more SAM sites at the enemy's end of the main corridor.
const MAIN_LANE_SAMS: Array[Vector2] = [Vector2(60, 7), Vector2(60, -7)]

## The enemy's MAIN BASE, east of the old map edge (BASE, along 100..140, across -40..56), which
## the ends of all three west–east corridors open onto. The two southern corridors are covered by
## SAM sites (the south lane's, the main corridor's); the top one, BEYOND, has none, and every
## SAM site in the base stands in its southern two thirds (across 12 or less, reach 20), so its
## northern third is a gap the Ravens can come in by.
const CITADEL_AT := Vector2(120, 8)
const BASE_BARRACKS: Array[Vector2] = [Vector2(108, -22), Vector2(132, -20), Vector2(110, 34)]
const BASE_AIRFIELDS: Array[Vector2] = [Vector2(130, 30), Vector2(128, -34)]
const BASE_BUILDING_GROUPS: Array[Vector2] = [Vector2(104, 12), Vector2(134, 6), Vector2(116, -30)]
const BASE_SAMS: Array[Vector2] = [
	Vector2(104, -37),
	Vector2(138, -28),
	Vector2(102, -8),
	Vector2(110, 2),
	Vector2(128, 0),
	Vector2(120, -22),
]
## The base's Compounds, empty, laid out by the builder on a grid over the base wherever nothing
## else stands (_base_compound_spots). HOW MANY is the infrastructure ledger's (Alex,
## 2026-10-18): one enemy pool, sized so that, with the four prisons and the two lane-end
## Compounds already destroyed — the route the player takes to get here — the base goes
## defective once 4 of its 12 Compounds are lost (33%; Alex asked for about 30%, 2026-10-19,
## and 11 would be 3 of 11). See _report_infrastructure. The shipped scene's 12 were thinned by
## hand from the first build's 24, evenly across the rows, so a rebuild places them differently.
const BASE_COMPOUNDS: int = 12
const BASE_REGION := Rect2(100, -40, 40, 96)
const BASE_GRID_STEP: float = 6.0
## Clearance a Compound keeps from every other piece the base places, centre to centre.
const BASE_CLEARANCE: float = 6.5

const RAVENS: int = 3
## Where the Ravens come from — past the lane's end, off the map (the play area ends about 97
## along) — and where the search for the player's unit they land beside starts: the SAM field,
## where the player is when the last site falls.
const RAVENS_FROM := Vector2(106, -32)
const RAVENS_LAND_NEAR := Vector2(80, -32)
## How far from that unit, back toward the SAM field, they set down.
const RAVENS_STANDOFF: float = 5.0
const RAVEN_GROUP: StringName = &"prologue_m1_ravens"

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
		_prison(root, at, [[IRREGULAR, PRISONERS]])
	for at: Vector2 in FIELD_TOWERS:
		_place(root, WATCH_TOWER, ENEMY, at, "FieldTower")
	for at: Vector2 in FIELD_COMPOUNDS:
		_place(root, COMPOUND, ENEMY, at, "FieldCompound")
	for at: Vector2 in SOUTH_PRISONS:
		var held: Node3D = _prison(
			root, at, [[WARLORD, 1], [IRREGULAR, PRISONERS]], WEST_RACK_OFFSETS, WEST_CELL_OFFSETS
		)
		(held.get_node("Garrison") as Garrison).capacity = SOUTH_PRISON_CAPACITY
	for entry: Array in LANE_BUILDINGS:
		_place(root, entry[0], 0, entry[1], "LaneBuilding")
	for at: Vector2 in SAM_SITES:
		_place(root, SAM_SITE, ENEMY, at, "SamSite")
	for at: Vector2 in MAIN_LANE_SAMS:
		_place(root, SAM_SITE, ENEMY, at, "LaneSam")
	for outpost: Array in OUTPOSTS:
		_outpost_on_mesa(root, outpost[0], outpost[1])
	_main_base(root)
	for at: Vector2 in END_COMPOUNDS:
		_hold(root, at, "EndCompound", PLAYER, [[IRREGULAR, END_COMPOUND_PRISONERS]])
	var house: Node3D = _place(root, BUILDING_SQUARE, 0, GARRISON_HOUSE, GARRISON_HOUSE_NAME)
	house.name = GARRISON_HOUSE_NAME

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
	_beats(manager, house)
	_south_lane(manager)

	_report_infrastructure(root)
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


## An enemy prison Compound holding `a_contents` of the player's units (see _hold), with power
## cells and battery racks against it as one chain (RACK_OFFSETS). Destroying it frees the
## prisoners back to the player (Garrison: a dead host's captives return to their own
## commander). The Compound is snapped to whole cells first, so the hazard offsets land on the
## cells beside its footprint.
func _prison(
	a_root: Node,
	a_at: Vector2,
	a_contents: Array,
	a_racks: Array[Vector2] = RACK_OFFSETS,
	a_cells: Array[Vector2] = CELL_OFFSETS
) -> Node3D:
	var compound: Node3D = _hold(a_root, a_at, "PrisonCompound", PLAYER, a_contents)
	for offset: Vector2 in a_racks:
		_place_at(a_root, BATTERY_RACK, compound.position + Vector3(offset.x, 0.0, offset.y))
	for offset: Vector2 in a_cells:
		_place_at(a_root, POWER_CELL, compound.position + Vector3(offset.x, 0.0, offset.y))
	return compound


## An enemy Compound at `a_at` named `a_name`, holding `a_contents` — [scene, count] pairs —
## owned by `a_inside`, its prison switched off (OccupantDominionGenerator.is_disabled, on its
## DominionGenerator node — an override inside the instance, so the instance is made editable),
## so nobody inside serves a sentence. The occupants are STARTING events parked under it.
func _hold(a_root: Node, a_at: Vector2, a_name: String, a_inside: int, a_contents: Array) -> Node3D:
	var compound: Node3D = _place(a_root, COMPOUND, ENEMY, a_at, a_name)
	compound.position = Vector3(roundf(compound.position.x), 0.0, roundf(compound.position.z))
	a_root.set_editable_instance(compound, true)
	(compound.get_node("DominionGenerator") as OccupantDominionGenerator).is_disabled = true
	for entry: Array in a_contents:
		var inside := EventSpawnEntities.new()
		inside.name = "Inside%s" % (entry[0] as String).get_file().get_basename()
		inside.commander_id = a_inside
		inside.entity_scenes = [load(entry[0]) as PackedScene]
		inside.count_expression = str(entry[1])
		inside.garrison_host = compound as Actor
		compound.add_child(inside)
	return compound


## One of the mesa OUTPOSTS (see OUTPOSTS): two SAM sites, a group of neutral buildings, and its
## `a_kind` — a Barracks, two empty Compounds, or a Sky Port — around `a_at`.
func _outpost_on_mesa(a_root: Node, a_at: Vector2, a_kind: String) -> void:
	for offset: Vector2 in OUTPOST_SAMS:
		_place(a_root, SAM_SITE, ENEMY, a_at + offset, "OutpostSam")
	_building_group(a_root, a_at + OUTPOST_BUILDINGS, "OutpostBuilding")
	match a_kind:
		"barracks":
			_place(a_root, BARRACKS, ENEMY, a_at, "OutpostBarracks")
		"compounds":
			for offset: Vector2 in OUTPOST_COMPOUNDS:
				_place(a_root, COMPOUND, ENEMY, a_at + offset, "OutpostCompound")
		"airfield":
			_place(a_root, AIRFIELD, ENEMY, a_at, "OutpostAirfield")


## A group of three neutral buildings around `a_at` (BUILDING_GROUP).
func _building_group(a_root: Node, a_at: Vector2, a_name: String) -> void:
	for entry: Array in BUILDING_GROUP:
		_place(a_root, entry[0], 0, a_at + (entry[1] as Vector2), a_name)


## The enemy's main base (see CITADEL_AT).
func _main_base(a_root: Node) -> void:
	var taken: Array[Vector2] = []
	_place(a_root, CITADEL, ENEMY, CITADEL_AT, "Citadel")
	taken.append(CITADEL_AT)
	for at: Vector2 in BASE_BARRACKS:
		_place(a_root, BARRACKS, ENEMY, at, "BaseBarracks")
		taken.append(at)
	for at: Vector2 in BASE_AIRFIELDS:
		_place(a_root, AIRFIELD, ENEMY, at, "BaseAirfield")
		taken.append(at)
	for at: Vector2 in BASE_BUILDING_GROUPS:
		_building_group(a_root, at, "BaseBuilding")
		for entry: Array in BUILDING_GROUP:
			taken.append(at + (entry[1] as Vector2))
	for at: Vector2 in BASE_SAMS:
		_place(a_root, SAM_SITE, ENEMY, at, "BaseSam")
		taken.append(at)
	var spots: Array[Vector2] = _base_compound_spots(taken)
	if spots.size() < BASE_COMPOUNDS:
		push_error(
			"prologue_m1_layout: room for %d base Compounds of %d" % [spots.size(), BASE_COMPOUNDS]
		)
	for i: int in mini(BASE_COMPOUNDS, spots.size()):
		_place(a_root, COMPOUND, ENEMY, spots[i], "BaseCompound")


## Where the base's Compounds go: a grid over BASE_REGION, inset by half a step, keeping
## BASE_CLEARANCE from `a_taken` and from each other, spread evenly by taking every other row
## first. The citadel's footprint is twice a Compound's, so it keeps 2.5 more.
func _base_compound_spots(a_taken: Array[Vector2]) -> Array[Vector2]:
	var spots: Array[Vector2] = []
	var rows: Array[float] = []
	var y: float = BASE_REGION.position.y + BASE_GRID_STEP * 0.5
	while y < BASE_REGION.end.y - BASE_GRID_STEP * 0.4:
		rows.append(y)
		y += BASE_GRID_STEP
	for parity: int in 2:
		for r: int in rows.size():
			if r % 2 != parity:
				continue
			var x: float = BASE_REGION.position.x + BASE_GRID_STEP * 0.5
			while x < BASE_REGION.end.x - BASE_GRID_STEP * 0.4:
				var at := Vector2(x, rows[r])
				if _clear_of(at, a_taken, spots):
					spots.append(at)
				x += BASE_GRID_STEP
	return spots


func _clear_of(a_at: Vector2, a_taken: Array[Vector2], a_spots: Array[Vector2]) -> bool:
	for other: Vector2 in a_taken:
		var clearance: float = BASE_CLEARANCE + (2.5 if other == CITADEL_AT else 0.0)
		if a_at.distance_to(other) < clearance:
			return false
	for other: Vector2 in a_spots:
		if a_at.distance_to(other) < BASE_GRID_STEP - 0.1:
			return false
	return true


## Print the enemy's infrastructure ledger as laid down: what it provides and requires at the
## start, and how many base Compounds it can lose once the prisons and the lane-end Compounds are
## gone (the route to the base) before it goes defective.
func _report_infrastructure(a_root: Node) -> void:
	# Every commander starts with some capacity of its own (Commander.BASE_INFRASTRUCTURE).
	var provided: int = Commander.BASE_INFRASTRUCTURE
	var required: int = 0
	var prisons: int = 0
	for node: Node in a_root.get_children():
		var piece := node as Actor
		if piece == null or int(piece.get("default_commander_id")) != ENEMY:
			continue
		var value: int = int(piece.get("infrastructure"))
		if value > 0:
			provided += value
		else:
			required -= value
		if piece.name.begins_with("PrisonCompound") or piece.name.begins_with("EndCompound"):
			prisons += value
	var on_arrival: int = provided - prisons
	var spare: int = on_arrival - required
	print(
		(
			(
				"[prologue_m1_layout] enemy infrastructure: provides %d, requires %d at the start; "
				% [provided, required]
			)
			+ (
				"on reaching the base (prisons and lane-end Compounds gone) %d spare, so the base "
				% spare
			)
			+ (
				"goes defective after losing %d of %d Compounds"
				% [floori(spare / 100.0) + 1, BASE_COMPOUNDS]
			)
		)
	)


## A neutral piece at Map-local world position `a_world`.
func _place_at(a_root: Node, a_scene: String, a_world: Vector3) -> void:
	var piece: Node3D = _place(a_root, a_scene, 0, Vector2.ZERO)
	piece.position = a_world


## OUTPOST_RECRUITS of the enemy's Recruits holding the SKIRMISH clearing (see _defenders).
func _outpost(a_manager: Node) -> void:
	_defenders(a_manager, "RecruitOutpost", OUTPOST, [[RECRUIT, OUTPOST_RECRUITS]], OUTPOST_GROUP)


## The enemy's `a_contents` — [scene, count] pairs — holding the ground at `a_at`: spawned at the
## start (an unconditional trigger), labelled `a_group`, and ordered to Defend it — the game's
## own Defend command, so they hold the ground and engage what comes into it.
func _defenders(
	a_manager: Node, a_name: String, a_at: Vector2, a_contents: Array, a_group: StringName
) -> void:
	var trigger := GlobalTrigger.new()
	trigger.name = a_name
	a_manager.add_child(trigger)
	for entry: Array in a_contents:
		var spawn := EventSpawnEntities.new()
		spawn.name = "Spawn%s" % (entry[0] as String).get_file().get_basename()
		spawn.commander_id = ENEMY
		spawn.entity_scenes = [load(entry[0]) as PackedScene]
		spawn.count_expression = str(entry[1])
		spawn.spawn_groups = [a_group]
		trigger.add_child(spawn)
		spawn.position = MissionLane.to_world(a_at.x, a_at.y)
		var orders := EventIssueCommand.new()
		orders.name = "Orders"
		spawn.add_child(orders)
		var defend := EventCommandPoint.new()
		defend.name = "Defend"
		defend.command_type = "defend"
		orders.add_child(defend)
		defend.position = Vector3.ZERO


## The south lane's encounters (see SOUTH_PRISONS): the guard post, the charge and its trigger,
## and the Ravens handed to the player when the SAM sites fall.
func _south_lane(a_manager: Node) -> void:
	_defenders(
		a_manager,
		"LaneGuard",
		LANE_GUARD,
		[[RECRUIT, 4], [CLIPPER, 2]],
		LANE_GUARD_GROUP,
	)

	var stationed := GlobalTrigger.new()
	stationed.name = "ChargersStationed"
	a_manager.add_child(stationed)
	for i: int in CHARGERS_AT.size():
		_spawn(
			stationed,
			"Chargers%d" % (i + 1),
			ENEMY,
			RECRUIT,
			CHARGERS_PER_GROUP,
			CHARGERS_AT[i],
			CHARGE_GROUP
		)
	var charge := GlobalTrigger.new()
	charge.name = "RecruitsCharge"
	charge.conditions = [_units_in(PLAYER, "BuildingsRegion")]
	a_manager.add_child(charge)
	_region(charge, "BuildingsRegion", BUILDINGS_TRIGGER, BUILDINGS_TRIGGER_RADIUS)
	# Until the charge, no rule matches and the Recruits stand where they were put.
	var chargers := ScenarioTactic.new()
	chargers.name = "ChargeTactic"
	chargers.unit_group = CHARGE_GROUP
	a_manager.add_child(chargers)
	_add_rule(chargers, "Charge", TacticRule.Action.ASSAULT, CHARGE_TARGET, _fired(charge.name))

	# When the SAM sites are down, three Ravens of the player's fly in from beyond the lane's end
	# and land beside the player's nearest unit (Alex, 2026-10-18).
	var arrive := GlobalTrigger.new()
	arrive.name = "RavensArrive"
	var sams_down: Array[Condition] = []
	for i: int in SAM_SITES.size():
		sams_down.append(_killed("SamSite%d" % (i + 1)))
	arrive.conditions = sams_down
	a_manager.add_child(arrive)
	var ravens := EventSpawnEntities.new()
	ravens.name = "Ravens"
	ravens.commander_id = PLAYER
	ravens.entity_scenes = [load(RAVEN) as PackedScene]
	ravens.count_expression = str(RAVENS)
	ravens.spawn_groups = [RAVEN_GROUP]
	arrive.add_child(ravens)
	ravens.position = MissionLane.to_world(RAVENS_FROM.x, RAVENS_FROM.y)
	var orders := EventIssueCommand.new()
	orders.name = "Orders"
	ravens.add_child(orders)
	var fly_in := EventCommandPoint.new()
	fly_in.name = "FlyIn"
	fly_in.command_type = "move"
	fly_in.near_commander_id = PLAYER
	fly_in.near_standoff = RAVENS_STANDOFF
	orders.add_child(fly_in)
	# Relative to the spawn event above it, which stands at RAVENS_FROM.
	fly_in.position = (
		MissionLane.to_world(RAVENS_LAND_NEAR.x, RAVENS_LAND_NEAR.y)
		- MissionLane.to_world(RAVENS_FROM.x, RAVENS_FROM.y)
	)
	var land := EventCommandPoint.new()
	land.name = "Land"
	land.command_type = "land"
	orders.add_child(land)


## The beats after the opening (see PLAYER_START): five triggers, the squad's tactic and the
## enemy's two.
func _beats(a_manager: Node, a_house: Node3D) -> void:
	# 1. The rescue: the player walks into it; the fight's reveal ends with the ambushers.
	var ambush := GlobalTrigger.new()
	ambush.name = "RescueAmbush"
	ambush.conditions = [_units_in(PLAYER, "AmbushRegion")]
	a_manager.add_child(ambush)
	_region(ambush, "AmbushRegion", AMBUSH_TRIGGER, AMBUSH_TRIGGER_RADIUS)
	_spawn(ambush, "Rescuers", ALLY, IRREGULAR, RESCUERS, RESCUERS_AT, RESCUE_GROUP)
	_spawn(ambush, "Ambushers", ENEMY, RECRUIT, AMBUSHERS, AMBUSHERS_AT, AMBUSH_GROUP)
	_reveal(ambush, "RevealFight", FIGHT_REVEAL_AT, FIGHT_REVEAL_RADIUS, FIGHT_REVEAL)
	var won := GlobalTrigger.new()
	won.name = "AmbushBeaten"
	won.conditions = [_group_at_most(AMBUSH_GROUP, 0)]
	won.prerequisites = [ambush]
	a_manager.add_child(won)
	_end_reveal(won, "EndFightReveal", FIGHT_REVEAL)

	# 2–3. The squad moves on once the prisons are down and the outpost is cleared — not before
	# the outpost falls, or it would walk into the player's first fight (Alex: it stays out).
	var move_on := GlobalTrigger.new()
	move_on.name = "SquadMovesOn"
	move_on.conditions = [
		_killed("PrisonCompound1"), _killed("PrisonCompound2"), _group_at_most(OUTPOST_GROUP, 0)
	]
	move_on.prerequisites = [won]
	a_manager.add_child(move_on)

	# 4. The garrison: the player takes cover and the squad walks on; when it gets there the
	# Clippers fall on it from beyond it, out of the building's reach — spawned where the squad
	# IS, not when the player garrisons, or they would appear beside the building (found
	# 2026-10-18: spawned at the squad's waiting place, one came within 12 of it). A reveal shows
	# the player the squad's end.
	var cover := GlobalTrigger.new()
	cover.name = "PlayerTakesCover"
	var occupied := ConditionGarrisonOccupied.new()
	occupied.host_name = GARRISON_HOUSE_NAME
	occupied.commander_id = PLAYER
	cover.conditions = [occupied]
	cover.prerequisites = [move_on]
	a_manager.add_child(cover)
	var strike := GlobalTrigger.new()
	strike.name = "ClippersStrike"
	strike.conditions = [_units_in(ALLY, "AdvanceRegion")]
	strike.prerequisites = [cover]
	a_manager.add_child(strike)
	_region(strike, "AdvanceRegion", ADVANCE_AT, ADVANCE_RADIUS)
	for i: int in 2:
		var spawn := EventSpawnEntities.new()
		spawn.name = "Clipper%d" % (i + 1)
		spawn.commander_id = ENEMY
		spawn.entity_scenes = [load(CLIPPER) as PackedScene]
		spawn.count_expression = "1"
		spawn.spawn_groups = [CLIPPER_GROUP]
		spawn.follow_group = RESCUE_GROUP
		spawn.follow_away_from = a_house
		spawn.follow_offset = Vector2(CLIPPERS_PAST_SQUAD, (float(i) - 0.5) * CLIPPER_SPACING)
		strike.add_child(spawn)
		spawn.position = MissionLane.to_world(ADVANCE_AT.x, ADVANCE_AT.y)
	_reveal(cover, "RevealAdvance", ADVANCE_AT, ADVANCE_REVEAL_RADIUS, ADVANCE_REVEAL)
	var squad_lost := GlobalTrigger.new()
	squad_lost.name = "SquadLost"
	squad_lost.conditions = [_group_at_most(RESCUE_GROUP, 0)]
	squad_lost.prerequisites = [cover]
	a_manager.add_child(squad_lost)
	_end_reveal(squad_lost, "EndAdvanceReveal", ADVANCE_REVEAL)

	# 5. The fork: walking on east shows all of it.
	var fork := GlobalTrigger.new()
	fork.name = "ForkReveal"
	fork.conditions = [_units_in(PLAYER, "ForkRegion")]
	a_manager.add_child(fork)
	_region(fork, "ForkRegion", FORK_TRIGGER, FORK_TRIGGER_RADIUS)
	_reveal(fork, "RevealFork", FORK_REVEAL_AT, FORK_REVEAL_RADIUS, &"prologue_m1_fork_reveal")

	# On the way down to the main corridor: the match is autosaved (Alex, 2026-10-18).
	var autosave := GlobalTrigger.new()
	autosave.name = "AutosaveToMainLane"
	autosave.conditions = [_units_in(PLAYER, "AutosaveRegion")]
	a_manager.add_child(autosave)
	_region(autosave, "AutosaveRegion", AUTOSAVE_AT, AUTOSAVE_RADIUS)
	var save := EventAutosave.new()
	save.name = "Autosave"
	autosave.add_child(save)

	# The squad: fight the ambush; then lead to the prisons and wait; then wait by the building;
	# then walk on. First matching rule wins, so the latest beat is listed first.
	var squad := ScenarioTactic.new()
	squad.name = "SquadTactic"
	squad.unit_group = RESCUE_GROUP
	a_manager.add_child(squad)
	_add_rule(
		squad, "Fight", TacticRule.Action.ASSAULT, AMBUSHERS_AT, _group_at_least(AMBUSH_GROUP)
	)
	_add_rule(squad, "WalkOn", TacticRule.Action.ASSAULT, ADVANCE_AT, _fired(cover.name))
	_add_rule(squad, "WaitAtHouse", TacticRule.Action.HOLD, GARRISON_HOLD, _fired(move_on.name))
	_add_rule(squad, "WaitAtPrisons", TacticRule.Action.HOLD, PRISON_HOLD)
	_assault(a_manager, "AmbusherTactic", AMBUSH_GROUP, RESCUERS_AT)
	# The Clippers kill the squad, then turn on the building.
	var clippers := ScenarioTactic.new()
	clippers.name = "ClipperTactic"
	clippers.unit_group = CLIPPER_GROUP
	a_manager.add_child(clippers)
	var squad_alive: Condition = _group_at_least(RESCUE_GROUP)
	_add_rule(clippers, "KillSquad", TacticRule.Action.ASSAULT, ADVANCE_AT, squad_alive)
	_add_rule(clippers, "AttackHouse", TacticRule.Action.ASSAULT, GARRISON_HOUSE)


func _group_at_least(a_group: StringName) -> ConditionGroupCount:
	var condition := ConditionGroupCount.new()
	condition.group = a_group
	condition.comparison = ConditionGroupCount.Comparison.AT_LEAST
	condition.count = 1
	return condition


func _group_at_most(a_group: StringName, a_count: int) -> ConditionGroupCount:
	var condition := ConditionGroupCount.new()
	condition.group = a_group
	condition.comparison = ConditionGroupCount.Comparison.AT_MOST
	condition.count = a_count
	return condition


func _killed(a_name: String) -> ConditionEntityKilled:
	var condition := ConditionEntityKilled.new()
	condition.entity_name = a_name
	return condition


func _fired(a_trigger_name: String) -> ConditionTriggerFired:
	var condition := ConditionTriggerFired.new()
	condition.trigger_name = a_trigger_name
	return condition


func _end_reveal(a_trigger: Node, a_name: String, a_label: StringName) -> void:
	var end := EventEndReveal.new()
	end.name = a_name
	end.reveal_label = a_label
	a_trigger.add_child(end)


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
	_add_rule(tactic, "Assault", TacticRule.Action.ASSAULT, a_target)
	return tactic


## Append a rule to `a_tactic`: `a_action` at lane position `a_target`, while `a_condition` holds
## (null: always). Rules are tried in order, so a rule added after a conditional one is what the
## squad does once that condition stops holding.
func _add_rule(
	a_tactic: ScenarioTactic,
	a_name: String,
	a_action: TacticRule.Action,
	a_target: Vector2,
	a_condition: Condition = null
) -> void:
	var rule := TacticRule.new()
	rule.name = a_name
	rule.action = a_action
	rule.condition = a_condition
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
