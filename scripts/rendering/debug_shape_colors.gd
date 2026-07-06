class_name DebugShapeColors

## Single source of truth for debug-shape colors, keyed by the `debug_shape_*` group a
## CollisionShape3D belongs to (see the entity scenes and scene_visibility_tools plugin).
## The plugin applies these to each shape's `debug_color` on scene load, so every shape
## of a class renders the same color in the editor without per-scene values that can
## drift. Change a color here and it takes effect project-wide on the next scene open.
##
## Only physics shapes (CollisionShape3D) are colored; FootprintVisualizer is a drawn
## Node3D, not a shape, so it is intentionally absent and keeps its own color.

const GROUP_COLOR: Dictionary = {
	"debug_shape_attack_range":    Color(0.85, 0.01, 0.0, 0.42),  # reddish
	"debug_shape_aggro_range":     Color(1.0, 0.55, 0.1, 0.35),   # amber
	"debug_shape_vision_range":    Color(0.2, 0.6, 1.0, 0.30),    # blue
	"debug_shape_detection_range": Color(0.7, 0.2, 0.9, 0.35),    # purple (stealth reveal)
	"debug_shape_movement_body":   Color(0.8, 0.8, 0.8, 0.40),    # grey
	"debug_shape_target_body":     Color(1.0, 0.9, 0.2, 0.35),    # yellow
	"debug_shape_selection":       Color(0.2, 0.9, 0.3, 0.30),    # green
	"debug_shape_trigger":         Color(0.2, 0.85, 0.9, 0.30),   # cyan (event-trigger area)
}
