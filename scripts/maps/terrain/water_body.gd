@tool
class_name WaterBody
extends Node3D

## One contiguous body of water: a scene object owning a water LEVEL and a seed cell, from
## which everything else is derived — which cells it covers, how deep each is, the surface it
## draws, and which cells leave the navmesh.
##
## AUTHORED: `level`, `seed_cell`, `energy`, `charge_color`. DERIVED and never saved: the
## basin, the surface mesh, the submerged-cell publication, and THIS NODE'S TRANSFORM. A
## re-sculpt of the terrain under a body therefore re-floods it correctly on the next load
## instead of leaving a stale footprint behind (~/.claude/CLAUDE.md §10).
##
## The water itself has NO physics: units walk through it and the mesh is visual. What makes
## deep water impassable is that its cells are submerged past WaterBasin.WADE_DEPTH, which
## TerrainGrid marks and NavManager then bakes around.
##
## Rules: gdd/systems/terrain-and-navigation/water-bodies.md

#region Constants
## What a lithium pond yields per extraction cycle, as a multiple of the extractor's own
## rate. The pond is the fast-but-finite half of the energy economy (gdd/setting/resources.md
## §Lithium ponds), so it pays faster than an inexhaustible extraction site does — four times as
## fast, so the pond is clearly the better short-term income
## (gdd/systems/macroeconomics/pacing/income-and-cost.md).
const POND_RATE_MULTIPLIER: int = 4

## The energy an authored lithium pond is normally charged with. NOT the property default —
## a plain body of water holds none, and a pond is a body someone deliberately filled.
## Generated ponds are priced differently (cells × richness) — see
## gdd/systems/terrain-and-navigation/map-generation.md.
const NOMINAL_ENERGY: int = 2500

## The non-blue surface colours a charged pond picks from — the pinks, ochres and greens of a
## real lithium evaporation pond. Picked once when a body is authored and stored on it, so a
## map looks the same every time it loads.
const CHARGE_COLORS: Array[Color] = [
	Color(0.87, 0.42, 0.55),  # brine pink
	Color(0.92, 0.78, 0.33),  # sulphur yellow
	Color(0.80, 0.35, 0.36),  # iron rust
	Color(0.62, 0.76, 0.36),  # algal green
	Color(0.90, 0.55, 0.30),  # amber
]

const _SURFACE_NODE_NAME: StringName = &"Surface"
const _SHADER_PATH: String = "res://scripts/rendering/shaders/water_surface.gdshader"
#endregion

#region Authored properties
## World-space Y of the water surface. Every depth in the body is measured against it.
@export var level: float = 0.0:
	set(v):
		if is_equal_approx(level, v):
			return
		level = v
		rebuild()

## The cell the basin is flooded outward from — the cell the author clicked. Kept rather than
## the resulting cell list because it is the authored fact; the list is a consequence of it
## and of terrain that may still change.
@export var seed_cell: Vector2i = Vector2i.ZERO:
	set(v):
		if seed_cell == v:
			return
		seed_cell = v
		rebuild()

## Energy left in the body. Zero — plain water — is the default; a lithium pond is a body
## someone charged. Drawn down by extractors built in it and never replenished.
@export var energy: int = 0:
	set(v):
		energy = maxi(0, v)
		_initial_energy = maxi(_initial_energy, energy)
		_push_charge()

## The surface colour a FULL charge tints this body toward. Meaningless at zero energy.
@export var charge_color: Color = CHARGE_COLORS[0]:
	set(v):
		charge_color = v
		_push_charge()
#endregion

#region Derived state
## The flooded region, re-derived from (terrain, seed_cell, level) on every rebuild. Never
## null after initialization; empty when the level floods nothing.
var basin: WaterBasin = WaterBasin.new()

## The charge fraction is measured against the body's FULL charge, which is whatever it was
## first given. Held because `energy` alone cannot say how drained a pond is.
var _initial_energy: int = 0

var _map: Map = null
var _surface: MeshInstance3D = null
var _material: ShaderMaterial = null
#endregion

