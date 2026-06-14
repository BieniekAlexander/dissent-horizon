@tool
class_name Lab
extends Commandable

#region Lifecycle
func _on_death() -> void:
	var projectile: HitBox = preload("res://scenes/projectiles/radiation.tscn").instantiate()
	map.add_entity(projectile, xz_position, commander)
	super()
#endregion
