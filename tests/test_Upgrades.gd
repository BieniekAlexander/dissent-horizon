extends GutTest

## UPGRADES: one-time, commander-wide research at a structure
## (gdd/systems/macroeconomics/upgrades.md).
##
## Three halves, each against fixtures rather than the shipped Advanced Targetting doc:
##   * the importer — a `kind: Upgrade` doc, `researches:` on a structure, and what they generate;
##   * the purchase — research runs as a job in the global queue, completes by granting the
##     upgrade (nothing spawns), and cannot be bought twice;
##   * the effect — UpgradeCatalog.range_for and the Spot reach it raises.
##
## Run with:
## godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Upgrades.gd
## -gdir=res://tests/none -gexit

const UPGRADE: StringName = &"fake_upgrade"
const SPOTTER: StringName = &"fake_spotter"

var _saved_entries: Dictionary
var _commander: Commander


func before_each() -> void:
	_saved_entries = UpgradeCatalog._entries.duplicate(true)
	UpgradeCatalog._entries[UPGRADE] = {
		"title": "Fake Upgrade",
		"modifies": [{"piece": String(SPOTTER), "ability": String(Spot.ABILITY_ID), "range": 24.0}],
	}
	FakePieces.install_ability(Spot.ABILITY_ID, {"range": 10.0, "command": "command_spot"})
	_commander = Commander.new()
	_commander.id = 1
	add_child_autofree(_commander)


func after_each() -> void:
	UpgradeCatalog._entries = _saved_entries
	FakePieces.restore_abilities()


## A piece owned by the fixture commander, with the given FakePieces options.
func _owned(a_options: Dictionary, a_id: StringName = &"") -> Commandable:
	var piece: Commandable = FakePieces.make(a_options)
	_commander.add_child(piece)
	autofree(piece)
	piece.ownership.commander = _commander
	if a_id != &"":
		piece.id = a_id
	return piece


func _research_purchase(a_producer: Commandable, a_energy: int = 100) -> PurchaseTransaction:
	var tool := Tool.new(
		"command_tool_%s" % UPGRADE, UPGRADE, null, "Fake Upgrade", Vector2i.ZERO, 0, 0
	)
	tool.is_upgrade = true
	var transaction := PurchaseTransaction.for_cost(
		_commander, PurchaseTransaction.Kind.TRAIN, tool, a_energy
	)
	transaction.creation_time = 3
	transaction.dispatch_filter.assign([a_producer])
	return transaction


func _tick(a_producer: Commandable, a_times: int) -> void:
	for _i: int in a_times:
		a_producer.production.tick()


# --- The effect -----------------------------------------------------------------


func test_an_unowned_upgrade_leaves_the_reach_at_the_ability_docs_range() -> void:
	var spotter: Commandable = _owned({"abilities": [{"grants": [Spot.ABILITY_ID]}]}, SPOTTER)
	assert_almost_eq(Spot.target_range(spotter), 10.0, 0.001)


func test_an_owned_upgrade_raises_the_reach_of_existing_units() -> void:
	var spotter: Commandable = _owned({"abilities": [{"grants": [Spot.ABILITY_ID]}]}, SPOTTER)
	_commander.complete_upgrade(UPGRADE)
	assert_almost_eq(
		Spot.target_range(spotter),
		24.0,
		0.001,
		"a unit already on the field reads the upgraded reach — no per-unit state"
	)


func test_an_upgrade_modifies_only_the_piece_it_names() -> void:
	var other: Commandable = _owned({"abilities": [{"grants": [Spot.ABILITY_ID]}]}, &"someone_else")
	_commander.complete_upgrade(UPGRADE)
	assert_almost_eq(Spot.target_range(other), 10.0, 0.001)


func test_an_upgrade_belongs_to_its_commander() -> void:
	var spotter: Commandable = _owned({"abilities": [{"grants": [Spot.ABILITY_ID]}]}, SPOTTER)
	var rival := Commander.new()
	rival.id = 2
	add_child_autofree(rival)
	rival.complete_upgrade(UPGRADE)
	assert_almost_eq(Spot.target_range(spotter), 10.0, 0.001)


