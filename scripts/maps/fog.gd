class_name Fog
extends MeshInstance3D

## Terrain visibility as seen by a single commander, kept INCREMENTALLY: a per-pixel count of
## the vision sources covering each pixel, and for each source the stamp it last added. A tick
## re-stamps only the sources whose stamp changed, and the texture is uploaded only for the
## fog being displayed, only when its bytes changed. So a tick in which nothing crossed a pixel
## does no fog work at all. See gdd/systems/combat/scan-and-vision-cost.md §The fog of war.

## Three-state terrain visibility as seen by a single commander.
##   UNSEEN    — tile has never been in any owned unit's vision radius.
##   EXPLORED  — tile was seen at some point but is currently fogged.
##   IN_SIGHT  — tile is inside an owned unit's vision radius this frame.
enum TerrainVisibility { UNSEEN, EXPLORED, IN_SIGHT }

#region Properties
var POINTS_PER_UNIT: float = 1.0  # overwritten in _initialize() = 1.0 / Map.CELL_SIZE
# L8 byte value for "explored but not currently visible" (alpha ≈ 0.5)
const EXPLORED_ALPHA: int = 127
## An explored-buffer pixel no vision has ever touched.
const UNEXPLORED_BYTE: int = 255

## The commander whose units are used to reveal this fog texture.
## -1 (default) falls back to RTSController.PLAYER_COMMANDER_ID so the node
## placed in player.tscn needs no configuration.
var watching_commander_id: int = -1

## Which commander's fog currently drives entity visibility and renders its mesh.
## -1  (default)  → use RTSController.PLAYER_COMMANDER_ID (normal gameplay).
## -2             → omniscient: all entities visible, no fog plane rendered.
## ≥ 1            → that specific commander's Fog is active (spectator mode).
## Changed by the spectator HUD toggle buttons.
static var active_commander_id: int = -1

## Registry: commander_id → Fog node, for look-up by the minimap and spectator HUD.
## Keyed by the RESOLVED viewer id (see viewer_commander_id), so there is exactly one key
## per commander and `-1` never reaches it. It used to be keyed by the raw
## `watching_commander_id`, which filed the player's own fog under the authoring default
## `-1`: every caller then had to remember to re-map the player's id back to it, and the
## one that forgot — Entity.is_visible_to — silently reported EVERY enemy visible to
## the player, which is what left player aggro ungated by fog.
static var _fogs_by_commander: Dictionary = {}

var _img_width: int
var _img_height: int
var _center: Vector2
var _world_half_w: float  # actual world half-extent in X
var _world_half_d: float  # actual world half-extent in Z
var _explored_bytes: PackedByteArray  # UNEXPLORED_BYTE = never seen, EXPLORED_ALPHA = seen before
## Display buffer: 0 where a pixel is in sight now, its _explored_bytes value elsewhere. Kept
## in step with _sight_counts by _apply_stamp rather than rebuilt.
var _fog_bytes: PackedByteArray
## How many of this commander's vision sources cover each pixel; in sight while above zero.
## Counts rather than flags so a source that moves can be subtracted without re-stamping the rest.
var _sight_counts: PackedInt32Array
## Vision source instance id -> the SightStamp it last added to _sight_counts.
var _stamps: Dictionary = {}
## True when _fog_bytes has changed since the texture was last uploaded.
var _is_texture_stale: bool = true
## Structure instance id -> [the footprint cells array it was built from, the in-play pixel
## indices those cells cover]. Memoized: resolving cells to pixels every tick for every
## structure was most of the fog's cost once sight became incremental, and it cannot change
## while the cells array does not (Map replaces an entry, never edits it).
var _footprint_pixels: Dictionary = {}
## Per-pixel play-bounds mask (1 = in the screen-aligned playspace, 0 = out). Out-of-play
## pixels are held fully transparent (never shrouded/explored) so the fog stops at the play
## area instead of hanging black over the chopped-off corners. Empty/ignored when the map has
## no play bounds (see _play_bounds_active).
var _play_mask: PackedByteArray
var _play_bounds_active: bool = false
var _fog_image: Image
var _fog_texture: ImageTexture
var _sight_disc_cache: Dictionary  # int radius_px -> Array[Vector2i]
var _footprint_cache: Dictionary  # footprint signature "kind:hx:hz" -> Array[Vector2i]
var _map: Map  # cached in _initialize; used to look up structure footprint cells
## Every world-geometry ShaderMaterial the shroud has to be pushed into — the terrain, plus
## one per water surface (see Map.fogged_materials). The elected driver writes the active
## commander's fog texture into all of them each frame, so the shroud is drawn on the terrain
## (height-conformal) rather than by this node's flat plane, which is left hidden.
##
## A LIST rather than the one terrain material, because a surface left out of it is silently
## unfogged: you see the shroud stop at the shoreline and the lake stay bright. Empty on maps
## with no such mesh.
var _fogged_materials: Array[ShaderMaterial] = []
#endregion


