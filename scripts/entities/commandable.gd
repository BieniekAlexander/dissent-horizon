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
## `selectable`, and `target_body`; Commandable adds `production` and the
## command/combat machinery below.
## NavigationObstacle3D used for cross-team one-sided avoidance (see
## AvoidanceAgent3D for the bit-layout). Enabled and sized in _ready for units
## only (movement != null); layers are set in _on_commander_changed.
@onready var _avoidance_obstacle: NavigationObstacle3D = $AvoidanceObstacle
@onready var production: Production = get_node_or_null("Production") as Production

## Area3D used for crush detection (see _tick_crush). Its CollisionShape3D's shape is
## mirrored from the root's own collider in _ready, same as TargetBody's shape mirror
## in Entity._ready, so it matches each faction scene's actual footprint override.
@onready var _crush_area: Area3D = get_node_or_null("CrushArea") as Area3D

## Vigor (the "power" resource) this commandable contributes to its commander —
## the old ResourceProvider component, folded up into Commandable. Defaults to 0/0;
## structure scenes override (a vigor provider sets vigor_provided, a unit-producing
## structure sets vigor_required). Registered/unregistered with the commander on
## ownership change and on death (see _on_commander_changed / _on_death).
@export var vigor_provided: int = 0
@export var vigor_required: int = 0

@onready var ore_extractor: OreExtractor = get_node_or_null("OreExtractor") as OreExtractor
@onready var dominion_generator: DominionGenerator = get_node_or_null("DominionGenerator") as DominionGenerator
@onready var garrison: Garrison = get_node_or_null("Garrison") as Garrison
@onready var interactor: Interactor = get_node_or_null("Interactor") as Interactor
@onready var veterancy: Veterancy = $Veterancy

## True when the player can currently perceive this commandable — fog pixel is
## clear AND the unit is not stealthed. Written by fog.gd each physics tick for
## non-player entities; always meaningless for player-owned units (the player
## always knows where their own units are, so callers gate on commander_id first).
## Scoped to the player for now; TODO: promote to a per-commander map.
var in_sight_range: bool = false

## Whether commander [viewer_commander_id] can currently perceive this commandable:
## its fog pixel is clear for that commander AND this commandable is not stealthed.
## Unlike in_sight_range (which only tracks the single active/spectated commander),
## this looks up the viewer's own Fog instance directly, so it's correct for bots
## reasoning about their own vision regardless of which commander is being spectated.
func is_visible_to(viewer_commander_id: int) -> bool:
	if stealth != null and stealth.state == Stealth.State.STEALTHED:
		return false
	var fog: Fog = Fog._fogs_by_commander.get(viewer_commander_id)
	if fog == null:
		return true
	return fog.fog_clear_at(VU.inXZ(global_position))

var _command: MoveCommand:
	get: return command_receiver._command
	set(value): command_receiver._command = value

@onready var hpBarFill: Sprite3D = $HPBar/HPBarFill
@onready var _debug_label: Label3D = get_node_or_null("DebugLabel") as Label3D
#endregion

#region Command interface
func current_command() -> MoveCommand:
	return command_receiver._command

func get_command_chain() -> Array[MoveCommand]:
	return command_receiver.get_command_chain()

func has_command() -> bool:
	return current_command() != null

func clear_command() -> void:
	update_commands(null)

func update_commands(a_commands: Variant, add_to_queue: bool = false, prepend: bool = false) -> void:
	if not add_to_queue:
		# Notify any units waiting to garrison that the host is changing course.
		if garrison != null and not garrison._pending_garrison_units.is_empty():
			garrison.cancel_pending_garrison()
		# If the host is grounded (garrison landing or Land command) and receives a
		# new command that requires movement, lift off so it can execute it.
		# Commands that handle their own landing (e.g. Evacuate) return false from
		# should_move and must not trigger a take-off here.
		if movement != null and movement.mode == Movement.Mode.HOVERING:
			var first_cmd: MoveCommand = null
			if a_commands is MoveCommand:
				first_cmd = a_commands
			elif a_commands is Array and not (a_commands as Array).is_empty():
				first_cmd = (a_commands as Array)[0]
			if movement.is_grounded_temp():
				if first_cmd != null and first_cmd.should_move(self):
					movement.take_off_for_movement()
			elif movement.is_pending_land():
				movement.cancel_pending_land()
	command_receiver.update_commands(a_commands, add_to_queue, prepend)

