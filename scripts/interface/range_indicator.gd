class_name RangeIndicator
extends Node3D

## Draws REACH on the ground: the rings and footprints that answer "how far does this go?"
## for whatever the player is currently asking about — an info card they are hovering, or an
## ability they have armed.
##
## ONE NODE, MANY SOURCES. The controller recomposes the whole band list every frame from
## its own state rather than each source pushing and clearing its own marks. Two sources
## that could each be on or off is four states to keep straight, and a hover that ended
## while an ability was armed used to be exactly the kind of thing that left a ring on
## screen with nothing to explain it.
##
## Lives under the Map so its coordinates are world coordinates, the same arrangement
## WaypointIndicator and ScenarioHighlight use. The rendering recipe is theirs too — one
## ImmediateMesh, unshaded, depth-test off — so a range reads through terrain and buildings
## the way the rest of the game's world-space UI does.
##
## PROCESS_MODE_ALWAYS: a player who stopped the world to read a card must still see what
## the card is pointing at.

#region Constants
## Lift marks off the terrain so they don't z-fight the ground mesh. The same value
## ScenarioHighlight uses, for the same reason.
const Y_LIFT: float = 0.08
## Circle tessellation. Ranges are large and drawn as thin outlines, so this is higher than
## the objective painter's — a visibly polygonal ring reads as a diagram rather than a reach.
const RING_SEGMENTS: int = 48
## Outline points are sampled at least this often along an edge, so a footprint drapes over
## hills instead of cutting through them.
const SAMPLE_STEP: float = 0.75
## How opaque an outline is drawn. Steady, not pulsing: a range is a fact the player asked
## to see, not an alert competing for their attention (contrast ScenarioHighlight, which
## pulses because it is telling them something they did not ask).
const OUTLINE_ALPHA: float = 0.85
## A filled band's interior alpha, as a fraction of its outline's.
const FILL_ALPHA_SCALE: float = 0.18
## The shortest advance dash() takes along an edge, in metres.
const DASH_MIN_STEP: float = 0.0001
## Length of each colour's stretch on an ALTERNATING ring, in metres.
const ALTERNATE_METRES: float = 1.0
#endregion


#region Bands
## ONE RANGE TO DRAW. A footprint, a colour, and whether its interior is washed in.
##
## FILL IS FOR AN AREA THE PLAYER IS ABOUT TO PUT SOMETHING IN — a blast radius under the
## cursor — and an outline is for a reach they are reading. Filling a reach as well would
## put a translucent disc over half the battlefield every time a card is hovered.
##
## A PENDING band belongs to a piece that is ordered but not up yet, and its outline is dashed
## (PendingStyle) — the reach it will have, not one it has.
##
## An ALTERNATING band is two reaches that are the same ring — a weapon that carries as far
## against aircraft as against the ground — drawn once, in stretches of both colours.
class Band:
	var shape: HighlightShape
	var color: Color
	var filled: bool
	var is_pending: bool
	var alternate_color: Color = Color(0, 0, 0, 0)
	var is_alternating: bool = false

	static func of(
		a_shape: HighlightShape, a_color: Color, a_filled: bool = false, a_is_pending: bool = false
	) -> Band:
		var band := Band.new()
		band.shape = a_shape
		band.color = a_color
		band.filled = a_filled
		band.is_pending = a_is_pending
		return band


#endregion

#region Properties
## Terrain source for draping footprints. Null falls back to the plane at y = 0, which is
## what a headless test or a HUD preview gets.
var map: Map = null

var _bands: Array[Band] = []
var _mesh: ImmediateMesh
var _mesh_instance: MeshInstance3D
#endregion


#region Lifecycle
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "RangeMesh"
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


#endregion


#region Public API
## Replace everything drawn with `a_bands`. Called every frame with the whole list, so
## clearing is simply passing an empty one and there is no separate "and now put that other
## thing away" path to forget.
func set_bands(a_bands: Array[Band]) -> void:
	_bands = a_bands
	_redraw()


## The bands currently drawn — what a test asserts against, since the mesh itself says
## nothing readable.
func bands() -> Array[Band]:
	return _bands


## Every band `a_kinds` produces for `a_entity`, coloured per kind. The ordinary
## hover-a-card case, spelled once here so the controller does not carry the mapping.
##
## Ground and air reach that are the same ring become ONE alternating band in both colours:
## two identical circles would draw as whichever came last, hiding the other.
static func bands_for_entity(a_entity: Entity, a_kinds: Array) -> Array[Band]:
	var out: Array[Band] = []
	var pairs: Array = EntityRanges.shapes_for(a_entity, a_kinds)
	var ground: HighlightShape = null
	var air: HighlightShape = null
	for pair: Array in pairs:
		if pair[0] == EntityRanges.Kind.ATTACK:
			ground = pair[1]
		elif pair[0] == EntityRanges.Kind.ATTACK_AIR:
			air = pair[1]
	var merge: bool = ground != null and air != null and same_footprint(ground, air)
	for pair: Array in pairs:
		if merge and pair[0] == EntityRanges.Kind.ATTACK_AIR:
			continue
		var band := Band.of(pair[1] as HighlightShape, EntityRanges.color_of(pair[0]))
		if merge and pair[0] == EntityRanges.Kind.ATTACK:
			band.is_alternating = true
			band.alternate_color = EntityRanges.color_of(EntityRanges.Kind.ATTACK_AIR)
		out.append(band)
	return out


