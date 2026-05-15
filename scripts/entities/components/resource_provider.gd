class_name ResourceProvider
extends Node

## ResourceProvider component — what this entity contributes to (or consumes
## from) its commander's resource pools.
##
## Stage B of the Unit/Structure collapse. Previously these were @export'd on
## Structure itself, with Structure.initialize and Structure._on_death calling
## commander.population_max += population_provided inline. Now those reads
## come from this component, and apply_to/remove_from encapsulate the
## bidirectional accounting.
##
## Today this only covers population. As more resource types get tracked
## (ore production rate, energy upkeep, etc.), they'd join this component
## rather than spawning per-resource components.

@export var population_provided: int = 0
@export var population_required: int = 0

## Register this entity's contribution with the commander. Called by the
## entity's initialize().
func apply_to(commander: Commander) -> void:
	if commander == null: return
	commander.population_max += population_provided
	commander.population_used += population_required

## Unregister this entity's contribution. Called by the entity's _on_death.
func remove_from(commander: Commander) -> void:
	if commander == null: return
	commander.population_max -= population_provided
	commander.population_used -= population_required
