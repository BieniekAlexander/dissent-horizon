class_name Selectable
extends Area3D

## Selectable component — owns "is this entity currently selected" state.
##
## Step 1 of the components refactor: this node is added as a child of every
## Commandable. The controller continues to own the *set* of selected entities,
## but the per-entity selection bit lives here. Anything that needs to know
## whether an entity is selected (HP bar visibility, debug overlays, future
## SelectionVisual component) should read Selectable.state or listen to
## state_changed instead of inspecting an indicator sprite.
##
## A Selectable does NOT know about commands, ownership, or the controller.
## It exposes its parent via get_entity() and lets callers do their own
## component lookups. This is the boundary that keeps composition from
## collapsing back into implicit coupling.

signal state_changed(old_state: int, new_state: int)

enum State {
	UNSELECTED,
	HOVERED,  ## reserved for hover-highlight (not wired up yet)
	PREVIEW,  ## reserved for in-progress box-drag (not wired up yet)
	SELECTED,
}

@export var enabled: bool = true

## Optional path (relative to this Selectable) to a Node3D whose .visible should
## track selection state. Lets scenes wire up the indicator declaratively so
## Commandable doesn't have to know about it in code. A future SelectionVisual
## component will subscribe to state_changed instead and this export will go away.
@export var indicator_path: NodePath

var _state: int = State.UNSELECTED
var _indicator: Node3D = null

func _ready() -> void:
	add_to_group("selectables")
	if indicator_path != null and not indicator_path.is_empty():
		var node: Node = get_node_or_null(indicator_path)
		if node is Node3D:
			set_indicator(node)
		elif node != null:
			push_warning("Selectable.indicator_path points at non-Node3D: %s" % node)

var state: int:
	get: return _state
	set(value):
		set_state(value)

func set_state(new_state: int) -> bool:
	## Returns true if the state actually changed.
	if not enabled and new_state != State.UNSELECTED:
		return false
	if new_state == _state:
		return false
	var old: int = _state
	_state = new_state
	_refresh_indicator()
	state_changed.emit(old, new_state)
	return true

func is_selected() -> bool:
	return _state == State.SELECTED

func select() -> bool:
	return set_state(State.SELECTED)

func deselect() -> bool:
	return set_state(State.UNSELECTED)

func get_entity() -> Entity:
	return get_parent() as Entity

func set_indicator(indicator: Node3D) -> void:
	_indicator = indicator
	_refresh_indicator()

func _refresh_indicator() -> void:
	if _indicator == null: return
	# PREVIEW and SELECTED both show the ring for now. A future SelectionVisual
	# can differentiate (e.g., dimmed preview ring during box-drag).
	_indicator.visible = _state == State.SELECTED or _state == State.PREVIEW
