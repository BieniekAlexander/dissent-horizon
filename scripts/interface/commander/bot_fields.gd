class_name BotFields
extends RefCounted

## THE BOT'S LATTICE, WHAT THE BOT KNOWS OF THE GROUND ON IT, AND THE FIELDS OVER IT.
##
## One `Lattice` per bot, centred on the map (gdd/systems/ai/world-model/lattice-and-topology.md
## §One lattice); the passability over it that the distance fields are swept on; the explored
## set that gates where the bot may SEND a unit; and the DISTANCE FIELDS from the bot's believed
## enemy and from its own home, with the reads over them — an arrival time, the approach band,
## quiet ground (that note, §Distance fields). The scout grid's sight timestamps still live in
## `BotScout` — they are the `sight_age` channel's storage until a second reader wants them
## here — and index through this lattice.
##
## EVERY FIELD IS A FUNCTION OF BELIEFS: the sources are the blackboard's believed enemy
## positions and the bot's own structures, the ground is the true grid (below), and the bot's
## own armed presence is a PENALTY on the enemy's field — an allied army is a challenge to
## the enemy's movement, so the enemy's expected route bends around it and the approach band
## moves when the army does (Alex, 2026-10-08). Each read is a pure static over fixtures
## underneath, which is what tests/test_BotFields.gd exercises; this object only gathers the
## sources.
##
## REBUILT ON A CADENCE, IN PIECES, BEHIND A COMPLETE SNAPSHOT. A whole rebuild on a
## skirmish-sized lattice costs 48–54 ms once enemies are believed (measured 2026-10-08,
## lattice-and-topology.md §Performance) — more than a tick — so the fields job calls
## refresh() on `BotDifficulty.field_refresh_seconds` and then advance() with its work
## allowance until is_pending() clears, each sweep settling a bounded number of cells per
## call. Reads always serve the last COMPLETE snapshot, so a consumer never sees a field
## half-swept; the one exception is the first build, which a read completes synchronously so
## that nothing reads nothing. rebuild_now() is refresh() and advance() to completion, for a
## test or a probe.
##
## TWO RULES, both Alex's (2026-10-08; that note, §Passability is relative):
##
##   * **Passability reads the TRUE grid**, unexplored ground and unseen structures included. A
##     player has the same: an order into the fog is walked around every obstruction there, so
##     the terrain is obtainable by probing and the bot is handed it rather than made to probe.
##     One mask per `NavAgentClass.Size`, built the first time that class is asked for — a
##     truck's quiet flank is a raider's front door.
##   * **No destination is ever predicated on true-grid signal.** A field may be swept over
##     ground the bot has not seen; a point the bot ORDERS a unit to must be one it has
##     explored. `is_explored` is that gate, and every consumer that picks a stage point, a
##     post, an objective or a waypoint passes its candidate through it.
##
## A lattice cell stands for a block of terrain cells and is passable when at least
## PASSABLE_MIN_FRACTION of them survive the class's erosion. That is coarse — a thin wall
## through a block can read passable, a one-cell corridor can read sealed — and the coarseness
## is ACCEPTED as a known bias from signal degradation (Alex, 2026-10-08): the bot's behaviour
## does not turn on it.

## World units per lattice cell. One constant for every channel, coarser than the terrain
## grid by design and never finer than the old scout grid was (world-model/migration.md
## §Cadence and cost); retune only against a measurement.
const PITCH: float = 5.0

## The share of a lattice cell's terrain cells that must survive the class's erosion for the
## cell to count as passable. Half: a block more wall than ground is a wall.
const PASSABLE_MIN_FRACTION: float = 0.5

## How much the bot's own armed presence costs an enemy to walk through, in NavField cost
## units (tenths of a pitch) per energy of armed value covering the cell. At 0.03, a cell under
## a 1,000-energy army costs three orthogonal steps to enter, so crossing its reach disc is
## worth a detour of some fifteen steps. A MODEL CONSTANT to start (lattice-and-topology.md
## §Distance fields); whether it is worth a difficulty parameter is for the search to say.
const PRESENCE_PENALTY_PER_ENERGY: float = 0.03

