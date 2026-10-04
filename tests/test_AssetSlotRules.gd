extends GutTest

## The ASSET severity of SpecRules: a slot a piece is expected to fill is reported with an
## AssetState when unfilled, never failed, and a doc waives it like a norm. Driven with bare
## spec dictionaries and hand-made facts, so no scene or sound table is read. See
## gdd/systems/ux/README.md §Asset slots.

## Preloaded rather than reached through class_name: a headless run does not refresh the
## global class cache. Same reason as test_VisualOptOut.
const SpecRules := preload("res://tools/spec_import/spec_rules.gd")
const ImportPipelineScript := preload("res://tools/spec_import/import_pipeline.gd")

const UNIT: Dictionary = {"movement": {"speed": 3.0}}
const STRUCTURE: Dictionary = {"footprint": [2, 2]}
const TOKEN: Dictionary = {
	"commandable": false, "movement": {"speed": 0.0}, "aerial": {"mode": "HOVERING"}
}
const VOICED: Dictionary = {"missing_line_types": [], "has_death_clip": true}
const MUTE: Dictionary = {
	"missing_line_types": ["SELECTED", "ISSUED_ATTACK"],
	"has_death_clip": false,
}


func _entries(a_spec: Dictionary, a_facts: Dictionary, a_rule: String) -> Array:
	return SpecRules.evaluate(a_spec, a_facts).filter(
		func(e: Dictionary) -> bool: return e["id"] == a_rule
	)


func _waived(a_spec: Dictionary, a_rule: String) -> Dictionary:
	var spec: Dictionary = a_spec.duplicate(true)
	spec["exceptions"] = {a_rule: "dies silently on purpose"}
	return spec


func test_an_unvoiced_unit_is_missing_and_names_the_lines() -> void:
	var entries: Array = _entries(UNIT, MUTE, "has_voice_lines")
	assert_eq(entries.size(), 1)
	assert_eq(entries[0]["verdict"], SpecRules.Verdict.INCOMPLETE)
	assert_eq(entries[0]["asset_state"], SpecRules.AssetState.MISSING)
	assert_string_contains(entries[0]["detail"], "SELECTED, ISSUED_ATTACK")


func test_a_voiced_unit_is_silent() -> void:
	assert_eq(
		SpecRules.evaluate(UNIT, VOICED).filter(
			func(e: Dictionary) -> bool: return e["severity"] == SpecRules.ASSET
		),
		[]
	)


func test_voice_lines_do_not_exist_on_structures_or_tokens() -> void:
	for spec: Dictionary in [STRUCTURE, TOKEN]:
		assert_eq(_entries(spec, MUTE, "has_voice_lines"), [], "no voice, no slot")


func test_every_piece_has_a_death_sound_slot() -> void:
	for spec: Dictionary in [UNIT, STRUCTURE, TOKEN]:
		var entries: Array = _entries(spec, MUTE, "has_death_sound")
		assert_eq(entries.size(), 1, "a structure's collapse is its death sound")
		assert_eq(entries[0]["asset_state"], SpecRules.AssetState.MISSING)


func test_a_waived_slot_is_exempt() -> void:
	var entries: Array = _entries(_waived(UNIT, "has_death_sound"), MUTE, "has_death_sound")
	assert_eq(entries[0]["verdict"], SpecRules.Verdict.EXCEPTIONAL)
	assert_eq(entries[0]["asset_state"], SpecRules.AssetState.EXEMPT)


func test_a_waiver_on_a_filled_slot_is_stale() -> void:
	var entries: Array = _entries(_waived(UNIT, "has_death_sound"), VOICED, "has_death_sound")
	assert_eq(entries[0]["verdict"], SpecRules.Verdict.STALE)


func test_a_waiver_on_a_slot_that_does_not_exist_is_stale() -> void:
	var entries: Array = _entries(_waived(STRUCTURE, "has_voice_lines"), MUTE, "has_voice_lines")
	assert_eq(entries[0]["verdict"], SpecRules.Verdict.STALE)