#region Lifecycle
func _ready() -> void:
	call_deferred(&"_initialize")
	Fog._fogs_by_commander[viewer_commander_id()] = self


## The commander this fog answers for, with the `-1` authoring default resolved. The single
## place that resolution happens — everything else (the registry key, the reveal loop, the
## entity-visibility pass) reads it from here.
func viewer_commander_id() -> int:
	return (
		watching_commander_id if watching_commander_id >= 0 else RTSController.PLAYER_COMMANDER_ID
	)


## The live Fog tracking `a_commander_id`'s vision, or null when that commander has none
## (the neutral owner, a test rig, the editor).
##
## The registry is static and entries outlive the nodes that made them — a freed Fog never
## deregisters — so a stale key would otherwise hand back a dead instance.
## The local is UNTYPED on purpose: assigning a freed instance to a `Fog`-typed variable is
## itself an error in Godot, so the validity test has to come after an untyped read (see
## CLAUDE.md §A freed object cannot be passed to a typed parameter — assignment is the same
## check).
static func for_commander(commander_id: int) -> Fog:
	var fog: Variant = Fog._fogs_by_commander.get(commander_id)
	return fog if is_instance_valid(fog) else null


func _initialize() -> void:
	var map: Map = _resolve_map()
	# No Map (e.g. running player.tscn standalone to preview the HUD): leave
	# _fog_texture null so _physics_process no-ops and the fog stays inert.
	if map == null:
		return
	_map = map
	var hs: HeightMapShape3D = map.height_map

	# HeightMapShape3D with map_width W covers local X -(W-1)/2 .. +(W-1)/2.
	# World half-extents are (W-1)/2 * Map.CELL_SIZE.
	POINTS_PER_UNIT = 1.0 / Map.CELL_SIZE

	var half_w := (hs.map_width - 1) * 0.5 * Map.CELL_SIZE
	var half_d := (hs.map_depth - 1) * 0.5 * Map.CELL_SIZE
	var margin := Map.CELL_SIZE

	# World half-extents the fog texture covers (terrain plus a one-cell margin).
	_world_half_w = half_w + margin
	_world_half_d = half_d + margin

	# The fog texture is centred on the map; no plane to size any more (drawn by the terrain
	# shader). _center feeds _world_to_pixel and the terrain shader's fog_rect.
	_center = VU.in_xz(map.global_position)

	_img_width = int(_world_half_w * 2.0 * POINTS_PER_UNIT)
	_img_height = int(_world_half_d * 2.0 * POINTS_PER_UNIT)

	_allocate_buffers()
	_build_play_mask()  # holds out-of-play pixels transparent (zeroes them in both byte buffers)

	_fog_image = Image.create_from_data(
		_img_width, _img_height, false, Image.FORMAT_L8, _explored_bytes
	)
	_fog_texture = ImageTexture.create_from_image(_fog_image)

	# Fog is now drawn by the terrain shader (height-conformal), not this flat plane: hide the
	# plane and resolve the terrain material the player's fog will feed each frame.
	visible = false
	# Whichever nodes draw this map's world surfaces — see Map.fogged_materials.
	_fogged_materials = map.fogged_materials()


