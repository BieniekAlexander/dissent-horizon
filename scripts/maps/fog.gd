class_name Fog
extends MeshInstance3D

## Three-state terrain visibility as seen by the player.
##   UNSEEN    — tile has never been in a player unit's vision radius.
##   EXPLORED  — tile was seen at some point but is currently fogged.
##   IN_SIGHT  — tile is inside a player unit's vision radius this frame.
enum TerrainVisibility { UNSEEN, EXPLORED, IN_SIGHT }

#region Properties
var POINTS_PER_UNIT: float = 1.0  # overwritten in _initialize() = 1.0 / Map.CELL_SIZE
# L8 byte value for "explored but not currently visible" (alpha ≈ 0.5)
const EXPLORED_ALPHA: int = 127

var _img_width: int
var _img_height: int
var _center: Vector2
var _world_half_w: float  # actual world half-extent in X
var _world_half_d: float  # actual world half-extent in Z
var _explored_bytes: PackedByteArray  # 255 = never seen, EXPLORED_ALPHA = seen before
var _fog_bytes: PackedByteArray       # display buffer, rebuilt each frame from _explored_bytes
var _fog_image: Image
var _fog_texture: ImageTexture
var _sight_disc_cache: Dictionary  # int radius_px -> Array[Vector2i]
#endregion

#region Lifecycle
func _ready() -> void:
	call_deferred(&"_initialize")
	get_active_material(0).render_priority = RenderPriority.FOG_PRIORITY

func _initialize() -> void:
	var map: Map = get_tree().current_scene.find_child("Map")
	var hs: HeightMapShape3D = map.height_map

	# HeightMapShape3D with map_width W covers local X -(W-1)/2 .. +(W-1)/2.
	# World half-extents are (W-1)/2 * Map.CELL_SIZE.
	POINTS_PER_UNIT = 1.0 / Map.CELL_SIZE

	var half_w := (hs.map_width - 1) * 0.5 * Map.CELL_SIZE
	var half_d := (hs.map_depth - 1) * 0.5 * Map.CELL_SIZE
	var margin := Map.CELL_SIZE

	# Desired world half-extents for the fog plane.
	_world_half_w = half_w + margin
	_world_half_d = half_d + margin

	# PlaneMesh local vertices span ±(size/2) in XZ; node scale multiplies that.
	# We want world half-extent = _world_half_w, so node_scale = _world_half_w / mesh_half.
	var plane_mesh := mesh as PlaneMesh
	scale.x = _world_half_w / (plane_mesh.size.x * 0.5)
	scale.z = _world_half_d / (plane_mesh.size.y * 0.5)

	global_position = Vector3(map.global_position.x, 1.0, map.global_position.z)
	_center = VU.inXZ(global_position)

	_img_width = int(_world_half_w * 2.0 * POINTS_PER_UNIT)
	_img_height = int(_world_half_d * 2.0 * POINTS_PER_UNIT)

	_explored_bytes = PackedByteArray()
	_explored_bytes.resize(_img_width * _img_height)
	_explored_bytes.fill(255)

	_fog_image = Image.create_from_data(_img_width, _img_height, false, Image.FORMAT_L8, _explored_bytes)
	_fog_texture = ImageTexture.create_from_image(_fog_image)
	get_active_material(0).set_shader_parameter("fog_texture", _fog_texture)