func test_an_asset_rule_without_its_fact_says_nothing() -> void:
	assert_eq(
		SpecRules.evaluate(UNIT, {}).filter(
			func(e: Dictionary) -> bool: return e["severity"] == SpecRules.ASSET
		),
		[]
	)


func test_an_asset_waiver_is_well_formed() -> void:
	assert_eq(SpecRules.validate_exceptions_block(_waived(UNIT, "has_voice_lines")), [])


func test_the_summary_groups_by_rule_and_state() -> void:
	var incomplete: Array = [
		{
			"id": "b",
			"rule": "has_voice_lines",
			"what": "w",
			"detail": "",
			"state": SpecRules.AssetState.MISSING
		},
		{
			"id": "a",
			"rule": "has_voice_lines",
			"what": "w",
			"detail": "",
			"state": SpecRules.AssetState.MISSING
		},
		{
			"id": "a",
			"rule": "has_mesh_visual",
			"what": "m",
			"detail": "",
			"state": SpecRules.AssetState.PLACEHOLDER
		},
	]
	var lines: Array[String] = ImportPipelineScript.incomplete_asset_lines(incomplete)
	assert_eq(lines.size(), 5, "a header, then two lines per group: %s" % [lines])
	assert_string_contains(lines[1], "has_mesh_visual (PLACEHOLDER) ×1")
	assert_string_contains(lines[3], "has_voice_lines (MISSING) ×2")
	assert_eq(ImportPipelineScript.incomplete_asset_lines([]), [] as Array[String])


func test_the_sound_tables_report_an_unlisted_unit_as_empty() -> void:
	var voice: Script = load("res://scripts/audio/control_feedback_sounds.gd")
	var death: Script = load("res://scripts/audio/entity_death_sounds.gd")
	assert_eq(voice.missing_line_types(&"no_such_piece").size(), 3, "every line type")
	assert_false(death.has_clip(&"no_such_piece"))


# --- The HUD icon ---------------------------------------------------------------------
## Two rules over one slot: no picture is MISSING, a stock photograph is a PLACEHOLDER. Both
## are asked only of Actors, the pieces the HUD draws on a button or a card.


func _icon(a_state: String) -> Dictionary:
	return {"hud_icon": a_state}


func test_an_actor_without_an_icon_is_missing() -> void:
	for spec: Dictionary in [UNIT, STRUCTURE]:
		var entries: Array = _entries(spec, _icon(SpecRules.HUD_ICON_MISSING), "has_hud_icon")
		assert_eq(entries.size(), 1)
		assert_eq(entries[0]["asset_state"], SpecRules.AssetState.MISSING)
		assert_eq(
			_entries(spec, _icon(SpecRules.HUD_ICON_MISSING), "hud_icon_is_final"),
			[],
			"an absent icon is reported once, as missing, not also as a placeholder"
		)


func test_a_stock_icon_is_a_placeholder() -> void:
	var facts: Dictionary = _icon(SpecRules.HUD_ICON_PLACEHOLDER)
	assert_eq(_entries(UNIT, facts, "has_hud_icon"), [], "it has a picture")
	var entries: Array = _entries(UNIT, facts, "hud_icon_is_final")
	assert_eq(entries.size(), 1)
	assert_eq(entries[0]["asset_state"], SpecRules.AssetState.PLACEHOLDER)


func test_a_final_icon_is_silent() -> void:
	var facts: Dictionary = _icon(SpecRules.HUD_ICON_FINAL)
	for rule: String in ["has_hud_icon", "hud_icon_is_final"]:
		assert_eq(_entries(STRUCTURE, facts, rule), [], rule)


func test_a_token_has_no_icon_slot() -> void:
	for rule: String in ["has_hud_icon", "hud_icon_is_final"]:
		assert_eq(_entries(TOKEN, _icon(SpecRules.HUD_ICON_MISSING), rule), [], rule)
