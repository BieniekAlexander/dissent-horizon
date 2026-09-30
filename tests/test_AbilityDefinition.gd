extends GutTest

## The ABILITY as a first-class thing: what a `kind: AbilityDefinition` doc says about it, what the
## generated catalog carries at runtime, and the keys the Bombards fold retired.
##
## The distinction being pinned here is the one the whole fold turns on:
##   * an ABILITY is what a piece can do — passive or active, with an optional per-use
##     emission and an authored HUD presence;
##   * an SANCTION is one UNLOCK ROUTE for one — dominion, through the sanction grid — and
##     nothing else. `bombard` is the worked example of an ability that is not one.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_AbilityDefinition.gd -gexit

const FACTION_SCENE: String = "res://scenes/factions/anarchical.tscn"


func _doc(a_path: String, a_data: Dictionary) -> Dictionary:
	return {"path": a_path, "data": a_data}


func _registry(a_docs: Array) -> RefCounted:
	var r: RefCounted = SpecRegistry.new()
	r.build(a_docs)
	return r


## The errors from a lone ability doc, with a piece beside it so `emits:` has something
## real to name.
func _errors_for(a_data: Dictionary) -> Array:
	return _registry([
		_doc("res://gdd/x/shell.md", {"kind": "Entity", "title": "Shell", "hitscan": true,
			"scene": "res://scenes/entities/projectiles/bullet.tscn"}),
		_doc("res://gdd/x/spot.md", a_data),
	]).errors


# --- The doc shape --------------------------------------------------------------

func test_an_ability_needs_no_unlock_route_at_all() -> void:
	# The whole point of the split: `column:`/`levels:` are the DOMINION route, and an
	# ability that is free (or bought at a structure) authors neither.
	assert_eq(_errors_for({"kind": "AbilityDefinition", "title": "Spot", "hud_button": true}), [])


func test_an_ability_can_carry_a_per_use_emission() -> void:
	assert_eq(_errors_for({"kind": "AbilityDefinition", "title": "Spot", "emits": "shell"}), [])


func test_an_emission_naming_nothing_is_a_hard_error() -> void:
	var errors: Array = _errors_for({"kind": "AbilityDefinition", "title": "Spot", "emits": "nope"})
	assert_eq(errors.size(), 1)
	assert_string_contains(errors[0], "emits names unknown piece 'nope'")


func test_a_scene_path_emission_must_exist() -> void:
	var errors: Array = _errors_for({
		"kind": "AbilityDefinition", "title": "Spot", "emits": "res://scenes/nope.tscn"})
	assert_eq(errors.size(), 1)
	assert_string_contains(errors[0], "does not exist")


func test_the_two_ability_flags_must_be_booleans() -> void:
	for flag: String in ["passive", "hud_button"]:
		var errors: Array = _errors_for({"kind": "AbilityDefinition", "title": "Spot", flag: "yes"})
		assert_eq(errors.size(), 1, flag)
		assert_string_contains(errors[0], "%s must be true or false" % flag)


func test_a_command_and_an_unlock_route_are_alternatives() -> void:
	# A dominion-unlocked ability is armed as whichever CELL is in play, so naming a
	# command as well would be a second arming path for one ability.
	var errors: Array = _errors_for({
		"kind": "AbilityDefinition", "title": "Spot", "command": "command_spot",
		"column": 0, "levels": [{"title": "Spot 1", "tier": 0}],
	})
	assert_eq(errors.size(), 1)
	assert_string_contains(errors[0], "alternatives")


func test_a_command_must_look_like_a_command_name() -> void:
	var errors: Array = _errors_for({"kind": "AbilityDefinition", "title": "Spot", "command": "spot"})
	assert_eq(errors.size(), 1)
	assert_string_contains(errors[0], "must be a command name")


# --- Passivity belongs to the ability, not to a cell ----------------------------

func test_passive_is_read_from_the_doc_not_from_a_level() -> void:
	assert_eq(_errors_for({
		"kind": "AbilityDefinition", "title": "Spot", "passive": true, "column": 0,
		"levels": [{"title": "Spot 1", "tier": 0, "kill_bounty": 0.1}],
	}), [], "a top-level passive is what a kill_bounty needs")


func test_a_passive_inside_a_level_is_refused() -> void:
	# Refused rather than read: Scavenge 2 is not more passive than Scavenge 1, and a doc
	# saying it twice could disagree with itself.
	var errors: Array = _errors_for({
		"kind": "AbilityDefinition", "title": "Spot", "column": 0,
		"levels": [{"title": "Spot 1", "tier": 0, "passive": true}],
	})
	assert_eq(errors.size(), 1)
	assert_string_contains(errors[0], "move it to the doc's top level")


# --- What the fold retired ------------------------------------------------------

func test_the_sanction_kind_is_retired() -> void:
	var errors: Array = _registry([
		_doc("res://gdd/x/spot.md", {"kind": "sanction", "title": "Spot", "column": 0,
			"levels": [{"title": "Spot 1", "tier": 0}]}),
	]).errors
	assert_eq(errors.size(), 1)
	assert_string_contains(errors[0], "use `kind: AbilityDefinition")


