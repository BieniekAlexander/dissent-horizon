class_name FakePieces
extends RefCounted
## FAKE PIECES for unit tests: a `Commandable` built here, with exactly the components a test
## asks for and nothing a designer can retune.
##
## A test that instantiates a shipped piece (`cl_bioLight_antiLight.tscn`) is asserting about
## authored content by proxy — it breaks the day that piece is renamed, retuned or deleted,
## and isolates nothing. A test names the PROPERTY it needs instead:
##
##   var armed: Commandable = FakePieces.unit({"weapon": {"ground": 6.0}})
##   var gunless: Commandable = FakePieces.unit()
##
## The parts a piece is made of (`scenes/components/`) are the engine's own mechanics, not
## content, so they are used as-is; only pieces are faked. Nothing here reads `gdd/`, a shipped
## piece scene or a generated registry, and ids are `fake_*` so they cannot collide with one.
##
## The returned piece is NOT in the tree. Add it with `add_child_autofree`. Its physics is on,
## as it would be in a game; a test that does not want it to tick calls `set_physics_process`.
##
## Options (every one optional):
##   id: StringName          the piece's `Entity.id` (default `&"fake_unit"`)
##   hp: float               `Defense.hp_max`
##   speed: float            gives it a navigated `Movement` at this speed (default: immobile)
##   vision: float           radius of a `VisionRange` cylinder (default: none)
##   weapon: Dictionary      a `Loadout` with one `Weapon`:
##                             ground: float  radius of its ground reach (0 = none)
##                             air: float     radius of its air reach (0 = none)
##                             clip_size: int, charged: bool, reload_ticks: int
##   builds: Array           `Builds.buildable_types`, which also adds the `Builds` component
##   garrison: Dictionary    a `Garrison`: capacity: int
##   aerial: bool            an `Aerial` component that flies (implies a navigated `Movement`)
##   mesh: bool              a `MeshVisual` wearing one untextured placeholder mesh
##   dimensions: Vector2i    a structure's footprint (`structure()` only; default 1×1)
##   selectable: bool        false makes the `Selectable` refuse the player (default true)
##   obstruction: bool       a structure blocks line of fire (`structure()` only; default true)

const _COMPONENTS: String = "res://scenes/components/"


static func unit(a_options: Dictionary = {}) -> Commandable:
	return _build(a_options, false)


static func structure(a_options: Dictionary = {}) -> Commandable:
	return _build(a_options, true)


static func _build(a_options: Dictionary, a_structure: bool) -> Commandable:
	var piece := Commandable.new()
	piece.name = "FakeStructure" if a_structure else "FakeUnit"
	piece.id = a_options.get("id", &"fake_structure" if a_structure else &"fake_unit")
	piece.add_to_group(&"piece")
	piece.add_to_group(&"structure" if a_structure else &"unit")
	if a_structure:
		piece.add_to_group(&"fixture")

	# The pieces every Commandable's own lookups require.
	_add_scene(piece, "navigation_agent.tscn", "NavigationAgent")
	_add_scene(piece, "movement_body.tscn", "MovementBody")
	_add_scene(piece, "target_body.tscn", "TargetBody")
	_add_node(piece, Ownership.new(), "Ownership")
	var defense := Defense.new()
	defense.hp_max = float(a_options.get("hp", 100.0))
	_add_node(piece, defense, "Defense")
	_add_node(piece, Veterancy.new(), "Veterancy")
	_add_scene(piece, "selectable.tscn", "Selectable")
	_add_scene(piece, "hp_bar.tscn", "HPBar")

	if a_structure:
		var body := Structure.new()
		body.dimensions = a_options.get("dimensions", Vector2i(1, 1))
		body.is_obstruction = bool(a_options.get("obstruction", true))
		_add_node(piece, body, "Structure")
	if a_options.has("speed") or a_options.get("aerial", false):
		var movement := Movement.new()
		movement.speed = float(a_options.get("speed", 4.0))
		movement.nav_agent_path = NodePath("../NavigationAgent")
		_add_node(piece, movement, "Locomotion")
	if a_options.get("aerial", false):
		_add_node(piece, Aerial.new(), "Aerial")
	if a_options.get("mesh", false):
		var visual := MeshVisual.new()
		var model := MeshInstance3D.new()
		model.name = "PlaceholderModel"
		model.mesh = BoxMesh.new()
		visual.add_child(model)
		_add_node(piece, visual, "MeshVisual")
	if a_options.has("selectable"):
		(piece.get_node("Selectable") as Selectable).selectable_by_player = bool(a_options["selectable"])
	if a_options.has("vision"):
		var vision: Node = _scene("vision_range.tscn")
		vision.name = "VisionRange"
		(vision as CollisionShape3D).shape = _cylinder(float(a_options["vision"]))
		piece.add_child(vision)
	if a_options.has("weapon"):
		_add_loadout(piece, a_options["weapon"] as Dictionary)
	if a_options.has("builds"):
		var builds := Builds.new()
		var types: Array[StringName] = []
		for type: Variant in a_options["builds"] as Array:
			types.append(StringName(type))
		builds.buildable_types = types
		_add_node(piece, builds, "Builds")
	if a_options.has("garrison"):
		var garrison := Garrison.new()
		garrison.capacity = int((a_options["garrison"] as Dictionary).get("capacity", 1))
		_add_node(piece, garrison, "Garrison")
	return piece


