class_name MissionLane
extends RefCounted

## Prologue mission 1's map, in the coordinates its layout is written in: ALONG, west (negative)
## to east (positive), and ACROSS, south (negative) to north (positive), both in world units.
## "West" and "north" are screen directions at the default camera (TerrainData.play_size:
## screen-right is t = x - z, screen-up is -(x + z)). The frame's origin is the centre of the
## main west–east corridor, which is why the main corridor's pieces sit near (0, 0); the play
## rectangle is centred on the grid, so the map's centre is CENTRE in this frame.
##
## Shared by the terrain tool (PLAY_SIZE, CENTRE, its regions) and the layout builder
## (to_world), so the frame is stated once.

## The play rectangle, in diamonds: `.x` its on-screen height, `.y` its on-screen width. Sized to
## the terrain tool's regions plus a 6-unit hillside margin: about 226 along x 119 across.
const PLAY_SIZE: Vector2i = Vector2i(84, 160)
## The play rectangle's centre in this frame, in world units.
const CENTRE := Vector2(34.0, 12.0)


## The Map-local world position `a_along` east and `a_across` north of the main corridor's
## centre, at height `a_height`.
static func to_world(a_along: float, a_across: float, a_height: float = 0.0) -> Vector3:
	var t: float = (a_along - CENTRE.x) * sqrt(2.0)
	var s: float = -(a_across - CENTRE.y) * sqrt(2.0)
	return Vector3((s + t) * 0.5, a_height, (s - t) * 0.5)


## The (along, across) of Map-local world position `a_world`: the inverse of to_world, ignoring
## height.
static func to_lane(a_world: Vector3) -> Vector2:
	return (
		Vector2((a_world.x - a_world.z) / sqrt(2.0), -(a_world.x + a_world.z) / sqrt(2.0)) + CENTRE
	)