func test_the_bombards_key_is_retired() -> void:
	var errors: Array = _registry([
		_doc("res://gdd/x/gun.md", {"kind": "Entity", "title": "Gun", "footprint": [1, 1],
			"bombards": {"cooldown": 5}}),
	]).errors
	assert_eq(errors.size(), 1)
	assert_string_contains(errors[0], "abilities:")


func test_a_faction_cannot_sell_an_ability_with_no_cells() -> void:
	# `sanctions:` is the faction's dominion shop, so an ability with no sanction grid cells has
	# nothing to draw there.
	var errors: Array = _registry([
		_doc("res://gdd/x/spot.md", {"kind": "AbilityDefinition", "title": "Spot"}),
		_doc("res://gdd/x/an.md", {"kind": "Faction", "title": "A", "scene": FACTION_SCENE,
			"starts_with": [], "sanctions": ["spot"]}),
	]).errors
	assert_eq(errors.size(), 1)
	assert_string_contains(errors[0], "authors no levels:")


func test_a_faction_may_not_start_with_a_structure() -> void:
	# A command centre is dropped at the start of a match, so starts_with names units only.
	var errors: Array = _registry([
		_doc("res://gdd/x/hq.md", {"kind": "Entity", "title": "HQ", "footprint": [2, 2]}),
		_doc("res://gdd/x/an.md", {"kind": "Faction", "title": "A", "scene": FACTION_SCENE,
			"starts_with": ["hq"]}),
	]).errors
	assert_eq(errors.size(), 1)
	assert_string_contains(errors[0], "starts_with names the structure 'hq'")


# --- The generated catalog ------------------------------------------------------

func test_the_bombard_ability_is_free_and_wears_a_hud_button() -> void:
	assert_true(AbilityCatalog.has(Bombard.ABILITY_ID), "the bombard ability is defined")
	assert_false(AbilityCatalog.is_dominion_unlocked(Bombard.ABILITY_ID),
		"owning the gun is the whole unlock — no dominion is spent on it")
	assert_true(AbilityCatalog.has_hud_button(Bombard.ABILITY_ID),
		"and its reach is global, which is what earns a bar button")
	assert_false(AbilityCatalog.is_passive(Bombard.ABILITY_ID))
	assert_eq(AbilityCatalog.command_of(Bombard.ABILITY_ID), "command_bombard",
		"the bar arms the same grid command the card offers")


func test_the_bombard_ability_carries_its_shell() -> void:
	assert_not_null(AbilityCatalog.emission_of(Bombard.ABILITY_ID),
		"the per-use emission an ability may carry without becoming a sanction")


func test_the_scavenge_ability_is_passive_and_has_no_button() -> void:
	assert_true(AbilityCatalog.is_passive(&"scavenge"))
	assert_false(AbilityCatalog.has_hud_button(&"scavenge"),
		"a passive is never emitted through a command, so a button would do nothing")


func test_an_unknown_ability_degrades_rather_than_erroring() -> void:
	assert_false(AbilityCatalog.has(&"no_such_ability"))
	assert_false(AbilityCatalog.is_passive(&"no_such_ability"))
	assert_false(AbilityCatalog.has_hud_button(&"no_such_ability"))
	assert_null(AbilityCatalog.emission_of(&"no_such_ability"))


# --- The class an ability doc loads as ------------------------------------------

func test_an_empty_entry_is_an_unauthored_definition() -> void:
	var definition: AbilityDefinition = AbilityDefinition.from_entry(&"nothing", {})
	assert_eq(definition.title, "nothing", "an untitled ability reads as its id")
	assert_eq(definition.range_metres, AbilityDefinition.DEFAULT_RANGE)
	assert_eq(definition.cast_arity, MoveCommand.CastArity.SINGLE)
	assert_eq(definition.reveals, -1)
	assert_eq(definition.grid, AbilityDefinition.NO_CELL)
	assert_false(definition.is_passive)


func test_an_entry_parses_into_typed_fields() -> void:
	var definition: AbilityDefinition = AbilityDefinition.from_entry(&"spot", {
		"title": "Spot", "range": 12, "cast_by": "all", "grid": [2, 1],
		"levels": [{"title": "Spot 1"}, "junk"], "factions": ["colonial"],
	})
	assert_eq(definition.range_metres, 12.0)
	assert_eq(definition.cast_arity, MoveCommand.CastArity.ALL, "case-insensitive")
	assert_eq(definition.grid, Vector2i(2, 1))
	assert_eq(definition.levels.size(), 1, "a malformed level is dropped, not fatal")
	assert_eq(definition.faction_names, ["colonial"])


func test_the_catalog_answers_an_unknown_id_with_defaults() -> void:
	assert_false(AbilityCatalog.has(&"no_such_ability"))
	assert_eq(AbilityCatalog.title_of(&"no_such_ability"), "no_such_ability")
	assert_eq(AbilityCatalog.range_of(&"no_such_ability"), AbilityDefinition.DEFAULT_RANGE)
