class_name Fog
extends MeshInstance3D

## Terrain visibility as seen by a single commander, kept INCREMENTALLY: a per-pixel count of
## the vision sources covering each pixel, and for each source the stamp it last added. A tick
## re-stamps only the sources whose stamp changed, and the texture is uploaded only for the
## fog being displayed, only when its bytes changed. So a tick in which nothing crossed a pixel
## does no fog work at all. See gdd/systems/combat/scan-and-vision-cost.md §The fog of war.
##
## The raster itself — counts, stamps, display and explored bytes, and every per-pixel lookup —
## is a native FogRaster (native/src/fog_raster.h). This node keeps the registry, the texture
## upload, the terrain-shader driver and hiding pieces under the shroud.

## Three-state terrain visibility as seen by a single commander.
##   UNSEEN    — tile has never been in any owned unit's vision radius.
##   EXPLORED  — tile was seen at some point but is currently fogged.
##   IN_SIGHT  — tile is inside an owned unit's vision radius this frame.
enum TerrainVisibility {
	UNSEEN = FogRaster.UNSEEN,
	EXPLORED = FogRaster.EXPLORED,
	IN_SIGHT = FogRaster.IN_SIGHT,
}

#region Properties
var POINTS_PER_UNIT: float = 1.0  # overwritten in _initialize() = 1.0 / Map.CELL_SIZE
## L8 byte value for "explored but not currently visible" (alpha ≈ 0.5).
const EXPLORED_ALPHA: int = FogRaster.EXPLORED_ALPHA
## An explored-buffer pixel no vision has ever touched.
const UNEXPLORED_BYTE: int = FogRaster.UNEXPLORED_BYTE

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

