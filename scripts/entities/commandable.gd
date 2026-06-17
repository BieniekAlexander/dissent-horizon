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

#region Properties
@onready var command_receiver: CommandReceiver = CommandReceiver.new()

## Component references — all optional. Entity declares `ownership`, `movement`,
## `selectable`, and `target_body`; Commandable adds `production`,
## `resource_provider`, and the command/combat machinery below.
## NavigationObstacle3D used for cross-team one-sided avoidance (see
## AvoidanceAgent3D for the bit-layout). Enabled and sized in _ready for units
## only (movement != null); layers are set in _on_commander_changed.
@onready var _avoidance_obstacle: NavigationObstacle3D = $AvoidanceObstacle
@onready var production: Production = get_node_or_null("Production") as Production
@onready var resource_provider: ResourceProvider = get_node_or_null("ResourceProvider") as ResourceProvider
@onready var ore_extractor: OreExtractor = get_node_or_null("OreExtractor") as OreExtractor
@onready var dominion_generator: DominionGenerator = get_node_or_null("DominionGenerator") as DominionGenerator
@onready var dominion_provider: DominionProvider = get_node_or_null("DominionProvider") as DominionProvider
@onready var garrison: Garrison = get_node_or_null("Garrison") as Garrison
@onready var interactor: Interactor = get_node_or_null("Interactor") as Interactor
@onready var veterancy: Veterancy = $Veterancy

## True when the player can currently perceive this commandable — fog pixel is
## clear AND the unit is not stealthed. Written by fog.gd each physics tick for
## non-player entities; always meaningless for player-owned units (the player
## always knows where their own units are, so callers gate on commander_id first).
## Scoped to the player for now; TODO: promote to a per-commander map.
var in_sight_range: bool = false

var _command: Command:
	get: return command_receiver._command
	set(value): command_receiver._command = value

@onready var hpBarFill: Sprite3D = $HPBar/HPBarFill
@onready var _debug_label: Label3D = get_node_or_null("DebugLabel") as Label3D
var _attack_duration: int = 0
#endregion

#region Command interface
func current_command() -> Command:
	return command_receiver._command

func get_command_chain() -> Array[Command]:
	return command_receiver.get_command_chain()

func has_command() -> bool:
	return current_command() != null

func clear_command() -> void:
	update_commands(null)

func update_commands(a_commands: Variant, add_to_queue: bool = false, prepend: bool = false) -> void:
	command_receiver.update_commands(a_commands, add_to_queue, prepend)

func load_destination(command: Command) -> void:
	command_receiver.load_destination(command)
#endregion

#region Structure state
## These were on Structure before the collapse. Kept on Commandable so the
## scene script can stay generic; readers gate on group membership or on the
## presence of the component that exposes the related behavior (Production,
## ResourceProvider).
var build_progress: float = 1.
## True when this entity is fully constructed. Units are always built; structures
## become built once build_progress reaches 1.0 (set to 0.1 by Build.fulfill_action,
## ticked up by Repair, defaulting to 1.0 for editor-placed structures).
var is_built: bool:
	get: return not is_in_group("structure") or build_progress >= 1.0
var map_cells: Set:
	get: return map.structure_cell_map.get(self, null) if map != null else null
#endregion

#region Grid placement

#region Static helpers
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
## valid_placement moved to Entity (any grid-occupying entity, incl. non-commandable
## structures like Deposit, can be placement-checked) — call Entity.valid_placement.
#endregion

#endregion

