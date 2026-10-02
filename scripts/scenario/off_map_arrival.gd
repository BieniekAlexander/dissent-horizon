class_name OffMapArrival
extends RefCounted

## Where something that is CALLED IN from beyond the play space comes from, and when it has
## left again.
##
## Most abilities originate about the piece that produces them — a gun fires its shell from
## its own muzzle. A few do not: they are requests to something off the board, and what
## answers arrives over the map edge (the Command & Conquer: Generals promotion shape — a
## barrage, a transport). This is the one place that "off the board" is turned into a world
## position, so a mortar barrage and an airdrop enter from the same remove and by the same
## rule.
##
## THE ORIGIN IS DERIVED FROM THE CASTER, not from the target. The delivery therefore comes
## in over the caster's own side of the field and flies toward the target, which is what
## makes an ability called from a forward building read differently from the same ability
## called from home. Aiming it from the target instead would have made the caster's position
## mean nothing, and every drop would arrive from whichever edge happened to be nearest the
## enemy.

## How far outside the play area a called-in piece starts, in world units.
##
## The same number is the despawn threshold on the way out (see has_left), so a transport
## enters and leaves at the same remove from the board — and so a piece that has just
## spawned is never immediately judged to have left.
const EXTERIOR_MARGIN: float = 10.0


## The world XZ a piece called in by a caster at `caster_xz` enters from: the point on the
## play-area perimeter nearest the caster, EXTERIOR_MARGIN further out along that ray.
##
## Falls back to `caster_xz` itself on a map that declares no play area (a bare test
## harness, a scene with no heightmap). The ability then fires from the caster, which is
## the ordinary shape every other ability already has — degraded, but not broken.
static func entry_xz(map: Map, caster_xz: Vector2) -> Vector2:
	var area: PlayArea = _area_of(map)
	if area == null:
		return caster_xz
	return area.exterior_point(caster_xz, EXTERIOR_MARGIN)


## A point far enough along `heading` from `from_xz` to be off the map whichever way it
## points — where a piece flying THROUGH the play area is aimed once its work is done.
##
## Sized from the play area's diagonal rather than solved for the actual boundary crossing:
## the piece is removed by has_left() the moment it is clear (see AirDropRun), so the
## destination only has to be beyond every possible exit, never exactly on one.
static func exit_xz(map: Map, from_xz: Vector2, heading: Vector2) -> Vector2:
	var direction: Vector2 = heading if not heading.is_zero_approx() else Vector2.RIGHT
	var area: PlayArea = _area_of(map)
	var reach: float = (area.diagonal() if area != null else 0.0) + EXTERIOR_MARGIN * 2.0
	return from_xz + direction.normalized() * reach


## Whether `xz` is clear of the play area by EXTERIOR_MARGIN — i.e. back where it came
## from, and no longer part of the game.
##
## False on a map with no play area, which is the safe answer: a piece that can never be
## judged to have left keeps flying rather than vanishing the tick it spawns.
static func has_left(map: Map, xz: Vector2) -> bool:
	var area: PlayArea = _area_of(map)
	return area != null and area.is_beyond(xz, EXTERIOR_MARGIN)


## This map's play rectangle, or null when it has none to speak of. A degenerate area
## (no heightmap resolved yet) is reported as absent rather than as a zero-sized map, so
## every caller above takes its fallback branch instead of dividing by nothing.
static func _area_of(map: Map) -> PlayArea:
	var area: PlayArea = map.play_area() if map != null else null
	return area if area != null and area.is_valid() else null
