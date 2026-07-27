class_name BeaconRange
extends Node

## Declares that this entity PERMANENTLY spots the ground around it for the Colonial
## bombardment system: a Bombard may fire into anywhere within `radius` of it, without a
## beacon and without consuming anything.
##
## The persistent half of the two ways ground becomes bombardable (see BombardTargeting):
##   • a [Beacon] — placed deliberately, one strike, then gone
##   • a BeaconRange — always on, unlimited strikes, but only where the carrier stands
##
## It is a plain radius rather than a CollisionShape3D like `VisionRange` / `AggroRange`,
## because the only question ever asked of it is "is this point within r of that entity",
## which is one distance comparison. A shape would buy a physics query nothing here needs.
##
## Carried by the Bombard itself (r=20, so a lone battery covers its own approaches) and
## by the Reverence spotter aircraft (r=5, a mobile firing solution the player flies to
## wherever the guns are needed).

## World-space radius of the spotted area, measured on the XZ plane from the carrier.
@export var radius: float = 10.0


## True when `world_position` lies inside this range: within `radius` of the carrier's
## footprint, as every range is measured (see Hull). Measured in XZ: a bombardment is a
## ground strike, and an aircraft carrying the component should spot the ground beneath
## it rather than a sphere around itself.
func covers(a_world_position: Vector3) -> bool:
	var owner_entity: Entity = get_parent() as Entity
	if owner_entity == null or radius <= 0.0:
		return false
	return owner_entity.hull().distance_to_point(VU.inXZ(a_world_position)) <= radius
