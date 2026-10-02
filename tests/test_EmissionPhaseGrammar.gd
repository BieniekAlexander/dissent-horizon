extends GutTest

## The doc grammar for an emission's phases — `phases:` and the flat shorthand that stands for
## the common two-phase shape — on dictionaries, the way the importer reads a doc. See
## gdd/systems/combat/projectiles.md §Phases.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gtest=res://tests/test_EmissionPhaseGrammar.gd -gdir=res://tests/none -gexit

## Preloaded rather than reached through class_name: a headless run does not refresh the
## global class cache. Same reason as test_SpecGenerators.
const EmissionPhases := preload("res://tools/spec_import/emission_phases.gd")


func test_the_shorthand_is_a_flight_then_a_one_tick_impact() -> void:
	var phases: Array[Dictionary] = EmissionPhases.expand({"speed": 9, "trajectory": "BALLISTIC"})
	assert_eq(phases.size(), 2)
	assert_eq(phases[0]["name"], "Flight")
	assert_eq(phases[0]["speed"], 9.0)
	assert_eq(phases[0]["gravity_mps2"], EmissionPhase.BALLISTIC_GRAVITY_MPS2, "the preset")
	assert_true(phases[0]["ends_on_arrival"], "a moving phase arrives")
	assert_false(phases[0]["applies_payload"], "a flight applies nothing")
	assert_true(is_inf(phases[0]["lifespan_seconds"]), "no lifespan")
	assert_eq(phases[1]["name"], "Impact")
	assert_false(phases[1]["ends_on_arrival"], "a phase without motion never arrives")
	assert_eq(phases[1]["lifespan_seconds"], 0.0, "one tick")
	assert_true(phases[1]["applies_payload"])
	assert_true(is_inf(phases[1]["payload_period_seconds"]), "once")


func test_the_shorthand_defaults_to_the_old_default_trajectory() -> void:
	var phases: Array[Dictionary] = EmissionPhases.expand({"speed": 5})
	assert_eq(phases[0]["gravity_mps2"], EmissionPhase.BALLISTIC_GRAVITY_MPS2)


func test_an_explicit_motion_overrides_its_preset() -> void:
	var phases: Array[Dictionary] = (
		EmissionPhases
		. expand(
			{
				"phases":
				[
					{"motion": {"preset": "HOMING", "speed": 24, "turn_rate": 30}, "lifespan": 2},
				]
			}
		)
	)
	assert_eq(phases[0]["turn_rate_degrees_per_second"], 30.0, "overridden")
	assert_eq(phases[0]["launch_speed_ratio"], 0.5, "the rest of the preset kept")
	assert_eq(phases[0]["lifespan_seconds"], 2.0)


func test_a_phase_item_carries_every_clause() -> void:
	var phases: Array[Dictionary] = (
		EmissionPhases
		. expand(
			{
				"phases":
				[
					{
						"name": "Sweep",
						"motion": {"speed": 10},
						"ends_on_arrival": false,
						"lifespan": 1.5,
						"impact_mask": ["terrain", "structures"],
						"payload": 0.2,
						"emits": {"id": "toxin_cloud", "every": 1},
						"visuals": ["BeamMesh"]
					},
				]
			}
		)
	)
	var sweep: Dictionary = phases[0]
	assert_eq(sweep["name"], "Sweep")
	assert_false(sweep["ends_on_arrival"])
	assert_eq(
		sweep["impact_mask"], CollisionLayers.Mask.TERRAIN | CollisionLayers.Mask.STRUCTURE_BLOCKER
	)
	assert_eq(sweep["payload_period_seconds"], 0.2)
	assert_eq(sweep["emits"], "toxin_cloud")
	assert_eq(sweep["event_period_seconds"], 1.0)
	assert_eq(sweep["visual_roles"], ["BeamMesh"])


func test_later_phases_show_the_post_impact_visuals_by_default() -> void:
	var phases: Array[Dictionary] = EmissionPhases.expand(
		{"phases": [{"motion": "LINEAR"}, {"lifespan": 1, "payload": "once"}, {"lifespan": 3}]}
	)
	assert_eq(phases[0]["visual_roles"], EmissionPhases.IN_FLIGHT_VISUALS)
	assert_eq(phases[1]["visual_roles"], EmissionPhases.POST_IMPACT_VISUALS)
	assert_eq(phases[2]["name"], "Phase2", "named by position past the two defaults")


func test_a_valid_doc_has_no_errors() -> void:
	assert_eq(EmissionPhases.errors_for({"speed": 9, "trajectory": "LINEAR"}), [])
	assert_eq(
		EmissionPhases.errors_for(
			{
				"phases":
				[
					{"motion": {"preset": "HOMING", "speed": 9}, "lifespan": 5},
					{"lifespan": 1, "payload": "once"}
				]
			}
		),
		[]
	)


func _assert_refused(a_spec: Dictionary, a_fragment: String) -> void:
	var errors: Array[String] = EmissionPhases.errors_for(a_spec)
	assert_true(
		errors.any(func(e: String) -> bool: return e.contains(a_fragment)),
		"refused with '%s': %s" % [a_fragment, errors]
	)


func test_flat_motion_beside_phases_is_refused() -> void:
	_assert_refused({"speed": 9, "phases": [{"motion": "LINEAR"}]}, "beside phases")


func test_a_steered_flight_without_a_lifespan_is_refused() -> void:
	_assert_refused({"phases": [{"motion": "HOMING"}]}, "needs a lifespan")
	_assert_refused({"trajectory": "HOMING", "speed": 9}, "needs a lifespan")


func test_a_pitch_without_gravity_is_refused() -> void:
	_assert_refused({"phases": [{"motion": {"launch_pitch": 45}}]}, "without gravity")


func test_unknown_names_are_refused() -> void:
	_assert_refused({"trajectory": "SPIRAL"}, "SPIRAL")
	_assert_refused({"phases": [{"motion": "SPIRAL"}]}, "not a preset")
	_assert_refused({"phases": [{"wobble": 1}]}, "unknown key")
	_assert_refused({"phases": [{"motion": {"wobble": 1}}]}, "unknown motion key")
	_assert_refused({"phases": [{"impact_mask": ["water"]}]}, "water")


func test_bad_values_are_refused() -> void:
	_assert_refused({"phases": []}, "non-empty")
	_assert_refused({"phases": [{"lifespan": -1}]}, "lifespan")
	_assert_refused({"phases": [{"payload": "often"}]}, "payload")
	_assert_refused({"phases": [{"emits": {"every": 1}}]}, "needs an id")


func test_a_motion_may_ask_for_jitter() -> void:
	var spec: Dictionary = {
		"phases":
		[
			{"motion": {"preset": "LINEAR", "speed": 15, "jitter": 0.1, "jitter_frequency": 2}},
			{"lifespan": 1, "payload": "once"}
		]
	}
	assert_eq(EmissionPhases.errors_for(spec), [])
	var flight: Dictionary = EmissionPhases.expand(spec)[0]
	assert_eq(flight["jitter_degrees"], 0.1)
	assert_eq(flight["jitter_frequency_hz"], 2.0)