## How far past the shortest enemy-to-home walk a cell may lie and still be ON an approach:
## two lattice hops, one of give either way, so the band is a corridor rather than a line and
## its width at a point is how constrained the approach is there.
const BAND_SLACK_COST: int = 2 * NavField.STEP_ORTHOGONAL

## Ground the believed enemy cannot reach within this many seconds is QUIET: physically
## accessible and not realistically so, which is what the rear of a base is. A model
## constant to retune in testing; the threat clock's own falloff is a difficulty parameter.
const QUIET_HORIZON_SECONDS: float = 60.0

## Work units (BotScheduler: ~1 µs each) one settled lattice cell costs. Calibrated
## 2026-10-08: 8.5 ms for a 1,936-cell sweep, 4.4 µs a cell.
const WORK_UNITS_PER_SETTLED_CELL: int = 4
## Work units one explored-mask cell costs: a fog pixel read.
const WORK_UNITS_PER_EXPLORED_CELL: int = 2
## Work units gathering one believed source costs, its type's mobility included.
const WORK_UNITS_PER_SOURCE: int = 5
## Work units one presence stamp costs.
const WORK_UNITS_PER_STAMP: int = 10

## The rebuild's stages, in order.
enum Stage { GATHER, SWEEP, DONE }

var lattice: Lattice

var _map: Map
var _commander: Commander
## NavAgentClass.Size → the terrain grid's navigable mask for that class, whole grid, kept
## until the grid's cells change (memoized: one pass over every terrain cell per class).
var _terrain_masks: Dictionary = {}
## NavAgentClass.Size → the lattice mask for that class, kept until the grid's cells change.
var _passable: Dictionary = {}
## One byte per lattice cell, non-zero where the commander has explored its centre; empty
## until asked, dropped by refresh().
var _explored: PackedByteArray = PackedByteArray()
## THE READY SNAPSHOT: the fields and reads consumers see. Keys are a NavAgentClass.Size, or
## "size:speed" for the per-speed enemy fields the arrival time reads. A field a consumer asks
## for that the snapshot lacks (another class) is built on the spot and kept until the next
## swap.
var _enemy_fields: Dictionary = {}
var _enemy_arrival_fields: Dictionary = {}
var _home_fields: Dictionary = {}
var _bands: Dictionary = {}
var _penalty: PackedInt32Array = PackedInt32Array()
var _penalty_built: bool = false
## The believed enemy sources behind the snapshot — see _enemy_sources.
var _sources: Array = []
var _sources_built: bool = false
## Whether a snapshot has ever been completed: before the first, a read builds synchronously.
var _ready: bool = false

## THE REBUILD IN PROGRESS, or empty: its stage, the sources and penalty gathered, the fields
## being swept (each a NavField with its sources added, run in pieces), and the explored mask.
var _build: Dictionary = {}
## A believed type's mobility, cached for one rebuild: Bot.mobility_of_type walks the piece
## group, so it is asked once per type rather than once per believed piece.
var _mobility_cache: Dictionary = {}
## reach → the band coverage of a weapon of that reach at every cell, for reach_coverage;
## kept until the next swap.
var _coverage_cache: Dictionary = {}
## "cell:size" → a field sourced at one cell, for arrival_seconds_between; swept on first
## request and kept until the next swap. TODO: a sweep per (point, class) per refresh while
## the base is under threat — measure once the guard reads it under load.
var _point_fields: Dictionary = {}


#region Construction
## The fields of `a_commander` on its map, or null while it has no map to lay a lattice over.
static func over(a_commander: Commander) -> BotFields:
	if a_commander == null or a_commander.map == null or a_commander.map.height_map == null:
		return null
	var fields := BotFields.new()
	fields._commander = a_commander
	fields._map = a_commander.map
	fields.lattice = Lattice.covering(a_commander.map.world_bounds(), PITCH)
	if a_commander.map.terrain_grid != null:
		a_commander.map.terrain_grid.cells_changed.connect(fields._on_cells_changed)
	return fields


