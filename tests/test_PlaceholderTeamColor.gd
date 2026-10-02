extends GutTest

## The team tint reaching a piece that is still wearing a GENERATED PLACEHOLDER model.
##
## A placeholder is a bare primitive with no material on it (see
## tools/spec_import/visual_defaults.gd), and MeshVisual used to gather only surfaces that
## already carried a BaseMaterial3D. So the pieces with no art — precisely the ones with
## nothing else to read allegiance from — were the ones drawn in the same colour for every
## commander. MeshVisual now fits an unmaterialed surface with a plain white
## StandardMaterial3D, which looks identical untinted and multiplies like any other.

const PLAYER_RED: Color = Color(0.9, 0.2, 0.2)


func _visual_with_bare_mesh() -> MeshVisual:
	var visual := MeshVisual.new()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = BoxMesh.new()
	visual.add_child(mesh_instance)
	add_child_autofree(visual)
	return visual


func test_a_mesh_with_no_material_is_still_gathered() -> void:
	assert_eq(
		_visual_with_bare_mesh()._surfaces.size(),
		1,
		"the bare surface is tintable rather than skipped"
	)


func test_a_mesh_with_no_material_starts_white() -> void:
	# Its design albedo has to match how the engine drew it before, or fitting the material
	# would silently restyle every placeholder in the game.
	var visual: MeshVisual = _visual_with_bare_mesh()
	assert_eq(visual._surfaces[0]["albedo"], Color.WHITE)


func test_a_mesh_with_no_material_takes_the_team_colour() -> void:
	var visual: MeshVisual = _visual_with_bare_mesh()
	visual.set_team_color(PLAYER_RED)
	var mat: BaseMaterial3D = visual._surfaces[0]["mat"] as BaseMaterial3D
	assert_almost_eq(mat.albedo_color.r, PLAYER_RED.r, 0.01)
	assert_almost_eq(mat.albedo_color.g, PLAYER_RED.g, 0.01)
	assert_almost_eq(mat.albedo_color.b, PLAYER_RED.b, 0.01)


## A ShaderMaterial still can't be tinted — that needs a uniform, and quietly replacing one
## with a StandardMaterial3D would throw the custom look away.
func test_a_shader_material_surface_is_still_skipped() -> void:
	var visual := MeshVisual.new()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = BoxMesh.new()
	mesh_instance.set_surface_override_material(0, ShaderMaterial.new())
	visual.add_child(mesh_instance)
	add_child_autofree(visual)
	assert_eq(visual._surfaces.size(), 0)


## The whole point, on a real piece: a unit still wearing the importer's stand-in.
func test_a_piece_wearing_a_placeholder_takes_the_team_colour() -> void:
	var unit: Node = FakePieces.unit({"mesh": true})
	add_child_autofree(unit)
	var visual := unit.get_node("MeshVisual") as MeshVisual
	assert_not_null(
		unit.get_node_or_null("MeshVisual/PlaceholderModel"),
		"guards the fixture: this piece has no art yet"
	)
	assert_gt(visual._surfaces.size(), 0, "the stand-in is tintable")
	visual.set_team_color(PLAYER_RED)
	for record: Dictionary in visual._surfaces:
		var mat: BaseMaterial3D = record["mat"] as BaseMaterial3D
		assert_lt(mat.albedo_color.g, mat.albedo_color.r, "drawn in the commander's colour")