func _physics_process(_delta: float) -> void:
	if _fog_texture == null:
		return
	# The debug view (hold Space) only hides the fog MESH so the whole map shows;
	# the fog STATE keeps updating underneath so reveals/explored data stay current
	# (and enemy sight logic keeps running) while the button is held.
	var debug_view: bool = Input.is_action_pressed("debug_info")
	visible = not debug_view

	_fog_bytes = _explored_bytes.duplicate()
	for entity: Entity in get_tree().get_nodes_in_group("commandable"):
		if entity.commander_id != RTSController.PLAYER_COMMANDER_ID:
			continue
		if entity.vision_range_shape == null:
			continue
		var pixel := _world_to_pixel(VU.inXZ(entity.global_position))
		var vision_shape := entity.vision_range_shape
		var world_radius := (vision_shape.shape as CylinderShape3D).radius \
			* vision_shape.global_transform.basis.x.length()
		var radius_px := int(world_radius * POINTS_PER_UNIT)
		for offset: Vector2i in _sight_disc(radius_px):
			var px := pixel.x + offset.x
			var py := pixel.y + offset.y
			if px >= 0 and px < _img_width and py >= 0 and py < _img_height:
				var idx := py * _img_width + px
				_fog_bytes[idx] = 0
				_explored_bytes[idx] = EXPLORED_ALPHA

	_fog_image = Image.create_from_data(_img_width, _img_height, false, Image.FORMAT_L8, _fog_bytes)
	_fog_texture.update(_fog_image)

	for entity: Entity in get_tree().get_nodes_in_group("commandable"):
		if entity.commander_id == RTSController.PLAYER_COMMANDER_ID:
			continue
		var pixel: Vector2i = _world_to_pixel(VU.inXZ(entity.global_position))
		var in_bounds: bool = pixel.x >= 0 and pixel.x < _img_width and pixel.y >= 0 and pixel.y < _img_height
		var fog_clear: bool = in_bounds and _fog_bytes[pixel.y * _img_width + pixel.x] == 0
		# While debug-viewing, reveal every entity too; otherwise enemies show only
		# where the fog is clear. in_sight_range below stays pure game logic.
		entity.visible = debug_view or fog_clear
		# in_sight_range: true only when the fog pixel is clear AND the entity is
		# not actively stealthed. A stealthed enemy in a revealed fog cell is
		# technically "visible" (the pixel is clear) but is perceptually hidden —
		# its sprite alpha is 0 and it should not appear on the minimap or trigger
		# any sight-based game logic. REVEALED and UNSTEALTHED count as perceptible.
		if entity is Commandable:
			var stealthed: bool = entity.stealth != null \
				and entity.stealth.state == Stealth.State.STEALTHED
			(entity as Commandable).in_sight_range = fog_clear and not stealthed
#endregion

#region Public API
## Returns the three-state terrain visibility for the fog pixel covering
## `world_xz`. Used by the minimap to colour terrain appropriately.
func terrain_visibility_at(world_xz: Vector2) -> TerrainVisibility:
	if _explored_bytes.is_empty() or _fog_bytes.is_empty():
		return TerrainVisibility.UNSEEN
	var pixel: Vector2i = _world_to_pixel(world_xz)
	if pixel.x < 0 or pixel.x >= _img_width or pixel.y < 0 or pixel.y >= _img_height:
		return TerrainVisibility.UNSEEN
	var idx: int = pixel.y * _img_width + pixel.x
	if _explored_bytes[idx] == 255:
		return TerrainVisibility.UNSEEN
	if _fog_bytes[idx] == 0:
		return TerrainVisibility.IN_SIGHT
	return TerrainVisibility.EXPLORED

## Permanently reveal a circular area in world-space XZ (lift fog of war).
## The pixels are written to _explored_bytes so the reveal persists across frames.
## Safe to call before _initialize() completes — exits silently if not yet ready.
func reveal_region(world_xz: Vector2, radius_world: float) -> void:
	if _explored_bytes.is_empty():
		return
	var pixel := _world_to_pixel(world_xz)
	var radius_px := maxi(1, int(radius_world * POINTS_PER_UNIT))
	for offset: Vector2i in _sight_disc(radius_px):
		var px := pixel.x + offset.x
		var py := pixel.y + offset.y
		if px >= 0 and px < _img_width and py >= 0 and py < _img_height:
			_explored_bytes[py * _img_width + px] = EXPLORED_ALPHA
#endregion

#region Private helpers
func _world_to_pixel(world_xz: Vector2) -> Vector2i:
	return Vector2i(
		int(round((world_xz.x - _center.x + _world_half_w) * POINTS_PER_UNIT)),
		int(round((world_xz.y - _center.y + _world_half_d) * POINTS_PER_UNIT))
	)

func _sight_disc(radius_px: int) -> Array:
	if _sight_disc_cache.has(radius_px):
		return _sight_disc_cache[radius_px]
	var disc: Array[Vector2i] = []
	var r2 := radius_px * radius_px
	for dx in range(-radius_px, radius_px + 1):
		for dy in range(-radius_px, radius_px + 1):
			if dx * dx + dy * dy <= r2:
				disc.append(Vector2i(dx, dy))
	_sight_disc_cache[radius_px] = disc
	return disc
#endregion
