@tool
class_name MapGenerationParams
extends RefCounted

## Every knob MapGenerator reads. Brackets and the reason for each are the parameter table in
## gdd/systems/terrain-and-navigation/map-generation.md; the defaults here sit inside them.
## TODO: none of these are tuned — see that table.
##
## Distances are in CELLS (Map.CELL_SIZE is 1, so also world units) and times in seconds.
## The generator knows the alliance count and these values — nothing about factions.

#region Constants
## Building occupancy at and above which placement is known to run out of room on default
## maps — measured, not derived; see map-generation.md §3.
const BUILDING_OCCUPANCY_FAILURE: float = 0.10
## Extra height on alternate ridge corners. Above TerrainGrid.MAX_SLOPE_DIFF, so a ridge's top
## is as unwalkable as its sides — a flat crest would be a plateau nothing can reach.
const RIDGE_ROUGHNESS: float = 1.0
## The last pass there is. Derived from the enum, so adding a pass moves it.
const PASS_COUNT: int = Pass.ELEVATION
## No walkable passage between two barriers, or between a barrier and the edge of the play
## area, is narrower than this many cells. A constant, not a knob: it is the floor that keeps a
## unit column moving through every choke on every map, and a carve samples its width from it.
## Chokes made by resource footprints are not held to it.
const MIN_CHOKE_WIDTH: int = 10
#endregion

#region Grouping
## How a form shows these knobs: ordered groups of property names, so the dock can section the
## parameter list without knowing what any of them mean. A property missing from here still
## shows — the dock collects the leftovers under "Other" — but it shows with no company, which
## is what test_MapGeneratorDock watches for.
const PROPERTY_GROUPS: Array = [
	{name = "Passes", properties = ["last_pass"]},
	{name = "Extent", properties = ["play_size_min", "play_size_max", "ground_height"]},
	{
		name = "Starts",
		properties = [
			"starts_per_alliance", "start_min_center_fraction", "start_angle_jitter_fraction",
			"start_clear_radius_cells", "start_edge_margin_cells",
			"start_separation_diagonal_fraction", "start_attempts",
		],
	},
	{
		name = "Value",
		properties = [
			"site_energy_per_second", "pond_rate_multiplier", "value_horizon_seconds",
			"energy_value_per_alliance", "pond_value_fraction",
		],
	},
	{
		name = "Ponds",
		properties = [
			"pond_cells_min", "pond_cells_max", "pond_cells_location", "pond_cells_scale",
			"pond_cells_skew", "pond_richness_factors", "pond_richness_weights",
			"pond_richness_size_decay",
		],
	},
	{
		name = "Shelters",
		properties = ["shelters_per_alliance_min", "shelters_per_alliance_extra"],
	},
	{
		name = "Buildings",
		properties = [
			"building_occupancy", "cluster_size_successes", "cluster_size_success_chance",
			"cluster_size_max", "cluster_packing_density", "building_cluster_separation_cells",
			"building_pool",
		],
	},
	{
		name = "Extraction sites",
		properties = [
			"site_triple_fraction_min", "site_triple_fraction_max", "site_pair_fraction_min",
			"site_pair_fraction_max", "site_cluster_separation_cells",
		],
	},
	{name = "Pieces", properties = ["site_piece", "shelter_piece"]},
	{
		name = "Favor and placement",
		properties = [
			"favor_concentration", "favor_tolerance", "placement_candidates",
			"candidate_draw_factor", "feature_spacing_cells", "footprint_gap_cells",
		],
	},
	{
		name = "Topology and terrain",
		properties = [
			"cut_fraction", "flooded_cut_fraction", "barrier_width_cells", "min_routes",
			"correction_radius_cells", "ridge_height", "chasm_depth", "flat_fraction",
		],
	},
	{
		name = "Elevation",
		properties = [
			"elevation_levels", "elevation_step", "cliff_levels", "cliff_step",
			"elevation_scale_cells", "start_level_fraction_min", "start_level_fraction_max",
		],
	},
	{name = "Collocation", properties = ["collocation_weight", "collocation_rules"]},
	{name = "Alliances", properties = ["alliance_count"]},
]

