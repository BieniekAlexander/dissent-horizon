extends GutTest

## Preloaded (not via class_name) so the test runs even when the global class cache has
## not rescanned — headless runs do not refresh it. Same reason as test_TscnDoc.
const SpecGenerators := preload("res://tools/spec_import/generators.gd")
const SpecRegistry := preload("res://tools/spec_import/spec_registry.gd")

## WHAT THE IMPORTER DOES ABOUT AN ID THAT LEFT THE DOCS.
##
## `entity_ids.gd` is REBUILT from the registry on every run rather than accumulated, so a
## piece whose doc is deleted stops being emitted on its own. That is the removal behaviour
## the docs promise — and by itself it is completely silent, which is the problem these
## tests exist for: a dropped const is a PARSE error in every file still naming it, and an
## unparseable test file is dropped from the GUT run while the run still reports green
## (CLAUDE.md §A skipped test file is invisible). `tc_barracks`, `tc_lab`, `tc_armory` and
## `kamikaze` left four files broken exactly that way, two of them tests.
##
## So the rebuild is tested (removal happens) and `pending_removals` is tested (removal is
## SAID). The registries here are synthetic — these are rules about the generator, not
## assertions about the shipped roster (CLAUDE.md §A unit test does not assert facts about
## authored content).

const SCRATCH: String = "user://test_spec_generators_ids.gd"


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


## A registry carrying just the ids named — enough for the id generators, which read only
## `pieces` / `status_effects`.
func _registry(a_piece_ids: Array, a_effect_ids: Array = []) -> SpecRegistry:
	var registry := SpecRegistry.new()
	for id: String in a_piece_ids:
		registry.pieces[id] = {"id": id, "_kind": "piece"}
	for id: String in a_effect_ids:
		registry.status_effects[id] = {"id": id, "_kind": "status_effect"}
	return registry


func _write(a_text: String) -> void:
	var f: FileAccess = FileAccess.open(SCRATCH, FileAccess.WRITE)
	assert_not_null(f, "scratch file opens")
	f.store_string(a_text)
	f.close()


#region The rebuild itself
func test_the_enum_is_rebuilt_from_the_registry_so_a_deleted_piece_is_dropped() -> void:
	# The whole removal mechanism: nothing carries an id forward, so an id is present iff a
	# doc defines it. Two registries, one text each.
	var before: String = SpecGenerators.entity_ids_text(_registry(["tc_barracks", "an_barracks"]))
	var after: String = SpecGenerators.entity_ids_text(_registry(["an_barracks"]))
	assert_string_contains(before, 'const TC_BARRACKS := &"tc_barracks"')
	assert_false(after.contains("TC_BARRACKS"), "the deleted piece is gone from the rebuild")
	assert_string_contains(after, 'const AN_BARRACKS := &"an_barracks"')


func test_ids_are_emitted_alphabetically() -> void:
	var text: String = SpecGenerators.entity_ids_text(_registry(["zz_last", "aa_first"]))
	assert_lt(text.find("AA_FIRST"), text.find("ZZ_LAST"), "alphabetical, per the header")


#endregion


#region Reading back what a generated file declares
func test_declared_ids_reads_the_consts_out_of_a_generated_file() -> void:
	_write(SpecGenerators.entity_ids_text(_registry(["an_barracks", "tc_lab"])))
	var declared: Dictionary = SpecGenerators.declared_ids(SCRATCH)
	assert_eq(declared.size(), 2)
	assert_eq(declared.get("tc_lab"), "TC_LAB", "id maps to the const name code references")


func test_declared_ids_of_a_missing_file_is_empty() -> void:
	# A first run has nothing to compare against and must therefore remove nothing.
	assert_eq(SpecGenerators.declared_ids("user://no_such_generated_file.gd"), {})


#endregion


