extends MeshInstance3D


### SHADER
## The set of values representing whether an area of the fog mesh should be drawn
## The number of shader points representing the width of 1 distance unit of space
const points_per_unit: float = 2
var center: Vector2
var fog_texture: PortableCompressedTexture2D
var fog_image: Image

var vision_range_index_map: Dictionary

func world_to_image(world_position: Vector2) -> Vector2i:
	return Vector2i(
		round((world_position.x-center.x+scale.x/2)*points_per_unit),
		round((world_position.y-center.y+scale.z/2)*points_per_unit)
	)

# TODO: unused function
#func image_to_world(image_coordinate: Vector2i) -> Vector2:
#	return Vector2(
#		image_coordinate.x/points_per_unit-scale.x/2 + center.x,
#		image_coordinate.y/points_per_unit-scale.z/2 + center.y
#	)


### NODE
func _physics_process(_delta: float) -> void:
	# https://forum.godotengine.org/t/how-to-create-texture-from-fog_image-in-editorscript/52267/2 
	#visible = not Input.is_action_pressed("debug_hide_fog")
	visible = false
	#
	#for x in range(fog_image.get_width()):
		#for y in range(fog_image.get_height()):
			#if fog_image.get_pixelv(Vector2i(x, y))!=Color.WHITE:
				#fog_image.set_pixelv(Vector2i(x, y), Color.GRAY)
	#
	#for entity: Entity in get_tree().get_nodes_in_group("entity"):
		#if entity.commander_id!=1 and entity is not Star: continue # TODO hardcoding for now - find some method of identifying the ID of the player
		#var entity_location: Vector2i = world_to_image(VU.inXZ(entity.global_position))
		#
		#for index in vision_range_index_map[int(entity.sight_range*points_per_unit)]:
			#var offset: Vector2i = entity_location+index
			#if offset.x>0 and offset.x<fog_image.get_width() and offset.y>0 and offset.y<fog_image.get_height():
				#fog_image.set_pixelv(offset, Color.BLACK)
	#
	#fog_texture = PortableCompressedTexture2D.new()
	#fog_texture.create_from_image(fog_image, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
	
	# hide units that aren't covered by fog
	#for entity: Entity in get_tree().get_nodes_in_group("entity"):
	#	if entity is Unit:
	#		if fog_image.get_pixelv(world_to_image(VU.inXZ(entity.global_position)))!=Color.BLACK:
	#			entity.visible = false
	#		else:
	#			entity.visible = true

func _process(_delta: float) -> void:
	get_active_material(0).set_shader_parameter("fog_texture", fog_texture)

func _ready() -> void:
	# set size
	var map: Map = get_tree().current_scene.find_child("Map")
	# TODO hacking the scale to cover map with fog - seems wrong with the added constants,
	# but I'm not sure why the fog reveal seems to wrap around the bottom of the map
	var min_max = map.get_min_max()
	var width: int = min_max[1].x-min_max[0].x
	var length: int = min_max[1].y-min_max[0].y
	scale.x = float((width + 5) * map.cell_size)
	scale.z = float((length + 5) * map.cell_size)
	# set position
	global_position = Vector3(scale.x, 0, scale.z)/2
	center = VU.inXZ(global_position)
	# setup shader
	get_active_material(0).set_shader_parameter("mesh_scale", scale)
	get_active_material(0).set_shader_parameter("points_per_unit", points_per_unit)
	# set up fog image
	fog_image = Image.create(
		scale.x*points_per_unit,
		scale.z*points_per_unit,
		false,
		Image.FORMAT_L8
	)
	
	fog_image.fill(Color.WHITE)
	# precalculate fog range index offsets
	vision_range_index_map = {}
	for r in range(1, 50):
		var arr: Array = []
		for x in range(-r,r+1):
			for y in range(-r,r+1):
				arr.append(Vector2i(x, y))
		
		vision_range_index_map[r] = arr.filter(
			func(index: Vector2i): return index.length_squared()<r**2
		)
