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

var _command: Command:
	get: return command_receiver._command
	set(value): command_receiver._command = value


func current_command() -> Command:
	return command_receiver._command

func has_command() -> bool:
	return current_command() != null

func clear_command() -> void:
	update_commands(null)

@onready var hpBarFill: Sprite3D = $HPBar/HPBarFill
@onready var _debug_label: Label3D = get_node_or_null("DebugLabel") as Label3D
var SHOT_DURATION: int = 2

### STRUCTURE-FLAVORED STATE (gated on is_in_group("structure"))
## These were on Structure before the collapse. Kept on Commandable so the
## scene script can stay generic; readers gate on group membership or on the
## presence of the component that exposes the related behavior (Production,
## ResourceProvider).
@onready var build_progress: float = 1
var width: int = 1
var length: int = 1
var map_cells: Set:
	get: return map.structure_cell_map.get(self, null) if map != null else null

### GRID PLACEMENT (statics — used by build.gd and other commands)
## These were Structure.<method> before the collapse. A future GridUtils
## module is the right home, but moving them onto Commandable keeps the
## existing `Structure.get_arrangement_cells(...)` call shape working as
## `Commandable.get_arrangement_cells(...)`.
static func get_grid_coordinates(a_center: Vector2i, a_dimensions) -> Array:
	var ret: Array = []
	for w in range(a_dimensions.x):
		for h in range(a_dimensions.y):
			ret.append(Vector2(a_center.x + w, a_center.y + h))
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

static func valid_placement(_a_command_message: CommandMessage, _a_dimensions: Vector2i) -> bool:
	push_error("TODO")
	return true

### WEAPON
## Default weapon patterns for unit-grouped commandables. Structures default to
## no patterns. Subclasses (e.g. Vanguard) override get_weapon_evaluation_patterns
## as an instance method to provide custom weapons.
func get_aggro_near_position() -> Command:
	if aggro_range_shape == null:
		return null
	
	var aggro_query := PhysicsShapeQueryParameters3D.new()
	aggro_query.shape = aggro_range_shape.shape
	aggro_query.transform = aggro_range_shape.global_transform
	aggro_query.collision_mask = CollisionLayers.Layer.BODY
	aggro_query.exclude = [self]
	
	var weapon_patterns: Array = WeaponPatternsRegistry.for_type(type)
	var vs = get_world_3d().direct_space_state.intersect_shape(aggro_query, 10).map(
		func(r): return r["collider"]
	)
	var vs2 = vs.filter(
		func(t): return t is Commandable and Pattern.eval(weapon_patterns, t) != null
	)
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
		
		if commander:
			movement.set_avoidance_team(commander.id)

func _on_commander_changed(old_commander: Commander, new_commander: Commander) -> void:
	super(old_commander, new_commander)
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
	command_receiver.receive_damage(attacker, amount)
	if hp > 0 and command_receiver.is_idle() and attacker != null:
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
	params.collision_mask = CollisionLayers.Layer.BODY
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
	$HPBar.visible = hp < hpMax or selectable.is_selected()
	if hpBarFill.visible:
		hpBarFill.scale.x = hp / hpMax
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
			if attack_timer == ATTACK_DURATION:
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

func _on_velocity_computed(a_velocity: Vector3) -> void:
	velocity = a_velocity

	if velocity != Vector3.ZERO:
		if move_and_slide():
			var c := get_slide_collision_count()
			for i in range(c):
				var collision_collider = get_slide_collision(i).get_collider()
				if collision_collider is Commandable and collision_collider.is_in_group("unit") and collision_collider._command == null:
					if not (_command is Attack and _command.message.target == collision_collider):
						_command = null

func _update_state() -> void:
	if hp <= 0:
		_on_death()
		return

	if attack_timer > 0:
		attack_timer -= 1

	if command_receiver.is_idle():
		var aggro_cmd := get_aggro_near_position()
		if aggro_cmd != null:
			update_commands(aggro_cmd)

	command_receiver._update_state()

	# Per-tick production. No-op for non-producing entities.
	if production != null:
		production.tick()
	if ore_extractor != null:
		ore_extractor.tick()
	if dominion_generator != null:
		dominion_generator.tick()

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint(): return
	_update_state()

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

func _on_death() -> void:
	# Structure-flavored teardown.
	if is_in_group("structure"):
		if commander != null:
			commander.remove_structure(self)
			if resource_provider != null:
				resource_provider.remove_from(commander)
		map.remove_structure(self)
	super()
