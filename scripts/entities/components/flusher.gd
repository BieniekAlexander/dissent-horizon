class_name Flusher
extends Node

## Declares that this piece STORMS a garrison: ordered onto a flushable garrison its enemy holds,
## it walks up, kills everything inside and takes the place itself (Flush). Presence is the whole
## capability; the doc key is a bare `flushes: true` — the same key a flushing emission carries.
## Rules: gdd/systems/combat/garrison-and-transport.md §Flushing a garrison.


## Whether `actor` storms garrisons.
static func flushes(actor: Node) -> bool:
	return actor != null and actor.get_node_or_null("Flusher") != null