func load_destination(command: MoveCommand) -> void:
	command_receiver.load_destination(command)
#endregion

#region Rally
## True when units produced or released by this commandable (Production
## training a unit, or Garrison evacuating occupants) should be given an
## initial destination to move toward. Covers structures that train units and
## any commandable — structure or mobile unit — that can hold occupants in a
## Garrison (e.g. a transport).
func can_rally() -> bool:
	return production != null or garrison != null

## Destination held by a stationary can_rally() commandable (movement ==
## null), set by intercepting a bare MoveCommand in _process_commands (see
## there). Meaningless for mobile commandables, which share their own active
## movement instead — see rally_destination.
var rally_point: MoveCommand = null

func set_rally(command: MoveCommand) -> void:
	rally_point = command

## The command a unit produced or released by this commandable should inherit
## as its next order, or null for "no forced destination". A mobile
## commandable (movement != null) hands off its own active movement — so e.g.
## a transport that's destroyed mid-move passes its heading to its evacuated
## passengers — excluding commands that don't represent motion (should_move()
## == false, e.g. Evacuate itself). A stationary commandable (a structure) has
## no movement order of its own to share, so it uses rally_point instead.
func rally_destination() -> MoveCommand:
	if movement == null:
		return rally_point
	var current: MoveCommand = current_command()
	if current != null and current.should_move(self):
		return current
	return null
#endregion

#region Structure state
## These were on Structure before the collapse. Kept on Commandable so the
## scene script can stay generic; readers gate on group membership or on the
## presence of the component that exposes the related behavior (e.g. Production).
var build_progress: float = 1.
## Construction progress a freshly-placed structure starts at (see begin_construction).
const INITIAL_BUILD_PROGRESS: float = 0.1
## Fraction of max_health a freshly-placed structure starts with.
const INITIAL_HEALTH_FACTOR: float = 0.1
## Emitted whenever build_progress changes, so visuals (construction alpha / train
## bar) could update reactively rather than polling.
signal build_progress_changed(progress: float)
## True when this entity is fully constructed. Units are always built; structures
## become built once build_progress reaches 1.0 (set to INITIAL_BUILD_PROGRESS by
## Build.fulfill_action, ticked up by Repair, defaulting to 1.0 for editor-placed
## structures).
var is_built: bool:
	get: return not is_in_group("structure") or build_progress >= 1.0

## Units currently registered as active builders of this structure.
var _active_builders: Array[Commandable] = []

## Mark a freshly-instantiated structure as just-started construction. Call before
## add_entity so _ready → add_structure → proc_technology see is_built = false.
## HP is initialized to INITIAL_HEALTH_FACTOR * hp_max in Commandable._ready(),
## after Defense._ready() has set it to hp_max, so we don't touch it here.
func begin_construction() -> void:
	build_progress = INITIAL_BUILD_PROGRESS
	build_progress_changed.emit(build_progress)

## Advance construction by `delta`, clamped at 1.0 (fully built). Returns true on
## the single tick construction first reaches completion, so callers run their
## one-time finish logic (tech re-eval, builder XP) exactly once.
## Also scales hp proportionally so health tracks build progress during construction
## (Task 4): each unit of build progress adds delta * hp_max * (1 - INITIAL_HEALTH_FACTOR).
func advance_build_progress(delta: float) -> bool:
	var was_built: bool = build_progress >= 1.0
	var old_progress: float = build_progress
	build_progress = minf(build_progress + delta, 1.0)
	var actual_delta: float = build_progress - old_progress
	if defense != null and actual_delta > 0.0 and not was_built:
		defense.hp = minf(
			defense.hp + actual_delta * defense.hp_max * (1.0 - INITIAL_HEALTH_FACTOR) / (1.0 - INITIAL_BUILD_PROGRESS),
			defense.hp_max
		)
		defense.hp_changed.emit(defense.hp, defense.hp_max)
	build_progress_changed.emit(build_progress)
	return not was_built and build_progress >= 1.0