## The fog raster; unconfigured (every lookup unseen, nothing in vision) until _configure.
var _raster: FogRaster = FogRaster.new()
## The raster's world framing, kept for the terrain shader's fog_rect.
var _center: Vector2
var _world_half_w: float  # actual world half-extent in X
var _world_half_d: float  # actual world half-extent in Z
## Structure instance id -> [the footprint cells array it was built from, the in-play pixel
## indices those cells cover]. Memoized: resolving cells to pixels every tick for every
## structure was most of the fog's cost once sight became incremental, and it cannot change
## while the cells array does not (Map replaces an entry, never edits it).
var _footprint_pixels: Dictionary = {}
var _fog_image: Image
var _fog_texture: ImageTexture
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
	var center: Vector2 = VU.in_xz(map.global_position)
	_configure(
		int(_world_half_w * 2.0 * POINTS_PER_UNIT),
		int(_world_half_d * 2.0 * POINTS_PER_UNIT),
		center,
		_world_half_w,
		_world_half_d
	)
	_build_play_mask()  # holds out-of-play pixels transparent (zeroes them in both byte buffers)

	_fog_image = Image.create_from_data(
		_raster.image_width(),
		_raster.image_height(),
		false,
		Image.FORMAT_L8,
		_raster.explored_bytes()
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
	if _raster.is_texture_stale() and Fog.get_active_fog() == self:
		_fog_image.set_data(
			_raster.image_width(),
			_raster.image_height(),
			false,
			Image.FORMAT_L8,
			_raster.fog_bytes()
		)
		_fog_texture.update(_fog_image)
		_raster.mark_texture_uploaded()

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


## This fog's raster, for a reader that works pixel by pixel (the minimap).
func raster() -> FogRaster:
	return _raster


## Returns the three-state terrain visibility for the fog pixel covering
## `world_xz`. Used by the minimap to colour terrain appropriately.
func terrain_visibility_at(a_world_xz: Vector2) -> TerrainVisibility:
	return _raster.terrain_visibility_at(a_world_xz) as TerrainVisibility


## Whether [a_world_xz] is currently within this commander's live vision (fog pixel clear).
## Unlike terrain_visibility_at this works for any registered commander's Fog, not only the
## spectated one — every one's raster is kept current each physics tick.
##
## OUT OF PLAY IS NOT IN VISION: byte 0 means both "revealed" and "outside the play rectangle",
## and conflating them left anything sited past the play edge permanently in sight. Why:
## gdd/systems/combat/target-acquisition.md §Out of play is not in vision.
func fog_clear_at(a_world_xz: Vector2) -> bool:
	return _raster.fog_clear_at(a_world_xz)


## Whether [a_world_xz] has EVER been in this commander's vision — in sight now, or explored.
## Works for any registered commander's Fog, since every one keeps its raster current. Out of
## play is never explored.
func explored_at(a_world_xz: Vector2) -> bool:
	return _raster.explored_at(a_world_xz)


## True when ANY grid cell [structure] occupies is currently in this fog's vision.
## Structures are discretised into a footprint of terrain cells, so a multi-cell
## building counts as seen the instant any of its cells is scouted — not only when
## the cell under its origin is. Falls back to the origin point when the structure
## has no registered footprint (or the Map is unavailable).
func structure_in_vision(a_structure: Node) -> bool:
	var origin_xz: Vector2 = VU.in_xz((a_structure as Node3D).global_position)
	if _map == null or not _raster.is_configured():
		return fog_clear_at(origin_xz)
	var cells: Variant = _map.structure_cell_map.get(a_structure)
	if cells == null or (cells as Array).is_empty():
		return fog_clear_at(origin_xz)
	return _raster.any_in_sight(_structure_pixels(a_structure, cells))


## Permanently reveal a circular area in world-space XZ (lift fog of war).
## The pixels are written to the explored bytes so the reveal persists across frames.
## Safe to call before _initialize() completes — does nothing while unconfigured.
func reveal_region(a_world_xz: Vector2, a_radius_world: float) -> void:
	_raster.reveal_region(a_world_xz, a_radius_world)


#endregion


#region Sight counts
## Size and frame the raster: `a_width` x `a_height` pixels centred on world `a_center`,
## covering `a_half_w` x `a_half_d` world units either side, at POINTS_PER_UNIT. Nothing
## explored, nothing in sight, every pixel in play.
func _configure(
	a_width: int, a_height: int, a_center: Vector2, a_half_w: float, a_half_d: float
) -> void:
	_center = a_center
	_world_half_w = a_half_w
	_world_half_d = a_half_d
	_footprint_pixels.clear()
	_raster.configure(a_width, a_height, a_center, a_half_w, a_half_d, POINTS_PER_UNIT)


## Bring the sight counts up to date with `a_sources` (the "los" group): re-stamp only a source
## on this commander's side (allies' sight counts as its own — vision is shared within an
## alliance) whose pixel or footprint changed, and withdraw the stamp of any source that no
## longer counts. Diffing each tick, rather than hooking each event that changes vision (capture,
## death, garrisoning, an upgrade, construction), is what keeps it correct for the event
## nobody remembered.
func _update_sight(a_sources: Array) -> void:
	_raster.update_sight(a_sources, viewer_commander_id())


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
	var points := PackedVector2Array()
	for cell: Vector2i in a_cells:
		points.append(VU.in_xz(_map.grid_to_world(cell)))
	# Out of play is not in vision (see fog_clear_at), so those pixels are left out.
	var pixels: PackedInt32Array = _raster.in_play_pixels(points)
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
	return _raster.world_to_pixel(a_world_xz)


## Build the per-pixel play mask from the map's play bounds: out-of-play pixels are held fully
## transparent, never shrouded or explored, so the fog stops at the play area instead of hanging
## black over the chopped-off corners. Leaves every pixel in play for an un-migrated map with no
## TerrainData, which has no play bounds to speak of. A TerrainData map always has them.
func _build_play_mask() -> void:
	var td: TerrainData = _map.terrain_data
	if td == null:
		return
	var width: int = _raster.image_width()
	var height: int = _raster.image_height()
	var cells_in_play: PackedByteArray = td.in_play_mask()
	var gw: int = td.grid_width()
	var mask := PackedByteArray()
	mask.resize(width * height)
	for py: int in height:
		for px: int in width:
			var cell: Vector2i = _map.world_to_grid(_raster.pixel_to_world(px, py))
			var in_play: bool = (
				cells_in_play[cell.y * gw + cell.x] != 0
				if td.is_cell_in_bounds(cell)
				else td.is_cell_in_play(cell)
			)
			mask[py * width + px] = 1 if in_play else 0
	_raster.set_play_mask(mask)


## Pixel offsets (relative to the vision shape's centre pixel) covered by `vision_shape`
## projected onto the XZ plane — what a vision source stamps. The rule is the raster's; this
## exposes it to tests that rebuild the fog from scratch.
func _vision_offsets(a_vision_shape: CollisionShape3D) -> Array:
	return _raster.vision_offsets(a_vision_shape)
#endregion
