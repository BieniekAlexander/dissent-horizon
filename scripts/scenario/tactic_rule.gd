@tool
class_name TacticRule
extends EventIssueCommand

## One rule in a ScenarioTactic's ordered list: "while `condition` holds, this is the
## command chain the cluster should be running." A null `condition` always matches — the
## same "nothing to wait for" idiom GlobalTrigger gives an empty `conditions` array — so a
## rule with no condition, placed last, reads as the cluster's default/fallback behaviour.
##
## Extends EventIssueCommand rather than wrapping one: the chain-building it already does
## (EventCommand children, per-unit formation offsets, the Defend aggro-shape override) is
## exactly what a rule's action needs. ScenarioTactic calls issue_commands_to() directly and
## never execute() — the same bypass EventSpawnEntities already relies on for a nested
## EventIssueCommand, since a rule's recipients are the tactic's live cluster, not whatever
## execute()'s own EntitySelector pipeline would find.

@export var condition: Condition
