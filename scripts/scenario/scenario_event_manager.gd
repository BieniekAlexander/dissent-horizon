class_name ScenarioEventManager
extends Node

## Evaluates its Trigger child nodes each physics tick and fires their events
## when conditions are met. Add this as a direct child of the Scenario node, then
## add Trigger child nodes (each with its conditions authored in the inspector and
## references to the ScenarioEvent nodes it fires). Event nodes are also placed as
## children of this manager so they can be positioned in the world.

#region Signals
## Emitted when an EventShowMessage fires. Connect to HUD to display it.
signal message_requested(text: String)
## Emitted when an EventWinLose fires. won=true → player wins, false → loses.
signal game_over(won: bool)
#endregion

#region Properties
## Populated in _ready() from the Trigger child nodes, in scene-tree order.
var triggers: Array[Trigger] = []

var scenario: Scenario
var map: Map

var _fog: Node  # fog.gd MeshInstance3D; cached on first get_fog() call
#endregion

#region Lifecycle
func _ready() -> void:
	var parent := get_parent()
	if parent is Scenario:
		scenario = parent as Scenario
		# Resolve the Map node directly rather than through Scenario's @onready
		# `map` property: a child's _ready() runs before its parent's, so the
		# parent's @onready vars aren't initialized yet at this point. The Map
		# node itself is already in the tree, so get_node finds it.
		map = scenario.get_node_or_null("Map") as Map
	else:
		push_warning("ScenarioEventManager: expected parent to be Scenario, got %s" % parent)

	for child in get_children():
		if child is Trigger:
			triggers.append(child)

	for t: Trigger in triggers:
		t.enabled = not t.starts_disabled


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	for t: Trigger in triggers:
		if not t.enabled:
			continue
		if t.is_satisfied(self):
			t.fire(self)
#endregion

#region Public API
## Number of triggers still active (enabled) — i.e. waiting to fire or able to
## re-fire. A one-shot trigger drops out of this count once it fires and disables
## itself. Used by ConditionNoPendingTriggers to detect "this is the last event."
func active_trigger_count() -> int:
	return triggers.filter(func(t: Trigger) -> bool: return t.enabled).size()


## Return the Commander with the given id, or null.
func get_commander(id: int) -> Commander:
	if scenario == null:
		return null
	for c: Commander in scenario.commanders:
		if c.id == id:
			return c
	return null


## Return the Fog node (the one running fog.gd), or null if none exists.
## The Fog node lives in the player Commander's subtree (scenes/player.tscn).
func get_fog() -> Node:
	if _fog != null and is_instance_valid(_fog):
		return _fog
	_fog = get_tree().current_scene.find_child("Fog", true, false)
	return _fog
#endregion
