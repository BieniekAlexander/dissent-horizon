class_name Train
extends Command

## Which units a producer can train is no longer answered here — that capability
## now lives on the Production component (see production.gd `producible_types` /
## `can_produce`), configured per structure scene. CommandContextParser inspects
## the entity's Production node to build the train menu, so this command class
## carries only the train action's behavior.

#region Preconditions
static func requires_position() -> bool:
	## Indicates whether this command requires a specified position to be issued
	return false
#endregion