#region Reporting the removal
func test_removal_for_names_the_ids_a_run_would_drop() -> void:
	_write(
		SpecGenerators.entity_ids_text(
			_registry(["an_barracks", "tc_armory", "tc_barracks", "tc_lab"])
		)
	)
	var removal: Dictionary = SpecGenerators.removal_for(
		SCRATCH, "EntityIds", {"an_barracks": true}
	)
	assert_eq(removal["ids"], ["tc_armory", "tc_barracks", "tc_lab"], "sorted, and only the dead")
	assert_eq(
		removal["consts"],
		["TC_ARMORY", "TC_BARRACKS", "TC_LAB"],
		"reported as the CONST names, because that is what hand-written code names"
	)
	assert_eq(removal["scope"], "EntityIds")
	assert_eq(removal["path"], SCRATCH)


func test_a_file_that_loses_nothing_reports_nothing() -> void:
	# An ordinary import must stay quiet, or the line stops being read.
	_write(SpecGenerators.entity_ids_text(_registry(["an_barracks"])))
	assert_eq(
		SpecGenerators.removal_for(
			SCRATCH, "EntityIds", {"an_barracks": true, "an_new_piece": true}
		),
		{},
		"an ADDED piece is not a removal"
	)


func test_the_comparison_is_against_the_file_on_disk() -> void:
	# The file on disk is what hand-written code last compiled against, and that is what a
	# removal breaks — so the diff is against the file, not against some earlier registry.
	_write('class_name EntityIds\nconst HAND_EDITED := &"hand_edited"\n')
	assert_eq(SpecGenerators.removal_for(SCRATCH, "EntityIds", {})["consts"], ["HAND_EDITED"])


#endregion


#region The wiring, against the real generated files
## Proves pending_removals actually reads ID_FILES and the registry collections named there,
## which removal_for on a scratch path cannot show. The roster is taken FROM the generated
## file rather than asserted, so this pins the plumbing and not the content.
func test_pending_removals_is_empty_when_the_registry_still_defines_everything() -> void:
	var registry: SpecRegistry = _registry_matching_the_generated_ids()
	assert_eq(
		SpecGenerators.pending_removals(registry),
		[],
		"a registry holding exactly what the file declares removes nothing"
	)


func test_pending_removals_reports_a_piece_taken_out_of_the_registry() -> void:
	var registry: SpecRegistry = _registry_matching_the_generated_ids()
	var ids: Array = registry.pieces.keys()
	ids.sort()
	var dropped: String = str(ids[0])
	registry.pieces.erase(dropped)

	var removals: Array = SpecGenerators.pending_removals(registry)
	assert_eq(removals.size(), 1, "exactly the one id file lost a constant")
	assert_eq(removals[0]["scope"], "EntityIds")
	assert_eq(removals[0]["path"], SpecGenerators.ENTITY_IDS_PATH)
	assert_eq(removals[0]["ids"], [dropped])


## A registry whose pieces / status effects are exactly what the generated files declare
## today — whatever that is.
func _registry_matching_the_generated_ids() -> SpecRegistry:
	var pieces: Dictionary = SpecGenerators.declared_ids(SpecGenerators.ENTITY_IDS_PATH)
	var effects: Dictionary = SpecGenerators.declared_ids(SpecGenerators.STATUS_EFFECT_IDS_PATH)
	assert_false(pieces.is_empty(), "the generated entity ids file was read")
	return _registry(pieces.keys(), effects.keys())


#endregion

#region The grid review
## WHY THE IMPORT REFUSES A SHARED CELL. The HUD draws only the first button a cell holds
## and hides the rest, so two pieces authored into one cell leave one of them unreachable
## with nothing on screen to say why. These pin the review to the separators
## ControlBinding.grid_collisions already defines — faction, context and producer — against
## synthetic docs, never the shipped roster.


## A piece carrying just what the tool table reads: a cell, a faction, and optionally a
## footprint (which makes it BUILT unless something trains it) and a `trains:` list.
func _piece(a_id: String, a_grid: Array, a_faction: String, a_extra: Dictionary = {}) -> Dictionary:
	var spec: Dictionary = {
		"id": a_id,
		"_kind": "piece",
		"_doc_path": "res://gdd/%s.md" % a_id,
		"ui": {"grid": a_grid, "factions": [a_faction]}
	}
	spec.merge(a_extra, true)
	return spec


func _grid_registry(a_specs: Array) -> SpecRegistry:
	var registry := SpecRegistry.new()
	for spec: Dictionary in a_specs:
		registry.pieces[spec["id"]] = spec
	return registry


