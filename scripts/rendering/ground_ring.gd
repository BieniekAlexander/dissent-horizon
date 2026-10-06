@tool
class_name GroundRing
extends Decal

## A thin circle projected onto the ground, marking exactly where an area effect reaches: a
## frost field's edge. A Decal rather than a flat mesh so it lies on sloped terrain instead of
## cutting into it.
##
## The radius is the host's HitShape, never authored here: the ring and the area it marks are
## one number, so retuning the field's shape cannot leave the ring drawing the old one.

## Width of the line, in world units — fixed, so a large field's ring is no heavier than a
## small one's.
@export var line_width: float = 0.25:
	set(value):
		line_width = value
		_draw_ring()
## How far above and below the host the ring reaches for ground, in world units: the field
## stands on the terrain at its centre, and its edge may sit on a slope above or below.
@export var reach_height: float = 6.0:
	set(value):
		reach_height = value
		_draw_ring()
@export var color: Color = Color(1.0, 1.0, 1.0, 0.9):
	set(value):
		color = value
		_draw_ring()

## Texture resolution along each side; enough that a 0.25-wide line on a 10-unit field is
## several texels wide.
const TEXTURE_SIZE: int = 512
## Width of the soft edge on either side of the line, as a fraction of the line's own width.
const SOFT_EDGE: float = 0.35


func _ready() -> void:
	_draw_ring()


## The radius of the area this ring marks: the host's HitShape, or 0 with none to read.
func radius() -> float:
	var hit_shape := get_parent().get_node_or_null("HitShape") as CollisionShape3D
	if hit_shape == null or hit_shape.shape == null:
		return 0.0
	var shape: Shape3D = hit_shape.shape
	if shape is CylinderShape3D:
		return (shape as CylinderShape3D).radius
	if shape is SphereShape3D:
		return (shape as SphereShape3D).radius
	return 0.0


func _draw_ring() -> void:
	if not is_inside_tree():
		return
	var r: float = radius()
	if r <= 0.0:
		return
	size = Vector3(r * 2.0, reach_height * 2.0, r * 2.0)
	texture_albedo = ring_texture(r, line_width, color)


## A square texture holding a ring whose OUTER edge touches the square's sides — so a decal
## `2r` across draws the ring's outside exactly at `r`.
static func ring_texture(ring_radius: float, width: float, ink: Color) -> GradientTexture2D:
	var line: float = clampf(width / ring_radius, 0.0, 1.0)
	var soft: float = line * SOFT_EDGE
	var clear := Color(ink, 0.0)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(
		[0.0, maxf(0.0, 1.0 - line - soft), 1.0 - line, 1.0 - soft, 1.0]
	)
	gradient.colors = PackedColorArray([clear, clear, ink, ink, clear])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = TEXTURE_SIZE
	texture.height = TEXTURE_SIZE
	return texture
