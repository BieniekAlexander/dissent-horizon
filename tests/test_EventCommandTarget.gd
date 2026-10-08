extends GutTest

## Tests for EventCommandTarget — the `frame_filter` addition, and to_command()'s BASE-type
## branch (Command Assignment extensions, gdd/tasks.md). Both exercised without a live
## Map/navmesh fixture: _enemy_candidates() has no such dependency, and neither does
## to_command() for Type.BASE specifically — it builds an Attack targeting a live structure
## entity directly rather than calling NavigationServer3D.map_get_closest_point(), which is
## Type.ARMY's path only. ARMY's to_command() therefore still has no coverage here — no other
## test in this suite sets up a navmesh fixture either.
##
## Run with:
## godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_EventCommandTarget.gd -gexit

## BIO frame.
const RECRUIT: Dictionary = FakePieces.SOLDIER
## MECH frame.
## A metallic flier, against the soldier's biological frame.
const CLIPPER: Dictionary = {"aerial": true, "vision": 8.0, "frame": Defense.FrameType.MECH}
const BUILDING: Dictionary = FakePieces.BUILDING

var _manager: ScenarioTriggerManager


func before_each() -> void:
	_manager = ScenarioTriggerManager.new()
	add_child_autofree(_manager)
	assert_push_warning("expected parent to be Scenario")


## A live Actor owned by `commander_id`, in the "unit" group (mirrors what Map.add_entity
## does for a real spawn).
func _unit(a_options: Dictionary, a_commander_id: int) -> Actor:
	var unit: Actor = FakePieces.make(a_options)
	add_child_autofree(unit)
	# The Commander must already be IN THE TREE: setting .commander fires
	# Ownership.commander_changed, which auto-reparents the entity to live under its commander
	# (CLAUDE.md's Scenario section) — a tree-less Commander would carry the unit out of the
	# live SceneTree with it, silently, and get_nodes_in_group() would find nothing afterward.
	var owner_commander := Commander.new()
	owner_commander.id = a_commander_id
	add_child_autofree(owner_commander)
	unit.commander = owner_commander
	unit.add_to_group("unit")
	return unit


## A live structure Actor owned by `commander_id`, in the "structure" group, positioned
## at `pos`.
func _structure(a_commander_id: int, a_pos: Vector3) -> Actor:
	var structure: Actor = FakePieces.make(BUILDING)
	add_child_autofree(structure)
	var owner_commander := Commander.new()
	owner_commander.id = a_commander_id
	add_child_autofree(owner_commander)
	structure.commander = owner_commander
	structure.add_to_group("structure")
	structure.global_position = a_pos
	return structure


func test_no_filter_includes_every_frame_type() -> void:
	var target := EventCommandTarget.new()
	autofree(target)
	target.type = EventCommandTarget.Type.ARMY  # default is BASE (structures); these units are "unit"
	var bio := _unit(RECRUIT, 2)
	var metal := _unit(CLIPPER, 2)
	var candidates: Array = target._enemy_candidates(_manager, 1)
	assert_has(candidates, bio, "no frame_filter set: biological is a candidate")
	assert_has(candidates, metal, "no frame_filter set: metallic is a candidate too")


func test_frame_filter_excludes_the_other_frame_type() -> void:
	var target := EventCommandTarget.new()
	autofree(target)
	target.type = EventCommandTarget.Type.ARMY  # default is BASE (structures); these units are "unit"
	target.frame_filter = Defense.FrameType.BIO
	var bio := _unit(RECRUIT, 2)
	var metal := _unit(CLIPPER, 2)
	var candidates: Array = target._enemy_candidates(_manager, 1)
	assert_has(candidates, bio, "matches the filtered frame type")
	assert_does_not_have(candidates, metal, "the other frame type is excluded")


func test_frame_filter_still_respects_commander_exclusion() -> void:
	var target := EventCommandTarget.new()
	autofree(target)
	target.type = EventCommandTarget.Type.ARMY  # default is BASE (structures); these units are "unit"
	target.frame_filter = Defense.FrameType.BIO
	var own_bio := _unit(RECRUIT, 1)  # same commander as the spawning_id passed below
	var neutral_bio := _unit(RECRUIT, 0)
	var enemy_bio := _unit(RECRUIT, 2)
	var candidates: Array = target._enemy_candidates(_manager, 1)
	assert_does_not_have(candidates, own_bio, "still excludes the spawning commander's own units")
	assert_does_not_have(candidates, neutral_bio, "still excludes neutral (commander 0)")
	assert_has(candidates, enemy_bio, "a genuine enemy of the matching frame type is included")


# --- to_command(), Type.BASE: Attack on a specific structure, not AttackMove to a centroid --


func test_base_type_returns_an_attack_locked_onto_one_structure() -> void:
	var target := EventCommandTarget.new()
	add_child_autofree(target)  # global_position (used as ref_pos) needs target inside the tree
	# type defaults to BASE
	var near := _structure(2, Vector3(1, 0, 0))
	var far := _structure(2, Vector3(50, 0, 0))  # outside the 10wu cluster threshold: its own cluster
	var cmd: MoveCommand = target.to_command(_manager)
	assert_true(cmd is Attack, "BASE locks onto a specific structure, not an AttackMove")
	assert_eq(
		cmd.message.target,
		near,
		"CLOSEST priority (the default) picks the nearer cluster/structure"
	)
	assert_ne(cmd.message.target, far)


func test_base_type_ignores_units_entirely() -> void:
	var target := EventCommandTarget.new()
	add_child_autofree(target)
	var structure := _structure(2, Vector3(3, 0, 0))
	_unit(RECRUIT, 2)  # an enemy unit, much closer to the origin than the structure
	var cmd: MoveCommand = target.to_command(_manager)
	assert_true(cmd is Attack)
	assert_eq(
		cmd.message.target,
		structure,
		"a BASE-type rule never targets a unit, regardless of proximity"
	)


func test_base_type_with_no_enemy_structures_returns_null() -> void:
	var target := EventCommandTarget.new()
	autofree(target)
	_unit(RECRUIT, 2)  # units exist, but type is BASE — nothing to target
	var cmd: Variant = target.to_command(_manager)
	assert_null(cmd, "no enemy structures at all: a no-op, not a crash")
