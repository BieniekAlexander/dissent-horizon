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
##   occupancy: int          `Entity.occupancy_size`, how much of a garrison it fills (default 1)
##   hp: float               `Defense.hp_max`
##   speed: float            gives it a navigated `Movement` at this speed (default: immobile)
##   vision: float           radius of a `VisionRange` cylinder (default: none)
##   weapon: Dictionary      a `Loadout` with one `Weapon`:
##                             projectile: bool  ranged (default when it has reach) or melee
##                             damage: float  per hit (default 0: a fake gun wounds nobody)
##                             ground: float  radius of its ground reach (0 = none)
##                             air: float     radius of its air reach (0 = none)
##                             clip_size: int, charged: bool, reload_ticks: int
##   builds: Array | true    `Builds.buildable_types` (true: one real tool's type), adding `Builds`
##   frame / armour: int     `Defense.frame_type` / `Defense.armour_type` (defaults BIO / LIGHT)
##   crush: int              `Movement.crush_class` (needs `speed`)
##   interactions: Array     `Interaction.Type`s, which adds an `Interactor`
##   garrison: Dictionary    a `Garrison`: capacity: int, sentence_length: float, bunker: bool,
##                             frames / armours / movements: int masks, ids: Array
##   aerial: bool            an `Aerial` component that flies (implies a navigated `Movement`)
##   mesh: bool              a `MeshVisual` wearing one untextured placeholder mesh
##   extraction_site: bool  an `ExtractionSite` marker (`structure()` only)
##   occupant_dominion: bool  an `OccupantDominionGenerator` (named "DominionGenerator")
##   liberatable: bool       a `Liberatable`: neutral, it sits on the liberation layer
##   liberator: bool         a `Liberator` converting into a blank unit, with a `LiberationRange`
##   shelter: bool          a `Shelter` component that spawns a blank unit
##   repairs: bool          a `Repairs` component: the piece can mend
##   dimensions: Vector2i    a structure's footprint (`structure()` only; default 1×1)
##   selectable: bool        false makes the `Selectable` refuse the player (default true)
##   obstruction: bool       a structure blocks line of fire (`structure()` only; default true)

const _COMPONENTS: String = "res://scenes/components/"

## PRESETS: the usual stand-ins, so a test that only needs "a soldier" says so. Each is just an
## options dictionary — copy and extend with `.merged({...})` when a test needs one more thing.
## A mobile piece that sees and has a ground gun.
const SOLDIER: Dictionary = {"speed": 2.0, "vision": 8.0, "weapon": {"ground": 6.0}}
## A mobile piece that sees and can build. (`"builds": true` fills in a real tool's type.)
const BUILDER: Dictionary = {"speed": 2.0, "vision": 8.0, "builds": true}
## A mobile, unarmed, non-building piece.
const PLAIN: Dictionary = {"speed": 2.0, "vision": 8.0}
## A structure with a hold.
const BUILDING: Dictionary = {"structure": true, "dimensions": Vector2i(2, 2)}
## A crusher-sized carrier with a cage and a DEPOSIT errand (no gun).
const TRUCK: Dictionary = {"speed": 2.0, "vision": 8.0, "crush": Movement.CrushClass.LARGE,
	"garrison": {"capacity": 3, "bunker": false}, "interactions": [Interaction.Type.DEPOSIT]}
## A structure that spawns residents.
const SHELTER: Dictionary = {"structure": true, "shelter": true}
## A closed hold that sentences captives and banks dominion for them.
const COMPOUND: Dictionary = {"structure": true, "occupant_dominion": true,
	"garrison": {"capacity": 6, "bunker": false, "sentence_length": 30.0, "frames": 0, "armours": 0, "movements": 0}}
## A neutral structure that holds an extractor.
const SITE: Dictionary = {"structure": true, "extraction_site": true}
## A mobile machine (MECH frame).
const MACHINE: Dictionary = {"speed": 2.0, "vision": 8.0, "frame": Defense.FrameType.MECH}
## A flying piece with a ground gun.
const AIRCRAFT: Dictionary = {"aerial": true, "vision": 8.0, "weapon": {"ground": 6.0}}


## Whichever of `unit` / `structure` the options name (`"structure": true` picks the latter).
static func make(a_options: Dictionary = {}) -> Commandable:
	return _build(a_options, bool(a_options.get("structure", false)))


## A PackedScene of the piece `a_options` describes, for code that takes scenes (a spawn event's
## `entity_scenes`) rather than instances. Each call packs a fresh copy.
static func scene_of(a_options: Dictionary = {}) -> PackedScene:
	var piece: Commandable = make(a_options)
	_claim_for_packing(piece, piece)
	var scene := PackedScene.new()
	scene.pack(piece)
	piece.free()
	return scene


static func _claim_for_packing(a_root: Node, a_node: Node) -> void:
	for child: Node in a_node.get_children():
		if child.owner == null:
			child.owner = a_root
		# Nodes inside an instanced component keep that instance as their owner.
		if child.scene_file_path.is_empty():
			_claim_for_packing(a_root, child)


static func unit(a_options: Dictionary = {}) -> Commandable:
	return _build(a_options, false)


static func structure(a_options: Dictionary = {}) -> Commandable:
	return _build(a_options, true)


