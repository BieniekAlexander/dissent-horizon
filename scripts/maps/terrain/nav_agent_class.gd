class_name NavAgentClass

## Size classes used for baking space-eroded nav-meshes.
##
## One NavigationMesh (and one NavigationServer3D map) is baked per class, eroded
## for that class's radius; an agent navigates on the map for its class and avoids
## at its class radius. See nav-agent-size-classes.md for the full design and the
## research (StarCraft / AoE2 / clearance-based pathfinding) behind it.

## Collision size classes. Values are deliberately 1..4 (ordered by width).
enum Size {
	SMALL   = 1,  ## navs comfortably between cells
	MEDIUM  = 2,  ## fits single-file through a 1-cell hallway
	LARGE   = 3,  ## can only fit through 2-cell hallways
	MASSIVE = 4,  ## can only fit through 3-cell hallways
}

## World-space avoidance radius per class. Drives BOTH the space-erosion of the
## class's nav-mesh (below) and the agent's RVO radius. Tuned for Map.CELL_SIZE = 1.0:
## a corridor of world-width Wd admits radius r iff Wd >= 2*r (diameter).
const RADIUS: Dictionary = {
	Size.SMALL:   0.2,
	Size.MEDIUM:  0.4,
	Size.LARGE:   0.7,
	Size.MASSIVE: 1.3,
}


## World-space radius for a size class.
static func radius(size: Size) -> float:
	return RADIUS[size]


## The size class a unit of footprint `shape_radius` (e.g. its MovementBody radius)
## belongs to: the SMALLEST class whose radius is still >= shape_radius — the
## tightest class the unit fits within. A unit at radius 0.3 fits MEDIUM/LARGE/
## MASSIVE but is assigned MEDIUM (0.4), the smallest large-enough class. Units
## bigger than every class radius clamp to MASSIVE. (RADIUS ascends with enum
## order, so the first large-enough class is the smallest.)
static func class_for_radius(shape_radius: float) -> Size:
	for size: int in Size.values():
		if RADIUS[size] >= shape_radius:
			return size
	return Size.MASSIVE


## Whole-cell layers to strip around obstacles before building the class's mesh.
## floor(r/cs) — keeps big units cells away from obstacles and keeps the sub-cell
## inset from overshooting interior vertices. {SMALL,MEDIUM,LARGE}=0, MASSIVE=1.
static func erosion_rings(size: Size, cell_size: float) -> int:
	return maxi(0, ceili(RADIUS[size] / cell_size) - 1)


## Minimum corridor width, in whole cells, the class can traverse (the covering
## gate). ceil(2*r/cs) = ceil(diameter/cs). {SMALL,MEDIUM}=1, LARGE=2, MASSIVE=3.
static func required_clearance(size: Size, cell_size: float) -> int:
	return maxi(1, ceili(2.0 * RADIUS[size] / cell_size))


## Sub-cell distance (world units) to inset the built mesh's boundary vertices —
## the part of the radius not already covered by whole-cell ring-erosion. Always
## < cell_size, so the inset never overshoots an interior vertex.
static func inset(size: Size, cell_size: float) -> float:
	return RADIUS[size] - erosion_rings(size, cell_size) * cell_size
