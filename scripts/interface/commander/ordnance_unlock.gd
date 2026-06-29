class_name OrdnanceUnlock extends Resource

## One node in a faction's ordnance DAG: it wraps an Ordnance with the dominion cost
## to acquire it and the prerequisites that gate it. A commander may unlock it once
## it owns ANY of its prerequisites (an "any-of" edge, never "all-of") — or
## immediately when it has none.
##
## The DAG is authored by reference: each unlock points at the prerequisite unlocks
## it depends on, and the Faction lists every node in `ordnance_unlocks`. Shared
## sub-resource references form the edges, so there's no separate graph structure to
## maintain. Per-commander ownership and cooldown state lives in OrdnanceArsenal, not
## here — these resources are read-only authored templates.

## The ordnance this node grants once unlocked.
@export var ordnance: Ordnance

## Dominion spent to unlock it.
@export var dominion_cost: int = 0

## Unlocks that gate this one. Owning ANY of them makes this available to unlock.
## Empty = available from the start (a DAG root). Every prerequisite must also appear
## in the faction's ordnance_unlocks list (the node set must be closed).
@export var prerequisites: Array[OrdnanceUnlock] = []