#region Lifecycle
## _ENTER_TREE, NOT _READY, and that is the fix for "editing `level` sometimes does nothing".
##
## `_ready` fires ONCE in a node's lifetime. Undo/redo removes a body from the tree and adds it
## back — the same instance — so `_ready` never ran again, `_map` stayed null from _exit_tree,
## `rebuild()` returned early, and every later edit to `level` was silently ignored. The body
## sat there drawing the surface it had before the undo.
##
## At runtime Map drives initialization instead: a child is ready before its parent, so the
## terrain grid this body publishes into does not exist yet. In the editor Map._ready returns
## early, so a body authored into a scene has to find its own way to the terrain.
func _enter_tree() -> void:
	if Engine.is_editor_hint():
		call_deferred(&"initialize", _find_map())


func _exit_tree() -> void:
	if _map != null:
		_map.unregister_water_body(self)
		_map = null
#endregion

#region Public API
## Bind this body to `a_map` and derive everything from its terrain. Idempotent: calling it
## again re-floods the basin, which is what a terrain edit under an authored body needs.
func initialize(a_map: Map) -> void:
	if a_map == null:
		return
	if _map != a_map:
		if _map != null:
			_map.unregister_water_body(self)
		_map = a_map
		_map.register_water_body(self)
	rebuild()


## Re-flood the basin, redraw the surface, and ask the map to republish the water layer —
## which it does over EVERY body at once, because the terrain grid holds the union and cannot
## be told about one body in isolation. That makes an author's edit to `level` land on the
## navmesh immediately, at the cost of rewalking the other bodies' cells; there are a handful
## of bodies per map and they only change while a map is being authored.
func rebuild() -> void:
	# Re-resolve a lost map rather than doing nothing. A body that has been out of the tree has
	# no map until something hands it one, and a property setter is exactly when an author
	# expects the surface to update — see _enter_tree for how it comes to be lost.
	if _map == null:
		var found: Map = _find_map()
		if found != null:
			initialize(found)  # calls back into rebuild() with the map set
			return
	if _map == null or _map.terrain_data == null:
		return
	basin = WaterBasin.fill(_map.terrain_data, seed_cell, level)
	_recentre_on_basin()
	_rebuild_surface()
	_push_charge()
	_map.refresh_water()


## Draw `a_base_rate` energy at the pond multiplier, clamped to what is left. Returns what
## was actually withdrawn, which is 0 for a spent or uncharged body — an extractor pays its
## commander exactly this, so a drained pond stops earning without needing to be torn down.
func extract(a_base_rate: int) -> int:
	var taken: int = mini(a_base_rate * POND_RATE_MULTIPLIER, energy)
	if taken <= 0:
		return 0
	energy -= taken
	return taken


## Whether this body's water covers `a_cell` at any depth.
## The extractor drawing from this body, or null.
##
## ONE AT A TIME, and for a reason a site does not have: a pond is a FINITE charge
## (`energy`), so a second extractor on it would not add income — it would split one pond's
## remaining charge between two structures and drain it at twice the rate for the same total.
## That is the same rule `ExtractionSite.extractor` enforces for the inexhaustible half of
## the economy, and this is its missing counterpart.
##
## HELD UNTYPED. The claim is released explicitly by `Extractor._on_death`, but a body that
## outlives a missed release must not be stranded unworkable forever — and a typed field
## holding a freed object cannot even be READ into a typed local (CLAUDE.md §A freed object
## cannot be passed to a typed parameter). `has_extractor()` therefore validates rather than
## trusting the field.
var extractor: Variant = null


## Whether this body is already being worked. The placement question every route asks —
## the player's build preview, `Build.meets_precondition`, and the bot's income search — so
## they cannot disagree about which ponds are free.
func has_extractor() -> bool:
	return extractor != null and is_instance_valid(extractor)


## Whether this body is worth putting an extractor on at all: charged, and unclaimed. A
## drained pond is dry ground with a surface on it.
func is_workable() -> bool:
	return energy > 0 and not has_extractor()


func covers_cell(a_cell: Vector2i) -> bool:
	return basin.covers_cell(a_cell)


