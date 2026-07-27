class_name PlacementGridOverlay
extends Node3D

## The terrain grid traced around a structure being placed: the cells it would take, the cells
## around it, and — for a piece whose worth depends on the ground it covers — which of those
## cells are worth nothing. Why it looks the way it does: gdd/systems/ux/ui/construction-visuals.md
## §The placement grid.
##
## The controller hands over the lit cells and their colours; this node adds the falloff rings
## and draws. Lives under the Map, drawn like RangeIndicator: one ImmediateMesh, unshaded,
## depth-test off, lifted off the ground.

#region Constants
## Cells of grid drawn at full strength around the footprint, on every side. The falloff rings
## below extend it: one full-strength cell then two fading ones, three in all.
const MARGIN_CELLS: int = 1

## The opacity of each ring of cells past the lit region, outward. Two rings, dropping fast:
## the grid should read as fading out rather than as a hard-edged box.
const FALLOFF_ALPHAS: Array[float] = [0.3, 0.08]

## The lit region's line opacity, and a washed cell's fill as a fraction of it.
const LINE_ALPHA: float = 0.85
const WASH_ALPHA_SCALE: float = 0.35

## Lift off the terrain, as RangeIndicator does, so the lines don't z-fight the ground.
const Y_LIFT: float = 0.08

## TODO: placeholder palette — Alex is revisiting the game's colours. A cell the footprint takes
## and can build on; one it takes and cannot; any other lit cell; and one a piece would claim
## that is worth nothing to it.
const VALID_COLOR: Color = Color(0.35, 1.0, 0.45)
const INVALID_COLOR: Color = Color(1.0, 0.3, 0.25)
const NEUTRAL_COLOR: Color = Color(0.85, 0.9, 1.0)
const WORTHLESS_COLOR: Color = Color(0.45, 0.45, 0.5)

## The claim layer (tiles a dominion route's sources claim — see DominionRoute.claim_layer), by
## state. A PENDING state is the same hue drawn fainter: "this will be so, but is not yet".
const CLAIM_COLORS: Dictionary = {
	DominionRoute.ClaimState.ACTIVE: Color(0.95, 0.8, 0.3, 0.22),
	DominionRoute.ClaimState.PENDING_GAIN: Color(0.95, 0.8, 0.3, 0.09),
	DominionRoute.ClaimState.PENDING_LOSS: Color(1.0, 0.45, 0.3, 0.14),
}
#endregion

#region Properties
var map: Map = null
var _mesh: ImmediateMesh
## The claim layer, on its own mesh: it covers thousands of tiles and changes only when the
## claim does, so it is not redrawn every time the cursor crosses a cell.
var _layer_mesh: ImmediateMesh
#endregion

#region Lifecycle
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer_mesh = _add_mesh(0)
	_mesh = _add_mesh(1)


## One unshaded, always-on-top mesh child, `a_priority_offset` above the highlight priority —
## the claim layer below the grid, so the grid's lines read over it whatever depth sorting says.
func _add_mesh(a_priority_offset: int) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = RenderPriority.HIGHLIGHT_PRIORITY + a_priority_offset
	instance.material_override = material
	add_child(instance)
	return mesh
#endregion

#region Public API
## Draw `a_lit` (cell -> border colour) at full strength with its falloff rings around it, and
## wash each cell of `a_washed` (cell -> colour) in. Replaces whatever was drawn.
func draw_cells(a_lit: Dictionary, a_washed: Dictionary) -> void:
	_mesh.clear_surfaces()
	if map == null or a_lit.is_empty():
		return
	if not a_washed.is_empty():
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for cell: Vector2i in a_washed:
			var color: Color = a_washed[cell]
			color.a = LINE_ALPHA * WASH_ALPHA_SCALE
			_add_fill(cell, color)
		_mesh.surface_end()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var rings: Array[Dictionary] = falloff_rings(a_lit, FALLOFF_ALPHAS.size())
	for i: int in rings.size():
		for cell: Vector2i in rings[i]:
			var faded: Color = NEUTRAL_COLOR
			faded.a = FALLOFF_ALPHAS[i]
			_add_border(cell, faded)
	for cell: Vector2i in a_lit:
		var color: Color = a_lit[cell]
		color.a = LINE_ALPHA
		_add_border(cell, color)
	_mesh.surface_end()


func clear() -> void:
	_mesh.clear_surfaces()
	_layer_mesh.clear_surfaces()


## Wash each cell of `a_cells` (cell -> Color, alpha included) in on the claim layer.
func draw_layer(a_cells: Dictionary) -> void:
	_layer_mesh.clear_surfaces()
	if map == null or a_cells.is_empty():
		return
	_layer_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell: Vector2i in a_cells:
		_add_fill_to(_layer_mesh, cell, a_cells[cell])
	_layer_mesh.surface_end()


## The cells `a_margin` steps out from `a_cells` in any direction (diagonals included), as a set.
static func dilate(a_cells: Dictionary, a_margin: int) -> Dictionary:
	var out: Dictionary = {}
	for cell: Vector2i in a_cells:
		for dz: int in range(-a_margin, a_margin + 1):
			for dx: int in range(-a_margin, a_margin + 1):
				out[cell + Vector2i(dx, dz)] = true
	return out


## `a_count` rings of cells around `a_region`, innermost first, each one cell further out and
## none repeating a cell already in the region or an inner ring.
static func falloff_rings(a_region: Dictionary, a_count: int) -> Array[Dictionary]:
	var rings: Array[Dictionary] = []
	var inside: Dictionary = a_region.duplicate()
	for i: int in a_count:
		var ring: Dictionary = {}
		for cell: Vector2i in dilate(inside, 1):
			if not inside.has(cell):
				ring[cell] = true
		for cell: Vector2i in ring:
			inside[cell] = true
		rings.append(ring)
	return rings
#endregion

#region Drawing
func _corner(a_corner: Vector2i) -> Vector3:
	return map.grid_corner_to_world(a_corner) + Vector3(0.0, Y_LIFT, 0.0)


func _add_border(a_cell: Vector2i, a_color: Color) -> void:
	if not map.grid_coordinates_in_bounds(a_cell):
		return
	var corners: Array[Vector3] = [_corner(a_cell), _corner(a_cell + Vector2i(1, 0)),
		_corner(a_cell + Vector2i(1, 1)), _corner(a_cell + Vector2i(0, 1))]
	_mesh.surface_set_color(a_color)
	for i: int in corners.size():
		_mesh.surface_add_vertex(corners[i])
		_mesh.surface_add_vertex(corners[(i + 1) % corners.size()])


func _add_fill(a_cell: Vector2i, a_color: Color) -> void:
	_add_fill_to(_mesh, a_cell, a_color)


func _add_fill_to(a_mesh: ImmediateMesh, a_cell: Vector2i, a_color: Color) -> void:
	if not map.grid_coordinates_in_bounds(a_cell):
		return
	var a: Vector3 = _corner(a_cell)
	var b: Vector3 = _corner(a_cell + Vector2i(1, 0))
	var c: Vector3 = _corner(a_cell + Vector2i(1, 1))
	var d: Vector3 = _corner(a_cell + Vector2i(0, 1))
	a_mesh.surface_set_color(a_color)
	for v: Vector3 in [a, b, c, a, c, d]:
		a_mesh.surface_add_vertex(v)
#endregion
