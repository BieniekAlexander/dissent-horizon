@tool
class_name Snowfall
extends GPUParticles3D

## Snowflakes swirling and falling fast through a column: what a frost field looks like. One
## authored particle look, sized per field — the column takes the field's radius, so a
## Blizzard and an Avalanche's shot share the look without sharing a size. Writes its own
## process material's emission ring and particle count from these exports.

## Radius of the column the flakes fall through, in world units. Match the field's HitShape.
@export var radius: float = 5.0:
	set(value):
		radius = value
		_shape_column()
## Height of the column, in world units, from the ground up.
@export var column_height: float = 6.0:
	set(value):
		column_height = value
		_shape_column()
## Flakes per square world unit of ground the column covers.
@export var density: float = 2.0:
	set(value):
		density = value
		_shape_column()


func _ready() -> void:
	# Each instance sizes its own column, so it must not write into the scene's shared material.
	if process_material != null:
		process_material = process_material.duplicate()
	_shape_column()


func _shape_column() -> void:
	var material := process_material as ParticleProcessMaterial
	if material == null:
		return
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	material.emission_ring_axis = Vector3.UP
	material.emission_ring_radius = radius
	material.emission_ring_inner_radius = 0.0
	material.emission_ring_height = column_height
	position.y = column_height * 0.5
	amount = maxi(1, roundi(density * PI * radius * radius))
	var reach: float = radius + 2.0
	visibility_aabb = AABB(
		Vector3(-reach, -column_height, -reach),
		Vector3(reach * 2.0, column_height * 2.0, reach * 2.0)
	)