## Register `unit` as an active builder of this structure. Connects to tree_exiting
## so a dead or removed builder is automatically unregistered. Safe to call multiple
## times with the same unit (idempotent).
func register_builder(unit: Commandable) -> void:
	if _active_builders.has(unit):
		return
	_active_builders.append(unit)
	unit.tree_exiting.connect(unregister_builder.bind(unit), CONNECT_ONE_SHOT)

## Remove `unit` from the active-builder list. Called explicitly when a Repair
## command ends, and automatically via tree_exiting when a builder dies.
func unregister_builder(unit: Commandable) -> void:
	_active_builders.erase(unit)

## Per-builder-per-tick build progress increment consistent with the AOE2 formula:
##   effective_build_time = 3 * base_build_time / (n + 2)
## Each of n builders calls this each tick, so total progress per tick = 1/effective_build_time.
func effective_build_increment() -> float:
	var n: int = max(1, _active_builders.size())
	var spec: TechnologySpec = commander.technology_mapping.get(type) if commander != null else null
	var base_build_time: int = spec.creation_time if spec != null else 600
	return float(n + 2) / (3.0 * float(base_build_time) * float(n))
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
## Widen Entity.is_armed(): a Commandable also counts as armed while it is a bunker
## garrison ACTIVELY holding an occupant that carries a weapon, since bunker fire
## propagates that occupant's shots (making e.g. a garrisoned shelter a COMBAT_STRUCTURES
## target). Capability alone — an empty bunker — does not qualify.
func is_armed() -> bool:
	return super() or (garrison != null and garrison.bunker and garrison.has_armed_occupants())

## Default weapon patterns for unit-grouped commandables. Structures default to
## no patterns. Subclasses (e.g. Vanguard) override get_weapon_evaluation_patterns
## as an instance method to provide custom weapons.
func get_aggro_near_position(a_center: Variant = null, a_shape: CollisionShape3D = null, \
		min_target_priority: TargetPriority = TargetPriority.NON_COMBAT_UNITS) -> MoveCommand:
	var is_bunker: bool = garrison != null and garrison.bunker and garrison.garrisoned_count() > 0
	if aggro_range_shape == null or (weapon_inventory == null and not is_bunker):
		return null

	var shape_source: CollisionShape3D = a_shape if a_shape != null else aggro_range_shape
	var center: Vector3
	if a_center == null:
		center = aggro_range_shape.global_transform.origin
	elif a_center is Node3D:
		center = a_center.global_position
	else:
		center = a_center as Vector3

	var vs: Array[Entity] = SU.entities_in_aggro_shape(
		get_world_3d(), shape_source, center, target_body, 10
	).filter(func(t: Entity) -> bool:
		# An attackable enemy this actor (or its garrison, when a bunker) can fire on,
		# ranked at least as important as the command's minimum target priority.
		if not (t is Commandable and (t as Commandable).defense != null):
			return false
		if t.target_priority > min_target_priority:
			return false
		if not is_enemy_of(t):
			return false
		if not (t as Commandable).is_visible_to(commander_id):
			return false
		if weapon_inventory != null and weapon_inventory.weapon_for_target(t) != null:
			return true
		return is_bunker and garrison.any_garrison_can_target(t)
	)

	# Prefer higher-priority targets (lower TargetPriority value), breaking ties by the
	# nearest so a unit still engages the closest of the most important targets.
	var self_xz: Vector2 = VU.inXZ(global_position)
	vs.sort_custom(func(a: Entity, b: Entity) -> bool:
		if a.target_priority != b.target_priority:
			return a.target_priority < b.target_priority
		return self_xz.distance_squared_to(VU.inXZ(a.global_position)) \
			< self_xz.distance_squared_to(VU.inXZ(b.global_position))
	)

	if vs.is_empty():
		return null
	var msg := CommandMessage.new(map, vs[0], null)
	msg.persist = false
	return Attack.new(msg)

