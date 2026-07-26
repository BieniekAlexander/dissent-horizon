@tool
class_name EventCommand
extends EditorMarkerSprite3D

## Pseudo-abstract base for follow-up command descriptors attached as children
## of scenario events (e.g. EventSpawnUnits). Each subclass produces one Command
## per spawned unit when the owning event executes.
##
## Subclasses must override to_command(); the default returns null (no-op).
##
## Extends EditorMarkerSprite3D so each command point shows a clickable, draggable
## marker in the 3D editor (hidden at runtime).

## Build a fresh Command for one unit. Called once per spawned unit so each unit
## owns its own Command/CommandMessage (they ref-count the message and must never
## be shared). Returns null if no valid command can be produced (e.g. no matching
## targets exist yet); callers must skip null entries.
##
## `post_offset` is a per-unit planar offset applied to positional destinations so a group
## fans into a formation instead of stacking on one point (subclasses that target an entity
## rather than a position ignore it).
func to_command(_manager: ScenarioTriggerManager, _post_offset: Vector3 = Vector3.ZERO) -> MoveCommand:
	return null
