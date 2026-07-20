class_name NavAgentClass

## Size classes used for baking space-eroded nav-meshes.
##
## One NavigationMesh (and one region on the shared NavigationServer3D map) is baked
## per class, eroded for that class's radius; an agent navigates on the mesh for its
## class. See nav-agent-size-classes.md for the full design and the research
## (StarCraft / AoE2 / clearance-based pathfinding) behind it.
##
## The classes ARE corridor-width tiers: the enum value is the corridor width, in
## whole cells, the class needs (SMALL=1, MEDIUM=2, LARGE=3). Everything else — the
## effective radius, the erosion, the admission gate — is derived from that tier and
## the cell size, so there is a single source of truth and the classification cutoff
## can never drift out of step with the erosion (the bug the old per-class RADIUS
## table caused, where a body a hair larger than a class radius jumped a whole tier).

#region Constants
## Collision size classes. The value IS the required corridor width in cells.
enum Size {
	SMALL  = 1,  ## fits a 1-cell corridor
	MEDIUM = 2,  ## needs a 2-cell corridor
	LARGE  = 3,  ## needs a 3-cell corridor
}

## Wall clearance (world units) every unit keeps from an obstacle. It is also the
## amount by which a class's effective radius sits below its corridor half-width, so
## after erosion the minimal corridor of a tier stays open by 2*CLEARANCE_MARGIN and
## a body never fills a corridor wall-to-wall (which would leave no room for steering
## / RVO and cause scraping). Larger = safer spacing but borderline bodies get pushed
## to a wider tier; smaller = tighter fits but more wall-scraping and float-boundary
## fragility. Must be < cell_size/2 so a class's radius stays positive and its tier
## is preserved. Tuned for Map.CELL_SIZE = 1.0.
const CLEARANCE_MARGIN: float = 0.05
#endregion

#region Public API
## Effective radius of a size class for cell size `cs`: the corridor half-width
## (tier * cs / 2) minus the clearance margin. This single value is BOTH the largest
## body radius the class admits (see class_for_radius) AND the distance the class's
## mesh is space-eroded (see erosion_rings / inset), so the two always agree.
static func radius(size: Size, cs: float) -> float:
	return int(size) * cs * 0.5 - CLEARANCE_MARGIN

## The size class a unit of footprint `shape_radius` belongs to: the smallest tier
## whose effective radius still covers it (so the body keeps CLEARANCE_MARGIN of wall
## room in that tier's minimal corridor). A body at 0.75 (cs=1) fails SMALL (0.45) and
## takes MEDIUM (0.95) — the 2-cell tier — matching a disc of diameter 1.5 needing 2
## cells. Bodies larger than LARGE's radius clamp to LARGE.
static func class_for_radius(shape_radius: float, cs: float) -> Size:
	for size: int in Size.values():
		if radius(size, cs) >= shape_radius:
			return size
	return Size.LARGE

## Minimum corridor width, in whole cells, the class can traverse — the covering gate
## (admit_k) fed to TerrainGrid.get_navigable_cells. This IS the tier: the enum value.
static func required_clearance(size: Size, _cs: float) -> int:
	return int(size)

## Whole-cell layers to strip around obstacles before building the class's mesh —
## the integer part of the erosion radius, floor(radius/cs). The sub-cell remainder
## is applied as a vertex inset. At cs=1: SMALL/MEDIUM=0, LARGE=1.
static func erosion_rings(size: Size, cs: float) -> int:
	return maxi(0, floori(radius(size, cs) / cs))

## Sub-cell distance (world units) to inset the built mesh's boundary vertices — the
## part of the erosion radius not covered by whole-cell ring-erosion. Always < cs
## (it is a remainder mod cs), so the inset never overshoots an interior vertex.
static func inset(size: Size, cs: float) -> float:
	return radius(size, cs) - erosion_rings(size, cs) * cs
#endregion
