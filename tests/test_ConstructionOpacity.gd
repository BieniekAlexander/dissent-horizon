extends GutTest

## The construction fade: a structure is drawn at one of three opacities depending on how
## real it is (see MeshVisual's OPACITY_* constants) —
##   0.2 planned      — a ghost: the placement preview under the cursor, or the blueprint
##                      standing at a site an issued Build order has claimed.
##   0.5 constructing — placed on the map, collidable, not finished.
##   1.0 built        — finished.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ConstructionOpacity.gd -gexit

const STRUCTURE: Dictionary = {"mesh": true}
const UNIT: Dictionary = {"mesh": true, "speed": 2.0}


func _visual(a_entity: Node) -> MeshVisual:
	return a_entity.get_node_or_null("MeshVisual") as MeshVisual


## Editor-placed structures start built (build_progress defaults to 1.0), so nothing fades.
func test_finished_structure_is_fully_opaque() -> void:
	var s: Node = FakePieces.structure(STRUCTURE)
	add_child_autofree(s)
	assert_eq(_visual(s).opacity(), MeshVisual.OPACITY_BUILT,
		"a structure that starts built is drawn solid")


## Build.fulfill_action calls begin_construction() on the instance BEFORE adding it to the
## tree, so the fade has to be applied from _ready — the progress signal it emits there has
## no listeners yet.
func test_structure_placed_under_construction_is_faded() -> void:
	var s: Node = FakePieces.structure(STRUCTURE)
	(s as Commandable).begin_construction()
	add_child_autofree(s)
	assert_eq(_visual(s).opacity(), MeshVisual.OPACITY_CONSTRUCTING,
		"a freshly placed structure is drawn translucent")


## The fade is a STEP, not a ramp with build_progress: a structure halfway up still reads
## as "under construction" rather than as nearly-invisible.
func test_opacity_does_not_track_progress_until_complete() -> void:
	var s: Node = FakePieces.structure(STRUCTURE)
	var c := s as Commandable
	c.begin_construction()
	add_child_autofree(s)
	c.advance_build_progress(0.5)
	assert_almost_eq(c.build_progress, 0.6, 0.0001, "progress advanced (0.1 start + 0.5)")
	assert_eq(_visual(s).opacity(), MeshVisual.OPACITY_CONSTRUCTING,
		"half-built is still drawn at the construction opacity")


func test_finishing_construction_restores_full_opacity() -> void:
	var s: Node = FakePieces.structure(STRUCTURE)
	var c := s as Commandable
	c.begin_construction()
	add_child_autofree(s)
	assert_true(c.advance_build_progress(1.0), "advancing past 1.0 reports completion")
	assert_true(c.is_built, "the structure is now built")
	assert_eq(_visual(s).opacity(), MeshVisual.OPACITY_BUILT,
		"a completed structure snaps to solid")


## Units are always built, so the construction fade never touches them.
func test_units_are_never_faded() -> void:
	var u: Node = FakePieces.unit(UNIT)
	add_child_autofree(u)
	var visual: MeshVisual = _visual(u)
	if visual == null:
		pass_test("this unit is billboard art, not a MeshVisual — nothing to fade")
		return
	assert_eq(visual.opacity(), MeshVisual.OPACITY_BUILT, "units are drawn solid")


## A faded model must not keep casting a solid shadow, or it reads as a finished building
## from the ground up regardless of its alpha.
func test_fading_drops_the_models_shadow() -> void:
	var s: Node = FakePieces.structure(STRUCTURE)
	var c := s as Commandable
	c.begin_construction()
	add_child_autofree(s)
	for mi: MeshInstance3D in _mesh_instances(_visual(s)):
		assert_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"%s casts no shadow while under construction" % mi.name)
	c.advance_build_progress(1.0)
	for mi: MeshInstance3D in _mesh_instances(_visual(s)):
		assert_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
			"%s casts a shadow again once finished" % mi.name)


func _mesh_instances(a_node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if a_node is MeshInstance3D:
		out.append(a_node as MeshInstance3D)
	for child: Node in a_node.get_children():
		out.append_array(_mesh_instances(child))
	return out