#endregion


#region Passability — the true grid
## Where the ground is passable for `a_size`, one byte per lattice cell, row-major as
## `Lattice.index_of` counts. Built on first request per class and kept until the terrain
## grid's cells change.
func passable_mask(a_size: NavAgentClass.Size) -> PackedByteArray:
	if not _passable.has(a_size):
		_passable[a_size] = _build_passable(a_size)
	return _passable[a_size]


func _build_passable(a_size: NavAgentClass.Size) -> PackedByteArray:
	var grid: TerrainGrid = _map.terrain_grid
	if grid == null:
		return PackedByteArray()
	if not _terrain_masks.has(a_size):
		_terrain_masks[a_size] = grid.navigable_mask(
			grid.get_bounds_rect(),
			NavAgentClass.erosion_rings(a_size, Map.CELL_SIZE),
			NavAgentClass.required_clearance(a_size, Map.CELL_SIZE)
		)
	return lattice_mask(
		lattice,
		_terrain_masks[a_size],
		grid.grid_width(),
		grid.grid_depth(),
		_map.world_bounds().position + Vector2(0.5, 0.5) * Map.CELL_SIZE,
		Map.CELL_SIZE
	)


func _on_cells_changed(_a_cells: Array) -> void:
	_terrain_masks = {}
	_passable = {}


## THE PURE RULE: the lattice mask over a terrain mask.
##
## `terrain_mask` is one byte per terrain cell, row-major over `terrain_width` × `terrain_depth`,
## non-zero where the cell is navigable for the class; terrain cell (x, z) has its centre at
## `first_cell_centre + (x, z) × cell_size`. A lattice cell takes the terrain cells whose
## centres fall inside it, and is passable when at least PASSABLE_MIN_FRACTION of them are
## navigable. A lattice cell with no terrain cell under it (the overhang of an odd remainder)
## is impassable.
static func lattice_mask(
	lattice: Lattice,
	terrain_mask: PackedByteArray,
	terrain_width: int,
	terrain_depth: int,
	first_cell_centre: Vector2,
	cell_size: float
) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(lattice.cell_count())
	for index: int in lattice.cell_count():
		var rect: Rect2 = lattice.rect_of(lattice.cell_of(index))
		# The terrain cells whose centres lie in [rect.position, rect.end).
		var low: Vector2 = (rect.position - first_cell_centre) / cell_size
		var high: Vector2 = (rect.end - first_cell_centre) / cell_size
		var x0: int = maxi(0, ceili(low.x))
		var z0: int = maxi(0, ceili(low.y))
		var x1: int = mini(terrain_width - 1, ceili(high.x) - 1)
		var z1: int = mini(terrain_depth - 1, ceili(high.y) - 1)
		var total: int = 0
		var navigable: int = 0
		for z: int in range(z0, z1 + 1):
			for x: int in range(x0, x1 + 1):
				total += 1
				if terrain_mask[z * terrain_width + x] != 0:
					navigable += 1
		if total > 0 and float(navigable) >= PASSABLE_MIN_FRACTION * float(total):
			out[index] = 1
	return out


#endregion


#region The explored set — the gate on destinations
## Whether the bot may send a unit to `a_cell`: it has explored the cell's centre. False off
## the lattice.
func is_explored(a_cell: Vector2i) -> bool:
	if not lattice.is_in_bounds(a_cell):
		return false
	return explored_mask()[lattice.index_of(a_cell)] != 0


## One byte per lattice cell, non-zero where explored — as of the ready snapshot, since the
## explored set only grows while units look about and a refresh period's lag costs nothing.
func explored_mask() -> PackedByteArray:
	_ensure_ready()
	return _explored


## BEGIN A REBUILD over what the bot believes now. The ready snapshot keeps serving reads
## until advance() has completed the new one. The fields job calls this on its cadence;
## passability does not depend on it.
func refresh() -> void:
	_build = {"stage": Stage.GATHER}
	_mobility_cache = {}


## Whether a rebuild is part-way through.
func is_pending() -> bool:
	return not _build.is_empty() and _build["stage"] != Stage.DONE