func test_two_buildings_of_one_faction_in_one_cell_are_refused_naming_both_docs() -> void:
	var collisions: Array = (
		SpecGenerators
		. grid_collisions(
			_grid_registry(
				[
					_piece("lb_relay", [0, 2], "libertarian", {"footprint": [5, 5]}),
					_piece("lb_opticon", [0, 2], "libertarian", {"footprint": [1, 1]}),
				]
			)
		)
	)
	assert_eq(collisions.size(), 1, "one shared cell, one report")
	assert_string_contains(collisions[0], "res://gdd/lb_relay.md")
	assert_string_contains(collisions[0], "res://gdd/lb_opticon.md")


func test_a_piece_with_no_scene_yet_is_still_reviewed() -> void:
	# The scene sync gives a new doc its scene AFTER validation; its button exists from then on.
	var registry: SpecRegistry = _grid_registry(
		[
			_piece(
				"lb_relay", [0, 2], "libertarian", {"footprint": [5, 5], "scene": "res://x.tscn"}
			),
			_piece("lb_opticon", [0, 2], "libertarian", {"footprint": [1, 1]}),
		]
	)
	assert_eq(SpecGenerators.grid_collisions(registry).size(), 1)


func test_different_factions_may_share_a_cell() -> void:
	assert_eq(
		(
			SpecGenerators
			. grid_collisions(
				_grid_registry(
					[
						_piece("lb_relay", [0, 2], "libertarian", {"footprint": [5, 5]}),
						_piece("cl_citadel", [0, 2], "colonial", {"footprint": [5, 5]}),
					]
				)
			)
		),
		[]
	)


func test_units_trained_by_different_producers_may_share_a_cell() -> void:
	assert_eq(
		(
			SpecGenerators
			. grid_collisions(
				_grid_registry(
					[
						_piece(
							"lb_barracks",
							[1, 0],
							"libertarian",
							{"footprint": [3, 3], "trains": ["lb_rifle"]}
						),
						_piece(
							"lb_airfield",
							[2, 0],
							"libertarian",
							{"footprint": [3, 3], "trains": ["lb_jet"]}
						),
						_piece("lb_rifle", [0, 1], "libertarian"),
						_piece("lb_jet", [0, 1], "libertarian"),
					]
				)
			)
		),
		[]
	)


func test_units_trained_by_one_producer_may_not_share_a_cell() -> void:
	assert_eq(
		(
			SpecGenerators
			. grid_collisions(
				_grid_registry(
					[
						_piece(
							"lb_barracks",
							[1, 0],
							"libertarian",
							{"footprint": [3, 3], "trains": ["lb_rifle", "lb_medic"]}
						),
						_piece("lb_rifle", [0, 1], "libertarian"),
						_piece("lb_medic", [0, 1], "libertarian"),
					]
				)
			)
			. size()
		),
		1
	)


func test_a_trained_unit_may_not_sit_on_its_producers_context_button() -> void:
	# Row 0 of the PRODUCTION card holds the producer radio buttons (ui.context_grid).
	var collisions: Array = (
		SpecGenerators
		. grid_collisions(
			_grid_registry(
				[
					_piece(
						"lb_barracks",
						[1, 0],
						"libertarian",
						{
							"footprint": [3, 3],
							"trains": ["lb_rifle"],
							"ui":
							{"grid": [1, 0], "factions": ["libertarian"], "context_grid": [1, 0]}
						}
					),
					_piece("lb_rifle", [1, 0], "libertarian"),
				]
			)
		)
	)
	assert_eq(collisions.size(), 1)
	assert_string_contains(collisions[0], "ui.context_grid")


func test_a_building_and_a_unit_never_collide() -> void:
	# BUILD and TRAIN are different contexts on different cards.
	assert_eq(
		(
			SpecGenerators
			. grid_collisions(
				_grid_registry(
					[
						_piece(
							"lb_barracks",
							[0, 1],
							"libertarian",
							{"footprint": [3, 3], "trains": ["lb_rifle"]}
						),
						_piece("lb_rifle", [0, 1], "libertarian"),
					]
				)
			)
		),
		[]
	)
#endregion
