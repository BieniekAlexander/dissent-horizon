@tool
class_name AreaEffect
extends Node3D

## A particle look sized to the area it is drawn for: the burst of a blast, the cloud of a
## cryo dewar, the motes of a radiation field. One authored look is reused by every size of
## hazard — it reads the host emission's `HitShape`, as GroundRing does, so the look and the
## area it marks are one number: retuning the blast cannot leave the burst drawing the old size.
##
## Every GPUParticles3D under this node is authored at AUTHORED_RADIUS. At `_ready` each one's
## process material is duplicated (an instance must not write into the scene's shared
## material) and its emission volume, speeds, particle size, count and height are scaled by
## the ratio of the live radius to the authored one; a system named in `unscaled` keeps its
## count (one shockwave is one shockwave).
## Cosmetic only: nothing here touches the simulation.
## → gdd/systems/combat/environmental-pieces.md §Hazards

## The radius every child system was authored for, in world units (the medium blast's).
const AUTHORED_RADIUS: float = 2.5

## Systems whose `amount` is not scaled with the area (a single ring, a single flash).
@export var unscaled: Array[NodePath] = []
## The radius this instance is drawn for when its parent has no HitShape to read, in world
## units — a hand-placed preview. Read from the HitShape otherwise.
@export var fallback_radius: float = AUTHORED_RADIUS


func _ready() -> void:
	var factor: float = radius() / AUTHORED_RADIUS
	for system: GPUParticles3D in _systems(self):
		_scale_system(system, factor, unscaled.has(get_path_to(system)))


## The radius of the area this effect is drawn for: the host's HitShape, else the fallback.
func radius() -> float:
	var parent: Node = get_parent()
	var hit_shape := (
		parent.get_node_or_null("HitShape") as CollisionShape3D if parent != null else null
	)
	if hit_shape == null or hit_shape.shape == null:
		return fallback_radius
	var r: float = RangeShapes.radius_of(hit_shape.shape)
	return r if r > 0.0 else fallback_radius


static func _systems(a_node: Node) -> Array[GPUParticles3D]:
	var out: Array[GPUParticles3D] = []
	for child: Node in a_node.get_children():
		if child is GPUParticles3D:
			out.append(child)
		out.append_array(_systems(child))
	return out


## Grow one system from its authored size by `a_factor`: the volume it emits from, how fast
## and how far its particles go, how big they are, how many there are, and where it stands.
static func _scale_system(a_system: GPUParticles3D, a_factor: float, a_keep_count: bool) -> void:
	if is_equal_approx(a_factor, 1.0):
		return
	var material := a_system.process_material as ParticleProcessMaterial
	if material != null:
		material = material.duplicate() as ParticleProcessMaterial
		a_system.process_material = material
		material.emission_sphere_radius *= a_factor
		material.emission_ring_radius *= a_factor
		material.emission_ring_inner_radius *= a_factor
		material.emission_box_extents *= a_factor
		material.initial_velocity_min *= a_factor
		material.initial_velocity_max *= a_factor
		material.scale_min *= a_factor
		material.scale_max *= a_factor
	if not a_keep_count:
		# Area, not length: twice the radius is four times the ground to cover.
		a_system.amount = maxi(1, roundi(float(a_system.amount) * a_factor * a_factor))
	a_system.position.y *= a_factor
	var aabb: AABB = a_system.visibility_aabb
	a_system.visibility_aabb = AABB(aabb.position * a_factor, aabb.size * a_factor)