func test_the_longest_reach_wins_whatever_order_upgrades_arrive_in() -> void:
	UpgradeCatalog._entries[&"fake_short"] = {
		"modifies": [{"piece": String(SPOTTER), "ability": String(Spot.ABILITY_ID), "range": 15.0}]
	}
	var spotter: Commandable = _owned({"abilities": [{"grants": [Spot.ABILITY_ID]}]}, SPOTTER)
	_commander.complete_upgrade(UPGRADE)
	_commander.complete_upgrade(&"fake_short")
	assert_almost_eq(Spot.target_range(spotter), 24.0, 0.001)


# --- Ownership ------------------------------------------------------------------


func test_completing_an_upgrade_is_idempotent_and_announced_once() -> void:
	watch_signals(_commander)
	_commander.complete_upgrade(UPGRADE)
	_commander.complete_upgrade(UPGRADE)
	assert_true(_commander.has_upgrade(UPGRADE))
	assert_signal_emit_count(_commander, "upgrade_researched", 1)


# --- The purchase ---------------------------------------------------------------


func test_research_runs_as_a_job_and_grants_the_upgrade_instead_of_spawning() -> void:
	var lab: Commandable = _owned({"structure": true, "produces": [UPGRADE]})
	_commander.energy = 100
	var transaction := _commander.production_queue.submit(_research_purchase(lab))
	assert_true(lab.production.is_producing(UPGRADE), "the research is the lab's job")
	var before: int = _commander.get_children().size()
	_tick(lab, 3)
	assert_true(_commander.has_upgrade(UPGRADE))
	assert_eq(transaction.state, PurchaseTransaction.State.COMPLETED)
	assert_eq(_commander.get_children().size(), before, "nothing was spawned")


func test_an_upgrade_being_researched_cannot_be_bought_again() -> void:
	var lab: Commandable = _owned({"structure": true, "produces": [UPGRADE]})
	_commander.energy = 1000
	_commander.technology_mapping[UPGRADE] = TechnologySpec.new(100, 0, 0, 3)
	assert_false(_commander.is_research_taken(UPGRADE))
	_commander.production_queue.submit(_research_purchase(lab))
	assert_true(_commander.is_research_taken(UPGRADE), "running on the lab")
	assert_eq(_commander.get_unmet_need(UPGRADE), TechnologySpec.UnmetNeed.ALREADY_RESEARCHED)


func test_a_queued_research_cannot_be_bought_again() -> void:
	var lab: Commandable = _owned({"structure": true, "produces": [UPGRADE]})
	# Unaffordable, so the purchase waits in the queue rather than reaching the lab.
	_commander.energy = 0
	_commander.production_queue.submit(_research_purchase(lab, 100))
	assert_false(lab.production.is_producing(UPGRADE))
	assert_true(_commander.is_research_taken(UPGRADE), "waiting in the queue")


func test_an_owned_upgrade_cannot_be_bought_again() -> void:
	_commander.technology_mapping[UPGRADE] = TechnologySpec.new(100, 0, 0, 3)
	_commander.energy = 1000
	_commander.complete_upgrade(UPGRADE)
	assert_eq(_commander.get_unmet_need(UPGRADE), TechnologySpec.UnmetNeed.ALREADY_RESEARCHED)


func test_a_piece_is_never_refused_as_already_researched() -> void:
	assert_false(_commander.is_research_taken(&"fake_piece_not_an_upgrade"))


func test_a_standing_research_is_demoted_to_a_one_off() -> void:
	var lab: Commandable = _owned({"structure": true, "produces": [UPGRADE]})
	var purchase := _research_purchase(lab)
	purchase.standing = true
	_commander.production_queue.submit(purchase)
	assert_false(purchase.standing, "an upgrade is bought once, so there is nothing to repeat")


func test_the_upgrade_survives_losing_the_lab() -> void:
	var lab: Commandable = _owned({"structure": true, "produces": [UPGRADE]})
	_commander.energy = 100
	_commander.production_queue.submit(_research_purchase(lab))
	_tick(lab, 3)
	lab.free()
	assert_true(_commander.has_upgrade(UPGRADE))


