extends GutTest

## ATTACKABLE is its own facet: a target layer and a Defense, and nothing about being an Actor
## (gdd/systems/authoring/piece-vocabulary.md §Facets).
##
## Attack and aggro used to filter on `is Commandable`, so an uncommandable piece could only be
## made shootable by making it a Commandable it was not — which is exactly how the Recon Drone
## came to be one. The fixture here is the extraction site: a plain `Entity` with a TargetBody
## and a footprint, so it shows a ground target layer, and no Defense of its own.
##
## PATHS, not preloads — a file-scope preload of an entity scene poisons the Tool registry
## (CLAUDE.md §A file-scope `preload`…).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Attackable.gd -gexit

const SITE_SCENE: String = "res://scenes/entities/structures/nt/nt_extractionSite.tscn"


## The extraction site, optionally given a Defense before it enters the tree so the
## @onready that resolves `defense` sees it.
func _site(a_with_defense: bool) -> Entity:
	var site: Entity = (load(SITE_SCENE) as PackedScene).instantiate()
	if a_with_defense:
		var defense := Defense.new()
		defense.name = "Defense"
		site.add_child(defense)
	add_child_autofree(site)
	return site


func _attack_message(a_target: Entity) -> CommandMessage:
	return CommandMessage.new(null, a_target, null)


func test_the_fixture_is_not_an_actor_and_is_targetable() -> void:
	var site := _site(false)
	assert_false(site is Commandable, "the premise: an uncommandable piece")
	assert_ne(site.targetable_layers(), 0, "that a weapon could lock onto")


func test_a_target_layer_without_a_defense_is_not_attackable() -> void:
	var site := _site(false)
	assert_false(site.is_attackable())
	assert_false(Attack._target_attackable(_attack_message(site)))


func test_a_defense_makes_an_uncommandable_piece_attackable() -> void:
	var site := _site(true)
	assert_true(site.is_attackable())
	assert_true(Attack._target_attackable(_attack_message(site)),
		"Attack no longer asks whether the target takes orders")
