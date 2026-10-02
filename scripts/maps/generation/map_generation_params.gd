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
## Garrison capacity per player at and above which building placement is known to run out of
## room on default 1v1 maps — measured, not derived; see map-generation.md §3.
const BUILDING_CAPACITY_FAILURE: int = 250
## Extra height on alternate ridge corners. Twice TerrainGrid.MAX_SLOPE_DIFF, so a ridge's top
## is as unwalkable as its sides — a flat crest would be a plateau nothing can reach — with margin
## for pass 6's offsets. Derived because it is a passability rule, not a look: it scales with the
## slope limit, where ridge_height is free to be tuned by eye.
const RIDGE_ROUGHNESS: float = TerrainGrid.MAX_SLOPE_DIFF * 2.0
## Extra height on alternate corners of a cliff's talus apron and crest: over the slope limit, so
## no cell of the band can be stood on, and half again for margin, but far under a ridge so the
## band does not hide the face it flanks.
const TALUS_ROUGHNESS: float = TerrainGrid.MAX_SLOPE_DIFF * 1.5
## The last pass there is. Derived from the enum, so adding a pass moves it.
const PASS_COUNT: int = Pass.VISUALS
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
		properties =
		[
			"starts_per_alliance",
			"start_min_center_fraction",
			"start_angle_jitter_fraction",
			"start_clear_radius_cells",
			"start_edge_margin_cells",
			"start_separation_diagonal_fraction",
			"start_attempts",
		],
	},
	{
		name = "Value",
		properties =
		[
			"site_energy_per_second",
			"pond_rate_multiplier",
			"value_horizon_seconds",
			"energy_value_per_player",
			"pond_value_fraction",
		],
	},
	{
		name = "Ponds",
		properties =
		[
			"pond_charge_min",
			"pond_charge_max",
			"pond_charge_location",
			"pond_charge_scale",
			"pond_charge_skew",
			"pond_cells_min",
			"pond_cells_max",
			"pond_richness_factors",
			"pond_richness_weights",
			"pond_richness_cells_min",
			"pond_richness_cells_max",
		],
	},
	{
		name = "Shelters",
		properties = ["shelters_per_alliance_min", "shelters_per_alliance_extra"],
	},
	{
		name = "Buildings",
		properties =
		[
			"building_capacity_per_player",
			"cluster_capacity_band_edges",
			"cluster_capacity_band_weights",
			"cluster_capacity_overshoot",
			"cluster_large_building_bias",
			"cluster_packing_density",
			"building_cluster_separation_cells",
			"building_pool",
		],
	},
	{
		name = "Extraction sites",
		properties =
		[
			"site_triple_fraction_min",
			"site_triple_fraction_max",
			"site_pair_fraction_min",
			"site_pair_fraction_max",
			"site_cluster_separation_cells",
		],
	},
	{name = "Pieces", properties = ["site_piece", "shelter_piece"]},
	{
		name = "Favor and placement",
		properties =
		[
			"favor_concentration",
			"favor_tolerance",
			"placement_candidates",
			"candidate_draw_factor",
			"feature_spacing_cells",
			"footprint_gap_cells",
		],
	},
	{
		name = "Topology and terrain",
		properties =
		[
			"cut_fraction",
			"flooded_cut_fraction",
			"barrier_width_cells",
			"min_routes",
			"correction_radius_cells",
			"ridge_height",
			"chasm_depth",
			"flat_fraction",
		],
	},
	{
		name = "Obstacle regions",
		properties =
		[
			"target_traversable_fraction",
			"traversable_tolerance",
			"open_gap_cells",
			"max_obstacle_span_fraction",
			"region_width_min_cells",
			"region_width_max_cells",
			"region_edge_noise",
			"region_noise_scale_cells",
			"region_lake_fraction",
			"lake_shelf_cells",
			"mountain_rise_per_cell",
			"mountain_rise_max",
			"obstruction_tolerance",
		],
	},
	{
		name = "Elevation",
		properties =
		[
			"elevation_levels",
			"elevation_step",
			"cliff_cut_fraction",
			"cliff_drop_terraces_min",
			"cliff_drop_terraces_max",
			"occlusion_allowance",
			"elevation_scale_cells",
			"start_level_fraction_min",
			"start_level_fraction_max",
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
	"play_size_min":
	"Smallest play-area sides (s, t), in diamonds. Each axis is drawn between its min and max.",
	"play_size_max": "Largest play-area sides (s, t), in diamonds. Equal to min pins the size.",
	"ground_height": "Height of the flat ground. It must leave room for a chasm to sink below it.",
	"alliance_count": "Number of alliances. Changing it resets the defaults that depend on it.",
	"starts_per_alliance": "Starting positions each alliance gets.",
	"start_min_center_fraction":
	"Least distance of a start from the map centre, as a fraction of the side.",
	"start_angle_jitter_fraction":
	"How far starts wander from even angular spacing, as a fraction of it.",
	"start_clear_radius_cells": "Half-width of the flat, empty box kept around each start.",
	"start_edge_margin_cells": "Least distance of a start from the edge of the play area.",
	"start_separation_diagonal_fraction":
	"Least distance between starts, as a fraction of the play diagonal.",
	"start_attempts": "How many start layouts to try before generation fails.",
	"site_energy_per_second": "An extraction site's income. Read from the piece, not edited here.",
	"pond_rate_multiplier":
	"A pond's rate as a multiple of a site's. Read from the game, not edited here.",
	"value_horizon_seconds":
	(
		"The time window a pond's value is compared with a site's over. Match it to the "
		+ "largest pond's drain time, or large ponds are undervalued."
	),
	"energy_value_per_player":
	(
		"Total energy value the map places per player, so a team game gives every player "
		+ "as much as a duel."
	),
	"pond_value_fraction": "Share of the energy value placed as ponds rather than sites.",
	"pond_charge_min": "Smallest pond's energy: about 3 minutes for one extractor.",
	"pond_charge_max": "Largest pond's energy: about 8 minutes for one extractor.",
	"pond_charge_location": "Centre of the pond-charge draw, in energy.",
	"pond_charge_scale": "Spread of the pond-charge draw, in energy.",
	"pond_charge_skew": "Skew of the pond-charge draw. Positive makes small ponds more common.",
	"pond_cells_min": "Smallest pond any category may make, in cells.",
	"pond_cells_max": "Largest pond any category may make, in cells.",
	"pond_richness_factors":
	(
		"Charge per cell for each pond richness category. A pond's size is its charge "
		+ "over its richness, so rich ponds are compact."
	),
	"pond_richness_weights":
	"How often each richness category is drawn, among those that can hold the charge.",
	"pond_richness_cells_min": "Smallest pond of each richness category, in cells.",
	"pond_richness_cells_max":
	"Largest pond of each richness category, in cells. Caps how large a rich pond grows.",
	"shelters_per_alliance_min": "Fewest shelters per alliance.",
	"shelters_per_alliance_extra": "Random extra shelters per alliance, on top of the minimum.",
	"building_capacity_per_player":
	(
		"Total garrison capacity of the neutral buildings placed per player. Too high "
		+ "and placement runs out of room."
	),
	"cluster_capacity_band_edges":
	"Garrison-capacity bands a cluster's size is drawn from: band i runs from edge i to edge i+1.",
	"cluster_capacity_band_weights":
	"How often each capacity band is drawn. Falling band by band, so small clusters are common.",
	"cluster_capacity_overshoot":
	"How far a cluster's last building may carry it past its drawn capacity.",
	"cluster_large_building_bias":
	(
		"How much a large cluster favours large buildings. 0 draws every cluster from "
		+ "the pool's own weights."
	),
	"cluster_packing_density":
	"How tightly a cluster's buildings are packed. Lower spreads them out.",
	"building_cluster_separation_cells": "Least gap between buildings of two different clusters.",
	"building_pool": "The neutral buildings a cluster draws from.",
	"site_triple_fraction_min": "Least share of extraction sites standing in groups of three.",
	"site_triple_fraction_max": "Greatest share of extraction sites standing in groups of three.",
	"site_pair_fraction_min": "Least share of extraction sites standing in pairs.",
	"site_pair_fraction_max": "Greatest share of extraction sites standing in pairs.",
	"site_cluster_separation_cells": "Least gap between sites of two different site groups.",
	"site_piece": "The extraction-site piece and its footprint.",
	"shelter_piece": "The shelter piece and its footprint.",
	"favor_concentration":
	"How evenly each feature is shared between alliances. Lower lets features lean one way.",
	"favor_tolerance": "How far an alliance's share of value may stray from fair, as a fraction.",
	"placement_candidates":
	"Candidate spots scored for each feature. More is slower but better placed.",
	"candidate_draw_factor": "Draws allowed per candidate before placement stops looking.",
	"feature_spacing_cells": "Least centre-to-centre distance between features.",
	"footprint_gap_cells": "Clear cells kept between any two structures.",
	"cut_fraction": "Share of connections between features blocked by a ridge or chasm.",
	"flooded_cut_fraction":
	"Share of blocked connections that are water chasms rather than ridges.",
	"barrier_width_cells": "Rough thickness of a ridge or chasm.",
	"min_routes": "Separate routes every start keeps to every other start.",
	"correction_radius_cells":
	"How far a feature may move to rebalance once barriers lengthen paths.",
	"ridge_height": "How high a ridge rises above the ground.",
	"chasm_depth": "How deep a chasm sinks below the ground. Its water fills half of it.",
	"target_traversable_fraction":
	"Share of the play area left traversable. Cuts grow into mountains and lakes until it is reached.",
	"traversable_tolerance":
	"How far a finished map's traversable share may sit from the target before the map is rejected.",
	"max_obstacle_span_fraction":
	"Largest share of either side of the map one mass of mountains and lakes may span.",
	"open_gap_cells": "Narrowest gap kept between two obstacles, or an obstacle and the map edge.",
	"region_width_min_cells":
	"Narrowest a grown cut reaches from equidistant between its two nodes.",
	"region_width_max_cells": "Widest a grown cut reaches from equidistant between its two nodes.",
	"region_edge_noise": "How ragged a region's edge is, as a fraction of its width.",
	"region_noise_scale_cells": "Size of the bumps along a region's edge.",
	"region_lake_fraction": "Share of grown area that is lakes rather than mountains.",
	"lake_shelf_cells": "Width of the shallow, wadeable shelf around a lake's deep core.",
	"mountain_rise_per_cell": "How much a mountain rises for each cell further from its edge.",
	"mountain_rise_max": "The most a mountain rises above an ordinary ridge.",
	"obstruction_tolerance":
	"How unevenly impassable ground may fall between alliances before the map is rejected.",
	"flat_fraction": "Least share of walkable ground that must be flat enough to build on.",
	"elevation_levels": "Terrace levels the ground steps through. 1 keeps the ground level.",
	"elevation_step":
	(
		"Height of one terrace step. Keep it under the walkable slope limit, or every "
		+ "step becomes a cliff."
	),
	"cliff_cut_fraction":
	"Share of eligible barriers realised as cliffs rather than ridges or rivers.",
	"cliff_drop_terraces_min": "Smallest cliff drop, in terrace steps.",
	"cliff_drop_terraces_max": "Largest cliff drop, in terrace steps.",
	"occlusion_allowance":
	"How much of a unit at a mountain's foot the mountain may hide. Masses rise from there.",
	"elevation_scale_cells": "Size of the highs and lows, in cells. Larger gives broader ones.",
	"start_level_fraction_min": "Lowest the starts' shared terrace can be (0 bottom, 1 top).",
	"start_level_fraction_max": "Highest the starts' shared terrace can be (0 bottom, 1 top).",
	"collocation_weight":
	"How much the feature-neighbour rules count against fairness when placing.",
	"collocation_rules":
	"Which feature kinds attract or repel one another, and over what distance.",
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
	VISUALS = 7,
}

## The last pass to run: an earlier stop leaves the map as that pass left it, so each pass can
## be inspected alone. Passes run in order and none can be skipped.
var last_pass: Pass = Pass.VISUALS
#endregion

#region Extent
## Default play-size bounds by start count: [min, max], each (s, t) in diamonds. A heuristic
## starting point. TODO: only two players have a range, and it is untuned (map-generation.md
## §Parameters).
const PLAY_SIZE_RANGE_BY_START_COUNT: Dictionary = {
	2: [Vector2i(100, 100), Vector2i(120, 120)],
}

## The play rectangle's s side is drawn uniformly in [min.x, max.x] diamonds and its t side in
## [min.y, max.y]; the corner grid is derived from the result (TerrainData). Equal bounds pin
## the size, and unequal axes shape a long map.
var play_size_min: Vector2i = Vector2i(100, 100)
var play_size_max: Vector2i = Vector2i(120, 120)
## Height of the flat ground: high enough that a chasm sunk chasm_depth into it stays inside
## the brush's height range (0 and up).
var ground_height: float = 8.0
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
var site_energy_per_second: float = 5.0
## A pond's rate as a multiple of a site's (WaterBody.POND_RATE_MULTIPLIER, set by the shell).
var pond_rate_multiplier: float = 3.0
## The window a pond is priced against a site over (map-generation.md §Energy value). It is the
## largest pond's drain time, so every pond is valued at its full charge.
var value_horizon_seconds: float = 480.0
## Per PLAYER, so a team game gives each player as much as a duel; placement still balances
## access per alliance. Ponds take 25000 of it (5-6 ponds) and sites the rest: about five
## generated sites at 5/s x 480 s = 2400 each, beside the two home sites
## (pacing/resource-allotment.md §Second pass).
var energy_value_per_player: float = 37000.0
## Share of the energy budget spent on ponds.
var pond_value_fraction: float = 0.676
#endregion

#region Ponds
## A pond's energy is drawn first, from a right-skewed normal over [min, max]: 2700-7200 is 3 to 8
## minutes for one extractor at 15/s (pacing/resource-allotment.md §Second pass).
var pond_charge_min: int = 2700
var pond_charge_max: int = 7200
var pond_charge_location: float = 3500.0
var pond_charge_scale: float = 2000.0
var pond_charge_skew: float = 4.0
## Bounds on any pond's size, whatever its category: the union of the per-category bounds.
var pond_cells_min: int = 30
var pond_cells_max: int = 80
## Richness categories (poor, standard, rich): charge per cell, base draw weight, and size bounds.
## A pond's cells are its charge over its richness, so the category is drawn only among those
## whose bounds can hold the charge, and a rich pond is compact: easy to hold, quick to lose.
var pond_richness_factors: PackedInt32Array = PackedInt32Array([60, 90, 120])
var pond_richness_weights: PackedFloat32Array = PackedFloat32Array([0.35, 0.45, 0.2])
var pond_richness_cells_min: PackedInt32Array = PackedInt32Array([45, 30, 30])
var pond_richness_cells_max: PackedInt32Array = PackedInt32Array([80, 70, 60])
#endregion

#region Shelters
## Shelter count = round(alliances x (min + extra x randf())).
var shelters_per_alliance_min: float = 1.0
var shelters_per_alliance_extra: float = 1.5
#endregion

#region Buildings
## Total garrison capacity of the neutral buildings, per PLAYER like the energy budget. 75 is
## about seven clusters per player at the bands below, which is what their stated frequencies
## assume. From BUILDING_CAPACITY_FAILURE up, placement runs out of room (see warnings()).
var building_capacity_per_player: int = 75
## A cluster is sized by GARRISON CAPACITY, not building count, because the buildings differ:
## a band is drawn by weight, then a capacity uniformly within it. Up to 10 is about half of all
## clusters, 10-15 about a third, 15-20 about one per two players and 20-25 about one match in
## three (map-generation.md §Buildings).
var cluster_capacity_band_edges: PackedInt32Array = PackedInt32Array([3, 10, 15, 20, 25])
var cluster_capacity_band_weights: PackedFloat32Array = PackedFloat32Array([0.55, 0.36, 0.07, 0.02])
## A building is drawn only if it lands the cluster at most this far past its capacity.
var cluster_capacity_overshoot: int = 2
## A building's draw weight is scaled by capacity^(bias × t), t the cluster's capacity across the
## bands in [0, 1]: a small cluster draws from the pool as weighted, a large one leans large.
var cluster_large_building_bias: float = 0.5
## Fraction of a cluster's disc its buildings fill, gap included. The scatter radius is
## derived from it, so a cluster of eight spreads wider than a cluster of three.
var cluster_packing_density: float = 0.35
## Least L1 distance, in cells, between the nearest buildings of two different clusters —
## what keeps neighbouring clusters from reading as one.
var building_cluster_separation_cells: int = 20
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
## Share of feature-graph edges cut by a barrier. 0.45, the top of its bracket, because only
## uncarved cuts grow into obstacle regions, and at 0.3 growing every one of them still left
## 81-88% of a 1v1 map traversable, short of the old 80% target. TODO: not re-measured at 85%.
var cut_fraction: float = 0.45
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
var chasm_depth: float = 4.0
## Least share of in-play dry walkable cells that must be buildable (all corners level).
var flat_fraction: float = 0.55
#endregion

#region Obstacle regions (pass 4, shaped in pass 5)
## The finished map's traversable share: in play, not steep, not deep water, not a footprint.
## Shallow water counts as traversable (map-generation.md §Obstacle regions).
var target_traversable_fraction: float = 0.85
var traversable_tolerance: float = 0.025
## Pass 4 trims an obstacle back until every gap it leaves — to another obstacle, or to the play
## edge — is at least this wide, so masses either merge or stand well apart. Trimmed to
## MIN_CHOKE_WIDTH instead, the floor became the commonest passage width (map-generation.md
## §Openness). Carves and ramps are still MIN_CHOKE_WIDTH and up: the deliberate chokes.
var open_gap_cells: float = 20.0
## No obstacle mass's bounding box, in the play area's own axes, spans more than this share of
## either side: a larger one is a long walk round for ground units and hands the map to air.
var max_obstacle_span_fraction: float = 0.3
## A grown cut keeps its Voronoi band out to a gap drawn in [min, max]: the cells whose two
## nearest nodes are the cut's pair, at most that much closer to one than the other.
var region_width_min_cells: float = 8.0
var region_width_max_cells: float = 22.0
## The gap is scaled by 1 + noise × this, from coherent noise this many cells across, so an
## edge is ragged rather than following the Voronoi boundary exactly.
var region_edge_noise: float = 0.35
var region_noise_scale_cells: float = 12.0
## Cuts are grown as lakes (flooded) or mountains (ridges) to keep this share of grown cells lakes.
var region_lake_fraction: float = 0.5
## A lake's deep core is ringed by this many cells sunk to a pond's pan: shallow, wadeable water.
var lake_shelf_cells: int = 2
## A mountain cell rises this much per cell of distance from the region's edge, up to the max.
var mountain_rise_per_cell: float = 0.5
var mountain_rise_max: float = 2.0
## Worst relative deviation of any alliance's share of impassable ground from even.
var obstruction_tolerance: float = 0.15
#endregion

#region Elevation (pass 6)
## Terrace levels the ground steps through, 0 lowest; 1 leaves the ground level. The map's whole
## relief: regions a walker can cross between differ by at most one, and a cliff is where a cut's
## sides end several apart (map-generation.md §6).
var elevation_levels: int = 6
## Height between neighbouring terrace levels. **Keep it at or under TerrainGrid.MAX_SLOPE_DIFF**:
## a terrace step is meant to be walked over, so elevation may not divide ground that pass 4
## left open. Only the cells on the step lose their buildability.
var elevation_step: float = 0.5
## Share of the eligible cuts — thin, uncarved, and not already crossed on foot — pass 6 tries to
## realise as cliffs rather than as the ridge or river pass 4 drew. One whose sides cannot be
## held far enough apart stays a ridge or river.
var cliff_cut_fraction: float = 0.5
## A cliff's drop in terrace steps, drawn per cliff. At least two, or the step would be walked
## over; at most what the way round can climb a terrace per region, and what the apron hides.
var cliff_drop_terraces_min: int = 2
var cliff_drop_terraces_max: int = 4
## How much of a unit standing at an obstacle's foot the obstacle may hide, in height. An
## obstacle cell may stand at most this plus its distance from walkable ground times the tangent
## of the lowest camera pitch above that ground, so masses rise toward their middle.
var occlusion_allowance: float = 0.5
## Size of the noise features that decide levels, in cells: larger gives broad highs and lows.
var elevation_scale_cells: float = 60.0
## The band of the terrace range the starts' shared level is drawn from: 0 lowest, 1 highest.
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
	CollocationRule.of(
		MapFeature.Kind.BUILDING_CLUSTER, MapFeature.Kind.BUILDING_CLUSTER, -0.6, 18.0
	),
]
#endregion