func receive_damage(damage: Damage, from: Commandable = null) -> void:
	super(damage, from)
	# Being attacked breaks stealth: force the timed UNSTEALTHED window.
	if stealth != null:
		stealth.unstealth()
	# retaliation logic
	if defense != null and defense.hp > 0 and command_receiver.is_idle() and from != null:
		var attack_cmd: MoveCommand = _get_vision_range_attack(from)
		if attack_cmd != null:
			update_commands(attack_cmd)

## Returns an Attack command targeting `attacker` if it is within VisionRange and
## is a valid enemy and retaliator has a valid weapon, otherwise null.
func _get_vision_range_attack(attacker: Commandable) -> MoveCommand:
	# A garrisoned (or otherwise orphaned) unit is out of the scene tree, so get_world_3d()
	# is null and the shape query below would crash. It also can't act on a retaliation
	# target while inside a garrison, so bail out.
	if vision_range_shape == null or not is_inside_tree():
		return null
	if not is_enemy_of(attacker):
		return null
	if weapon_inventory==null or not weapon_inventory.has_weapons():
		return null
	var excludes: Array = [target_body.get_rid()] if target_body != null else []
	var potential_targets: Array[Entity] = SU.query_shape_for_entities(
		get_world_3d(), vision_range_shape.shape, vision_range_shape.global_transform,
		CollisionLayers.TARGETABLE_ANY, excludes, 20
	)
	for t in potential_targets:
		if t == attacker and weapon_inventory.weapon_for_target(attacker) != null:
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

	# Mirror the root's collision shape onto the crush-detection area's shape, so its
	# overlap test matches this entity's real footprint (MovementBody/Body is overridden
	# per faction scene — see e.g. vanguard.tscn — same pattern as TargetBody's mirror
	# in Entity._ready).
	if _crush_area != null and collider != null:
		(_crush_area.get_node("CrushShape") as CollisionShape3D).shape = collider.shape

	# Drive the HP-bar fill geometry off damage events rather than recomputing it
	# every frame. Visibility still depends on selection (see _process), but the
	# fill scale/offset only move when hp moves.
	if defense != null:
		defense.hp_changed.connect(_on_hp_changed)
		# Defense._ready() initializes hp to hp_max. For structures placed by
		# Build.fulfill_action (begin_construction called before _ready), override
		# hp to match the construction starting fraction (Task 4).
		if is_in_group("structure") and not is_built:
			defense.hp = defense.hp_max * INITIAL_HEALTH_FACTOR
		_on_hp_changed(defense.hp, defense.hp_max)

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
		old_commander.adjust_vigor(-vigor_required, -vigor_provided)
	if new_commander != null:
		new_commander.add_structure(self)
		new_commander.adjust_vigor(vigor_required, vigor_provided)

func initialize(a_map: Map, a_commander: Commander):
	super(a_map, a_commander)
	command_receiver.initialize(self)
	# `map` is now set (super assigned it), for both dynamically-spawned and
	# scene-placed units — unlike _on_commander_changed, which fires during _ready
	# (before initialize) for scene-placed units. Derive the unit's size class from
	# its MovementBody footprint and point the agent at the navmesh for that class.
	if movement != null and map != null:
		movement.configure_for_map(
			map,
			map.nav_manager,
			bounding_radius(CollisionLayers.Mask.MOVEMENT_OBSTRUCTION)
		)
	# Structure registration is handled by _on_commander_changed, which fires
	# from Entity._ready() when Ownership migrates the pre-tree _commander value.