## The Map this fog answers for, found by walking UP from this node — the same
## resolution Commander._resolve_refs uses, and for the same reason.
##
## It used to start from `get_tree().current_scene`, which is only the Scenario when the
## Scenario IS the opened scene. Host it under anything else — the self-play harness
## instantiates it as a child of a runner node, and a GUT simulation test does the same —
## and the lookup missed, every Fog stayed inert, and `fog_clear_at` then answered FALSE for
## every point on the map. That is a silent, total blinding rather than a visible failure:
## `Entity.is_visible_to` returns false, so aggro, BotTargeting and the blackboard all
## see an empty world and no bot ever fights. Walking up cannot miss that way — a Fog is
## always a descendant of the Scenario that owns the Map it belongs to.
##
## Returns null for a genuinely map-less rig (player.tscn opened on its own, a GUT test
## adding a bare Fog to the tree), which stays as quiet as it always was.
func _resolve_map() -> Map:
	if not is_inside_tree():
		return null
	var node: Node = self
	while node != null:
		# owned = false: the Scenario's Map is owned by the Scenario's own scene, not by
		# whatever node is hosting it, so an ownership-filtered search is exactly the check
		# that failed here.
		var found := node.find_child("Map", true, false) as Map
		if found != null:
			return found
		node = node.get_parent()
	return null


func _physics_process(_a_delta: float) -> void:
	if _fog_texture == null:
		return

	var active_id: int = Fog.active_commander_id
	var viewer_id: int = viewer_commander_id()
	var is_active: bool = (
		(active_id == -1 and viewer_id == RTSController.PLAYER_COMMANDER_ID)
		or viewer_id == active_id
	)

	# ── Update this commander's sight from its vision sources ──
	# Runs for every commander's Fog so their data stays current even off-screen. The "los"
	# group holds every Entity that has a VisionRange shape (see Entity._ready), so anything
	# with sight reveals fog regardless of whether it accepts commands.
	_update_sight(get_tree().get_nodes_in_group("los"))
	# Only the displayed fog's texture is read (by the terrain shader, via the elected
	# driver); every gameplay reader uses the bytes. A fog that becomes displayed while stale
	# uploads on its first tick.
	if _is_texture_stale and Fog.get_active_fog() == self:
		_fog_image.set_data(_img_width, _img_height, false, Image.FORMAT_L8, _fog_bytes)
		_fog_texture.update(_fog_image)
		_is_texture_stale = false

	# ── Drive the terrain-shader fog ──
	# Fog is sampled per-fragment in the terrain shader (conforms to terrain height) instead of
	# being a flat plane. Exactly one node — the ELECTED DRIVER, see terrain_fog_driver_id —
	# pushes the ACTIVE commander's fog texture into the terrain material each frame;
	# a fog-lifting debug view / omniscient disable it.
	var debug_view: bool = DebugMode.lifts_fog()
	if viewer_id == Fog.terrain_fog_driver_id():
		_drive_terrain_fog(debug_view)

	# ── Entity visibility: only one system touches this per frame ──
	if active_id == -2:
		# Omniscient spectator: every Fog instance runs this — idempotent and cheap.
		for entity: Entity in get_tree().get_nodes_in_group("piece"):
			entity.visible = true
			if entity is Actor:
				var stealthed: bool = (
					entity.stealth != null and entity.stealth.state == Stealth.State.STEALTHED
				)
				(entity as Actor).in_sight_range = not stealthed
		_apply_figure_visibility(viewer_id, true)
	elif is_active:
		_apply_figure_visibility(viewer_id, debug_view)
		for entity: Entity in get_tree().get_nodes_in_group("piece"):
			if entity.is_on_side_of(viewer_id):
				# Own and allied units are always visible to their side. Set this explicitly
				# rather than skipping: when the active view switches directly from
				# another commander (spectator POV), that commander's fog had hidden
				# these as enemies, and nothing else would clear that stale state
				# (switching via "no fog" works only because it forces everything
				# visible). Garrisoned occupants are out of the tree, so untouched.
				#
				# The one exception is a planted charge, which its owner sees only inside their
				# own vision — it carries none of its own.
				entity.visible = (
					debug_view
					or PlantedCharge.of(entity) == null
					or fog_clear_at(VU.in_xz(entity.global_position))
				)
				# An ally's piece is perceived like an enemy's in sight, except that its
				# stealth hides nothing from this side (Entity.is_visible_to).
				if entity is Actor and entity.commander_id != viewer_id:
					(entity as Actor).in_sight_range = entity.visible
				continue
			# A structure that is merely PLANNED (a blueprint an enemy commander has ordered
			# but not built) isn't on the map at all — it occupies no cells and can't be shot
			# at, so it is never shown to anyone but its owner, whatever the fog says.
			if entity.is_planned:
				entity.visible = false
				if entity is Actor:
					(entity as Actor).in_sight_range = false
				continue
			# A structure occupies a footprint of grid cells, so it's in sight when
			# ANY occupied cell is revealed — not only the cell under its origin.
			# Units (and structures with no registered footprint) use their point.
			var fog_clear: bool
			if entity.structure_is_active():
				fog_clear = structure_in_vision(entity)
			else:
				fog_clear = fog_clear_at(VU.in_xz(entity.global_position))
			entity.visible = debug_view or fog_clear
			if entity is Actor:
				var stealthed: bool = (
					entity.stealth != null and entity.stealth.state == Stealth.State.STEALTHED
				)
				(entity as Actor).in_sight_range = fog_clear and not stealthed


