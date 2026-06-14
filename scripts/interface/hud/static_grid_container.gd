class_name StaticGridContainer
extends Container

#region Properties
@export var grid_dimensions: Vector2i = Vector2.ZERO

var control_size: Vector2:
	get: return Vector2(
		size.x/grid_dimensions.x,
		size.y/grid_dimensions.y
	)
#endregion

#region Public API
func grid_index_to_position(a_grid_index: Vector2i) -> Vector2:
	return Vector2(
		control_size.x*a_grid_index.x,
		control_size.y*a_grid_index.y
	)
#endregion

#region Lifecycle
func _ready() -> void:
	assert(
		get_children().all(
			func(b: StaticGridButton): return (
				b.grid_index.x>=0 and b.grid_index.x<grid_dimensions.x
				and b.grid_index.y>=0 and b.grid_index.y<grid_dimensions.y
			)
		),
		"One of the buttons doesn't have a proper grid position"
	)

	for b: StaticGridButton in get_children():
		b.custom_minimum_size = control_size
		var control_position: Vector2 = grid_index_to_position(b.grid_index)
		b.set_position(control_position, true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		for c in get_children():
			fit_child_in_rect(c, Rect2(Vector2(), size))
#endregion
