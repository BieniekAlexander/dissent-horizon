@tool
class_name Extractor
extends Node

## Extractor component: its host, an energy-extracting structure, works a lithium source
## rather than occupying fresh ground. On an extraction site it OVERLAYS the site — the site
## stays the cells' occupant, the extractor registers the same footprint and is what
## obstructs it, and the two hold mutual references (Map.add_structure routes this); in a
## lithium pond it occupies its own cells and claims the body instead. The host's
## EnergyExtractor does the actual collection.
##
## A component rather than the host's class, like Shelter; `Extractor.of` finds it.

#region Properties
## The extraction-site PIECE this extractor works. Set by the build path at runtime
## (Map.add_structure) or authored in a scene (and auto-created by the editor helper below).
@export var extraction_site: Entity

## Site Selectable/TargetBody shapes disabled on bind, remembered so restoration re-enables
## exactly those (and not any disabled for another reason).
var _site_disabled_shapes: Array[CollisionShape3D] = []
#endregion


#region Public API
## `a_node`'s Extractor component, or null. Untyped because a caller may hold a freed
## reference.
static func of(a_node: Variant) -> Extractor:
	if a_node == null or not is_instance_valid(a_node) or not (a_node is Node):
		return null
	return (a_node as Node).get_node_or_null("Extractor") as Extractor


## The extractor piece this component belongs to.
func host() -> Commandable:
	return get_parent() as Commandable


## Link the host to its site, both directions. The host OVERLAYS the site and becomes the
## interactive entity at that cell — it must stay selectable and targetable — so the site's
## own Selectable and TargetBody are suppressed until the host goes (see _release).
func bind_extraction_site(a_site: Entity) -> void:
	extraction_site = a_site
	var site: ExtractionSite = ExtractionSite.of(a_site)
	if site != null:
		site.extractor = host()
		_set_site_interaction_disabled(true)


## Point the host's collection at the lithium pond it stands in. A pond is not a host to
## overlay — the extractor occupies its own cells there — so the binding only says where the
## energy comes from and how fast (WaterBody.extract), and claims the body: one extractor per
## body, the pond-side counterpart of the site claim. A null body leaves the inexhaustible
## default.
func bind_water_body(a_body: WaterBody) -> void:
	if a_body == null:
		return
	var collector: EnergyExtractor = (
		get_parent().get_node_or_null("EnergyExtractor") as EnergyExtractor
	)
	if collector != null:
		collector.reservoir = a_body
	a_body.extractor = host()


#endregion


#region Lifecycle
func _ready() -> void:
	if Engine.is_editor_hint():
		# Defer so the host's owner/parent are settled before we add a sibling.
		call_deferred(&"_ensure_editor_extraction_site")
		return
	host().entity_occurrence.connect(_on_host_occurrence)


func _on_host_occurrence(a_occurrence: Entity.EntityOccurrence, _a_source: Entity) -> void:
	if a_occurrence == Entity.EntityOccurrence.ON_DEATH:
		_release()


## The site is never removed from the grid; release it so it can be worked again, restoring
## the interaction colliders suppressed while overlaying it — and release the pond too, so a
## destroyed extractor leaves its body workable.
func _release() -> void:
	var site: ExtractionSite = ExtractionSite.of(extraction_site)
	if site != null:
		_set_site_interaction_disabled(false)
		site.extractor = null
	var collector: EnergyExtractor = (
		get_parent().get_node_or_null("EnergyExtractor") as EnergyExtractor
	)
	if collector != null:
		# Read into a Variant first: `reservoir` is typed WaterBody, and a typed read of a
		# freed object errors before any guard can run (CLAUDE.md §A freed object cannot be
		# passed to a typed parameter).
		var pond: Variant = collector.reservoir
		if pond != null and is_instance_valid(pond):
			(pond as WaterBody).extractor = null


#endregion


#region Extraction-site overlay
## Suppress (or restore) the site's interaction colliders — the CollisionShape3Ds under its
## Selectable (SELECTION layer) and TargetBody (TARGETABLE layer) — so the overlaying host is
## the sole click/attack target. The site's grid and movement presence is left untouched.
## Editor-inert.
func _set_site_interaction_disabled(a_disabled: bool) -> void:
	if Engine.is_editor_hint() or not is_instance_valid(extraction_site):
		return
	if a_disabled:
		for shape: CollisionShape3D in _site_interaction_shapes():
			if not shape.disabled:
				shape.disabled = true
				_site_disabled_shapes.append(shape)
	else:
		for shape: CollisionShape3D in _site_disabled_shapes:
			if is_instance_valid(shape):
				shape.disabled = false
		_site_disabled_shapes.clear()


## The site's SELECTION + TARGETABLE CollisionShape3Ds; a missing component is skipped.
func _site_interaction_shapes() -> Array[CollisionShape3D]:
	var result: Array[CollisionShape3D] = []
	for component: Node in [extraction_site.selectable, extraction_site.target_body]:
		if component != null:
			for node: Node in component.find_children("*", "CollisionShape3D", true, false):
				result.append(node as CollisionShape3D)
	return result


#endregion


#region Editor helpers
## When an extractor is authored into a scene without a site, auto-create a linked site
## sibling of the host at the same spot so the extractor is valid. Guarded on
## extraction_site == null so it runs once and never fights the user.
func _ensure_editor_extraction_site() -> void:
	if not Engine.is_editor_hint() or extraction_site != null:
		return
	var extractor_piece: Node3D = get_parent() as Node3D
	# owner == null means the extractor piece is itself the scene being edited, not an
	# instance placed inside another scene — nothing to attach to.
	if (
		extractor_piece == null
		or extractor_piece.owner == null
		or extractor_piece.get_parent() == null
	):
		return
	var site: Entity = (
		load("res://scenes/entities/structures/nt/nt_extractionSite.tscn").instantiate()
	)
	extractor_piece.get_parent().add_child(site)
	site.owner = extractor_piece.owner
	site.global_transform = extractor_piece.global_transform
	site.name = extractor_piece.name + "ExtractionSite"
	extraction_site = site
#endregion
