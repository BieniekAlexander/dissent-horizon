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
## A cluster: its members — sites placed edge to edge, or buildings packed around a centre.
var cluster_pieces: Array[MapPiece] = []
## Pond: the cell count to grow and the richness it is priced at.
var pond_cells: int = 0
var pond_richness: int = 0
#endregion
