class_name FakePieces
extends RefCounted
## FAKE PIECES for unit tests: a `Actor` built here, with exactly the components a test
## asks for and nothing a designer can retune.
##
## A test that instantiates a shipped piece (`cl_bioLight_antiLight.tscn`) is asserting about
## authored content by proxy — it breaks the day that piece is renamed, retuned or deleted,
## and isolates nothing. A test names the PROPERTY it needs instead:
##
##   var armed: Actor = FakePieces.unit({"weapon": {"ground": 6.0}})
##   var gunless: Actor = FakePieces.unit()
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
##   infrastructure: int     `Actor.infrastructure`: what it provides (+) or draws (-)
##   occupancy: int          `Entity.occupancy_size`, how much of a garrison it fills (default 1)
##   hp: float               `Defense.hp_max`
##   speed: float            gives it a navigated `Movement` at this speed (default: immobile)
##   vision: float           radius of a `VisionRange` cylinder (default: none)
##   weapon: Dictionary      a `Loadout` with one `Weapon`:
## projectile: bool  ranged (it carries a blank projectile) or melee (default)
##                             damage: float  per hit (default 0: a fake gun wounds nobody)
##                             ground: float  radius of its ground reach (0 = none)
##                             air: float     radius of its air reach (0 = none)
##                             clip_size: int, charged: bool, reload_ticks: int
##   builds: Array | true    `Builds.buildable_types` (true: one real tool's type), adding `Builds`
##   frame / armour: int     `Defense.frame_type` / `Defense.armour_type` (defaults BIO / LIGHT)
##   crush: int              `Movement.crush_class` (needs `speed`)
##   interactions: Array     `Interaction.Type`s, which adds an `Interactor`
##   garrison: Dictionary    a `Garrison`: capacity: int, sentence_length: float, bunker: bool,
##                             captures: bool (takes prisoners by contact; the truck's cage),
##                             frames / armours / movements: int masks, ids: Array
##   aerial: bool            an `Aerial` component that flies (implies a navigated `Movement`)
##   flying: bool            `Movement.mode` FLYING rather than HOVERING (needs `aerial`)
## extractor: bool         an `EnergyExtractor` and `Extractor`: built over an extraction site, it
## works it
##   production: bool       a `Production` component (a producer)
##   produces: Array         `Production.producible_types` (implies `production`)
##   mesh: bool              a `MeshVisual` wearing one untextured placeholder mesh
##   extraction_site: bool  an `ExtractionSite` marker (`structure()` only)
##   occupant_dominion: bool  an `OccupantDominionGenerator` (named "DominionGenerator")
##   liberatable: bool       a `Liberatable`: neutral, it sits on the liberation layer
##   liberator: bool         a `Liberator` converting into a blank unit, with a `LiberationRange`
##   stealth: bool           a `Stealth` component (starts stealthed)
##   status_visuals: bool    a `StatusVisuals` (badges, tints, pips); pair it with `mesh`
##   docking: bool           a `Docking`: the aircraft can land at a friendly airfield
##   docking_bay: Dictionary an airfield: pads: int (default 2), runways: int (default 1)
##   beacon_range: float     a `BeaconRange` of this radius: ground it covers counts as spotted
## abilities: Array        an `Abilities` pool per entry: {grants: [ids], max_charges,
## cooldown_ticks}
##   shelter: bool          a `Shelter` component that spawns a blank unit
##   repairs: bool          a `Repairs` component: the piece can mend
##   dimensions: Vector2i    a structure's footprint (`structure()` only; default 1×1)
##   selectable: bool        false makes the `Selectable` refuse the player (default true)
##   obstruction: bool       a structure blocks line of fire (`structure()` only; default true)
##   commandable: bool       false leaves off the `Orders` component: an Actor that takes no orders

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
const TRUCK: Dictionary = {
	"speed": 2.0,
	"vision": 8.0,
	"crush": Movement.CrushClass.LARGE,
	"garrison": {"capacity": 3, "bunker": false, "captures": true},
	"interactions": [Interaction.Type.DEPOSIT]
}
## A structure that spawns residents.
const SHELTER: Dictionary = {"structure": true, "shelter": true}
## A closed hold that sentences captives and banks dominion for them.
const COMPOUND: Dictionary = {
	"structure": true,
	"occupant_dominion": true,
	"garrison":
	{
		"capacity": 6,
		"bunker": false,
		"sentence_length": 30.0,
		"frames": 0,
		"armours": 0,
		"movements": 0
	}
}
## A neutral structure that holds an extractor.
const SITE: Dictionary = {"structure": true, "extraction_site": true}
## A mobile machine (MECH frame).
const MACHINE: Dictionary = {"speed": 2.0, "vision": 8.0, "frame": Defense.FrameType.MECH}
## A flying piece with a ground gun.
const AIRCRAFT: Dictionary = {"aerial": true, "vision": 8.0, "weapon": {"ground": 6.0}}


