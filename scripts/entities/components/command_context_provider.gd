class_name CommandContextProvider
extends Node

## CommandContextProvider component — exposes the CommandContext this entity
## contributes when it's part of a selected group.
##
## Step 4 of the components refactor. The controller previously did
## `c.get_script().get_command_context()` (calling an instance method on a
## Script class — well-defined only when the chain bottomed out at a static
## method, which was a latent footgun). Now it asks each entity's
## CommandContextProvider for its context directly.
##
## The default implementation delegates to the parent entity's existing
## get_command_context() instance method so we don't have to rewrite Structure's
## structure_command_context plumbing, Vanguard's override, etc. in this step.
## A future step can move context construction *into* the provider — at which
## point this becomes a leaf component that simply owns a CommandContext value.
##
## Entities without a CommandContextProvider (e.g. neutral resource items)
## simply don't contribute to the merged context — which is the correct
## behavior. Absence of the component IS the signal.

func get_context() -> CommandContext:
	var parent: Node = get_parent()
	if parent != null and parent.has_method("get_command_context"):
		return parent.get_command_context()
	return CommandContext.NULL
