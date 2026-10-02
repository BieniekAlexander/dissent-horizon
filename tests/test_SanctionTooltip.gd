extends GutTest

## Tests for the sanction bar's hover tooltips, sourced from Sanction.description.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_SanctionTooltip.gd -gexit

const ANARCHICAL: PackedScene = preload("res://scenes/factions/anarchical.tscn")
const COLONIAL: PackedScene = preload("res://scenes/factions/colonial.tscn")


func _sanction(a_description: String) -> Sanction:
	var sanction := Sanction.new()
	sanction.sanction_name = "Test Sanction"
	sanction.description = a_description
	return sanction


# --- The field ------------------------------------------------------------------


func test_description_defaults_to_blank() -> void:
	# An un-described sanction must degrade to "no tooltip", not to an empty popup.
	assert_eq(Sanction.new().description, "")


func test_description_survives_the_per_commander_duplicate() -> void:
	# SanctionGrid duplicates each Sanction so cooldowns are per-commander; authored
	# data has to come along or the tooltip would be blank for every actual player.
	var original := _sanction("Calls down a radiation field.")
	var copy: Sanction = original.duplicate()
	assert_eq(copy.description, "Calls down a radiation field.")


# --- The tooltip button ---------------------------------------------------------


## A button gets its copy before it joins the tree, the way every HUD builder does it
## (see ButtonSpec.create_button_from_spec) — _ready is the deadline, and reports a
## button that arrives undescribed.
func _described_button(a_text: String) -> VerboseTooltipButton:
	var button := VerboseTooltipButton.new()
	button.simple_tooltip = a_text
	add_child_autofree(button)
	return button


func test_the_button_shows_the_description_on_hover() -> void:
	var button := _described_button(_sanction("Drops three irregulars.").description)

	assert_eq(button._text_for(false), "Drops three irregulars.")


func test_a_blank_description_falls_back_to_the_missing_tooltip() -> void:
	# Every HUD button says something on hover: a blank tooltip is an authoring bug, so
	# it degrades to the visible TODO placeholder (and a push_error) rather than to a
	# button that silently explains nothing.
	var button := _described_button(_sanction("").description)

	assert_eq(button._text_for(false), VerboseTooltipButton.MISSING_TOOLTIP)
	assert_push_error_count(1, "the blank tooltip is reported, not swallowed")


func test_a_button_that_never_got_a_tooltip_is_caught_on_entering_the_tree() -> void:
	# The setter only fires on an explicit assignment; _ready is the backstop for a
	# button nobody described at all.
	var button := VerboseTooltipButton.new()
	add_child_autofree(button)

	assert_eq(button.simple_tooltip, VerboseTooltipButton.MISSING_TOOLTIP)
	assert_push_error_count(1, "entering the HUD undescribed is reported")


func test_the_verbose_variant_stays_optional() -> void:
	# Only the simple tooltip is mandatory: a button whose one line says everything has
	# nothing longer to show, and holding the verbose key just keeps that line.
	var button := _described_button("Drops three irregulars.")

	assert_eq(button.verbose_tooltip, "")
	assert_eq(button._text_for(true), "Drops three irregulars.")


func test_the_built_in_tooltip_stays_suppressed() -> void:
	# VerboseTooltipButton renders its own popup; leaving tooltip_text set would show
	# Godot's built-in one on top of it.
	var button := _described_button("Drops three irregulars.")
	assert_eq(button.tooltip_text, "", "_ready clears the built-in tooltip")


# --- The authored factions ------------------------------------------------------


func _descriptions_of(a_faction_scene: PackedScene) -> Dictionary:
	var faction: Node = a_faction_scene.instantiate()
	autofree(faction)
	var by_name: Dictionary = {}
	for unlock: SanctionUnlock in (faction as Faction).sanction_unlocks:
		if unlock != null and unlock.sanction != null:
			by_name[unlock.sanction.sanction_name] = unlock.sanction.description
	return by_name


func test_every_anarchical_sanction_is_described() -> void:
	var descriptions: Dictionary = _descriptions_of(ANARCHICAL)
	assert_gt(descriptions.size(), 0, "the faction authors some sanctions")
	for sanction_name: String in descriptions:
		assert_false(
			(descriptions[sanction_name] as String).is_empty(),
			"%s has a tooltip description" % sanction_name
		)


func test_every_colonial_sanction_is_described() -> void:
	var descriptions: Dictionary = _descriptions_of(COLONIAL)
	assert_gt(descriptions.size(), 0, "the faction authors some sanctions")
	for sanction_name: String in descriptions:
		assert_false(
			(descriptions[sanction_name] as String).is_empty(),
			"%s has a tooltip description" % sanction_name
		)