## Whether `a_cell` is water a unit can wade through — and, because buildability follows the
## same line, the only water a structure may stand in.
func is_shallow(a_cell: Vector2i) -> bool:
	return basin.is_shallow(a_cell)


## Whether `a_cell` is submerged past wading depth: impassable, unbuildable, no navmesh.
func is_deep(a_cell: Vector2i) -> bool:
	return basin.is_deep(a_cell)


## The charge this body was first given — its energy before any extraction. Zero for plain
## water.
func full_charge() -> int:
	return _initial_energy


## How full the body is, 0..1. 0 for water that never held energy, so an uncharged body and a
## spent one look the same — which is the point: a drained pond IS ordinary water.
func charge_fraction() -> float:
	if _initial_energy <= 0:
		return 0.0
	return float(energy) / float(_initial_energy)


## The material the surface draws with, for Fog to push the shroud into (see
## Map.fogged_materials). Null before the first rebuild.
func surface_material() -> ShaderMaterial:
	return _material
#endregion

#region Private helpers
## Rebuild the surface plane under an INTERNAL child, so the generated mesh is never written
## into the scene file and the author only ever edits the four properties above.
func _rebuild_surface() -> void:
	if _surface == null or not is_instance_valid(_surface):
		_surface = MeshInstance3D.new()
		_surface.name = _SURFACE_NODE_NAME
		add_child(_surface, false, Node.INTERNAL_MODE_BACK)
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load(_SHADER_PATH) as Shader
		_surface.material_override = _material
	_surface.mesh = WaterSurfaceMesh.build(basin, _map.terrain_data)
	_surface.visible = _surface.mesh != null
	# Vertices are in the heightmap's own frame (see WaterSurfaceMesh), which is the Map's —
	# not this node's, whose transform is whatever the author left it at.
	_surface.global_transform = _map.global_transform


## Sit this node at the middle of its own basin, so the editor shows it where the pond is
## instead of at the Map's origin.
##
## PURELY COSMETIC, and safe precisely because nothing reads this transform. The basin is
## derived from `seed_cell` and the terrain in GRID coordinates; the surface pins itself to
## the MAP's frame rather than this node's (see _rebuild_surface, which says so); the
## submerged-cell publication is cells. The node is a gizmo, not geometry — moving it cannot
## move the water.
##
## DERIVED, so it is never written to the scene (see _validate_property): a stored transform
## would be a second, stale answer to where the pond is the moment the terrain under it is
## re-sculpted.
func _recentre_on_basin() -> void:
	if _map == null or not is_inside_tree():
		return
	var cells: Array[Vector2i] = basin.covered_cells()
	if cells.is_empty():
		return  # nothing flooded: leave it wherever it is rather than aiming at an average of none
	var total: Vector3 = Vector3.ZERO
	for cell: Vector2i in cells:
		total += _map.grid_to_world(cell)
	var centre: Vector3 = total / float(cells.size())
	# global_position rather than position: the Map carries CELL_SIZE as its own scale, so the
	# parent frame is not world units (CLAUDE.md §`Map.CELL_SIZE` const).
	global_position = Vector3(centre.x, level, centre.z)


## Keep the derived transform out of the scene file.
##
## `transform` is the property Node3D actually STORES (`position` / `rotation` / `scale` are
## editor-side views of it), so this is the one to strip. Read-only as well, because an author
## who dragged the node would otherwise watch it snap back on the next rebuild with no
## indication why.
func _validate_property(a_property: Dictionary) -> void:
	if a_property.name == "transform":
		a_property.usage = (a_property.usage | PROPERTY_USAGE_READ_ONLY) & ~PROPERTY_USAGE_STORAGE


func _push_charge() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("charge", charge_fraction())
	_material.set_shader_parameter("charge_color", charge_color)


## The owning Map, for the editor path where nothing hands one over.
func _find_map() -> Map:
	var node: Node = get_parent()
	while node != null:
		if node is Map:
			return node as Map
		node = node.get_parent()
	return null
#endregion