#endregion


#region Public API
## The test a drawing owned by `a_owner_id` must pass, point by point, to be seen by whoever is
## watching: the displayed fog's `fog_clear_at`, or an invalid Callable when everything of
## theirs is shown — it is the viewer's own, or the view is omniscient or a fog-lifting debug
## view.
static func active_sight_test(a_owner_id: int) -> Callable:
	if DebugMode.lifts_fog():
		return Callable()
	var active_fog: Variant = Fog.get_active_fog()
	if not (active_fog is Fog) or (active_fog as Fog).viewer_commander_id() == a_owner_id:
		return Callable()
	return (active_fog as Fog).fog_clear_at


## The Fog node currently driving entity visibility and the rendered plane.
## Returns null in omniscient mode (active_commander_id == -2).
static func get_active_fog() -> Variant:
	var active_id: int = Fog.active_commander_id
	if active_id == -2:
		return null
	if active_id == -1:
		return Fog.for_commander(RTSController.PLAYER_COMMANDER_ID)
	return Fog.for_commander(active_id)


## Which commander's Fog pushes the shroud into the shared terrain material: the LOWEST-numbered
## one with a live Fog, or -1 when none is registered (scan-and-vision-cost.md §One Fog drives
## the terrain shroud, by election).
static func terrain_fog_driver_id() -> int:
	var best: int = -1
	for id: int in Fog._fogs_by_commander:
		if not is_instance_valid(Fog._fogs_by_commander[id]):
			continue  # a freed Fog never deregisters; a stale key must not win the election
		if best < 0 or id < best:
			best = id
	return best


## Returns the three-state terrain visibility for the fog pixel covering
## `world_xz`. Used by the minimap to colour terrain appropriately.
func terrain_visibility_at(a_world_xz: Vector2) -> TerrainVisibility:
	if _explored_bytes.is_empty() or _fog_bytes.is_empty():
		return TerrainVisibility.UNSEEN
	var pixel: Vector2i = _world_to_pixel(a_world_xz)
	if pixel.x < 0 or pixel.x >= _img_width or pixel.y < 0 or pixel.y >= _img_height:
		return TerrainVisibility.UNSEEN
	var idx: int = pixel.y * _img_width + pixel.x
	if _play_bounds_active and _play_mask[idx] == 0:
		return TerrainVisibility.UNSEEN  # out of play: not real terrain
	if _explored_bytes[idx] == UNEXPLORED_BYTE:
		return TerrainVisibility.UNSEEN
	if _fog_bytes[idx] == 0:
		return TerrainVisibility.IN_SIGHT
	return TerrainVisibility.EXPLORED


