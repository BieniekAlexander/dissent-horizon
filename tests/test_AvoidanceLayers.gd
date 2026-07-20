extends GutTest

## Regression test for the size-class navmesh split. Each class mesh is a region on
## ONE shared navigation map, and an agent selects its class via navigation_layers.
## The bug this guards against: an earlier version put each class on its OWN map
## (set_navigation_map), which silos RVO avoidance per-map — so units of different
## sizes (and, as it turned out, even same-size units) passed through each other.
##
## A live NavigationServer can't be driven headlessly (see test_Movement), so we don't
## simulate avoidance here; we assert the configuration that makes map-wide avoidance
## possible: distinct per-class navigation LAYERS, and that configuring a unit changes
## only its layer — never its navigation MAP (which must stay shared for avoidance).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_AvoidanceLayers.gd


func test_layer_for_is_a_distinct_bit_per_class():
	var nm := NavManager.new()  # layer_for is pure; no _ready / map needed
	assert_eq(nm.layer_for(NavAgentClass.Size.SMALL),  1 << 0)
	assert_eq(nm.layer_for(NavAgentClass.Size.MEDIUM), 1 << 1)
	assert_eq(nm.layer_for(NavAgentClass.Size.LARGE),  1 << 2)
	# All class layers are disjoint from each other and from the base region's layer,
	# so no agent ever paths on another class's mesh or on the un-eroded base mesh.
	var seen: int = 0
	for size: int in NavAgentClass.Size.values():
		var bit: int = nm.layer_for(size)
		assert_eq(seen & bit, 0, "class layers must not overlap")
		assert_eq(bit & NavManager._BASE_LAYER, 0, "class layer must avoid the base layer")
		seen |= bit
	nm.free()


func test_configure_sets_class_layer_and_keeps_shared_map():
	# Build a Movement wrapping a real NavigationAgent3D, like test_Movement does.
	var parent := Node3D.new()
	add_child_autofree(parent)
	var agent := NavigationAgent3D.new()
	agent.name = "NavigationAgent"
	parent.add_child(agent)
	var m := Movement.new()
	m.nav_agent_path = NodePath("../NavigationAgent")
	parent.add_child(m)  # _ready resolves _nav_agent

	var map_before: RID = agent.get_navigation_map()

	# layer_for is pure, so a bare NavManager (no _ready) is enough to drive
	# configure_for_map. Radius 0.5 -> MEDIUM (SMALL's ceiling is 0.45 < 0.5).
	var nm := NavManager.new()
	m.configure_for_map(null, nm, 0.5)

	assert_eq(m.nav_agent_class, NavAgentClass.Size.MEDIUM, "0.5 footprint -> MEDIUM")
	assert_eq(agent.navigation_layers, nm.layer_for(NavAgentClass.Size.MEDIUM),
		"agent paths on its class layer")
	assert_eq(agent.get_navigation_map(), map_before,
		"agent stays on the shared map — avoidance must remain map-wide")
	# The avoidance radius tracks the true footprint, not the (larger) class radius.
	assert_almost_eq(agent.radius, 0.5, 1e-5, "avoidance radius = MovementBody footprint")
	nm.free()