## One-line hover text per knob, for a form to show beside it (the dock's tooltips). The full
## reasoning is each property's own doc comment and the map-generation.md parameter table; this
## is the short version. test_MapGeneratorDock checks every property has one.
const DESCRIPTIONS: Dictionary = {
	"last_pass": "The last pass to run. Stop early to inspect a pass on its own.",
	"play_size_min": "Smallest play-area side, in diamonds. Each axis is drawn between min and max.",
	"play_size_max": "Largest play-area side, in diamonds. Equal to min pins the size.",
	"ground_height": "Height of the flat ground. It must leave room for a chasm to sink below it.",
	"alliance_count": "Number of alliances. Changing it resets the defaults that depend on it.",
	"starts_per_alliance": "Starting positions each alliance gets.",
	"start_min_center_fraction": "Least distance of a start from the map centre, as a fraction of the side.",
	"start_angle_jitter_fraction": "How far starts wander from even angular spacing, as a fraction of it.",
	"start_clear_radius_cells": "Half-width of the flat, empty box kept around each start.",
	"start_edge_margin_cells": "Least distance of a start from the edge of the play area.",
	"start_separation_diagonal_fraction": "Least distance between starts, as a fraction of the play diagonal.",
	"start_attempts": "How many start layouts to try before generation fails.",
	"site_energy_per_second": "An extraction site's income. Read from the piece, not edited here.",
	"pond_rate_multiplier": "A pond's rate as a multiple of a site's. Read from the game, not edited here.",
	"value_horizon_seconds": "The time window a pond's value is compared with a site's over.",
	"energy_value_per_alliance": "Total energy value the map places per alliance.",
	"pond_value_fraction": "Share of the energy value placed as ponds rather than sites.",
	"pond_cells_min": "Smallest pond, in cells.",
	"pond_cells_max": "Largest pond, in cells.",
	"pond_cells_location": "Centre of the pond-size draw, in cells.",
	"pond_cells_scale": "Spread of the pond-size draw, in cells.",
	"pond_cells_skew": "Skew of the pond-size draw. Positive makes small ponds more common.",
	"pond_richness_factors": "Charge per cell for each pond richness category.",
	"pond_richness_weights": "How often each richness category is drawn. Richer is rarer.",
	"pond_richness_size_decay": "How quickly the rich categories become rarer as ponds get larger.",
	"shelters_per_alliance_min": "Fewest shelters per alliance.",
	"shelters_per_alliance_extra": "Random extra shelters per alliance, on top of the minimum.",
	"building_occupancy": "Share of the play area covered by buildings. Keep it low: too high and placement runs out of room.",
	"cluster_size_successes": "Shape of the buildings-per-cluster draw. Higher gives larger clusters.",
	"cluster_size_success_chance": "Shape of the buildings-per-cluster draw. Higher gives smaller clusters.",
	"cluster_size_max": "Most buildings in one cluster.",
	"cluster_packing_density": "How tightly a cluster's buildings are packed. Lower spreads them out.",
	"building_cluster_separation_cells": "Least gap between buildings of two different clusters.",
	"building_pool": "The neutral buildings a cluster draws from.",
	"site_triple_fraction_min": "Least share of extraction sites standing in groups of three.",
	"site_triple_fraction_max": "Greatest share of extraction sites standing in groups of three.",
	"site_pair_fraction_min": "Least share of extraction sites standing in pairs.",
	"site_pair_fraction_max": "Greatest share of extraction sites standing in pairs.",
	"site_cluster_separation_cells": "Least gap between sites of two different site groups.",
	"site_piece": "The extraction-site piece and its footprint.",
	"shelter_piece": "The shelter piece and its footprint.",
	"favor_concentration": "How evenly each feature is shared between alliances. Lower lets features lean one way.",
	"favor_tolerance": "How far an alliance's share of value may stray from fair, as a fraction.",
	"placement_candidates": "Candidate spots scored for each feature. More is slower but better placed.",
	"candidate_draw_factor": "Draws allowed per candidate before placement stops looking.",
	"feature_spacing_cells": "Least centre-to-centre distance between features.",
	"footprint_gap_cells": "Clear cells kept between any two structures.",
	"cut_fraction": "Share of connections between features blocked by a ridge or chasm.",
	"flooded_cut_fraction": "Share of blocked connections that are water chasms rather than ridges.",
	"barrier_width_cells": "Rough thickness of a ridge or chasm.",
	"min_routes": "Separate routes every start keeps to every other start.",
	"correction_radius_cells": "How far a feature may move to rebalance once barriers lengthen paths.",
	"ridge_height": "How high a ridge rises above the ground.",
	"chasm_depth": "How deep a chasm sinks below the ground. Its water fills half of it.",
	"flat_fraction": "Least share of walkable ground that must be flat enough to build on.",
	"elevation_levels": "Terrace levels the ground steps through. 1 keeps each tier level.",
	"elevation_step": "Height of one terrace step. Keep it under the walkable slope limit, or every step becomes a cliff.",
	"cliff_levels": "Cliff tiers, the map's large height changes.",
	"cliff_step": "Height of one cliff tier. It is a cliff only where a barrier stands.",
	"elevation_scale_cells": "Size of the highs and lows, in cells. Larger gives broader ones.",
	"start_level_fraction_min": "Lowest the starts' shared terrace can be (0 bottom, 1 top).",
	"start_level_fraction_max": "Highest the starts' shared terrace can be (0 bottom, 1 top).",
	"collocation_weight": "How much the feature-neighbour rules count against fairness when placing.",
	"collocation_rules": "Which feature kinds attract or repel one another, and over what distance.",
}
#endregion

