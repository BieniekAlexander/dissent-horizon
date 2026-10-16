extends GutTest

## Burning: a damage-over-time that takes hold on FIXTURES only, and a heal puts it out. Also
## the host filter itself, through the cryo burst that takes the other half. Rules:
## gdd/systems/combat/environmental-pieces.md §Hazards.
##
## Scenes are loaded inside the tests, never preloaded at file scope (CLAUDE.md).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gtest=res://tests/test_BurningStatusEffect.gd -gexit

const BURNING_SCENE: String = "res://scenes/entities/status_effects/burning.tscn"
const CRYO_BURST_SCENE: String = "res://scenes/entities/status_effects/cryo_burst.tscn"
const HP: float = 100.0


func _effect(a_scene: String) -> StatusEffect:
	return (load(a_scene) as PackedScene).instantiate() as StatusEffect


func _piece(a_options: Dictionary) -> Actor:
	var piece := FakePieces.make(a_options) as Actor
	add_child_autofree(piece)
	return piece


func _effects_on(a_piece: Node) -> Array:
	return a_piece.get_children().filter(
		func(c: Node) -> bool: return c is StatusEffect and (c as StatusEffect).is_active()
	)


func _tick(a_effect: StatusEffect, a_count: int) -> void:
	for _i: int in a_count:
		a_effect.simulation_step(0.0)


func test_burning_takes_hold_on_a_fixture() -> void:
	var building: Actor = _piece({"structure": true, "hp": HP})
	_effect(BURNING_SCENE).apply_to(building)
	assert_eq(_effects_on(building).size(), 1)


func test_burning_is_refused_on_a_figure() -> void:
	var soldier: Actor = _piece({"speed": 2.0, "hp": HP})
	var effect: StatusEffect = _effect(BURNING_SCENE)
	effect.apply_to(soldier)
	assert_eq(_effects_on(soldier).size(), 0)
	assert_true(effect.is_queued_for_deletion(), "the refused duplicate is freed")


func test_burning_deals_its_damage_on_its_cadence() -> void:
	var building: Actor = _piece({"structure": true, "hp": HP})
	var effect := _effect(BURNING_SCENE) as DamageOverTimeStatusEffect
	effect.apply_to(building)
	_tick(effect, effect.tick_rate - 1)
	assert_eq(building.defense.hp, HP, "not before the first cadence")
	_tick(effect, 1)
	assert_lt(building.defense.hp, HP, "and then it burns")


func test_a_heal_puts_the_fire_out() -> void:
	var building: Actor = _piece({"structure": true, "hp": HP})
	_effect(BURNING_SCENE).apply_to(building)
	# A whole building, so the heal restores nothing and only sheds: a hit would have staggered
	# it, and a staggered piece cannot be mended (Defense.restore).
	building.defense.restore(1.0)
	assert_eq(_effects_on(building).size(), 0, "repair sheds a burning")


func test_the_cryo_burst_takes_hold_on_a_figure_and_not_a_fixture() -> void:
	var soldier: Actor = _piece({"speed": 2.0, "hp": HP})
	var building: Actor = _piece({"structure": true, "hp": HP})
	_effect(CRYO_BURST_SCENE).apply_to(soldier)
	_effect(CRYO_BURST_SCENE).apply_to(building)
	assert_eq(_effects_on(soldier).size(), 1, "a unit in the cloud freezes")
	assert_eq(_effects_on(building).size(), 0, "a structure shrugs it off")
