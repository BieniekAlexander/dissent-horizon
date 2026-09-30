extends GutTest

## Tests for the Shelter → Terrestrial → liberation loop:
##   - Shelter: a spawn countdown that parks at capacity and resumes when a resident
##     is taken out of play.
##   - Terrestrial: a neutral unit with no weapons and no ability to build.
##   - Wander: the never-completing loiter command residents are issued.
##   - Liberator: the Warlord's passive conversion component.

const TERRESTRIAL: Dictionary = {"speed": 1.0, "liberatable": true}
const SHELTER: Dictionary = FakePieces.SHELTER
const WARLORD: Dictionary = {"speed": 2.0, "vision": 8.0, "liberator": true}

## --- Terrestrial ------------------------------------------------------------

func test_terrestrial_is_unarmed_and_cannot_build():
	var t: Node = FakePieces.make(TERRESTRIAL)
	add_child_autofree(t)
	assert_null(t.get_node_or_null("Loadout"), "terrestrials carry no weapons")
	assert_null(t.get_node_or_null("Builds"), "terrestrials cannot build")
	assert_false((t as Entity).is_armed(), "an unarmed unit reports is_armed() false")

## --- Shelter spawn timer ----------------------------------------------------
##
## The component is driven directly (calling _ready / _physics_process) against a
## stub host, so no Map or navmesh is stood up. With no terrestrial_scene the
## production step is a no-op, which is exactly what we want when asserting timing.

## A bare Entity carrying an Ownership child, standing in for the shelter structure.
## `map` is assigned so the component considers the host initialized.
func _stub_host() -> Entity:
	var host := Entity.new()
	var own := Ownership.new()
	own.name = "Ownership"
	host.add_child(own)
	add_child_autofree(host)
	host.map = autofree(Map.new())
	return host

func _shelter_on(a_host: Entity, a_interval: float, a_capacity: int = 3) -> Shelter:
	var s := Shelter.new()
	s.name = "Shelter"
	s.spawn_interval = a_interval
	s.capacity = a_capacity
	s.terrestrial_scene = null
	a_host.add_child(s)
	s._ready()
	return s

## A resident to register: a real terrestrial, left neutral (no commander assigned →
## commander id 0) so it matches the stub host's ownership.
func _stub_resident() -> Commandable:
	var r := FakePieces.make(TERRESTRIAL) as Commandable
	add_child_autofree(r)
	return r

func test_shelter_counts_down_and_resets_after_producing():
	var host := _stub_host()
	var s := _shelter_on(host, 2.0)
	assert_almost_eq(s._remaining, 2.0, 0.001, "starts at the full interval")
	s._physics_process(1.0)
	assert_almost_eq(s._remaining, 1.0, 0.001, "counts down")
	s._physics_process(1.5)  # overshoot
	assert_almost_eq(s._remaining, 2.0, 0.001, "resets to the interval after producing")

func test_shelter_timer_parks_at_capacity():
	var host := _stub_host()
	var s := _shelter_on(host, 10.0, 2)
	s.register(_stub_resident())
	s._physics_process(1.0)
	assert_almost_eq(s._remaining, 9.0, 0.001, "still ticking below capacity")
	s.register(_stub_resident())
	assert_true(s.is_full())
	s._physics_process(5.0)
	assert_almost_eq(s._remaining, 9.0, 0.001, "timer holds while at capacity")

func test_shelter_resumes_when_a_resident_leaves():
	var host := _stub_host()
	var s := _shelter_on(host, 10.0, 1)
	var resident := _stub_resident()
	s.register(resident)
	s._physics_process(1.0)
	assert_almost_eq(s._remaining, 10.0, 0.001, "parked")
	s.unregister(resident)
	assert_eq(s.resident_count(), 0)
	s._physics_process(1.0)
	assert_almost_eq(s._remaining, 9.0, 0.001, "ticking again once a slot frees up")

func test_shelter_unregisters_a_resident_that_leaves_the_tree():
	var host := _stub_host()
	var s := _shelter_on(host, 10.0)
	var resident := _stub_resident()
	s.register(resident)
	assert_eq(s.resident_count(), 1)
	# Abduction / liberation / death all take the unit out of the tree.
	resident.get_parent().remove_child(resident)
	assert_eq(s.resident_count(), 0, "leaving the tree frees the slot")
	resident.queue_free()

func test_shelter_registration_is_idempotent():
	var host := _stub_host()
	var s := _shelter_on(host, 10.0)
	var resident := _stub_resident()
	s.register(resident)
	s.register(resident)
	assert_eq(s.resident_count(), 1)

func test_shelter_scene_is_wired_to_the_terrestrial():
	var shelter: Node = FakePieces.make(SHELTER)
	add_child_autofree(shelter)
	var s := shelter.get_node_or_null("Shelter") as Shelter
	assert_not_null(s, "the shelter structure carries a Shelter component")
	assert_not_null(s.terrestrial_scene, "it knows what to produce")
	assert_gt(s.spawn_interval, 0.0, "it spawns on a timer")
	assert_gt(s.capacity, 0, "and sustains residents")

## --- Wander -----------------------------------------------------------------

func test_wander_never_completes():
	var msg := CommandMessage.new(null, null, null, Vector3(4.0, 0.0, 7.0))
	var w := Wander.new(msg)
	# fulfill_action is what runs on "arrival"; returning self keeps the command.
	assert_eq(w.fulfill_action(null), w, "an arrived wanderer holds its command")
	assert_true(w.should_move(null), "and is always willing to move again")