## Whichever of `unit` / `structure` / `feature` the options name (`"structure": true`,
## `"feature": true`).
static func make(a_options: Dictionary = {}) -> Entity:
	if a_options.get("feature", false):
		return feature(a_options)
	return _build(a_options, bool(a_options.get("structure", false)))


## An UNCOMMANDABLE fixture: an `Entity` with a footprint and hit points that takes no orders
## (a neutral marker, a resource site). Options as for `structure()`.
static func feature(a_options: Dictionary = {}) -> Entity:
	var piece := Entity.new()
	piece.name = "FakeFeature"
	piece.id = a_options.get("id", &"fake_feature")
	piece.add_to_group(&"piece", true)
	piece.add_to_group(&"fixture", true)
	_add_hurtbox(piece)
	_add_scene(piece, "selectable.tscn", "Selectable")
	_add_node(piece, Ownership.new(), "Ownership")
	var defense := Defense.new()
	defense.hp_max = float(a_options.get("hp", 100.0))
	_add_node(piece, defense, "Defense")
	var body := Fixture.new()
	body.dimensions = a_options.get("dimensions", Vector2i(1, 1))
	body.is_obstruction = bool(a_options.get("obstruction", true))
	_add_node(piece, body, "Fixture")
	if a_options.get("extraction_site", false):
		_add_node(piece, ExtractionSite.new(), "ExtractionSite")
		piece.add_to_group(&"extraction_site", true)
	_claim_for_packing(piece, piece)
	return piece


## A PackedScene of the piece `a_options` describes, for code that takes scenes (a spawn event's
## `entity_scenes`) rather than instances. Each call packs a fresh copy.
static func scene_of(a_options: Dictionary = {}) -> PackedScene:
	var piece: Entity = make(a_options)
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


static func unit(a_options: Dictionary = {}) -> Actor:
	return _build(a_options, false)


static func structure(a_options: Dictionary = {}) -> Actor:
	return _build(a_options, true)