#region Passes
## The generator's passes, in order, as map-generation.md §The pipeline names them. Values are
## the pass NUMBERS that doc uses, so they read the same in a report as in the doc.
enum Pass {
	EXTENT = 1,
	STARTS = 2,
	RESOURCES = 3,
	TOPOLOGY = 4,
	TERRAIN = 5,
	ELEVATION = 6,
}

## The last pass to run: an earlier stop leaves the map as that pass left it, so each pass can
## be inspected alone. Passes run in order and none can be skipped.
var last_pass: Pass = Pass.ELEVATION
#endregion

#region Extent
## Default play-size bounds, in diamonds per axis, by start count. A heuristic starting point:
## TODO: only two players have a range, and it is untuned (map-generation.md §Parameters).
const PLAY_SIZE_RANGE_BY_START_COUNT: Dictionary = {2: Vector2i(75, 120)}

## Each axis of the play rectangle is drawn uniformly in [min, max] diamonds; the corner grid
## is derived from the result (TerrainData). Equal bounds pin the size.
var play_size_min: int = 75
var play_size_max: int = 120
## Height of the flat ground: high enough that a chasm sunk chasm_depth into it stays inside
## the brush's height range (0 and up).
var ground_height: float = 4.0
#endregion

#region Starts
var alliance_count: int = 2
var starts_per_alliance: int = 1
## Least distance of a start from the play-area centre, as a fraction of the side length it
## is measured along — an ellipse with the play rectangle's aspect. The distance beyond it is
## drawn freely up to the edge margin.
var start_min_center_fraction: float = 0.25
## Angular jitter as a fraction of the equal-spacing angle.
var start_angle_jitter_fraction: float = 0.3
## L-infinity radius of the box around each start that stays flat and empty. The box is twice
## this on a side, and must lie wholly in the play area. The default (a 12x12 box) holds the
## largest starting structure (8x8) with a margin; the starting extractor row it once also had
## to hold is gone.
## TODO: every Skirmish now drops its command centre wherever it chooses, so this box only has
## to hold the starting units; whether to shrink it is undecided — starting-formations.md.
var start_clear_radius_cells: int = 6
## Least distance of a start from any play-area edge.
var start_edge_margin_cells: float = 10.0
## Minimum start-to-start distance as a fraction of the play diagonal, at two starts; scaled
## by sqrt(2 / start count) beyond that.
var start_separation_diagonal_fraction: float = 0.25
## How many ring draws may be tried before the generation fails.
var start_attempts: int = 64
#endregion

#region Value
## A site's income. The shell sets this from nt_extractor, so the generator never hardcodes a
## piece stat.
var site_energy_per_second: float = 20.0
## A pond's rate as a multiple of a site's (WaterBody.POND_RATE_MULTIPLIER, set by the shell).
var pond_rate_multiplier: float = 2.0
## The window a pond is priced against a site over (map-generation.md §Energy value).
var value_horizon_seconds: float = 300.0
var energy_value_per_alliance: float = 24000.0
## Share of the energy budget spent on ponds.
var pond_value_fraction: float = 0.3
#endregion

