@tool
class_name MapDecoration
extends RefCounted

## What pass 7 (visual facets) derives for one map: ground paint, doodads, and the facet sites
## later decoration will dress. Purely cosmetic — nothing here is read by gameplay — and never
## saved: MapDecorationPlanner rebuilds it from the map whenever it is needed.

#region Enums
## A place the terrain implies a piece of set dressing that does not exist yet. Detected now so
## the shapes can be reviewed and the dressing built later without re-deriving where it goes.
## PLANNED: each kind gets real dressing — see visual-facets.md §Shortlist.
enum Facet { CLIFF_FACE, SHORE, WATERFALL, MOUNTAIN, RAMP }
#endregion

#region Properties
## Per-cell ground paint, grid_width x grid_depth, RGBA8: R meadow, G trail, B scree, A shore.
## Read by the terrain shader (terrain_common.gdshaderinc), linearly filtered.
var ground_overlay: Image = null
## Every doodad placed, as DoodadPlacement.
var doodads: Array[DoodadPlacement] = []
## The routed trails, each a list of cells from one settlement to another.
var trails: Array[PackedVector2Array] = []
## Facet -> Array[Vector2i] of the cells where that dressing would go.
var facets: Dictionary = {}
#endregion


func doodad_count(kind: DoodadLibrary.Kind) -> int:
	return doodads.filter(func(d: DoodadPlacement) -> bool: return d.kind == kind).size()


## One line per non-empty category, for a generation report.
func summary() -> String:
	var parts: PackedStringArray = []
	parts.append("%d doodads" % doodads.size())
	parts.append("%d trails" % trails.size())
	for facet: Facet in facets:
		parts.append("%d %s cells" % [(facets[facet] as Array).size(),
			String(Facet.keys()[facet]).to_lower()])
	return ", ".join(parts)
