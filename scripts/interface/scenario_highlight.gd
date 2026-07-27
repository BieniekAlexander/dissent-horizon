class_name ScenarioHighlight
extends Node3D

## Draws "the objective means THIS" markers in the world: a pulsing ring under each entity
## the player has to act on, and a pulsing footprint on the ground for each region.
##
## One of these is created per active EventHighlight and lives under the Map, so its
## coordinates are world coordinates (the same arrangement WaypointIndicator uses). It draws
## nothing on its own — an EventHighlight supplies a `target_source` Callable returning the
## current entities and shapes, and this node re-asks periodically so the marks follow units
## that move, spawn, or die without the caller having to push updates.
##
## Rendering is one ImmediateMesh with an unshaded, depth-test-free material — the same
## recipe as WaypointIndicator and BotDebugOverlay, so highlights read through terrain and
## buildings the way the rest of the game's world-space UI does.
##
## PROCESS_MODE_ALWAYS: a tutorial beat that stops the world to say "kill these three" must
## still show which three.

#region Tuning
## The colour objectives are drawn in, everywhere they appear: the rings and footprints this
## node paints in the world, and the markers the minimap stamps for the same targets. One
## constant so "the green things are what I'm supposed to be doing" holds across both views.
##
## Deliberately a vivid spring green rather than anything darker: team 3 is Color(.1,.6,.1),
## and an objective marker must never read as somebody's unit colour.
const OBJECTIVE_COLOR: Color = Color(0.2, 1.0, 0.35)

## Every live ScenarioHighlight joins this group, which is how the minimap finds what to
## stamp without reaching into the trigger system for it.
const GROUP: StringName = &"scenario_highlight"

## Lift markers off the terrain so they don't z-fight the ground mesh.
const Y_LIFT: float = 0.08
## Segments used to tessellate a circular footprint or an entity ring.
const RING_SEGMENTS: int = 28
## How far above an entity the vertical stalk rises, so the mark reads from the iso camera.
const STALK_HEIGHT: float = 1.4
## Ring radius used when an entity's own footprint can't be measured.
const DEFAULT_ENTITY_RADIUS: float = 0.45
## Extra clearance between an entity's footprint and its ring.
const RING_MARGIN: float = 0.25
## Seconds between re-queries of the target set. Conditions can be O(units), and a unit
## can't enter or leave a set meaningfully faster than this.
const REFRESH_INTERVAL: float = 0.2
## Ground-fill vertices are sampled every this many world units along a footprint edge, so
## a large region drapes over hills instead of cutting through them.
const FILL_SAMPLE_STEP: float = 1.0

## Pulse rate (cycles/second) and the alpha range it sweeps.
const PULSE_HZ: float = 1.1
const ALPHA_MIN: float = 0.35
const ALPHA_MAX: float = 0.9
## Region fill alpha, as a fraction of the outline's current pulse alpha.
const FILL_ALPHA_SCALE: float = 0.22
#endregion

#region Properties
## Marker colour. Set by the EventHighlight that owns this node; the minimap reads it too,
## so a highlight and its minimap markers always agree.
var color: Color = OBJECTIVE_COLOR

## Supplies what to draw. Called with no arguments; returns a Dictionary with
## "entities": Array[Entity] and "shapes": Array[HighlightShape]. Kept as a Callable rather
## than a stored list so the highlight tracks a LIVE set — the objective's targets are
## whatever currently matches, not whatever matched when the highlight was raised.
var target_source: Callable = Callable()

## Terrain source for draping footprints. Null falls back to y=0.
var map: Map = null

var _mesh: ImmediateMesh
var _mesh_instance: MeshInstance3D
var _entities: Array[Entity] = []
var _shapes: Array[HighlightShape] = []
var _since_refresh: float = REFRESH_INTERVAL
#endregion

#region Lifecycle
func _ready() -> void:
	# The marks must stay up while a SimulationClock hold freezes the world.
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(GROUP)
	_mesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "HighlightMesh"
	_mesh_instance.mesh = _mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = RenderPriority.HIGHLIGHT_PRIORITY
	_mesh_instance.material_override = material
	add_child(_mesh_instance)


