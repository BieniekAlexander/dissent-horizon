class_name BeaconPlanter
extends Node

## Declares that this piece SPOTS BY PLANTING: its Spot order walks to the point itself,
## channels, and leaves a ground beacon behind — the same point beacon a Beacon Drop places —
## then ends, free to move on. A spotter without one HOLDS its beacon instead (the Recruit).
## Presence is the whole capability; the doc key is a bare `plants_beacons: true`.
## Rules: gdd/systems/combat/bombardment.md §Planting a beacon.

## How close to the point the planter must stand to plant, in world units: at the point, with
## room for the arrival tolerance of a unit that cannot stand exactly on it.
const PLANT_REACH: float = 1.0


## Whether `actor` spots by planting rather than by holding.
static func plants(actor: Node) -> bool:
	return actor != null and actor.get_node_or_null("BeaconPlanter") != null
