extends GutTest

## Coverage for the "see-through when obstructed" silhouette: MeshVisual puts Godot's
## built-in x-ray stencil (BaseMaterial3D.STENCIL_MODE_XRAY) on the surface materials it
## already duplicates for tinting, so a unit hidden behind a building or a cliff is redrawn
## over it in its own team colour. Only entities without a Structure component get it — see
## MeshVisual._wants_obstruction_silhouette.
##
## The stencil is what makes this correct rather than merely present. The rejected
## alternative — a shader comparing the fragment against hint_depth_texture — asks "is
## anything nearer than me here?", which an unobstructed unit answers YES to twice: once
## because the depth buffer holds its OWN opaque draw (a float compared against itself, so
## rounding paints the whole model in silhouette), and once because a model's own head
## really is in front of its own shoulders. The first is a bias away; the second is not,
## and it is why this is a stencil. See MeshVisual's #region Obstruction silhouette.
##
## Real scenes are used (not bare nodes) so the parent/Structure-sibling lookup and the
## actual imported-model surface list are exercised for real — an irregular (unit, no
## Structure) and the anarchist command center (structure, has both Structure and
## MeshVisual, unlike most of the still-Sprite-based structures).

const UNIT: PackedScene = preload("res://scenes/entities/units/an/an_bioLight_builder.tscn")
const STRUCTURE: PackedScene = preload("res://scenes/entities/structures/an/an_commandCenter.tscn")


func _mesh_visual_of(a_node: Node) -> MeshVisual:
	return a_node.get_node("MeshVisual") as MeshVisual


func _materials_of(a_visual: MeshVisual) -> Array[BaseMaterial3D]:
	var out: Array[BaseMaterial3D] = []
	for rec: Dictionary in a_visual._surfaces:
		out.append(rec["mat"] as BaseMaterial3D)
	return out


func test_non_structure_entity_gets_the_xray_stencil() -> void:
	var unit: Node = UNIT.instantiate()
	add_child_autofree(unit)
	var visual: MeshVisual = _mesh_visual_of(unit)
	var mats: Array[BaseMaterial3D] = _materials_of(visual)
	assert_false(mats.is_empty(), "the irregular model has at least one tintable surface")
	for mat: BaseMaterial3D in mats:
		assert_eq(mat.stencil_mode, BaseMaterial3D.STENCIL_MODE_XRAY,
			"a unit's surfaces are drawn through whatever hides them")


func test_structure_entity_has_no_silhouette() -> void:
	var structure: Node = STRUCTURE.instantiate()
	add_child_autofree(structure)
	var visual: MeshVisual = _mesh_visual_of(structure)
	var mats: Array[BaseMaterial3D] = _materials_of(visual)
	assert_false(mats.is_empty(), "the command center model has at least one tintable surface")
	assert_false(visual._silhouette, "a Structure sibling opts the model out")
	for mat: BaseMaterial3D in mats:
		assert_eq(mat.stencil_mode, BaseMaterial3D.STENCIL_MODE_DISABLED,
			"structures obstructing structures is left to mesh design, not drawn around")


func test_silhouette_color_tracks_team_tint() -> void:
	var unit: Node = UNIT.instantiate()
	add_child_autofree(unit)
	var visual: MeshVisual = _mesh_visual_of(unit)
	var team_color := Color(1.0, 0.2, 0.2)
	visual.set_team_color(team_color)
	for mat: BaseMaterial3D in _materials_of(visual):
		assert_eq(mat.stencil_color.r, team_color.r)
		assert_eq(mat.stencil_color.g, team_color.g)
		assert_eq(mat.stencil_color.b, team_color.b)
		assert_almost_eq(mat.stencil_color.a, MeshVisual.SILHOUETTE_ALPHA, 0.001,
			"alpha is fixed, not tied to construction opacity")


## A faded material is transparent, so it writes neither depth nor stencil — leaving the
## x-ray pass with no mark to test against, which would paint the entire model as hidden.
func test_silhouette_is_suppressed_while_the_model_is_faded() -> void:
	var unit: Node = UNIT.instantiate()
	add_child_autofree(unit)
	var visual: MeshVisual = _mesh_visual_of(unit)
	visual.set_opacity(MeshVisual.OPACITY_CONSTRUCTING)
	for mat: BaseMaterial3D in _materials_of(visual):
		assert_eq(mat.stencil_mode, BaseMaterial3D.STENCIL_MODE_DISABLED,
			"no silhouette while translucent")
	visual.set_opacity(MeshVisual.OPACITY_BUILT)
	for mat: BaseMaterial3D in _materials_of(visual):
		assert_eq(mat.stencil_mode, BaseMaterial3D.STENCIL_MODE_XRAY,
			"and it comes back when the model is solid again")


func test_each_entity_keeps_its_own_silhouette_colour() -> void:
	var a: Node = UNIT.instantiate()
	var b: Node = UNIT.instantiate()
	add_child_autofree(a)
	add_child_autofree(b)
	_mesh_visual_of(a).set_team_color(Color(1.0, 0.2, 0.2))
	_mesh_visual_of(b).set_team_color(Color(0.2, 1.0, 0.2))
	var mat_a: BaseMaterial3D = _materials_of(_mesh_visual_of(a))[0]
	var mat_b: BaseMaterial3D = _materials_of(_mesh_visual_of(b))[0]
	assert_ne(mat_a, mat_b, "surface materials are duplicated per entity, never shared")
	assert_ne(mat_a.stencil_color, mat_b.stencil_color)