func test_wander_anchors_on_its_issue_position():
	var anchor := Vector3(4.0, 0.0, 7.0)
	var w := Wander.new(CommandMessage.new(null, null, null, anchor))
	assert_eq(w._anchor, anchor)

## --- Liberator --------------------------------------------------------------

func test_warlord_liberates_rather_than_interacting():
	var warlord: Node = FakePieces.make(WARLORD)
	add_child_autofree(warlord)
	assert_null(
		warlord.get_node_or_null("Interactor"),
		"the shelter LIBERATE interaction is gone"
	)
	var lib := warlord.get_node_or_null("Liberator") as Liberator
	assert_not_null(lib, "the warlord converts terrestrials on contact instead")
	assert_not_null(lib.converted_scene, "and mints something in their place")

## The reach query is capped at a result COUNT, and intersect_shape truncates BEFORE the
## caller filters — so a cap doubling as the conversion throttle drops candidates rather
## than deferring them. The two numbers must stay separate.
func test_liberator_query_cap_is_not_the_conversion_cap():
	assert_gt(
		Liberator.QUERY_LIMIT, Liberator.MAX_PER_TICK,
		"the query must return more than one tick's worth of conversions"
	)

## --- Liberatable ------------------------------------------------------------
##
## Eligibility lives entirely in the LIBERATABLE collision layer, so these assert the
## bit rather than a caller-side predicate: what is on the layer IS what converts.

func _is_on_liberation_layer(a_entity: Node) -> bool:
	var body := a_entity.get_node_or_null("TargetBody") as CollisionObject3D
	return body != null and (body.collision_layer & CollisionLayers.Mask.LIBERATABLE) != 0

func test_neutral_terrestrial_is_on_the_liberation_layer():
	var t: Node = FakePieces.make(TERRESTRIAL)
	add_child_autofree(t)
	assert_not_null(
		t.get_node_or_null("Liberatable"),
		"the terrestrial declares itself convertible"
	)
	assert_true(_is_on_liberation_layer(t), "and a neutral one is on the layer")

func test_ownership_takes_a_terrestrial_off_and_back_onto_the_layer():
	var t: Node = FakePieces.make(TERRESTRIAL)
	add_child_autofree(t)
	var cmd := Commander.new()
	cmd.id = 2
	add_child_autofree(cmd)

	(t as Entity).ownership.commander = cmd
	assert_false(_is_on_liberation_layer(t), "an owned terrestrial is left alone")

	(t as Entity).ownership.commander = null
	assert_true(_is_on_liberation_layer(t), "and rejoins the layer if it goes neutral again")

func test_death_leaves_the_liberation_layer():
	var t: Node = FakePieces.make(TERRESTRIAL)
	add_child_autofree(t)
	# queue_free() is end-of-frame, so a corpse answers shape queries for the rest of the
	# tick. Leaving on death is what keeps those out of the query in the first place.
	(t as Entity).entity_occurrence.emit(Entity.EntityOccurrence.ON_DEATH, null)
	assert_false(_is_on_liberation_layer(t), "a dying terrestrial drops off the layer")

func test_other_pieces_are_not_on_the_liberation_layer():
	var other: Node = FakePieces.unit(FakePieces.PLAIN)
	add_child_autofree(other)
	assert_false(_is_on_liberation_layer(other), "other pieces are not targets")

	# The regression this layer exists for: the host's own TargetBody sits dead-centre in
	# its LiberationRange, so on a shared targeting layer it consumed a query slot every
	# tick — which is why a warlord in a crowd converted nothing.
	var warlord: Node = FakePieces.make(WARLORD)
	add_child_autofree(warlord)
	assert_false(_is_on_liberation_layer(warlord), "a warlord cannot see itself")

func test_liberation_layer_survives_targetable_layer_recompute():
	var t: Node = FakePieces.make(TERRESTRIAL)
	add_child_autofree(t)
	# _apply_targetable_layers clears only the bits it owns; the LIBERATABLE bit is not
	# one of them. Sharing the TargetBody with targeting only works because of that.
	(t as Entity)._apply_targetable_layers()
	assert_true(_is_on_liberation_layer(t), "still liberatable after a targeting recompute")
	assert_true(
		((t as Entity).target_body.collision_layer & CollisionLayers.Mask.TARGETABLE_GROUND) != 0,
		"and still a ground target"
	)

func test_liberated_unit_follows_its_liberator():
	var warlord := FakePieces.make(WARLORD) as Commandable
	add_child_autofree(warlord)
	var recruit := FakePieces.unit(FakePieces.PLAIN)
	add_child_autofree(recruit)
	var lib := warlord.get_node_or_null("Liberator") as Liberator

	lib._follow(recruit, warlord)

	var cmd: MoveCommand = recruit.current_command()
	assert_not_null(cmd, "a freshly liberated unit is given an order")
	assert_eq(cmd.get_script(), MoveCommand, "a plain move — which is what reads as a follow")
	assert_eq(cmd.message.target, warlord, "targeting the warlord that liberated it")
	# A target-bearing message resolves its position from the target every tick, so the
	# recruit tracks the warlord as it walks rather than a fixed point.
	warlord.global_position = Vector3(9.0, 0.0, -4.0)
	assert_eq(cmd.message.position, warlord.global_position, "the destination follows the target")