static func _build(a_options: Dictionary, a_structure: bool) -> Commandable:
	var piece := Commandable.new()
	piece.name = "FakeStructure" if a_structure else "FakeUnit"
	piece.id = a_options.get("id", &"fake_structure" if a_structure else &"fake_unit")
	if a_options.has("occupancy"):
		piece.occupancy_size = int(a_options["occupancy"])
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
	defense.frame_type = a_options.get("frame", Defense.FrameType.BIO)
	defense.armour_type = a_options.get("armour", Defense.ArmourType.LIGHT)
	_add_node(piece, defense, "Defense")
	_add_node(piece, Veterancy.new(), "Veterancy")
	_add_scene(piece, "selectable.tscn", "Selectable")
	_add_scene(piece, "hp_bar.tscn", "HPBar")
	_add_scene(piece, "target_indicator.tscn", "TargetIndicator")

	if a_structure:
		var body := Structure.new()
		body.dimensions = a_options.get("dimensions", Vector2i(1, 1))
		body.is_obstruction = bool(a_options.get("obstruction", true))
		_add_node(piece, body, "Structure")
	if a_options.has("speed") or a_options.get("aerial", false):
		var movement := Movement.new()
		movement.speed = float(a_options.get("speed", 4.0))
		movement.nav_agent_path = NodePath("../NavigationAgent")
		if a_options.has("crush"):
			movement.crush_class = a_options["crush"]
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
	if a_options.get("extraction_site", false):
		_add_node(piece, ExtractionSite.new(), "ExtractionSite")
		piece.add_to_group(&"extraction_site")
	if a_options.get("occupant_dominion", false):
		_add_node(piece, OccupantDominionGenerator.new(), "DominionGenerator")
	if a_options.get("liberatable", false):
		_add_node(piece, Liberatable.new(), "Liberatable")
	if a_options.get("liberator", false):
		var liberator := Liberator.new()
		liberator.converted_scene = _blank_projectile()
		_add_node(piece, liberator, "Liberator")
		var reach := CollisionShape3D.new()
		reach.shape = _cylinder(4.0)
		_add_node(piece, reach, "LiberationRange")
	if a_options.get("shelter", false):
		var shelter := Shelter.new()
		shelter.terrestrial_scene = _blank_projectile()
		_add_node(piece, shelter, "Shelter")
	if a_options.get("repairs", false):
		_add_node(piece, Repairs.new(), "Repairs")
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
		var named: Variant = a_options["builds"]
		if named is Array:
			for type: Variant in named as Array:
				types.append(StringName(type))
		elif named == true:
			types.append(a_buildable_type())
		builds.buildable_types = types
		_add_node(piece, builds, "Builds")
	if a_options.has("garrison"):
		_add_garrison(piece, a_options["garrison"] as Dictionary)
	if a_options.has("interactions"):
		var interactor := Interactor.new()
		var list: Array[Interaction] = []
		for type: Variant in a_options["interactions"] as Array:
			var interaction := Interaction.new()
			interaction.type = type
			interaction.interact_shape = _cylinder(2.0)
			list.append(interaction)
		interactor.interactions = list
		_add_node(piece, interactor, "Interactor")
	return piece


static func _add_garrison(a_piece: Commandable, a_spec: Dictionary) -> void:
	var garrison := Garrison.new()
	garrison.capacity = int(a_spec.get("capacity", 1))
	garrison.sentence_length = float(a_spec.get("sentence_length", 0.0))
	garrison.bunker = bool(a_spec.get("bunker", true))
	if a_spec.has("frames"):
		garrison.occupiable_frames = int(a_spec["frames"])
	if a_spec.has("armours"):
		garrison.occupiable_armours = int(a_spec["armours"])
	if a_spec.has("movements"):
		garrison.occupiable_movements = int(a_spec["movements"])
	if a_spec.has("ids"):
		var ids: Array[StringName] = []
		for id: Variant in a_spec["ids"] as Array:
			ids.append(StringName(id))
		garrison.occupiable_ids = ids
	_add_node(a_piece, garrison, "Garrison")


static func _add_loadout(a_piece: Commandable, a_weapon: Dictionary) -> void:
	var loadout := Loadout.new()
	loadout.name = "Loadout"
	var weapon := Weapon.new()
	weapon.name = "Weapon"
	weapon.clip_size = int(a_weapon.get("clip_size", 1))
	weapon.charged = bool(a_weapon.get("charged", false))
	weapon.reload_time_ticks = int(a_weapon.get("reload_ticks", 10))
	# Harmless by default: a fake that shoots would kill what a test set up to be shot AT.
	weapon.melee_damage = float(a_weapon.get("damage", 0.0))
	loadout.add_child(weapon)
	var ground: float = float(a_weapon.get("ground", 0.0))
	var air: float = float(a_weapon.get("air", 0.0))
	# A gun that reaches somewhere is ranged and fires SOMETHING; `projectile: false` makes it melee.
	if bool(a_weapon.get("projectile", ground > 0.0 or air > 0.0)):
		weapon.projectile_scene = _blank_projectile()
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
	else:
		# A weapon always looks for its reach shape: a gun that reaches nowhere has an empty one.
		_add_reach(weapon, "AttackRange", 0.0)
	a_piece.add_child(loadout)
	# A piece that can shoot will pick a fight on its own, out to about as far as it reaches.
	_add_aggro(a_piece, "AggroRangeGround", ground)
	_add_aggro(a_piece, "AggroRangeAir", air)


## A scene with nothing in it: enough for a weapon to count as ranged, and to launch into.
static func _blank_projectile() -> PackedScene:
	var blank := Node3D.new()
	var scene := PackedScene.new()
	scene.pack(blank)
	blank.free()
	return scene


static func _add_aggro(a_piece: Commandable, a_name: String, a_radius: float) -> void:
	var aggro: Node = _scene("aggro_range.tscn")
	aggro.name = a_name
	if a_radius > 0.0:
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
	if a_radius > 0.0:
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