## Defaults for `start_count` starts, one per alliance: the play-size bounds from the per-count
## table, when it has an entry.
static func for_start_count(start_count: int) -> MapGenerationParams:
	var params := MapGenerationParams.new()
	params.alliance_count = start_count
	var bounds: Array = PLAY_SIZE_RANGE_BY_START_COUNT.get(
		start_count, [params.play_size_min, params.play_size_max]
	)
	params.play_size_min = bounds[0]
	params.play_size_max = bounds[1]
	return params


## Parameter values known to make generation fail, in words for whoever set them. Empty when
## none applies.
func warnings() -> PackedStringArray:
	var found := PackedStringArray()
	if last_pass < PASS_COUNT:
		found.append(
			(
				"Generation stops after pass %d of %d, %s."
				% [clampi(last_pass, 1, PASS_COUNT), PASS_COUNT, pass_name(last_pass)]
			)
		)
	if play_size_min.x > play_size_max.x or play_size_min.y > play_size_max.y:
		found.append(
			(
				"The play-size minimum %s exceeds the maximum %s on an axis."
				% [play_size_min, play_size_max]
			)
		)
	if elevation_step > TerrainGrid.MAX_SLOPE_DIFF:
		found.append(
			(
				(
					"A terrace step of %.2f is steeper than %.2f, so every terrace boundary "
					% [elevation_step, TerrainGrid.MAX_SLOPE_DIFF]
				)
				+ "becomes a cliff and elevation will divide ground pass 4 left open."
			)
		)
	if not energy_value_per_player > 0.0:
		found.append(
			(
				(
					"An energy value per player of %s places no ponds or sites, so generation "
					% energy_value_per_player
				)
				+ "will fail."
			)
		)
	if building_capacity_per_player >= BUILDING_CAPACITY_FAILURE:
		found.append(
			(
				(
					"A building capacity of %d or more per player leaves no room: building "
					% BUILDING_CAPACITY_FAILURE
				)
				+ "placement will fail for lack of space."
			)
		)
	found.append_array(_cliff_warnings())
	return found


