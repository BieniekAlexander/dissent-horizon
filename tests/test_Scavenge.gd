extends GutTest

## SCAVENGING — a destroyed grounded vehicle leaves a wreck, and an infantry unit carrying a
## scavenged weapon strips it to switch to that weapon for good.
##
## Three halves, tested separately because they fail differently:
##   * the LOADOUT — which weapons are live before and after a scavenge;
##   * the INTERACTION — which targets Interaction.Type.SCAVENGE accepts, and what completing
##     it does to the wreck and the unit;
##   * the WRECK — which pieces leave one, and how it is put into play.
## Rules: gdd/systems/combat/scavenging.md.
##
## Run with:
##   godot --headless --fixed-fps 30 -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Scavenge.gd -gexit

const OWNER: int = 1
const ENEMY: int = 2
const NEUTRAL: int = 0

## An infantryman whose gun has a faster-reloading scavenged form, and the interaction to get it.
const SCAVENGER: Dictionary = {
	"speed": 2.0,
	"weapon": {"ground": 6.0, "reload_ticks": 24, "scavenged": {"reload_ticks": 12}},
	"interactions": [Interaction.Type.SCAVENGE],
}
## The same infantryman with nothing to scavenge for.
const PLAIN_SOLDIER: Dictionary = {
	"speed": 2.0, "weapon": {"ground": 6.0}, "interactions": [Interaction.Type.SCAVENGE]
}
const VEHICLE: Dictionary = {"speed": 2.0, "frame": Defense.FrameType.MECH}
const INFANTRY: Dictionary = {"speed": 2.0}
const AIRCRAFT: Dictionary = {"aerial": true, "frame": Defense.FrameType.MECH}
const MECH_STRUCTURE: Dictionary = {"structure": true, "frame": Defense.FrameType.MECH}


## Answers what placing a token asks of its map; nothing here is registered on a grid.
class StubMap:
	extends Map

	func terrain_height_at(_a_world_xz: Vector2) -> float:
		return 0.0

	func nearest_navmesh_point(a_point: Vector3) -> Vector3:
		return a_point

	func _fixture_extent_at(_a_world_xz: Vector2) -> float:
		return 0.0


func _commanded(a_id: int) -> Commander:
	var commander := Commander.new()
	commander.id = a_id
	add_child_autofree(commander)
	return commander


func _unit(a_options: Dictionary, a_commander_id: int) -> Actor:
	var unit := FakePieces.make(a_options) as Actor
	add_child_autofree(unit)
	unit.ownership.commander = _commanded(a_commander_id)
	return unit


## A wreck token: an Entity carrying a Wreck facet, as nt_wreck's scene does.
func _wreck_piece(a_lifespan: float = 30.0) -> Entity:
	var piece := Entity.new()
	piece.name = "FakeWreck"
	piece.id = &"fake_wreck"
	var ownership := Ownership.new()
	ownership.name = "Ownership"
	piece.add_child(ownership)
	var facet := Wreck.new()
	facet.name = "Wreck"
	facet.lifespan_seconds = a_lifespan
	piece.add_child(facet)
	return piece


func _wreck() -> Entity:
	var piece: Entity = _wreck_piece()
	add_child_autofree(piece)
	piece.ownership.commander = _commanded(NEUTRAL)
	return piece


func _message_for(a_target: Entity) -> CommandMessage:
	return CommandMessage.new(null, a_target)


func _applies(a_actor: Actor, a_target: Entity) -> bool:
	return a_actor.interactor.can_interact(a_actor, _message_for(a_target))


func _weapon_names(a_actor: Actor) -> Array:
	return a_actor.weapon_inventory.get_weapons().map(func(w: Weapon) -> String: return w.name)


## --- The loadout ------------------------------------------------------------


func test_only_the_ordinary_weapon_is_live_before_a_scavenge() -> void:
	var soldier := _unit(SCAVENGER, OWNER)
	assert_eq(_weapon_names(soldier), ["Weapon"])
	assert_eq(soldier.weapon_inventory.all_weapons().size(), 2, "both weapons are carried")


func test_a_scavenge_replaces_the_ordinary_weapon_with_the_scavenged_one() -> void:
	var soldier := _unit(SCAVENGER, OWNER)
	soldier.weapon_inventory.scavenge()
	assert_true(soldier.weapon_inventory.is_scavenged)
	assert_eq(_weapon_names(soldier), ["ScavengedWeapon"])
	assert_eq(
		(soldier.weapon_inventory.get_weapons()[0] as Weapon).reload_time_ticks,
		12,
		"the live weapon is the scavenged one's own, not a modified copy of the first"
	)


func test_the_scavenged_weapon_is_the_one_that_answers_for_a_target() -> void:
	var soldier := _unit(SCAVENGER, OWNER)
	var target := _unit(INFANTRY, ENEMY)
	soldier.weapon_inventory.scavenge()
	var weapon: Weapon = soldier.weapon_inventory.weapon_for_target(target)
	assert_true(weapon == null or weapon.scavenged, "never the retired ordinary weapon")


func test_a_loadout_can_be_scavenged_once() -> void:
	var soldier := _unit(SCAVENGER, OWNER)
	assert_true(soldier.weapon_inventory.can_scavenge())
	soldier.weapon_inventory.scavenge()
	assert_false(soldier.weapon_inventory.can_scavenge(), "already upgraded")


