class_name StructureCommandContextProvider
extends CommandContextProvider

## Variant of CommandContextProvider that adds the structure-flavored Train/
## Command dispatch patterns to whatever the base provider returns. Used on
## structure.tscn so structures can be told to train units and accept rally
## points while keeping the base CommandContextProvider clean.
##
## Stage D of the collapse. Previously these patterns lived in Structure as
## `structure_command_context`; with Structure gone, they live here, attached
## to scenes via composition rather than via inheritance.

var _cached_context: CommandContext

func get_context() -> CommandContext:
	if _cached_context == null:
		var base: CommandContext = super.get_context()
		if base == null:
			base = CommandContext.NULL
		_cached_context = CommandContext.merge(
			CommandContext.new(
				[
					Pattern.new(func(_a): return _a[1].tool != null, Train),
					Pattern.new(func(_a): return true, Command),
				]
			),
			base
		)
	return _cached_context