## CARRY THE REBUILD ON for up to `a_allowance` work units; returns the units spent. GATHER
## reads the sources, the presence stamps and the explored mask and plans the sweeps — the
## enemy and home fields for SMALL (the most permissive ground, every raider's door) and one
## arrival field per believed (class, speed) — then SWEEP settles each field a budgeted
## number of cells at a time, and DONE swaps the new snapshot in.
func advance(a_allowance: int) -> int:
	if _build.is_empty() or _build["stage"] == Stage.DONE:
		return 0
	var spent: int = 0
	if _build["stage"] == Stage.GATHER:
		spent += _gather()
		_build["stage"] = Stage.SWEEP
	var queue: Array = _build["queue"]
	while not queue.is_empty() and spent < a_allowance:
		var field: NavField = queue[0]
		var cells: int = maxi(1, (a_allowance - spent) / WORK_UNITS_PER_SETTLED_CELL)
		var settled_before: int = field.settled_count()
		var done: bool = field.run(cells)
		spent += (field.settled_count() - settled_before) * WORK_UNITS_PER_SETTLED_CELL
		if done:
			queue.pop_front()
	if queue.is_empty():
		_swap_in()
		_build["stage"] = Stage.DONE
	return spent


## refresh() and advance() to completion — for a test or a probe that reads at once.
func rebuild_now() -> void:
	refresh()
	advance(BotJob.UNLIMITED_WORK_UNITS)


## Stage GATHER: the sources, the penalty, the explored mask, and the planned sweeps.
func _gather() -> int:
	var sources: Array = _gather_sources()
	var stamps: Array = _presence_stamps()
	var penalty: PackedInt32Array = presence_penalty_of(
		lattice, stamps, PRESENCE_PENALTY_PER_ENERGY
	)
	var explored: PackedByteArray = explored_mask_over(lattice, _is_explored_at)
	var queue: Array = []
	var enemy_cells: Array = []
	var by_key: Dictionary = {}
	for source: Dictionary in sources:
		enemy_cells.append(source["cell"])
		if source.get("is_air", false) or source.get("speed", 0.0) <= 0.0:
			continue
		var key: String = _arrival_key(source)
		if not by_key.has(key):
			by_key[key] = {"size": source["nav_class"], "speed": source["speed"], "cells": []}
		by_key[key]["cells"].append(source["cell"])
	var enemy: NavField = null
	if not enemy_cells.is_empty():
		enemy = _planned(passable_mask(NavAgentClass.Size.SMALL), enemy_cells, penalty)
		queue.append(enemy)
	var home: NavField = null
	var home_cells: Array = _home_cells()
	if not home_cells.is_empty():
		home = _planned(passable_mask(NavAgentClass.Size.SMALL), home_cells, PackedInt32Array())
		queue.append(home)
	var arrival: Dictionary = {}
	for key: String in by_key:
		var field: NavField = _planned(
			passable_mask(by_key[key]["size"]), by_key[key]["cells"], penalty
		)
		arrival[key] = {"speed": by_key[key]["speed"], "field": field}
		queue.append(field)
	(
		_build
		. merge(
			{
				"sources": sources,
				"penalty": penalty,
				"explored": explored,
				"enemy": enemy,
				"home": home,
				"arrival": arrival,
				"queue": queue,
			},
			true
		)
	)
	return (
		sources.size() * WORK_UNITS_PER_SOURCE
		+ stamps.size() * WORK_UNITS_PER_STAMP
		+ lattice.cell_count() * WORK_UNITS_PER_EXPLORED_CELL
	)


## Stage DONE: the new snapshot replaces the old, whole.
func _swap_in() -> void:
	_sources = _build["sources"]
	_sources_built = true
	_penalty = _build["penalty"]
	_penalty_built = true
	_explored = _build["explored"]
	_enemy_fields = {}
	if _build["enemy"] != null:
		_enemy_fields[NavAgentClass.Size.SMALL] = _build["enemy"]
	_home_fields = {}
	if _build["home"] != null:
		_home_fields[NavAgentClass.Size.SMALL] = _build["home"]
	_enemy_arrival_fields = _build["arrival"]
	_bands = {}
	_point_fields = {}
	_coverage_cache = {}
	_ready = true


