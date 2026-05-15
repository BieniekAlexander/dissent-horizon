class_name NavGrid extends GridMap

func _ready() -> void:
	$NavigationRegion3D.bake_navigation_mesh()
	push_error($NavigationRegion3D.navigation_mesh.get_polygon_count())
