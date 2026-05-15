class_name Entity
extends CharacterBody3D


### IDENTIFIERS


#### TYPE ENUMERATION
# I need to enumerate because I can't peek into packed scenes
@export var type: Type

enum Type {
	# 3 - Faction {0: generic, 1: tech}
	# 2 - Type {0: entity, 1: unit, 2: structure}
	# 1 - Index
	# 0 - Index
	UNDEFINED=-1,
	STRUCTURE_OUTPOST=0x1200,
	STRUCTURE_DWELLING=0x1201,
	STRUCTURE_MINE=0x1202,
	STRUCTURE_LAB=0x1203,
	STRUCTURE_COMPOUND=0x1204,
	STRUCTURE_ARMORY=0x1205,
	UNIT_TECHNICIAN=0x1100,
	UNIT_SENTRY=0x1101,
	UNIT_VANGUARD=0x1102
}

## Ownership component — owns the commander relationship. Resolved at _ready
## time (scene composition: see unit.tscn, structure.tscn). Entities without
## an Ownership child (e.g. star.tscn) fall back to the private _commander
## field below.
@onready var ownership: Ownership = get_node_or_null("Ownership") as Ownership

## Movement component — wraps NavigationAgent3D for entities that pathfind.
## Null for entities that don't (structures, items). Callers must gate on
## `movement != null` before using it.
@onready var movement: Movement = get_node_or_null("Movement") as Movement

## Fallback storage used (a) before _ready resolves `ownership`, and (b) when
## the entity scene doesn't include an Ownership component at all. _ready
## migrates any pre-tree value into ownership.commander.
var _commander: Commander
var commander: Commander:
	get:
		if ownership != null: return ownership.commander
		return _commander
	set(value):
		if ownership != null:
			ownership.commander = value
		else:
			_commander = value

var commander_id: int:
	get:
		if ownership != null: return ownership.commander_id
		return _commander.id if _commander != null else 0

const TEAM_COLOR_MAP: Dictionary = {
	0: Color.WHITE,
	1: Color(.2, 1, 1),
	2: Color(1, 1, .2),
	3: Color(.1, .6, .1),
	4: Color(1, .2, .2)
}


### VISION
@export_range(0, 100) var sight_range: int = 20

### PHYSICAL STATS
enum LocomotionMode { GROUNDED, FLYING }
enum Armor { LIGHT, HEAVY }
enum Attribute { MECH, BIO, UNMANNED }

@export var armor: Armor = Armor.LIGHT
@export var attributes_list: Array[Attribute] = []
var attributes: Set

@export var hpMax: float = 100
@onready var hp: float = hpMax
@onready var inventory: Array[Entity] = []
@onready var inventory_capacity: int = 1

@export var AGGRO_RANGE: float = 5
@export var DAMAGE: float = 10
@export var ATTACK_RANGE: float = 0
@export var ATTACK_DURATION: int = 10
var attack_timer: int = 0

@export var SPEED: float = .25
@onready var SPEED_PER_SECOND: float = SPEED * Engine.physics_ticks_per_second

### COLLISION
var xz_position: Vector2:
	get: return VU.inXZ(global_position)
	set(value): global_position = VU.fromXZ(value)

var map: Map
var pc_set: Set = Set.new()
@onready var collider: CollisionShape3D = get_node_or_null("Collider")

# TODO: unused function
#func get_collision_extents() -> Array[Vector2]:
#	var collider_radius
#	match typeof(collider.shape):
#		SphereShape3D: collider_radius = collider.shape.radius
#		BoxShape3D: collider_radius = collider.shape.size.x*sqrt(2)
#		ConcavePolygonShape3D:  collider_radius = 1
#		_: collider_radius = 1
#
#	return [
#		VU.inXZ(global_position),
#		VU.inXZ(global_position)+Vector2.UP*collider_radius,
#		VU.inXZ(global_position)+Vector2.DOWN*collider_radius,
#		VU.inXZ(global_position)+Vector2.LEFT*collider_radius,
#		VU.inXZ(global_position)+Vector2.RIGHT*collider_radius
#	]

var collision_radius: float:
	get:
		var shape = $Collider.shape
		if shape is SphereShape3D: return shape.radius
		elif shape is BoxShape3D: return max(shape.size.x, shape.size.z)
		else:
			assert(false, "unhandled collider type %s" % typeof(shape))
			return -1.0


### NODE
func _ready() -> void:
	add_to_group("entity")
	if ownership != null:
		ownership.commander_changed.connect(_on_commander_changed)
		# Migrate any pre-tree commander value (set via initialize() before the
		# entity entered the scene tree) into Ownership so the component is the
		# single source of truth from here on.
		if _commander != null and ownership.commander == null:
			ownership.commander = _commander
			_commander = null
	_apply_team_tint()

func _on_commander_changed(_old_commander: Commander, _new_commander: Commander) -> void:
	_apply_team_tint()

func _apply_team_tint() -> void:
	# Previously this lived inline in the commander setter, which meant the
	# setter had to know about the Sprite child. Now it's a separate concern
	# driven by Ownership's commander_changed signal; a future SpriteVisual
	# component should own this logic entirely.
	var sprite: Node = get_node_or_null("Sprite")
	if sprite != null and "modulate" in sprite:
		sprite.modulate = TEAM_COLOR_MAP.get(commander_id, Color.WHITE)

func initialize(a_map: Map, a_commander: Commander):
	map = a_map
	commander = a_commander
	commander.add_child(self)

func _on_death() -> void:
	for coords: Vector2i in pc_set.get_values():
		map.spatial_partition_grid[coords.x][coords.y].remove(self)
	
	queue_free()