#region Ponds
var pond_cells_min: int = 30
var pond_cells_max: int = 75
## Skew-normal shape of the pond size draw: right-skewed, so small ponds are common.
var pond_cells_location: float = 32.0
var pond_cells_scale: float = 18.0
var pond_cells_skew: float = 4.0
## Charge = cells x factor.
var pond_richness_factors: PackedInt32Array = PackedInt32Array([50, 75, 90, 100])
## Base draw weight per richness category; richer is rarer.
var pond_richness_weights: PackedFloat32Array = PackedFloat32Array([0.4, 0.3, 0.2, 0.1])
## How much faster rich categories fade as a pond grows: category k is weighted by
## exp(-decay * k * t), t the pond's size in [0, 1] between the bounds.
var pond_richness_size_decay: float = 1.0
#endregion

#region Shelters
## Shelter count = round(alliances x (min + extra x randf())).
var shelters_per_alliance_min: float = 1.0
var shelters_per_alliance_extra: float = 1.5
#endregion

#region Buildings
## Fraction of the play area's cells covered by building footprints. The building count
## follows map area and footprint sizes, not player count. Low values are the sensible range:
## from BUILDING_OCCUPANCY_FAILURE up, placement runs out of room (see warnings()).
var building_occupancy: float = 0.03
## Buildings per cluster: 1 + a negative binomial (failures before `successes` successes of
## chance `success_chance`), capped. At 2 and 0.4 the mean is 4: 1-3 is about half of all
## clusters, 4-7 about a third, 8-10 about one per two players and 11-16 about one match in
## three.
var cluster_size_successes: int = 2
var cluster_size_success_chance: float = 0.4
var cluster_size_max: int = 16
## Fraction of a cluster's disc its buildings fill, gap included. The scatter radius is
## derived from it, so a cluster of eight spreads wider than a cluster of three.
var cluster_packing_density: float = 0.35
## Least L1 distance, in cells, between the nearest buildings of two different clusters —
## what keeps neighbouring clusters from reading as one.
var building_cluster_separation_cells: int = 10
#endregion

#region Extraction sites
## Share of all sites standing in clusters of three, and of two, each drawn uniformly per map
## in [min, max]; the rest stand alone. A restricted integer partition of the site count into
## parts of 1-3 (map-generation.md §Extraction sites).
var site_triple_fraction_min: float = 0.2
var site_triple_fraction_max: float = 0.4
var site_pair_fraction_min: float = 0.2
var site_pair_fraction_max: float = 0.4
## Least L1 distance, in cells, between the nearest sites of two different site clusters.
var site_cluster_separation_cells: int = 50
## The neutral pieces a cluster draws from. The shell fills it; empty means no buildings.
var building_pool: Array[MapPiece] = []
#endregion

#region Pieces
## The shell sets these from the piece scenes, so footprints come from the pieces themselves.
var site_piece: MapPiece = MapPiece.of(&"nt_extractionSite", Vector2i(2, 2))
var shelter_piece: MapPiece = MapPiece.of(&"nt_shelter", Vector2i(3, 3))
#endregion

#region Favor and placement
## Dirichlet concentration of each feature's raw target share. Higher draws nearer an even
## split; lower lets single features lean hard toward one alliance.
## TODO: favor spread and bounds are not designed (map-generation.md §Favor).
var favor_concentration: float = 2.0
## Largest allowed deviation of an alliance's accessible value from its target, as a fraction
## of that target, per currency.
var favor_tolerance: float = 0.1
## Best-candidate budget per feature.
var placement_candidates: int = 48
## Draws allowed per wanted candidate before placement gives up on finding more.
var candidate_draw_factor: int = 8
## Minimum centre-to-centre distance between features.
var feature_spacing_cells: float = 6.0
## Clear cells kept between any two structures, so every footprint stays walkable around.
var footprint_gap_cells: int = 1
#endregion

#region Topology and terrain (passes 4-5)
## Share of feature-graph edges cut by a barrier.
var cut_fraction: float = 0.3
## Share of cuts drawn as flooded chasms; the rest are ridges.
var flooded_cut_fraction: float = 0.5
## How far from equidistant between its two nodes a barrier reaches: roughly its thickness.
var barrier_width_cells: float = 3.0
## Vertex-disjoint routes every start keeps to every other start over the feature graph.
var min_routes: int = 2
## How far pass 4 may move a feature to restore its favor once barriers lengthen paths.
var correction_radius_cells: float = 12.0
## Ridge height above the ground; every other ridge corner is raised a further
## RIDGE_ROUGHNESS, so no ridge cell is flat enough to stand on.
var ridge_height: float = 3.0
## How far below the ground a chasm is sunk; its water stands halfway up.
var chasm_depth: float = 2.0
## Least share of in-play dry walkable cells that must be buildable (all corners level).
var flat_fraction: float = 0.55
#endregion

