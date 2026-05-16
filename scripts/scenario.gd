#@tool
class_name Scenario
extends Node3D


### GAME STATE
var frame: int = 0
@onready var commanders: Array = range(3).map(
	func(o):
		var c = (
			load("res://scenes/player.tscn").instantiate() if o == 1
			else Bot.new() if o >= 2
			else Commander.new()
		)
		c.id = o
		return c
)

### GAME WORLD
@onready var map: Map = $Map


### NODE
func _ready() -> void:
	var players_node = Node3D.new()
	players_node.name = "Players"
	add_child(players_node, true)
	players_node.set_owner(self)
	
	for commander in commanders:
		players_node.add_child(commander)
		commander.set_owner(self)
	
	for commander: Commander in commanders: # setting camera
		if commander.has_node("Camera"):
			commander.get_node("Camera").make_current()
			var camera: Node3D = commander.get_node("Camera")
			camera.look_at(Vector3.ZERO)
			# camera.rotate_x(deg_to_rad(180))
		
	if Engine.is_editor_hint():
		set_physics_process(false)

func _physics_process(delta: float) -> void:
	pass
	# $Map.nav_region.bake_navigation_mesh(false)

# TODO: unused function
#func purge() -> void:
#	if has_node("Players"):
#		$Players.queue_free()
	