## A field with its sources and penalty set, not yet run.
func _planned(a_passable: PackedByteArray, a_cells: Array, a_penalty: PackedInt32Array) -> NavField:
	var field: NavField = NavField.over(lattice.width, lattice.depth, a_passable)
	field.set_penalty(a_penalty)
	for cell: Vector2i in a_cells:
		field.add_source(cell)
	return field


## Before the first snapshot exists, a read completes the pending rebuild (or starts one) so
## that nothing reads an empty model; afterwards reads serve the snapshot as it stands.
func _ensure_ready() -> void:
	if _ready:
		return
	if _build.is_empty():
		refresh()
	advance(BotJob.UNLIMITED_WORK_UNITS)


## Whether the commander has explored the ground at `a_xz`; everywhere, with no commander (a
## fixture).
func _is_explored_at(a_xz: Vector2) -> bool:
	return _commander == null or _commander.has_explored(VU.from_xz(a_xz))


## THE PURE RULE: `is_explored` sampled at every cell's centre.
static func explored_mask_over(lattice: Lattice, is_explored: Callable) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(lattice.cell_count())
	for index: int in lattice.cell_count():
		if is_explored.call(lattice.centre_of(lattice.cell_of(index))):
			out[index] = 1
	return out


#endregion


#region The fields — from believed sources
## Whether the bot believes in any enemy piece at all: without one there is no enemy field,
## no band, and no arrival time — the MISSING read the posture layer will fill
## (lattice-and-topology.md §Passability is relative).
func has_enemy_sources() -> bool:
	_ensure_ready()
	return not _enemy_sources().is_empty()


## The field from every believed enemy position, over ground passable for `a_size`, with the
## bot's own presence as a penalty. Null with nothing believed.
func enemy_field(a_size: NavAgentClass.Size) -> NavField:
	_ensure_ready()
	if not _enemy_fields.has(a_size):
		var cells: Array = []
		for source: Dictionary in _enemy_sources():
			cells.append(source["cell"])
		_enemy_fields[a_size] = (
			null
			if cells.is_empty()
			else sweep(lattice, passable_mask(a_size), cells, presence_penalty())
		)
	return _enemy_fields[a_size]


## The field from the bot's own structures (its units, when it has no structure), over ground
## passable for `a_size`. Null when the bot owns nothing.
func home_field(a_size: NavAgentClass.Size) -> NavField:
	_ensure_ready()
	if not _home_fields.has(a_size):
		var cells: Array = _home_cells()
		_home_fields[a_size] = (
			null
			if cells.is_empty()
			else sweep(lattice, passable_mask(a_size), cells, PackedInt32Array())
		)
	return _home_fields[a_size]


## THE APPROACH BAND for `a_size`: one byte per cell, non-zero on the ground a walk from the
## believed enemy to the bot's home would plausibly cross. Empty when either end is missing.
func approach_band(a_size: NavAgentClass.Size) -> PackedByteArray:
	_ensure_ready()
	if not _bands.has(a_size):
		var enemy: NavField = enemy_field(a_size)
		var home: NavField = home_field(a_size)
		_bands[a_size] = (
			PackedByteArray()
			if enemy == null or home == null
			else band(enemy, home, BAND_SLACK_COST)
		)
	return _bands[a_size]


## SECONDS UNTIL THE NEAREST BELIEVED ENEMY UNIT COULD STAND AT `a_xz`: ground units along
## their class's field at their type's speed, aircraft on the straight line at theirs. INF with
## no believed mobile enemy, or none that can get there — the MISSING read, not zero.
func arrival_seconds_at(a_xz: Vector2) -> float:
	_ensure_ready()
	var cell: Vector2i = lattice.index_at(a_xz)
	var best: float = INF
	for key: String in _ground_arrival_keys():
		var field: NavField = _enemy_arrival_fields[key]["field"]
		var speed: float = _enemy_arrival_fields[key]["speed"]
		best = minf(best, arrival_seconds(field, cell, lattice.pitch, speed))
	for source: Dictionary in _enemy_sources():
		if source.get("is_air", false) and source.get("speed", 0.0) > 0.0:
			best = minf(best, source["xz"].distance_to(a_xz) / source["speed"])
	return best