## Whether two footprints would draw as the same outline.
static func same_footprint(a: HighlightShape, b: HighlightShape) -> bool:
	if a.kind != b.kind or not a.center.is_equal_approx(b.center):
		return false
	if a.kind == HighlightShape.Kind.CIRCLE:
		return is_equal_approx(a.radius, b.radius)
	return (
		a.half_extents.is_equal_approx(b.half_extents)
		and is_equal_approx(a.rotation_y, b.rotation_y)
	)


#endregion


#region Drawing
func _redraw() -> void:
	_mesh.clear_surfaces()
	if _bands.is_empty():
		return

	# Fills first, as translucent triangles, so the outlines drawn after read on top.
	var filled: Array[Band] = []
	for band: Band in _bands:
		if band.filled:
			filled.append(band)
	if not filled.is_empty():
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for band: Band in filled:
			_add_fill(band)
		_mesh.surface_end()

	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for band: Band in _bands:
		_add_outline(band)
	_mesh.surface_end()


func _add_outline(a_band: Band) -> void:
	var points: Array[Vector2] = _points(a_band.shape)
	if points.size() < 2:
		return
	var color: Color = a_band.color
	color.a = OUTLINE_ALPHA
	var closed: Array[Vector2] = points.duplicate()
	closed.append(points[0])
	if a_band.is_alternating:
		# Two dash patterns, the second offset by one stretch, so together they close the ring.
		var other: Color = a_band.alternate_color
		other.a = OUTLINE_ALPHA
		_add_pieces(dash(closed, ALTERNATE_METRES, ALTERNATE_METRES), color)
		_add_pieces(dash(closed, ALTERNATE_METRES, ALTERNATE_METRES, ALTERNATE_METRES), other)
		return
	var pieces: Array = (
		dash(closed, PendingStyle.DASH_METRES, PendingStyle.GAP_METRES)
		if a_band.is_pending
		else _edges(closed)
	)
	_add_pieces(pieces, color)


func _add_pieces(a_pieces: Array, a_color: Color) -> void:
	_mesh.surface_set_color(a_color)
	for piece: Array in a_pieces:
		_mesh.surface_add_vertex(to_local(_ground_point(piece[0])))
		_mesh.surface_add_vertex(to_local(_ground_point(piece[1])))


## A polyline's edges as [from, to] pairs.
static func _edges(polyline: Array[Vector2]) -> Array:
	var out: Array = []
	for i: int in polyline.size() - 1:
		out.append([polyline[i], polyline[i + 1]])
	return out


## The visible [from, to] pieces of `polyline` drawn as `dash_length` on, `gap_length` off,
## measured along its length — the phase carries across vertices, so a finely tessellated
## circle dashes evenly rather than restarting at every short edge. `a_offset` shifts where the
## pattern starts along the line, in metres.
static func dash(
	polyline: Array[Vector2], dash_length: float, gap_length: float, a_offset: float = 0.0
) -> Array:
	var out: Array = []
	var period: float = dash_length + gap_length
	if period <= 0.0:
		return _edges(polyline)
	var travelled: float = 0.0
	for i: int in polyline.size() - 1:
		var a: Vector2 = polyline[i]
		var b: Vector2 = polyline[i + 1]
		var length: float = a.distance_to(b)
		var along: float = 0.0
		while along < length:
			var phase: float = fposmod(travelled + along + a_offset, period)
			var is_on: bool = phase < dash_length
			# Floored so float error at a phase boundary cannot stall the walk.
			var step: float = maxf(
				minf((dash_length if is_on else period) - phase, length - along), DASH_MIN_STEP
			)
			if is_on:
				out.append([a.lerp(b, along / length), a.lerp(b, (along + step) / length)])
			along += step
		travelled += length
	return out


## Translucent interior, as a triangle fan from the footprint centre. Both footprint kinds
## are convex, so a fan is always well-formed.
func _add_fill(a_band: Band) -> void:
	var points: Array[Vector2] = _points(a_band.shape)
	if points.size() < 3:
		return
	var color: Color = a_band.color
	color.a = OUTLINE_ALPHA * FILL_ALPHA_SCALE
	_mesh.surface_set_color(color)
	var center: Vector3 = _ground_point(a_band.shape.center)
	for i: int in points.size():
		_mesh.surface_add_vertex(to_local(center))
		_mesh.surface_add_vertex(to_local(_ground_point(points[i])))
		_mesh.surface_add_vertex(to_local(_ground_point(points[(i + 1) % points.size()])))


## A circle is tessellated finely and needs no further sampling; a rectangle's four corners
## do, or a long edge cuts straight through a hill.
func _points(a_shape: HighlightShape) -> Array[Vector2]:
	return (
		a_shape.outline(RING_SEGMENTS)
		if a_shape.kind == HighlightShape.Kind.CIRCLE
		else a_shape.perimeter_points(SAMPLE_STEP)
	)


func _ground_point(a_xz: Vector2) -> Vector3:
	var y: float = map.terrain_height_at(a_xz) if map != null else 0.0
	return Vector3(a_xz.x, y + Y_LIFT, a_xz.y)
#endregion