## Whether [a_world_xz] is currently within this commander's live vision (fog pixel clear).
## Unlike terrain_visibility_at this works for any registered commander's Fog, not only the
## spectated one — `_fog_bytes` is kept current for every one each physics tick.
##
## OUT OF PLAY IS NOT IN VISION: the mask is tested BEFORE the byte, because byte 0 means
## both "revealed" and "outside the play rectangle" and conflating them left anything sited
## past the play edge permanently in sight. Why:
## gdd/systems/combat/target-acquisition.md §Out of play is not in vision.
func fog_clear_at(a_world_xz: Vector2) -> bool:
	if _fog_bytes.is_empty():
		return false
	var pixel: Vector2i = _world_to_pixel(a_world_xz)
	if pixel.x < 0 or pixel.x >= _img_width or pixel.y < 0 or pixel.y >= _img_height:
		return false
	var idx: int = pixel.y * _img_width + pixel.x
	if _play_bounds_active and _play_mask[idx] == 0:
		return false
	return _fog_bytes[idx] == 0


## Whether [a_world_xz] has EVER been in this commander's vision — in sight now, or explored.
## Works for any registered commander's Fog, since every one keeps its bytes current. Out of
## play is never explored (`_apply_stamp` leaves those pixels alone).
func explored_at(a_world_xz: Vector2) -> bool:
	if _explored_bytes.is_empty():
		return false
	var pixel: Vector2i = _world_to_pixel(a_world_xz)
	if pixel.x < 0 or pixel.x >= _img_width or pixel.y < 0 or pixel.y >= _img_height:
		return false
	return _explored_bytes[pixel.y * _img_width + pixel.x] != UNEXPLORED_BYTE


## True when ANY grid cell [structure] occupies is currently in this fog's vision.
## Structures are discretised into a footprint of terrain cells, so a multi-cell
## building counts as seen the instant any of its cells is scouted — not only when
## the cell under its origin is. Falls back to the origin point when the structure
## has no registered footprint (or the Map is unavailable).
func structure_in_vision(a_structure: Node) -> bool:
	var origin_xz: Vector2 = VU.in_xz((a_structure as Node3D).global_position)
	if _map == null or _fog_bytes.is_empty():
		return fog_clear_at(origin_xz)
	var cells: Variant = _map.structure_cell_map.get(a_structure)
	if cells == null or (cells as Array).is_empty():
		return fog_clear_at(origin_xz)
	for idx: int in _structure_pixels(a_structure, cells):
		if _fog_bytes[idx] == 0:
			return true
	return false


## Permanently reveal a circular area in world-space XZ (lift fog of war).
## The pixels are written to _explored_bytes so the reveal persists across frames.
## Safe to call before _initialize() completes — exits silently if not yet ready.
func reveal_region(a_world_xz: Vector2, a_radius_world: float) -> void:
	if _explored_bytes.is_empty():
		return
	var pixel := _world_to_pixel(a_world_xz)
	var radius_px := maxi(1, int(a_radius_world * POINTS_PER_UNIT))
	for offset: Vector2i in _sight_disc(radius_px):
		var px := pixel.x + offset.x
		var py := pixel.y + offset.y
		if px >= 0 and px < _img_width and py >= 0 and py < _img_height:
			var idx := py * _img_width + px
			if _play_bounds_active and _play_mask[idx] == 0:
				continue  # out of play: stays transparent
			_explored_bytes[idx] = EXPLORED_ALPHA
			if _sight_counts[idx] == 0:
				_fog_bytes[idx] = EXPLORED_ALPHA
				_is_texture_stale = true


#endregion


#region Sight counts
## What one vision source last added to the sight counts, kept so it can be withdrawn exactly.
class SightStamp:
	var pixel: Vector2i
	## The shared cached footprint from _vision_offsets: compared by identity, since equal
	## footprints are one cached array.
	var offsets: Array

	func _init(a_pixel: Vector2i, a_offsets: Array) -> void:
		pixel = a_pixel
		offsets = a_offsets


