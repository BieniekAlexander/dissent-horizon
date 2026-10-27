extends GutTest

## EventEndReveal takes down the vision sources an EventRevealRegion placed under a label, and
## nothing else. A labelled reveal's Scouts join the label's group
## (EventRevealRegion._clear_fog_at); these stand in for them with fake pieces in that group.

const LABEL: StringName = &"test_end_reveal"

var _manager: ScenarioTriggerManager


func before_each() -> void:
	_manager = ScenarioTriggerManager.new()
	add_child_autofree(_manager)
	assert_push_warning("expected parent to be Scenario")


func after_each() -> void:
	if _manager.simulation_clock != null:
		_manager.simulation_clock.clear()
	get_tree().paused = false


func _watcher(a_group: StringName = &"") -> Entity:
	var piece := FakePieces.make({"vision": 12.0}) as Entity
	if not a_group.is_empty():
		piece.add_to_group(a_group)
	add_child_autofree(piece)
	return piece


func _end(a_label: StringName) -> void:
	var event := EventEndReveal.new()
	event.reveal_label = a_label
	autofree(event)
	event.execute(_manager)


func test_it_frees_every_source_under_its_label() -> void:
	var first: Entity = _watcher(LABEL)
	var second: Entity = _watcher(LABEL)
	_end(LABEL)
	assert_true(first.is_queued_for_deletion(), "the reveal goes dark")
	assert_true(second.is_queued_for_deletion())


func test_it_leaves_other_vision_alone() -> void:
	var other: Entity = _watcher(&"another_reveal")
	var unlabelled: Entity = _watcher()
	_end(LABEL)
	assert_false(other.is_queued_for_deletion(), "another reveal stands")
	assert_false(unlabelled.is_queued_for_deletion(), "and so does any other vision")


func test_a_missing_label_is_reported() -> void:
	_end(&"")
	assert_push_error("no reveal_label")


func test_a_reveal_offers_its_label_only_when_it_clears_fog() -> void:
	var reveal := EventRevealRegion.new()
	autofree(reveal)
	var label_usage := func() -> int:
		for property: Dictionary in reveal.get_property_list():
			if property.name == "reveal_label":
				reveal._validate_property(property)
				return property.usage
		return -1
	assert_ne(label_usage.call() & PROPERTY_USAGE_READ_ONLY, 0, "marking explored places nothing")
	reveal.clears_fog = true
	assert_eq(label_usage.call() & PROPERTY_USAGE_READ_ONLY, 0, "a standing reveal can be named")