func _process(a_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_since_refresh += a_delta
	if _since_refresh >= REFRESH_INTERVAL:
		_since_refresh = 0.0
		refresh()
	_redraw()
#endregion

#region Public API
## Re-ask target_source for what to draw. Called on the refresh cadence, and directly by
## the owning EventHighlight when it first raises the highlight so the first frame is
## already correct.
func refresh() -> void:
	_entities = []
	_shapes = []
	if not target_source.is_valid():
		return
	var result: Variant = target_source.call()
	if result is Dictionary:
		var entities: Variant = (result as Dictionary).get("entities")
		if entities is Array:
			for entity: Variant in entities:
				var e := entity as Entity
				if e != null and is_instance_valid(e) and e.is_inside_tree():
					_entities.append(e)
		var shapes: Variant = (result as Dictionary).get("shapes")
		if shapes is Array:
			for shape: Variant in shapes:
				var s := shape as HighlightShape
				if s != null:
					_shapes.append(s)


## Whether this highlight currently has anything to draw. Used by tests and by the
## objective HUD to tell "nothing to point at" from "not highlighting".
func is_empty() -> bool:
	return _entities.is_empty() and _shapes.is_empty()


## The entities currently being marked (already pruned of freed/orphaned nodes).
func marked_entities() -> Array[Entity]:
	return _entities


## The footprints currently being painted.
func marked_shapes() -> Array[HighlightShape]:
	return _shapes
#endregion

#region Drawing
func _redraw() -> void:
	_mesh.clear_surfaces()
	# Prune here as well as in refresh(). Marks are re-queried on a REFRESH_INTERVAL cadence,
	# so a marked unit routinely dies mid-interval and this list outlives it by a few frames —
	# which matters because ImmediateMesh raises "No vertices were added, surface can't be
	# created" if a surface is opened and closed with nothing in it. Killing the last unit a
	# "destroy these" objective was watching used to log that every frame until the next
	# refresh.
	var live: Array[Entity] = []
	for entity: Entity in _entities:
		if is_instance_valid(entity) and entity.is_inside_tree():
			live.append(entity)
	if live.is_empty() and _shapes.is_empty():
		return

	var outline_color: Color = color
	outline_color.a = _pulse_alpha()
	var fill_color: Color = color
	fill_color.a = outline_color.a * FILL_ALPHA_SCALE

	# Fills first, as translucent triangles, so the outlines drawn after read on top.
	if not _shapes.is_empty():
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for shape: HighlightShape in _shapes:
			_add_shape_fill(shape, fill_color)
		_mesh.surface_end()

	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for shape: HighlightShape in _shapes:
		_add_shape_outline(shape, outline_color)
	for entity: Entity in live:
		_add_entity_marker(entity, outline_color)
	_mesh.surface_end()


## Alpha sweeping between ALPHA_MIN and ALPHA_MAX. Driven by wall-clock ticks rather than
## accumulated delta so the pulse keeps breathing while the simulation is held.
func _pulse_alpha() -> float:
	var phase: float = float(Time.get_ticks_msec()) / 1000.0 * PULSE_HZ * TAU
	return lerpf(ALPHA_MIN, ALPHA_MAX, 0.5 + 0.5 * sin(phase))


## A ring at the entity's feet plus a stalk rising out of it.
func _add_entity_marker(a_entity: Entity, a_marker_color: Color) -> void:
	var origin: Vector3 = a_entity.global_position
	var center: Vector2 = VU.inXZ(origin)
	var radius: float = _entity_radius(a_entity)
	_mesh.surface_set_color(a_marker_color)

	var previous: Vector3 = _ground_point(center + Vector2(radius, 0.0))
	for i: int in range(1, RING_SEGMENTS + 1):
		var angle: float = TAU * float(i) / float(RING_SEGMENTS)
		var point: Vector3 = _ground_point(center + Vector2(cos(angle), sin(angle)) * radius)
		_mesh.surface_add_vertex(to_local(previous))
		_mesh.surface_add_vertex(to_local(point))
		previous = point

	var base: Vector3 = _ground_point(center)
	_mesh.surface_add_vertex(to_local(base))
	_mesh.surface_add_vertex(to_local(base + Vector3(0.0, STALK_HEIGHT, 0.0)))


## Ring radius for an entity: its own footprint where that is knowable, with a margin so
## the ring sits outside the art rather than through it.
func _entity_radius(a_entity: Entity) -> float:
	var structure := a_entity.get_node_or_null("Structure") as Structure
	if structure != null:
		var dims: Vector2i = structure.dimensions
		return maxf(float(dims.x), float(dims.y)) * Map.CELL_SIZE * 0.5 + RING_MARGIN
	return DEFAULT_ENTITY_RADIUS + RING_MARGIN


## Closed outline of a footprint, draped on the terrain.
func _add_shape_outline(a_shape: HighlightShape, a_outline_color: Color) -> void:
	var points: Array[Vector2] = a_shape.perimeter_points(FILL_SAMPLE_STEP)
	if points.size() < 2:
		return
	_mesh.surface_set_color(a_outline_color)
	for i: int in points.size():
		var a: Vector3 = _ground_point(points[i])
		var b: Vector3 = _ground_point(points[(i + 1) % points.size()])
		_mesh.surface_add_vertex(to_local(a))
		_mesh.surface_add_vertex(to_local(b))


## Translucent interior, as a triangle fan from the footprint centre. Both footprint kinds
## are convex, so a fan is always well-formed.
func _add_shape_fill(a_shape: HighlightShape, a_fill_color: Color) -> void:
	var points: Array[Vector2] = a_shape.perimeter_points(FILL_SAMPLE_STEP)
	if points.size() < 3:
		return
	_mesh.surface_set_color(a_fill_color)
	var center: Vector3 = _ground_point(a_shape.center)
	for i: int in points.size():
		var a: Vector3 = _ground_point(points[i])
		var b: Vector3 = _ground_point(points[(i + 1) % points.size()])
		_mesh.surface_add_vertex(to_local(center))
		_mesh.surface_add_vertex(to_local(a))
		_mesh.surface_add_vertex(to_local(b))


## Lift an XZ point onto the terrain surface. Falls back to the plane at y=0 when there is
## no Map (headless tests, HUD previews).
func _ground_point(a_xz: Vector2) -> Vector3:
	var y: float = map.terrain_height_at(a_xz) if map != null else 0.0
	return Vector3(a_xz.x, y + Y_LIFT, a_xz.y)
#endregion