## Whether `a_xz` is QUIET: no believed enemy unit can reach it inside QUIET_HORIZON_SECONDS.
## True with nothing believed — quiet is what unknown ground reads as, and the posture layer
## is what will say otherwise.
func is_quiet_at(a_xz: Vector2) -> bool:
	return arrival_seconds_at(a_xz) > QUIET_HORIZON_SECONDS


## WHERE THE ARMY STANDS ON THE APPROACH: the explored band cell at least `a_min_distance`
## from `a_anchor_xz` that lies nearest home along the enemy's walk, as a world XZ — or null
## when there is no band (nothing believed, or nothing connects it to home). Ties break in
## the bot's own frame (`a_forward`), never by cell index, so two mirrored bots choose mirror
## posts (post_on_band).
func approach_post(a_anchor_xz: Vector2, a_forward: Vector2, a_min_distance: float) -> Variant:
	_ensure_ready()
	var home: NavField = home_field(NavAgentClass.Size.SMALL)
	if home == null:
		return null
	return post_on_band(
		lattice,
		approach_band(NavAgentClass.Size.SMALL),
		home,
		explored_mask(),
		a_anchor_xz,
		a_forward,
		a_min_distance
	)


## SECONDS FOR A PIECE OF `a_mobility` (Bot.mobility_of) STANDING AT `a_from_xz` TO REACH
## `a_to_xz`: a flyer on the straight line; a walker along a field sourced at the destination
## over its class's ground, read to beside a walled destination. INF when it cannot get
## there, or cannot move at all.
func arrival_seconds_between(a_from_xz: Vector2, a_to_xz: Vector2, a_mobility: Dictionary) -> float:
	_ensure_ready()
	var speed: float = float(a_mobility.get("speed", 0.0))
	if speed <= 0.0:
		return INF
	if a_mobility.get("is_air", false):
		return a_from_xz.distance_to(a_to_xz) / speed
	var size: NavAgentClass.Size = a_mobility.get("nav_class", NavAgentClass.Size.SMALL)
	var to_cell: Vector2i = lattice.index_at(a_to_xz)
	var key: String = "%d,%d:%d" % [to_cell.x, to_cell.y, int(size)]
	if not _point_fields.has(key):
		_point_fields[key] = sweep(lattice, passable_mask(size), [to_cell], PackedInt32Array())
	return arrival_seconds(_point_fields[key], lattice.index_at(a_from_xz), lattice.pitch, speed)


## HOW MUCH OF THE APPROACH BAND a weapon of ground reach `a_reach` standing at each cell
## would cover, 0–1 per cell (reach_coverage_of). Empty with no band: a defence then places
## by bearing alone.
func reach_coverage(a_reach: float) -> PackedFloat32Array:
	_ensure_ready()
	if not _coverage_cache.has(a_reach):
		_coverage_cache[a_reach] = reach_coverage_of(
			lattice, approach_band(NavAgentClass.Size.SMALL), a_reach
		)
	return _coverage_cache[a_reach]


## The penalty the bot's own armed pieces put on the enemy's field, one cost per cell.
func presence_penalty() -> PackedInt32Array:
	_ensure_ready()
	if not _penalty_built:
		_penalty = presence_penalty_of(lattice, _presence_stamps(), PRESENCE_PENALTY_PER_ENERGY)
		_penalty_built = true
	return _penalty


## The per-(class, speed) enemy fields the arrival time reads, built from the mobile sources.
func _ground_arrival_keys() -> Array:
	return _enemy_arrival_fields.keys()


static func _arrival_key(source: Dictionary) -> String:
	return "%d:%.2f" % [int(source["nav_class"]), source["speed"]]


