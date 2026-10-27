@tool
class_name TacticRule
extends EventIssueCommand

## One rule in a ScenarioTactic's ordered list: "while `condition` holds, this is what the
## cluster should be doing." A null `condition` always matches — the same "nothing to wait for"
## idiom GlobalTrigger gives an empty `conditions` array — so a rule with no condition, placed
## last, reads as the cluster's default/fallback behaviour.
##
## WHAT it does is `action`: COMMANDS runs this node's own EventCommand children (a scripted
## route, the cluster's original vocabulary); every other action is one of the SquadPolicies the
## bot's own squads run, so a mission and the bot speak the same verbs
## (gdd/systems/scenario-scripting/tactics.md §Trigger-decided mission commanders). Those that
## stand somewhere name the place by `point_path`, a Node3D under the rule.
##
## Extends EventIssueCommand rather than wrapping one: the chain-building it already does
## (EventCommand children, per-unit formation offsets, the Defend aggro-shape override) is
## exactly what COMMANDS needs. ScenarioTactic calls issue_commands_to() directly and never
## execute() — the same bypass EventSpawnEntities already relies on for a nested
## EventIssueCommand, since a rule's recipients are the tactic's live cluster, not whatever
## execute()'s own EntitySelector pipeline would find.

## What the rule keeps the cluster doing.
##   COMMANDS — this rule's EventCommand children, as a chain (TacticRulePolicy).
##   HOLD     — stand at the point (HoldPolicy).
##   STAGE    — gather at the point and wait to be handed on (StagePolicy).
##   ASSAULT  — attack-move on the point (AssaultPolicy, with no believed structure to raze).
##   ESCORT   — carry `escort_of`'s squad where its own rule sends it (EscortPolicy, transport).
##   RETREAT  — take cover, else walk to the point or home (RetreatPolicy).
##   BUILD    — keep a `structure_type` standing at the point (BuildPolicy).
enum Action { COMMANDS, HOLD, STAGE, ASSAULT, ESCORT, RETREAT, BUILD }

@export var condition: Condition
@export var action: Action = Action.COMMANDS
## While this rule wins, the cluster holds fire: no member picks a target of its own, though an
## order to attack still attacks. Released when a rule without it takes over.
@export var holds_fire: bool = false
## The Node3D whose position is the rule's point: HOLD, STAGE, ASSAULT and BUILD need one;
## RETREAT falls back to each member's nearest own structure without one.
@export var point_path: NodePath
## ESCORT: the ScenarioTactic whose squad this cluster carries.
@export var escort_of: NodePath
## BUILD: the piece id of the structure to keep standing.
@export var structure_type: StringName = &""


## The rule's point, or null when it names none (or names something that is not placed).
func point() -> Variant:
	if point_path.is_empty():
		return null
	var node := get_node_or_null(point_path) as Node3D
	return node.global_position if node != null else null


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var needs_point: bool = action in [Action.HOLD, Action.STAGE, Action.ASSAULT, Action.BUILD]
	if needs_point and (get_node_or_null(point_path) as Node3D) == null:
		warnings.append(
			"%s needs Point Path to name a Node3D under the rule" % Action.find_key(action)
		)
	if action == Action.ESCORT and (get_node_or_null(escort_of) as ScenarioTactic) == null:
		warnings.append("ESCORT needs Escort Of to name the ScenarioTactic it carries")
	if action == Action.BUILD and structure_type.is_empty():
		warnings.append("BUILD needs a Structure Type")
	if condition != null:
		for problem: String in [condition.configuration_warning(), condition.perspective_warning()]:
			if not problem.is_empty():
				warnings.append(problem)
	return warnings
