class_name Vanguard
extends Commandable

## Vanguard unit. Its command set (Collect from a Lab, the command_launch →
## Launch sub-context) is declared in CommandContextParser via predicates
## keyed off Entity.Type.UNIT_VANGUARD.

## NODE
func _process(delta: float) -> void:
	super(delta)
	if Engine.is_editor_hint():
		return

	if attack_timer > ATTACK_DURATION-5 and _command!=null:
		$Lazer.global_position = global_position + .5*(_command.message.position-global_position) + Vector3.UP*.5

		# TODO get the 3D mesh to be aligned correctly - I can't get the mesh's major axis to be correct
		$Lazer.rotation = Vector3(-VU.inXZ(_command.message.position-global_position).angle(), 0, deg_to_rad(90))

		$Lazer.scale.y = (_command.message.position-global_position).length()/2
		$Lazer.set_visible(true)
	else:
		$Lazer.set_visible(false)


## WEAPONS
static var vanguard_weapon_patterns: Array[Pattern] = [
	
]

# Instance override now (the Commandable default became an instance method).
# Returning vanguard's LAZER patterns regardless of group membership.
func get_weapon_evaluation_patterns() -> Array:
	return vanguard_weapon_patterns
