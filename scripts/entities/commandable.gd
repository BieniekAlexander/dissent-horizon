class_name Commandable
extends Entity

## Commandable — the unified base for entities that participate in the command
## system. After the Stage D collapse, both "units" and "structures" are just
## Commandables with different component bags and different group memberships.
##
## - is_in_group("unit") replaces the old `is Unit` check
## - is_in_group("structure") replaces the old `is Structure` check
##
## The group memberships are declared in unit.tscn and structure.tscn rather
## than in code, so behavior that varies between units and structures can be
## gated by `is_in_group(...)` without referencing class names that no longer
## exist.

@onready var command_receiver: CommandReceiver = CommandReceiver.new()

## Component references — all optional. Entity declares `ownership` and
## `movement`; Commandable adds `selectable`, `production`, `resource_provider`.
@onready var selectable: Selectable = $Selectable
@onready var production: Production = get_node_or_null("Production") as Production
@onready var resource_provider: ResourceProvider = get_node_or_null("ResourceProvider") as ResourceProvider
@onready var ore_extractor: OreExtractor = get_node_or_null("OreExtractor") as OreExtractor
@onready var dominion_generator: DominionGenerator = get_node_or_null("DominionGenerator") as DominionGenerator
@onready var shelter: Shelter = get_node_or_null("Shelter") as Shelter

var _command: Command:
	get: return command_receiver._command
	set(value): command_receiver._command = value


func current_command() -> Command:
	return command_receiver._command

func get_command_chain() -> Array[Command]:
	return command_receiver.get_command_chain()

func has_command() -> bool:
	return current_command() != null

func clear_command() -> void:
	update_commands(null)

@onready var hpBarFill: Sprite3D = $HPBar/HPBarFill
@onready var _debug_label: Label3D = get_node_or_null("DebugLabel") as Label3D
var _attack_duration: int = 0

### STRUCTURE-FLAVORED STATE (gated on is_in_group("structure"))
## These were on Structure before the collapse. Kept on Commandable so the
## scene script can stay generic; readers gate on group membership or on the
## presence of the component that exposes the related behavior (Production,
## ResourceProvider).
@onready var build_progress: float = 1
var map_cells: Set:
	get: return map.structure_cell_map.get(self, null) if map != null else null

### GRID PLACEMENT (statics — used by build.gd and other commands)
## These were Structure.<method> before the collapse. A future GridUtils
## module is the right home, but moving them onto Commandable keeps the
## existing `Structure.get_arrangement_cells(...)` call shape working as
## `Commandable.get_arrangement_cells(...)`.
static func get_grid_coordinates(a_center: Vector2i, a_dimensions) -> Array:
	var ret: Array = []
	var ox: int = (a_dimensions.x - 1) / 2
	var oy: int = (a_dimensions.y - 1) / 2
	for w in range(a_dimensions.x):
		for h in range(a_dimensions.y):
			ret.append(Vector2(a_center.x - ox + w, a_center.y - oy + h))
	return ret

static func get_arrangement_cells(
	a_map: Map,
	a_point: Vector2,
	a_dimensions: Vector2i
) -> Set:
	var center_coords: Vector2i = a_map.world_to_grid(a_point)
	var neighbor_coordinates = get_grid_coordinates(center_coords, a_dimensions)

	if neighbor_coordinates.any(
		func(c: Vector2i): return not a_map.grid_coordinates_in_bounds(c)
	):
		return Set.Empty
	else:
		return Set.new(
			neighbor_coordinates.map(
				func(coords): return a_map.cell_grid[coords.x][coords.y]
			)
		)

## True iff every cell of the structure's footprint is in-bounds, unoccupied,
## and perfectly flat. The clicked world position is treated as the footprint
## centre, matching how add_structure places the building.
static func valid_placement(a_command_message: CommandMessage, a_dimensions: Vector2i) -> bool:
	var placement_map: Map = a_command_message.map
	if placement_map == null:
		return false
	var origin: Vector2i = placement_map.world_to_grid(a_command_message.xz_position)
	for coords in get_grid_coordinates(origin, a_dimensions):
		var cell := Vector2i(coords)
		if not placement_map.grid_coordinates_in_bounds(cell):
			return false
		if placement_map.cell_grid[cell.x][cell.y] != null:
			return false
		if not placement_map.terrain_grid.is_flat(cell):
			return false
	return true

