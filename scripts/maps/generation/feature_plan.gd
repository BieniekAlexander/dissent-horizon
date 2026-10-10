@tool
class_name FeaturePlan
extends RefCounted

## A feature decided but not yet placed: its kind and everything that fixes its value, drawn
## BEFORE placement because value is what favor steering needs (map-generation.md §3).

#region Properties
var kind: MapFeature.Kind = MapFeature.Kind.SITE_CLUSTER
var value: float = 0.0
## Shelter: the one piece placed.
var piece: MapPiece = null
## A shelter ASSIGNED to a start: the index of that start in the generator's starts, whose
## distance band (MapGenerationParams.shelter_start_band_*) every candidate must lie in. -1 for a
## feature free to stand anywhere. Kept on the plan, so pass 4's re-placement honours it too.
var band_start: int = -1
## A shelter chosen to have a building cluster built around it (map-generation.md §Shelters
## and clusters). Decided after shelters are placed, before buildings are.
var hosts_cluster: bool = false
## A building cluster built around a shelter: that shelter's index in the generator's feature
## list, which pass 4 keeps stable while it replaces features. -1 for a free-standing cluster.
var host_index: int = -1
## A cluster: its members — sites placed edge to edge, or buildings grown in groupings.
var cluster_pieces: Array[MapPiece] = []
## Pond: the cell count to grow and the richness it is priced at.
var pond_cells: int = 0
var pond_richness: int = 0
#endregion
