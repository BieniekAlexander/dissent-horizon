## Abstracts the set of arguments that can be provided to a command
class_name CommandMessage

#region Properties
var map: Map				# the game map, passed for gamestate checks
var target: Entity			# The entity which will be the recipient of the command
var tool: Tool				# Any potential thing that is used in the fulfillment of a command
var world_position: Vector3	# The raw position at which the command is requested (NOTE: `target` might not always be relevant)
var ability_type: Variant	# For Ability commands: which Ability.Type to invoke (null otherwise)
var aggro_shape: CollisionShape3D	# Largest aggro shape in the issuing group (Defend); null → each unit uses its own

## When true, the commandable pursues this command to completion regardless of the
## "still worth it?" checks that MoveCommand.get_updated_state runs while `not persist`.
## Defaults false; e.g. idle-aggro acquisition sets it true so a guarding unit
## chases the target it spotted even after the target leaves its aggro range.
var persist: bool = true

## Emitted when the last MoveCommand holding this message releases it, signalling
## that no live commands still reference this snapshot.
signal unreferenced

var _ref_count: int = 0

var position: Vector3:
	get:
		# Keep the target's real Y (its terrain height), not a zeroed ground plane,
		# so position-based renderers (waypoint + command-line indicators) sit at
		# the target's height instead of a constant Y=0. xz_position drops Y anyway,
		# and nav targets snap to the navmesh, so those consumers are unaffected.
		if target!=null and is_instance_valid(target):
			return target.global_position
		else:
			return world_position

var xz_position: Vector2:
	get: return VU.inXZ(position)
#endregion

#region Lifecycle
func _init(a_map: Map, a_target: Entity = null, a_tool: Tool = null, a_world_position: Vector3 = Vector3.ZERO, a_ability_type: Variant = null) -> void:
	map = a_map
	target = a_target
	tool = a_tool
	world_position = a_world_position
	ability_type = a_ability_type
#endregion

#region Public API
func retain() -> void:
	_ref_count += 1

func release() -> void:
	_ref_count -= 1
	if _ref_count <= 0:
		unreferenced.emit()

func clear() -> void:
	target = null
	tool = null
	ability_type = null

static func deep_copy(a_message: CommandMessage) -> CommandMessage:
	var copy := CommandMessage.new(
		a_message.map,
		a_message.target,
		a_message.tool,
		a_message.world_position,
		a_message.ability_type
	)
	copy.persist = a_message.persist
	copy.aggro_shape = a_message.aggro_shape
	return copy
#endregion