### WEAPON
## Default weapon patterns for unit-grouped commandables. Structures default to
## no patterns. Subclasses (e.g. Vanguard) override get_weapon_evaluation_patterns
## as an instance method to provide custom weapons.
func get_aggro_near_position() -> Command:
	var is_bunker: bool = shelter != null and shelter.bunker and shelter.garrisoned_count() > 0
	if aggro_range_shape == null or (weapon_inventory == null and not is_bunker):
		return null

	var aggro_query := PhysicsShapeQueryParameters3D.new()
	aggro_query.shape = aggro_range_shape.shape
	aggro_query.transform = aggro_range_shape.global_transform
	aggro_query.collision_mask = CollisionLayers.Layer.TARGETABLE
	aggro_query.exclude = [self]

	var vs = get_world_3d().direct_space_state.intersect_shape(aggro_query, 10).map(
		func(r): return r["collider"]
	)
	var vs2 = vs.filter(func(t): return t is Commandable and (
		(weapon_inventory != null and weapon_inventory.weapon_for_target(t) != null)
		or (is_bunker and shelter.any_garrison_can_target(t))
	))
	var vs3 = vs2.filter(
		func(t): return t.commander_id > 0 and t.commander_id != commander_id
	)
	var potential_targets: Array = AU.sort_on_key(
		func(c: Commandable): return global_position.distance_squared_to(c.global_position),
		vs3
	)

	return (
		Attack.new(CommandMessage.new(map, potential_targets[0], null))
		if not potential_targets.is_empty()
		else null
	)

func _ready() -> void:
	super()
	attributes = Set.new(attributes_list)
	command_receiver.initialize(self)

	# Wire Movement → physics handler for unit-shaped entities. Structures
	# typically have no Movement component, so movement is null and this is
	# a no-op for them.
	if movement != null:
		movement.velocity_ready.connect(_on_velocity_computed)
		# Match the RVO avoidance radius to this unit's movement footprint so
		# agents space themselves correctly during group moves.
		movement.set_agent_radius(bounding_radius(CollisionLayers.Layer.MOVEMENT_OBSTRUCTION))
		# NOTE: avoidance team is configured in _on_commander_changed, not here.
		# During initialize() add_child() (→ _ready) runs BEFORE the commander is
		# assigned, so `commander` is null at this point; the team must be set
		# when ownership is actually established.

func _on_commander_changed(old_commander: Commander, new_commander: Commander) -> void:
	super(old_commander, new_commander)

	# Configure RVO avoidance team whenever ownership is established/changes. This
	# is the first point at which the commander is known for dynamically-spawned
	# units (initialize() assigns the commander after add_child/_ready), so this
	# is what actually turns avoidance on — without it the agent keeps its
	# scene-default avoidance_layers/mask of 0 and avoids nothing.
	if movement != null and new_commander != null:
		movement.set_avoidance_team(new_commander.id)

	if not is_in_group("structure"):
		return
	if old_commander != null:
		old_commander.remove_structure(self)
		if resource_provider != null:
			resource_provider.remove_from(old_commander)
	if new_commander != null:
		new_commander.add_structure(self)
		if resource_provider != null:
			resource_provider.apply_to(new_commander)

func initialize(a_map: Map, a_commander: Commander):
	super(a_map, a_commander)
	command_receiver.initialize(self)
	# Structure registration is handled by _on_commander_changed, which fires
	# from Entity._ready() when Ownership migrates the pre-tree _commander value.

func receive_damage(attacker: Commandable, amount: float) -> void:
	# Being attacked breaks stealth: force the timed UNSTEALTHED window.
	if stealth != null:
		stealth.unstealth()
	command_receiver.receive_damage(attacker, amount)
	if defense != null and defense.hp > 0 and command_receiver.is_idle() and attacker != null:
		var attack_cmd := _get_vision_range_attack(attacker)
		if attack_cmd != null:
			update_commands(attack_cmd)