## Size every per-pixel buffer for the current image dimensions: nothing explored, nothing in
## sight.
func _allocate_buffers() -> void:
	var pixel_count: int = _img_width * _img_height
	_explored_bytes = PackedByteArray()
	_explored_bytes.resize(pixel_count)
	_explored_bytes.fill(UNEXPLORED_BYTE)
	_fog_bytes = _explored_bytes.duplicate()
	_sight_counts = PackedInt32Array()
	_sight_counts.resize(pixel_count)
	_stamps.clear()
	_is_texture_stale = true


## Bring the sight counts up to date with `a_sources` (the "los" group): re-stamp only a source
## whose pixel or footprint changed, and withdraw the stamp of any source that no longer
## counts. Diffing each tick, rather than hooking each event that changes vision (capture,
## death, garrisoning, an upgrade, construction), is what keeps it correct for the event
## nobody remembered.
func _update_sight(a_sources: Array) -> void:
	var viewer_id: int = viewer_commander_id()
	var live: Dictionary = {}
	for entity: Entity in a_sources:
		# Allies' sight counts as this commander's own: vision is shared within an alliance.
		if not entity.is_on_side_of(viewer_id) or not entity.grants_vision():
			continue
		var key: int = entity.get_instance_id()
		live[key] = true
		# Centre on the shape (it may be offset from the entity origin), and cover the shape's
		# XZ cross-section — any shape type, not just a circle.
		var vision_shape: CollisionShape3D = entity.vision_range_shape
		var pixel: Vector2i = _world_to_pixel(VU.in_xz(vision_shape.global_position))
		var offsets: Array = _vision_offsets(vision_shape)
		var old: SightStamp = _stamps.get(key)
		if old != null and old.pixel == pixel and is_same(old.offsets, offsets):
			continue
		if old != null:
			_apply_stamp(old, -1)
		var stamp := SightStamp.new(pixel, offsets)
		_apply_stamp(stamp, 1)
		_stamps[key] = stamp
	for key: int in _stamps.keys():
		if not live.has(key):
			_apply_stamp(_stamps[key], -1)
			_stamps.erase(key)


## Add (`a_delta` 1) or withdraw (-1) one stamp from the sight counts, touching the display
## bytes only where a pixel enters or leaves sight. Hot loop: every re-stamp walks a whole
## footprint, twice for a move.
func _apply_stamp(a_stamp: SightStamp, a_delta: int) -> void:
	for offset: Vector2i in a_stamp.offsets:
		var px: int = a_stamp.pixel.x + offset.x
		var py: int = a_stamp.pixel.y + offset.y
		if px < 0 or px >= _img_width or py < 0 or py >= _img_height:
			continue
		var idx: int = py * _img_width + px
		if _play_bounds_active and _play_mask[idx] == 0:
			continue  # out of play: keep it transparent, don't shroud/explore it
		var count: int = _sight_counts[idx] + a_delta
		_sight_counts[idx] = count
		if count == 1 and a_delta > 0:
			_fog_bytes[idx] = 0
			_explored_bytes[idx] = EXPLORED_ALPHA
			_is_texture_stale = true
		elif count == 0:
			_fog_bytes[idx] = _explored_bytes[idx]
			_is_texture_stale = true


#endregion


#region Private helpers
## Hide the figures the piece pass does not reach — beacons and emissions — under the viewer's
## fog, exactly as an enemy piece is hidden: by the pixel under it, never for their owner. A
## beacon's stealth is drawn separately, on its MeshVisual (Beacon._process), so the two rules
## compose: an opponent sees it only when it is out of fog AND not stealthed. A beam is clipped
## by its Tracer, which draws outside this visibility (Tracer._segments).
func _apply_figure_visibility(a_viewer_id: int, a_show_all: bool) -> void:
	for group: StringName in [Beacon.GROUP, PhasedLocomotion.EMISSION_GROUP]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var figure: Node3D = node as Node3D
			if figure == null:
				continue
			var entity: Entity = figure as Entity
			var owner_id: int = (
				entity.commander_id if entity != null and entity.ownership != null else 0
			)
			figure.visible = (
				a_show_all
				or owner_id == a_viewer_id
				or (entity != null and owner_id > 0 and entity.is_on_side_of(a_viewer_id))
				or fog_clear_at(VU.in_xz(figure.global_position))
			)


