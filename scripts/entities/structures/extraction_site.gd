class_name ExtractionSite
extends Node

## Extraction-site component: marks its host — a neutral, walkable, terrain-grid-occupying
## feature — as an inexhaustible supply of lithium, which a player works by building an
## extractor "on top of" it. The host stays the cells' occupant; the extractor overlays it and
## is what obstructs them, and the two hold mutual references (see Extractor).
##
## A component rather than the host's class, like Shelter: the host is a plain Entity, and
## "is this an extraction site" is the presence of this node (`ExtractionSite.of`).

#region Properties
## The extractor PIECE working this site, or null while the site is open. The single source
## of truth for "is this site already worked" — EnergyExtractor's placement check forbids a
## second, and the extractor clears it when it goes so the site becomes workable again.
var extractor: Commandable = null:
	set(value):
		extractor = value
		# Hide the site's model while an extractor covers it (the extractor's own model shows
		# on top); reveal it again when released.
		var mesh_visual: Node3D = get_parent().get_node_or_null("MeshVisual") as Node3D \
			if get_parent() != null else null
		if mesh_visual != null:
			mesh_visual.visible = value == null
#endregion

#region Public API
## `a_node`'s ExtractionSite component, or null when it is not an extraction site (or is
## gone). Untyped because a caller may hold a freed reference.
static func of(a_node: Variant) -> ExtractionSite:
	if a_node == null or not is_instance_valid(a_node) or not (a_node is Node):
		return null
	return (a_node as Node).get_node_or_null("ExtractionSite") as ExtractionSite


## The site piece this component marks.
func host() -> Entity:
	return get_parent() as Entity
#endregion
