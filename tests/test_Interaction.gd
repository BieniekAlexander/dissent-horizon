extends GutTest

## Tests for the Shelter/interaction mechanic:
##   - Shelter: a startup countdown that flips `available` once it hits 0.
##   - Interactor / Interaction: a unit's list of type-matched interactions.
##
## These classes are pure data/logic components, so the tests drive them
## directly (calling _ready / _physics_process) without standing up a scene.

## --- Shelter ------------------------------------------------------------

func test_Shelter_starts_unavailable_and_counts_down():
	var e := Shelter.new()
	e.startup_delay = 2.0
	autofree(e)
	e._ready()
	assert_false(e.available, "unavailable while the timer is running")
	e._physics_process(1.0)
	assert_false(e.available, "still counting down after a partial tick")
	e._physics_process(1.0)
	assert_true(e.available, "available once the timer reaches 0")

func test_Shelter_clamps_at_zero():
	var e := Shelter.new()
	e.startup_delay = 1.0
	autofree(e)
	e._ready()
	e._physics_process(5.0)  # overshoot the remaining time
	assert_true(e.available)
	assert_eq(e._remaining, 0.0, "timer never goes negative")

## --- Interactor / Interaction ---------------------------------------------
##
## Applicability is now decided by the interaction type's mapped precondition
## function. LIBERATE passes iff the message target has a Shelter component.

func _make_interactor(a_type: Interaction.Type) -> Interactor:
	var interactor := Interactor.new()
	autofree(interactor)
	var ix := Interaction.new()
	ix.type = a_type
	interactor.interactions.append(ix)
	return interactor

## A bare target entity, optionally carrying a Shelter component child (a plain
## Node named "Shelter" — the LIBERATE evaluator only checks has_node).
func _make_target(a_has_shelter: bool) -> Entity:
	var t := Entity.new()
	autofree(t)
	if a_has_shelter:
		var s := Node.new()
		s.name = "Shelter"
		t.add_child(s)
		autofree(s)
	return t

func _message_for(a_target: Entity) -> CommandMessage:
	return CommandMessage.new(null, a_target)

func test_liberate_applies_when_target_has_shelter():
	var interactor := _make_interactor(Interaction.Type.LIBERATE)
	var target := _make_target(true)
	var msg := _message_for(target)
	assert_true(interactor.can_interact(null, msg))
	assert_eq(interactor.applicable_interaction(null, msg).type, Interaction.Type.LIBERATE)

func test_liberate_does_not_apply_without_shelter():
	var interactor := _make_interactor(Interaction.Type.LIBERATE)
	var target := _make_target(false)
	var msg := _message_for(target)
	assert_false(interactor.can_interact(null, msg))
	assert_null(interactor.applicable_interaction(null, msg))

func test_liberate_evaluation_returns_failure_cause():
	var ix := Interaction.new()
	ix.type = Interaction.Type.LIBERATE
	assert_eq(
		ix.meets_precondition(null, _message_for(_make_target(true))),
		Command.PreconditionFailureCause.NONE
	)
	assert_eq(
		ix.meets_precondition(null, _message_for(_make_target(false))),
		Command.PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	)
