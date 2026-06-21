@tool
class_name EntitySelector
extends Node3D

## Abstract base for entity-selection pipeline stages attached as children of an
## EventIssueCommand or EffectApplicator. Each subclass narrows the input list. Stages
## are applied in scene-tree order; the first stage receives the caller's seed.
##
## Operates on Entity (not Commandable): an effect/selection may legitimately target any
## Entity. A stage that needs a narrower kind (e.g. only Commandables, for command
## issuance) is itself just a predicate — express it as a selector, don't bake it into
## the base type.

func filter(entities: Array[Entity], _manager: ScenarioTriggerManager) -> Array[Entity]:
	return entities
