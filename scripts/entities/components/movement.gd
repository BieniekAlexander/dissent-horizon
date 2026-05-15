class_name Movement
extends Node

## Movement component — wraps a NavigationAgent3D and exposes the pathfinding
## API the rest of the game cares about.
##
## Stage A of the Unit/Structure collapse. Previously NavigationAgent3D was a
## direct child of Unit, with `Unit._nav_agent` referenced by name in command
## machinery (CommandReceiver). That meant any non-Unit entity that wanted to
## navigate had to either subclass Unit or have a sibling agent that nobody
## knew how to find. Now any entity that has a Movement component can navigate;
## entities without one return null from `entity.movement`, and callers gate
## on that.
##
## Movement does not own move_and_slide() — that lives on the entity root
## (CharacterBody3D). Movement just produces the velocity via the avoidance
## system and emits velocity_ready; the entity applies it.

signal velocity_ready(velocity: Vector3)

## Path (relative to this Movement node) to the NavigationAgent3D this
## component wraps. Set in the scene file.
@export var nav_agent_path: NodePath

var _nav_agent: NavigationAgent3D

var target_position: Vector3:
	get:
		return _nav_agent.target_position if _nav_agent != null else Vector3.ZERO
	set(value):
		if _nav_agent != null:
			_nav_agent.target_position = value

func _ready() -> void:
	if not nav_agent_path.is_empty():
		_nav_agent = get_node_or_null(nav_agent_path) as NavigationAgent3D
	if _nav_agent != null:
		_nav_agent.velocity_computed.connect(_on_velocity_computed)

func set_target_position(world_position: Vector3) -> void:
	target_position = world_position

func set_velocity(velocity: Vector3) -> void:
	if _nav_agent != null:
		_nav_agent.set_velocity(velocity)

func is_navigation_finished() -> bool:
	return _nav_agent.is_navigation_finished() if _nav_agent != null else true

func get_next_path_position() -> Vector3:
	return _nav_agent.get_next_path_position() if _nav_agent != null else Vector3.ZERO

## Configure avoidance so units of the same commander avoid each other but
## not units of other commanders (or vice versa, depending on game design).
## This used to live in Unit._ready as `_nav_agent.avoidance_layers = 1<<commander.id`.
func set_avoidance_team(commander_id: int) -> void:
	if _nav_agent != null:
		var mask: int = 1 << commander_id
		_nav_agent.avoidance_layers = mask
		_nav_agent.avoidance_mask = mask

func _on_velocity_computed(velocity: Vector3) -> void:
	velocity_ready.emit(velocity)