## Every believed enemy as a source: its lattice cell and XZ, and for a unit its type's
## mobility (Bot.mobility_of_type) — speed, nav class, whether it flies. A structure, or a
## unit whose type nothing carries, has no speed and seeds the band only.
func _enemy_sources() -> Array:
	if not _sources_built:
		_sources = _gather_sources()
		_sources_built = true
	return _sources


## A believed type's mobility (Bot.mobility_of_type), cached until the next refresh(): that
## read walks every piece in the tree, and the clock asks it for every believed unit on every
## demand-map call.
func mobility_of_type(a_type: StringName) -> Dictionary:
	if not _mobility_cache.has(a_type):
		var bot: Bot = _commander as Bot
		_mobility_cache[a_type] = bot.mobility_of_type(a_type) if bot != null else {}
	return _mobility_cache[a_type]


## Every believed enemy as a source — see _enemy_sources. Overridable by a fixture.
func _gather_sources() -> Array:
	var sources: Array = []
	var bot: Bot = _commander as Bot
	if bot == null or bot.blackboard == null:
		return sources
	for entry: CommanderBlackboard.Entry in bot.blackboard.believed():
		var xz: Vector2 = VU.in_xz(entry.last_known_location)
		var source: Dictionary = {"cell": lattice.index_at(xz), "xz": xz}
		if not entry.is_structure:
			source.merge(mobility_of_type(entry.type))
		sources.append(source)
	return sources


func _home_cells() -> Array:
	var bot: Bot = _commander as Bot
	if bot == null:
		return []
	var anchors: Array = bot.get_structures()
	if anchors.is_empty():
		anchors = bot.get_units()
	var cells: Array = []
	for piece: Actor in anchors:
		cells.append(lattice.index_at(VU.in_xz(piece.global_position)))
	return cells


## The bot's armed pieces as {"xz", "reach", "value"}: where each stands, how far its longest
## ground weapon reaches, and what it cost — the stamps the presence penalty is built from.
func _presence_stamps() -> Array:
	var bot: Bot = _commander as Bot
	if bot == null:
		return []
	var stamps: Array = []
	for piece: Actor in bot.get_units() + bot.get_structures():
		if not bot.unit_is_armed(piece):
			continue
		var reach: float = 0.0
		for weapon: Weapon in piece.weapon_inventory.get_weapons():
			reach = maxf(reach, weapon.ground_reach())
		(
			stamps
			. append(
				{
					"xz": VU.in_xz(piece.global_position),
					"reach": reach,
					"value": float(bot.unit_cost(piece.id)),
				}
			)
		)
	return stamps


#endregion


#region The pure rules under the fields
## A settled field over `passable` from `source_cells`, with `penalty` on entering each cell
## (empty for none).
static func sweep(
	lattice: Lattice, passable: PackedByteArray, source_cells: Array, penalty: PackedInt32Array
) -> NavField:
	var field: NavField = NavField.over(lattice.width, lattice.depth, passable)
	field.set_penalty(penalty)
	for cell: Vector2i in source_cells:
		field.add_source(cell)
	field.run()
	return field


## THE APPROACH BAND: the cells whose enemy distance plus home distance lies within `slack`
## of the smallest such sum — the ground a walk from the one to the other would plausibly
## cross. One byte per cell. Empty when nothing connects the two.
static func band(enemy: NavField, home: NavField, slack: int) -> PackedByteArray:
	var enemy_d: PackedInt32Array = enemy.distances()
	var home_d: PackedInt32Array = home.distances()
	var out := PackedByteArray()
	out.resize(enemy_d.size())
	var shortest: int = -1
	for i: int in enemy_d.size():
		if enemy_d[i] == NavField.UNREACHABLE or home_d[i] == NavField.UNREACHABLE:
			continue
		var through: int = enemy_d[i] + home_d[i]
		if shortest < 0 or through < shortest:
			shortest = through
	if shortest < 0:
		return PackedByteArray()
	for i: int in enemy_d.size():
		if enemy_d[i] == NavField.UNREACHABLE or home_d[i] == NavField.UNREACHABLE:
			continue
		if enemy_d[i] + home_d[i] <= shortest + slack:
			out[i] = 1
	return out


