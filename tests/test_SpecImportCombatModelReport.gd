extends GutTest

## THE IMPORTER REPORTS WHAT THE COMBAT MODEL DOES NOT KNOW (ImportPipeline.combat_model_lines):
## the armed units the shipped model was never fitted on, and the types it knows that are no
## longer armed units — reported where the pieces are fixed, never an error. Pure functions over
## a registry-shaped dictionary and a model-shaped one (tools/spec_import/README.md §Summary).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gexit \
##       -gtest=res://tests/test_SpecImportCombatModelReport.gd


## A registry with just the field the report reads.
class FakeRegistry:
	extends RefCounted
	var specs: Dictionary = {}


func _registry() -> FakeRegistry:
	var registry := FakeRegistry.new()
	registry.specs = {
		"x_rifle": {"movement": {}, "weapons": [{"name": "Gun"}], "cost": {"energy": 100}},
		"x_tank": {"movement": {}, "weapons": [{"name": "Cannon"}], "cost": {"energy": 500}},
		"x_truck": {"movement": {}, "weapons": [], "cost": {"energy": 300}},
		"x_turret": {"weapons": [{"name": "Gun"}], "cost": {"energy": 200}},
		"x_free": {"movement": {}, "weapons": [{"name": "Gun"}], "cost": {"energy": 0}},
	}
	return registry


func test_an_armed_unit_moves_carries_a_weapon_and_costs_energy() -> void:
	assert_eq(ImportPipeline.armed_unit_ids(_registry()), ["x_rifle", "x_tank"])


func test_a_model_that_knows_every_armed_unit_reports_nothing() -> void:
	var lines: Array[String] = ImportPipeline.combat_model_lines(
		["x_rifle", "x_tank"], {"types": ["x_rifle", "x_tank"], "trained": "2026-10-09"}
	)
	assert_eq(lines, [] as Array[String])


func test_unknown_armed_units_are_named_with_the_models_date_by_faction() -> void:
	var lines: Array[String] = ImportPipeline.combat_model_lines(
		["x_rifle", "x_tank", "x_sleeper", "y_hover"],
		{"types": ["x_rifle", "x_tank"], "trained": "2026-10-09"},
		["x_"]
	)
	assert_eq(lines.size(), 3)
	assert_true(lines[0].contains("trained 2026-10-09"), lines[0])
	assert_true(lines[0].contains("2 armed unit"), lines[0])
	assert_true(lines[1].begins_with("      x_ ×1 — x_sleeper"), lines[1])
	assert_true(lines[1].contains("regenerate.sh"), "a pooled faction is regenerated: " + lines[1])
	assert_true(lines[2].begins_with("      y_ ×1 — y_hover"), lines[2])
	assert_true(lines[2].contains("not in the fight generator's pool"), lines[2])


func test_with_no_pool_named_every_faction_reads_as_pooled() -> void:
	var lines: Array[String] = ImportPipeline.combat_model_lines(
		["y_hover"], {"types": [], "trained": "2026-10-09"}
	)
	assert_true(lines[1].contains("regenerate.sh"), lines[1])


func test_types_the_model_knows_that_are_no_longer_armed_units_are_named() -> void:
	var lines: Array[String] = ImportPipeline.combat_model_lines(
		["x_rifle"], {"types": ["x_rifle", "x_retired"], "trained": "2026-10-09"}
	)
	assert_eq(lines.size(), 1)
	assert_true(lines[0].contains("no longer armed units: x_retired"), lines[0])


func test_no_model_at_all_is_reported_once() -> void:
	var lines: Array[String] = ImportPipeline.combat_model_lines(["x_rifle"], {})
	assert_eq(lines.size(), 1)
	assert_true(lines[0].contains("no combat model"), lines[0])