static func _build(a_options: Dictionary, a_structure: bool) -> Actor:
	var piece := Actor.new()
	piece.name = "FakeStructure" if a_structure else "FakeUnit"
	piece.id = a_options.get("id", &"fake_structure" if a_structure else &"fake_unit")
	if a_options.has("infrastructure"):
		piece.infrastructure = int(a_options["infrastructure"])
	if a_options.has("occupancy"):
		piece.occupancy_size = int(a_options["occupancy"])
	piece.add_to_group(&"piece", true)
	piece.add_to_group(&"structure" if a_structure else &"unit", true)
	if a_structure:
		piece.add_to_group(&"fixture", true)

	# The pieces every Actor's own lookups require.
	_add_scene(piece, "navigation_agent.tscn", "NavigationAgent")
	_add_scene(piece, "movement_body.tscn", "MovementBody")
	_add_hurtbox(piece)
	_add_node(piece, Ownership.new(), "Ownership")
	var defense := Defense.new()
	defense.hp_max = float(a_options.get("hp", 100.0))
	defense.frame_type = a_options.get("frame", Defense.FrameType.BIO)
	defense.armour_type = a_options.get("armour", Defense.ArmourType.LIGHT)
	_add_node(piece, defense, "Defense")
	_add_node(piece, Veterancy.new(), "Veterancy")
	_add_scene(piece, "selectable.tscn", "Selectable")
	# Takes orders unless the test says otherwise, as `commandable: false` does for a doc.
	if bool(a_options.get("commandable", true)):
		_add_node(piece, Orders.new(), "Orders")
	_add_scene(piece, "hp_bar.tscn", "HPBar")
	_add_scene(piece, "target_indicator.tscn", "TargetIndicator")
	_add_scene(piece, "avoidance_obstacle.tscn", "AvoidanceObstacle")

	if a_structure:
		var body := Fixture.new()
		body.dimensions = a_options.get("dimensions", Vector2i(1, 1))
		body.is_obstruction = bool(a_options.get("obstruction", true))
		_add_node(piece, body, "Fixture")
	if a_options.has("speed") or a_options.get("aerial", false):
		var movement := Movement.new()
		movement.speed = float(a_options.get("speed", 4.0))
		movement.nav_agent_path = NodePath("../NavigationAgent")
		movement.turn_rate = float(a_options.get("turn_rate", 360.0))
		if a_options.get("flying", false):
			movement.mode = Movement.Mode.FLYING
		if a_options.has("crush"):
			movement.crush_class = a_options["crush"]
		_add_node(piece, movement, "Locomotion")
	if a_options.get("aerial", false):
		var aerial := Aerial.new()
		if a_options.get("flying", false):
			aerial.mode = Movement.Mode.FLYING
		_add_node(piece, aerial, "Aerial")
	if a_options.get("mesh", false):
		var visual := MeshVisual.new()
		var model := MeshInstance3D.new()
		model.name = "PlaceholderModel"
		model.mesh = BoxMesh.new()
		visual.add_child(model)
		_add_node(piece, visual, "MeshVisual")
	if a_options.has("selectable"):
		(piece.get_node("Selectable") as Selectable).selectable_by_player = bool(
			a_options["selectable"]
		)
	if a_options.get("extraction_site", false):
		_add_node(piece, ExtractionSite.new(), "ExtractionSite")
		piece.add_to_group(&"extraction_site", true)
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
	if a_options.get("stealth", false):
		_add_node(piece, Stealth.new(), "Stealth")
	if a_options.get("status_visuals", false):
		_add_node(piece, StatusVisuals.new(), "StatusVisuals")
	if a_options.get("extractor", false):
		_add_node(piece, EnergyExtractor.new(), "EnergyExtractor")
		_add_node(piece, Extractor.new(), "Extractor")
	if a_options.get("production", false) or a_options.has("produces"):
		var production := Production.new()
		var produced: Array[StringName] = []
		for id: Variant in a_options.get("produces", []) as Array:
			produced.append(StringName(id))
		production.producible_types = produced
		_add_node(piece, production, "Production")
	if a_options.get("docking", false):
		_add_node(piece, Docking.new(), "Docking")
	if a_options.has("docking_bay"):
		_add_docking_bay(piece, a_options["docking_bay"] as Dictionary)
	if a_options.has("beacon_range"):
		var spotting := BeaconRange.new()
		spotting.radius = float(a_options["beacon_range"])
		_add_node(piece, spotting, "BeaconRange")
	if a_options.has("abilities"):
		var pool := Abilities.new()
		var groups: Array[Dictionary] = []
		for entry: Variant in a_options["abilities"] as Array:
			var group: Dictionary = {"max_charges": 1, "cooldown_ticks": 100}
			group.merge(entry as Dictionary, true)
			groups.append(group)
		pool.groups = groups
		_add_node(piece, pool, "Abilities")
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
	_claim_for_packing(piece, piece)
	return piece


static func _add_docking_bay(a_piece: Actor, a_spec: Dictionary) -> void:
	var bay := DockingBay.new()
	bay.name = "DockingBay"
	for i: int in int(a_spec.get("pads", 2)):
		var pad := DockingPad.new()
		pad.name = "Pad%d" % i
		pad.position = Vector3(float(i) * 3.0, 0.0, 0.0)
		bay.add_child(pad)
	for i: int in int(a_spec.get("runways", 1)):
		var runway := Runway.new()
		runway.name = "Runway%d" % i
		# Beside the apron, so the way from a pad onto the strip is a real taxi.
		runway.position = Vector3(-6.0, 0.0, -4.0 - float(i) * 3.0)
		bay.add_child(runway)
	a_piece.add_child(bay)


static func _add_garrison(a_piece: Actor, a_spec: Dictionary) -> void:
	var garrison := Garrison.new()
	garrison.capacity = int(a_spec.get("capacity", 1))
	garrison.sentence_length = float(a_spec.get("sentence_length", 0.0))
	garrison.bunker = bool(a_spec.get("bunker", true))
	garrison.captures = bool(a_spec.get("captures", false))
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


static func _add_loadout(a_piece: Actor, a_weapon: Dictionary) -> void:
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
	# Melee unless a test asks for a ranged gun: a blank projectile a fake fires is not an Entity,
	# and nothing here should actually launch one.
	if bool(a_weapon.get("projectile", false)):
		weapon.projectile_scene = _blank_projectile()
	# Reach on both layers is two named shapes, one each; reach on one layer is a lone shape whose
	# weapon's target_mask names the layer it serves.
	if ground > 0.0 and air > 0.0:
		weapon.target_mask = (
			CollisionLayers.Mask.TARGETABLE_GROUND | CollisionLayers.Mask.TARGETABLE_AIR
		)
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


static func _add_aggro(a_piece: Actor, a_name: String, a_radius: float) -> void:
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
	reach.add_to_group(&"debug_shape_attack_range", true)
	a_weapon.add_child(reach)


