extends GutTest

## The Scenario must guarantee a ScenarioTriggerManager (the event host) so that
## commander ordnances and scripted events always have somewhere to run — even in a
## scene like skirmish.tscn that declares no triggers. Guards the regression where
## bots silently no-op'd because the booted scene had no host.
##
## The Scenario is kept ORPHAN (never added to the tree) so its heavy _ready boot
## doesn't run; we exercise _ensure_trigger_manager() directly.

var _scn: Scenario


func before_each() -> void:
	_scn = Scenario.new()


func after_each() -> void:
	_scn.free()


func test_creates_a_host_when_the_scene_has_none() -> void:
	assert_null(_scn.get_node_or_null("ScenarioTriggerManager"), "starts with no host")
	var host: ScenarioTriggerManager = _scn._ensure_trigger_manager()
	assert_not_null(host, "a host is created on demand")
	assert_eq(host.name, &"ScenarioTriggerManager", "named so get_node_or_null finds it")
	assert_eq(host.get_parent(), _scn, "parented under the scenario")


func test_is_idempotent_when_a_host_already_exists() -> void:
	# A scene that ships its own authored host (e.g. s1.tscn) keeps it.
	var authored := ScenarioTriggerManager.new()
	authored.name = &"ScenarioTriggerManager"
	_scn.add_child(authored)

	var resolved: ScenarioTriggerManager = _scn._ensure_trigger_manager()
	assert_same(resolved, authored, "returns the existing host, doesn't create a second")
	assert_eq(
		_scn.find_children("*", "ScenarioTriggerManager", true, false).size(), 1,
		"exactly one host"
	)