#region Combat
## Default weapon patterns for unit-grouped commandables. Structures default to
## no patterns. Subclasses (e.g. Vanguard) override get_weapon_evaluation_patterns
## as an instance method to provide custom weapons.
func get_aggro_near_position() -> Command:
	var is_bunker: bool = garrison != null and garrison.bunker and garrison.garrisoned_count() > 0
	if aggro_range_shape == null or (weapon_inventory == null and not is_bunker):
		return null

	var aggro_query := PhysicsShapeQueryParameters3D.new()
	aggro_query.shape = aggro_range_shape.shape
	aggro_query.transform = aggro_range_shape.global_transform
	aggro_query.collision_mask = CollisionLayers.Mask.TARGETABLE
	aggro_query.exclude = [target_body.get_rid()] if target_body != null else []

	var vs = get_world_3d().direct_space_state.intersect_shape(aggro_query, 10).map(
		func(r): return Entity.entity_from_collider(r["collider"])
	).filter(
		func(t): return weapon_inventory.weapon_for_target(t)!=null
	).filter(func(t): return t is Commandable and t.defense != null and (
		(weapon_inventory != null and weapon_inventory.weapon_for_target(t) != null)
		or (is_bunker and garrison.any_garrison_can_target(t))
	)).filter(
		func(t): return t.commander_id > 0 and t.commander_id != commander_id
	)
	
	var potential_targets: Array = AU.sort_on_key(
		func(c: Commandable): return global_position.distance_squared_to(c.global_position),
		vs
	)

	if potential_targets.is_empty():
		return null
	var msg := CommandMessage.new(map, potential_targets[0], null)
	# An idle aggro acquisition (no active command) persists: the unit pursues the
	# target to completion. Aggro acquired while already running a command (e.g.
	# AttackMove/Defend calling this) stays non-persistent, so it's abandoned once
	# the target leaves aggro range and the unit resumes its prior command.
	msg.persist = has_command()
	return Attack.new(msg)

func receive_damage(from: Commandable, amount: float) -> void:
	# Being attacked breaks stealth: force the timed UNSTEALTHED window.
	if stealth != null:
		stealth.unstealth()
	command_receiver.receive_damage(from, amount)
	
	# retaliation logic
	if defense != null and defense.hp > 0 and command_receiver.is_idle() and from != null:
		var attack_cmd := _get_vision_range_attack(from)
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
	params.collision_mask = CollisionLayers.Mask.TARGETABLE
	params.exclude = [target_body.get_rid()] if target_body != null else []
	var potential_targets: Array = get_world_3d().direct_space_state.intersect_shape(params, 20)
	for hit in potential_targets:
		if Entity.entity_from_collider(hit["collider"]) == attacker:
			return Attack.new(CommandMessage.new(map, attacker, null))
	return null
#endregion

#region Lifecycle
func _ready() -> void:
	super()
	# Establish the root's movement-collision layer now (map is still null, so this
	# resolves to MOVEMENT_OBSTRUCTION) — bounding_radius() below reads it, and it
	# runs before initialize() would otherwise set it. The TargetBody shape mirror
	# and STRUCTURE_BLOCKER layer are handled in Entity._ready (via super() above).
	refresh_movement_collision()
	attributes = Set.new(attributes_list)
	command_receiver.initialize(self)

	# Wire Movement → physics handler for unit-shaped entities. Structures
	# typically have no Movement component, so movement is null and this is
	# a no-op for them.
	if movement != null:
		movement.velocity_ready.connect(_on_velocity_computed)
		var _r: float = bounding_radius(CollisionLayers.Mask.MOVEMENT_OBSTRUCTION)
		movement.set_agent_radius(_r)
		# Size the obstacle to match the unit's footprint and hand the reference
		# to Movement so suppress/restore_avoidance_layers can silence it too.
		# avoidance_layers is set when ownership is established (see _on_commander_changed).
		_avoidance_obstacle.radius = _r
		_avoidance_obstacle.avoidance_enabled = true
		movement.avoidance_obstacle = _avoidance_obstacle
		# NOTE: avoidance team is configured in _on_commander_changed, not here.
		# During initialize() add_child() (→ _ready) runs BEFORE the commander is
		# assigned, so `commander` is null at this point; the team must be set
		# when ownership is actually established.

