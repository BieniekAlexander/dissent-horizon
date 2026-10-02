extends RefCounted

## Reads what a scene ALREADY looks like: how big its visible model is, and which of the
## generated visual slots are still empty.
##
## Sits between the pure arithmetic (visual_defaults.gd, which never sees a Node) and the
## writer (scene_sync.gd, which never measures). Both the importer and the audit report
## call it, which is what keeps "the piece has no visual" meaning the same thing in the
## thing that fixes it and the thing that lists it.
##
## Every walk composes transforms BY HAND from the scene root rather than reading
## global_transform, because the instances it is given are deliberately out of the tree —
## the importer never adds a scene it is editing, and neither does the report.

const VisualDefaults := preload("res://tools/spec_import/visual_defaults.gd")

## Node metadata recording what the importer generated, and for which class. Presence
## identifies the node/value as ours; it is NOT how ownership is decided (see
## visual_defaults.gd's header — a baked value is never overwritten either way). It is what
## lets the report separate "still the untouched default" from "hand-tuned since".
const STAMP_MESH: String = "_visual_default_mesh"
const STAMP_SELECTION: String = "_visual_default_selection"
const STAMP_HP_BAR: String = "_visual_default_hp_bar"

## Where a generated placeholder model is parented, and what it is called. Replacing it with
## art is a delete and an add, never a re-instance: a second declaration of a node under one
## parent segfaults the process during engine teardown (entity-scene-hierarchy.md).
const MESH_VISUAL_PATH: String = "MeshVisual"
const PLACEHOLDER_NODE: String = "PlaceholderModel"
## The shared stand-in model a structure instances when it has no art of its own.
const DUMMY_STRUCTURE_SCENE: String = "res://assets/meshes/entities/dummy_structure.blend"

## A projectile has no MeshVisual and no ground to stand on, so its placeholders hang off
## the root. The names are what an EmissionPhase's visuals list resolves, which is how a
## generated mesh gets hidden and shown with the state it belongs to.
const IN_FLIGHT_MESH_NODE: String = "InFlightMesh"
const POST_IMPACT_MESH_NODE: String = "PostImpactMesh"
## Art of another kind that fills one of those two states, so its stand-in is not wanted: a
## beam a Tracer draws in flight, and a particle effect that draws something on impact.
const TRACER_NODE: String = "Tracer"
const BEAM_MESH_NODE: String = "BeamMesh"
const POST_IMPACT_PARTICLES_NODE: String = "PostImpactParticles"

const HP_BAR_PATH: String = "HPBar"
const HP_BAR_FILL_PATH: String = "HPBar/HPBarFill"
const SELECTION_SHAPE_PATH: String = "Selectable/SelectionShape"


## Everything the importer and the report need to know about one scene's visuals:
##   size, top      — the visible model's extent in the entity's own local space
##   mesh_count     — how many visible MeshInstance3D nodes contributed
##   is_placeholder — the only thing visible is a stand-in (ours, or the shared structure
##                    dummy), i.e. this piece still has no art of its own
##   has_mesh       — anything visible at all
static func measure(entity: Node3D) -> Dictionary:
	var bounds: AABB = AABB()
	var found: bool = false
	var count: int = 0
	var own_art: bool = false
	for record: Dictionary in _visible_meshes(entity):
		var mesh_instance: MeshInstance3D = record["node"]
		count += 1
		var box: AABB = (record["xform"] as Transform3D) * mesh_instance.get_aabb()
		bounds = box if not found else bounds.merge(box)
		found = true
		if not _is_stand_in(entity, mesh_instance):
			own_art = true
	return {
		"has_mesh": found,
		"mesh_count": count,
		"size": bounds.size if found else Vector3.ZERO,
		"top": (bounds.position.y + bounds.size.y) if found else 0.0,
		"is_placeholder": found and not own_art,
	}


## The larger horizontal extent of the model — what "approximately how wide is this" means
## for a bar that billboards, since the narrow axis turns toward the camera half the time.
static func model_width(measurement: Dictionary) -> float:
	var size: Vector3 = measurement["size"]
	return maxf(size.x, size.z)


## A mesh that is standing in for art nobody has made: either a placeholder this importer
## generated, or an instance of the shared structure dummy. Both mean the same thing to a
## reader of the report.
static func _is_stand_in(entity: Node3D, mesh_instance: MeshInstance3D) -> bool:
	var node: Node = mesh_instance
	while node != null and node != entity:
		if (
			node.has_meta(STAMP_MESH)
			or node.name == PLACEHOLDER_NODE
			or node.scene_file_path == DUMMY_STRUCTURE_SCENE
		):
			return true
		node = node.get_parent()
	return false


## Every visible MeshInstance3D with a mesh, paired with its transform relative to the
## entity root. Visibility is composed down the chain: a hidden ancestor hides its whole
## subtree.
static func _visible_meshes(entity: Node3D) -> Array:
	var out: Array = []
	var stack: Array = [{"node": entity, "xform": Transform3D.IDENTITY, "shown": true}]
	while not stack.is_empty():
		var frame: Dictionary = stack.pop_back()
		var node: Node = frame["node"]
		var xform: Transform3D = frame["xform"]
		var shown: bool = frame["shown"]
		if node != entity and node is Node3D:
			xform = xform * (node as Node3D).transform
			shown = shown and (node as Node3D).visible
		if shown and node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			out.append({"node": node, "xform": xform})
		for child: Node in node.get_children():
			stack.append({"node": child, "xform": xform, "shown": shown})
	return out


