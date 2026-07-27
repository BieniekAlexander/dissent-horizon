@tool
class_name CollocationRule
extends RefCounted

## How much a feature of one kind wants to stand near an already-placed feature of another
## (map-generation.md §Collocation). Positive pulls, negative pushes, and only features within
## `radius_cells` of the candidate count.

#region Properties
var placing: MapFeature.Kind = MapFeature.Kind.SITE_CLUSTER
var placed: MapFeature.Kind = MapFeature.Kind.SITE_CLUSTER
## In [-1, 1].
var affinity: float = 0.0
var radius_cells: float = 0.0
#endregion


static func of(
	placing: MapFeature.Kind, placed: MapFeature.Kind, affinity: float, radius_cells: float
) -> CollocationRule:
	var rule := CollocationRule.new()
	rule.placing = placing
	rule.placed = placed
	rule.affinity = affinity
	rule.radius_cells = radius_cells
	return rule
