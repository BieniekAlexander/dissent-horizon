class_name Tracer
extends Node

## Draws an emission's BeamMesh — a tracer cylinder — from where it was fired. A beam launched
## at no speed (the vanguard lazer) is a static flash spanning launch point to destination; a
## travelling one grows from the launch point toward the emission, capped at BEAM_MAX_LENGTH,
## past which its near end trails behind like a tracer round.
##
## The beam is hidden under the viewer's fog piece by piece rather than whole: it is drawn as
## one segment per stretch of it in sight (`visible_spans`). The segments are copies of the
## authored `BeamMesh`, parented to this plain Node rather than to the emission, so hiding the
## emission under fog (Fog._apply_figure_visibility) does not hide the part of its beam that
## is in sight. The authored node itself is only the template, and is never drawn.
##
## TODO the beam handling is very ugly; generalise it with the other phase visuals.

## How far the beam is lifted off the origin/target line so it doesn't clip the ground.
const BEAM_LIFT: float = 0.5
## Cap on how long a travelling tracer grows before it trails behind at a fixed length.
const BEAM_MAX_LENGTH: float = 3.0

## A beam is clipped against the fog at this spacing, as a fraction of a fog pixel (one cell),
## so no pixel it crosses is skipped.
const SPAN_SAMPLES_PER_CELL: float = 2.0

var _origin: Vector3
var _destination: Variant = null
var _is_static: bool = true
## The drawn segments, reused frame to frame: a beam that dips in and out of fog would
## otherwise allocate a mesh instance per frame per stretch.
var _segments: Array[MeshInstance3D] = []


static func of(a_node: Variant) -> Tracer:
	if a_node == null or not is_instance_valid(a_node) or not (a_node is Node):
		return null
	return (a_node as Node).get_node_or_null("Tracer") as Tracer


func host() -> Node3D:
	return get_parent() as Node3D


## The authored mesh the segments copy, which no phase's visuals list may toggle.
func beam() -> MeshInstance3D:
	return host().get_node_or_null("BeamMesh") as MeshInstance3D


func start(a_origin: Vector3, a_destination: Vector3, a_is_static: bool) -> void:
	_origin = a_origin
	_destination = a_destination
	_is_static = a_is_static
	refresh()


## Redraw the beam for the emission's current position and the viewer's current fog.
func refresh() -> void:
	var template: MeshInstance3D = beam()
	if template == null or _destination == null:
		return
	template.visible = false
	var far_point: Vector3 = _destination if _is_static else host().global_position
	var full_diff: Vector3 = far_point - _origin
	var full_length: float = full_diff.length()
	var spans: Array[Vector2] = []
	if full_length >= 0.001:
		var direction: Vector3 = full_diff / full_length
		var length: float = full_length if _is_static else minf(full_length, BEAM_MAX_LENGTH)
		var near_point: Vector3 = far_point - direction * length
		var entity: Entity = host() as Entity
		var owner_id: int = (
			entity.commander_id if entity != null and entity.ownership != null else 0
		)
		spans = visible_spans(
			near_point,
			far_point,
			Map.CELL_SIZE / SPAN_SAMPLES_PER_CELL,
			Fog.active_sight_test(owner_id)
		)
		_lay_segments(near_point, far_point, spans)
	for i: int in range(spans.size(), _segments.size()):
		_segments[i].visible = false


## The stretches of the line `a_near` → `a_far` that pass `a_is_clear` (a test on a world XZ
## point), as (from, to) fractions of its length, in order. An invalid test passes everywhere.
## Sampled every `a_step` world units; a boundary between a clear and a hidden sample is put
## halfway between them.
static func visible_spans(
	a_near: Vector3, a_far: Vector3, a_step: float, a_is_clear: Callable
) -> Array[Vector2]:
	if not a_is_clear.is_valid():
		return [Vector2(0.0, 1.0)]
	var count: int = maxi(1, ceili(a_near.distance_to(a_far) / a_step))
	var clear: Array[bool] = []
	for i: int in count + 1:
		clear.append(bool(a_is_clear.call(VU.inXZ(a_near.lerp(a_far, float(i) / count)))))
	var spans: Array[Vector2] = []
	var start: float = -1.0
	for i: int in count + 1:
		var t: float = float(i) / count
		var half_back: float = maxf(0.0, t - 0.5 / count)
		if clear[i] and start < 0.0:
			start = 0.0 if i == 0 else half_back
		elif not clear[i] and start >= 0.0:
			spans.append(Vector2(start, half_back))
			start = -1.0
	if start >= 0.0:
		spans.append(Vector2(start, 1.0))
	return spans


func _ready() -> void:
	# By name: the host's own reference to it is not yet set while its children are readying.
	var phased: PhasedLocomotion = host().get_node_or_null("Locomotion") as PhasedLocomotion
	if phased != null:
		phased.phase_entered.connect(func(_a_index: int) -> void: refresh())
		phased.moved.connect(refresh)


## Re-clipped every frame as well as on every move: the fog changes under a static beam too.
func _process(_a_delta: float) -> void:
	refresh()


## Place one segment per span along `a_near` → `a_far`, growing the pool as needed.
func _lay_segments(a_near: Vector3, a_far: Vector3, a_spans: Array[Vector2]) -> void:
	var direction: Vector3 = (a_far - a_near).normalized()
	var basis: Basis = _cylinder_basis_along(direction)
	for i: int in a_spans.size():
		var from: Vector3 = a_near.lerp(a_far, a_spans[i].x)
		var to: Vector3 = a_near.lerp(a_far, a_spans[i].y)
		var segment: MeshInstance3D = _segment(i)
		segment.visible = true
		# Global coordinates, not local: the host turns to face its velocity every tick, so
		# local space stops lining up with world space the moment it moves. An explicit
		# orthonormal basis rather than Euler angles, so rotation_order never enters into it.
		segment.global_transform = Transform3D(basis, 0.5 * (from + to) + Vector3.UP * BEAM_LIFT)
		segment.scale = Vector3(1, from.distance_to(to) / 2.0, 1)


## The `a_index`th drawn segment, copied from the template the first time it is needed.
func _segment(a_index: int) -> MeshInstance3D:
	while _segments.size() <= a_index:
		var copy: MeshInstance3D = beam().duplicate() as MeshInstance3D
		copy.name = "BeamSegment%d" % _segments.size()
		add_child(copy)
		_segments.append(copy)
	return _segments[a_index]


## A basis whose local +Y axis (a CylinderMesh's long axis) points along `a_direction`.
static func _cylinder_basis_along(a_direction: Vector3) -> Basis:
	var up_hint: Vector3 = (
		Vector3.FORWARD if absf(a_direction.dot(Vector3.UP)) > 0.999 else Vector3.UP
	)
	var x_axis: Vector3 = up_hint.cross(a_direction).normalized()
	var z_axis: Vector3 = x_axis.cross(a_direction).normalized()
	return Basis(x_axis, a_direction, z_axis)
