class_name ObjectiveChain
extends Node

## Runs its GlobalTrigger children one at a time, in scene-tree order: only the first is
## armed at the start, and each one completing reveals the next.
##
## Pure sugar over GlobalTrigger.prerequisites: it wires each step to depend on the one
## above it, and the manager's ordinary DAG arming does the rest. So a chain is exactly the
## dependency graph you would have drawn by hand — it just spares you drawing the straight
## line, which is the shape most missions are.
##
## Add it as a child of the ScenarioTriggerManager and put GlobalTrigger nodes under it. The
## manager collects them into its own `global_triggers` list, so from the arming and firing
## machinery's point of view they are ordinary triggers that merely happen to be gated.
##
## A chain is about ORDER, not about being player-facing: set `scope` on the steps you want in
## the HUD checklist, exactly as you would on a standalone trigger. A chain step left at
## ObjectiveScope.NONE still sequences, it just isn't shown.
##
## Branching or optional steps are deliberately out of scope: for those, drop the chain and
## wire EventChainTrigger by hand, which can express any graph.

#region Signals
## Emitted once, when the last step completes.
signal chain_completed(chain: ObjectiveChain)
#endregion

#region Properties
## Ordered steps, collected from the child nodes in _ready.
var steps: Array[GlobalTrigger] = []
#endregion


#region Lifecycle
## Wire the chain into dependency edges BEFORE the manager reads them.
##
## Ordering is what makes this work: a child's _ready runs before its parent's, and this node
## is a child of the ScenarioTriggerManager, so every edge added here is already in place when
## the manager's own _ready collects triggers, checks for cycles, and (later, once the navmesh
## is ready) arms them.
##
## Edges are APPENDED, not assigned: a step is allowed to also depend on something outside the
## chain, and replacing the array would silently drop that.
func _ready() -> void:
	for child: Node in get_children():
		if child is GlobalTrigger:
			steps.append(child as GlobalTrigger)

	for i: int in steps.size():
		if i > 0 and steps[i - 1] not in steps[i].prerequisites:
			steps[i].prerequisites.append(steps[i - 1])
		steps[i].fired.connect(_on_step_fired.bind(steps[i]))


#endregion


#region Public API
## The step the player is currently working on, or null when the chain is finished (or
## hasn't been armed yet).
func active_step() -> GlobalTrigger:
	for step: GlobalTrigger in steps:
		if step.objective_state() == GlobalTrigger.ObjectiveState.ACTIVE:
			return step
	return null


## Index of the active step in the chain, or -1.
func active_index() -> int:
	for i: int in steps.size():
		if steps[i].objective_state() == GlobalTrigger.ObjectiveState.ACTIVE:
			return i
	return -1


func is_complete() -> bool:
	return not steps.is_empty() and steps.all(func(s: GlobalTrigger) -> bool: return s.has_fired)


#endregion


#region Sequencing
## Announce the end of the chain. Revealing the NEXT step is not done here — the edge added in
## _ready means the manager arms it as part of walking the DAG, exactly as it would for a
## hand-authored dependency.
func _on_step_fired(a_step: GlobalTrigger) -> void:
	if steps.find(a_step) == steps.size() - 1:
		chain_completed.emit(self)
#endregion