func _on_commander_changed(old_commander: Commander, new_commander: Commander) -> void:
	super(old_commander, new_commander)

	# Turn on RVO avoidance once ownership is established. This is the first point
	# at which the commander is known for dynamically-spawned units (initialize()
	# assigns the commander after add_child/_ready); without it the agent keeps
	# its scene-default avoidance_layers/mask of 0 and avoids nothing.
	# Also update the NavigationObstacle3D layer so enemies steer around this
	# unit one-sidedly (cross-team one-sided avoidance — see AvoidanceAgent3D).
	if movement != null and new_commander != null:
		movement.enable_avoidance(new_commander.id)
		_avoidance_obstacle.avoidance_layers = AvoidanceAgent3D.obstacle_bit(new_commander.id)

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
	# `map` is now set (super assigned it), for both dynamically-spawned and
	# scene-placed units — unlike _on_commander_changed, which fires during _ready
	# (before initialize) for scene-placed units. Derive the unit's size class from
	# its MovementBody footprint and point the agent at the navmesh for that class.
	if movement != null and map != null and map.nav_manager != null:
		movement.configure_for_map(
			map.nav_manager,
			bounding_radius(CollisionLayers.Mask.MOVEMENT_OBSTRUCTION)
		)
	# Structure registration is handled by _on_commander_changed, which fires
	# from Entity._ready() when Ownership migrates the pre-tree _commander value.

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

		# NOTE hardcoding pattern preserved from Unit — Irregular uses 3 hframes.
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
	# garrisoning into a Garrison); the remaining per-tick work touches world/
	# physics state that is invalid while orphaned, so stop here.
	if not is_inside_tree():
		return

	# Bunker firing: when this garrison-owner has an active Attack command and
	# garrisoned units carry matching weapons, fire those weapons each tick from
	# this entity's world position. Runs independently of the owner's own weapon
	# so a structure with no weapon_inventory can still provide fire support.
	if garrison != null and garrison.bunker and garrison.garrisoned_count() > 0:
		var active_cmd := current_command()
		if active_cmd is Attack and is_instance_valid(active_cmd.message.target):
			garrison.tick_bunker_fire(self, active_cmd.message.target)

	# Per-tick production. No-op for non-producing entities or unbuilt structures.
	if production != null and is_built:
		production.tick()
	if ore_extractor != null and is_built:
		ore_extractor.tick()
	if dominion_generator != null:
		dominion_generator.tick()
	if dominion_provider != null:
		dominion_provider.tick()

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
	# Garrison) may remove this unit from the tree mid-tick; touching
	# global_position while orphaned warns, so skip the rest of the tick.
	if not is_inside_tree(): return
	# Keep units glued to terrain height each tick.  The navmesh is 3D (built
	# from HeightMapShape3D data) but the velocity computation zeroes Y to keep
	# avoidance stable, so Y tracking must happen here instead.
	if movement != null and map != null:
		global_position.y = map.terrain_height_at(VU.inXZ(global_position)) + movement.height_offset()

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
			if is_built and commander.has_resources_for(current.message.tool.type):
				production.enqueue(
					commander.technology_mapping[current.message.tool.type].creation_time,
					current.message.tool.packed_scene
				)
				commander.use_resources_for(current.message.tool.type)
			clear_command()
			return
	command_receiver._process_commands()

func _on_death() -> void:
	# Commander/economy teardown for owned structures. The grid teardown
	# (map.remove_structure) is handled in Entity._on_death via super().
	if is_in_group("structure") and commander != null:
		commander.remove_structure(self)
		if resource_provider != null:
			resource_provider.remove_from(commander)
	super()
#endregion

#region Private helpers
## Query the STEALTH collision layer within DetectionRange and stamp reveal()
## on every enemy entity found.  Uses a targeted physics query so only
## entities that opted into the STEALTH layer (i.e. those with a Stealth node)
## are considered.
func _detect_stealthed_units() -> void:
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = detection_range.shape
	params.transform = detection_range.global_transform
	params.collision_mask = CollisionLayers.Mask.STEALTH
	params.exclude = [self]

	for result: Dictionary in get_world_3d().direct_space_state.intersect_shape(params, 20):
		var target := result["collider"] as Entity
		if target == null or target.stealth == null:
			continue
		# Only reveal enemies — neutral (id 0) and own units are skipped.
		if target.commander_id == 0 or target.commander_id == commander_id:
			continue
		target.stealth.reveal()
#endregion