func test_a_loadout_with_no_scavenged_weapon_cannot_be_scavenged() -> void:
	var soldier := _unit(PLAIN_SOLDIER, OWNER)
	assert_false(soldier.weapon_inventory.can_scavenge())
	soldier.weapon_inventory.scavenge()
	assert_eq(_weapon_names(soldier), ["Weapon"], "nothing changes")


## --- Applicability ----------------------------------------------------------


func test_applies_to_a_wreck() -> void:
	assert_true(_applies(_unit(SCAVENGER, OWNER), _wreck()))


func test_does_not_apply_to_a_unit_with_nothing_to_scavenge_for() -> void:
	assert_false(_applies(_unit(PLAIN_SOLDIER, OWNER), _wreck()))


func test_does_not_apply_once_the_unit_has_scavenged() -> void:
	# A unit already upgraded must not use up a wreck for nothing.
	var soldier := _unit(SCAVENGER, OWNER)
	soldier.weapon_inventory.scavenge()
	assert_false(_applies(soldier, _wreck()))


func test_does_not_apply_to_anything_but_a_wreck() -> void:
	assert_false(_applies(_unit(SCAVENGER, OWNER), _unit(VEHICLE, ENEMY)))


func test_does_not_apply_to_a_consumed_wreck() -> void:
	var wreck := _wreck()
	Wreck.of(wreck).consume()
	assert_false(_applies(_unit(SCAVENGER, OWNER), wreck))


func test_taking_damage_pauses_it() -> void:
	var interaction := Interaction.new()
	interaction.type = Interaction.Type.SCAVENGE
	assert_true(interaction.blocks_while_staggered())


## --- Completion -------------------------------------------------------------


## Run the interaction for `a_ticks` ticks (or to completion), returning whether it ended.
func _run(a_actor: Actor, a_target: Entity, a_ticks: int) -> bool:
	var command := Interact.new(_message_for(a_target))
	for i in a_ticks:
		if command.fulfill_action(a_actor) == null:
			return true
	return false


func _scavenger_taking(a_seconds: float) -> Actor:
	var soldier := _unit(SCAVENGER, OWNER)
	soldier.interactor.interactions[0].duration = a_seconds
	return soldier


func test_completing_it_upgrades_the_unit_and_consumes_the_wreck() -> void:
	var soldier := _scavenger_taking(3.0)
	var wreck := _wreck()
	assert_true(_run(soldier, wreck, TimeUtils.ticks_from_seconds(3.0) + 2), "it finished")
	assert_true(soldier.weapon_inventory.is_scavenged, "the unit switched weapons")
	assert_false(Wreck.of(wreck).is_available(), "the wreck is used up")
	assert_true(wreck.is_queued_for_deletion(), "and leaves play")


func test_nothing_happens_before_the_full_duration() -> void:
	var soldier := _scavenger_taking(3.0)
	var wreck := _wreck()
	assert_false(_run(soldier, wreck, TimeUtils.ticks_from_seconds(3.0) - 2), "still working")
	assert_false(soldier.weapon_inventory.is_scavenged)
	assert_true(Wreck.of(wreck).is_available())


func test_one_wreck_upgrades_one_unit() -> void:
	var first := _scavenger_taking(3.0)
	var second := _scavenger_taking(3.0)
	var wreck := _wreck()
	_run(first, wreck, TimeUtils.ticks_from_seconds(3.0) + 2)
	assert_false(_applies(second, wreck), "the second scavenger finds nothing left")


## --- Which pieces leave a wreck ---------------------------------------------


func test_a_grounded_vehicle_leaves_a_wreck() -> void:
	assert_true(Wreck.leaves_wreck(_unit(VEHICLE, ENEMY)))


func test_infantry_leaves_nothing() -> void:
	assert_false(Wreck.leaves_wreck(_unit(INFANTRY, ENEMY)))


func test_an_aircraft_leaves_nothing() -> void:
	assert_false(Wreck.leaves_wreck(_unit(AIRCRAFT, ENEMY)))


func test_a_structure_leaves_nothing() -> void:
	assert_false(Wreck.leaves_wreck(_unit(MECH_STRUCTURE, ENEMY)))


## --- Putting a wreck into play ----------------------------------------------


func test_a_wreck_is_placed_where_the_vehicle_stood_under_its_owner() -> void:
	var map := StubMap.new()
	autofree(map)
	var vehicle := _unit(VEHICLE, ENEMY)
	vehicle.map = map
	vehicle.global_position = Vector3(3.0, 0.0, 4.0)
	var scene := PackedScene.new()
	var template: Entity = _wreck_piece(12.0)
	for child: Node in template.get_children():
		child.owner = template
	scene.pack(template)
	template.free()
	var neutral := _commanded(NEUTRAL)

	var wreck: Entity = Wreck.place(vehicle, neutral, scene)
	assert_not_null(wreck)
	autofree(wreck)
	assert_almost_eq(wreck.position, Vector3(3.0, 0.0, 4.0), Vector3.ONE * 0.01)
	assert_eq(wreck.commander, neutral, "owned by the world")
	var lifespan := wreck.get_node_or_null("Lifespan") as Lifespan
	assert_not_null(lifespan, "it stands for a fixed time")
	assert_eq(lifespan.lifespan_seconds, 12.0, "the time its own Wreck names")
