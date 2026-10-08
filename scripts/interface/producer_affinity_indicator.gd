class_name ProducerAffinityIndicator
extends Node3D

## Rings the structures that could build the production-queue entry the cursor is over.
##
## This is the world-facing half of producer affinity. The HUD half — the Details pane
## showing only the purchases that could land on the selected producers (a scoped
## ProductionRail) — answers "what will this building make?"; this answers the other
## direction, "where will this purchase go?". Between them they recover what a per-structure
## queue used to show for free, as a live query over the global queue rather than as a second
## data structure.
##
## Drawn in RallyIndicator's cyan, deliberately: both mark the same kind of fact — where
## production is headed — and using a second colour for one of them would imply a distinction
## that does not exist. The SHAPES separate them (rings around buildings here, lines and
## diamonds to a destination there), which is what a player actually reads.
##
## Follows RallyIndicator's recipe rather than pooling per-target nodes: one ImmediateMesh
## redrawn every frame from a set that changes under a live query (the hover moves, producers
## finish, structures die). ScenarioHighlight is the same shape and is deliberately NOT reused
## — every live one joins the `scenario_highlight` group, which the minimap reads to paint
## objective markers, so borrowing it would draw HUD hover feedback on the minimap as though
## it were a mission objective.

const Y_OFFSET: float = 0.15
## Segments per ring. Enough that a ring reads as round at the default zoom without spending
## vertices on something that is on screen only while the cursor rests on a chip.
const RING_SEGMENTS: int = 24
## Ring radius for a structure declaring no footprint, in world units.
const DEFAULT_RADIUS: float = 1.1
## How far outside a structure's footprint the ring sits, so it reads as marking the building
## rather than as part of it.
const FOOTPRINT_MARGIN: float = 0.45
const COLOR: Color = RallyIndicator.COLOR

var _mesh: ImmediateMesh
var _mesh_instance: MeshInstance3D


func _ready() -> void:
	_mesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	# No depth test, like every other marker in this family: a ring on a structure standing
	# behind a hill is exactly the case the player needs to see.
	material.no_depth_test = true
	material.render_priority = RenderPriority.WAYPOINT_PRIORITY
	_mesh_instance.material_override = material
	add_child(_mesh_instance)


## Redraw a ring around each commandable in `a_producers`. An empty array clears the mesh,
## which is how the indicator turns itself off when the cursor leaves a chip.
func update_producers(a_producers: Array) -> void:
	_mesh.clear_surfaces()
	var drawable: Array = a_producers.filter(
		func(node: Variant) -> bool: return node is Actor and is_instance_valid(node)
	)
	if drawable.is_empty():
		return

	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_mesh.surface_set_color(COLOR)
	for node: Node in drawable:
		_add_ring(node as Actor)
	_mesh.surface_end()


## One closed ring on the ground around `a_producer`, sized to its footprint.
##
## Height is sampled per VERTEX from the terrain rather than taken once from the structure's
## origin, so a ring on sloped ground follows the slope instead of cutting into the hill on
## one side and floating on the other.
func _add_ring(a_producer: Actor) -> void:
	var centre: Vector2 = VU.in_xz(a_producer.global_position)
	var radius: float = _radius_for(a_producer)
	var previous: Vector3 = _ring_point(a_producer, centre, radius, RING_SEGMENTS - 1)
	for i: int in RING_SEGMENTS:
		var current: Vector3 = _ring_point(a_producer, centre, radius, i)
		_mesh.surface_add_vertex(to_local(previous))
		_mesh.surface_add_vertex(to_local(current))
		previous = current


func _ring_point(
	a_producer: Actor, a_centre: Vector2, a_radius: float, a_index: int
) -> Vector3:
	var angle: float = TAU * float(a_index) / float(RING_SEGMENTS)
	var xz: Vector2 = a_centre + Vector2(cos(angle), sin(angle)) * a_radius
	var height: float = a_producer.global_position.y
	if a_producer.map != null:
		height = a_producer.map.terrain_height_at(xz)
	return Vector3(xz.x, height + Y_OFFSET, xz.y)


## A ring big enough to contain the structure it marks. Multi-cell structures declare their
## footprint on their Structure component; anything without one gets the default.
##
## Sized to the footprint's half-DIAGONAL, not its half-width: a circle at half-width passes
## inside the corners of the square it is meant to enclose, which is visibly wrong on anything
## bigger than about 2×2.
static func _radius_for(producer: Actor) -> float:
	var structure: Fixture = producer.get_node_or_null("Fixture") as Fixture
	if structure == null:
		return DEFAULT_RADIUS
	var half: Vector2 = Vector2(structure.dimensions) * Map.CELL_SIZE * 0.5
	return half.length() + FOOTPRINT_MARGIN
