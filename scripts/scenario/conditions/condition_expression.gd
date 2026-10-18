@tool
class_name ConditionExpression
extends Condition

## True while an authored expression holds (see ScenarioExpression): a comparison is taken as it
## is, a number is true while nonzero. Its first use is gating a trigger or a tactic rule by the
## mission's difficulty — "difficulty >= 2" — composed with the trigger's other conditions by
## ALL_OF / ANY_OF rather than by a field on every trigger class.
## gdd/systems/scenario-scripting/tactics.md §Trigger-decided mission commanders.
##
## A PULL condition: re-evaluated every poll, so an expression over `tick` or `seconds` changes
## truth as the session runs. A blank or broken expression is false, and the Scene dock says why.

@export_placeholder("e.g. difficulty >= 2") var expression: String = ""


#region Public API
func evaluate(a_manager: ScenarioTriggerManager) -> bool:
	return ScenarioExpression.evaluate_bool(
		expression, false, a_manager, owner_fire_count(), "ConditionExpression"
	)


func configuration_warning() -> String:
	if not ScenarioExpression.is_authored(expression):
		return "Expression is blank, so this condition is never true"
	var problem: String = ScenarioExpression.validation_error(expression, true)
	if problem.is_empty():
		return ""
	return 'Expression "%s" %s' % [expression, problem]
#endregion