func test_a_research_only_structure_is_not_a_unit_producer() -> void:
	var lab: Commandable = _owned({"structure": true, "produces": [UPGRADE]})
	assert_false(lab.production.trains_units())
	assert_false(Production.node_trains_units(lab))
	assert_false(lab.can_rally(), "research spawns nothing, so there is nowhere to rally to")


func test_a_structure_that_also_trains_is_a_unit_producer() -> void:
	var yard: Commandable = _owned({"structure": true, "produces": [UPGRADE, &"fake_trainee"]})
	assert_true(yard.production.trains_units())
	assert_true(yard.can_rally())


# --- The importer ---------------------------------------------------------------


func _doc(a_path: String, a_data: Dictionary) -> Dictionary:
	return {"path": a_path, "data": a_data}


## A lab that researches `a_upgrade`, a spotter granted `spot`, the spot ability and a shape.
func _registry(a_upgrade: Dictionary, a_lab_extra: Dictionary = {}) -> RefCounted:
	var lab: Dictionary = {
		"kind": "Entity",
		"title": "Lab",
		"footprint": [2, 2],
		"researches": ["fake_upgrade"],
		"ui": {"grid": [0, 0]}
	}
	lab.merge(a_lab_extra, true)
	var r: RefCounted = SpecRegistry.new()
	(
		r
		. build(
			[
				_doc(
					"res://gdd/x/shapes.md",
					{
						"kind": "ShapeLibrary",
						"title": "Shapes",
						"shapes": {"far_reach": {"radius": 24}}
					}
				),
				_doc(
					"res://gdd/x/spot.md",
					{"kind": "AbilityDefinition", "title": "Spot", "range": 10}
				),
				_doc(
					"res://gdd/x/fake_spotter.md",
					{
						"kind": "Entity",
						"title": "Spotter",
						"movement": {"speed": 2.0},
						"abilities": [{"grants": ["spot"]}]
					}
				),
				_doc("res://gdd/x/fake_lab.md", lab),
				_doc("res://gdd/x/fake_upgrade.md", a_upgrade),
			]
		)
	)
	return r


func _upgrade_doc(a_extra: Dictionary = {}) -> Dictionary:
	var doc: Dictionary = {
		"kind": "Upgrade",
		"title": "Fake Upgrade",
		"build": {"cost": {"energy": 800}, "time": 45},
		"modifies": [{"piece": "fake_spotter", "ability": "spot", "range": "far_reach"}],
		"ui": {"grid": [0, 1]}
	}
	doc.merge(a_extra, true)
	return doc


func _errors_mentioning(a_registry: RefCounted, a_text: String) -> Array:
	return a_registry.errors.filter(func(e: String) -> bool: return e.contains(a_text))


func test_a_well_formed_upgrade_imports_clean() -> void:
	var r: RefCounted = _registry(_upgrade_doc())
	assert_eq(_errors_mentioning(r, "fake_upgrade"), [])
	assert_true(r.upgrades.has("fake_upgrade"))


func test_a_modifier_range_is_resolved_to_the_shapes_radius() -> void:
	var r: RefCounted = _registry(_upgrade_doc())
	var json: Variant = JSON.parse_string(SpecGenerators.upgrades_json(r))
	assert_almost_eq(float(json["fake_upgrade"]["modifies"][0]["range"]), 24.0, 0.001)


func test_an_upgrade_is_priced_and_offered_like_a_trainee() -> void:
	var r: RefCounted = _registry(_upgrade_doc())
	var tech: Dictionary = JSON.parse_string(SpecGenerators.technology_json(r))
	assert_eq(int(tech["fake_upgrade"]["cost"]["energy"]), 800)
	var tool: Dictionary = SpecGenerators.tools_table(r)["command_tool_fake_upgrade"]
	assert_true(bool(tool["upgrade"]))
	assert_eq(tool["context"], "TRAIN")
	assert_eq(tool["producers"], ["fake_lab"])