## Seconds to walk `field`'s distance to `cell` — or, for a cell never reached, to beside it,
## since what is asked about is usually a structure on a wall — at `speed` world units per
## second, the field's
## costs being tenths of `pitch`. INF where the field does not reach.
static func arrival_seconds(field: NavField, cell: Vector2i, pitch: float, speed: float) -> float:
	var cost: int = field.distance_beside(cell)
	if cost == NavField.UNREACHABLE or speed <= 0.0:
		return INF
	return float(cost) / float(NavField.STEP_ORTHOGONAL) * pitch / speed


## THE POST ON THE BAND (approach_post's rule): among band cells that are explored and at
## least `min_distance` from `anchor` by centre, the one with the least home distance; ties
## go to the cell further ALONG `forward` from the anchor, then further to its right. Null
## with no candidate.
static func post_on_band(
	lattice: Lattice,
	band: PackedByteArray,
	home: NavField,
	explored: PackedByteArray,
	anchor: Vector2,
	forward: Vector2,
	min_distance: float
) -> Variant:
	var right := Vector2(-forward.y, forward.x)
	var best: Variant = null
	var best_key: Array = []
	for index: int in band.size():
		if band[index] == 0 or explored[index] == 0:
			continue
		var cell: Vector2i = lattice.cell_of(index)
		var centre: Vector2 = lattice.centre_of(cell)
		var offset: Vector2 = centre - anchor
		if offset.length() < min_distance:
			continue
		var distance: int = home.distance(cell)
		if distance == NavField.UNREACHABLE:
			continue
		var key: Array = [distance, -offset.dot(forward), -offset.dot(right)]
		if best == null or key < best_key:
			best = centre
			best_key = key
	return best


## REACH COVERAGE: for every cell, the fraction of the band's cells whose centres lie within
## `reach` of that cell's centre. Empty when the band is empty. The clustered turrets whose
## ranges covered cliffs (observed 2026-10-06) read near zero here.
static func reach_coverage_of(
	lattice: Lattice, band: PackedByteArray, reach: float
) -> PackedFloat32Array:
	var on_band: Array = []
	for index: int in band.size():
		if band[index] != 0:
			on_band.append(lattice.centre_of(lattice.cell_of(index)))
	if on_band.is_empty():
		return PackedFloat32Array()
	var out := PackedFloat32Array()
	out.resize(lattice.cell_count())
	var reach_sq: float = reach * reach
	for index: int in lattice.cell_count():
		var centre: Vector2 = lattice.centre_of(lattice.cell_of(index))
		var covered: int = 0
		for point: Vector2 in on_band:
			if centre.distance_squared_to(point) <= reach_sq:
				covered += 1
		out[index] = float(covered) / float(on_band.size())
	return out


## The presence penalty: every cell whose centre lies within a stamp's reach plus one pitch of
## the stamp (a piece stands anywhere in its cell) takes `per_energy × value`, summed over
## stamps and rounded to whole cost units.
static func presence_penalty_of(
	lattice: Lattice, stamps: Array, per_energy: float
) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(lattice.cell_count())
	for stamp: Dictionary in stamps:
		var centre: Vector2 = stamp["xz"]
		var radius: float = float(stamp["reach"]) + lattice.pitch
		var weight: int = roundi(per_energy * float(stamp["value"]))
		if weight <= 0:
			continue
		var low: Vector2i = lattice.index_at(centre - Vector2(radius, radius))
		var high: Vector2i = lattice.index_at(centre + Vector2(radius, radius))
		for z: int in range(maxi(0, low.y), mini(lattice.depth - 1, high.y) + 1):
			for x: int in range(maxi(0, low.x), mini(lattice.width - 1, high.x) + 1):
				var cell := Vector2i(x, z)
				if lattice.centre_of(cell).distance_to(centre) <= radius:
					out[lattice.index_of(cell)] += weight
	return out
#endregion
