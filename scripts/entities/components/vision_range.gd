class_name VisionRange
extends CollisionShape3D

## What a piece reveals of the fog: a disabled shape the fog stamps from wherever the shape
## stands (FogRaster.update_sight). Usually that is the piece itself; an ORBIT vision stands at
## the centre of the orbit its piece flies instead, and sees only while it holds that orbit.
## Doc key `senses.vision_from:`. Rules: gdd/systems/combat/range-buckets.md §Where a reach is
## measured from.

## Where the vision stands.
enum Origin {
	## On the piece, wherever it goes. Always sees.
	BODY,
	## At the centre of the piece's FLYING orbit, and only while it is holding that orbit — on a
	## Sortie, only on station. Blind in transit, and on anything that does not orbit.
	ORBIT,
}

@export var origin: Origin = Origin.BODY


## Whether this vision reveals anything right now. A BODY vision always does; the piece's own
## rules (Entity.grants_vision) still apply on top.
func is_active() -> bool:
	return origin == Origin.BODY or orbit_origin() is Vector3


## The orbit centre an ORBIT vision stands at, or null when it is not holding an orbit — or is
## a BODY vision, which has none.
func orbit_origin() -> Variant:
	if origin != Origin.ORBIT:
		return null
	var host: Entity = get_parent() as Entity
	var aerial: Aerial = host.get_node_or_null("Aerial") as Aerial if host != null else null
	if aerial == null or aerial.mode != Movement.Mode.FLYING or not aerial.is_airborne():
		return null
	var sortie: Sortie = Sortie.of(host)
	if sortie != null and not sortie.is_on_station():
		return null
	return aerial.anchor()


func _ready() -> void:
	# A BODY vision rides on its piece as any child does; only an ORBIT one is placed by hand.
	top_level = origin == Origin.ORBIT
	set_physics_process(origin == Origin.ORBIT)


## Framework-imposed: the shape is re-stood at the orbit's centre every tick, since the anchor
## moves (a Sortie takes station, an Attack re-centres it) without telling anyone.
func _physics_process(_a_delta: float) -> void:
	var at: Variant = orbit_origin()
	if at is Vector3:
		global_position = at
