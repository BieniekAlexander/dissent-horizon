extends GutTest

## Every authored speed NAMES a class of the one `kind: SpeedLibrary` doc
## (gdd/movement/speed_classes.md), which is the source of truth for the number. Pinned here:
## the registry swaps the name for its value in all three places a speed is written, refuses a
## bare number and an unknown name, and refuses a malformed or second ladder.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gtest=res://tests/test_SpeedLibrary.gd -gdir=res://tests/none -gexit

## Preloaded rather than reached through class_name: a headless run does not refresh the
## global class cache. Same reason as test_SpecGenerators.
const SpecRegistry := preload("res://tools/spec_import/spec_registry.gd")

const LADDER: Dictionary = {
	"kind": "SpeedLibrary", "title": "Speeds", "speeds": {"ZERO": 0, "CRAWL": 1.25, "DART": 20}
}


func _registry(a_docs: Dictionary, a_ladder: Variant = LADDER) -> RefCounted:
	var docs: Array = []
	if a_ladder != null:
		docs.append({"path": "res://gdd/x/speed_classes.md", "data": a_ladder})
	for id: String in a_docs:
		docs.append({"path": "res://gdd/x/%s.md" % id, "data": a_docs[id]})
	var registry: RefCounted = SpecRegistry.new()
	registry.build(docs)
	return registry


func _assert_refused(a_registry: RefCounted, a_fragment: String) -> void:
	assert_true(
		a_registry.errors.any(func(e: String) -> bool: return e.contains(a_fragment)),
		"refused with '%s': %s" % [a_fragment, a_registry.errors]
	)


func test_a_movement_speed_resolves_to_its_class_value() -> void:
	var registry: RefCounted = _registry(
		{"runner": {"kind": "Entity", "movement": {"speed": "CRAWL"}}}
	)
	assert_eq(registry.errors, [])
	assert_eq(registry.pieces["runner"]["movement"]["speed"], 1.25)


func test_zero_is_a_class_like_any_other() -> void:
	var registry: RefCounted = _registry(
		{"post": {"kind": "Entity", "movement": {"speed": "ZERO"}}}
	)
	assert_eq(registry.errors, [])
	assert_eq(registry.pieces["post"]["movement"]["speed"], 0.0)


func test_an_emission_shorthand_speed_resolves() -> void:
	var registry: RefCounted = _registry(
		{
			"round":
			{
				"kind": "Entity",
				"damage": 5,
				"damage_type": "LEAD",
				"speed": "DART",
				"trajectory": "LINEAR"
			}
		}
	)
	assert_eq(registry.errors, [])
	assert_eq(registry.projectiles["round"]["speed"], 20.0)


func test_a_phase_motion_speed_resolves() -> void:
	var registry: RefCounted = _registry(
		{
			"lob":
			{
				"kind": "Entity",
				"damage": 5,
				"damage_type": "LEAD",
				"phases":
				[
					{"motion": {"preset": "BALLISTIC", "speed": "CRAWL"}},
					{"lifespan": 0, "payload": "once"}
				]
			}
		}
	)
	assert_eq(registry.errors, [])
	assert_eq(registry.projectiles["lob"]["phases"][0]["motion"]["speed"], 1.25)


func test_an_inline_emission_speed_resolves() -> void:
	var registry: RefCounted = _registry(
		{
			"gunner":
			{
				"kind": "Entity",
				"movement": {"speed": "CRAWL"},
				"weapons":
				[
					{
						"name": "Gun",
						"reach": 1,
						"emits":
						{
							"id": "gunner_round",
							"damage": 5,
							"damage_type": "LEAD",
							"speed": "DART",
							"trajectory": "LINEAR"
						}
					}
				]
			}
		}
	)
	assert_true(registry.projectiles.has("gunner_round"), "the inline emission was hoisted")
	assert_eq(registry.projectiles["gunner_round"]["speed"], 20.0)


func test_a_bare_number_is_refused() -> void:
	_assert_refused(
		_registry({"runner": {"kind": "Entity", "movement": {"speed": 1.25}}}),
		"movement.speed must NAME a speed class"
	)
	_assert_refused(
		_registry(
			{
				"round":
				{
					"kind": "Entity",
					"damage": 5,
					"damage_type": "LEAD",
					"speed": 20,
					"trajectory": "LINEAR"
				}
			}
		),
		"speed must NAME a speed class"
	)


func test_an_unknown_class_is_refused() -> void:
	_assert_refused(
		_registry({"runner": {"kind": "Entity", "movement": {"speed": "WARP"}}}),
		"movement.speed 'WARP' is not a speed class"
	)


func test_a_speed_with_no_ladder_is_refused() -> void:
	_assert_refused(
		_registry({"runner": {"kind": "Entity", "movement": {"speed": "CRAWL"}}}, null),
		"is not a speed class"
	)


func test_the_ladder_is_one_doc() -> void:
	var registry: RefCounted = SpecRegistry.new()
	registry.build(
		[
			{"path": "res://gdd/x/speed_classes.md", "data": LADDER},
			{"path": "res://gdd/y/more_speeds.md", "data": LADDER}
		]
	)
	_assert_refused(registry, "a second SpeedLibrary")


func test_a_malformed_ladder_is_refused() -> void:
	_assert_refused(
		_registry({}, {"kind": "SpeedLibrary", "speeds": {"crawl": 1}}), "must be UPPER_SNAKE"
	)
	_assert_refused(
		_registry({}, {"kind": "SpeedLibrary", "speeds": {"BACK": -1}}), "non-negative number"
	)
	_assert_refused(
		_registry({}, {"kind": "SpeedLibrary", "speeds": {}}), "a SpeedLibrary needs speeds:"
	)
	_assert_refused(
		_registry({}, {"kind": "SpeedLibrary", "speeds": {"A": 1}, "ratio": 2}),
		"unknown SpeedLibrary key 'ratio'"
	)
