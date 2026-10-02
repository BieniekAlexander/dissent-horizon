class_name LibertarianDominion
extends DominionRoute

## The Libertarian dominion route: every Opticon claims the tiles inside its vision, and each
## claimed tile banks dominion every cycle unless one of the commander's own fixtures stands
## on it. Why it works this way: gdd/factions/libertarian/structures/lb_dominion.md.
##
## RUN ONCE PER COMMANDER RATHER THAN ONCE PER OPTICON, for the same reason AnarchicalDominion
## is: a tile two Opticons both see is ONE tile, and a per-piece generator cannot see its
## neighbours to know that.

#region Properties
## Dominion one claimed tile banks per cycle. Fractional, so a tile's share is tracked in
## `_carry` and paid out as it adds up to whole dominion.
## TODO: placeholder, not tuned — set so a lone Opticon on open ground (a radius-20 vision,
## ~1250 tiles) banks about what a Warlord with four followers does.
@export var dominion_per_tile: float = 0.016

## Dominion earned but not yet paid, below one whole point.
var _carry: float = 0.0
## Physics ticks since the last payout. Private: nothing outside drives this cycle.
var _ticks_elapsed: int = 0
#endregion


#region Public API
## The Opticons this commander owns that are finished and standing.
func sources() -> Array[Commandable]:
	var out: Array[Commandable] = []
	if commander == null:
		return out
	for node: Node in commander.get_children():
		var piece := node as Commandable
		if (
			piece != null
			and structure_sources.has(piece.id)
			and piece.is_built
			and not piece.is_planned
			and not piece.is_queued_for_deletion()
			and piece.is_inside_tree()
		):
			out.append(piece)
	return out


## The Opticons this commander has ordered but that are not paying yet: blueprints still waiting
## for a builder, and ones under construction.
func pending_sources() -> Array[Commandable]:
	var out: Array[Commandable] = []
	if commander == null:
		return out
	for node: Node in commander.get_children():
		var piece := node as Commandable
		if (
			piece != null
			and structure_sources.has(piece.id)
			and not piece.is_queued_for_deletion()
			and (piece.is_planned or not piece.is_built)
		):
			out.append(piece)
	return out


func collection_rate() -> float:
	var snapshot: Dictionary = _snapshot_or_empty()
	return (snapshot.get("paying", {}) as Dictionary).size() * _tile_rate()


func pending_rate_change() -> float:
	var snapshot: Dictionary = _snapshot_or_empty()
	var projected: int = (snapshot.get("projected", {}) as Dictionary).size()
	var paying: int = (snapshot.get("paying", {}) as Dictionary).size()
	return (projected - paying) * _tile_rate()


## Dominion/s one paying tile is worth.
func _tile_rate() -> float:
	return dominion_per_tile * Engine.physics_ticks_per_second / DominionGenerator.TICK_RATE


func _snapshot_or_empty() -> Dictionary:
	if commander == null or commander.map == null:
		return {}
	return _snapshot(commander.map)


## The distinct tiles every source claims that pay this cycle — what the sweep banks for.
func paying_cells() -> Dictionary:
	var sources_now: Array[Commandable] = sources()
	if sources_now.is_empty():
		return {}
	var map: Map = sources_now[0].map
	var claimed: Array = []
	for source: Commandable in sources_now:
		claimed.append(cells_claimed_by(source))
	return union_excluding(claimed, _allied_fixture_cells(map))


## The tiles inside one source's vision, before de-duplication or exclusion. The vision SHAPE
## is the reach, so retuning the Opticon's sight retunes its claim with it.
static func cells_claimed_by(a_source: Commandable) -> Array[Vector2i]:
	if a_source.map == null:
		return []
	return cells_within(
		a_source.map.world_to_grid_point(VU.inXZ(a_source.global_position)),
		claim_radius_cells(a_source),
		grid_size_of(a_source.map)
	)


## The claim's radius in cells: the piece's vision shape. Read by node name rather than through
## `vision_range_shape`, so it also answers for an out-of-tree build preview. 0 without one.
static func claim_radius_cells(a_piece: Entity) -> float:
	var shape_node := a_piece.get_node_or_null("VisionRange") as CollisionShape3D
	if shape_node == null or shape_node.shape == null:
		return 0.0
	# Every library shape is a cylinder (tools/spec_import generates only CylinderShape3D).
	var radius: Variant = shape_node.shape.get("radius")
	return float(radius) / Map.CELL_SIZE if radius != null else 0.0


static func grid_size_of(a_map: Map) -> Vector2i:
	return Vector2i(a_map.height_map.map_width - 1, a_map.height_map.map_depth - 1)


