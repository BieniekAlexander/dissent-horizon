extends Node3D

## DOES THE BOT STILL TRAP ITS OWN UNITS? Asked of a whole match, not of a fixture.
##
##   godot --headless --path . --fixed-fps 30 tools/selfplay/_placement_audit.tscn -- \
##       scenario=res://scenes/scenarios/skirmish_symmetric.tscn seed=1001 seconds=480
##
## Every simulated second it checks the two things the user reported, against the LIVE
## terrain grid rather than against the bot's intentions:
##
##   1. THE WALKABLE SURFACE WAS NOT SPLIT — the number of 4-connected passable regions has
##      not gone up since the navmesh first built. A building that walls off a pocket shows
##      up here whoever placed it.
##   2. NO STRUCTURE IS SEALED IN — every owned structure still has a whole side on walkable
##      ground in the biggest region, and production structures are reported separately
##      because that is the case the user named.
##
## It reports the WORST state seen, not the final one: a pocket that opens again when the
## building in it dies would otherwise go unnoticed.

const DEFAULT_SCENARIO: String = "res://scenes/scenarios/skirmish_symmetric.tscn"
const DEFAULT_FACTION: String = "res://scenes/factions/colonial.tscn"

var _scenario: Scenario
var _seconds: float = 480.0
var _regions_at_start: int = -1
var _worst_regions: int = 0
var _sealed_production: Array = []
var _sealed_any: Array = []
var _checks: int = 0


func _ready() -> void:
	var scenario_path: String = DEFAULT_SCENARIO
	var seed_value: int = 1001
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("scenario="):
			scenario_path = arg.substr("scenario=".length())
		elif arg.begins_with("seed="):
			seed_value = int(arg.substr("seed=".length()))
		elif arg.begins_with("seconds="):
			_seconds = float(arg.substr("seconds=".length()))
	_run.call_deferred(scenario_path, seed_value)


func _run(a_scenario_path: String, a_seed: int) -> void:
	var packed := load(a_scenario_path) as PackedScene
	_scenario = packed.instantiate() as Scenario
	_scenario.rng_seed = a_seed
	var faction := load(DEFAULT_FACTION) as PackedScene
	var slots: Array[PlayerSlot] = []
	for source: PlayerSlot in _scenario.player_slots:
		var slot: PlayerSlot = source.duplicate()
		slot.is_bot = true
		slot.faction = faction
		slot.difficulty = PlayerSlot.Difficulty.MEDIUM
		slots.append(slot)
	_scenario.player_slots = slots
	add_child(_scenario)
	var hud: Node = _scenario.get_node_or_null("SpectatorHUD")
	if hud != null:
		hud.free()
	await _audit()


func _audit() -> void:
	var map: Map = _scenario.get_node_or_null("Map") as Map
	if map == null:
		for node: Node in _scenario.get_children():
			if node is Map:
				map = node as Map
	var total_ticks: int = int(_seconds * TimeUtils.ticks_per_second())
	var per_check: int = TimeUtils.ticks_per_second()
	for tick: int in total_ticks:
		await get_tree().physics_frame
		if tick % per_check != 0 or map.terrain_grid == null:
			continue
		_check(map, tick)
	print("---PLACEMENT-AUDIT---")
	print("checks: %d over %.0f simulated seconds" % [_checks, _seconds])
	print("passable regions: %d at first check, %d at worst" % [_regions_at_start, _worst_regions])
	print(
		(
			"structures sealed in at any check (production): %d  %s"
			% [_sealed_production.size(), _sealed_production.slice(0, 8)]
		)
	)
	print(
		(
			"structures sealed in at any check (any kind):   %d  %s"
			% [_sealed_any.size(), _sealed_any.slice(0, 8)]
		)
	)
	get_tree().quit()


func _check(a_map: Map, a_tick: int) -> void:
	_checks += 1
	var grid: TerrainGrid = a_map.terrain_grid
	var regions: int = grid.component_count()
	if _regions_at_start < 0:
		_regions_at_start = regions
	_worst_regions = maxi(_worst_regions, regions)
	var main: int = grid.largest_component()
	for commander: Commander in _scenario.commanders:
		if commander == null or commander.id == 0:
			continue
		for child: Node in commander.get_children():
			var entity := child as Entity
			if entity == null or entity.is_queued_for_deletion():
				continue
			if not entity.has_node("Structure"):
				continue
			var cells: Array = a_map.structure_cell_map.get(entity, [])
			if cells.is_empty():
				continue
			if NavPlacement.has_navmesh_side(grid, cells, main):
				continue
			var record: String = "tick %d c%d %s" % [a_tick, commander.id, entity.id]
			_sealed_any.append(record)
			if entity.has_node("Production"):
				_sealed_production.append(record)
