@tool
class_name HeightmapGenerator
extends Resource

## Base class for procedural heightmap generators.
## Subclass this and override generate() to produce different terrain shapes.
##
## `dimensions` (x = width, y = depth) is the output grid size. HeightmapGeneratorTool
## sizes the target HeightMapShape3D to match before/after calling generate().

#region Properties
@export var dimensions: Vector2i = Vector2i(120, 120)

## Axis accessors for `dimensions`, used throughout the generator implementations.
var width: int:
	get: return dimensions.x
	set(value): dimensions.x = value
var depth: int:
	get: return dimensions.y
	set(value): dimensions.y = value
#endregion

#region Public API
## Return a PackedFloat32Array of size width*depth with corner heights in
## HeightMapShape3D local space.  Index: z * width + x.
func generate() -> PackedFloat32Array:
	push_error("HeightmapGenerator.generate() not implemented in %s" % get_script().resource_path)
	return PackedFloat32Array()
#endregion
