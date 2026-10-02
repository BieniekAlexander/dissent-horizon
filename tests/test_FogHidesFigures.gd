extends GutTest

## Fog hides every piece under it, beacons and emissions included, and a beam that crosses the
## fog edge is drawn only where it is in sight (piece-vocabulary.md §Where today's code
## disagrees). The fog here is a stub whose sight is everything west of FOG_EDGE_X, so the
## tests can put things on either side of a known edge.

const FOG_EDGE_X: float = 5.0
const VIEWER: int = 1
const OPPONENT: int = 2
const SAMPLE_STEP: float = 0.5


## Sees everything with x below FOG_EDGE_X. Inert otherwise (no Map), so its own per-frame pass
## never runs and each test drives the pass it is about.
class EdgeFog:
	extends Fog

	func fog_clear_at(a_world_xz: Vector2) -> bool:
		return a_world_xz.x < 5.0


var _saved_active_id: int


func before_each() -> void:
	Fog._fogs_by_commander.clear()
	_saved_active_id = Fog.active_commander_id
	Fog.active_commander_id = VIEWER


func after_each() -> void:
	Fog._fogs_by_commander.clear()
	Fog.active_commander_id = _saved_active_id


func _fog() -> EdgeFog:
	var fog: EdgeFog = EdgeFog.new()
	fog.watching_commander_id = VIEWER
	add_child_autofree(fog)
	return fog


func _commander(a_id: int) -> Commander:
	var commander: Commander = Commander.new()
	commander.id = a_id
	add_child_autofree(commander)
	return commander


## A bare figure in `a_group`, owned by `a_owner_id`, standing at x = `a_x`.
func _figure(a_group: StringName, a_owner_id: int, a_x: float) -> Entity:
	var figure: Entity = Entity.new()
	var ownership: Ownership = Ownership.new()
	ownership.name = "Ownership"
	figure.add_child(ownership)
	add_child_autofree(figure)
	figure.ownership.commander = _commander(a_owner_id)
	figure.add_to_group(a_group)
	figure.global_position = Vector3(a_x, 0.0, 0.0)
	return figure


#region Beacons and emissions are hidden like pieces
func test_an_opponents_emission_under_fog_is_hidden() -> void:
	var fog: EdgeFog = _fog()
	var shell: Entity = _figure(PhasedLocomotion.EMISSION_GROUP, OPPONENT, FOG_EDGE_X + 3.0)
	fog._apply_figure_visibility(VIEWER, false)
	assert_false(shell.visible, "a shell in the fog is not drawn")


func test_an_opponents_emission_shows_once_it_enters_sight() -> void:
	var fog: EdgeFog = _fog()
	var shell: Entity = _figure(PhasedLocomotion.EMISSION_GROUP, OPPONENT, FOG_EDGE_X + 3.0)
	fog._apply_figure_visibility(VIEWER, false)
	shell.global_position.x = FOG_EDGE_X - 1.0
	fog._apply_figure_visibility(VIEWER, false)
	assert_true(shell.visible, "it appears as it crosses into sight")


func test_an_opponents_beacon_under_fog_is_hidden() -> void:
	var fog: EdgeFog = _fog()
	var beacon: Entity = _figure(Beacon.GROUP, OPPONENT, FOG_EDGE_X + 3.0)
	fog._apply_figure_visibility(VIEWER, false)
	assert_false(beacon.visible)


func test_the_viewers_own_figures_are_never_hidden() -> void:
	var fog: EdgeFog = _fog()
	var shell: Entity = _figure(PhasedLocomotion.EMISSION_GROUP, VIEWER, FOG_EDGE_X + 3.0)
	var beacon: Entity = _figure(Beacon.GROUP, VIEWER, FOG_EDGE_X + 3.0)
	fog._apply_figure_visibility(VIEWER, false)
	assert_true(shell.visible, "the player always sees their own shots")
	assert_true(beacon.visible, "and their own beacons")


func test_the_omniscient_and_debug_views_show_everything() -> void:
	var fog: EdgeFog = _fog()
	var shell: Entity = _figure(PhasedLocomotion.EMISSION_GROUP, OPPONENT, FOG_EDGE_X + 3.0)
	fog._apply_figure_visibility(VIEWER, true)
	assert_true(shell.visible)