## Push command state into the MeshVisual component: map the current situation
## to a high-level animation state. The animation call is a no-op until an
## AnimationTree is authored.
##
## Facing is NOT pushed here anymore. The root node's rotation.y is now the
## single source of truth for facing (Movement rotates it toward the direction
## of travel / aim — see Movement.get_facing, which treats +Z as the mesh's
## visual front), and MeshVisual is a child that inherits that rotation.
## Driving MeshVisual.face_direction as well would rotate the mesh a SECOND time
## on top of the root, compounding the two into a doubled, offset yaw that
## snaps for large turns.
func _drive_mesh_visual(mesh_visual: MeshVisual) -> void:
	var state: MeshVisual.AnimationState = MeshVisual.AnimationState.IDLE
	if has_command() and current_command() is Attack:
		state = MeshVisual.AnimationState.ATTACK
	elif movement != null and Vector2(velocity.x, velocity.z).length_squared() > 0.0001:
		state = MeshVisual.AnimationState.MOVE
	mesh_visual.set_animation_state(state)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint(): return
	var sprite: Sprite3D = get_node_or_null("Sprite") as Sprite3D

	# HP bar visibility (visible while damaged or selected). The fill geometry is
	# driven separately by _on_hp_changed, since it only moves when hp moves.
	$HPBar.visible = defense != null and (defense.hp < defense.hp_max or selectable.is_selected())

	# Movement-driven facing + animation state. MeshVisual (3D models) supersedes
	# the Sprite path (billboards); drive whichever this entity actually has.
	var mesh_visual := get_node_or_null("MeshVisual") as MeshVisual
	if mesh_visual != null:
		_drive_mesh_visual(mesh_visual)
	elif movement != null and sprite != null:
		if velocity.x > 0:
			sprite.flip_h = true
		elif velocity.x < 0:
			sprite.flip_h = false
		elif velocity.x == 0 and has_command():
			sprite.flip_h = current_command().message.position.x > global_position.x

		# NOTE hardcoding pattern preserved from Unit — Irregular uses 3 hframes.
		# A future SpriteAnimation component should own this.
		if sprite.hframes > 1:
			if false: # TODO revisit, get firing state from weapon
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

## Resize/offset the HP-bar fill to match the current hp fraction. Connected to
## Defense.hp_changed, so it runs only when hp actually changes.
func _on_hp_changed(a_hp: float, a_hp_max: float) -> void:
	if hpBarFill == null or a_hp_max <= 0:
		return
	hpBarFill.scale.x = a_hp / a_hp_max
	var half_w := hpBarFill.texture.get_width() * hpBarFill.pixel_size / 2.0
	hpBarFill.position.x = -half_w * (1.0 - hpBarFill.scale.x)

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

	if command_receiver.is_idle():
		var aggro_cmd := get_aggro_near_position()
		if aggro_cmd != null:
			update_commands(aggro_cmd)

	command_receiver._update_state()

	# A HOVERING garrison host with pending units descends to accept them once it
	# is idle (no active command). This fires both when already idle at the moment
	# intent is registered and when a movement command completes.
	if garrison != null and not garrison._pending_garrison_units.is_empty() \
			and movement != null and movement.mode == Movement.Mode.HOVERING \
			and command_receiver.is_idle():
		movement.land(Callable())

	# Command processing above may remove this unit from the tree mid-tick (e.g.
	# garrisoning into a Garrison); the remaining per-tick work touches world/
	# physics state that is invalid while orphaned, so stop here.
	if not is_inside_tree():
		return

	# Per-tick production. No-op for non-producing entities or unbuilt structures.
	if production != null and is_built:
		production.tick()
	if ore_extractor != null and is_built:
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
	# Garrison) may remove this unit from the tree mid-tick; touching
	# global_position while orphaned warns, so skip the rest of the tick.
	if not is_inside_tree(): return
	# Keep units glued to terrain height each tick.  The navmesh is 3D (built
	# from HeightMapShape3D data) but the velocity computation zeroes Y to keep
	# avoidance stable, so Y tracking must happen here instead.
	if movement != null and map != null:
		global_position.y = map.terrain_height_at(VU.inXZ(global_position)) + movement.height_offset()
	_update_crush_avoidance_exclusions()
	_tick_crush()

