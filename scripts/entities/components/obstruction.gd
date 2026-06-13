@tool
class_name Obstruction
extends Node

## How many grid cells this entity blocks in each axis (width × depth).
## Footprint origin is the min-x/min-z corner (top-left in grid space).
@export var dimensions: Vector2i = Vector2i(1, 1)


## Determines whether a structure can be placed on uneven terrain
@export var allow_uneven: bool = false
