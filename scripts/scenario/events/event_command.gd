@tool
class_name EventCommand
extends Node3D

## Pseudo-abstract base for follow-up command descriptors attached as children
## of scenario events (e.g. EventSpawnUnits). Each subclass produces one Command
## per spawned unit when the owning event executes.
##
## Subclasses must override to_command(); the default returns null (no-op).

## Build a fresh Command for one unit. Called once per spawned unit so each unit
## owns its own Command/CommandMessage (they ref-count the message and must never
## be shared). Returns null if no valid command can be produced (e.g. no matching
## targets exist yet); callers must skip null entries.
func to_command(_manager: ScenarioTriggerManager) -> Command:
	return null
