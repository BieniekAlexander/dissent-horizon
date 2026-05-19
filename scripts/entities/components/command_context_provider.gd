class_name CommandContextProvider
extends Node

## CommandContextProvider component — exposes the CommandContext this entity
## contributes when it's part of a selected group.
##
## The context is keyed off the parent's Entity.Type via CommandContextRegistry,
## not built per-instance or pulled from CommandReceiver. Different types yield
## different command state machines (a structure can Train, a Vanguard can
## Launch, …) and the controller merges the contexts of every selected type.
##
## Entities without a CommandContextProvider (e.g. neutral resource items like
## Stars) simply don't contribute to the merged context — absence of the
## component IS the "no contribution" signal, so a missing/non-Entity parent
## resolves to the NULL sentinel rather than a default command set.

func get_context() -> CommandContext:
	var parent: Node = get_parent()
	if parent is Entity:
		return CommandContextRegistry.for_type((parent as Entity).type)
	return CommandContext.NULL