#region Elevation (pass 6)
## Terrace levels the ground steps through, 0 lowest; 1 keeps the ground level within a tier.
var elevation_levels: int = 5
## Height between neighbouring terrace levels. **Keep it at or under TerrainGrid.MAX_SLOPE_DIFF**:
## a terrace step is meant to be walked over, so elevation may not divide ground that pass 4
## left open. Only the cells on the step lose their buildability.
var elevation_step: float = 0.4
## Cliff tiers, each a cliff_step above the last: the map's big relief. A tier's drop is a cliff
## only where a barrier carries it — everywhere else pass 6 grades the drop into a walkable
## slope, so elevation never divides ground the topology left open.
var cliff_levels: int = 3
## Height between neighbouring tiers: a cliff, so well above MAX_SLOPE_DIFF. Keep it above
## chasm_depth / 2 — a chasm's water stands that far above its floor, and must not reach the
## floor of a chasm one tier up.
var cliff_step: float = 1.5
## Size of the noise features that decide levels, in cells: larger gives broad highs and lows.
var elevation_scale_cells: float = 60.0
## The band of the terrace range the starts' shared level is drawn from: 0 lowest, 1 highest.
## Their tier is the middle one, so the band reads against the whole height range.
var start_level_fraction_min: float = 0.5
var start_level_fraction_max: float = 0.75
#endregion

#region Collocation
## Weight of the collocation term against favor error in a candidate's score.
var collocation_weight: float = 0.2
var collocation_rules: Array[CollocationRule] = [
	CollocationRule.of(MapFeature.Kind.POND, MapFeature.Kind.POND, -0.8, 30.0),
	CollocationRule.of(MapFeature.Kind.SHELTER, MapFeature.Kind.SHELTER, -0.8, 25.0),
	CollocationRule.of(MapFeature.Kind.BUILDING_CLUSTER, MapFeature.Kind.SHELTER, 1.0, 14.0),
	CollocationRule.of(MapFeature.Kind.BUILDING_CLUSTER, MapFeature.Kind.BUILDING_CLUSTER, -0.6, 18.0),
]
#endregion


## Defaults for `start_count` starts, one per alliance: the play-size bounds from the per-count
## table, when it has an entry.
static func for_start_count(start_count: int) -> MapGenerationParams:
	var params := MapGenerationParams.new()
	params.alliance_count = start_count
	var bounds: Vector2i = PLAY_SIZE_RANGE_BY_START_COUNT.get(
		start_count, Vector2i(params.play_size_min, params.play_size_max))
	params.play_size_min = bounds.x
	params.play_size_max = bounds.y
	return params


## Parameter values known to make generation fail, in words for whoever set them. Empty when
## none applies.
func warnings() -> PackedStringArray:
	var found := PackedStringArray()
	if last_pass < PASS_COUNT:
		found.append("Generation stops after pass %d of %d, %s."
			% [clampi(last_pass, 1, PASS_COUNT), PASS_COUNT, pass_name(last_pass)])
	if elevation_step > TerrainGrid.MAX_SLOPE_DIFF:
		found.append("A terrace step of %.2f is steeper than %.2f, so every terrace boundary "
			% [elevation_step, TerrainGrid.MAX_SLOPE_DIFF]
			+ "becomes a cliff and elevation will divide ground pass 4 left open.")
	if building_occupancy >= BUILDING_OCCUPANCY_FAILURE:
		found.append("Building occupancy of %d%% or more leaves no room: building placement "
			% roundi(BUILDING_OCCUPANCY_FAILURE * 100.0) + "will fail for lack of space.")
	return found


## A pass's name as the enum spells it, in prose: "terrain" for Pass.TERRAIN.
static func pass_name(a_pass: Pass) -> String:
	for name: String in Pass.keys():
		if Pass[name] == a_pass:
			return name.to_lower()
	return "pass %d" % a_pass


func start_count() -> int:
	return alliance_count * starts_per_alliance


func site_value() -> float:
	return site_energy_per_second * value_horizon_seconds


## A pond's value: its charge, capped at what it could pay out within the horizon.
func pond_value(a_charge: int) -> float:
	return minf(float(a_charge), site_energy_per_second * pond_rate_multiplier * value_horizon_seconds)