## A cliff must step more than a walker can, and must hide no walkable ground: the ground a drop
## hides from the lowest camera pitch has to fall on its own apron and steep border.
func _cliff_warnings() -> PackedStringArray:
	var found := PackedStringArray()
	if cliff_drop_terraces_min > cliff_drop_terraces_max:
		found.append("The smallest cliff drop exceeds the largest.")
	if cliff_drop_terraces_min * elevation_step <= TerrainGrid.MAX_SLOPE_DIFF:
		found.append(
			(
				"A cliff drop of %d terraces is walkable, so the smallest cliffs will not divide."
				% cliff_drop_terraces_min
			)
		)
	var hidden_cells: float = (
		cliff_drop_terraces_max
		* elevation_step
		/ tan(deg_to_rad(TerrainGrid.MIN_VIEW_PITCH_DEGREES))
	)
	if hidden_cells > barrier_width_cells + 1.0:
		(
			found
			. append(
				(
					(
						"A %d-terrace cliff hides %.1f cells behind it, past its %.0f-cell apron: units "
						% [cliff_drop_terraces_max, hidden_cells, barrier_width_cells + 1.0]
					)
					+ "below it can be hidden."
				)
			)
		)
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
	return minf(
		float(a_charge), site_energy_per_second * pond_rate_multiplier * value_horizon_seconds
	)