static func _cylinder(a_radius: float) -> CylinderShape3D:
	var shape := CylinderShape3D.new()
	shape.radius = a_radius
	shape.height = 2.0
	return shape


static func _scene(a_file: String) -> Node:
	return (load(_COMPONENTS + a_file) as PackedScene).instantiate()


## The component ships its hurtbox EMPTY — the importer fits each piece's to its model — so a
## fake carries one fitted to a nominal body: the default 0.5-radius, 2-tall cylinder,
## standing on the origin as every baked hurtbox does.
const HURTBOX_RADIUS: float = 0.5
const HURTBOX_HEIGHT: float = 2.0


static func _add_hurtbox(a_piece: Node) -> void:
	_add_scene(a_piece, "hurtbox.tscn", "Hurtbox")
	var node := a_piece.get_node("Hurtbox/HurtboxShape") as CollisionShape3D
	var shape := _cylinder(HURTBOX_RADIUS)
	shape.height = HURTBOX_HEIGHT
	node.shape = shape
	node.position.y = HURTBOX_HEIGHT / 2.0


static func _add_scene(a_piece: Node, a_file: String, a_name: String) -> void:
	var node: Node = _scene(a_file)
	node.name = a_name
	a_piece.add_child(node)


static func _add_node(a_piece: Node, a_node: Node, a_name: String) -> void:
	a_node.name = a_name
	a_piece.add_child(a_node)


#region Abilities
static var _saved_abilities: Dictionary = {}
static var _fake_emissions: Array[String] = []


## An EMISSION (a shell; options `hitscan`, `hit_shape`): an `Entity` flying a two-phase
## `PhasedLocomotion` — a flight, then an
## impact that does not end on arrival — carrying a `Payload`. The smallest piece an ability
## can throw; nothing about what a shipped shell looks like or hits for.
static func emission(a_options: Dictionary = {}) -> Entity:
	var shell := Entity.new()
	shell.name = "FakeShell"
	shell.id = &"fake_shell"
	_add_node(shell, Ownership.new(), "Ownership")
	# A blast is a HitShape, which a hitscan emission does not carry (`hit_shape` false drops it).
	if bool(a_options.get("hit_shape", true)):
		var hit := CollisionShape3D.new()
		hit.shape = _cylinder(0.5)
		_add_node(shell, hit, "HitShape")
	var flight := EmissionPhase.new()
	flight.speed = 9.0
	flight.gravity_mps2 = 4.5
	flight.tracks_goal = true
	_add_node(shell, flight, "Flight")
	var impact := EmissionPhase.new()
	impact.ends_on_arrival = false
	impact.lifespan_seconds = 2.6
	impact.applies_payload = true
	_add_node(shell, impact, "Impact")
	_add_node(shell, PhasedLocomotion.new(), "Locomotion")
	var payload := Payload.new()
	payload.hitscan = bool(a_options.get("hitscan", false))
	_add_node(shell, payload, "Payload")
	_claim_for_packing(shell, shell)
	return shell


## A PackedScene of a fake emission, for code that takes a scene (a weapon's `projectile_scene`,
## a spawn event's `emission_scene`).
static func emission_scene(a_options: Dictionary = {}) -> PackedScene:
	return _packed(emission(a_options))


## Make ability `a_id` throw a fake emission, in addition to `a_entry`'s own keys.
static func install_emitting_ability(a_id: StringName, a_entry: Dictionary = {}) -> void:
	var path: String = "fake://emission/%s" % a_id
	AbilityCatalog._emission_cache[path] = _packed(emission())
	_fake_emissions.append(path)
	var entry: Dictionary = a_entry.duplicate()
	entry["emits"] = path
	install_ability(a_id, entry)


static func _packed(a_root: Node) -> PackedScene:
	var scene := PackedScene.new()
	scene.pack(a_root)
	a_root.free()
	return scene


## Define (or redefine) ability `a_id` in the catalog for this test: `a_entry` takes the keys of
## a `kind: AbilityDefinition` doc (`range`, `cast_by`, `passive`, `title` ...). Mechanics that
## name an ability by a code constant (`Bombard.ABILITY_ID`) read their numbers from here, so a
## test states them rather than depending on the shipped doc. Call `restore_abilities` in
## `after_each`.
static func install_ability(a_id: StringName, a_entry: Dictionary = {}) -> void:
	if not _saved_abilities.has(a_id):
		_saved_abilities[a_id] = AbilityCatalog._definitions.get(String(a_id))
	AbilityCatalog._definitions[String(a_id)] = AbilityDefinition.from_entry(a_id, a_entry)
	AbilityBinding._bindings = AbilityBinding._build()  # the ordnance buttons derive from the catalog