#region Crush
## Recompute which enemy obstacle channels (AvoidanceAgent3D.obstacle_bit) this unit's
## avoidance mask should ignore: any enemy commander with at least one nearby unit this
## unit can crush (Movement.can_crush) is walked through rather than detoured around.
## No-op without a GROUNDED_DIRECT Movement + AvoidanceAgent3D (avoidance_agent() is
## null for HOVERING/FLYING and for units without an AvoidanceAgent3D-backed nav agent).
## See the _crush_excluded_obstacles caveat on AvoidanceAgent3D: obstacle channels are
## per-commander, not per-unit, so this is a team-wide approximation.
func _update_crush_avoidance_exclusions() -> void:
	if movement == null or aggro_range_shape == null:
		return
	var agent: AvoidanceAgent3D = movement.avoidance_agent()
	if agent == null:
		return
	var nearby: Array[Entity] = SU.entities_in_aggro_shape(
		get_world_3d(), aggro_range_shape, global_position, target_body, 20
	)
	var excluded: int = 0
	for e: Entity in nearby:
		if not (e is Commandable) or not is_enemy_of(e):
			continue
		var enemy: Commandable = e as Commandable
		if enemy.movement != null and movement.can_crush(enemy.movement):
			excluded |= AvoidanceAgent3D.obstacle_bit(enemy.commander_id)
	agent.set_crush_excluded_obstacles(excluded)

## Instant-kill any enemy Commandable currently overlapping CrushArea that this unit's
## Movement.can_crush() clears — the "drive over the smaller unit" half of the crush
## mechanic (_update_crush_avoidance_exclusions above is the "don't detour around it"
## half). No-op without Movement or a CrushArea child.
func _tick_crush() -> void:
	if movement == null or _crush_area == null:
		return
	for body: Node in _crush_area.get_overlapping_bodies():
		var enemy := body as Commandable
		if enemy == null or enemy == self or not is_enemy_of(enemy):
			continue
		if enemy.movement == null or not movement.can_crush(enemy.movement):
			continue
		if enemy.defense != null and enemy.defense.hp > 0:
			enemy.defense.kill()
#endregion

func _process_commands() -> void:
	# A stationary can_rally() commandable routes a bare MoveCommand into its own
	# rally_point instead of moving (see rally_destination). Structures also
	# route Train into the Production component. Everything else falls through
	# to CommandReceiver's default handling.
	if has_command():
		var current: MoveCommand = current_command()
		if movement == null and can_rally() and current.get_script() == MoveCommand:
			set_rally(current)
			clear_command()
			return
		elif production != null and current is Train:
			if is_built and commander.has_resources_for(current.message.tool.type):
				production.enqueue(
					commander.technology_mapping[current.message.tool.type].creation_time,
					current.message.tool.packed_scene,
					current.message.tool.type
				)
				commander.use_resources_for(current.message.tool.type)
			clear_command()
			return
	command_receiver._process_commands()

func _on_death() -> void:
	# Return or kill garrisoned occupants before queue_free() voids the host's map
	# reference and orphans them permanently.
	if garrison != null and garrison.garrisoned_count() > 0:
		if garrison.preserve_occupants:
			garrison.evacuate(map)
		else:
			garrison.kill_occupants()
	# Return or free inventory occupants (e.g. abducted units in a stock truck or
	# internment camp). eject_to_scene clears the items array, so the Inventory
	# PREDELETE handler becomes a harmless no-op.
	if ability_inventory != null and ability_inventory.has_items():
		if ability_inventory.preserve_occupants:
			ability_inventory.eject_to_scene(global_position)
		else:
			ability_inventory.free_items()
	# Commander/economy teardown for owned structures. The grid teardown
	# (map.remove_structure) is handled in Entity._on_death via super().
	if is_in_group("structure") and commander != null:
		commander.remove_structure(self)
		commander.adjust_vigor(-vigor_required, -vigor_provided)
	super()
#endregion

#region Private helpers
## Query the STEALTH collision layer within DetectionRange and stamp reveal()
## on every enemy entity found.  Uses a targeted physics query so only
## entities that opted into the STEALTH layer (i.e. those with a Stealth node)
## are considered.
func _detect_stealthed_units() -> void:
	var targets: Array[Entity] = SU.query_shape_for_entities(
		get_world_3d(), detection_range.shape, detection_range.global_transform,
		CollisionLayers.Mask.STEALTH, [self], 20
	)
	for target in targets:
		if target.stealth == null:
			continue
		# Only reveal enemies — neutral (id 0) and own units are skipped.
		if not is_enemy_of(target):
			continue
		target.stealth.reveal()
#endregion