## The in-play pixel indices covering `a_cells`, the footprint `a_structure` holds now.
func _structure_pixels(a_structure: Node, a_cells: Array) -> PackedInt32Array:
	var key: int = a_structure.get_instance_id()
	var cached: Variant = _footprint_pixels.get(key)
	if cached != null and is_same(cached[0], a_cells):
		return cached[1]
	var pixels := PackedInt32Array()
	for cell: Vector2i in a_cells:
		var pixel: Vector2i = _world_to_pixel(VU.in_xz(_map.grid_to_world(cell)))
		if pixel.x < 0 or pixel.x >= _img_width or pixel.y < 0 or pixel.y >= _img_height:
			continue
		var idx: int = pixel.y * _img_width + pixel.x
		if _play_bounds_active and _play_mask[idx] == 0:
			continue  # out of play is not in vision (see fog_clear_at)
		pixels.append(idx)
	_footprint_pixels[key] = [a_cells, pixels]
	return pixels


## Feed the terrain material the ACTIVE commander's fog so the shroud renders on the ground.
## Called only by the elected driver (terrain_fog_driver_id). Disabled (full-bright terrain)
## during debug-view or omniscient spectator, or when there is no active fog.
func _drive_terrain_fog(a_debug_view: bool) -> void:
	if _fogged_materials.is_empty():
		return
	var active_id: int = Fog.active_commander_id
	var active_fog: Variant = Fog.get_active_fog()
	if a_debug_view or active_id == -2 or not (active_fog is Fog):
		for material: ShaderMaterial in _fogged_materials:
			material.set_shader_parameter("fog_enabled", 0.0)
		return
	var af: Fog = active_fog
	for material: ShaderMaterial in _fogged_materials:
		material.set_shader_parameter("fog_texture", af._fog_texture)
		material.set_shader_parameter("fog_rect", af._fog_rect_param())
		material.set_shader_parameter("fog_enabled", 1.0)


## World-XZ → fog-UV mapping for the terrain shader: (center.x, center.z, half_w, half_d).
func _fog_rect_param() -> Vector4:
	return Vector4(_center.x, _center.y, _world_half_w, _world_half_d)


func _world_to_pixel(a_world_xz: Vector2) -> Vector2i:
	return Vector2i(
		int(round((a_world_xz.x - _center.x + _world_half_w) * POINTS_PER_UNIT)),
		int(round((a_world_xz.y - _center.y + _world_half_d) * POINTS_PER_UNIT))
	)


## World XZ at the centre of fog pixel (px, py) — the inverse of _world_to_pixel (which uses
## round(), so pixel px is centred at px/PPU, with no half-pixel offset).
func _pixel_to_world(a_px: int, a_py: int) -> Vector2:
	return Vector2(
		float(a_px) / POINTS_PER_UNIT - _world_half_w + _center.x,
		float(a_py) / POINTS_PER_UNIT - _world_half_d + _center.y
	)


## Build the per-pixel play mask from the map's play bounds, and pre-clear out-of-play pixels
## in both byte buffers to 0 so they start (and stay) fully transparent. No-op — _play_bounds_active
## stays false, the mask unused — for an un-migrated map with no TerrainData, which has no play
## bounds to speak of and is left unchanged. A TerrainData map always has them.
func _build_play_mask() -> void:
	var td: TerrainData = _map.terrain_data
	if td == null:
		_play_bounds_active = false
		return
	_play_bounds_active = true
	_play_mask = PackedByteArray()
	_play_mask.resize(_img_width * _img_height)
	_play_mask.fill(1)
	for py: int in _img_height:
		for px: int in _img_width:
			var cell: Vector2i = _map.world_to_grid(_pixel_to_world(px, py))
			if not td.is_cell_in_play(cell):
				var idx: int = py * _img_width + px
				_play_mask[idx] = 0
				_explored_bytes[idx] = 0  # out of play: fully transparent, never shrouded
				_fog_bytes[idx] = 0