static func restore_abilities() -> void:
	for id: StringName in _saved_abilities:
		if _saved_abilities[id] == null:
			AbilityCatalog._definitions.erase(String(id))
		else:
			AbilityCatalog._definitions[String(id)] = _saved_abilities[id]
	_saved_abilities.clear()
	AbilityBinding._bindings = AbilityBinding._build()
	for path: String in _fake_emissions:
		AbilityCatalog._emission_cache.erase(path)
	_fake_emissions.clear()


#endregion


#region Tools, families and technology
## A tool (BUILD unless `a_context` says TRAIN) for a fake piece of id `a_type` (built from
## `a_options`, `id` filled in), with
## optional `a_variants` (piece ids registered with `install_families`).
static func tool(
	a_type: StringName,
	a_options: Dictionary = {},
	a_variants: Array[StringName] = [],
	a_context: int = ControlBinding.ControlContext.BUILD,
	a_producers: Array = [],
	a_context_grid: Vector2i = Vector2i(-1, -1)
) -> Tool:
	var options: Dictionary = a_options.duplicate()
	options["id"] = a_type
	# Row 1 of its card, never the producer-context row 0, whatever the grid does with it.
	var made := Tool.new(
		"command_tool_%s" % a_type,
		a_type,
		scene_of(options),
		String(a_type),
		Vector2i(0, 1),
		a_context,
		0
	)
	made.producers = a_producers
	made.context_grid = a_context_grid
	made.variants = a_variants
	return made


## What each registered name held before the test (null: nothing), so `restore_tools` puts the
## shipped entry back rather than deleting it.
static var _registered_tools: Dictionary = {}


## Make `a_tool` findable by name and id (`Tool.for_name` / `Tool.for_id`), for code that looks
## a tool up rather than being handed one. `restore_tools` takes every such tool out again.
static func register_tool(a_tool: Tool) -> Tool:
	if not _registered_tools.has(a_tool.command_name):
		_registered_tools[a_tool.command_name] = Tool.command_tool_map.get(a_tool.command_name)
	Tool.command_tool_map[a_tool.command_name] = a_tool
	Tool._by_id_cache = {}
	return a_tool


static func restore_tools() -> void:
	for name: String in _registered_tools:
		if _registered_tools[name] == null:
			Tool.command_tool_map.erase(name)
		else:
			Tool.command_tool_map[name] = _registered_tools[name]
	_registered_tools.clear()
	Tool._by_id_cache = {}


## Replace `PieceFamilies`' table with the pieces named in `a_entries`, each
## `{id, family, footprint: Vector2i, options: Dictionary}`. The scene a variant tool places is
## `scene_of(options)`. Call `restore_families` in `after_each`.
static func install_families(a_entries: Array[Dictionary]) -> void:
	var table := PieceFamilies.Table.new()
	for entry: Dictionary in a_entries:
		var template := _FakeTemplate.new()
		template.id = entry["id"]
		template.family = entry.get("family", &"fake_family")
		template.title = String(entry["id"])
		template.footprint = entry.get("footprint", Vector2i(1, 1))
		template.hp = float(entry.get("hp", 100.0))
		template.energy_cost = int(entry.get("energy_cost", 0))
		template.build_time_ticks = int(entry.get("build_time_ticks", 30))
		template.infrastructure = int(entry.get("infrastructure", 0))
		var options: Dictionary = (entry.get("options", {}) as Dictionary).duplicate()
		options["id"] = template.id
		options["structure"] = true
		if template.infrastructure != 0:
			options["infrastructure"] = template.infrastructure
		options["dimensions"] = template.footprint
		template.scene = scene_of(options)
		table.templates[template.id] = template
		var members: Array = table.members.get(template.family, [])
		members.append(template.id)
		table.members[template.family] = members
	PieceFamilies._table = table


## Put `PieceFamilies` back to reading the shipped table (on its next use).
static func restore_families() -> void:
	PieceFamilies._table = null


## A `TechnologySpec` with nothing to pay and nothing required unless a test says so.
static func tech(
	a_energy: int = 0,
	a_infrastructure: int = 0,
	a_dominion: int = 0,
	a_ticks: int = 30,
	a_requires: Array = []
) -> TechnologySpec:
	return TechnologySpec.new(a_energy, a_infrastructure, a_dominion, a_ticks, a_requires)


## A `PieceFamilies.Template` that hands back a scene built in memory, not one loaded by path.
class _FakeTemplate:
	extends PieceFamilies.Template
	var scene: PackedScene

	func load_scene() -> PackedScene:
		return scene
#endregion
