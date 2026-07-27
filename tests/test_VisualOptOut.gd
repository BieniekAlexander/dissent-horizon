extends GutTest

## A piece opts out of a model by WAIVING the norm that it carries one —
## `exceptions: {has_mesh_visual: <why>}` — so the declaration goes STALE, and fails the
## import, the day the scene grows authored art. The rule judges the scene, not just the doc,
## which is what the registry's scene view is for. See
## gdd/systems/ux/ui/generated-visual-defaults.md and composition-rework.md §MeshVisual is
## default-on.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gtest=res://tests/test_VisualOptOut.gd -gdir=res://tests/none -gexit

## Preloaded rather than reached through class_name: a headless run does not refresh the
## global class cache. Same reason as test_SpecGenerators.
const SpecRules := preload("res://tools/spec_import/spec_rules.gd")
const SpecSchema := preload("res://tools/spec_import/schema.gd")
const VisualMeasure := preload("res://tools/spec_import/visual_measure.gd")
const SpecComposition := preload("res://tools/spec_import/composition.gd")

const WAIVED: Dictionary = {"exceptions": {"has_mesh_visual": "a trigger volume, nothing to see"}}


func _verdicts(a_spec: Dictionary, a_view: Dictionary) -> Array:
	return SpecRules.evaluate(a_spec, a_view) \
		.filter(func(e: Dictionary) -> bool: return e["id"] == "has_mesh_visual") \
		.map(func(e: Dictionary) -> int: return e["verdict"])


func test_an_undeclared_piece_without_art_is_incomplete_not_failed() -> void:
	assert_eq(_verdicts({}, {"has_authored_mesh": false}), [SpecRules.Verdict.INCOMPLETE],
		"it wears the placeholder — reported, never an error")


func test_an_undeclared_piece_with_art_is_silent() -> void:
	assert_eq(_verdicts({}, {"has_authored_mesh": true}), [])


func test_a_waiver_on_a_piece_without_art_is_exceptional() -> void:
	assert_eq(_verdicts(WAIVED, {"has_authored_mesh": false}), [SpecRules.Verdict.EXCEPTIONAL])


func test_a_waiver_on_a_piece_with_art_is_stale() -> void:
	assert_eq(_verdicts(WAIVED, {"has_authored_mesh": true}), [SpecRules.Verdict.STALE])


func test_the_waiver_is_the_opt_out() -> void:
	assert_true(SpecSchema.wants_no_visual(WAIVED))
	assert_false(SpecSchema.wants_no_visual({}))


func test_the_old_key_is_retired() -> void:
	var spec: Dictionary = {"visual": "none"}
	var errors: Array = SpecSchema.normalize(spec)
	assert_true(errors.any(func(e: String) -> bool: return e.contains("has_mesh_visual")),
		"refused, naming the replacement: %s" % [errors])


func _piece_with(a_children: Array[Node]) -> Node3D:
	var root: Node3D = Node3D.new()
	var mesh_visual: Node3D = Node3D.new()
	mesh_visual.name = "MeshVisual"
	root.add_child(mesh_visual)
	for child: Node in a_children:
		mesh_visual.add_child(child)
	autofree(root)
	return root


func test_only_the_generated_placeholder_is_not_art() -> void:
	assert_false(VisualMeasure.has_authored_mesh(_piece_with([])), "empty")
	var placeholder: MeshInstance3D = MeshInstance3D.new()
	placeholder.name = VisualMeasure.PLACEHOLDER_NODE
	assert_false(VisualMeasure.has_authored_mesh(_piece_with([placeholder])), "the stand-in")
	var model: MeshInstance3D = MeshInstance3D.new()
	model.name = "Model"
	assert_true(VisualMeasure.has_authored_mesh(_piece_with([model])), "somebody's art")


func test_an_emission_is_judged_by_its_unstamped_meshes() -> void:
	var emission: Node3D = Node3D.new()
	autofree(emission)
	var generated: MeshInstance3D = MeshInstance3D.new()
	generated.name = VisualMeasure.IN_FLIGHT_MESH_NODE
	generated.set_meta(VisualMeasure.STAMP_MESH, "linear projectile")
	emission.add_child(generated)
	assert_false(VisualMeasure.has_authored_mesh(emission), "the importer's stand-in")
	generated.remove_meta(VisualMeasure.STAMP_MESH)
	assert_true(VisualMeasure.has_authored_mesh(emission), "hand-drawn")


func test_a_waived_piece_is_composed_without_a_mesh_visual() -> void:
	var piece: Dictionary = {"kind": "Entity", "footprint": [1, 1]}
	var names: Array = SpecComposition.components(piece).map(
		func(e: Dictionary) -> String: return e["name"])
	assert_true(names.has(VisualMeasure.MESH_VISUAL_PATH), "default-on")
	piece.merge(WAIVED)
	names = SpecComposition.components(piece).map(
		func(e: Dictionary) -> String: return e["name"])
	assert_false(names.has(VisualMeasure.MESH_VISUAL_PATH), "the waiver removes the node itself")


func test_a_tracer_beam_is_in_flight_art() -> void:
	var emission: Node3D = Node3D.new()
	autofree(emission)
	var beam: MeshInstance3D = MeshInstance3D.new()
	beam.name = VisualMeasure.BEAM_MESH_NODE
	emission.add_child(beam)
	assert_false(VisualMeasure.has_tracer_beam(emission), "a beam nothing draws is not one")
	var tracer: Tracer = Tracer.new()
	tracer.name = VisualMeasure.TRACER_NODE
	emission.add_child(tracer)
	assert_true(VisualMeasure.has_tracer_beam(emission))
	assert_true(VisualMeasure.has_authored_mesh(emission), "a traced bullet has art")


func test_only_a_drawing_particle_effect_fills_the_impact_state() -> void:
	var emission: Node3D = Node3D.new()
	autofree(emission)
	var effect: Node3D = Node3D.new()
	effect.name = VisualMeasure.POST_IMPACT_PARTICLES_NODE
	emission.add_child(effect)
	var particles: GPUParticles3D = GPUParticles3D.new()
	effect.add_child(particles)
	assert_false(VisualMeasure.has_impact_effect(emission), "a particles node drawing nothing")
	particles.draw_pass_1 = QuadMesh.new()
	assert_true(VisualMeasure.has_impact_effect(emission), "an effect that draws")
