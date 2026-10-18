class_name MissionLane
extends RefCounted

## Prologue mission 1's lane, in the coordinates its layout is written in: ALONG the lane, west
## (negative) to east (positive), and ACROSS it, south (negative) to north (positive), both in
## world units from the lane's centre — which is the map's origin, since the play rectangle is
## centred on the grid. "West" and "north" are screen directions at the default camera
## (TerrainData.play_size: screen-right is t = x - z, screen-up is -(x + z)).
##
## Shared by the terrain tool (PLAY_SIZE) and the layout builder (to_world), so the lane's size
## is stated once.

## The play rectangle, in diamonds: `.x` the lane's on-screen height, `.y` its length.
const PLAY_SIZE: Vector2i = Vector2i(20, 100)


## The lane's half-length along it, in world units: a half-extent of PLAY_SIZE.y in t is
## PLAY_SIZE.y / √2 along the screen-right axis.
static func half_length() -> float:
	return float(PLAY_SIZE.y) / sqrt(2.0)


## The lane's half-width across it, in world units.
static func half_width() -> float:
	return float(PLAY_SIZE.x) / sqrt(2.0)


## The Map-local world position `a_along` east and `a_across` north of the lane's centre, at
## height `a_height`.
static func to_world(a_along: float, a_across: float, a_height: float = 0.0) -> Vector3:
	var t: float = a_along * sqrt(2.0)
	var s: float = -a_across * sqrt(2.0)
	return Vector3((s + t) * 0.5, a_height, (s - t) * 0.5)