## Every in-bounds cell whose CENTRE lies within `radius_cells` of `centre` (continuous grid
## coordinates). Terrain is not consulted: an unbuildable tile is claimed like any other.
static func cells_within(
	centre: Vector2, radius_cells: float, grid_size: Vector2i
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var reach: int = ceili(radius_cells)
	var origin := Vector2i(floori(centre.x), floori(centre.y))
	for z: int in range(maxi(0, origin.y - reach), mini(grid_size.y, origin.y + reach + 1)):
		for x: int in range(maxi(0, origin.x - reach), mini(grid_size.x, origin.x + reach + 1)):
			if Vector2(x + 0.5, z + 0.5).distance_to(centre) <= radius_cells:
				out.append(Vector2i(x, z))
	return out


## The union of every claim, as a set, less the `excluded` set.
static func union_excluding(claims: Array, excluded: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for claim: Array in claims:
		for cell: Vector2i in claim:
			if not excluded.has(cell):
				out[cell] = true
	return out


## A snapshot for pricing a new Opticon's site: which tiles will pay or sit under one of our
## fixtures once everything ordered is standing, so a candidate adds only the rest. Null outside
## a commander.
func site_survey(a_preview: Entity) -> DominionSiteSurvey:
	var map: Map = commander.map if commander != null else null
	if map == null:
		return null
	var snapshot: Dictionary = _snapshot(map)
	return OpticonSurvey.new(
		map,
		snapshot["projected"],
		snapshot["shielded"],
		claim_radius_cells(a_preview),
		dominion_per_tile
	)


## Every tile a new Opticon at `a_world_xz` would claim, marked with whether it would pay: not
## when a source — standing or pending — claims it, nor when one of our fixtures, standing or
## planned, stands on it.
func site_claim(a_preview: Entity, a_world_xz: Vector2) -> Dictionary:
	var map: Map = commander.map if commander != null else null
	if map == null:
		return {}
	var snapshot: Dictionary = _snapshot(map)
	var out: Dictionary = {}
	for cell: Vector2i in cells_within(
		map.world_to_grid_point(a_world_xz), claim_radius_cells(a_preview), grid_size_of(map)
	):
		out[cell] = not snapshot["projected"].has(cell) and not snapshot["shielded"].has(cell)
	return out


func claim_layer() -> Dictionary:
	var map: Map = commander.map if commander != null else null
	return _snapshot(map)["layer"] if map != null else {}


## How many cells a side of one survey block covers.
##
## THE SURVEY COUNTS BLOCKS, NOT CELLS: a candidate's claim is ~1250 cells, and at roughly 130 ns
## a cell in GDScript a survey of the ~200 candidates the bot scores cost 35 ms — a whole frame.
## Summing precounted 2×2 blocks is a quarter of the reads, for a claim edge a cell ragged.
const SURVEY_BLOCK_CELLS: int = 2


## The Libertarian survey: free tiles counted per block, and the claim as block offsets.
class OpticonSurvey:
	extends DominionSiteSurvey

	var _map: Map
	## Free tiles (neither paying nor shielded) per block, row-major.
	var _free: PackedByteArray = PackedByteArray()
	var _blocks: Vector2i
	var _offsets: Array[Vector2i] = []
	## Tiles that already pay, for the one a new Opticon would stand on.
	var _paying: Dictionary
	var _per_tile: float

	func _init(
		a_map: Map,
		a_paying: Dictionary,
		a_shielded: Dictionary,
		a_radius_cells: float,
		a_per_tile: float
	) -> void:
		_map = a_map
		_paying = a_paying
		_per_tile = a_per_tile
		var size: Vector2i = LibertarianDominion.grid_size_of(a_map)
		_blocks = Vector2i(
			ceili(float(size.x) / SURVEY_BLOCK_CELLS), ceili(float(size.y) / SURVEY_BLOCK_CELLS)
		)
		# Every block starts full and loses the cells that pay or are shielded — rather than asking
		# of every cell on the map, which is tens of thousands of lookups for a few thousand hits.
		_free.resize(_blocks.x * _blocks.y)
		_free.fill(SURVEY_BLOCK_CELLS * SURVEY_BLOCK_CELLS)
		for bz: int in _blocks.y:
			for bx: int in _blocks.x:
				if (bx + 1) * SURVEY_BLOCK_CELLS > size.x or (bz + 1) * SURVEY_BLOCK_CELLS > size.y:
					_free[bz * _blocks.x + bx] = (
						(mini(size.x, (bx + 1) * SURVEY_BLOCK_CELLS) - bx * SURVEY_BLOCK_CELLS)
						* (mini(size.y, (bz + 1) * SURVEY_BLOCK_CELLS) - bz * SURVEY_BLOCK_CELLS)
					)
		for taken: Dictionary in [a_paying, a_shielded]:
			for cell: Vector2i in taken:
				if cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y:
					_free[(cell.y / SURVEY_BLOCK_CELLS) * _blocks.x + cell.x / SURVEY_BLOCK_CELLS] -= 1
		var reach: float = a_radius_cells / SURVEY_BLOCK_CELLS
		for bz: int in range(-ceili(reach), ceili(reach) + 1):
			for bx: int in range(-ceili(reach), ceili(reach) + 1):
				if Vector2(bx, bz).length() <= reach:
					_offsets.append(Vector2i(bx, bz))

	func gain_at(a_world_xz: Vector2) -> float:
		var own: Vector2i = _map.world_to_grid(a_world_xz)
		var origin: Vector2i = own / SURVEY_BLOCK_CELLS
		var gained: int = 0
		for offset: Vector2i in _offsets:
			var bx: int = origin.x + offset.x
			var bz: int = origin.y + offset.y
			if bx >= 0 and bz >= 0 and bx < _blocks.x and bz < _blocks.y:
				gained += _free[bz * _blocks.x + bx]
		# The Opticon's own tile stops paying once something stands on it.
		gained -= 1
		return maxf(0.0, gained * _per_tile)


func full_site_gain(a_preview: Entity) -> float:
	var r: float = claim_radius_cells(a_preview)
	return PI * r * r * dominion_per_tile


#endregion


#region Private helpers
## Tiles under a fixture this commander's side owns, the Opticons included. Enemy and neutral
## fixtures do not shield a tile. The side is Commander.shares_side_with.
func _allied_fixture_cells(a_map: Map) -> Dictionary:
	var out: Dictionary = {}
	for fixture: Variant in a_map.structure_cell_map:
		if (
			not is_instance_valid(fixture)
			or not commander.shares_side_with((fixture as Entity).commander_id)
		):
			continue
		for cell: Vector2i in a_map.structure_cell_map[fixture]:
			out[cell] = true
	return out


## The claim as it stands and as it will stand once everything ordered is up:
##   "paying"    — tiles that pay this cycle (what the payout reads is paying_cells, the same)
##   "projected" — tiles that will pay, pending sources and planned buildings included
##   "shielded"  — tiles under our fixtures, standing or planned
##   "layer"     — cell -> ClaimState, the union of the first two, for drawing
## Memoized on claim_key, because the build preview asks every time the cursor crosses a cell and
## each half is a union over every Opticon's ~1250-cell claim.
func _snapshot(a_map: Map) -> Dictionary:
	var key: Variant = claim_key()
	if key == _snapshot_key:
		return _snapshot_value
	_snapshot_key = key
	_snapshot_value = claim_states(
		sources().map(cells_claimed_by),
		pending_sources().map(cells_claimed_by),
		_allied_fixture_cells(a_map),
		commander.planned_footprint_cells()
	)
	return _snapshot_value


## The snapshot's rule, pure: from the standing and pending sources' claims (arrays of cells) and
## the standing and planned fixtures' cells (sets), the four sets _snapshot describes.
static func claim_states(
	a_standing_claims: Array,
	a_pending_claims: Array,
	a_standing_fixtures: Dictionary,
	a_planned_fixtures: Dictionary
) -> Dictionary:
	var shielded: Dictionary = a_standing_fixtures.duplicate()
	shielded.merge(a_planned_fixtures)
	var paying: Dictionary = union_excluding(a_standing_claims, a_standing_fixtures)
	var projected: Dictionary = union_excluding(a_standing_claims + a_pending_claims, shielded)
	var layer: Dictionary = {}
	for cell: Vector2i in projected:
		layer[cell] = ClaimState.ACTIVE if paying.has(cell) else ClaimState.PENDING_GAIN
	for cell: Vector2i in paying:
		if not projected.has(cell):
			layer[cell] = ClaimState.PENDING_LOSS
	return {"paying": paying, "projected": projected, "shielded": shielded, "layer": layer}


var _snapshot_key: Variant = []
var _snapshot_value: Dictionary = {}


## What _snapshot reads: our Opticons standing and pending, our planned buildings and where they
## stand, and how many fixtures hold grid cells.
func claim_key() -> Variant:
	var map: Map = commander.map if commander != null else null
	if map == null:
		return []
	var planned: Array = []
	for node: Node in commander.get_children():
		var piece := node as Commandable
		if piece != null and piece.is_planned:
			planned.append([piece.get_instance_id(), piece.global_position])
	return [
		sources().map(func(c: Commandable) -> int: return c.get_instance_id()),
		pending_sources().map(func(c: Commandable) -> int: return c.get_instance_id()),
		planned,
		map.structure_cell_map.size()
	]


func _proc() -> void:
	_carry += paying_cells().size() * dominion_per_tile
	var whole: int = floori(_carry)
	if whole > 0:
		_carry -= whole
		commander.add_dominion(whole)


#endregion


#region Lifecycle
func _physics_process(_a_delta: float) -> void:
	if commander == null:
		return
	_ticks_elapsed += 1
	if _ticks_elapsed % DominionGenerator.TICK_RATE == 0:
		_proc()
#endregion
