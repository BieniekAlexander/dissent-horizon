@tool
class_name EffectApplicator
extends AbstractEvent

## Composable "apply an effect to a set of units" node — the effect analogue of
## EventIssueCommand. Children are two kinds, applied in scene-tree order:
##
##   * StatusEffect nodes  — the TEMPLATES to apply (one or more). Each is duplicate()d
##                           per recipient and attached to it.
##   * EntitySelector nodes — a recipient-selection PIPELINE (the EntitySelector pattern):
##                           each narrows the previous output. The seed depends on caller.
##
## Authoring example (mirrors the requested shape):
##
##   EffectApplicator                 # the "Effect (slow)"
##     SlowStatusEffect               # what is applied
##     EntitySelectorAttribute        # who: narrow by attribute
##     EntitySelectorInArea           # who: narrow by area
##
## Two activation contexts, one implementation:
##   * Under a Projectile: the projectile calls apply() on impact, seeding with the units
##     it hit (so EntitySelectorInArea is optional — the hit_shape already scoped them).
##   * Under a GlobalTrigger: it extends AbstractEvent, so the trigger fires execute(),
##     which seeds with EVERY unit in the scene and lets the selectors do the scoping.

#region Public API
## Trigger-driven entry point (GlobalTrigger.fire → ScenarioTriggerManager.run_event).
## Seeds with all scene units; the selector pipeline scopes them.
func execute(manager: ScenarioTriggerManager) -> void:
	apply(_all_scene_units(manager), null, manager)


## Apply the child status effects to `seed`, narrowed by the child selector pipeline.
## `a_source` is the inflictor (for damage attribution); `manager` is forwarded to
## selectors that need it (most ignore it) and may be null (e.g. projectile impact).
func apply(seed: Array[Commandable], a_source: Commandable = null, manager: ScenarioTriggerManager = null) -> void:
	var recipients: Array[Commandable] = seed
	for sel: EntitySelector in _selectors():
		recipients = sel.filter(recipients, manager)
	if recipients.is_empty():
		return
	var templates: Array[StatusEffect] = _effect_templates()
	for entity: Commandable in recipients:
		for template: StatusEffect in templates:
			var effect: StatusEffect = template.duplicate() as StatusEffect
			effect.apply_to(entity, a_source)
#endregion

#region Children
func _selectors() -> Array[EntitySelector]:
	var result: Array[EntitySelector] = []
	for child: Node in get_children():
		if child is EntitySelector:
			result.append(child as EntitySelector)
	return result


func _effect_templates() -> Array[StatusEffect]:
	var result: Array[StatusEffect] = []
	for child: Node in get_children():
		if child is StatusEffect:
			result.append(child as StatusEffect)
	return result


func _all_scene_units(manager: ScenarioTriggerManager) -> Array[Commandable]:
	var result: Array[Commandable] = []
	for node: Node in manager.get_tree().get_nodes_in_group("unit"):
		var c: Commandable = node as Commandable
		if c != null:
			result.append(c)
	return result
#endregion