func test_an_upgrade_that_modifies_nothing_is_refused() -> void:
	var doc: Dictionary = _upgrade_doc()
	doc.erase("modifies")
	assert_eq(_errors_mentioning(_registry(doc), "needs a modifies:").size(), 1)


func test_a_modifier_on_a_piece_not_granted_the_ability_is_refused() -> void:
	var doc: Dictionary = _upgrade_doc(
		{"modifies": [{"piece": "fake_lab", "ability": "spot", "range": "far_reach"}]}
	)
	assert_eq(_errors_mentioning(_registry(doc), "is not granted 'spot'").size(), 1)


func test_an_unknown_upgrade_key_is_refused() -> void:
	assert_eq(
		(
			_errors_mentioning(
				_registry(_upgrade_doc({"footprint": [2, 2]})), "may not carry `footprint:`"
			)
			. size()
		),
		1
	)


func test_researches_must_name_an_upgrade() -> void:
	var r: RefCounted = _registry(_upgrade_doc(), {"researches": ["fake_spotter"]})
	assert_eq(_errors_mentioning(r, "references unknown upgrade 'fake_spotter'").size(), 1)


## An upgrade whose one modifier is `a_modifier`.
func _modifier_doc(a_modifier: Dictionary) -> Dictionary:
	return _upgrade_doc({"modifies": [a_modifier]})


func test_factor_modifiers_import_clean_and_are_generated_as_numbers() -> void:
	var r: RefCounted = _registry(
		_upgrade_doc(
			{
				"modifies":
				[
					{"frame": "BIO", "hp_factor": 1.25},
					{"piece": "fake_spotter", "ability": "spot", "cooldown_rate_factor": 1.3},
				]
			}
		)
	)
	assert_eq(_errors_mentioning(r, "fake_upgrade"), [])
	var modifies: Array = (
		JSON.parse_string(SpecGenerators.upgrades_json(r))["fake_upgrade"]["modifies"]
	)
	assert_eq(modifies[0], {"frame": "BIO", "hp_factor": 1.25})
	assert_almost_eq(float(modifies[1]["cooldown_rate_factor"]), 1.3, 0.001)


func test_a_modifier_with_two_effects_is_refused() -> void:
	var doc: Dictionary = _modifier_doc(
		{"piece": "fake_spotter", "hp_factor": 1.25, "rearm_rate_factor": 2.0}
	)
	assert_eq(_errors_mentioning(_registry(doc), "exactly one effect").size(), 1)


func test_a_modifier_needs_exactly_one_selector() -> void:
	var doc: Dictionary = _modifier_doc(
		{"piece": "fake_spotter", "frame": "BIO", "hp_factor": 1.25}
	)
	assert_eq(_errors_mentioning(_registry(doc), "exactly one of").size(), 1)


func test_an_unknown_frame_is_refused() -> void:
	var doc: Dictionary = _modifier_doc({"frame": "SILICON", "hp_factor": 1.25})
	assert_eq(_errors_mentioning(_registry(doc), "frame must be one of").size(), 1)


func test_a_hit_point_factor_refuses_an_ability() -> void:
	var doc: Dictionary = _modifier_doc(
		{"piece": "fake_spotter", "ability": "spot", "hp_factor": 1.25}
	)
	assert_eq(_errors_mentioning(_registry(doc), "hp_factor is not about an ability").size(), 1)


func test_a_recharge_factor_needs_an_ability() -> void:
	var doc: Dictionary = _modifier_doc({"piece": "fake_spotter", "cooldown_rate_factor": 1.3})
	assert_eq(_errors_mentioning(_registry(doc), "cooldown_rate_factor needs an ability").size(), 1)


func test_a_rearm_factor_on_a_piece_without_a_charged_weapon_is_refused() -> void:
	var doc: Dictionary = _modifier_doc({"piece": "fake_spotter", "rearm_rate_factor": 2.0})
	assert_eq(_errors_mentioning(_registry(doc), "never rearms").size(), 1)


func test_a_factor_must_be_positive() -> void:
	var doc: Dictionary = _modifier_doc({"frame": "BIO", "hp_factor": 0})
	assert_eq(_errors_mentioning(_registry(doc), "must be a positive number").size(), 1)