# --------------------------------------------------------------------------- #
# Which slots are still empty
# --------------------------------------------------------------------------- #
## An HP bar sitting exactly on the entity's origin. That position is inside the model on
## every piece in the game, so it cannot be a value anybody meant — which is what makes it
## usable as the "cleared, please rebake" signal. Any other origin is the author's, whether
## they typed it or accepted a generated one.
static func hp_bar_is_cleared(entity: Node3D) -> bool:
	var bar: Node3D = entity.get_node_or_null(HP_BAR_PATH) as Node3D
	return bar != null and bar.transform.origin.is_zero_approx()


## A selection shape nobody has given a shape to.
static func selection_is_cleared(entity: Node3D) -> bool:
	var node: CollisionShape3D = entity.get_node_or_null(SELECTION_SHAPE_PATH) as CollisionShape3D
	return node != null and node.shape == null


## Whether the scene carries a mesh somebody AUTHORED — anything under `MeshVisual` but the
## generated placeholder, or, for an emission (which has no MeshVisual), an in-flight or
## post-impact mesh the importer did not stamp, or the art that stands in for one (a tracer
## beam, an impact particle effect). What the `has_mesh_visual` waiver goes STALE on: the day a
## piece declared to carry no model grows one.
static func has_authored_mesh(entity: Node) -> bool:
	var mesh_visual: Node = entity.get_node_or_null(MESH_VISUAL_PATH)
	var candidates: Array[Node] = []
	if mesh_visual != null:
		candidates.assign(mesh_visual.get_children())
	else:
		if has_tracer_beam(entity) or has_impact_effect(entity):
			return true
		for node_name: String in [IN_FLIGHT_MESH_NODE, POST_IMPACT_MESH_NODE]:
			var node: Node = entity.get_node_or_null(node_name)
			if node != null:
				candidates.append(node)
	return candidates.any(
		func(n: Node) -> bool: return n.name != PLACEHOLDER_NODE and not n.has_meta(STAMP_MESH)
	)


## Whether a Tracer draws the emission in flight. A beam is art the player sees, so an
## emission that has one wants no in-flight stand-in.
static func has_tracer_beam(entity: Node) -> bool:
	return (
		entity.get_node_or_null(TRACER_NODE) != null
		and entity.get_node_or_null(BEAM_MESH_NODE) != null
	)


## Whether an authored particle effect fills the emission's post-impact state: a particle
## system under PostImpactParticles that draws something. An empty particles node left over
## from an old template draws nothing, and is not art.
static func has_impact_effect(entity: Node) -> bool:
	var node: Node = entity.get_node_or_null(POST_IMPACT_PARTICLES_NODE)
	if node == null:
		return false
	return EmissionPhase.particle_systems_in(node).any(
		func(n: Node) -> bool:
			return (
				(n is GPUParticles3D and (n as GPUParticles3D).draw_pass_1 != null)
				or (n is CPUParticles3D and (n as CPUParticles3D).mesh != null)
			)
	)


## Whether this scene still wants a stand-in model.
##
## Asked of the `MeshVisual` NODE — has anybody put anything under it — rather than of what
## measures VISIBLE, so a scene whose art is authored hidden is left alone. The measurement
## is the fallback for a piece with no MeshVisual at all. Why the node is the right question:
## gdd/systems/ux/ui/generated-visual-defaults.md §A placeholder is wanted when `MeshVisual` has
## no CHILDREN.
static func needs_placeholder_mesh(entity: Node3D, measurement: Dictionary) -> bool:
	var mesh_visual: Node = entity.get_node_or_null(MESH_VISUAL_PATH)
	if mesh_visual != null:
		return mesh_visual.get_child_count() == 0
	return not measurement["has_mesh"]


## Whether a slot's value is one the importer put there. The standing rule does not consult
## this — a baked value is left alone whether it is stamped or not — but the `--rebake-visuals`
## migration does: an UNSTAMPED value is one that predates this pass, and is what that flag
## is for. A stamped value edited since is a decision made against this system, and the flag
## deliberately leaves it alone.
static func selection_is_owned(entity: Node3D) -> bool:
	var node: Node = entity.get_node_or_null(SELECTION_SHAPE_PATH)
	return node != null and node.has_meta(STAMP_SELECTION)


static func hp_bar_is_owned(entity: Node3D) -> bool:
	var node: Node = entity.get_node_or_null(HP_BAR_PATH)
	return node != null and node.has_meta(STAMP_HP_BAR)


## The conversion between a bar's WORLD width and the Sprite3D scale the scene stores,
## expressed exactly once. Returns 0.0 when the sprite has no texture to measure, which
## callers read as "cannot size this bar" rather than dividing by zero.
static func hp_bar_scale_per_world_unit(entity: Node3D) -> float:
	var fill: Sprite3D = entity.get_node_or_null(HP_BAR_FILL_PATH) as Sprite3D
	if fill == null or fill.texture == null or fill.pixel_size <= 0.0:
		return 0.0
	var drawn_width: float = fill.texture.get_size().x * fill.pixel_size
	return 0.0 if drawn_width <= 0.0 else 1.0 / drawn_width