## Returns an Attack command targeting `attacker` if it is within VisionRange and
## is a valid enemy, otherwise null.
func _get_vision_range_attack(attacker: Commandable) -> Command:
	if vision_range_shape == null:
		return null
	if attacker.commander_id == 0 or attacker.commander_id == commander_id:
		return null
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = vision_range_shape.shape
	params.transform = vision_range_shape.global_transform
	params.collision_mask = CollisionLayers.Layer.TARGETABLE
	params.exclude = [self]
	var potential_targets: Array = get_world_3d().direct_space_state.intersect_shape(params, 20)
	for hit in potential_targets:
		if hit["collider"] == attacker:
			return Attack.new(CommandMessage.new(map, attacker, null))
	return null

func _process(_delta: float) -> void:
	if Engine.is_editor_hint(): return
	var sprite: Sprite3D = get_node_or_null("Sprite") as Sprite3D

	# HP bar (visible while damaged or selected)
	$HPBar.visible = defense != null and (defense.hp < defense.hp_max or selectable.is_selected())
	if hpBarFill.visible:
		hpBarFill.scale.x = defense.hp / defense.hp_max
		var half_w := hpBarFill.texture.get_width() * hpBarFill.pixel_size / 2.0
		hpBarFill.position.x = -half_w * (1.0 - hpBarFill.scale.x)

	# Movement-driven sprite facing + animation frames. Was Unit._process.
	if movement != null and sprite != null:
		if velocity.x > 0:
			sprite.flip_h = true
		elif velocity.x < 0:
			sprite.flip_h = false
		elif velocity.x == 0 and has_command():
			sprite.flip_h = current_command().message.position.x > global_position.x

		# NOTE hardcoding pattern preserved from Unit — Sentry uses 3 hframes.
		# A future SpriteAnimation component should own this.
		if sprite.hframes > 1:
			if _attack_duration > 0 and attack_timer == _attack_duration:
				sprite.frame = 2
			elif current_command() is Attack:
				sprite.frame = 1
			else:
				sprite.frame = 0

	# Debug label: show active command name while debug_info is held.
	if _debug_label != null:
		var show_debug := Input.is_action_pressed("debug_info")
		_debug_label.visible = show_debug
		if show_debug:
			_debug_label.text = current_command().get_script().get_global_name() if has_command() else "NULL"

	# Production-driven build progress alpha + train bar. Was Structure._process.
	if production != null:
		if sprite != null:
			sprite.modulate.a = build_progress
		production.update_bar(scale.x)

	# Stealth visibility (driven by Stealth.state). The pulsing partial alpha is
	# the "partially visible" cue; full alpha = fully visible; zero = unseen.
	# • STEALTHED   — owner sees the faint pulse; enemies see nothing (HP bar hidden).
	# • REVEALED    — faint pulse for everyone (owner and enemies).
	# • UNSTEALTHED — fully visible to everyone (restored each frame so the
	#                 transition out of stealth snaps back cleanly).
	if stealth != null and sprite != null:
		var pulse_alpha: float = 0.3 + .1 * sin(Engine.get_physics_frames() / 5.)
		match stealth.state:
			Stealth.State.UNSTEALTHED:
				sprite.modulate.a = 1.0
			Stealth.State.REVEALED:
				sprite.modulate.a = pulse_alpha
			Stealth.State.STEALTHED:
				if commander_id == RTSController.PLAYER_COMMANDER_ID:
					sprite.modulate.a = pulse_alpha
				else:
					sprite.modulate.a = 0.0
					$HPBar.visible = false

func _on_velocity_computed(a_velocity: Vector3) -> void:
	# a_velocity is the RVO avoidance-adjusted velocity from the NavigationAgent3D.
	# We simply apply it; same-team avoidance keeps units from overlapping, so we
	# no longer cancel commands on contact — the agents steer around each other
	# instead of giving up when they touch.
	velocity = a_velocity

	if velocity != Vector3.ZERO:
		move_and_slide()

	# Snap Y to terrain after each move so height tracks the final XZ this tick,
	# not the XZ from before the move (which is what _physics_process saw).
	if map != null:
		global_position.y = map.terrain_height_at(VU.inXZ(global_position)) + movement.height_offset()

