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

## Whether the player may add this entity to a SELECTION.
##
## False for a piece that exists on the field but is nobody's to command — the Scan
## sanction's recon drone. Godot cannot remove a node inherited from a base scene, so the
## component is unavoidable; this is how it is switched off.
##
## Expressed as a flag rather than by clearing the node's collision_layer, and that
## distinction cost a bug: the SELECTION layer is what the CURSOR picks against
## (RTSController.get_cursor_target), so a layerless Selectable also became impossible to
## right-click — the drone could not be attacked. Worse, it did not even work: box-select
## reads the "selectables" GROUP rather than the layer, so a drag still caught it. The flag
## is honoured at the one choke point both paths share (select, below), and the entity
## stays pickable, which is what makes it a legal ATTACK target.
@export var selectable_by_player: bool = true


## Whether the player can select this entity — the question Commander.has_anything_in_play
## asks, where "can they still do anything" is what is really meant.
func is_reachable() -> bool:
	return selectable_by_player


#region Signals
signal state_changed(old_state: int, new_state: int)
#endregion

#region Constants
enum State {
	UNSELECTED,
	HOVERED,  ## reserved for hover-highlight (not wired up yet)
	PREVIEW,  ## reserved for in-progress box-drag (not wired up yet)
	SELECTED,
}
#endregion

#region Properties
@export var enabled: bool = true

## Optional path (relative to this Selectable) to a Node3D whose .visible should
## track selection state. Lets scenes wire up the indicator declaratively so
## Commandable doesn't have to know about it in code. A future SelectionVisual
## component will subscribe to state_changed instead and this export will go away.
@export var indicator_path: NodePath

var _state: int = State.UNSELECTED
var _indicator: Node3D = null

## Engine-time (ms) this entity was last selected. Seeded at _ready — i.e. the
## moment the entity is introduced into the game — so a never-selected unit
## still orders sensibly (oldest first) for the controller's
## least-recently-selected idle-unit cyclers. Refreshed each time the entity
## enters the SELECTED state.
@onready var last_selected_time: int = Time.get_ticks_msec()
#endregion


#region Lifecycle
func _ready() -> void:
	add_to_group("selectables")
	if indicator_path != null and not indicator_path.is_empty():
		var node: Node = get_node_or_null(indicator_path)
		if node is Node3D:
			set_indicator(node)
		elif node != null:
			push_warning("Selectable.indicator_path points at non-Node3D: %s" % node)


#endregion

#region Public API
var state: int:
	get:
		return _state
	set(value):
		set_state(value)


func set_state(a_new_state: int) -> bool:
	## Returns true if the state actually changed.
	if not enabled and a_new_state != State.UNSELECTED:
		return false
	if a_new_state == _state:
		return false
	var old: int = _state
	_state = a_new_state
	if a_new_state == State.SELECTED:
		last_selected_time = Time.get_ticks_msec()
	_refresh_indicator()
	state_changed.emit(old, a_new_state)
	return true


func is_selected() -> bool:
	return _state == State.SELECTED


## Both selection paths — the click in RTSController.set_selection and the box drag below
## it — go through here and honour the returned bool, so refusing here is the whole of
## "this cannot be selected".
func select() -> bool:
	if not selectable_by_player:
		return false
	return set_state(State.SELECTED)


func deselect() -> bool:
	return set_state(State.UNSELECTED)


func get_entity() -> Entity:
	return get_parent() as Entity


func set_indicator(a_indicator: Node3D) -> void:
	_indicator = a_indicator
	_refresh_indicator()


#endregion


#region Private helpers
func _refresh_indicator() -> void:
	if _indicator == null:
		return
	# PREVIEW and SELECTED both show the ring for now. A future SelectionVisual
	# can differentiate (e.g., dimmed preview ring during box-drag).
	_indicator.visible = _state == State.SELECTED or _state == State.PREVIEW
#endregion
