## Editor-only component that previews a Commandable's team colour in the editor.
##
## Scene-placed entities don't run initialize()/_auto_initialize() in the editor
## (Entity/Commandable aren't @tool), so their Sprite never gets the team tint that
## Entity._apply_team_tint() applies at runtime. This @tool child reads the parent's
## default_commander_id and applies the same TEAM_COLOR_MAP tint so units/structures
## show their owner's colour while editing.
##
## At runtime it frees itself immediately — the normal Ownership-driven tint
## (Entity._apply_team_tint, fired from commander_changed) takes over with the
## actually-assigned commander.
@tool
class_name TeamTint
extends Node

#region Properties
var _last_id: int = -1
#endregion

#region Lifecycle
func _ready() -> void:
	if not Engine.is_editor_hint():
		queue_free()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	var entity := get_parent()
	if entity == null:
		return
	var id_value: Variant = entity.get("default_commander_id")
	if not (id_value is int):
		return
	var id: int = id_value
	if id == _last_id:
		return
	var sprite := entity.get_node_or_null("Sprite")
	if sprite == null or not ("modulate" in sprite):
		return
	sprite.modulate = Entity.TEAM_COLOR_MAP.get(id, Color.WHITE)
	_last_id = id
#endregion
