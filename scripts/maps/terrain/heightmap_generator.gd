@tool
class_name HeightmapGenerator
extends Resource

## Base class for procedural heightmap generators.
## Subclass this and override generate() to produce different terrain shapes.
##
## width and depth must match the target HeightMapShape3D's map_width / map_depth.
## HeightmapGeneratorTool syncs these automatically before calling generate().

@export var width: int = 120
@export var depth: int = 120

## Return a PackedFloat32Array of size width*depth with corner heights in
## HeightMapShape3D local space.  Index: z * width + x.
func generate() -> PackedFloat32Array:
	push_error("HeightmapGenerator.generate() not implemented in %s" % get_script().resource_path)
	return PackedFloat32Array()
