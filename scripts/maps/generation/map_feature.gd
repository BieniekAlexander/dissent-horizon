@tool
class_name MapFeature
extends RefCounted

## One thing the generator put on the map: a cluster of extraction sites, a pond, a shelter,
## or a building cluster.
##
## A feature is what favor is measured on, so a CLUSTER is one feature — its members are placed
## together and share its target (gdd/systems/terrain-and-navigation/
## map-generation.md §3). Positions are continuous cell-space: cell (x, z) spans
## [x, x+1] x [z, z+1], so a cell's centre is (x + 0.5, z + 0.5).

#region Enums
enum Kind { SITE_CLUSTER, POND, SHELTER, BUILDING_CLUSTER }

## Each currency is balanced on its own; see map-generation.md §Currencies. Sites and ponds
## both yield energy but are balanced apart, so neither alliance gets the ponds while the other
## gets the sites.
enum Currency { SITE_ENERGY, POND_ENERGY, SHELTER, BUILDINGS }
#endregion

#region Properties
var kind: Kind = Kind.SITE_CLUSTER

## Where favor is measured from: the footprint centre, a pond's cell centroid, or a cluster's
## centre.
var center: Vector2 = Vector2.ZERO

## Value in this feature's currency (map-generation.md §Currencies).
var value: float = 0.0

## The access share per alliance this feature was AIMED at, and the one it landed on.
var target_share: PackedFloat32Array = PackedFloat32Array()
var realised_share: PackedFloat32Array = PackedFloat32Array()

## The structures this feature places: one for a shelter, one or more for a cluster, none for
## a pond. Each is {piece: MapPiece, origin: Vector2i, quarter_turns: int} — origin the min-x/min-z
## cell of the TURNED footprint (placement_rect), quarter_turns as Fixture.quarter_turns and 0
## when absent.
var placements: Array[Dictionary] = []

## The plan this feature was placed from, so pass 4 can place it again elsewhere.
var plan: FeaturePlan = null

## A pond's flooded cells. Empty for anything else.
var pond_cells: Array[Vector2i] = []
## A pond's energy charge, and the richness factor it was priced with.
var pond_charge: int = 0
var pond_richness: int = 0
## The cell a WaterBody floods the pond from, and the water level it floods to.
var pond_seed_cell: Vector2i = Vector2i.ZERO
var pond_level: float = 0.0
#endregion


func currency() -> Currency:
	match kind:
		Kind.SHELTER:
			return Currency.SHELTER
		Kind.BUILDING_CLUSTER:
			return Currency.BUILDINGS
		Kind.POND:
			return Currency.POND_ENERGY
	return Currency.SITE_ENERGY


## For two alliances, the signed favor toward alliance 0: +1 on its start, 0 even. See
## map-generation.md §Favor.
func realised_favor() -> float:
	return realised_share[0] - realised_share[1] if realised_share.size() == 2 else 0.0


func target_favor() -> float:
	return target_share[0] - target_share[1] if target_share.size() == 2 else 0.0


## The cells one placement claims: its piece's footprint, turned by its quarter turns.
static func placement_rect(placement: Dictionary) -> Rect2i:
	return Rect2i(
		placement.origin,
		Fixture.oriented_dimensions(
			(placement.piece as MapPiece).footprint, placement.get("quarter_turns", 0)
		)
	)


## Every cell a structure of this feature stands on.
func structure_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for rect: Rect2i in footprints():
		cells.append_array(PlacementGrid.rect_cells(rect.position, rect.size))
	return cells


## Every structure's footprint, in cells.
func footprints() -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	for placement: Dictionary in placements:
		rects.append(placement_rect(placement))
	return rects