func test_a_fogged_beacon_is_not_visible_to_the_logic() -> void:
	# Hidden to the logic as well as the eye: the predicate every targeting path asks.
	_fog()
	var beacon: Entity = _figure(Beacon.GROUP, OPPONENT, FOG_EDGE_X + 3.0)
	assert_false(beacon.is_visible_to(VIEWER), "an opponent cannot act on a fogged beacon")
	beacon.global_position.x = FOG_EDGE_X - 1.0
	assert_true(beacon.is_visible_to(VIEWER), "and can once it is in sight")


#endregion


#region Clipping a beam at the fog edge
func _clear_west_of(a_x: float) -> Callable:
	return func(a_xz: Vector2) -> bool: return a_xz.x < a_x


func test_a_beam_with_no_fog_test_is_drawn_whole() -> void:
	var spans: Array[Vector2] = Tracer.visible_spans(
		Vector3.ZERO, Vector3(10, 0, 0), SAMPLE_STEP, Callable()
	)
	assert_eq(spans, [Vector2(0.0, 1.0)] as Array[Vector2])


func test_a_beam_entirely_in_fog_is_not_drawn() -> void:
	var spans: Array[Vector2] = Tracer.visible_spans(
		Vector3(6, 0, 0), Vector3(10, 0, 0), SAMPLE_STEP, _clear_west_of(FOG_EDGE_X)
	)
	assert_eq(spans.size(), 0)


func test_a_beam_crossing_the_edge_is_cut_off_there() -> void:
	# Fired from inside the fog at a target in sight: only the near-the-target half is drawn.
	var spans: Array[Vector2] = Tracer.visible_spans(
		Vector3(10, 0, 0), Vector3(0, 0, 0), SAMPLE_STEP, _clear_west_of(FOG_EDGE_X)
	)
	assert_eq(spans.size(), 1)
	assert_almost_eq(spans[0].x, 0.5, SAMPLE_STEP / 10.0, "it starts at the fog edge")
	assert_eq(spans[0].y, 1.0, "and runs to the target")


func test_a_fog_gap_splits_the_beam_in_two() -> void:
	var gap: Callable = func(a_xz: Vector2) -> bool: return a_xz.x < 3.0 or a_xz.x > 7.0
	var spans: Array[Vector2] = Tracer.visible_spans(
		Vector3.ZERO, Vector3(10, 0, 0), SAMPLE_STEP, gap
	)
	assert_eq(spans.size(), 2, "one stretch each side of the fogged middle")
	assert_eq(spans[0].x, 0.0)
	assert_eq(spans[1].y, 1.0)


func test_the_drawn_beam_survives_its_emission_being_hidden() -> void:
	# The fog hides a fogged emission's root; the part of its beam in sight must still draw.
	_fog()
	var emission: Entity = Entity.new()
	var ownership: Ownership = Ownership.new()
	ownership.name = "Ownership"
	emission.add_child(ownership)
	var template: MeshInstance3D = MeshInstance3D.new()
	template.name = "BeamMesh"
	template.mesh = CylinderMesh.new()
	emission.add_child(template)
	var tracer: Tracer = Tracer.new()
	tracer.name = "Tracer"
	emission.add_child(tracer)
	add_child_autofree(emission)
	emission.ownership.commander = _commander(OPPONENT)
	emission.global_position = Vector3(10, 0, 0)
	tracer.start(Vector3(10, 0, 0), Vector3.ZERO, true)
	emission.visible = false
	var drawn: Array = tracer.get_children().filter(
		func(c: Node) -> bool: return c is MeshInstance3D and (c as MeshInstance3D).visible
	)
	assert_eq(drawn.size(), 1, "one segment for the one stretch in sight")
	assert_true(
		(drawn[0] as MeshInstance3D).is_visible_in_tree(),
		"a segment under the tracer is not hidden with the emission"
	)
	assert_false(template.visible, "the authored mesh is only the template")
#endregion
