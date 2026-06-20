@tool
class_name EntitySelector
extends Node3D

## Abstract base for unit-selection pipeline stages attached as children of
## EventIssueCommand. Each subclass narrows the input list. Stages are applied
## in scene-tree order; the first stage receives all scene units as its seed.

func filter(units: Array[Commandable], _manager: ScenarioTriggerManager) -> Array[Commandable]:
	return units
