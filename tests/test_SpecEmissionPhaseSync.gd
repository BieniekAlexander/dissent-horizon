extends GutTest

## The importer writing an emission's phase list into its scene: one EmissionPhase node per
## phase, in run order, removed when the doc drops it — and written THROUGH an override when
## the scene inherits the phase from another emission, never re-declared beside it. A second
## node of the same name is the duplicate that segfaults at engine teardown (CLAUDE.md), and
## recruit_bullet.tscn, which inherits irregular_bullet.tscn, is the shipped case.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gtest=res://tests/test_SpecEmissionPhaseSync.gd -gdir=res://tests/none -gexit

## Preloaded rather than reached through class_name: a headless run does not refresh the
## global class cache. Same reason as test_SpecGenerators.
const SceneSync := preload("res://tools/spec_import/scene_sync.gd")
const TscnDoc := preload("res://tools/spec_import/tscn_doc.gd")

const BARE_SCENE: String = """[gd_scene load_steps=1 format=3]

[node name="Shot" type="CharacterBody3D"]
"""

const SHORTHAND: Dictionary = {"speed": 30, "trajectory": "LINEAR", "hitscan": true}


func _ctx(a_text: String, a_inst: Node) -> RefCounted:
	var ctx := SceneSync.Ctx.new()
	ctx.doc = TscnDoc.from_text(a_text)
	ctx.inst = a_inst
	ctx.path = "res://scenes/entities/projectiles/test_shot.tscn"
	return ctx


func _bare_inst() -> Node:
	var root: CharacterBody3D = CharacterBody3D.new()
	root.name = "Shot"
	add_child_autofree(root)
	return root


## A live instance that already carries `a_names` as phases — inherited ones, since the doc
## text passed alongside it declares none of them.
func _inst_inheriting(a_names: Array[String]) -> Node:
	var root: Node = _bare_inst()
	for phase_name: String in a_names:
		var phase: EmissionPhase = EmissionPhase.new()
		phase.name = phase_name
		root.add_child(phase)
	return root


func _node_names(a_text: String) -> Array[String]:
	var names: Array[String] = []
	var regex: RegEx = RegEx.create_from_string("\\[node name=\"([^\"]+)\"")
	for found: RegExMatch in regex.search_all(a_text):
		names.append(found.get_string(1))
	return names


func test_the_shorthand_writes_a_flight_and_an_impact_in_order() -> void:
	var ctx: RefCounted = _ctx(BARE_SCENE, _bare_inst())
	SceneSync.new()._sync_phases(ctx, SHORTHAND)
	var text: String = ctx.doc.to_text()
	assert_eq(_node_names(text), ["Shot", "Flight", "Impact"])
	assert_string_contains(text, "speed = 30.0")
	assert_string_contains(text, "applies_payload = true")
	assert_false(text.contains("gravity_mps2"), "a default is not written into a new node")


func test_a_dropped_phase_is_removed() -> void:
	var sync := SceneSync.new()
	var ctx: RefCounted = _ctx(BARE_SCENE, _bare_inst())
	sync._sync_phases(ctx, {"phases": [{"motion": "LINEAR"}, {"lifespan": 0, "payload": "once"},
		{"name": "Linger", "lifespan": 1}]})
	var three_phase: String = ctx.doc.to_text()
	var reread: RefCounted = _ctx(three_phase, _inst_owning(three_phase))
	sync._sync_phases(reread, SHORTHAND)
	assert_eq(_node_names(reread.doc.to_text()), ["Shot", "Flight", "Impact"])


func test_an_inherited_phase_is_overridden_not_redeclared() -> void:
	var ctx: RefCounted = _ctx(BARE_SCENE, _inst_inheriting(["Flight", "Impact"]))
	SceneSync.new()._sync_phases(ctx, {"speed": 20, "trajectory": "LINEAR"})
	var text: String = ctx.doc.to_text()
	assert_false(text.contains("[node name=\"Flight\" type="),
		"no second Flight declared beside the inherited one")
	assert_string_contains(text, "[node name=\"Flight\" parent=\".\"")
	assert_string_contains(text, "speed = 20.0")


func test_a_matching_inherited_phase_writes_nothing() -> void:
	var inst: Node = _inst_inheriting(["Flight", "Impact"])
	var flight: EmissionPhase = inst.get_node("Flight")
	flight.speed = 30.0
	var impact: EmissionPhase = inst.get_node("Impact")
	impact.ends_on_arrival = false
	impact.lifespan_seconds = 0.0
	impact.applies_payload = true
	var ctx: RefCounted = _ctx(BARE_SCENE, inst)
	SceneSync.new()._sync_phases(ctx, SHORTHAND)
	assert_eq(ctx.doc.to_text(), BARE_SCENE, "an inheriting scene that agrees states nothing")


## A live instance matching `a_text`'s own phase declarations, as loading that scene would give.
func _inst_owning(a_text: String) -> Node:
	var names: Array[String] = _node_names(a_text)
	names.erase("Shot")
	return _inst_inheriting(names)