func _update_state() -> void:
	if defense != null and defense.hp <= 0:
		_on_death()
		return

	if attack_timer > 0:
		attack_timer -= 1

	if command_receiver.is_idle():
		var aggro_cmd := get_aggro_near_position()
		if aggro_cmd != null:
			update_commands(aggro_cmd)

	command_receiver._update_state()

	# Command processing above may remove this unit from the tree mid-tick (e.g.
	# garrisoning into a Shelter); the remaining per-tick work touches world/
	# physics state that is invalid while orphaned, so stop here.
	if not is_inside_tree():
		return

	# Bunker firing: when this shelter-owner has an active Attack command and
	# garrisoned units carry matching weapons, fire those weapons each tick from
	# this entity's world position. Runs independently of the owner's own weapon
	# so a structure with no weapon_inventory can still provide fire support.
	if shelter != null and shelter.bunker and shelter.garrisoned_count() > 0:
		var active_cmd := current_command()
		if active_cmd is Attack and is_instance_valid(active_cmd.message.target):
			shelter.tick_bunker_fire(self, active_cmd.message.target)

	# Per-tick production. No-op for non-producing entities.
	if production != null:
		production.tick()
	if ore_extractor != null:
		ore_extractor.tick()
	if dominion_generator != null:
		dominion_generator.tick()

	# Detection: reveal enemy stealth units within DetectionRange this tick.
	if detection_range != null:
		_detect_stealthed_units()
	# Stealth: advance the unstealthing countdown on this entity.
	if stealth != null:
		stealth.tick()

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint(): return
	_update_state()
	# A command fulfilled during _update_state() (e.g. garrisoning into a
	# Shelter) may remove this unit from the tree mid-tick; touching
	# global_position while orphaned warns, so skip the rest of the tick.
	if not is_inside_tree(): return
	# Keep units glued to terrain height each tick.  The navmesh is 3D (built
	# from HeightMapShape3D data) but the velocity computation zeroes Y to keep
	# avoidance stable, so Y tracking must happen here instead.
	if movement != null and map != null:
		global_position.y = map.terrain_height_at(VU.inXZ(global_position)) + movement.height_offset()

func update_commands(a_commands: Variant, add_to_queue: bool = false, prepend: bool = false) -> void:
	command_receiver.update_commands(a_commands, add_to_queue, prepend)

func load_destination(command: Command) -> void:
	command_receiver.load_destination(command)

func _process_commands() -> void:
	# Structures route Train and Command (rally) into the Production component.
	# Everything else falls through to CommandReceiver's default handling.
	if production != null and has_command():
		var current: Command = current_command()
		if current.get_script() == Command:
			production.set_rally(current)
			clear_command()
			return
		elif current is Train:
			if commander.has_resources_for(current.message.tool.type):
				production.enqueue(
					commander.technology_mapping[current.message.tool.type].creation_time,
					current.message.tool.packed_scene
				)
				commander.use_resources_for(current.message.tool.type)
			clear_command()
			return
	command_receiver._process_commands()

## Query the STEALTH collision layer within DetectionRange and stamp reveal()
## on every enemy entity found.  Uses a targeted physics query so only
## entities that opted into the STEALTH layer (i.e. those with a Stealth node)
## are considered.
func _detect_stealthed_units() -> void:
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = detection_range.shape
	params.transform = detection_range.global_transform
	params.collision_mask = CollisionLayers.Layer.STEALTH
	params.exclude = [self]

	for result: Dictionary in get_world_3d().direct_space_state.intersect_shape(params, 20):
		var target := result["collider"] as Entity
		if target == null or target.stealth == null:
			continue
		# Only reveal enemies — neutral (id 0) and own units are skipped.
		if target.commander_id == 0 or target.commander_id == commander_id:
			continue
		target.stealth.reveal()


func _on_death() -> void:
	# Structure-flavored teardown.
	if is_in_group("structure"):
		if commander != null:
			commander.remove_structure(self)
			if resource_provider != null:
				resource_provider.remove_from(commander)
		map.remove_structure(self)
	super()
