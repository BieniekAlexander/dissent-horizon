@tool
class_name EditorMarkerSprite3D
extends Sprite3D

## A Sprite3D that shows a small, camera-facing authoring icon in the 3D editor so the
## node can be click-selected and dragged in the viewport — the same idea as HeightPin.
## It replaces the old hand-drawn _process/ImmediateMesh gizmos, which weren't pickable.
##
## At runtime the marker hides itself (the node keeps running its logic — unlike HeightPin,
## which deletes itself, these are live scenario nodes). Scenario events, command points,
## and global triggers extend this instead of Node3D so their markers are directly
## selectable in the viewport.
##
## Subclasses currently have no _ready of their own; if one is added it MUST call
## super._ready() so the icon/runtime-hide still applies.

## Fallback icon used only when the node's own `texture` is unset. Set `texture` in the
## inspector/scene to override per node — the base just visualizes whatever `texture` holds.
const _DEFAULT_ICON: Texture2D = preload("res://assets/logo.png")

## Tint applied to the editor icon (helps tell marker classes apart at a glance).
@export var marker_color: Color = Color(1.0, 0.7, 0.2)


func _ready() -> void:
	if not Engine.is_editor_hint():
		visible = false  # editor-only authoring marker; node still executes at runtime
		return
	if texture == null:
		texture = _DEFAULT_ICON
	modulate = marker_color
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true    # show through terrain so markers are always reachable
	pixel_size = 0.004