static func _add_loadout(a_piece: Commandable, a_weapon: Dictionary) -> void:
	var loadout := Loadout.new()
	loadout.name = "Loadout"
	var weapon := Weapon.new()
	weapon.name = "Weapon"
	weapon.clip_size = int(a_weapon.get("clip_size", 1))
	weapon.charged = bool(a_weapon.get("charged", false))
	weapon.reload_time_ticks = int(a_weapon.get("reload_ticks", 10))
	loadout.add_child(weapon)
	var ground: float = float(a_weapon.get("ground", 0.0))
	var air: float = float(a_weapon.get("air", 0.0))
	# Reach on both layers is two named shapes, one each; reach on one layer is a lone shape whose
	# weapon's target_mask names the layer it serves.
	if ground > 0.0 and air > 0.0:
		weapon.target_mask = CollisionLayers.Mask.TARGETABLE_GROUND | CollisionLayers.Mask.TARGETABLE_AIR
		_add_reach(weapon, "AttackRangeGround", ground)
		_add_reach(weapon, "AttackRangeAir", air)
	elif ground > 0.0:
		_add_reach(weapon, "AttackRange", ground)
	elif air > 0.0:
		weapon.target_mask = CollisionLayers.Mask.TARGETABLE_AIR
		_add_reach(weapon, "AttackRange", air)
	a_piece.add_child(loadout)
	# A piece that can shoot will pick a fight on its own, out to about as far as it reaches.
	if ground > 0.0:
		_add_aggro(a_piece, "AggroRangeGround", ground)
	if air > 0.0:
		_add_aggro(a_piece, "AggroRangeAir", air)


static func _add_aggro(a_piece: Commandable, a_name: String, a_radius: float) -> void:
	var aggro: Node = _scene("aggro_range.tscn")
	aggro.name = a_name
	(aggro as CollisionShape3D).shape = _cylinder(a_radius)
	a_piece.add_child(aggro)


## The type of some tool a builder could be given, read from the registry so a test names a
## tool that exists without naming WHICH one: the registry's contents are content.
static func a_buildable_type() -> StringName:
	var tools: Array = Tool.tools_in_context(ControlBinding.ControlContext.BUILD)
	assert(not tools.is_empty(), "the tool registry holds at least one build tool")
	return (tools[0] as Tool).type


static func _add_reach(a_weapon: Weapon, a_name: String, a_radius: float) -> void:
	var reach := CollisionShape3D.new()
	reach.name = a_name
	reach.shape = _cylinder(a_radius)
	reach.add_to_group(&"debug_shape_attack_range")
	a_weapon.add_child(reach)


static func _cylinder(a_radius: float) -> CylinderShape3D:
	var shape := CylinderShape3D.new()
	shape.radius = a_radius
	shape.height = 2.0
	return shape


static func _scene(a_file: String) -> Node:
	return (load(_COMPONENTS + a_file) as PackedScene).instantiate()


static func _add_scene(a_piece: Node, a_file: String, a_name: String) -> void:
	var node: Node = _scene(a_file)
	node.name = a_name
	a_piece.add_child(node)


static func _add_node(a_piece: Node, a_node: Node, a_name: String) -> void:
	a_node.name = a_name
	a_piece.add_child(a_node)