func _sight_disc(a_radius_px: int) -> Array:
	if _sight_disc_cache.has(a_radius_px):
		return _sight_disc_cache[a_radius_px]
	var disc: Array[Vector2i] = []
	var r2 := a_radius_px * a_radius_px
	for dx in range(-a_radius_px, a_radius_px + 1):
		for dy in range(-a_radius_px, a_radius_px + 1):
			if dx * dx + dy * dy <= r2:
				disc.append(Vector2i(dx, dy))
	_sight_disc_cache[a_radius_px] = disc
	return disc


## Pixel offsets (relative to the vision shape's centre pixel) covered by `vision_shape`
## projected onto the XZ plane. The fog is a flat plane, so only the shape's XZ
## cross-section matters. Handles the shapes we use — Cylinder/Sphere/Capsule (a circle,
## or an ellipse under non-uniform scale) and Box (a rectangle) — and falls back to any
## other shape's bounding box, so a new shape type still reveals (over-reveals at worst)
## rather than crashing. Shapes are assumed axis-aligned. Cached by footprint signature
## (kind + pixel half-extents) so identical footprints are computed once.
func _vision_offsets(a_vision_shape: CollisionShape3D) -> Array:
	var shape: Shape3D = a_vision_shape.shape
	var xf: Transform3D = a_vision_shape.global_transform
	# Axis-aligned: basis.x / basis.z carry only horizontal scale, no rotation.
	var scale_x: float = Vector2(xf.basis.x.x, xf.basis.x.z).length()
	var scale_z: float = Vector2(xf.basis.z.x, xf.basis.z.z).length()

	# kind 0 = ellipse (circular in XZ), 1 = rectangle. `half` = world-space XZ half-extents.
	var kind: int = 1
	var half: Vector2 = Vector2.ZERO
	if shape is CylinderShape3D:
		var r: float = (shape as CylinderShape3D).radius
		kind = 0
		half = Vector2(r * scale_x, r * scale_z)
	elif shape is SphereShape3D:
		var r: float = (shape as SphereShape3D).radius
		kind = 0
		half = Vector2(r * scale_x, r * scale_z)
	elif shape is CapsuleShape3D:
		var r: float = (shape as CapsuleShape3D).radius
		kind = 0
		half = Vector2(r * scale_x, r * scale_z)
	elif shape is BoxShape3D:
		var s: Vector3 = (shape as BoxShape3D).size
		half = Vector2(s.x * 0.5 * scale_x, s.z * 0.5 * scale_z)
	else:
		# Unknown shape: reveal its XZ bounding box so it still contributes vision.
		var aabb: AABB = shape.get_debug_mesh().get_aabb()
		half = Vector2(aabb.size.x * 0.5 * scale_x, aabb.size.z * 0.5 * scale_z)

	var hx: int = int(half.x * POINTS_PER_UNIT)
	var hz: int = int(half.y * POINTS_PER_UNIT)
	var key: String = "%d:%d:%d" % [kind, hx, hz]
	if _footprint_cache.has(key):
		return _footprint_cache[key]

	var offsets: Array[Vector2i] = []
	for dz: int in range(-hz, hz + 1):
		for dx: int in range(-hx, hx + 1):
			var inside: bool = true
			if kind == 0:
				# Normalised ellipse test (a circle when hx == hz).
				var nx: float = float(dx) / float(hx) if hx > 0 else 0.0
				var nz: float = float(dz) / float(hz) if hz > 0 else 0.0
				inside = nx * nx + nz * nz <= 1.0
			if inside:
				offsets.append(Vector2i(dx, dz))
	_footprint_cache[key] = offsets
	return offsets
#endregion
