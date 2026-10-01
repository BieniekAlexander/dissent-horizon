@tool
class_name MapDecorator
extends Node3D

## Draws a map's MapDecoration: one MultiMesh per doodad kind, the ground paint handed to the
## terrain shader, and (optionally) markers on the facet sites later dressing will fill.
## Built by Map at load and in the editor, never saved (Map adds it unowned), and rebuilt from
## scratch rather than patched — the decoration is derived (visual-facets.md).
##
## The ONE runtime mutation is clear_cells: a structure placed later hides the props under it.

#region Constants
const DOODAD_SHADER: String = "res://scripts/rendering/shaders/doodad.gdshader"
## Per-instance tint range, so a stand of one kind is not a stand of clones.
const TINT_MIN: float = 0.85
const TINT_MAX: float = 1.1
## Foliage sway, as DoodadLibrary heights go (doodad.gdshader sway_amount).
const SWAY_BY_KIND: Dictionary = {
	DoodadLibrary.Kind.CONIFER: 0.015, DoodadLibrary.Kind.BROADLEAF: 0.02,
	DoodadLibrary.Kind.BUSH: 0.05, DoodadLibrary.Kind.GRASS_TUFT: 0.25,
	DoodadLibrary.Kind.FLOWERS: 0.25, DoodadLibrary.Kind.REEDS: 0.2,
}
## A collapsed instance: how a cleared prop is hidden without reindexing the MultiMesh.
const _HIDDEN := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
## Facet marker colours, debug only.
const FACET_COLORS: Dictionary = {
	MapDecoration.Facet.CLIFF_FACE: Color(0.9, 0.5, 0.1),
	MapDecoration.Facet.SHORE: Color(0.2, 0.8, 0.9),
	MapDecoration.Facet.WATERFALL: Color(1, 1, 1), MapDecoration.Facet.MOUNTAIN: Color(0.6, 0.3, 0.8),
	MapDecoration.Facet.RAMP: Color(1, 0.9, 0.1),
}
#endregion

#region Properties
## Draw a small marker on every detected facet cell, to review where dressing would go.
@export var show_facet_markers: bool = false

var decoration: MapDecoration = null
## Kind -> ShaderMaterial, so Fog can shroud the props (Map.fogged_materials).
var _materials: Dictionary = {}
## Kind -> MultiMesh.
var _multimeshes: Dictionary = {}
## Cell -> Array of [kind, instance index], for clear_cells. Kept beside the MultiMeshes because
## finding a cell's instances by scanning every instance on each placement would be linear in
## the whole decoration.
var _by_cell: Dictionary = {}
#endregion


#region Public API
## Replace whatever is drawn with `a_decoration`, positioned for a grid of `a_grid_size` cells
## centred on this node.
func show_decoration(a_decoration: MapDecoration, a_grid_size: Vector2i) -> void:
	_clear()
	decoration = a_decoration
	var grid_half := Vector2(a_grid_size) * 0.5
	var by_kind: Dictionary = {}
	for placement: DoodadPlacement in a_decoration.doodads:
		if not by_kind.has(placement.kind):
			by_kind[placement.kind] = [] as Array[DoodadPlacement]
		by_kind[placement.kind].append(placement)
	for kind: int in by_kind:
		_build_kind(kind as DoodadLibrary.Kind, by_kind[kind], grid_half)
	if show_facet_markers:
		_build_facet_markers(a_decoration, grid_half)


func doodad_materials() -> Array[ShaderMaterial]:
	var result: Array[ShaderMaterial] = []
	result.assign(_materials.values())
	return result


## Hide every prop standing on `a_cells` (a structure was just placed there).
func clear_cells(a_cells: Array[Vector2i]) -> void:
	for cell: Vector2i in a_cells:
		for entry: Array in _by_cell.get(cell, []):
			var multimesh: MultiMesh = _multimeshes[entry[0]]
			multimesh.set_instance_transform(entry[1], _HIDDEN)
		_by_cell.erase(cell)
#endregion


#region Private helpers
func _build_kind(kind: DoodadLibrary.Kind, placements: Array, grid_half: Vector2) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	# Instance colours carry the tint. They must be ON even if a tint were not wanted: the
	# Compatibility renderer multiplies vertex colour by an instance colour that defaults to
	# black, and every prop renders black.
	multimesh.use_colors = true
	multimesh.mesh = DoodadLibrary.mesh_of(kind)
	multimesh.instance_count = placements.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	for i: int in placements.size():
		var p: DoodadPlacement = placements[i]
		var basis := Basis(Vector3.UP, p.yaw_radians).scaled(Vector3.ONE * p.scale)
		var at := Vector3(p.position.x - grid_half.x, p.position.y, p.position.z - grid_half.y)
		multimesh.set_instance_transform(i, Transform3D(basis, at))
		var tint: float = rng.randf_range(TINT_MIN, TINT_MAX)
		multimesh.set_instance_color(i, Color(tint, tint * rng.randf_range(0.95, 1.05), tint, 1.0))
		if not _by_cell.has(p.cell):
			_by_cell[p.cell] = []
		_by_cell[p.cell].append([kind, i])
	var material := ShaderMaterial.new()
	material.shader = load(DOODAD_SHADER) as Shader
	material.set_shader_parameter("sway_amount", SWAY_BY_KIND.get(kind, 0.0))
	var node := MultiMeshInstance3D.new()
	node.name = String(DoodadLibrary.Kind.keys()[kind]).to_pascal_case()
	node.multimesh = multimesh
	node.material_override = material
	add_child(node)
	_materials[kind] = material
	_multimeshes[kind] = multimesh


func _build_facet_markers(a_decoration: MapDecoration, grid_half: Vector2) -> void:
	for facet: int in a_decoration.facets:
		var cells: Array = a_decoration.facets[facet]
		if cells.is_empty():
			continue
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.3, 0.6, 0.3)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = FACET_COLORS.get(facet, Color.MAGENTA)
		mesh.material = material
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = cells.size()
		var map := get_parent() as Map
		for i: int in cells.size():
			var cell: Vector2i = cells[i]
			var y: float = map.terrain_data.cell_mean_height(cell) if map != null else 0.0
			multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY,
				Vector3(cell.x + 0.5 - grid_half.x, y + 0.3, cell.y + 0.5 - grid_half.y)))
		var node := MultiMeshInstance3D.new()
		node.name = "Facet" + String(MapDecoration.Facet.keys()[facet]).to_pascal_case()
		node.multimesh = multimesh
		add_child(node)


func _clear() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_materials.clear()
	_multimeshes.clear()
	_by_cell.clear()
	decoration = null
#endregion
